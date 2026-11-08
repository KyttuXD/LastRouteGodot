extends Node

## Two-process content-pack handshake over real ENet (docs/DATA_DRIVEN_CONTENT.md, "Rooms"). The host opens a private
## room with one pack enabled; a guest that has the same pack adopts it and ends on the host's pack hash, and a guest
## without it leaves before generating anything, with the pack named in its status.
##
##   godot4 --headless --path . res://tests/scenes/pack_smoke.tscn -- host  match|missing
##   godot4 --headless --path . res://tests/scenes/pack_smoke.tscn -- client match|missing
## tools/build/pack_smoke.sh runs both pairs.
##
## Live end-to-end (real index server and file host; the pack must be published):
##   godot4 --headless --path . res://tests/scenes/pack_smoke.tscn -- host  download <pack dir>
##   godot4 --headless --path . res://tests/scenes/pack_smoke.tscn -- client download [host address]
## The host loads <pack dir> (e.g. examples/mods/ember); the guest starts with no packs, and a stand-in for the lobby's
## ModJoinDialog (auto-download on) fetches them through the real provider before RoomState lets it start.

const PORT := 18431
const TIMEOUT_SECONDS := 12.0
const PACK := "smokepack"
const PRINTER := "res://assets/props/maze/office_printer.glb"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	if args.size() < 2 or not ["host", "client"].has(args[0]) or not ["match", "missing", "download"].has(args[1]):
		_finish(false, "usage: pack_smoke.tscn -- host|client match|missing|download [pack dir]")
		return
	# the live guest needs the real pack index; nothing else here talks to the backend, and the host never lists itself
	if args[0] == "host" or args[1] != "download":
		Backend.suppress_requests_for_tests()
	RoomState.suppress_scene_transitions_for_tests()
	# both processes share user://, so each side keeps its packs in its own folder
	RoomPacks.mods_root = "user://pack_smoke_%s" % args[0]
	_wipe(RoomPacks.mods_root)
	if args[0] == "host" and args[1] == "download":
		if args.size() < 3:
			_finish(false, "the live host needs the pack folder to serve")
			return
		_copy_tree(args[2], RoomPacks.mods_root.path_join(args[2].trim_suffix("/").get_file()))
		_pack = args[2].trim_suffix("/").get_file()
	elif args[0] == "host" or args[1] == "match":
		_make_pack(RoomPacks.mods_root.path_join(PACK))
	if args[0] == "host":
		await _run_host()
	else:
		if args[1] == "download":
			await _run_live_client(args[2] if args.size() > 2 else RoomState.DEFAULT_ADDRESS)
		else:
			await _run_client(args[1] == "match")


var _pack := PACK


## Stands in for the lobby's ModJoinDialog with auto-download on: fetch every pack through ModPackApi's provider.
class AutoJoin extends Control:
	signal join_allowed
	signal cancelled
	var result := ""

	func begin(host_packs: Array, _private_room: bool = true) -> void:
		var provider = load("res://game/mods/mod_pack_api.gd").provider
		if provider == null:
			result = "no mod provider installed"
			cancelled.emit()
			return
		provider.download_packs(host_packs, func(done: int, total: int, name: String):
			print("PACK CLIENT DOWNLOAD // %s %d/%d" % [name, done, total]),
			func(ok: bool, reason: String):
				result = "ok" if ok else reason
				print("PACK CLIENT DOWNLOAD %s" % ("OK" if ok else "FAILED // " + reason))
				if ok:
					join_allowed.emit()
				else:
					# a refused download returns RoomState to staging, which replaces this scene: report and stop here
					print("PACK SMOKE FAIL // download refused: %s" % reason)
					get_tree().quit(1))


func _run_live_client(address: String) -> void:
	var dialog := AutoJoin.new()
	dialog.name = "ModJoinDialog"
	get_tree().root.add_child(dialog)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var error := RoomState.join_room(address, PORT)
	if not error.is_empty():
		_finish(false, error)
		return
	if not await _wait_for(func() -> bool: return RoomState.session_active and RoomState._packs_waiting.is_empty() \
			and not ContentRegistry.loaded_packs().is_empty(), 60.0):
		_finish(false, "guest never started with the host's packs: %s // %s" % [dialog.result, RoomState.status_message])
		return
	var pack: Dictionary = ContentRegistry.loaded_packs()[0]
	_finish(String(pack["dir"]).contains("/.cache/"), "PACK CLIENT DOWNLOAD OK // downloaded, verified and adopted %s %s // sha %s // hash %s"
		% [pack["id"], pack["version"], pack["sha256"], ContentRegistry.pack_hash().substr(0, 12)])


func _run_host() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	Settings.mods_enabled = [_pack]
	var error := RoomState.host_room(PORT)
	if not error.is_empty() or ContentRegistry.loaded_packs().size() != 1:
		_finish(false, "host room did not open with its pack: %s %s" % [error, RoomState.status_message])
		return
	print("PACK HOST OK // %s loaded // sha %s // hash %s" % [_pack, ContentRegistry.loaded_packs()[0]["sha256"],
		ContentRegistry.pack_hash().substr(0, 12)])
	if not await _wait_for(func() -> bool: return RoomState.roster().size() == 2):
		_finish(false, "no guest joined")
		return
	# a guest without the pack leaves on its own; one with it stays until told to start
	await get_tree().create_timer(1.5).timeout
	if RoomState.roster().size() == 2:
		RoomState._receive_start.rpc(RoomState.code, RoomState.seed_text, RoomState.mode, RoomState.map_scale,
			RoomState.difficulty)
		print("PACK HOST START OK")
	# a live guest may still be downloading when the start goes out; it leaves once it has started with the packs
	await _wait_for(func() -> bool: return RoomState.roster().size() == 1, 90.0)
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


func _wait_for(condition: Callable, seconds: float = TIMEOUT_SECONDS) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
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


func _copy_tree(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for name in DirAccess.get_files_at(from):
		if not String(name).begins_with("."):
			_write(to.path_join(name), FileAccess.get_file_as_bytes(from.path_join(name)))
	for name in DirAccess.get_directories_at(from):
		_copy_tree(from.path_join(name), to.path_join(name))


func _write(path: String, content) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if content is PackedByteArray:
		file.store_buffer(content)
	else:
		file.store_string(String(content))
	file.close()


## Delete `dir` and everything in it. Only test folders (their name carries "pack_smoke_") are ever touched, and the walk
## uses absolute paths (ContentPacks.os_path) so a user data dir containing "//" cannot point it at the project.
func _wipe(dir: String) -> void:
	var path := ContentPacks.os_path(dir)
	if not path.contains("pack_smoke_") or not DirAccess.dir_exists_absolute(path):
		return
	_remove_tree(path)


func _remove_tree(path: String) -> void:
	var access := DirAccess.open(path)
	if access == null:
		return
	access.include_hidden = true
	for name in access.get_files():
		DirAccess.remove_absolute(path.path_join(name))
	for name in access.get_directories():
		if access.is_link(name):
			DirAccess.remove_absolute(path.path_join(name))
		else:
			_remove_tree(path.path_join(name))
	DirAccess.remove_absolute(path)
