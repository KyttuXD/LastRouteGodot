extends Node

## Real-process deliberate host handoff, one headless process per role. Driven by tools/build/handoff_test.sh
## (local backend + relay only).
##
##   godot --headless --path . res://tests/scenes/handoff_test.tscn -- old|succ|other --backend=URL --dir=DIR
##
## old: hosts, starts the route, pins a waypoint, then hands the room over (RoomState.begin_host_handoff) and must
##   leave WITHOUT closing the room. succ: joins first (so it is the chosen successor), pins a waypoint, and must come
##   back as peer 1 on a fresh ENet server with the route rebuilt from the checkpoint (its pin now peer 1's, the old
##   host's gone). other: pins a waypoint, freezes, reconnects to the successor, proves its resume identity and must
##   see its pin rebound to its NEW peer id. Each role ends with `HANDOFF <ROLE> DONE` or `HANDOFF <ROLE> FAIL ...`.

const TIMEOUT_SECONDS := 200.0
const OLD_PORT := 18531

var role := ""
var dir := ""
var scene: Node
var started_msec := 0


func _ready() -> void:
	started_msec = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text in ["old", "succ", "other"]:
			role = text
		elif text.begins_with("--dir="):
			dir = text.trim_prefix("--dir=")
	if role.is_empty() or dir.is_empty():
		_fail("usage: -- old|succ|other --backend=URL --dir=DIR")
		return
	var refused := TargetGuard.problem()
	if not refused.is_empty():
		_fail(refused)
		return
	if not Backend.base_url.begins_with("http://127.0.0.1:"):
		_fail("the handoff test runs only against its local backend")
		return
	get_tree().current_scene = null
	_run.call_deferred()


func _log(message: String) -> void:
	print("HANDOFF %s OK %s" % [role.to_upper(), message])


func _state() -> String:
	var current := get_tree().current_scene
	return "[scene %s; online %s host %s; session %s; handoff phase %d; status %s]" % [
		current.scene_file_path if current != null else "<none>", RoomState.online, RoomState.is_host,
		RoomState.session_active, RoomState.handoff_phase, RoomState.status_message]


func _fail(message: String) -> void:
	message += " " + _state()
	push_error("HANDOFF %s FAIL %s" % [role.to_upper(), message])
	print("HANDOFF %s FAIL %s" % [role.to_upper(), message])
	get_tree().quit(1)


