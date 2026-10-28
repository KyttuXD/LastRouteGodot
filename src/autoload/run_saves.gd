extends Node

## One automatic save per Last Route run (KT, 2026-10-28). The route saves itself at safe moments (a new level, a
## checkpoint, a relay, quitting from the pause menu); the title screen's CONTINUE resumes it; death clears it.
##
## Seed-based: the record keeps the route seed, level, player (position, inventory, stamina, flashlight), relays and
## pickups taken, run time and discoveries. Hunters and everything else regenerate from the seed.
##
## Never lose progress: the record is written to run.json.tmp, the current run.json becomes run.json.bak, then the temp
## file is renamed into place. A load tries run.json, then a complete leftover temp file, then the backup.
##
## Version-safe: every record carries FORMAT and goes through migrate() on load. Anything unreadable comes back as
## {ok: false, message} for the title screen to show, never a crash or a half-built run.
##
## Cloud: signed-in players also keep the record in their account (/api/v1/saves/CLOUD_GAME_ID/CLOUD_SLOT). Offline
## writes mark the local copy unsynced; it is pushed on the next save or title visit. The newer copy wins on pull.

signal changed

const FORMAT := 2
## Payload shape the route adopts (infinite_route_test LOCAL_SAVE_SCHEMA).
const PAYLOAD_SCHEMA := 1
const SAVE_SCHEMA := PAYLOAD_SCHEMA   # legacy name, kept for older callers
const DEFAULT_DIR := "user://route_saves"
const FILE_NAME := "run.json"
const LEGACY_EXTENSION := ".lrsave"
const CLOUD_GAME_ID := "last-route-godot"
const CLOUD_SLOT := "run"
## World state kept in a save: what the seed cannot regenerate. Live hunters, doors, lights and rides are rebuilt.
const WORLD_KEYS := ["schema", "active_checkpoint", "claimed_pickups", "sabotaged_relays", "safe_rooms",
	"dropped_items", "next_drop_sequence", "waypoints"]

## Tests point the store at a scratch folder.
var save_dir := DEFAULT_DIR
## Test hook: stop a write after the temp file is written, as if the game was killed mid-save.
var interrupt_before_swap := false
## Test hook: never talk to the account server.
var cloud_disabled := false

var _pending := {}
var _cloud_request: HTTPRequest
var _cloud_operation := ""


func _ready() -> void:
	_cloud_request = HTTPRequest.new()
	_cloud_request.name = "RunSaveCloud"
	add_child(_cloud_request)
	_cloud_request.request_completed.connect(_on_cloud_response)


func main_path() -> String:
	return save_dir.path_join(FILE_NAME)


func _temp_path() -> String:
	return main_path() + ".tmp"


func _backup_path() -> String:
	return main_path() + ".bak"


func _sync_marker() -> String:
	return main_path() + ".unsynced"


## Writes the run. `place` is the player-facing spot ("LEVEL -2"); region names stay admin-only.
func write(payload: Dictionary, place: String) -> Dictionary:
	if not payload_valid(payload):
		return _failure("THE CURRENT ROUTE CANNOT BE SAVED")
	var record := {
		"format": FORMAT,
		"saved_at": int(Time.get_unix_time_from_system()),
		"place": place.strip_edges().left(48),
		"payload": _trim(payload),
	}
	var result := _write_record(record)
	if bool(result.get("ok", false)):
		_mark_unsynced(true)
		_cloud_push(record)
		changed.emit()
	return result


func _write_record(record: Dictionary) -> Dictionary:
	_ensure_directory()
	var text := JSON.stringify(JSON.from_native(record))
	var temp := FileAccess.open(_temp_path(), FileAccess.WRITE)
	if temp == null:
		return _failure("SAVE FOLDER IS NOT WRITABLE")
	temp.store_string(text)
	temp.flush()
	temp.close()
	if interrupt_before_swap:
		return _failure("SAVE INTERRUPTED")
	var main := ProjectSettings.globalize_path(main_path())
	var backup := ProjectSettings.globalize_path(_backup_path())
	if FileAccess.file_exists(main_path()):
		if FileAccess.file_exists(_backup_path()):
			DirAccess.remove_absolute(backup)
		if DirAccess.rename_absolute(main, backup) != OK:
			return _failure("SAVE COULD NOT KEEP A BACKUP")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(_temp_path()), main) != OK:
		return _failure("SAVE COULD NOT BE SWAPPED IN")
	return {"ok": true, "message": "RUN SAVED", "place": String(record.get("place", ""))}


