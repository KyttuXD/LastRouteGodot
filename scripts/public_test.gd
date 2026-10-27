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
var game_mode: RoomState.Mode = RoomState.Mode.DEFAULT


func _ready() -> void:
	started = Time.get_ticks_msec()
	var key := ""
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text in ["a", "b", "b2"]:
			role = text
		elif text.begins_with("--dir="):
			dir = text.trim_prefix("--dir=")
		elif text == "--game=city":
			game_mode = RoomState.Mode.CITY
		elif text.begins_with("--key="):
			key = text.trim_prefix("--key=")
	if role.is_empty() or dir.is_empty() or key.is_empty():
		_fail("usage: -- a|b|b2 --backend=URL --dir=DIR --key=HEX")
		return
	var refused := TargetGuard.problem()
	if not refused.is_empty():
		_fail(refused)
		return
	PublicRoute.use_player_key(key)
	get_tree().current_scene = null
	_run.call_deferred()


func _say(message: String) -> void:
	print("PUBLIC %s OK %s" % [role.to_upper(), message])


func _fail(message: String) -> void:
	print("PUBLIC %s FAIL %s [public: %s | room: %s | online=%s connecting=%s host=%s]" % [role.to_upper(), message,
		PublicRoute.status, RoomState.status_message, RoomState.online, RoomState.connecting, RoomState.is_host])
	push_error(message)
	OS.kill(OS.get_process_id())


