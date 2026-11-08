extends Node

## One automatic save per Last Route run. The route saves itself at safe moments (a new level, a
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
## Beta world revisions require new runs. Each revision has its own directory and cloud slot; old records stay intact.
##
## Cloud: signed-in players also keep the record in their account (PUT/GET /api/v1/saves/CLOUD_GAME_ID/CLOUD_SLOT on the
## Godot backend, backend/game_saves.mjs). Every write marks the local copy unsynced until the server confirms it; offline
## or a failing server just leaves it owed for the next save or title visit. The newer copy wins.

signal changed

const FORMAT := 2
const WorldGenerationVersion = preload("res://game/config/world_generation_version.gd")
const NEW_RUN_REQUIRED := "WORLD GENERATION CHANGED // NEW RUN REQUIRED"
const PRESERVED_NOTICE := "NEWER SAVE PRESERVED // CLOUD SYNC PAUSED"
## Payload shape the route adopts (infinite_route_test LOCAL_SAVE_SCHEMA).
const PAYLOAD_SCHEMA := 1
const SAVE_SCHEMA := PAYLOAD_SCHEMA   # legacy name, kept for older callers
const DEFAULT_DIR := "user://route_saves"
const FILE_NAME := "run.json"
const LEGACY_EXTENSION := ".lrsave"
const CLOUD_GAME_ID := "last-route-godot"
const CLOUD_SLOT := "run"
## The write guards read a save file only to learn these two facts about it.
const _NEWER := 1     ## written by a newer build (format / save_schema / payload schema)
const _FOREIGN := 2   ## tagged with another world generation
## A file whose modified time (whole seconds) is this recent may still change again within the same second with the same
## length, so a stat match alone cannot vouch for it.
const _RACY_SECONDS := 3.0
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
## What the guards learned about each candidate save file, so an unchanged file is parsed at most once (see
## _unsupported_flags). path -> {mtime, length, flags, racy, bytes}. Purely a cache: dropping it only costs a re-parse.
var _scan_memo := {}
var _scan_dir := ""
var _cloud_request: HTTPRequest
var _cloud_operation := ""
var _resync := false
var _cloud_preservation_required := false


func _ready() -> void:
	_cloud_request = HTTPRequest.new()
	_cloud_request.name = "RunSaveCloud"
	add_child(_cloud_request)
	_cloud_request.request_completed.connect(_on_cloud_response)


func main_path() -> String:
	return generation_dir().path_join(FILE_NAME)


func generation_dir() -> String:
	return save_dir.path_join("world-%d" % WorldGenerationVersion.REVISION)


func _temp_path() -> String:
	return main_path() + ".tmp"


func _backup_path() -> String:
	return main_path() + ".bak"


func _sync_marker() -> String:
	return main_path() + ".unsynced"


func _cloud_preservation_marker() -> String:
	return main_path() + ".preserve-cloud"


func cloud_preserved() -> bool:
	return _cloud_preservation_required or FileAccess.file_exists(_cloud_preservation_marker()) \
		or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_cloud_preservation_marker()))


func _preservation_notice() -> String:
	return PRESERVED_NOTICE + (" // LOCAL GUARD NOT SAVED" \
		if _cloud_preservation_required and not _preservation_guard_saved() else "")


func _preservation_guard_saved() -> bool:
	return FileAccess.file_exists(_cloud_preservation_marker()) \
		and FileAccess.get_file_as_string(_cloud_preservation_marker()) == PRESERVED_NOTICE


## Writes the run. `place` is the player-facing spot ("LEVEL -2"); region names stay admin-only.
func write(payload: Dictionary, place: String) -> Dictionary:
	if not payload_valid(payload):
		return _failure("THE CURRENT ROUTE CANNOT BE SAVED")
	if not _preserve_unsupported():
		return _failure("UNSUPPORTED SAVE COULD NOT BE PRESERVED // SAVE NOT WRITTEN")
	var record := {
		"format": FORMAT,
		"world_generation": WorldGenerationVersion.REVISION,
		"saved_at": int(Time.get_unix_time_from_system()),
		"place": place.strip_edges().left(48),
		# The record is only encoded below and encoding never mutates or keeps its input, so sharing the caller's nested
		# data is safe and the deep copy is skipped (same bytes).
		"payload": _trim(payload, false),
	}
	var result := _write_record(record)
	if bool(result.get("ok", false)):
		_mark_unsynced("push")
		cloud_sync()
		changed.emit()
		if cloud_preserved():
			result["message"] = "RUN SAVED LOCALLY // " + _preservation_notice()
	return result