## The saved run, migrated to FORMAT: {ok, payload, place, saved_at} or {ok: false, message}.
func load_run() -> Dictionary:
	_migrate_legacy_slots()
	var found_any := false
	var best := {}
	var best_path := ""
	# the main file, or a complete temp file a killed write left behind (whichever is newer), else the backup
	for path in [main_path(), _temp_path(), _backup_path()]:
		if not FileAccess.file_exists(path):
			continue
		found_any = true
		if path == _backup_path() and not best.is_empty():
			break
		var record := migrate(_read(path))
		if not record.has("error") and int(record.get("saved_at", 0)) >= int(best.get("saved_at", -1)):
			best = record
			best_path = path
	if not best.is_empty():
		if best_path != main_path():
			_write_record(best)   # promote the surviving copy; the damaged one becomes the backup
		_remove(_temp_path())
		return {"ok": true, "message": "RUN READY", "payload": best["payload"],
			"place": String(best.get("place", "")), "saved_at": int(best.get("saved_at", 0))}
	if not found_any:
		return _failure("NO SAVED RUN")
	var newest := migrate(_read(main_path()))
	return _failure(String(newest.get("error", "SAVED RUN COULD NOT BE READ")) + " // START A NEW RUN")


func has_run() -> bool:
	return bool(load_run().get("ok", false))


## Title-screen line: "LEVEL -2 // 14:05" or the reason the save cannot load ("" when there is none).
func summary() -> Dictionary:
	var result := load_run()
	if not bool(result.get("ok", false)):
		var message := String(result.get("message", ""))
		return {"ok": false, "message": "" if message == "NO SAVED RUN" else message}
	var payload: Dictionary = result["payload"]
	var stats: Dictionary = payload.get("statistics", {}) if payload.get("statistics") is Dictionary else {}
	return {"ok": true, "place": String(result.get("place", "")), "saved_at": int(result.get("saved_at", 0)),
		"difficulty": String(payload.get("difficulty_id", "standard")).to_upper(),
		"elapsed_seconds": float(stats.get("elapsed_seconds", 0.0)),
		"status": status_line(String(result.get("place", "")), int(result.get("saved_at", 0)))}


static func status_line(place: String, saved_at: int) -> String:
	if saved_at <= 0:
		return "RUN NOT SAVED YET"
	var clock := Time.get_datetime_dict_from_unix_time(saved_at + _utc_offset_seconds())
	return "RUN SAVED AT %s, %02d:%02d" % [place if not place.is_empty() else "THE ROUTE",
		int(clock["hour"]), int(clock["minute"])]


static func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## Death, or a run that should not resume: the local copy, its backup and the cloud copy all go.
func clear() -> void:
	_pending = {}
	for path in [main_path(), _temp_path(), _backup_path()]:
		_remove(path)
	_mark_unsynced(false)
	_cloud_send({"sessionToken": Backend.account_session_token, "data": null})
	changed.emit()


func queue_continue() -> Dictionary:
	var result := load_run()
	_pending = result if bool(result.get("ok", false)) else {}
	return result


func consume_pending() -> Dictionary:
	var value := _pending
	_pending = {}
	return value


func clear_pending() -> void:
	_pending = {}


