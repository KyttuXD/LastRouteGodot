extends RefCounted

## Co-op sync over a bad link (live rooms, 2026-10-28: "syncing and interactions are horrible").
##
## A real ENet pair talks through a UDP proxy adding 75 ms each way (150 ms RTT) +-10 ms jitter and 5% loss each way:
##   - discrete events (reliable, channel 0) all arrive, in order;
##   - the 20 Hz runner state keeps flowing while those events are being resent (its own channel); the same link with
##     the state forced back onto channel 0 -- how every RPC was sent before -- is measured alongside for comparison;
##   - a guest's door request reaches the host (it was missing from the host's allowlist) and freshens its position;
## and offline:
##   - every request_interaction() call site in game/ names a "what" the host accepts;
##   - RemoteMotion draws a jittery, lossy 20 Hz stream without stalls, lurches or wall-sliding teleports.
##
##   godot4 --headless res://tests/scenes/validate.tscn -- coop_lossy

var PORT := 28463 + int(OS.get_environment("VALIDATE_PORT_OFFSET")) * 4
var PROXY_PORT := PORT + 1

const ONE_WAY_MS := 75
const JITTER_MS := 10
const LOSS := 0.05

var _failures := 0
var _host: Node


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_host = host
	_requests_allowed()
	_protocol()
	await _world_admission()
	_world_auth_retry()
	_motion()
	await _sync_gate()
	await _start_gate()
	await _start_gate_sliced()
	await _lossy_link()
	await _gray_binding()
	return _failures


## Every request_interaction({"what": ...}) in game/ is on RemotePlayers.GUEST_INTERACTIONS (doors were not).
## Build/protocol handshake: different RPC/world revisions and untagged hosts are refused.
func _protocol() -> void:
	var mine := NetProtocol.fingerprint()
	_expect(mine.length() == 8 and mine == NetProtocol.fingerprint(), "the protocol fingerprint is not a stable 8-hex value (%s)" % mine)
	_expect(NetProtocol.mismatch(mine).is_empty(), "a host on this build was refused")
	_expect(not NetProtocol.mismatch("").is_empty(), "an unversioned host bypassed world compatibility")
	var other_world := NetProtocol.fingerprint_for_generation(NetProtocol.WorldGenerationVersion.REVISION + 1)
	_expect(other_world != mine and not NetProtocol.mismatch(other_world).is_empty(),
		"a different generator revision with identical RPC tables was allowed")
	var refused := NetProtocol.mismatch("deadbeef")
	_expect(refused == "BUILD MISMATCH // HOST DEADBEEF YOU %s // UPDATE" % mine.to_upper(), "mismatch message: %s" % refused)
	# the fingerprint covers the RPC tables: a renamed / added RPC on RemotePlayers changes it
	var config: Dictionary = (load("res://game/network/remote_players.gd") as Script).get_rpc_config()
	_expect(config.has("_place") and config.has("_wire_profile"), "the fingerprint is not reading RemotePlayers' RPC table")


## Real transport admission: no RPC/scene peer exists before compatibility.
## These APIs are isolated from RoomState's live multiplayer and never host a game.
func _world_admission() -> void:
	for variant in ["match", "mismatch", "missing", "old_host", "old_guest"]:
		var server := ENetMultiplayerPeer.new()
		var client := ENetMultiplayerPeer.new()
		var mp_a := SceneMultiplayer.new()
		var mp_b := SceneMultiplayer.new()
		var events := {"host": 0, "guest": 0}
		mp_a.peer_connected.connect(func(_id: int) -> void: events["host"] += 1)
		mp_b.peer_connected.connect(func(_id: int) -> void: events["guest"] += 1)
		if variant != "old_host":
			RoomState.configure_world_auth(mp_a)
		if variant != "old_guest":
			RoomState.configure_world_auth(mp_b)
		if variant in ["mismatch", "missing"]:
			# Disconnect the exact stored Callable: reconstructing a bound static
			# method through the autoload can produce a different Callable identity.
			for connection in mp_b.peer_authenticating.get_connections():
				mp_b.peer_authenticating.disconnect(connection["callable"])
			_expect(mp_b.peer_authenticating.get_connections().is_empty(),
				"negative admission fixture retained a valid fingerprint sender")
			if variant == "mismatch":
				mp_b.peer_authenticating.connect(func(id: int) -> void:
					mp_b.send_auth(id, "wrong-generation".to_utf8_buffer()))
		var port := PORT + 2
		if server.create_server(port, 2) != OK or client.create_client("127.0.0.1", port) != OK:
			_fail("could not create world admission fixture")
			server.close()
			client.close()
			return
		mp_a.multiplayer_peer = server
		mp_b.multiplayer_peer = client
		# An id not in this API's authenticating set cannot approve a peer.
		RoomState._receive_world_auth(999, NetProtocol.fingerprint().to_utf8_buffer(), mp_a)
		var deadline := Time.get_ticks_msec() + 4000
		while Time.get_ticks_msec() < deadline:
			mp_a.poll()
			mp_b.poll()
			if variant == "match" and events["host"] == 1 and events["guest"] == 1:
				break
			await _host.get_tree().create_timer(0.01).timeout
		if variant == "match":
			_expect(events["host"] == 1 and events["guest"] == 1, "same-generation direct peers failed admission")
		else:
			if variant != "old_host":
				_expect(events["host"] == 0 and mp_a.get_peers().is_empty(),
					"new host admitted %s before compatibility" % variant)
			if variant != "old_guest":
				_expect(events["guest"] == 0 and mp_b.get_peers().is_empty(),
					"new guest admitted %s before compatibility" % variant)
		server.close()
		client.close()
		mp_a.multiplayer_peer = null
		mp_b.multiplayer_peer = null
		# Break fixture callback references; none outlive this transport attempt.
		mp_a.auth_callback = Callable()
		mp_b.auth_callback = Callable()
		for api in [mp_a, mp_b]:
			for connection in api.peer_authenticating.get_connections():
				api.peer_authenticating.disconnect(connection["callable"])