func _write_record(record: Dictionary) -> Dictionary:
	# All writers (autosave, recovery, legacy migration and cloud adoption) must
	# leave unsupported copies intact; reading an older build must not downgrade them.
	if _has_newer_local_record():
		return _failure("SAVED RUN IS FROM A NEWER BUILD")
	if _has_incompatible_generation():
		return _failure(NEW_RUN_REQUIRED)
	_ensure_directory()
	var text := JSON.stringify(JSON.from_native(record))
	# From here this class changes the files the memo describes. Keep what stays true across the swap: the old main file
	# becomes the backup (a rename keeps its content and stat), an untouched backup stays as it is.
	var had_main := FileAccess.file_exists(main_path())
	var carried: Dictionary = _memo_lookup(main_path() if had_main else _backup_path())
	_scan_memo.clear()
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
		_scan_memo.clear()
		return _failure("SAVE COULD NOT BE SWAPPED IN")
	_remember_written(record, text, carried)
	return {"ok": true, "message": "RUN SAVED", "place": String(record.get("place", ""))}


## The saved run, migrated to FORMAT: {ok, payload, place, saved_at} or {ok: false, message}.
func load_run() -> Dictionary:
	# Unsupported is not corrupt: recovery must not replace a newer build's save
	# with an older backup, or delete a complete newer-format interrupted write.
	if _has_newer_local_record():
		return _failure("SAVED RUN IS FROM A NEWER BUILD")
	if _has_incompatible_generation():
		return _failure(NEW_RUN_REQUIRED)
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
		if cloud_preserved():
			return _failure(_preservation_notice() + " // NEW RUN REQUIRED")
		if _has_other_generation():
			return _failure(NEW_RUN_REQUIRED)
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
		"status": status_line(String(result.get("place", "")), int(result.get("saved_at", 0))) \
			+ (" // " + _preservation_notice() if cloud_preserved() else "")}


static func status_line(place: String, saved_at: int) -> String:
	if saved_at <= 0:
		return "RUN NOT SAVED YET"
	var clock := Time.get_datetime_dict_from_unix_time(saved_at + _utc_offset_seconds())
	return "RUN SAVED AT %s, %02d:%02d" % [place if not place.is_empty() else "THE ROUTE",
		int(clock["hour"]), int(clock["minute"])]


static func _utc_offset_seconds() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


## Death clears the playable run. Unsupported records are archived first and
## their cloud slot is paused; neither a death nor a fresh beta run discards them.
func clear() -> void:
	_pending = {}
	_scan_memo.clear()
	if not _preserve_unsupported():
		changed.emit()
		return   # Never turn an archive failure into deletion or a cloud clear.
	for path in [main_path(), _temp_path(), _backup_path()]:
		if FileAccess.file_exists(path):
			var record := _read(path)
			if not record.is_empty() and not _generation_matches(record):
				continue   # even a misplaced old generation must never be deleted
		_remove(path)
	# the account copy must go too; until the server confirms, a pull can never bring the dead run back
	_mark_unsynced("clear")
	cloud_sync()
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


## a handoff successor rebuilds its route scene from the committed checkpoint (with its OWN runner) through
## the same pending slot CONTINUE uses. Nothing is written to disk here; the new host's autosaves start afterwards.
func queue_handoff(payload: Dictionary) -> bool:
	if not payload_valid(payload):
		return false
	_pending = {"ok": true, "payload": payload.duplicate(true), "handoff": true}
	return true


## Brings any record to FORMAT. Returns {"error": message} for what cannot be read.
func migrate(record: Dictionary) -> Dictionary:
	if record.is_empty():
		return {"error": "SAVED RUN IS DAMAGED"}
	if _newer_version(record):
		return {"error": "SAVED RUN IS FROM A NEWER BUILD"}
	if not _generation_matches(record):
		return {"error": NEW_RUN_REQUIRED}
	var format := int(record.get("format", 0))
	if format == 0 and int(record.get("save_schema", 0)) == 1:
		# format 1: a named slot from the old 9-slot SAVES page
		record = {"format": 2, "world_generation": WorldGenerationVersion.REVISION,
			"saved_at": int(record.get("saved_at", 0)),
			"place": _place_for(record.get("payload", {})), "payload": record.get("payload", {})}
		format = 2
	if format != FORMAT or not record.get("payload") is Dictionary:
		return {"error": "SAVED RUN IS DAMAGED"}
	var payload := _trim(record["payload"])
	if not payload_valid(payload):
		return {"error": "SAVED RUN IS DAMAGED"}
	record["payload"] = payload
	return record