func _wait_for(test: Callable, what: String, seconds: float = 45.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	var next_note := Time.get_ticks_msec() + 5000
	while Time.get_ticks_msec() < deadline:
		if test.call():
			return true
		if Time.get_ticks_msec() > next_note:
			next_note += 5000
			print("PUBLIC %s .. waiting for %s [public: %s | room: %s | online=%s connecting=%s host=%s]" % [role.to_upper(), what,
				PublicRoute.status, RoomState.status_message, RoomState.online, RoomState.connecting, RoomState.is_host])
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
	var route_scene := RoomState.CITY_ROUTE_SCENE if game_mode == RoomState.Mode.CITY else "res://scenes/infinite_route_test.tscn"
	return current != null and current.scene_file_path == route_scene \
		and current.get("facility") != null and current.facility.generator != null


func _relay() -> Dictionary:
	var generator: StreamedRouteGenerator = scene.facility.generator
	for coord in [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(0, 0, -1),
			Vector3i(1, 0, 1), Vector3i(-1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, -1), Vector3i(2, 0, 0), Vector3i(-2, 0, 0)]:
		for pickup_value in generator.chunk(coord).get("pickups", []):
			var pickup: Dictionary = pickup_value
			if String(pickup.get("kind", "")) == "relay":
				var cell: Vector2i = pickup["cell"]
				return {"id": String(pickup["id"]), "position": Vector3(
					coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5, .05,
					coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)}
	return {}


func _enter_public() -> bool:
	PublicRoute.join(game_mode)
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
	var counted := func() -> bool: return int(PublicRoute.server.get("relaysCollected", 0)) >= 1
	if not await _wait_for(counted, "backend to count it", 20.0):
		return
	_write("a_relay.txt", relay["id"])
	if not await _wait_for(func() -> bool: return int(PublicRoute.server.get("playersOnline", 0)) >= 2, "second player", 60.0):
		return
	_say("sees %d players online; hud line: %s" % [PublicRoute.server.get("playersOnline"), PublicRoute.line()])
	# Hunter emote: the authority's hunter plays one; the guest must see it through the replicated hunter state.
	if not await _wait_for(func() -> bool: return _read("server_restarted.txt") != "", "server restart", 180.0):
		return
	var restored := func() -> bool:
		return PublicRoute.session_id != "" and Backend.registered \
			and int(PublicRoute.server.get("relaysCollected", 0)) >= 1
	if not await _wait_for(restored, "session and listing after the server restart", 60.0):
		return
	_say("survived the server restart: new session, PUBLIC listing back, relays=%d" % PublicRoute.server.get("relaysCollected"))
	_write("a_after_restart.txt", "1")
	var holder := [null]   # lambdas capture by value; a container carries the result out
	var find_hunter := func() -> bool:
		for view_value in scene._hunter_views.values():
			holder[0] = view_value
			return holder[0] != null
		return false
	if not await _wait_for(find_hunter, "a hunter on the route", 60.0):
		return
	(holder[0] as HunterView3D).brain.start_emote(HunterEmoteCatalog.SMUG, 12.0)
	_write("a_hunter_emote.txt", "1")
	if not await _wait_for(func() -> bool: return _read("b2_saw_hunter_emote.txt") != "", "guest to see the hunter emote", 40.0):
		return
	_say("hunter emote replicated to the guest")
	# Spectator: the authority is caught while the guest still lives. It must watch
	# without dropping the session or its hunter simulation, then rejoin on its own.
	scene.get_script().set("public_spectate_seconds", 25.0)   # leave the guest time to see it
	scene._resolve_capture_outcome(HunterRoster.DEFAULT_ID)
	if not await _wait_for(func() -> bool: return scene.player.spectator_mode, "authority to spectate", 10.0):
		return
	if not RoomState.is_host or not PublicRoute.is_authority or not scene._remotes.simulates():
		_fail("authority lost its role or simulation while spectating")
		return
	_say("authority is spectating (still authority, still simulating)")
	_write("a_spectating.txt", "1")
	if not await _wait_for(func() -> bool: return not scene.player.spectator_mode, "authority to rejoin", 40.0):
		return
	if not await _wait_for(func() -> bool: return _read("b2_spectating.txt") != "", "guest to spectate", 60.0):
		return
	var guest_down := func() -> bool:
		for target in scene._remotes.target_states({}):
			if bool(target.get("spectating", false)) or bool(target.get("game_over", false)):
				return true
		return false
	if not await _wait_for(guest_down, "guest spectator state on the authority", 20.0):
		return
	_say("guest died and is a non-targetable spectator while the authority lives")
	_write("a_spectate_done.txt", "1")
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
	# hunter emote from the authority
	if not await _wait_for(func() -> bool: return _read("a_hunter_emote.txt") != "", "authority's hunter emote", 150.0):
		return
	var hunter_emote_seen := func() -> bool:
		for view_value in scene._hunter_views.values():
			var view := view_value as HunterView3D
			if view != null and view._emote_index == HunterEmoteCatalog.SMUG:
				return true
		return false
	if not await _wait_for(hunter_emote_seen, "the hunter's emote on the guest", 30.0):
		return
	_write("b2_saw_hunter_emote.txt", "1")
	_say("saw the hunter's emote")
	# authority gets caught: this guest must keep playing and see it as a spectator
	if not await _wait_for(func() -> bool: return _read("a_spectating.txt") != "", "authority to spectate", 120.0):
		return
	var host_down := func() -> bool:
		for target in scene._remotes.target_states({}):
			if bool(target.get("spectating", false)):
				return true
		return false
	if not await _wait_for(host_down, "authority spectator state on the guest", 20.0):
		return
	if scene.player.spectator_mode or scene._death_screen_open:
		_fail("guest was dragged into spectating by the authority's death")
		return
	_say("authority is spectating; this guest is still alive")
	await get_tree().create_timer(10.0).timeout
	scene.get_script().set("public_spectate_seconds", 25.0)
	scene._resolve_capture_outcome(HunterRoster.DEFAULT_ID)
	if not await _wait_for(func() -> bool: return scene.player.spectator_mode, "guest to spectate", 10.0):
		return
	_say("guest caught: spectating")
	_write("b2_spectating.txt", "1")
	if not await _wait_for(func() -> bool: return not scene.player.spectator_mode, "guest to rejoin", 20.0):
		return
	# the authority will be killed: this client must take over the route
	var took_over := func() -> bool:
		return PublicRoute.is_authority and RoomState.is_host and _in_route()
	if not await _wait_for(took_over, "to become the authority after the host vanished", 150.0):
		return
	scene = get_tree().current_scene
	if not await _wait_for(func() -> bool: return GameState.relays_collected >= 1, "restored relays", 20.0):
		return
	_say("took over as the authority; relays=%d restored from the backend" % GameState.relays_collected)
	_write("b2_authority.txt", "1")
	while true:
		await get_tree().create_timer(1.0).timeout