func _world_auth_retry() -> void:
	if RoomState.get("_peer") != null:
		_fail("auth retry fixture requires an offline RoomState")
		return
	var saved := {}
	for key in ["_peer", "_world_auth_mismatch_peer", "connecting", "online", "is_host", "status_message",
			"_connect_started_msec", "_relay_status", "_directory_status", "_primary_create_fallback_enabled",
			"reconnect_active", "_reconnect_generation", "_reconnect_deadline_msec", "_reconnect_next_lookup_msec",
			"_reconnect_room_received", "_reconnect_request_in_flight"]:
		saved[key] = RoomState.get(key)
	var failed_peer := OfflineMultiplayerPeer.new()
	var replacement := OfflineMultiplayerPeer.new()
	var deadline := Time.get_ticks_msec() + 5000
	RoomState.set("_peer", failed_peer)
	RoomState.set("_world_auth_mismatch_peer", null)
	RoomState.connecting = true
	RoomState.is_host = false
	RoomState.reconnect_active = true
	RoomState.set("_reconnect_deadline_msec", deadline)
	RoomState.set("_reconnect_generation", 40)
	RoomState._finish_world_auth_failure(failed_peer)
	_expect(RoomState.reconnect_active and RoomState.get("_peer") == null \
		and int(RoomState.get("_reconnect_deadline_msec")) == deadline \
		and int(RoomState.get("_reconnect_generation")) == 41,
		"auth timeout ended reconnect early or extended its original deadline")
	RoomState.set("_peer", replacement)
	RoomState.connecting = true
	RoomState._finish_world_auth_failure(failed_peer)
	_expect(RoomState.get("_peer") == replacement and RoomState.connecting \
		and int(RoomState.get("_reconnect_deadline_msec")) == deadline,
		"stale auth timeout changed a replacement transport or deadline")
	RoomState._on_world_auth_mismatch(2)
	_expect(RoomState.get("_world_auth_mismatch_peer") == null, "a non-host peer marked guest admission mismatched")
	RoomState._on_world_auth_mismatch(1)
	_expect(RoomState.get("_world_auth_mismatch_peer") == replacement,
		"explicit host mismatch was not distinguished from auth timeout")
	for key in saved:
		RoomState.set(key, saved[key])


func _requests_allowed() -> void:
	var call := RegEx.new()
	call.compile("request_interaction\\(\\s*(\\{[^}]*\\}|[a-z_]+)")
	var literal := RegEx.new()
	literal.compile("\"what\"\\s*:\\s*\"([a-z_]+)\"")
	var seen := {}
	for path in _gd_files("res://game") + _gd_files("res://dev/playtest"):
		var source := FileAccess.get_file_as_string(path)
		for found in call.search_all(source):
			var argument := found.get_string(1)
			var names: Array = literal.search_all(argument)
			if names.is_empty():   # a variable: its literal is just above the call
				var lines := source.substr(0, found.get_start()).split("\n")
				var back := "\n".join(lines.slice(maxi(0, lines.size() - 15)))
				var above: Array = literal.search_all(back)
				names = above.slice(above.size() - 1) if not above.is_empty() else []
			for name_match in names:
				seen[name_match.get_string(1)] = path
	_expect(seen.size() >= 15, "only %d interaction kinds found; the call-site scan is not reading game/" % seen.size())
	for what in seen:
		_expect(RemotePlayers.GUEST_INTERACTIONS.has(what),
			"%s requests \"%s\", which the host drops (not in RemotePlayers.GUEST_INTERACTIONS)" % [seen[what], what])


func _gd_files(root: String) -> Array[String]:
	var result: Array[String] = []
	var dir := DirAccess.open(root)
	if dir == null:
		return result
	for file in dir.get_files():
		if file.ends_with(".gd"):
			result.append(root.path_join(file))
	for sub in dir.get_directories():
		result.append_array(_gd_files(root.path_join(sub)))
	return result


## A runner walking a square at 4 m/s, sampled at 20 Hz, delivered with 75 +-40 ms delay and 5% loss, drawn at 60 fps.
func _motion() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var speed := 4.0
	var truth := func(t_ms: float) -> Vector3:
		var d := fmod(t_ms / 1000.0 * speed, 40.0)
		if d < 10.0: return Vector3(d, 0, 0)
		if d < 20.0: return Vector3(10, 0, d - 10.0)
		if d < 30.0: return Vector3(30.0 - d, 0, 10)
		return Vector3(0, 0, 40.0 - d)
	var arrivals := []   # [local arrival ms, sender ms]
	var clock_skew := 123456.0   # the sender's clock is nowhere near ours
	for i in 400:
		var sent := i * 50.0
		if rng.randf() < LOSS:
			continue
		arrivals.append([sent + 75.0 + rng.randf_range(-40.0, 40.0), sent])
	arrivals.sort_custom(func(a, b): return a[0] < b[0])
	var motion := RemoteMotion.new()
	var old_at := Vector3.ZERO
	var next := 0
	var worst_step := 0.0
	var worst_old_step := 0.0
	var worst_error := 0.0
	var accepted := 0
	var frame_ms := 1000.0 / 60.0
	var t := 0.0
	while t < 20_000.0:
		while next < arrivals.size() and arrivals[next][0] <= t:
			if motion.push(arrivals[next][1] + clock_skew, arrivals[next][0], truth.call(arrivals[next][1]), 0.0):
				accepted += 1
			next += 1
		var pose := motion.sample(t)
		if not pose.is_empty() and t > 1000.0:
			var at: Vector3 = pose["at"]
			worst_error = maxf(worst_error, at.distance_to(truth.call(t - RemoteMotion.DELAY_MS - 75.0)))
			if t > 1100.0:
				worst_step = maxf(worst_step, at.distance_to(motion.get_meta("last", at)))
			motion.set_meta("last", at)
			# the old drawing: lerp toward the newest sample at INTERPOLATION_SPEED
			var newest: Vector3 = truth.call(arrivals[maxi(next - 1, 0)][1])
			var stepped := old_at.lerp(newest, clampf(frame_ms / 1000.0 * RemotePlayers.INTERPOLATION_SPEED, 0.0, 1.0))
			if t > 1100.0:
				worst_old_step = maxf(worst_old_step, stepped.distance_to(old_at))
			old_at = stepped
		t += frame_ms
	var per_frame := speed * frame_ms / 1000.0
	print("  motion    20 Hz, 75+-40 ms, 5%% loss: worst frame step %.3f m (old lerp %.3f m, true %.3f m); worst lag error %.2f m; %d samples kept, reordered ones dropped" % [
		worst_step, worst_old_step, per_frame, worst_error, accepted])
	_expect(worst_step < per_frame * 2.5, "interpolated body lurched %.3f m in one frame (walking is %.3f)" % [worst_step, per_frame])
	_expect(worst_error < 1.5, "interpolated body was %.2f m off the delayed true path" % worst_error)

	# A respawn / stairs / anti-cheat snap is a step, never a slide through everything in between.
	var jump := RemoteMotion.new()
	jump.push(0.0, 0.0, Vector3.ZERO, 0.0)
	jump.push(50.0, 50.0, Vector3(20, 0, 0), 0.0)
	for probe in [60.0, 100.0, 130.0, 160.0, 400.0]:
		var at: Vector3 = jump.sample(probe)["at"]
		_expect(at.x < 0.01 or at.x > 19.99, "a 20 m jump was drawn mid-slide at x=%.1f" % at.x)
	_expect(not jump.push(40.0, 70.0, Vector3.ONE, 0.0), "a sample older than the newest was accepted")
	# Extrapolation stops after MAX_EXTRAPOLATE_MS: a peer that stops sending does not walk off into a wall.
	var stop := RemoteMotion.new()
	for i in 5:
		stop.push(i * 50.0, i * 50.0, Vector3(i * 0.2, 0, 0), 0.0)
	var far: Vector3 = stop.sample(5000.0)["at"]
	_expect(far.x <= 0.8 + 0.2 * RemoteMotion.MAX_EXTRAPOLATE_MS / 50.0 + 0.001, "extrapolated past its cap to x=%.2f" % far.x)