func _wait_for(test: Callable, what: String, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var next_note := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if test.call():
			return true
		if Time.get_ticks_msec() >= next_note:
			next_note += 10000
			print("HANDOFF %s WAIT %s %s" % [role.to_upper(), what, _state()])
		await get_tree().process_frame
	_fail("timed out waiting for " + what)
	return false


func _in_route() -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == "res://game/infinite_route/infinite_route_test.tscn" \
		and current.get("facility") != null and current.facility.generator != null


func _file(name: String) -> String:
	return dir.path_join(name)


func _write(name: String, text: String) -> void:
	var f := FileAccess.open(_file(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(name: String) -> String:
	return FileAccess.get_file_as_string(_file(name)).strip_edges() if FileAccess.file_exists(_file(name)) else ""


func _run() -> void:
	await get_tree().process_frame
	match role:
		"old":
			await _run_old()
		_:
			await _run_guest()


func _pin(at: Vector2) -> void:
	scene._place_waypoint_at(at, scene.facility.current_level())


func _run_old() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "HANDOFF-TEST-SEED"
	RoomState.set_map_scale(RoomState.Scale.INFINITE)
	var error := RoomState.host_primary_room(OLD_PORT)
	if not error.is_empty():
		_fail(error)
		return
	if not await _wait_for(func() -> bool: return Backend.registered, "backend registration", 15.0):
		return
	var code := RoomState.code
	_write("code.txt", code)
	_log("room %s listed (relay)" % code)
	if not await _wait_for(func() -> bool: return RoomState.roster().size() >= 3, "both guests", 60.0):
		return
	if not await _wait_for(func() -> bool: return RoomState.handoff_candidate() > 1, "a handoff-capable guest", 15.0):
		return
	RoomState.enter(get_tree())
	if not await _wait_for(_in_route, "host route scene", 60.0):
		return
	scene = get_tree().current_scene
	if not await _wait_for(func() -> bool: return scene._remotes.count() >= 2, "guest bodies", 60.0):
		return
	_pin(Vector2(20.5, 20.5))
	if not await _wait_for(func() -> bool: return scene.world_state.waypoints.by_peer.size() >= 3, "all three pins", 40.0):
		return
	_log("route up; pins by peer %s; successor candidate %d" % [scene.world_state.waypoints.by_peer.keys(), RoomState.handoff_candidate()])
	_write("old_peer_ids.txt", ",".join(RoomState.peers.keys().map(func(id): return str(id))))
	var handoff_error := RoomState.begin_host_handoff()
	if not handoff_error.is_empty():
		_fail("handoff did not start: %s" % handoff_error)
		return
	_log("handoff started (epoch %d)" % RoomState.handoff_epoch)
	if not await _wait_for(func() -> bool: return not RoomState.last_handoff_outcome.is_empty(), "handoff commit", 30.0):
		return
	if not RoomState.last_handoff_outcome.begins_with("HOST HANDED OVER"):
		_fail("handoff did not commit: %s" % RoomState.last_handoff_outcome)
		return
	if RoomState.online or RoomState.code == code or Backend.registered:
		_fail("the old host kept the room after the commit")
		return
	_log("committed; left the room without closing it")
	_write("old_left.txt", "1")
	print("HANDOFF OLD DONE")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _run_guest() -> void:
	if role == "other":
		if not await _wait_for(func() -> bool: return _read("succ_joined.txt") != "", "successor to join first", 60.0):
			return
	if not await _wait_for(func() -> bool: return _read("code.txt") != "", "room code", 60.0):
		return
	var code := _read("code.txt")
	var box := [{}]
	var finished := [false]
	Backend.room_resolved.connect(func(_c: String, endpoint: Dictionary, err: String) -> void:
		box[0] = endpoint if err.is_empty() else {"error": err}
		finished[0] = true)
	Backend.resolve_room(code)
	if not await _wait_for(func() -> bool: return finished[0], "room lookup", 10.0):
		return
	var resolved: Dictionary = box[0]
	if resolved.has("error"):
		_fail(String(resolved["error"]))
		return
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var join_error := RoomState.join_room(String(resolved.get("address", "")),
		int(resolved.get("port", 0)), String(resolved.get("transport", "relay")), code)
	if not join_error.is_empty():
		_fail(join_error)
		return
	if not await _wait_for(func() -> bool: return RoomState.online and RoomState.peers.size() >= 2, "joined roster", 20.0):
		return
	if not await _wait_for(func() -> bool: return not RoomState._resume_secret.is_empty(), "a host-issued resume identity", 10.0):
		return
	if role == "succ":
		_write("succ_joined.txt", "1")
	var old_id := multiplayer.get_unique_id()
	_log("joined %s as peer %d" % [code, old_id])
	if not await _wait_for(_in_route, "route start", 90.0):
		return
	scene = get_tree().current_scene
	if not await _wait_for(func() -> bool: return not scene._awaiting_snapshot, "host snapshot", 40.0):
		return
	var my_pin := Vector2(30.5, 24.5) if role == "succ" else Vector2(24.5, 30.5)
	# the host accepts a pin only once it has this runner's replicated state: retry until it is echoed back
	var last_try := [0]
	if not await _wait_for(func() -> bool:
			var own: Dictionary = scene.world_state.waypoints.get_for(old_id)
			if not own.is_empty() and (own["at"] as Vector2).is_equal_approx(my_pin):
				return true
			if Time.get_ticks_msec() - last_try[0] > 1000:
				last_try[0] = Time.get_ticks_msec()
				_pin(my_pin)
			return false, "own pin echoed by the old host", 40.0):
		return
	_log("pinned %s as peer %d" % [my_pin, old_id])
	var saw_freeze := [false]
	var watch := func() -> bool:
		if RoomState.handoff_freezes_input():
			saw_freeze[0] = true
		return saw_freeze[0]
	if not await _wait_for(watch, "the handoff freeze", 90.0):
		return
	_log("frozen for the handoff (phase %d)" % RoomState.handoff_phase)
	if role == "succ":
		await _finish_successor(old_id, my_pin)
	else:
		await _finish_other(old_id, my_pin)


func _finish_successor(old_id: int, my_pin: Vector2) -> void:
	if not await _wait_for(func() -> bool: return RoomState.is_host and RoomState.online, "promotion to host", 30.0):
		return
	if multiplayer.get_unique_id() != 1:
		_fail("the successor is not peer 1 (%d)" % multiplayer.get_unique_id())
		return
	_log("promoted: fresh ENet server, peer 1, relay host")
	if not await _wait_for(func() -> bool: return RoomState.handoff_phase == RoomState.Handoff.NONE and _in_route() \
			and get_tree().current_scene != scene, "route rebuilt from the checkpoint", 60.0):
		return
	scene = get_tree().current_scene
	if not await _wait_for(func() -> bool: return scene.get("_remotes") != null, "rebuilt remotes", 20.0):
		return
	var pins: Dictionary = scene.world_state.waypoints.by_peer
	if not pins.has(1) or not (pins[1]["at"] as Vector2).is_equal_approx(my_pin):
		_fail("the successor's own pin did not become peer 1's: %s" % [pins])
		return
	for peer_id in pins:
		if (pins[peer_id]["at"] as Vector2).is_equal_approx(Vector2(20.5, 20.5)):
			_fail("the old host's pin survived the handoff: %s" % [pins])
			return
	if not scene._remotes.simulates():
		_fail("the successor is not simulating after the rebuild")
		return
	_log("route rebuilt as authority; own pin is peer 1's; old host's pin gone")
	if not await _wait_for(func() -> bool: return RoomState.peers.size() >= 2, "the other guest to reconnect", 40.0):
		return
	if not await _wait_for(func() -> bool: return _read("other_done.txt") != "", "the other guest's verdict", 60.0):
		return
	if Backend.host_token().is_empty() or not Backend.registered:
		_fail("the successor does not hold the room listing")
		return
	_log("other guest reconnected (roster %s); room still listed" % [RoomState.roster()])
	print("HANDOFF SUCC DONE")
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)


func _finish_other(old_id: int, my_pin: Vector2) -> void:
	if not await _wait_for(func() -> bool: return RoomState.reconnect_active, "the reconnect to the new host", 40.0):
		return
	_log("new host ready; reconnecting")
	if not await _wait_for(func() -> bool: return not RoomState.reconnect_active and RoomState.online \
			and not scene._awaiting_snapshot, "the committed snapshot from the new host", 60.0):
		return
	var new_id := multiplayer.get_unique_id()
	if new_id == old_id:
		_fail("the peer id did not change across the ENet rebuild")
		return
	if not await _wait_for(func() -> bool:
			var own: Dictionary = scene.world_state.waypoints.get_for(new_id)
			return not own.is_empty() and (own["at"] as Vector2).is_equal_approx(my_pin) \
				and not scene.world_state.waypoints.has_for(old_id), "own pin rebound to the new peer id", 40.0):
		return
	if RoomState.peers.size() < 2 or not RoomState.peers.has(1):
		_fail("roster after the handoff: %s" % [RoomState.peers])
		return
	_log("reconnected as peer %d (was %d); pin rebound by resume proof; roster %s" % [new_id, old_id, RoomState.roster()])
	_write("other_done.txt", "1")
	print("HANDOFF OTHER DONE")
	await get_tree().create_timer(1.5).timeout
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - started_msec > int(TIMEOUT_SECONDS * 1000.0):
		_fail("global timeout")
