extends Node

## Local named Infinite Route archives. The payload is stored as a Godot
## Variant rather than JSON so Vector2/3, Vector*i and PackedByteArray map data
## survive a restart without lossy string conversion.

const SAVE_SCHEMA := 1
const SAVE_DIR := "user://route_saves"
const SAVE_EXTENSION := ".lrsave"
const MAX_NAME_LENGTH := 40

var _pending_slot_id := ""


func list_slots() -> Array:
	_ensure_directory()
	var result := []
	var directory := DirAccess.open(SAVE_DIR)
	if directory == null:
		return result
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.ends_with(SAVE_EXTENSION):
			var record := _read_record(SAVE_DIR.path_join(filename))
			if _record_valid(record):
				result.append(_summary(record))
		filename = directory.get_next()
	directory.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("saved_at", 0)) > int(b.get("saved_at", 0)))
	return result


func save_new(display_name: String, payload: Dictionary) -> Dictionary:
	var canonical := _valid_name(display_name)
	if canonical.is_empty():
		return _failure("ENTER A SAVE NAME")
	if not _payload_valid(payload):
		return _failure("THE CURRENT ROUTE CANNOT BE ARCHIVED")
	var slot_id := _new_slot_id()
	var record := {
		"save_schema": SAVE_SCHEMA,
		"slot_id": slot_id,
		"name": canonical,
		"created_at": int(Time.get_unix_time_from_system()),
		"saved_at": int(Time.get_unix_time_from_system()),
		"payload": payload.duplicate(true),
	}
	return _write_record(record)


func overwrite(slot_id: String, payload: Dictionary) -> Dictionary:
	var record := _read_slot(slot_id)
	if not _record_valid(record):
		return _failure("SAVE SLOT NOT FOUND")
	if not _payload_valid(payload):
		return _failure("THE CURRENT ROUTE CANNOT BE ARCHIVED")
	record["saved_at"] = int(Time.get_unix_time_from_system())
	record["payload"] = payload.duplicate(true)
	return _write_record(record)


func rename_slot(slot_id: String, display_name: String) -> Dictionary:
	var record := _read_slot(slot_id)
	var canonical := _valid_name(display_name)
	if not _record_valid(record):
		return _failure("SAVE SLOT NOT FOUND")
	if canonical.is_empty():
		return _failure("ENTER A SAVE NAME")
	record["name"] = canonical
	record["saved_at"] = int(Time.get_unix_time_from_system())
	return _write_record(record)


func delete_slot(slot_id: String) -> Dictionary:
	var path := _slot_path(slot_id)
	if path.is_empty() or not FileAccess.file_exists(path):
		return _failure("SAVE SLOT NOT FOUND")
	var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if error != OK:
		return _failure("SAVE SLOT COULD NOT BE DELETED")
	if _pending_slot_id == slot_id:
		_pending_slot_id = ""
	return {"ok": true, "message": "SAVE DELETED", "slot_id": slot_id}


func load_slot(slot_id: String) -> Dictionary:
	var record := _read_slot(slot_id)
	if not _record_valid(record):
		return _failure("SAVE SLOT IS MISSING OR INVALID")
	return {"ok": true, "message": "SAVE READY", "slot_id": slot_id,
		"name": String(record.get("name", "ROUTE")),
		"payload": (record.get("payload", {}) as Dictionary).duplicate(true)}


func queue_load(slot_id: String) -> Dictionary:
	var result := load_slot(slot_id)
	if bool(result.get("ok", false)):
		_pending_slot_id = slot_id
	return result


func consume_pending() -> Dictionary:
	if _pending_slot_id.is_empty():
		return {}
	var slot_id := _pending_slot_id
	_pending_slot_id = ""
	return load_slot(slot_id)


func clear_pending() -> void:
	_pending_slot_id = ""


func _write_record(record: Dictionary) -> Dictionary:
	_ensure_directory()
	var slot_id := String(record.get("slot_id", ""))
	var path := _slot_path(slot_id)
	if path.is_empty():
		return _failure("SAVE SLOT ID IS INVALID")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("SAVE DIRECTORY IS NOT WRITABLE")
	file.store_var(record, false)
	file.flush()
	file.close()
	return {"ok": true, "message": "ROUTE SAVED", "slot_id": slot_id,
		"name": String(record.get("name", "ROUTE"))}


func _read_slot(slot_id: String) -> Dictionary:
	var path := _slot_path(slot_id)
	return _read_record(path) if not path.is_empty() else {}


func _read_record(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var value = file.get_var(false)
	file.close()
	return value if value is Dictionary else {}


func _record_valid(record: Dictionary) -> bool:
	return int(record.get("save_schema", 0)) == SAVE_SCHEMA \
		and _valid_slot_id(String(record.get("slot_id", ""))) \
		and not _valid_name(String(record.get("name", ""))).is_empty() \
		and record.get("payload") is Dictionary \
		and _payload_valid(record.get("payload", {}))


func _payload_valid(payload: Dictionary) -> bool:
	return int(payload.get("schema", 0)) == SAVE_SCHEMA \
		and String(payload.get("kind", "")) == "infinite_route" \
		and not String(payload.get("seed_text", "")).is_empty() \
		and int(payload.get("run_seed", 0)) > 0 \
		and payload.get("world_state") is Dictionary \
		and payload.get("player") is Dictionary


func _summary(record: Dictionary) -> Dictionary:
	var payload: Dictionary = record.get("payload", {})
	var statistics: Dictionary = payload.get("statistics", {})
	return {
		"slot_id": String(record.get("slot_id", "")),
		"name": String(record.get("name", "ROUTE")),
		"saved_at": int(record.get("saved_at", 0)),
		"difficulty": String(payload.get("difficulty_id", "standard")).to_upper(),
		"level": int((payload.get("player", {}) as Dictionary).get("level", 0)),
		"relays": int(statistics.get("relays_collected", 0)),
		"elapsed_seconds": float(statistics.get("elapsed_seconds", 0.0)),
	}


func _valid_name(value: String) -> String:
	var canonical := value.strip_edges()
	canonical = canonical.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	while canonical.contains("  "):
		canonical = canonical.replace("  ", " ")
	return canonical.left(MAX_NAME_LENGTH)


func _new_slot_id() -> String:
	var base := "%d-%d" % [Time.get_unix_time_from_system(), randi()]
	return base.sha256_text().left(20)


func _slot_path(slot_id: String) -> String:
	return SAVE_DIR.path_join(slot_id + SAVE_EXTENSION) if _valid_slot_id(slot_id) else ""


func _valid_slot_id(value: String) -> bool:
	if value.length() != 20:
		return false
	for character in value:
		if character not in "0123456789abcdef":
			return false
	return true


func _ensure_directory() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))


func _failure(message: String) -> Dictionary:
	return {"ok": false, "message": message}