## Solo / host entry (RouteStartGate, load lag): a route opened by the loading screen holds the runner on
## the loading overlay, frozen with physics off and not a hunter target, until the nearby facility is built and frames are
## smooth, then lets her in; a scene built directly (validators, restarts) is never gated; the gate always ends.
func _start_gate() -> void:
	var gate := RouteStartGate.new()
	_expect(not gate.tick(1.0 / 60.0, false, true), "the start gate let the runner in before the facility was built")
	for i in RouteStartGate.SMOOTH_FRAMES - 1:
		gate.tick(1.0 / 60.0, true, true)
	_expect(not gate.world_ready(), "the start gate was ready before %d smooth frames" % RouteStartGate.SMOOTH_FRAMES)
	gate.tick(.2, true, true)   # a hitch restarts the count
	_expect(gate.smooth == 0, "a %.0f ms hitch did not restart the smooth-frame count" % 200.0)
	for i in RouteStartGate.SMOOTH_FRAMES:
		gate.tick(1.0 / 60.0, true, false)
	_expect(gate.world_ready() and not gate.tick(1.0 / 60.0, true, false), "the start gate let a runner in before she landed")
	_expect(gate.tick(1.0 / 60.0, true, true), "the start gate held a runner on built floor with the route ready")
	var stuck := RouteStartGate.new()
	stuck.tick(RouteStartGate.MAX_SECONDS - .1, false, false)
	_expect(not stuck.tick(.05, false, false), "the start gate gave up early")
	_expect(stuck.tick(.1, false, false), "the start gate can hold a runner forever")
	_start_gate_progress_mode()

	RoomState.create_local(RoomState.Mode.DEFAULT)
	OS.set_environment("LR_SLICED_STARTUP", "0")   # this route runs the legacy (synchronous opening, MAX_SECONDS) gate
	# built directly: no gate
	RouteLoadingScreen.entering = false
	var direct: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	_host.get_tree().root.add_child(direct)
	await _host.get_tree().process_frame
	_expect(direct.get("_start_gate") == null, "a route scene built directly (not through the loading screen) was gated")
	direct.queue_free()
	await _host.get_tree().process_frame
	# opened by the loading screen: gated, then released
	RouteLoadingScreen.entering = true
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	_host.get_tree().root.add_child(route)
	_expect(not RouteLoadingScreen.entering, "the route did not consume the loading screen's entry flag")
	_expect(not route.get("facility").sliced_startup, "a route entered with LR_SLICED_STARTUP=0 sliced its opening")
	var player := route.get("player") as PlayerController3D
	_expect(route.get("_start_gate") != null and player.input_frozen and not player.is_physics_processing(),
		"a solo route opened by the loading screen let the runner move before the world was ready")
	var overlay := route.get("_sync_overlay") as RouteLoadingScreen
	_expect(overlay != null and overlay.visible, "the start gate does not show the loading screen")
	_expect(bool((route.call("_streamed_state_overrides") as Dictionary).get("syncing", false)),
		"a runner still on the start gate is a hunter target")
	var waited := 0.0
	while route.get("_start_gate") != null and waited < RouteStartGate.MAX_SECONDS + 3.0:
		await _host.get_tree().process_frame
		waited += _host.get_process_delta_time()
		if route.get("_start_gate") != null:
			_expect(player.input_frozen, "the runner could move while the start gate held (%.2f s)" % waited)
	_expect(route.get("_start_gate") == null, "the start gate never let the runner in")
	_expect(not player.input_frozen and player.is_physics_processing() and not overlay.visible,
		"after the start gate the runner is still frozen or the loading screen is still up")
	_expect(route.call("_streamed_state_overrides").get("syncing", true) == false, "after the start gate she is still not a target")
	print("  start_gate  ready after %.2f s (%d chunks built, smooth frames, on floor)" % [waited, route.get("facility").loaded_chunk_count()])
	route.queue_free()
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
	OS.unset_environment("LR_SLICED_STARTUP")


