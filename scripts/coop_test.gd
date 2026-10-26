extends Node

## Real host + guest co-op session through the local backend, one headless
## process per role. Driven by scripts/coop_test.sh.
##
##   godot --headless --path . res://scenes/coop_test.tscn -- ROLE --backend=URL --dir=DIR [--port=N]
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
	return current != null and current.scene_file_path == "res://scenes/infinite_route_test.tscn" \
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

func _run_host() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
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
	RoomState.create_local(RoomState.Mode.DEFAULT)
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
	if not await _wait_for(func() -> bool: return _read("host_done.txt") != "", "host finish", 40.0):
		return
	print("COOP GUEST DONE")
	get_tree().quit(0)


func _process(_delta: float) -> void:
	if Time.get_ticks_msec() - started_msec > int(TIMEOUT_SECONDS * 1000.0) + 60000:
		_fail("global timeout")
