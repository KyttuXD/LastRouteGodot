extends RefCounted

## One automatic save per Last Route run (RunSaves): the route saves at a new level, a checkpoint, a relay and on quit;
## CONTINUE resumes it; an old 9-slot save migrates; a corrupt file or an interrupted write never loses the run or
## crashes; death clears it on every difficulty; a co-op guest never saves. Runs against a scratch save folder.
##
##   godot --headless --path . res://scenes/validate.tscn -- saves

const SCRATCH := "user://validate_saves_scratch"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _frames(host: Node, count: int = 4) -> void:
	for _i in count:
		await host.get_tree().process_frame


func _payload(level: int = -1, elapsed: float = 60.0) -> Dictionary:
	return {
		"schema": RunSaves.PAYLOAD_SCHEMA,
		"kind": "infinite_route",
		"seed_text": "VALIDATION-SAVE-SEED",
		"run_seed": 987654,
		"difficulty": RoomState.Difficulty.STANDARD,
		"difficulty_id": "standard",
		"world_state": StreamedWorldState.new().snapshot(),
		"player": {
			"position": Vector3(12.5, StreamedFacilityView3D.LEVEL_HEIGHT * level, -8.5),
			"level": level,
			"inventory_order": ["flashlight", "battery", "", "", ""],
			"inventory_slot_durability": [77, 0, 0, 0, 0],
			"stamina": 40.0,
			"flashlight_enabled": true,
		},
		"statistics": {"elapsed_seconds": elapsed, "relays_collected": 4},
		"discovery": {"rooms": {"r1": true}},
	}


func _wipe(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	for sub in directory.get_directories():
		_wipe(path.path_join(sub))
	for file_name in directory.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path.path_join(file_name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func run(host: Node) -> int:
	var old_dir := RunSaves.save_dir
	var old_cloud := RunSaves.cloud_disabled
	_wipe(SCRATCH)
	RunSaves.save_dir = SCRATCH
	RunSaves.cloud_disabled = true
	RunSaves.clear_pending()
	_check_store()
	_check_migration()
	_check_corrupt_and_interrupted()
	await _check_route(host)
	RunSaves.interrupt_before_swap = false
	RunSaves.clear_pending()
	_wipe(SCRATCH)
	RunSaves.save_dir = old_dir
	RunSaves.cloud_disabled = old_cloud
	if _failures == 0:
		print("  store     one run: atomic write + backup, vectors survive, CONTINUE consumed once, cloud newer-wins")
		print("  migrate   an old 9-slot .lrsave becomes the run; a newer format is refused with a message")
		print("  safety    corrupt file -> backup or a clear message; an interrupted write keeps the run")
		print("  route     level/checkpoint/relay/quit autosave; solo death clears (every difficulty); co-op keeps it through one death and a host quit, wipe clears; guests never save")
		print("saves OK")
	return _failures


func _check_store() -> void:
	RunSaves.clear()
	_expect(not RunSaves.has_run() and String(RunSaves.summary().get("message", "x")).is_empty(),
		"an empty save folder reports a run or an error")
	var written := RunSaves.write(_payload(-2, 3723.0), "LEVEL -2")
	_expect(bool(written.get("ok", false)), "the run could not be saved: %s" % written)
	var loaded := RunSaves.load_run()
	var payload: Dictionary = loaded.get("payload", {})
	_expect(bool(loaded.get("ok", false)) and payload.get("player", {}).get("position") is Vector3 \
		and float(payload.get("player", {}).get("stamina", 0.0)) == 40.0,
		"the saved run lost the player's position type or stamina across disk")
	_expect(not (payload.get("world_state", {}) as Dictionary).has("hunters") \
		and not payload.has("anti_idle"), "the save keeps live hunters; the seed should rebuild them")
	var summary := RunSaves.summary()
	_expect(String(summary.get("status", "")).begins_with("RUN SAVED AT LEVEL -2, "),
		"pause/title status line is wrong: %s" % summary)
	RunSaves.write(_payload(-3), "LEVEL -3")
	_expect(FileAccess.file_exists(RunSaves.main_path() + ".bak") \
		and not FileAccess.file_exists(RunSaves.main_path() + ".tmp"),
		"a second save did not keep the previous one as the backup")
	var queued := RunSaves.queue_continue()
	var consumed := RunSaves.consume_pending()
	_expect(bool(queued.get("ok", false)) and String(consumed.get("place", "")) == "LEVEL -3" \
		and RunSaves.consume_pending().is_empty(), "CONTINUE was not consumed exactly once")
	# cloud: a newer account copy replaces the local run, an older one does not
	var record := {"format": RunSaves.FORMAT, "saved_at": int(Time.get_unix_time_from_system()) + 60,
		"place": "LEVEL -9", "payload": _payload(-9)}
	_expect(RunSaves.adopt_cloud(JSON.to_native(JSON.parse_string(JSON.stringify(JSON.from_native(record))))) \
		and String(RunSaves.load_run().get("place", "")) == "LEVEL -9", "a newer cloud run was not adopted")
	record["saved_at"] = 5
	record["place"] = "LEVEL -1"
	_expect(not RunSaves.adopt_cloud(record) and String(RunSaves.load_run().get("place", "")) == "LEVEL -9",
		"an older cloud run replaced the local one")
	RunSaves.clear()
	_expect(not RunSaves.has_run() and not FileAccess.file_exists(RunSaves.main_path() + ".bak"),
		"clearing the run left a copy behind")


func _check_migration() -> void:
	RunSaves.clear()
	var legacy := {"save_schema": 1, "slot_id": "0123456789abcdef0123", "name": "Old Slot",
		"created_at": 100, "saved_at": 200, "payload": _payload(-1)}
	legacy["payload"]["world_state"]["hunters"] = {"H1": {"hunter_id": "x"}}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCRATCH))
	var file := FileAccess.open(SCRATCH.path_join("0123456789abcdef0123.lrsave"), FileAccess.WRITE)
	file.store_var(legacy, false)
	file.close()
	var loaded := RunSaves.load_run()
	_expect(bool(loaded.get("ok", false)) and String(loaded.get("place", "")) == "LEVEL -1" \
		and int(loaded.get("saved_at", 0)) == 200, "an old-format slot did not migrate into the run: %s" % loaded)
	_expect(not FileAccess.file_exists(SCRATCH.path_join("0123456789abcdef0123.lrsave")) \
		and FileAccess.file_exists(SCRATCH.path_join("legacy/0123456789abcdef0123.lrsave")),
		"the old slot file was not kept aside in legacy/")
	var future := {"format": RunSaves.FORMAT + 1, "saved_at": 1, "place": "", "payload": {}}
	_expect(String(RunSaves.migrate(future).get("error", "")).contains("NEWER BUILD"),
		"a save from a newer build is not refused with a clear message")
	RunSaves.clear()