## The start gate's progress mode (the sliced opening): MAX_SECONDS no longer ends it from the start, only a stall, the hard
## cap, or MAX_SECONDS counted from the moment the world was built. The legacy 3-argument gate is covered above.
func _start_gate_progress_mode() -> void:
	var moving := RouteStartGate.new()
	_expect(not moving.tick(RouteStartGate.MAX_SECONDS + 5.0, false, false, 1), "a progressing opening was cut off at MAX_SECONDS")
	_expect(not moving.tick(RouteStartGate.MAX_SECONDS + 5.0, false, false, 2), "a progressing opening was cut off past MAX_SECONDS")
	var still := RouteStartGate.new()
	still.tick(1.0, false, false, 5)   # first sight of the counter
	_expect(not still.tick(RouteStartGate.STALL_SECONDS - 1.1, false, false, 5), "a stalled opening was given up on before STALL_SECONDS")
	_expect(still.tick(1.2, false, false, 5), "an opening with no progress for STALL_SECONDS held the runner")
	var capped := RouteStartGate.new()
	var opened := false
	var progress := 0
	while capped.elapsed < RouteStartGate.HARD_SECONDS + 1.0 and not opened:
		progress += 1   # always moving, never built
		opened = capped.tick(1.0, false, false, progress)
	_expect(opened and capped.elapsed <= RouteStartGate.HARD_SECONDS + 1.0, "the hard cap never opened a progressing, never-built opening")
	# built, but every frame is a hitch (> SMOOTH_FRAME_MS): the legacy wait, counted from the moment it was built
	var hitching := RouteStartGate.new()
	hitching.tick(20.0, false, false, 1)
	var open_at := 0.0
	for index in 40:
		if hitching.tick(1.0, true, false, 2 + index):
			open_at = hitching.built_for
			break
	_expect(open_at >= RouteStartGate.MAX_SECONDS and open_at <= RouteStartGate.MAX_SECONDS + 1.0,
		"a built world with hitching frames opened %.1f s after it was built, not at MAX_SECONDS" % open_at)
	# a smooth rise counts as progress: frames that never move the counter but are smooth keep the stall at zero
	var smooth := RouteStartGate.new()
	smooth.tick(RouteStartGate.STALL_SECONDS - 1.0, false, false, 9)
	for index in 3:
		smooth.tick(1.0 / 60.0, true, false, 9)   # smooth frames: smooth rises, the stall resets
	_expect(smooth.stall == 0.0, "a smooth-frame rise did not count as progress")
	# the linked storeys no longer hold the gate once the runner's own window has been built for LINKED_WAIT_SECONDS
	var linked := RouteStartGate.new()
	var linked_done := false
	for index in 600:
		linked_done = linked.tick(1.0 / 60.0, false, true, 1 + index, true)
		if linked_done:
			break
	_expect(linked_done and linked.elapsed <= RouteStartGate.LINKED_WAIT_SECONDS + 2.0,
		"the linked storeys held a built window for %.1f s" % linked.elapsed)


## A route entered through the loading screen with LR_SLICED_STARTUP=1 builds its opening in slices behind the gate and
## opens it with the runner's whole 3x3 in place. Timing-based: the wait bound is STALL_SECONDS + 30 s of slack for a busy
## machine; re-run once on a timeout before calling it a regression. A route built directly never slices without the flag.
func _start_gate_sliced() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	OS.unset_environment("LR_SLICED_STARTUP")
	RouteLoadingScreen.entering = false
	var plain: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	_host.get_tree().root.add_child(plain)
	await _host.get_tree().process_frame
	_expect(not plain.get("facility").sliced_startup and plain.get("_start_gate") == null,
		"a plain route (no loading-screen entry, no flag) slices its opening")
	plain.queue_free()
	await _host.get_tree().process_frame
	RouteLoadingScreen.entering = true
	var unflagged: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	_host.get_tree().root.add_child(unflagged)
	_expect(not unflagged.get("facility").sliced_startup, "a loading-screen entry without the flag slices its opening (it is opt-in)")
	unflagged.queue_free()
	await _host.get_tree().process_frame
	OS.set_environment("LR_SLICED_STARTUP", "1")
	RouteLoadingScreen.entering = true
	var route: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	_host.get_tree().root.add_child(route)
	var facility := route.get("facility") as StreamedFacilityView3D
	var player := route.get("player") as PlayerController3D
	_expect(facility.sliced_startup and route.get("_start_gate") != null, "LR_SLICED_STARTUP=1 did not slice a gated route entry")
	_expect(facility.loaded_chunk_count() == 1, "the sliced route built %d chunks inside begin()" % facility.loaded_chunk_count())
	var overlay := route.get("_sync_overlay") as RouteLoadingScreen
	var bar := overlay.get("_progress") as ProgressBar if overlay != null else null
	var waited := 0.0
	var frames := 0
	var longest := 0.0
	var started := Time.get_ticks_msec()
	var coords_at_open := -1
	var complete_at_open := false
	var bar_mid := false
	while route.get("_start_gate") != null and waited < RouteStartGate.STALL_SECONDS + 30.0:
		await _host.get_tree().process_frame
		var dt := _host.get_process_delta_time()
		waited += dt
		longest = maxf(longest, dt)
		frames += 1
		if bar != null and route.get("_start_gate") != null and bar.value > 0.0 and bar.value < 100.0:
			bar_mid = true
		if route.get("_start_gate") != null:
			_expect(player.input_frozen, "the runner could move while the sliced start gate held")
		else:
			coords_at_open = facility.loaded_horizontal_coords().size()
			complete_at_open = facility.startup_window_complete()
	_expect(route.get("_start_gate") == null, "the sliced start gate never let the runner in (%.1f s)" % waited)
	_expect(coords_at_open == 9 and complete_at_open,
		"the sliced start gate opened with %d of 9 same-storey chunks (window complete %s)" % [coords_at_open, complete_at_open])
	_expect(bar == null or bar_mid, "the loading bar never showed a partial build while the opening was building")
	print("  start_gate_sliced  opened after %d frames, %.2f s (%.0f ms wall), longest frame %.0f ms, %d chunks, bar showed progress %s" % [
		frames, waited, float(Time.get_ticks_msec() - started), longest * 1000.0, facility.loaded_chunk_count(), bar_mid])
	route.queue_free()
	await _host.get_tree().process_frame
	await _host.get_tree().process_frame
	OS.unset_environment("LR_SLICED_STARTUP")
	RouteLoadingScreen.entering = false


