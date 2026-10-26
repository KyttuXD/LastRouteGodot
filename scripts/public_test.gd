extends Node

## One client of the PUBLIC route test (scripts/public_test.sh drives the whole
## story). Roles: a (first in: becomes the authority), b (guest), b2 (b again
## after a crash, same player key).
##
##   godot --headless --path . res://scenes/public_test.tscn -- ROLE --backend=URL --dir=DIR --key=HEX

var role := ""
var dir := ""
var scene: Node
var started := 0


func _ready() -> void:
	started = Time.get_ticks_msec()
	var key := ""
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text in ["a", "b", "b2"]:
			role = text
		elif text.begins_with("--dir="):
			dir = text.trim_prefix("--dir=")
		elif text.begins_with("--key="):
			key = text.trim_prefix("--key=")
	if role.is_empty() or dir.is_empty() or key.is_empty():
		_fail("usage: -- a|b|b2 --backend=URL --dir=DIR --key=HEX")
		return
	PublicRoute.use_player_key(key)
	get_tree().current_scene = null
	_run.call_deferred()


func _say(message: String) -> void:
	print("PUBLIC %s OK %s" % [role.to_upper(), message])


func _fail(message: String) -> void:
	print("PUBLIC %s FAIL %s" % [role.to_upper(), message])
	push_error(message)
	OS.kill(OS.get_process_id())


func _wait_for(test: Callable, what: String, seconds: float = 45.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if test.call():
			return true
		await get_tree().process_frame
	_fail("timed out waiting for " + what)
	return false


func _file(name: String) -> String:
	return dir.path_join(name)


func _write(name: String, text: String) -> void:
	var f := FileAccess.open(_file(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(name: String) -> String:
	return FileAccess.get_file_as_string(_file(name)).strip_edges() if FileAccess.file_exists(_file(name)) else ""


func _in_route() -> bool:
	var current := get_tree().current_scene
	return current != null and current.scene_file_path == "res://scenes/infinite_route_test.tscn" \
		and current.get("facility") != null and current.facility.generator != null


func _relay() -> Dictionary:
	var generator: StreamedRouteGenerator = scene.facility.generator
	for coord in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1)]:
		for pickup_value in generator.chunk(coord).get("pickups", []):
			var pickup: Dictionary = pickup_value
			if String(pickup.get("kind", "")) == "relay":
				var cell: Vector2i = pickup["cell"]
				return {"id": String(pickup["id"]), "position": Vector3(
					coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5, .05,
					coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)}
	return {}


func _enter_public() -> bool:
	PublicRoute.join()
	if not await _wait_for(_in_route, "route scene", 60.0):
		return false
	scene = get_tree().current_scene
	return await _wait_for(func() -> bool: return not scene._awaiting_snapshot, "snapshot", 30.0)


func _run() -> void:
	await get_tree().process_frame
	match role:
		"a":
			await _run_a()
		"b":
			await _run_b()
		"b2":
			await _run_b2()


func _run_a() -> void:
	if not await _enter_public():
		return
	if not RoomState.is_host or not PublicRoute.is_authority:
		_fail("first client did not become the authority")
		return
	_say("authority of the PUBLIC route, seed %s, day %s" % [RoomState.seed_text, PublicRoute.server.get("day")])
	var relay := _relay()
	scene.player.global_position = relay["position"]
	scene.facility.refresh_at_tracked_player()
	for _i in 20:
		await get_tree().process_frame
	scene._request_streamed_pickup(scene.player, relay["id"], "relay", "")
	if not await _wait_for(func() -> bool: return GameState.relays_collected >= 1, "own relay", 20.0):
		return
	_say("collected relay %s; relays=%d" % [relay["id"], GameState.relays_collected])
	if not await _wait_for(func() -> bool: return int(PublicRoute.server.get("relaysCollected", 0)) >= 1, "backend to count it", 20.0):
		return
	_write("a_relay.txt", relay["id"])
	if not await _wait_for(func() -> bool: return int(PublicRoute.server.get("playersOnline", 0)) >= 2, "second player", 60.0):
		return
	_say("sees %d players online; hud line: %s" % [PublicRoute.server.get("playersOnline"), PublicRoute.line()])
	if not await _wait_for(func() -> bool: return _read("server_restarted.txt") != "", "server restart", 180.0):
		return
	if not await _wait_for(func() -> bool: return PublicRoute.session_id != "" and int(PublicRoute.server.get("relaysCollected", 0)) >= 1
			and Backend.registered, "session and listing after the server restart", 60.0):
		return
	_say("survived the server restart: new session, PUBLIC listing back, relays=%d" % PublicRoute.server.get("relaysCollected"))
	_write("a_after_restart.txt", "1")
	# wait to be killed by the test
	while true:
		await get_tree().create_timer(1.0).timeout


func _run_b() -> void:
	if not await _wait_for(func() -> bool: return _read("a_relay.txt") != "", "authority's relay", 90.0):
		return
	if not await _enter_public():
		return
	if RoomState.is_host or PublicRoute.is_authority:
		_fail("second client became a host")
		return
	_say("guest in the shared route; relays=%d (server says %d)" % [GameState.relays_collected, PublicRoute.server.get("relaysCollected")])
	if GameState.relays_collected < 1:
		_fail("the relay collected by the first player is not counted for the guest")
		return
	if not await _wait_for(func() -> bool: return not PublicRoute.in_join_grace() or true, "grace", 1.0):
		return
	var target := Vector3(40.5, .05, 31.5)
	scene.player.global_position = scene._nearest_valid_position(Vector2(target.x, target.z))
	scene.facility.refresh_at_tracked_player()
	scene.player.grant_inventory_item("battery")
	for _i in 10:
		await get_tree().process_frame
	var position: Vector3 = scene.player.global_position
	await get_tree().create_timer(3.0).timeout   # let a state post carry position + inventory
	_write("b_pos.txt", "%f|%f" % [position.x, position.z])
	_say("moved to %s and picked up a battery; posting, then crashing" % position)
	OS.kill(OS.get_process_id())


func _run_b2() -> void:
	if not await _enter_public():
		return
	var saved := _read("b_pos.txt").split("|")
	var expected := Vector2(float(saved[0]), float(saved[1]))
	var here := Vector2(scene.player.global_position.x, scene.player.global_position.z)
	if here.distance_to(expected) > 1.5:
		_fail("did not resume at the saved spot: %s vs %s" % [here, expected])
		return
	if not scene.player.owns_inventory_item("battery"):
		_fail("did not resume the inventory (no battery)")
		return
	_say("resumed at %s with the battery after a crash" % here)
	_write("b2_ok.txt", "1")
	# the authority will be killed: this client must take over the route
	if not await _wait_for(func() -> bool: return PublicRoute.is_authority and RoomState.is_host and _in_route(),
			"to become the authority after the host vanished", 150.0):
		return
	scene = get_tree().current_scene
	if not await _wait_for(func() -> bool: return GameState.relays_collected >= 1, "restored relays", 20.0):
		return
	_say("took over as the authority; relays=%d restored from the backend" % GameState.relays_collected)
	_write("b2_authority.txt", "1")
	while true:
		await get_tree().create_timer(1.0).timeout