## Brings any record to FORMAT. Returns {"error": message} for what cannot be read.
func migrate(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {"error": "SAVED RUN IS DAMAGED"}
	var format := int(record.get("format", 0))
	if format == 0 and int(record.get("save_schema", 0)) == 1:
		# format 1: a named slot from the old 9-slot SAVES page
		record = {"format": 2, "saved_at": int(record.get("saved_at", 0)),
			"place": _place_for(record.get("payload", {})), "payload": record.get("payload", {})}
		format = 2
	if format > FORMAT:
		return {"error": "SAVED RUN IS FROM A NEWER BUILD"}
	if format != FORMAT or not record.get("payload") is Dictionary:
		return {"error": "SAVED RUN IS DAMAGED"}
	var payload := _trim(record["payload"])
	if not payload_valid(payload):
		return {"error": "SAVED RUN IS DAMAGED"}
	record["payload"] = payload
	return record


func payload_valid(payload: Dictionary) -> bool:
	return int(payload.get("schema", 0)) == PAYLOAD_SCHEMA \
		and String(payload.get("kind", "")) == "infinite_route" \
		and not String(payload.get("seed_text", "")).is_empty() \
		and int(payload.get("run_seed", 0)) > 0 \
		and payload.get("world_state") is Dictionary \
		and payload.get("player") is Dictionary \
		and (payload["player"] as Dictionary).get("position") is Vector3


func _trim(payload: Dictionary) -> Dictionary:
	var out := payload.duplicate(true)
	out.erase("anti_idle")
	if out.get("world_state") is Dictionary:
		var world := {}
		for key in WORLD_KEYS:
			if (out["world_state"] as Dictionary).has(key):
				world[key] = out["world_state"][key]
		out["world_state"] = world
	return out


func _place_for(payload) -> String:
	var player = (payload as Dictionary).get("player", {}) if payload is Dictionary else {}
	return "LEVEL %+d" % int((player as Dictionary).get("level", 0)) if player is Dictionary else ""


func _read(path: String) -> Dictionary:
	if path.ends_with(LEGACY_EXTENSION):
		var legacy := FileAccess.open(path, FileAccess.READ)
		if legacy == null:
			return {}
		var value = legacy.get_var(false)
		return value if value is Dictionary else {}
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var native = JSON.to_native(json.data, false)
	return native if native is Dictionary else {}


## One-time: the newest named slot from the old SAVES page becomes the run; the old files move to legacy/.
func _migrate_legacy_slots() -> void:
	var directory := DirAccess.open(save_dir)
	if directory == null:
		return
	var newest := {}
	var legacy_files: Array[String] = []
	for file_name in directory.get_files():
		if not file_name.ends_with(LEGACY_EXTENSION):
			continue
		legacy_files.append(file_name)
		var record := migrate(_read(save_dir.path_join(file_name)))
		if not record.has("error") and int(record.get("saved_at", 0)) >= int(newest.get("saved_at", -1)):
			newest = record
	if legacy_files.is_empty():
		return
	if not newest.is_empty() and not FileAccess.file_exists(main_path()):
		if not bool(_write_record(newest).get("ok", false)):
			return
	var archive := save_dir.path_join("legacy")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(archive))
	for file_name in legacy_files:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(save_dir.path_join(file_name)),
			ProjectSettings.globalize_path(archive.path_join(file_name)))


# --- cloud ------------------------------------------------------------------------------------------------------

func _cloud_ready() -> bool:
	return not cloud_disabled and _cloud_request != null and Backend.signed_in() \
		and Backend.accounts_available() and not Backend.offline_mode


func _cloud_path() -> String:
	return "/api/v1/saves/%s/%s" % [CLOUD_GAME_ID, CLOUD_SLOT]


func _cloud_push(record: Dictionary) -> void:
	_cloud_send({"sessionToken": Backend.account_session_token, "data": JSON.from_native(record)})


func _cloud_send(body: Dictionary) -> void:
	if not _cloud_ready() or not _cloud_operation.is_empty():
		return
	_cloud_operation = "push"
	if _cloud_request.request(Backend._url(_cloud_path()), Backend._headers(), HTTPClient.METHOD_POST,
			JSON.stringify(body)) != OK:
		_cloud_operation = ""


## Title screen: push an unsynced local run, or pull the account's run when it is newer than the local one.
func cloud_sync() -> void:
	if not _cloud_ready() or not _cloud_operation.is_empty():
		return
	if FileAccess.file_exists(_sync_marker()):
		var local := migrate(_read(main_path()))
		if not local.has("error"):
			_cloud_push(local)
			return
	_cloud_operation = "pull"
	var headers := Backend._headers()
	headers.append("X-Session-Token: %s" % Backend.account_session_token)
	if _cloud_request.request(Backend._url(_cloud_path()), headers, HTTPClient.METHOD_GET) != OK:
		_cloud_operation = ""


func _on_cloud_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _cloud_operation
	_cloud_operation = ""
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		return
	if operation == "push":
		_mark_unsynced(false)
		return
	var data = Backend._parse_body(body).get("data")
	if data is Dictionary:
		adopt_cloud(JSON.to_native(data, false))


## A cloud record replaces the local run only when it is newer.
func adopt_cloud(value) -> bool:
	if not value is Dictionary:
		return false
	var record := migrate(value)
	if record.has("error"):
		return false
	var local := migrate(_read(main_path()))
	if not local.has("error") and int(local.get("saved_at", 0)) >= int(record.get("saved_at", 0)):
		return false
	if not bool(_write_record(record).get("ok", false)):
		return false
	changed.emit()
	return true


func _mark_unsynced(on: bool) -> void:
	if on:
		_ensure_directory()
		var marker := FileAccess.open(_sync_marker(), FileAccess.WRITE)
		if marker != null:
			marker.close()
	else:
		_remove(_sync_marker())


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _ensure_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_dir))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
