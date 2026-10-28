extends Node

## Two-process content-pack handshake over real ENet (docs/DATA_DRIVEN_CONTENT.md, "Rooms"). The host opens a private
## room with one pack enabled; a guest that has the same pack adopts it and ends on the host's pack hash, and a guest
## without it leaves before generating anything, with the pack named in its status.
##
##   godot4 --headless --path . res://scenes/pack_smoke.tscn -- host  match|missing
##   godot4 --headless --path . res://scenes/pack_smoke.tscn -- client match|missing
## scripts/pack_smoke.sh runs both pairs.

const PORT := 18431
const TIMEOUT_SECONDS := 12.0
const PACK := "smokepack"
const PRINTER := "res://art/props-3d/props/maze/office_printer.glb"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not ["host", "client"].has(args[0]) or not ["match", "missing"].has(args[1]):
		_finish(false, "usage: pack_smoke.tscn -- host|client match|missing")
		return
	Backend.suppress_requests_for_tests()
	RoomState.suppress_scene_transitions_for_tests()
	# both processes share user://, so each side keeps its packs in its own folder
	RoomPacks.mods_root = "user://pack_smoke_%s" % args[0]
	_wipe(RoomPacks.mods_root)
	if args[0] == "host" or args[1] == "match":
		_make_pack(RoomPacks.mods_root.path_join(PACK))
	if args[0] == "host":
		await _run_host()
	else:
		await _run_client(args[1] == "match")


func _run_host() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	Settings.mods_enabled = [PACK]
	var error := RoomState.host_room(PORT)
	if not error.is_empty() or ContentRegistry.loaded_packs().size() != 1:
		_finish(false, "host room did not open with its pack: %s %s" % [error, RoomState.status_message])
		return
	print("PACK HOST OK // %s loaded // hash %s" % [PACK, ContentRegistry.pack_hash().substr(0, 12)])
	if not await _wait_for(func() -> bool: return RoomState.roster().size() == 2):
		_finish(false, "no guest joined")
		return
	# a guest without the pack leaves on its own; one with it stays until told to start
	await get_tree().create_timer(1.5).timeout
	if RoomState.roster().size() == 2:
		RoomState._receive_start.rpc(RoomState.code, RoomState.seed_text, RoomState.mode, RoomState.map_scale,
			RoomState.difficulty)
		print("PACK HOST START OK")
	await _wait_for(func() -> bool: return RoomState.roster().size() == 1)
	_finish(true, "PACK HOST DONE")


func _run_client(has_pack: bool) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var error := RoomState.join_room(RoomState.DEFAULT_ADDRESS, PORT)
	if not error.is_empty():
		_finish(false, error)
		return
	if has_pack:
		if not await _wait_for(func() -> bool: return RoomState.session_active):
			_finish(false, "guest never started: %s" % RoomState.status_message)
			return
		var loaded := ContentRegistry.loaded_packs()
		if loaded.size() != 1 or loaded[0]["id"] != PACK or not HunterRoster.PROFILES.has("%s_ember" % PACK):
			_finish(false, "guest started without the host's pack")
			return
		print("PACK CLIENT MATCH OK // adopted %s // hash %s" % [PACK, ContentRegistry.pack_hash().substr(0, 12)])
		RoomState.leave_network()
		_finish(ContentRegistry.loaded_packs().is_empty(), "PACK CLIENT LEAVE OK // back to vanilla")
		return
	if not await _wait_for(func() -> bool: return RoomState.status_message.begins_with("MODS DIFFER")):
		_finish(false, "guest without the pack was not refused: %s" % RoomState.status_message)
		return
	if RoomState.online or RoomState.session_active or not ContentRegistry.loaded_packs().is_empty():
		_finish(false, "refused guest stayed in the room or kept packs")
		return
	_finish(RoomState.status_message.contains(PACK.to_upper()), "PACK CLIENT MISSING OK // %s" % RoomState.status_message)


func _wait_for(condition: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + int(TIMEOUT_SECONDS * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if condition.call():
			return true
		await get_tree().process_frame
	return false


func _finish(ok: bool, message: String) -> void:
	print(message if ok else "PACK SMOKE FAIL // " + message)
	RoomState.leave_network()
	_wipe(RoomPacks.mods_root)
	get_tree().quit(0 if ok else 1)


func _make_pack(dir: String) -> void:
	_write(dir.path_join("pack.json"), JSON.stringify({"schema": "lr.pack/1", "id": PACK, "name": PACK,
		"version": "1.0.0"}))
	_write(dir.path_join("hunters/ember.json"), JSON.stringify({"schema": "lr.hunter/1", "id": "%s_ember" % PACK,
		"name": "Ember", "tier": "easy", "speed": 0.8, "chase": 3.5, "prog": 0.18, "sight": 8.0, "hearing": 1.0,
		"spawn": 12}))
	_write(dir.path_join("props/lamp.json"), JSON.stringify({"schema": "lr.prop/1", "family": "lamps",
		"props": [{"id": "%s_lamp" % PACK, "models": ["assets/lamp.glb"]}]}))
	_write(dir.path_join("assets/lamp.glb"), FileAccess.get_file_as_bytes(PRINTER))


func _write(path: String, content) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if content is PackedByteArray:
		file.store_buffer(content)
	else:
		file.store_string(String(content))
	file.close()


func _wipe(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for name in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(name))
	for name in DirAccess.get_directories_at(dir):
		_wipe(dir.path_join(name))
	DirAccess.remove_absolute(dir)