func _newer_version(record: Dictionary) -> bool:
	if int(record.get("format", 0)) > FORMAT or int(record.get("save_schema", 0)) > 1:
		return true
	var payload = record.get("payload")
	return payload is Dictionary and int(payload.get("schema", 0)) > PAYLOAD_SCHEMA


func _has_newer_local_record() -> bool:
	for path in _scan_candidates():
		if _unsupported_flags(path) & _NEWER != 0:
			return true
	return false


## Every file that can hold a run for this generation: main, interrupted temp, backup and old named slots.
func _scan_candidates() -> Array[String]:
	var paths: Array[String] = [main_path(), _temp_path(), _backup_path()]
	var directory := DirAccess.open(generation_dir())
	if directory != null:
		for file_name in directory.get_files():
			if file_name.ends_with(LEGACY_EXTENSION):
				paths.append(generation_dir().path_join(file_name))
	return paths


func _flags_of(record: Dictionary) -> int:
	var flags := 0
	if _newer_version(record):
		flags |= _NEWER
	if not record.is_empty() and not _generation_matches(record):
		flags |= _FOREIGN
	return flags


## _NEWER / _FOREIGN for one candidate file (0 when it is missing, unreadable or supported). The file is parsed once and the
## answer is remembered against its (modified time, length); any change to the file, or a different save folder, makes the
## next call parse it again. A file modified within _RACY_SECONDS is never trusted on its stat alone: a file this class just
## wrote is verified byte for byte (see _memo_lookup), and an outside file that fresh is simply parsed every time, as before.
func _unsupported_flags(path: String) -> int:
	_scan_sync_dir()
	if not FileAccess.file_exists(path):
		_scan_memo.erase(path)
		return 0
	var entry := _memo_lookup(path)
	if not entry.is_empty():
		return int(entry["flags"])
	var before := _stat(path)
	var flags := _flags_of(_read(path))
	if int(before[0]) >= 0 and _stat(path) == before \
			and Time.get_unix_time_from_system() - float(before[0]) >= _RACY_SECONDS:
		_scan_memo[path] = _new_entry(before, flags)
	return flags


static func _new_entry(stat: Array, flags: int) -> Dictionary:
	return {"mtime": stat[0], "length": stat[1], "flags": flags, "racy": false, "bytes": PackedByteArray()}


## [modified time, length], or [-1, -1] when the file cannot be opened.
func _stat(path: String) -> Array:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return [-1, -1]
	var length := file.get_length()
	file.close()
	return [FileAccess.get_modified_time(path), length]


func _scan_sync_dir() -> void:
	var directory := generation_dir()
	if directory != _scan_dir:
		_scan_memo.clear()
		_scan_dir = directory


## The remembered entry for `path` when the file is still exactly what it described, else {} (and the entry is dropped).
func _memo_lookup(path: String) -> Dictionary:
	_scan_sync_dir()
	var entry: Dictionary = _scan_memo.get(path, {})
	if entry.is_empty():
		return {}
	var stat := _stat(path)
	if stat != [entry["mtime"], entry["length"]]:
		_scan_memo.erase(path)
		return {}
	if bool(entry["racy"]):
		if FileAccess.get_file_as_bytes(path) != entry["bytes"]:
			_scan_memo.erase(path)
			return {}
		if Time.get_unix_time_from_system() - float(stat[0]) >= _RACY_SECONDS:
			# Unchanged and now old enough that any later change must show in the stat.
			entry["racy"] = false
			entry["bytes"] = PackedByteArray()
	return entry


## After this class wrote `record` as `text` and swapped it in: main is known without parsing it. `carried` is the entry of the
## file that became (or stayed) the backup; it is kept only if the backup still matches its stat.
func _remember_written(record: Dictionary, text: String, carried: Dictionary) -> void:
	_scan_memo.clear()
	if not carried.is_empty():
		var backup_stat := _stat(_backup_path())
		if backup_stat == [carried["mtime"], carried["length"]]:
			_scan_memo[_backup_path()] = carried
	if _flags_of(record) != 0:
		return
	var main_stat := _stat(main_path())
	if int(main_stat[0]) < 0:
		return
	var entry := _new_entry(main_stat, 0)
	entry["racy"] = true
	entry["bytes"] = text.to_utf8_buffer()
	_scan_memo[main_path()] = entry


func _generation_matches(record: Dictionary) -> bool:
	return record.get("world_generation") == WorldGenerationVersion.REVISION