func _check_corrupt_and_interrupted() -> void:
	# corrupt main, no backup: a message, never a crash
	RunSaves.clear()
	_write_text(RunSaves.main_path(), "{\"format\": 2, \"payl")
	var broken := RunSaves.load_run()
	_expect(not bool(broken.get("ok", true)) and String(broken.get("message", "")).contains("START A NEW RUN"),
		"a corrupt save did not report a clear message: %s" % broken)
	_expect(not bool(RunSaves.summary().get("ok", true)) and not String(RunSaves.summary().get("message", "")).is_empty(),
		"the title CONTINUE would not explain the corrupt save")
	_write_text(RunSaves.main_path(), "")
	_expect(not bool(RunSaves.load_run().get("ok", true)), "an empty save file loaded")
	# corrupt main with a good backup: the backup comes back
	RunSaves.clear()
	RunSaves.write(_payload(-4), "LEVEL -4")
	RunSaves.write(_payload(-5), "LEVEL -5")
	_write_text(RunSaves.main_path(), "garbage")
	var recovered := RunSaves.load_run()
	_expect(bool(recovered.get("ok", false)) and String(recovered.get("place", "")) == "LEVEL -4",
		"a corrupt save did not fall back to the backup: %s" % recovered)
	# killed mid-write: the complete temp file or the old run survives, never nothing
	RunSaves.clear()
	RunSaves.write(_payload(-6), "LEVEL -6")
	RunSaves.interrupt_before_swap = true
	var interrupted := RunSaves.write(_payload(-7), "LEVEL -7")
	RunSaves.interrupt_before_swap = false
	_expect(not bool(interrupted.get("ok", true)), "the interrupted-write hook did not interrupt")
	var after := RunSaves.load_run()
	_expect(bool(after.get("ok", false)) and String(after.get("place", "")) in ["LEVEL -6", "LEVEL -7"],
		"an interrupted write lost the run: %s" % after)
	_expect(not FileAccess.file_exists(RunSaves.main_path() + ".tmp"), "the leftover temp file was not tidied")
	RunSaves.write(_payload(-6), "LEVEL -6")
	_write_text(RunSaves.main_path() + ".tmp", "{\"format\": 2, \"saved_at\": 99999999999, \"pla")
	_expect(String(RunSaves.load_run().get("place", "")) == "LEVEL -6",
		"a half-written temp file replaced the good run")
	# main gone between the two renames: the temp file or backup still loads
	RunSaves.clear()
	RunSaves.write(_payload(-6), "LEVEL -6")
	RunSaves.write(_payload(-8), "LEVEL -8")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(RunSaves.main_path()))
	_expect(bool(RunSaves.load_run().get("ok", false)), "losing the main file lost the run despite the backup")
	RunSaves.clear()