## A joining guest stays on the loading screen through every RouteSyncGate step, is offered LEAVE after the timeout,
## and while it syncs it is never a hunter target or in reach of anything on the host.
func _sync_gate() -> void:
	var gate := RouteSyncGate.new()
	_expect(gate.first_unmet([true, false, true, true], false, 0.1) == 1, "the gate skipped an unmet host-snapshot step")
	_expect(gate.first_unmet([true, true, true, true], false, 0.1) == RouteSyncGate.STEPS.size() - 1,
		"the gate released before the runner settled at its spawn")
	_expect(gate.first_unmet([true, true, true, true], true, 0.1) == RouteSyncGate.STEPS.size(),
		"the gate held a runner standing on built floor with everything synced")
	var slow := RouteSyncGate.new()
	for i in 12:
		slow.first_unmet([true, true, true, true], false, 0.1)
	_expect(slow.first_unmet([true, true, true, true], false, 0.1) == RouteSyncGate.STEPS.size(),
		"a runner that never touches floor is held forever")
	_expect(RouteSyncGate.label(2) == "SYNCING ROUTE 3/5 // NEARBY FACILITY", "sync label reads %s" % RouteSyncGate.label(2))
	gate.tick(RouteSyncGate.TIMEOUT_SECONDS - 0.1)
	_expect(not gate.timed_out(), "the gate timed out early")
	gate.tick(0.2)
	_expect(gate.timed_out(), "the gate never times out")

	# a host on an older build (no wire tag): the guest gets in after OLD_HOST_SECONDS instead of waiting forever
	var old := RouteSyncGate.new()
	old.tick(RouteSyncGate.OLD_HOST_SECONDS - 0.5)
	_expect(not old.old_host(false), "an older host was given up on too early")
	old.tick(1.0)
	_expect(old.old_host(false), "a guest of an older host waits forever (KTMXN)")
	_expect(not old.old_host(true), "a current host's slow sync was cut short by the older-host fallback")

	MouseLock.release_all()
	MouseLock.set_gameplay_capture(true)
	var screen := (load(RoomState.ROUTE_LOADING_SCENE) as PackedScene).instantiate() as RouteLoadingScreen
	screen.auto_start = false
	_host.add_child(screen)
	screen.show_sync_step(2, RouteSyncGate.STEPS.size())
	var phase := screen.find_child("RouteLoadPhase", true, false) as Label
	var leave := screen.find_child("SyncLeaveButton", true, false) as Button
	_expect(screen.visible and phase != null and phase.text == RouteSyncGate.label(2),
		"the loading screen does not show the sync step (%s)" % (phase.text if phase != null else "no phase label"))
	_expect(MouseLock.cursor_visible(), "the mouse stays locked on the loading / sync screen (LEAVE cannot be clicked)")
	_expect(leave != null and not leave.visible, "LEAVE is offered before the sync timeout")
	screen.show_sync_stuck()
	_expect(leave != null and leave.visible and leave.text == "STILL SYNCING // LEAVE", "no STILL SYNCING // LEAVE after the timeout")
	screen.dismiss()
	_expect(not screen.visible and not leave.visible, "the loading screen stayed up after the sync finished")
	_expect(not MouseLock.cursor_visible(), "the mouse was not handed back to gameplay after the loading screen")
	screen.show_waiting_for_snapshot()   # rejoin / route load use the same screen
	_expect(MouseLock.cursor_visible(), "the mouse stays locked while waiting for the host snapshot")
	screen.queue_free()
	await _host.get_tree().process_frame
	_expect(not MouseLock.cursor_visible(), "a freed loading screen kept its claim on the mouse")
	MouseLock.release_all()

	var remotes := RemotePlayers.new()
	var now := Time.get_ticks_usec()
	remotes._states = {
		5: {"peer_id": 5, "position": Vector2(1, 0), "depth": 0, "received_usec": now, "syncing": true},
		6: {"peer_id": 6, "position": Vector2(9, 0), "depth": 0, "received_usec": now},
	}
	var ids := remotes.target_states({}).map(func(t): return int(t.get("peer_id", 0)))
	_expect(not 5 in ids and 6 in ids, "a syncing guest is still in the host's targets (%s)" % [ids])
	var picked := remotes.best_target(Vector2.ZERO, {}, 0)
	_expect(int(picked.get("peer_id", 0)) != 5, "a hunter picked the syncing guest")
	_expect(remotes.has_fresh_state(6) and not remotes.has_fresh_state(7), "has_fresh_state is wrong")
	remotes.free()


## UDP proxy: client <-> proxy <-> server with delay, jitter and loss in both directions.
class LossyProxy:
	var listen := PacketPeerUDP.new()
	var upstream := PacketPeerUDP.new()
	var server_port := 0
	var client_ip := ""
	var client_port := 0
	var queue := []   # [due_ms, to_server, bytes]
	var rng := RandomNumberGenerator.new()
	var dropped := 0
	var passed := 0

	func open(proxy_port: int, target_port: int) -> bool:
		rng.seed = 5
		server_port = target_port
		if listen.bind(proxy_port, "127.0.0.1", 1 << 20) != OK:
			return false
		if upstream.bind(0, "127.0.0.1", 1 << 20) != OK:
			return false
		upstream.set_dest_address("127.0.0.1", server_port)
		return true

	func poll() -> void:
		var now := Time.get_ticks_msec()
		while listen.get_available_packet_count() > 0:
			var packet := listen.get_packet()
			client_ip = listen.get_packet_ip()
			client_port = listen.get_packet_port()
			_enqueue(now, true, packet)
		while upstream.get_available_packet_count() > 0:
			_enqueue(now, false, upstream.get_packet())
		var keep := []
		for entry in queue:
			if entry[0] > now:
				keep.append(entry)
			elif entry[1]:
				upstream.put_packet(entry[2])
			elif client_port > 0:
				listen.set_dest_address(client_ip, client_port)
				listen.put_packet(entry[2])
		queue = keep

	func _enqueue(now: int, to_server: bool, packet: PackedByteArray) -> void:
		if rng.randf() < LOSS:
			dropped += 1
			return
		passed += 1
		queue.append([now + ONE_WAY_MS + rng.randi_range(-JITTER_MS, JITTER_MS), to_server, packet])

	func close() -> void:
		listen.close()
		upstream.close()