## A fresh beta run may proceed, but unsupported originals are recoverable and
## this generation's cloud slot stays paused until explicitly resolved. The marker
## is persistent: a restart or later death must not upload/delete over that slot.
func _pause_cloud_for_preservation() -> bool:
	var previous_notice := _preservation_notice() if cloud_preserved() else ""
	# Fail closed even when the disk cannot store the durable guard. A later sync
	# retries persistence; no PUT/DELETE is permitted while this latch is set.
	_cloud_preservation_required = true
	if _cloud_request != null and not _cloud_operation.is_empty():
		_cloud_request.cancel_request()
	_cloud_operation = ""
	_resync = false
	_ensure_directory()
	var marker := FileAccess.open(_cloud_preservation_marker(), FileAccess.WRITE)
	if marker == null:
		_emit_preservation_change(previous_notice)
		return false
	marker.store_string(PRESERVED_NOTICE)
	marker.flush()
	var error := marker.get_error()
	marker.close()
	if error != OK or FileAccess.get_file_as_string(_cloud_preservation_marker()) != PRESERVED_NOTICE:
		_emit_preservation_change(previous_notice)
		return false
	_emit_preservation_change(previous_notice)
	return true


func _emit_preservation_change(previous_notice: String) -> void:
	# Menu listeners may immediately retry sync. Publish only a real transition,
	# so an unchanged disk failure cannot recursively emit changed forever.
	if previous_notice != _preservation_notice():
		changed.emit()


func _preserve_unsupported() -> bool:
	var paths: Array[String] = []
	for path in _scan_candidates():
		if _unsupported_flags(path) != 0:
			paths.append(path)
	if paths.is_empty():
		return true
	_scan_memo.clear()   # the files below are about to be moved
	if not _pause_cloud_for_preservation():
		return false
	var root := generation_dir().path_join("preserved")
	if DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root)) != OK:
		return false
	var sequence := 1
	var archive := root.path_join("copy-%d" % sequence)
	while DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(archive)):
		sequence += 1
		archive = root.path_join("copy-%d" % sequence)
	if DirAccess.make_dir_absolute(ProjectSettings.globalize_path(archive)) != OK:
		return false
	for path in paths:
		var destination := archive.path_join(path.get_file())
		if FileAccess.file_exists(destination) or DirAccess.rename_absolute(ProjectSettings.globalize_path(path),
				ProjectSettings.globalize_path(destination)) != OK:
			return false
	_scan_memo.clear()
	return true


func _has_incompatible_generation() -> bool:
	for path in _scan_candidates():
		if _unsupported_flags(path) & _FOREIGN != 0:
			return true
	return false


## Old generations are diagnostic only. Never migrate, archive, clear or upload them.
func _has_other_generation() -> bool:
	var directory := DirAccess.open(save_dir)
	if directory == null:
		return false
	for file_name in directory.get_files():
		if file_name in [FILE_NAME, FILE_NAME + ".tmp", FILE_NAME + ".bak"] or file_name.ends_with(LEGACY_EXTENSION):
			return true
	for folder in directory.get_directories():
		if folder.begins_with("world-") and folder != generation_dir().get_file():
			var old_dir := DirAccess.open(save_dir.path_join(folder))
			if old_dir != null and not old_dir.get_files().is_empty():
				return true
	return false


func payload_valid(payload: Dictionary) -> bool:
	return int(payload.get("schema", 0)) == PAYLOAD_SCHEMA \
		and String(payload.get("kind", "")) == "infinite_route" \
		and not String(payload.get("seed_text", "")).is_empty() \
		and int(payload.get("run_seed", 0)) > 0 \
		and payload.get("world_state") is Dictionary \
		and payload.get("player") is Dictionary \
		and (payload["player"] as Dictionary).get("position") is Vector3


## `deep` false shares the nested data with `payload`: only for a result that is read (encoded), never changed or handed out.
func _trim(payload: Dictionary, deep := true) -> Dictionary:
	var out := payload.duplicate(deep)
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


## Only explicitly same-generation named slots may migrate. Untagged pre-revision
## slots in the root save directory remain untouched and require a new beta run.
func _migrate_legacy_slots() -> void:
	if _has_newer_local_record() or _has_incompatible_generation():
		return
	var directory := DirAccess.open(generation_dir())
	if directory == null:
		return
	var newest := {}
	var legacy_files: Array[String] = []
	for file_name in directory.get_files():
		if not file_name.ends_with(LEGACY_EXTENSION):
			continue
		legacy_files.append(file_name)
		var record := migrate(_read(generation_dir().path_join(file_name)))
		if not record.has("error") and int(record.get("saved_at", 0)) >= int(newest.get("saved_at", -1)):
			newest = record
	if legacy_files.is_empty():
		return
	if not newest.is_empty() and not FileAccess.file_exists(main_path()):
		if not bool(_write_record(newest).get("ok", false)):
			return
	_scan_memo.clear()   # the old slots are moved away below
	var archive := generation_dir().path_join("legacy")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(archive))
	for file_name in legacy_files:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(generation_dir().path_join(file_name)),
			ProjectSettings.globalize_path(archive.path_join(file_name)))


