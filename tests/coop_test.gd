extends Node

## Real host + guest co-op session through the local backend, one headless
## process per role. Driven by tools/build/coop_test.sh.
##
##   godot --headless --path . res://tests/scenes/coop_test.tscn -- ROLE --backend=URL --dir=DIR [--port=N]
##
## ROLE: host | guest | late. The host creates a room (listed with the backend,
## relayed over UDP), waits for a guest, starts the infinite route, and checks
## the guest's body, relay pickup and hunter replication. The late joiner enters
## after the pickup and must receive the claimed-relay state in its snapshot.
## Each role prints `COOP <ROLE> OK ...` lines and ends with `COOP <ROLE> DONE`
## (exit 0) or `COOP <ROLE> FAIL ...` (exit 1).

const TIMEOUT_SECONDS := 90.0

var role := ""
var dir := ""
var port := 18511
var scene: Node
var started_msec := 0


func _ready() -> void:
	started_msec = Time.get_ticks_msec()
	for argument in OS.get_cmdline_user_args():
		var text := String(argument)
		if text in ["host", "guest", "late"]:
			role = text
		elif text.begins_with("--dir="):
			dir = text.trim_prefix("--dir=")
		elif text.begins_with("--port="):
			port = int(text.trim_prefix("--port="))
	if role.is_empty() or dir.is_empty():
		_fail("usage: -- host|guest|late --backend=URL --dir=DIR")
		return
	var refused := TargetGuard.problem()
	if not refused.is_empty():
		_fail(refused)
		return
	# Stay in the tree when starting a route swaps the current scene: this node is
	# not "the current scene" any more, so change_scene_to_file leaves it alone.
	get_tree().current_scene = null
	_run.call_deferred()


func _log(message: String) -> void:
	print("COOP %s OK %s" % [role.to_upper(), message])


func _fail(message: String) -> void:
	push_error("COOP %s FAIL %s" % [role.to_upper(), message])
	print("COOP %s FAIL %s" % [role.to_upper(), message])
	get_tree().quit(1)


func _wait_for(test: Callable, what: String, seconds: float = 30.0) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if test.call():
			return true
		await get_tree().process_frame
	_fail("timed out waiting for " + what)
	return false


func _in_route() -> bool:
	var current := get_tree().current_scene
	var route_scene := "res://game/infinite_route/infinite_route_test.tscn"
	return current != null and current.scene_file_path == route_scene \
		and current.get("facility") != null and current.facility.generator != null


func _run() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	match role:
		"host":
			await _run_host()
		"guest":
			await _run_guest(false)
		"late":
			await _run_guest(true)


# -- helpers ---------------------------------------------------------------------

func _file(name: String) -> String:
	return dir.path_join(name)