func _lossy_link() -> void:
	var tree := _host.get_tree()
	var proxy := LossyProxy.new()
	if not proxy.open(PROXY_PORT, PORT):
		_fail("could not open the lossy UDP proxy on %d" % PROXY_PORT)
		return
	var server := ENetMultiplayerPeer.new()
	var client := ENetMultiplayerPeer.new()
	if server.create_server(PORT, 4) != OK or client.create_client("127.0.0.1", PROXY_PORT) != OK:
		_fail("could not open the ENet pair on %d/%d" % [PORT, PROXY_PORT])
		proxy.close()
		return
	var mp_a := SceneMultiplayer.new()
	var mp_b := SceneMultiplayer.new()
	var side_a := Node.new()
	side_a.name = "LossyA"
	var side_b := Node.new()
	side_b.name = "LossyB"
	tree.root.add_child(side_a)
	tree.root.add_child(side_b)
	tree.set_multiplayer(mp_a, side_a.get_path())
	tree.set_multiplayer(mp_b, side_b.get_path())
	mp_a.multiplayer_peer = server
	mp_b.multiplayer_peer = client
	var a := RemotePlayers.new()
	a.name = "Remotes"
	side_a.add_child(a)
	var b := RemotePlayers.new()
	b.name = "Remotes"
	side_b.add_child(b)
	var was_host := RoomState.is_host
	RoomState.is_host = false   # fixtures act as guests (GuestGuard would judge the fixture's moves)

	for frame in 600:
		proxy.poll()
		if mp_a.get_peers().size() == 1 and client.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
			break
		await tree.process_frame
	_expect(mp_a.get_peers().size() == 1, "ENet never connected through the lossy proxy")
	if mp_a.get_peers().size() == 1:
		var b_id := mp_b.get_unique_id()
		# Both learn each other's wire version first (full states, then hot + profile).
		var warm := 0
		while warm < 240 and not (a._wire_peers.has(b_id) and b._wire_peers.has(1)):
			proxy.poll()
			if warm % 3 == 0:
				_send(a, 0.0)
				_send(b, 0.0)
			warm += 1
			await tree.process_frame
		_expect(a._wire_peers.has(b_id) and b._wire_peers.has(1), "the peers never agreed on the wire version")
		var shared := await _burst(tree, proxy, a, b, b_id, NetChannels.EVENTS, 0)
		var split := await _burst(tree, proxy, a, b, b_id, NetChannels.STATE, 1000)
		print("  lossy     150 ms RTT, 5%% loss: state stalls >250 ms with events in flight -- shared channel 0: %d (worst %d ms), own channel: %d (worst %d ms); %d datagrams dropped" % [
			shared[0], shared[1], split[0], split[1], proxy.dropped])
		_expect(split[2] == split[3], "only %d of %d reliable events arrived" % [split[2], split[3]])
		_expect(split[4], "reliable events arrived out of order")
		# A gap is only the network's when frames kept coming: a busy test machine's own long frame is not a stall.
		# At 5% loss ENet's throttle can still drop a short run of unreliable samples now and then (seen up to ~560 ms,
		# on either channel); what must never happen is a stall long enough to freeze a runner (1 s) or a pattern of them.
		_expect(split[1] < 1000 and split[0] <= 2,
			"the runner state stalled %d ms (%d stalls over 250 ms) on its own channel (shared channel: %d ms, %d stalls; worst frame %d ms)" % [
			split[1], split[0], shared[1], shared[0], split[5]])
		await _door_request(tree, proxy, a, b, b_id)

	RoomState.is_host = was_host
	a.queue_free()
	b.queue_free()
	for frame in 3:
		proxy.poll()
		await tree.process_frame
	client.close()
	server.close()
	proxy.close()
	tree.set_multiplayer(null, side_a.get_path())
	tree.set_multiplayer(null, side_b.get_path())
	side_a.queue_free()
	side_b.queue_free()
	await tree.process_frame


## What RemotePlayers._process sends, for a fixture standing at x.
func _send(remotes: RemotePlayers, x: float) -> void:
	remotes._send_seq += 1
	remotes._send_state({"at": Vector3(x, 0, 0), "position": Vector2(x, 0), "facing_y": 0.0, "clip": "walk",
		"depth": 0, "display_name": "LOSSY", "skin": "", "inventory_free_slots": 3, "seq": remotes._send_seq,
		"sent_ms": Time.get_ticks_msec()})


## 4 s of 20 Hz state from A plus a ~600 B reliable event every 100 ms, with A's _place on `channel`.
## Returns [stalls over 250 ms, worst gap ms, events received, events sent, in order, worst frame ms].
func _burst(tree: SceneTree, proxy: LossyProxy, a: RemotePlayers, b: RemotePlayers, b_id: int, channel: int,
		first_event: int) -> Array:
	var config := {"rpc_mode": MultiplayerAPI.RPC_MODE_ANY_PEER, "call_local": false,
		"transfer_mode": MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED, "channel": channel}
	a.rpc_config("_place", config)
	b.rpc_config("_place", config)
	var received: Array[int] = []
	var on_event := func(event: Dictionary) -> void: received.append(int(event.get("n", -1)))
	b.world_event.connect(on_event)
	var padding := "x".repeat(600)
	var start := Time.get_ticks_msec()
	var last_state := 0
	var last_event := 0
	var sent := 0
	var seen_seq := int(b._last_seq.get(1, 0))
	var seen_at := start
	var stalls := 0
	var worst := 0
	var worst_frame := 0
	var frame_at := start
	while Time.get_ticks_msec() - start < 4000:
		var now := Time.get_ticks_msec()
		worst_frame = maxi(worst_frame, now - frame_at)
		frame_at = now
		if now - last_state >= 50:
			last_state = now
			_send(a, float(now - start) / 1000.0)
		if now - last_event >= 100:
			last_event = now
			a._event.rpc_id(b_id, {"what": "lossy_probe", "n": first_event + sent, "pad": padding})
			sent += 1
		proxy.poll()
		await tree.process_frame
		var seq := int(b._last_seq.get(1, 0))
		if seq != seen_seq:
			var gap := Time.get_ticks_msec() - seen_at
			if gap > 250 and Time.get_ticks_msec() - start > 300:
				stalls += 1
			if Time.get_ticks_msec() - start > 300:
				worst = maxi(worst, gap)
			seen_seq = seq
			seen_at = Time.get_ticks_msec()
	# let the last reliable resends land
	var settle := Time.get_ticks_msec()
	while received.size() < sent and Time.get_ticks_msec() - settle < 3000:
		proxy.poll()
		await tree.process_frame
	b.world_event.disconnect(on_event)
	var ordered := true
	for i in received.size():
		ordered = ordered and received[i] == first_event + i
	return [stalls, worst, received.size(), sent, ordered, worst_frame]