# --- cloud ------------------------------------------------------------------------------------------------------
# Nothing here ever reaches the player mid-run: offline, signed out, a 404 from an older server, a 5xx or a refused
# connection all leave the marker file in place ("push" or "clear") and the next save or title visit tries again.

func _cloud_ready() -> bool:
	return not cloud_disabled and _cloud_request != null and Backend.signed_in() \
		and Backend.accounts_available() and not Backend.offline_mode


func _cloud_path() -> String:
	return "/api/v1/saves/%s/%s-world-%d" % [CLOUD_GAME_ID, CLOUD_SLOT, WorldGenerationVersion.REVISION]


func _cloud_headers() -> PackedStringArray:
	var headers := Backend._headers()
	headers.append("X-Session-Token: %s" % Backend.account_session_token)
	return headers


## What the cloud owes: "push", "clear", "" (in sync), or "preserved" (paused
## while an unsupported copy is retained; never send an upload or deletion).
func pending_sync() -> String:
	if cloud_preserved():
		return "preserved"
	if not FileAccess.file_exists(_sync_marker()):
		return ""
	var value := FileAccess.get_file_as_string(_sync_marker()).strip_edges()
	return value if value in ["push", "clear"] else "push"


## Called on every save and every title visit: send what is owed, else pull the account's run when it is newer.
func cloud_sync() -> void:
	if cloud_preserved():
		if _cloud_preservation_required and not _preservation_guard_saved():
			_pause_cloud_for_preservation()
		return
	if _has_newer_local_record() or _has_incompatible_generation():
		_pause_cloud_for_preservation()
		return
	if not _cloud_ready():
		return
	if not _cloud_operation.is_empty():
		_resync = true   # a newer save landed while a request is out; send it once that one answers
		return
	var owed := pending_sync()
	var body := {}
	if owed == "clear":
		body = {"data": null, "updatedAt": int(Time.get_unix_time_from_system())}
	elif owed == "push":
		var local := migrate(_read(main_path()))
		if local.has("error"):
			_mark_unsynced("")
		else:
			body = {"data": JSON.from_native(local), "updatedAt": int(local.get("saved_at", 0))}
	if not body.is_empty():
		_cloud_operation = owed
		if _cloud_request.request(Backend._url(_cloud_path()), _cloud_headers(), HTTPClient.METHOD_PUT,
				JSON.stringify(body)) != OK:
			_cloud_operation = ""
		return
	_cloud_operation = "pull"
	if _cloud_request.request(Backend._url(_cloud_path()), _cloud_headers(), HTTPClient.METHOD_GET) != OK:
		_cloud_operation = ""


func _on_cloud_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var operation := _cloud_operation
	_cloud_operation = ""
	var resync := _resync
	_resync = false
	var reached := result == HTTPRequest.RESULT_SUCCESS
	if operation in ["push", "clear"]:
		if reached and code >= 200 and code < 300 and not resync and pending_sync() == operation:
			_mark_unsynced("")
		elif reached and code == 409 and operation == "push":
			# the account holds a newer run (another machine): drop our claim and let the pull decide
			_mark_unsynced("")
			resync = true
		# anything else (offline, 401, 404, 413, 429, 5xx) stays owed and is retried later
	elif operation == "pull" and reached and code >= 200 and code < 300:
		var data = Backend._parse_body(body).get("data")
		if data is Dictionary:
			adopt_cloud(JSON.to_native(data, false))
	if resync:
		cloud_sync()


## A cloud record replaces the local run only when it is newer, and never while a death's clear is still owed.
func adopt_cloud(value) -> bool:
	if not value is Dictionary:
		return false
	# A pull may complete after local death queued a clear. Inspect the remote
	# version FIRST, or the response's resync would delete an unsupported cloud run.
	if _newer_version(value) or not _generation_matches(value):
		_pause_cloud_for_preservation()
		return false
	if cloud_preserved() or pending_sync() == "clear" or _has_newer_local_record() or _has_incompatible_generation():
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


func _mark_unsynced(owed: String) -> void:
	if cloud_preserved():
		return
	if owed.is_empty():
		_remove(_sync_marker())
		return
	_ensure_directory()
	var marker := FileAccess.open(_sync_marker(), FileAccess.WRITE)
	if marker != null:
		marker.store_string(owed)
		marker.close()


func _remove(path: String) -> void:
	_scan_memo.erase(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _ensure_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(generation_dir()))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