func _write(name: String, text: String) -> void:
	var f := FileAccess.open(_file(name), FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _read(name: String) -> String:
	if not FileAccess.file_exists(_file(name)):
		return ""
	return FileAccess.get_file_as_string(_file(name)).strip_edges()


func _first_relay() -> Dictionary:
	# the relay nearest the spawn on the single level
	var generator: StreamedRouteGenerator = scene.facility.generator
	var best := {}
	var best_distance := INF
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			var coord := Vector3i(cx, 0, cz)
			var data := generator.chunk(coord)
			for pickup_value in data.get("pickups", []):
				var pickup: Dictionary = pickup_value
				if String(pickup.get("kind", "")) != "relay":
					continue
				var cell: Vector2i = pickup["cell"]
				var world := Vector3(coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5, 0.05,
					coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
				var distance := world.distance_to(Vector3(22.5, 0, 22.5))
				if distance < best_distance:
					best_distance = distance
					best = {"id": String(pickup["id"]), "position": world}
	return best


# -- roles -------------------------------------------------------------------------

static func _test_mode() -> RoomState.Mode:
	return RoomState.Mode.DEFAULT


func _run_host() -> void:
	RoomState.create_local(_test_mode())
	RoomState.seed_text = "COOP-TEST-SEED"
	RoomState.set_map_scale(RoomState.Scale.INFINITE)
	var error := RoomState.host_primary_room(port)
	if not error.is_empty():
		_fail(error)
		return
	if not await _wait_for(func() -> bool: return Backend.registered, "backend registration", 15.0):
		return
	_log("room %s listed with the backend (relay)" % RoomState.code)
	_write("code.txt", RoomState.code)
	if not await _wait_for(func() -> bool: return RoomState.roster().size() >= 2, "guest to join", 40.0):
		return
	_log("guest joined; roster %s" % [RoomState.roster()])
	RoomState.enter(get_tree())
	if not await _wait_for(_in_route, "host route scene", 40.0):
		return
	scene = get_tree().current_scene
	_log("host route up; chunks %d" % scene.facility.loaded_chunk_count())
	if not await _wait_for(func() -> bool: return scene._remotes.count() >= 1, "guest body", 40.0):
		return
	_log("guest body replicated on the host")
	_write("host_ready.txt", "1")
	var relay := _first_relay()
	if relay.is_empty():
		_fail("no relay near spawn")
		return
	_write("relay.txt", "%s|%f|%f" % [relay["id"], relay["position"].x, relay["position"].z])
	if not await _wait_for(func() -> bool: return not scene.world_state.pickup_available(relay["id"]),
			"guest relay claim", 40.0):
		return
	_log("guest's relay %s claimed through host authority; relays=%d" % [relay["id"], GameState.relays_collected])
	_write("claimed.txt", "1")
	# hunters materialise by id on both sides
	if not await _wait_for(func() -> bool: return _read("guest_hunters.txt") != "", "guest hunter report", 40.0):
		return
	_log("host hunters %d, guest saw %s" % [scene._hunter_views.size(), _read("guest_hunters.txt")])
	# late joiner
	if not await _wait_for(func() -> bool: return _read("late_done.txt") != "", "late joiner", 60.0):
		return
	_log("late joiner snapshot verified: %s" % _read("late_done.txt"))
	# guest disconnect + automatic reconnect
	if not await _wait_for(func() -> bool: return _read("guest_reconnected.txt") != "", "guest reconnect", 40.0):
		return
	if not await _wait_for(func() -> bool: return RoomState.roster().size() == 3, "stale peer row removal", 15.0):
		return
	_log("guest reconnected; roster %s (no ghost row)" % [RoomState.roster()])
	# -- hunter emotes -----------------------------------------------------------
	# the host's hunter plays a (long) smug emote; the guest must replay it from the replicated hunter state
	var smug := HunterEmoteCatalog.SMUG
	var emoting_view: HunterView3D
	for view_value in scene._hunter_views.values():
		emoting_view = view_value as HunterView3D
		break
	if emoting_view == null:
		_fail("no hunter on the host to emote")
		return
	emoting_view.brain.start_emote(smug, 8.0)
	_write("hunter_emote_id.txt", str(emoting_view.get_meta("streamed_entity_id", "")))
	if not await _wait_for(func() -> bool: return _read("guest_saw_hunter_emote.txt") != "", "guest to see the hunter emote", 20.0):
		return
	_log("hunter emote replicated to the guest (%s)" % _read("guest_saw_hunter_emote.txt"))
	# -- waypoints: one pin per player, host-authoritative, replicated ------------------
	var wp_level: int = scene.facility.current_level()
	scene._place_waypoint_at(Vector2(22.5, 26.5), wp_level)
	_write("wp_host.txt", "1")
	if not await _wait_for(func() -> bool: return _read("guest_wp.txt") != "", "guest waypoint report", 30.0):
		return
	var guest_wp := _read("guest_wp.txt").split("|")
	var host_pins: Dictionary = scene.world_state.waypoints.by_peer
	var guest_pin_ok := false
	for peer_id in host_pins:
		if int(peer_id) != 1 and (host_pins[peer_id]["at"] as Vector2).is_equal_approx(Vector2(float(guest_wp[0]), float(guest_wp[1]))):
			guest_pin_ok = true
	if host_pins.size() != 2 or not guest_pin_ok or not host_pins.has(1):
		_fail("waypoints on the host: expected the host pin and the guest's LAST pin, got %s" % [host_pins])
		return
	_log("waypoints: host holds one pin per player (%d), the guest's second pin replaced its first" % host_pins.size())
	_write("wp_ok.txt", "1")
	# -- spectators --------------------------------------------------------------
	# 1. guest dies while the host lives: host keeps playing and simulating
	if not await _wait_for(func() -> bool: return _read("guest_spectating.txt") != "", "guest to spectate", 40.0):
		return
	var guest_down := func() -> bool:
		for target in scene._remotes.target_states({}):
			if bool(target.get("spectating", false)):
				return true
		return false
	if not await _wait_for(guest_down, "guest spectator state on the host", 15.0):
		return
	if scene.player.spectator_mode or scene._death_screen_open or not scene._remotes.simulates():
		_fail("host was affected by the guest's death")
		return
	_log("guest died -> spectating; host still alive and simulating hunters")
	# the host restarting the run revives the spectating guest
	scene._death_screen_open = true
	scene._respawn_after_death()
	if not await _wait_for(func() -> bool: return _read("guest_revived.txt") != "", "guest revive", 15.0):
		return
	# 2. host dies while the guest lives: session and simulation continue. The revive file lands before the guest's
	# next state packet, so wait until the host itself counts the guest as living (not spectating, not syncing).
	if not await _wait_for(func() -> bool: return not scene._living_runners().is_empty(), "guest alive on the host", 15.0):
		return
	scene._resolve_capture_outcome(HunterRoster.DEFAULT_ID)
	if not await _wait_for(func() -> bool: return scene.player.spectator_mode, "host to spectate", 10.0):
		return
	await get_tree().create_timer(1.0).timeout
	if scene._death_screen_open or scene.run_report.is_open() or not scene._remotes.simulates() \
			or not RoomState.is_host or RoomState.peers.size() < 2:
		_fail("host death ended the session or its simulation")
		return
	var hunters_before: int = scene._hunter_views.size()
	_log("host died -> spectating; guest alive, session and simulation continue (%d hunters)" % hunters_before)
	_write("host_spectating.txt", "1")
	# 3. the guest then dies too: the run ends (run report on the host)
	if not await _wait_for(func() -> bool: return scene.run_report.is_open(), "party wipe run report", 30.0):
		return
	_log("everyone down -> run over screen")
	for target in scene._remotes.target_states({}):
		_log("  runner %s spectating=%s game_over=%s" % [target.get("peer_id"), target.get("spectating"), target.get("game_over")])
	scene._respawn_after_death()
	if not await _wait_for(func() -> bool: return _read("guest_revived2.txt") != "", "guest revive after wipe", 15.0):
		return
	_write("host_done.txt", "1")
	print("COOP HOST DONE")
	get_tree().quit(0)


func _run_guest(is_late: bool) -> void:
	if is_late:
		if not await _wait_for(func() -> bool: return _read("claimed.txt") != "", "claimed relay", 80.0):
			return
	if not await _wait_for(func() -> bool: return _read("code.txt") != "", "room code", 40.0):
		return
	var code := _read("code.txt")
	var box := [{}]   # lambdas capture by value; a container carries the result out
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
	RoomState.create_local(_test_mode())
	var join_error := RoomState.join_room(String(resolved.get("address", "")),
		int(resolved.get("port", 0)), String(resolved.get("transport", "relay")), code)
	if not join_error.is_empty():
		_fail(join_error)
		return
	if not await _wait_for(func() -> bool: return RoomState.online and RoomState.peers.size() >= 2,
			"joined roster", 20.0):
		return
	_log("joined room %s as %s" % [code, RoomState.local_display_name()])
	if not await _wait_for(_in_route, "route start from host", 60.0):
		return
	scene = get_tree().current_scene
	if not await _wait_for(func() -> bool: return not scene._awaiting_snapshot, "host snapshot", 30.0):
		return
	_log("snapshot adopted; chunks %d, seed %s" % [scene.facility.loaded_chunk_count(), RoomState.seed_text])
	# RouteSyncGate keeps a joining guest on its loading screen (state tagged "syncing") until the route is ready; the
	# host ignores a syncing runner's position, so every interaction below waits for the gate to drop the guest in.
	if not await _wait_for(func() -> bool: return scene._sync_gate == null, "route sync gate", RouteSyncGate.TIMEOUT_SECONDS):
		return
	_log("route sync gate finished")
	if is_late:
		var relay_text := _read("relay.txt").split("|")
		var claimed: bool = not scene.world_state.pickup_available(relay_text[0])
		if not claimed:
			_fail("late joiner snapshot lacks the claimed relay")
			return
		_write("late_done.txt", "relay %s already claimed" % relay_text[0])
		print("COOP LATE DONE")
		await get_tree().create_timer(1.0).timeout
		get_tree().quit(0)
		return
	# guest: walk to the relay and take it
	if not await _wait_for(func() -> bool: return _read("relay.txt") != "", "relay target", 40.0):
		return
	var parts := _read("relay.txt").split("|")
	var relay_id := String(parts[0])
	scene.player.global_position = Vector3(float(parts[1]), 0.05, float(parts[2]))
	scene.facility.refresh_at_tracked_player()
	for _i in 20:
		await get_tree().process_frame
	scene._request_streamed_pickup(scene.player, relay_id, "relay", "")
	if not await _wait_for(func() -> bool: return not scene.world_state.pickup_available(relay_id),
			"relay claim echoed back", 30.0):
		return
	_log("relay %s claimed and the claim reached this guest" % relay_id)
	if not await _wait_for(func() -> bool: return scene._hunter_views.size() > 0, "hunters replicated", 40.0):
		return
	_write("guest_hunters.txt", str(scene._hunter_views.size()))
	_log("%d hunters visible on the guest" % scene._hunter_views.size())
	if not await _wait_for(func() -> bool: return _read("late_done.txt") != "", "late joiner", 90.0):
		return
	# drop the connection abruptly: the host stays up, the guest must rejoin by itself
	var old_peer: MultiplayerPeer = multiplayer.multiplayer_peer
	old_peer.close()
	RoomState._on_server_disconnected()
	if not await _wait_for(func() -> bool: return RoomState.reconnect_active, "reconnect grace", 5.0):
		return
	_log("connection dropped; reconnecting")
	if not await _wait_for(func() -> bool: return not RoomState.reconnect_active and RoomState.online \
			and RoomState.peers.size() >= 2, "reconnect", 30.0):
		return
	_write("guest_reconnected.txt", "1")
	_log("reconnected to the same route")
	if not await _wait_for(func() -> bool: return GameState.relays_collected >= 0 and not scene._awaiting_snapshot,
			"snapshot after reconnect", 30.0):
		return
	scene = get_tree().current_scene
	var hunter_emote_seen := func() -> bool:
		for view_value in scene._hunter_views.values():
			var view := view_value as HunterView3D
			if view != null and view._emote_index == HunterEmoteCatalog.SMUG:
				return true
		return false
	if not await _wait_for(hunter_emote_seen, "the host's hunter emote", 30.0):
		return
	_write("guest_saw_hunter_emote.txt", "smug")
	_log("saw the host's hunter emote")
	# -- waypoints --------------------------------------------------------------
	if not await _wait_for(func() -> bool: return _read("wp_host.txt") != "", "host waypoint", 30.0):
		return
	if not await _wait_for(func() -> bool: return scene.world_state.waypoints.has_for(1), "the host's pin on the guest", 20.0):
		return
	var wp_level: int = scene.facility.current_level()
	scene._place_waypoint_at(Vector2(24.5, 30.5), wp_level)
	await get_tree().create_timer(.4).timeout   # the host rate-limits one change per player per 150 ms
	scene._place_waypoint_at(Vector2(26.5, 34.5), wp_level)
	var own_id := multiplayer.get_unique_id()
	if not await _wait_for(func() -> bool:
			var own: Dictionary = scene.world_state.waypoints.get_for(own_id)
			return not own.is_empty() and (own["at"] as Vector2).is_equal_approx(Vector2(26.5, 34.5)),
			"the guest's replacement pin to come back from the host", 20.0):
		return
	if scene.world_state.waypoints.by_peer.size() != 2:
		_fail("guest sees %d waypoints, expected 2 (one per player)" % scene.world_state.waypoints.by_peer.size())
		return
	_write("guest_wp.txt", "26.5|34.5")
	if not await _wait_for(func() -> bool: return _read("wp_ok.txt") != "", "host waypoint verdict", 20.0):
		return
	_log("waypoints replicated: own pin replaced, the host's pin visible")
	scene._resolve_capture_outcome(HunterRoster.DEFAULT_ID)
	if not await _wait_for(func() -> bool: return scene.player.spectator_mode, "guest to spectate", 10.0):
		return
	_log("guest caught -> spectator")
	_write("guest_spectating.txt", "1")
	if not await _wait_for(func() -> bool: return not scene.player.spectator_mode, "revive from host", 20.0):
		return
	_write("guest_revived.txt", "1")
	_log("revived when the host restarted the run")
	if not await _wait_for(func() -> bool: return _read("host_spectating.txt") != "", "host to spectate", 30.0):
		return
	if scene.player.spectator_mode or scene._death_screen_open:
		_fail("guest dragged into spectating by host death")
		return
	_log("host is spectating; guest still alive")
	await get_tree().create_timer(2.0).timeout
	scene._resolve_capture_outcome(HunterRoster.DEFAULT_ID)
	if not await _wait_for(func() -> bool: return scene.player.spectator_mode, "guest to spectate again", 10.0):
		return
	if not await _wait_for(func() -> bool: return not scene.player.spectator_mode, "revive after wipe", 20.0):
		return
	_write("guest_revived2.txt", "1")
	_log("party wipe ended the run; guest revived on restart")
	if not await _wait_for(func() -> bool: return _read("host_done.txt") != "", "host finish", 40.0):
		return
	print("COOP GUEST DONE")
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - started_msec > int(TIMEOUT_SECONDS * 1000.0) + 60000:
		_fail("global timeout")