## B (a guest) asks to open a door; the host must accept "stream_door" and take the position the request carried.
func _door_request(tree: SceneTree, proxy: LossyProxy, a: RemotePlayers, b: RemotePlayers, b_id: int) -> void:
	var got := []
	var on_request := func(peer_id: int, event: Dictionary) -> void: got.append([peer_id, event, Time.get_ticks_msec()])
	a.interaction_requested.connect(on_request)
	var drain := Time.get_ticks_msec()
	while Time.get_ticks_msec() - drain < 400:   # nothing of the bursts still in flight when A turns host
		proxy.poll()
		await tree.process_frame
	RoomState.is_host = true   # A answers as the host; B only sends
	var stored: Dictionary = a._states.get(b_id, {})
	stored["position"] = Vector2(10, 0)
	stored["at"] = Vector3(10, 0, 0)
	stored["depth"] = 0
	var start := Time.get_ticks_msec()
	b._request_interaction.rpc_id(1, {"what": "stream_door", "door_id": "probe", "_at": Vector3(11.5, 0, 0),
		"_pos": Vector2(11.5, 0), "_depth": 0})
	b._request_interaction.rpc_id(1, {"what": "stream_door", "door_id": "far", "_at": Vector3(60, 0, 0),
		"_pos": Vector2(60, 0), "_depth": 0})
	while got.size() < 2 and Time.get_ticks_msec() - start < 3000:
		proxy.poll()
		await tree.process_frame
	var door_requests := got.size()
	var door_position = a._states.get(b_id, {}).get("position")
	# A refused request is logged on the host and handed back to the guest with its reason (no more silent drops).
	var refused := []
	var on_player_event := func(event: Dictionary) -> void:
		if String(event.get("what", "")) == "interaction_refused":
			refused.append(event)
	b.player_event.connect(on_player_event)
	b._request_interaction.rpc_id(1, {"what": "not_a_real_interaction"})
	var asked := Time.get_ticks_msec()
	while refused.is_empty() and Time.get_ticks_msec() - asked < 3000:
		proxy.poll()
		await tree.process_frame
	b.player_event.disconnect(on_player_event)
	_expect(refused.size() == 1 and String(refused[0].get("kind", "")) == "not_a_real_interaction" \
		and not String(refused[0].get("reason", "")).is_empty(), "the guest never heard why its request was refused (%s)" % [refused])
	# A burst a busy player can make (a door mashed, a pile of pickups swept) is under the rate limit.
	var before := got.size()
	for i in 12:
		b._request_interaction.rpc_id(1, {"what": "stream_door", "door_id": "mash%d" % i})
	asked = Time.get_ticks_msec()
	while got.size() < before + 12 and Time.get_ticks_msec() - asked < 3000:
		proxy.poll()
		await tree.process_frame
	_expect(got.size() == before + 12, "only %d of 12 quick door presses reached the host" % (got.size() - before))
	# A guard verdict (a gap read as a teleport) snaps the sample but never trolls or kicks a player by itself.
	a.guard.forget(b_id)
	a._guard_sample(b_id, {"at": Vector3.ZERO, "position": Vector2.ZERO, "depth": 0, "seq": 900_001})
	for i in 6:
		await tree.process_frame
		a._guard_sample(b_id, {"at": Vector3(200.0 + i * 50.0, 0, 0), "position": Vector2(200.0 + i * 50.0, 0), "depth": 0,
			"seq": 900_002 + i})
	_expect(not a.troll_peers.has(b_id), "GuestGuard put a guest into troll mode by itself")
	_expect(b_id in a.multiplayer.get_peers(), "GuestGuard kicked a guest by itself")
	RoomState.is_host = false
	a.interaction_requested.disconnect(on_request)
	_expect(door_requests == 2, "the host accepted %d of 2 guest door requests (stream_door was not allowed)" % door_requests)
	if got.size() >= 1:
		print("  lossy     guest door request reached the host in %d ms (one way %d +-%d ms)" % [
			int(got[0][2]) - start, ONE_WAY_MS, JITTER_MS])
		_expect(int(got[0][0]) == b_id and String((got[0][1] as Dictionary).get("door_id", "")) == "probe",
			"the door request arrived as %s" % [got[0]])
		_expect(not (got[0][1] as Dictionary).has("_pos"), "the request's private position keys reached the game")
	# 11.5 is 1.5 m from the last sample (taken); 60 is 50 m off (ignored, the 11.5 stands).
	_expect(door_position is Vector2 and is_equal_approx((door_position as Vector2).x, 11.5),
		"the host's view of the guest is %s, not the request's fresh 11.5 (or it took the 50 m jump)" % [door_position])