func _check_route(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RunSaves.clear()
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	await _frames(host, 10)
	GameState.debug_run = false
	# relay
	RunSaves.clear()
	var world: StreamedWorldState = route.get("world_state")
	world.claimed_pickups["VALIDATE:PICKUP:RELAY:1"] = 1
	route.call("_sync_stream_progress")
	_expect(RunSaves.has_run() and String(route.get("_last_autosave_reason")) == "relay", "collecting a relay did not autosave")
	# checkpoint
	RunSaves.clear()
	route.call("_apply_stream_world_event", {"what": "stream_checkpoint", "checkpoint_id": "VALIDATE:CP", "winner_peer_id": 1})
	_expect(RunSaves.has_run() and String(route.get("_last_autosave_reason")) == "checkpoint", "a checkpoint did not autosave")
	# a new level
	RunSaves.clear()
	var stats: Dictionary = route.get("_run_statistics")
	(stats["visited_levels"] as Dictionary).clear()
	route.call("_update_run_statistics", 0.0)
	_expect(RunSaves.has_run() and String(route.get("_last_autosave_reason")) == "level", "reaching a new level did not autosave")
	RunSaves.clear()
	route.call("_update_run_statistics", 0.0)
	_expect(not RunSaves.has_run(), "staying on a visited level autosaved every frame")
	# quit from the pause menu saves before leaving (the scene change itself is not run here)
	var source := (route.get_script() as GDScript).source_code
	var leave := source.substr(source.find("func _leave_test()"), 200)
	_expect(leave.contains("autosave(\"quit\")"), "LEAVE ROUTE does not save the run first")
	# the saved run carries what CONTINUE needs and the pause line reads from it
	RunSaves.clear()
	route.call("autosave", "validate")
	var resumed := RunSaves.queue_continue()
	var payload: Dictionary = resumed.get("payload", {})
	_expect(bool(resumed.get("ok", false)) and String(payload.get("seed_text", "")) == RoomState.seed_text \
		and payload.get("player", {}).has("stamina") and payload.get("player", {}).has("flashlight_enabled") \
		and payload.get("discovery") is Dictionary and payload.get("statistics", {}).has("elapsed_seconds"),
		"the route save is missing seed, stamina, flashlight, discoveries or time")
	_expect(String(route.call("_save_status_line")).begins_with("RUN SAVED AT LEVEL "), "the pause line does not show the save")
	RunSaves.clear_pending()
	# solo: death clears the run on every difficulty, and a finished run cannot save again
	for difficulty in [RoomState.Difficulty.RELAXED, RoomState.Difficulty.STANDARD, RoomState.Difficulty.HARD]:
		RoomState.difficulty = difficulty
		route.set("_run_save_ended", false)
		route.call("autosave", "validate")
		route.call("_save_after_local_death")
		_expect(not RunSaves.has_run(), "a solo death left the save on difficulty %d" % difficulty)
	var capture := source.substr(source.find("func _resolve_capture_outcome("), 600)
	_expect(capture.contains("_save_after_local_death()"), "a capture does not reach the death save rule")
	_expect(not bool(route.call("autosave", "validate").get("ok", true)) and not RunSaves.has_run(),
		"a dead solo run saved again")
	route.set("_run_save_ended", false)
	GameState.game_over = true
	_expect(not bool(route.call("autosave", "validate").get("ok", true)), "a dead solo runner could still save")
	GameState.game_over = false
	var old := [RoomState.online, RoomState.is_host, RoomState.peers.duplicate(true)]
	RoomState.online = true
	RoomState.peers = {1: "HOST", 2: "GUEST"}
	# co-op: one runner down (the host here) keeps the run; the save goes on updating
	RoomState.is_host = true
	route.set("_test_party_alive", 1)
	RunSaves.write(_payload(-2), "LEVEL -2")
	GameState.game_over = true
	route.call("_save_after_local_death")
	_expect(RunSaves.has_run(), "one co-op death deleted the host's run save")
	_expect(bool(route.call("autosave", "relay").get("ok", false)), "the save stopped updating while the host waits for a revive")
	# co-op: the host quits mid-run while teammates are alive: the save stays for CONTINUE
	route.call("autosave", "quit")
	_expect(RunSaves.has_run(), "the host quitting with live teammates lost the save")
	# co-op: a full team wipe ends the run and its save
	route.set("_test_party_alive", 0)
	var wipe := source.substr(source.find("# Party wipe: the host was already spectating"), 400)
	_expect(wipe.contains("_end_run_save()"), "a party wipe does not end the run's save")
	route.call("_end_run_save")
	_expect(not RunSaves.has_run() and not bool(route.call("autosave", "relay").get("ok", true)),
		"a team wipe left the save or let the ended run save again")
	route.set("_run_save_ended", false)
	GameState.game_over = false
	# co-op: only the host saves
	RoomState.is_host = false
	_expect(not bool(route.call("autosave", "relay").get("ok", true)) and not RunSaves.has_run(), "a co-op guest saved the run")
	RunSaves.write(_payload(-2), "LEVEL -2")
	route.call("_save_after_local_death")
	route.call("_end_run_save")
	_expect(RunSaves.has_run(), "a guest's death touched the save on its machine")
	RunSaves.clear()
	RoomState.is_host = true
	route.set("_test_party_alive", 1)
	_expect(bool(route.call("autosave", "relay").get("ok", false)) and RunSaves.has_run(), "the co-op host could not save")
	route.set("_test_party_alive", -1)
	RoomState.online = old[0]
	RoomState.is_host = old[1]
	RoomState.peers = old[2]
	RunSaves.clear()
	route.queue_free()
	await _frames(host, 2)