## Gray belongs to the AFK runner only (she caught active guests). One AFK guest and one active guest
## standing nearer to her: she binds to the AFK one, never targets the active one, and lets go when the AFK one moves.
func _gray_binding() -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = load("res://game/infinite_route/infinite_route_test.tscn").instantiate()
	_host.get_tree().root.add_child(route)
	for i in 30:
		await _host.get_tree().process_frame
	var remotes := route.get("_remotes") as RemotePlayers
	var player := route.get("player") as PlayerController3D
	var facility := route.get("facility") as StreamedFacilityView3D
	var world_state = route.get("world_state")
	if remotes == null or player == null or facility == null:
		_fail("the Infinite route did not boot for the Gray check")
		route.queue_free()
		return
	var afk_delay := GameConfig.anti_afk_hunter_seconds(RoomState.difficulty_id())
	var depth := -facility.current_level()
	var here: Vector2 = player.grid_position()
	var now := Time.get_ticks_usec()
	var guest := func(id: int, offset: Vector2, idle: float) -> Dictionary:
		return {"peer_id": id, "position": here + offset, "at": Vector3(here.x + offset.x, 0, here.y + offset.y),
			"depth": depth, "received_usec": now, "idle_s": idle, "facing": Vector2(0, 1)}
	remotes._states = {7: guest.call(7, Vector2(6, 0), afk_delay + 30.0), 8: guest.call(8, Vector2(1, 0), 0.5)}
	route.set("_party_afk_seconds", 0.0)
	route.set("_anti_idle_last_relay_count", GameState.relays_collected)
	route.set("_relay_inactivity_seconds", 0.0)
	# Spawning needs a generated hunter-spawn candidate near the runner, which a loaded machine can take a while to
	# stream in; the route retries every frame while a runner stays AFK, so the check does too (up to ~15 s).
	var grays := []
	for attempt in 900:
		route.call("_update_anti_idle_pressure", 0.01)
		grays.clear()
		for entity_id in world_state.hunters:
			if String(world_state.hunters[entity_id].get("hunter_id", "")) == "void_gray":
				grays.append(String(entity_id))
		if not grays.is_empty():
			break
		await _host.get_tree().process_frame
	_expect(grays.size() == 1, "an AFK guest did not wake exactly one Gray (%d)" % grays.size())
	if grays.size() == 1:
		var gray_id: String = grays[0]
		_expect(int(world_state.hunters[gray_id].get("gray_peer", 0)) == 7,
			"Gray is bound to %s, not the AFK guest 7" % world_state.hunters[gray_id].get("gray_peer"))
		var local_target: Dictionary = route.call("_hunter_target", false)
		var picked: Dictionary = route.call("_target_for_hunter", gray_id, here + Vector2(1, 0), local_target, depth)
		_expect(int(picked.get("peer_id", 0)) == 7, "Gray chased %s instead of her AFK guest" % picked.get("peer_id"))
		# her guest's samples go stale: she has nobody, and never falls back to the nearest runner
		remotes._states[7]["received_usec"] = now - RemotePlayers.REMOTE_STATE_TIMEOUT_USEC * 2
		picked = route.call("_target_for_hunter", gray_id, here + Vector2(1, 0), local_target, depth)
		_expect(picked.is_empty(), "with her guest's samples late, Gray targeted %s" % picked.get("peer_id"))
		# the active guest stays active and is never bound; the AFK guest moves again: she is released
		remotes._states[7]["received_usec"] = Time.get_ticks_usec()
		remotes._states[7]["idle_s"] = 0.0
		remotes._states[8]["received_usec"] = Time.get_ticks_usec()
		route.call("_update_anti_idle_pressure", 0.01)
		_expect(not world_state.hunters.has(gray_id), "Gray stayed after her AFK guest moved again")
		var bound_to_active := false
		for entity_id in world_state.hunters:
			bound_to_active = bound_to_active or int(world_state.hunters[entity_id].get("gray_peer", 0)) == 8
		_expect(not bound_to_active, "Gray bound herself to the active guest")
	await _gray_god_mode(route, remotes, player, world_state, guest, afk_delay)
	remotes._states = {}
	route.queue_free()
	await _host.get_tree().process_frame


## Gray never wakes on a runner in admin god mode, using the same proof as the catch skip: a bare
## replicated god_mode flag without an admin proof is still AFK prey; a proven one is skipped, and a Gray already bound
## to that runner lets go the moment they turn god mode on.
func _gray_god_mode(route: Node, remotes: RemotePlayers, player: PlayerController3D, world_state, guest: Callable,
		afk_delay: float) -> void:
	var gray_peer_of := func() -> Array:
		var peers := []
		for entity_id in world_state.hunters:
			var state: Dictionary = world_state.hunters[entity_id]
			if String(state.get("hunter_id", "")) == "void_gray" and int(state.get("gray_peer", 0)) != 0:
				peers.append(int(state.get("gray_peer", 0)))
		return peers
	var saved_deny := Build.deny_admin_for_test
	route.set("_party_afk_seconds", 0.0)
	route.set("_relay_inactivity_seconds", 0.0)
	# 1. unproven god_mode (no admin proof): a forged flag does not buy immunity -- she still binds to the AFK guest
	Build.deny_admin_for_test = true
	remotes._states = {7: guest.call(7, Vector2(6, 0), afk_delay + 30.0)}
	remotes._states[7]["god_mode"] = true
	var bound: Array = []
	for attempt in 900:
		remotes._states[7]["received_usec"] = Time.get_ticks_usec()
		route.call("_update_anti_idle_pressure", 0.01)
		bound = gray_peer_of.call()
		if not bound.is_empty():
			break
		await _host.get_tree().process_frame
	_expect(bound == [7], "an unproven god_mode flag kept Gray off the AFK guest (bound %s)" % [bound])
	# 2. the same guest with a proven admin session and god mode on: she lets go and never rebinds
	Build.deny_admin_for_test = saved_deny
	for i in 30:
		remotes._states[7]["received_usec"] = Time.get_ticks_usec()
		route.call("_update_anti_idle_pressure", 0.01)
	bound = gray_peer_of.call()
	_expect(bound.is_empty(), "Gray stayed bound to a guest in admin god mode (bound %s)" % [bound])
	_expect(not bool(route.call("_spawn_anti_idle_hunter", 7, "afk", afk_delay + 30.0)),
		"Gray woke on a guest in admin god mode")
	# 3. a lone runner in god mode is not a stalled-relay target either
	route.set("_relay_inactivity_seconds", GameConfig.anti_idle_hunter_seconds(RoomState.difficulty_id()) + 1.0)
	route.set("_anti_idle_last_relay_count", GameState.relays_collected)
	remotes._states = {}
	var saved_god := player.admin_god_mode
	player.admin_god_mode = true
	var local_target: Dictionary = route.call("_hunter_target", false)
	var local_id := int(local_target.get("peer_id", 1))
	var god_peers: Dictionary = route.call("_gray_god_mode_peers", local_target)
	_expect(god_peers.has(local_id), "the host's own admin god mode is not recognised for Gray")
	_expect(not bool(route.call("_spawn_anti_idle_hunter", local_id, "relay", 0.0)),
		"Gray woke on the host in admin god mode")
	route.call("_update_anti_idle_pressure", 0.01)
	bound = gray_peer_of.call()
	_expect(not bound.has(local_id), "a stalled relay bound Gray to the host in admin god mode")
	# leave the clocks cold: the route's own frames would otherwise wake her on the host once god mode is back off
	route.set("_relay_inactivity_seconds", 0.0)
	route.set("_party_afk_seconds", 0.0)
	player.admin_god_mode = saved_god
	Build.deny_admin_for_test = saved_deny
