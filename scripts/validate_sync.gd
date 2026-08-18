extends RefCounted

## Headless check on the shared world.
##
## Two copies of the maze scene stand in for two peers. They are not networked
## to each other -- the transport is not what breaks -- so the events one raises
## are handed to the other directly, which is exactly what the RPC does once
## there is a socket in between.
##
## What this is really guarding is the assumption underneath all of it: a shared
## event names a GRID CELL, and that only identifies the same object on two
## machines if both machines built the same facility. Test the cell addressing
## without testing the seed and you get a suite that passes while every peer
## collects relays out of a different building.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- sync

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)

	_expect(RoomState.run_seed() != 0,
		"a room's run seed is zero, which GameState reads as 'pick one at random'")

	var alice: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(alice)
	var bob: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(bob)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	_same_facility(alice, bob)
	print("  seed      two peers built the same %dx%d facility from ROOM %s"
		% [alice.facility_view.generator.cols, alice.facility_view.generator.rows,
			RoomState.code])
	_spawn_points_separate(alice)
	print("  spawns    roster slots use separate nearby open cells")
	_pickups_travel(alice, bob)
	print("  pickups   a relay collected on one peer leaves the floor on the other")
	_heater_travels(alice, bob)
	print("  heater    the station's three states hold across the room")
	_hunter_state_travels(alice, bob)
	_gimmick_state_travels()
	print("  hunters   active/state/facing and interaction state replicate from the host")
	_taser_is_host_authoritative(alice)
	print("  taser     host validates aim and applies the replicated hunter stun")
	_target_selection(alice)
	print("  targeting the closest available remote runner can be chased safely")
	_targeted_outcomes(bob)
	print("  outcomes  host-selected stun and capture resolve on the target peer")
	_authoritative_world_request(alice)
	print("  authority guest world actions are validated and canonicalized by the host")
	await _snapshot_catches_up(host, alice)
	print("  latecomer a peer joining mid-floor is told what it missed")
	await _custom_map_snapshot_catches_up(host, alice)
	print("  custom    authored floor and mutations bootstrap before guest control")
	_admin_world_changes_persist(alice, bob)
	print("  admin     shared debug edits commit on host and advance floor revision")

	alice.queue_free()
	bob.queue_free()
	return _failures


## Both peers took the room's seed rather than one of their own.
func _same_facility(alice: Node, bob: Node) -> void:
	var a: FacilityGenerator = alice.facility_view.generator
	var b: FacilityGenerator = bob.facility_view.generator
	if a.cols != b.cols or a.rows != b.rows:
		_fail("two peers built facilities of different sizes (%dx%d vs %dx%d)"
			% [a.cols, a.rows, b.cols, b.rows])
		return
	if a.start != b.start:
		_fail("two peers spawn on different cells (%s vs %s)" % [a.start, b.start])
	for y in a.rows:
		if a.grid[y] != b.grid[y]:
			_fail("two peers built different walls on row %d" % y)
			return
	_expect(_cells(a.relays) == _cells(b.relays),
		"two peers put their relays on different cells")
	_expect(_cells(a.batteries) == _cells(b.batteries),
		"two peers put their batteries on different cells")
	_expect(a.place_boarded_paths() == b.place_boarded_paths(),
		"two peers generated different boarded room thresholds")


func _cells(entries: Array) -> Array:
	var out := []
	for entry in entries:
		out.append(Vector2i(entry["x"], entry["y"]))
	return out


func _spawn_points_separate(scene: Node) -> void:
	var first: Vector3 = scene._player_spawn_world_position(1)
	var second: Vector3 = scene._player_spawn_world_position(2)
	_expect(not first.is_equal_approx(second),
		"two connected runners spawn inside the same mannequin")
	_expect(scene.facility_view.generator.is_floor(first.x, first.z),
		"the first network spawn is not on an open floor cell")
	_expect(scene.facility_view.generator.is_floor(second.x, second.z),
		"the second network spawn is not on an open floor cell")


func _taser_is_host_authoritative(scene: Node) -> void:
	var generator: FacilityGenerator = scene.facility_view.generator
	var firing_cell := Vector2i(-1, -1)
	for cell in generator.floor_cells():
		if generator.is_floor(cell.x + 1.5, cell.y + .5):
			firing_cell = cell
			break
	if firing_cell.x < 0:
		_fail("no adjacent open cells exist for the taser line-of-sight check")
		return
	var hunter: HunterView3D = scene.hunter_view
	scene.player.global_position = Vector3(firing_cell.x + .5,
		scene.player.global_position.y, firing_cell.y + .5)
	scene.player.facing = Vector2(1, 0)
	hunter.brain.position = Vector2(firing_cell) + Vector2(1.5, .5)
	hunter.brain.active = true
	hunter.brain.stun_timer = 0.0
	scene._taser_ready_usec_by_peer.clear()
	scene._resolve_taser_request(1)
	_expect(is_equal_approx(hunter.brain.stun_timer, GameConfig.TASER_STUN_SECONDS),
		"an aimed in-range taser request did not stun the authoritative hunter")
	var first_stun := hunter.brain.stun_timer
	scene._resolve_taser_request(1)
	_expect(is_equal_approx(hunter.brain.stun_timer, first_stun),
		"the host accepted a second taser request during cooldown")


## A relay collected on one peer leaves the floor on the other, and counts once.
func _pickups_travel(alice: Node, bob: Node) -> void:
	var mine := _first(alice, RouteInteractable3D.Kind.RELAY)
	var theirs := _first(bob, RouteInteractable3D.Kind.RELAY)
	if mine == null or theirs == null:
		_fail("no relay on the floor to collect")
		return

	var raised: Array = []
	var listen := func(e: Dictionary) -> void: raised.append(e)
	alice.facility_view.world_changed.connect(listen)
	mine.activate(alice.player)
	alice.facility_view.world_changed.disconnect(listen)

	if raised.is_empty():
		_fail("collecting a relay told nobody -- the room never hears about it")
		return
	var event: Dictionary = raised[0]
	_expect(event.get("cell", Vector2i(-1, -1)) == mine.source_cell,
		"a pickup event named cell %s but happened on %s"
			% [event.get("cell"), mine.source_cell])

	# The count is the part a peer cannot recompute for itself, so it has to
	# come out of applying the event rather than out of who pressed the key.
	var before: int = GameState.relays_collected
	bob._apply_world_event(event)
	_expect(GameState.relays_collected == before + 1,
		"applying another peer's relay moved the count by %d, not 1"
			% (GameState.relays_collected - before))
	_expect(theirs.completed, "another peer's relay is still uncollected here")
	_expect(not _visible(theirs), "a relay collected by another peer is still standing there")
	_expect(_marked(bob.facility_view.generator.relays, theirs.source_cell),
		"the generator still lists a relay another peer collected, so hunters read a stale floor")

	# Twice is a real case: a second player reaching the same relay inside one
	# packet's worth of time. It must not count twice.
	bob._apply_world_event(event)
	_expect(GameState.relays_collected == before + 1,
		"the same relay counted twice when the event arrived twice")


func _heater_travels(alice: Node, bob: Node) -> void:
	var station: RouteInteractable3D = alice.facility_view.heater_station
	var far: RouteInteractable3D = bob.facility_view.heater_station
	if station == null or far == null:
		_fail("no heater station on the floor")
		return
	station.activate(alice.player)  # FROZEN -> UNFROZEN
	station.activate(alice.player)  # UNFROZEN -> POWERED
	bob._apply_world_event({"what": "heater", "state": station.heater_state})
	_expect(far.heater_state == RouteInteractable3D.HeaterState.POWERED,
		"the heater station is powered for one peer and not the other, so Wynelle disagrees")
	_expect(bob.player.heater_on,
		"one station warms one building, but the other peer is still in the cold")


## A peer that arrives after the floor started gets told what it missed.
func _snapshot_catches_up(host: Node, alice: Node) -> void:
	var hiding := _first(alice, RouteInteractable3D.Kind.HIDING_SPOT)
	if hiding:
		hiding.set_disabled(true)
	GameState.coins = 13
	GameState.score = 725
	var state: Dictionary = alice._build_snapshot()
	_expect(not state.get("taken", []).is_empty(),
		"the snapshot forgot the relay that was already collected")
	_expect(int(state.get("heater", -1)) == int(RouteInteractable3D.HeaterState.POWERED),
		"the snapshot forgot the heater station")
	_expect(int(state.get("coins", -1)) == 13 and int(state.get("score", -1)) == 725,
		"the snapshot forgot shared economy/progression totals")
	_expect(not (state.get("hunters", []) as Array).is_empty(),
		"the snapshot omitted the authoritative hunter state")
	if hiding:
		_expect(state.get("disabled_hiding", []).has(hiding.source_cell),
			"the snapshot forgot a disabled hiding spot")

	var latecomer: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(latecomer)
	await host.get_tree().process_frame

	latecomer._apply_world_snapshot(state)
	for entry in state["taken"]:
		var node: RouteInteractable3D = latecomer.facility_view._at(entry["cell"], entry["kind"])
		if node == null:
			_fail("a joining peer has no object on cell %s" % entry["cell"])
			continue
		_expect(node.completed and not _visible(node),
			"a joining peer can still collect a relay that is already gone")
	_expect(latecomer.facility_view.heater_station.heater_state
			== RouteInteractable3D.HeaterState.POWERED,
		"a joining peer thinks the heater station is untouched")
	if hiding:
		var late_hiding: RouteInteractable3D = latecomer.facility_view.hiding_spot_at(
			hiding.source_cell)
		_expect(late_hiding != null and late_hiding.disabled,
			"a joining peer can use a hiding spot Loxelle already disabled")
	_expect(GameState.coins == 13 and GameState.score == 725,
		"a joining peer did not adopt shared economy/progression totals")
	latecomer.queue_free()


## A custom map is the base world, not merely another mutation. The PNG must
## arrive before cell-addressed pickup/hiding state, and an invalid payload
## must leave the guest locked so RemotePlayers will request another snapshot.
func _custom_map_snapshot_catches_up(host: Node, alice: Node) -> void:
	var size := 35
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	for y in range(1, size - 1):
		for x in range(1, size - 1):
			image.set_pixel(x, y, Color(1, 1, 1, 1))
	image.set_pixel(2, 2, Color8(0, 255, 0))
	image.set_pixel(size - 5, 2, Color8(0, 255, 0))
	image.set_pixel(size - 3, size - 3, Color8(255, 0, 0))
	for y in range(5, 8):
		for x in range(5, 8):
			image.set_pixel(x, y, Color8(0x8e, 0x5f, 0xd9))

	GameState.relays_collected = 2
	GameState.relays_sabotaged = 1
	var install_error: String = alice._install_custom_map_png(
		image.save_png_to_buffer(), "SYNC:CUSTOM")
	_expect(install_error.is_empty(), "host could not install the custom map: %s" % install_error)
	if not install_error.is_empty():
		return
	_expect(GameState.relays_collected == 0 and GameState.relays_sabotaged == 0,
		"installing a fresh custom floor inherited old relay progress")
	var oversized := Image.create(CustomMapParser.MAX_DIMENSION + 1, 1,
		false, Image.FORMAT_RGBA8)
	oversized.fill(Color(1, 1, 1, 1))
	var oversized_error: String = alice._install_custom_map_png(
		oversized.save_png_to_buffer(), "SYNC:OVERSIZED")
	_expect(not oversized_error.is_empty(),
		"the transferable PNG path accepted an oversized decoded map")
	var first_spawn: Vector3 = alice._player_spawn_world_position(1)
	var second_spawn: Vector3 = alice._player_spawn_world_position(2)
	_expect(first_spawn.is_equal_approx(Vector3(2.5, first_spawn.y, 2.5)),
		"first room slot did not use the first authored custom-map spawn")
	_expect(second_spawn.is_equal_approx(Vector3(size - 4.5, second_spawn.y, 2.5)),
		"second room slot did not use the second authored custom-map spawn")
	var relay := _first(alice, RouteInteractable3D.Kind.RELAY)
	if relay != null:
		relay.activate(alice.player)
	var hiding := _first(alice, RouteInteractable3D.Kind.HIDING_SPOT)
	if hiding != null:
		hiding.set_disabled(true)
	alice.facility_view.heater_station.adopt({
		"what": "heater", "state": RouteInteractable3D.HeaterState.POWERED})
	var state: Dictionary = alice._build_snapshot()
	_expect(state.get("floor_source", "") == "custom",
		"custom snapshot was labelled procedural")
	_expect((state.get("custom_map_png", PackedByteArray()) as PackedByteArray).size() > 0,
		"custom snapshot omitted its transferable PNG")

	var latecomer: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(latecomer)
	await host.get_tree().process_frame
	latecomer._awaiting_initial_snapshot = true
	latecomer.player.input_frozen = true
	latecomer._remotes._snapshot_received = false
	latecomer.route_loading.show_waiting_for_snapshot()
	latecomer._apply_world_snapshot({
		"snapshot_protocol": alice.SNAPSHOT_PROTOCOL,
		"floor_source": "custom",
		"custom_map_png": PackedByteArray(),
		"depth": GameState.depth,
	})
	_expect(latecomer._awaiting_initial_snapshot and latecomer.player.input_frozen,
		"an invalid custom-map packet unlocked the joining player")
	_expect(not latecomer._remotes._snapshot_received,
		"an invalid custom-map packet disabled snapshot retries")
	_expect(latecomer.route_loading.visible,
		"an invalid host snapshot exposed the temporary guest floor")

	latecomer._apply_world_snapshot(state)
	_expect(latecomer.facility_view.generator.cols == size
		and latecomer.facility_view.generator.rows == size,
		"joining peer did not rebuild the authored map dimensions")
	_expect(latecomer.facility_view.generator.start == Vector2i(2, 2),
		"joining peer did not rebuild the authored start cell")
	_expect(latecomer.facility_view.generator.spawn_points \
		== alice.facility_view.generator.spawn_points,
		"joining peer did not rebuild every authored spawn cell")
	_expect(latecomer.facility_view.generator.grid == alice.facility_view.generator.grid,
		"joining peer rebuilt different custom-map walls")
	if relay != null:
		var late_relay: RouteInteractable3D = latecomer.facility_view._at(
			relay.source_cell, RouteInteractable3D.Kind.RELAY)
		_expect(late_relay != null and late_relay.completed,
			"custom-map pickup state landed before/without its base floor")
	if hiding != null:
		var late_hiding: RouteInteractable3D = latecomer.facility_view.hiding_spot_at(
			hiding.source_cell)
		_expect(late_hiding != null and late_hiding.disabled,
			"custom-map hiding state did not catch up")
	_expect(latecomer.facility_view.heater_station.heater_state
		== RouteInteractable3D.HeaterState.POWERED,
		"custom-map heater state did not catch up")
	_expect(not latecomer._awaiting_initial_snapshot and not latecomer.player.input_frozen,
		"valid snapshot did not release joining player control")
	_expect(latecomer._remotes._snapshot_received,
		"valid snapshot did not stop retry traffic")
	_expect(not latecomer.route_loading.visible,
		"valid host snapshot left the joining guest behind the loading screen")

	# An admin change can broadcast another snapshot for this exact base floor.
	# It must adopt mutation state without rebuilding the GridMap, moving the
	# local runner, or respawning the hunters from their initial positions.
	var generator_before: FacilityGenerator = latecomer.facility_view.generator
	var optimistic_relay: RouteInteractable3D
	for relay_entry in generator_before.relays:
		var candidate: RouteInteractable3D = latecomer.facility_view._at(
			Vector2i(int(relay_entry["x"]), int(relay_entry["y"])),
			RouteInteractable3D.Kind.RELAY)
		if candidate != null and not candidate.completed:
			optimistic_relay = candidate
			break
	if optimistic_relay != null:
		optimistic_relay.adopt({"what": "pickup"})
	if relay != null:
		var canonical_relay: RouteInteractable3D = latecomer.facility_view._at(
			relay.source_cell, RouteInteractable3D.Kind.RELAY)
		canonical_relay.adopt({"what": "sabotage", "sabotaged": true})
	if hiding != null:
		latecomer.facility_view.hiding_spot_at(hiding.source_cell).set_disabled(false)
	var position_before := Vector3(10.5, latecomer.player.position.y, 10.5)
	latecomer.player.position = position_before
	latecomer._apply_world_snapshot(state)
	_expect(latecomer.facility_view.generator == generator_before,
		"a same-revision custom snapshot rebuilt the guest's base floor")
	_expect(latecomer.player.position.is_equal_approx(position_before),
		"a same-revision custom snapshot teleported the guest back to spawn")
	if optimistic_relay != null:
		_expect(not optimistic_relay.completed,
			"canonical snapshot did not restore a host-rejected optimistic pickup")
		_expect(not _marked(generator_before.relays, optimistic_relay.source_cell),
			"rollback left the generator's relay entry marked collected")
	if relay != null:
		var canonical_relay: RouteInteractable3D = latecomer.facility_view._at(
			relay.source_cell, RouteInteractable3D.Kind.RELAY)
		_expect(not canonical_relay.sabotaged,
			"canonical snapshot did not clear stale relay sabotage")
	if hiding != null:
		_expect(latecomer.facility_view.hiding_spot_at(hiding.source_cell).disabled,
			"canonical snapshot did not restore the host's hiding-spot state")
	_expect(GameState.relays_collected == int(state.get("relays", -1)),
		"canonical snapshot kept an optimistic relay count instead of the host total")
	latecomer.queue_free()


func _admin_world_changes_persist(scene: Node, guest: Node) -> void:
	var revision_before: int = scene._floor_revision
	scene._apply_admin_world_action("all_relays")
	_expect(GameState.relays_collected == GameState.relay_target,
		"room-wide admin relay grant did not commit on host state")
	_expect(scene.facility_view.generator.uncollected(
		scene.facility_view.generator.relays).is_empty(),
		"admin relay grant changed the count but left host pickups behind")
	var collected_state: Dictionary = scene._build_snapshot()
	var relay_pickups := 0
	for entry in collected_state.get("taken", []):
		if int(entry.get("kind", -1)) == RouteInteractable3D.Kind.RELAY:
			relay_pickups += 1
	_expect(relay_pickups == GameState.relay_target,
		"admin relay snapshot omitted collected relay cells")
	guest._apply_world_snapshot(collected_state)
	_expect(guest.facility_view.generator.uncollected(
		guest.facility_view.generator.relays).is_empty(),
		"an existing guest kept relay pickups after the admin grant snapshot")
	scene._apply_admin_world_action("rebuild")
	var state: Dictionary = scene._build_snapshot()
	_expect(scene._floor_revision > revision_before,
		"admin rebuild did not advance the host floor revision")
	_expect(state.get("floor_source", "") == "procedural",
		"admin rebuild did not replace the prior custom floor on host")
	_expect(int(state.get("floor_revision", -1)) == scene._floor_revision,
		"admin rebuild snapshot did not publish its new floor revision")
	_expect(GameState.relays_collected == 0 and state.get("taken", []).is_empty(),
		"admin rebuild spawned a fresh floor with stale collected relay state")


func _hunter_state_travels(alice: Node, bob: Node) -> void:
	var source: HunterView3D = alice.hunter_view
	if source == null:
		_fail("the host has no route hunter to replicate")
		return
	source.brain.active = true
	source.brain.state = HunterBrain.State.CHASE
	source.brain.position += Vector2(1.25, 0.75)
	source.brain.facing = Vector2(1, 0)
	source.brain.stun_timer = 1.25
	source.target_peer_id = 77
	alice._collect_hunter_report()
	bob._apply_hunters(alice._hunter_report)
	var copy: HunterView3D = bob._find_hunter(source.brain.hunter_id)
	_expect(copy != null, "the other peer has no copy of the route hunter")
	if copy == null:
		return
	_expect(copy.brain.active, "an active host hunter is invisible on the other peer")
	_expect(copy.brain.state == HunterBrain.State.CHASE,
		"the other peer animates a chasing hunter in the wrong state")
	_expect(copy.brain.position.is_equal_approx(source.brain.position),
		"the other peer put the hunter at %s instead of %s"
			% [copy.brain.position, source.brain.position])
	_expect(copy.brain.facing.is_equal_approx(source.brain.facing),
		"the other peer lost the hunter's facing")
	_expect(is_equal_approx(copy.brain.stun_timer, source.brain.stun_timer),
		"the other peer did not receive the hunter's stun reaction timer")
	_expect(copy.target_peer_id == source.target_peer_id,
		"the other peer did not receive the hunter's pursued-player id")


func _gimmick_state_travels() -> void:
	var ceryth_host := CerythGimmick.new()
	ceryth_host.trap_spot = Vector2i(7, 9)
	ceryth_host.eyes_red = false
	ceryth_host.dispersed = true
	var ceryth_guest := CerythGimmick.new()
	ceryth_guest.apply_network_state(ceryth_host.network_state())
	_expect(ceryth_guest.trap_spot == Vector2i(7, 9) and not ceryth_guest.eyes_red
			and ceryth_guest.dispersed,
		"Ceryth's remote riddle state disagrees with the host")

	var opalie_host := OpalieGimmick.new()
	opalie_host.station = Vector2(4.5, 6.5)
	opalie_host.on_station = true
	var opalie_guest := OpalieGimmick.new()
	opalie_guest.apply_network_state(opalie_host.network_state())
	_expect(opalie_guest.blocks(Vector2(4.5, 6.5)),
		"Opalie's remote interaction guard is not active")

	var verrine_guest := VerrineGimmick.new()
	verrine_guest.apply_network_state({"active_in_vent": true, "speed_scale": 1.7})
	_expect(not verrine_guest.hidden_from_view(),
		"a remotely active Verrine is still hidden from the guest")
	var ilyra_guest := IlyraGimmick.new()
	ilyra_guest.apply_network_state({"hidden": true})
	_expect(ilyra_guest.hidden_from_view(),
		"Ilyra's remote banish visibility was not applied")


func _target_selection(scene: Node) -> void:
	var remotes := RemotePlayers.new()
	var now := Time.get_ticks_usec()
	remotes._states[2] = {
		"peer_id": 2,
		"position": Vector2(2, 1),
		"depth": GameState.depth,
		"received_usec": now,
		"hidden": false,
		"in_safe_zone": false,
		"temperature": 42.0,
	}
	var local := {
		"peer_id": 1,
		"position": Vector2(20, 20),
		"hidden": false,
		"in_safe_zone": false,
	}
	var picked := remotes.best_target(Vector2.ZERO, local, GameState.depth)
	_expect(int(picked.get("peer_id", -1)) == 2,
		"the hunter ignored the closer remote runner")
	var runtime: Dictionary = scene._target_with_runtime(picked)
	_expect(runtime.get("meters") is PlayerMeters,
		"a remote target did not reconstruct the meter object hunter gimmicks require")
	_expect(is_equal_approx(runtime["meters"].temperature, 42.0),
		"the reconstructed remote temperature changed value")
	remotes._states[2]["no_target"] = true
	picked = remotes.best_target(Vector2.ZERO, local, GameState.depth)
	_expect(int(picked.get("peer_id", -1)) == 1,
		"a remote runner's NO TARGET flag was ignored by the host")
	local["no_target"] = true
	_expect(remotes.best_target(Vector2.ZERO, local, GameState.depth).is_empty(),
		"host targeting selected a runner when every peer had NO TARGET")
	remotes.free()


func _targeted_outcomes(scene: Node) -> void:
	scene.player.stun_timer = 0.0
	scene._apply_player_event({"what": "stun", "seconds": 1.5})
	_expect(is_equal_approx(scene.player.stun_timer, 1.5),
		"a targeted hunter stun did not reach the selected player")
	GameState.escape_active = false
	GameState.escape_cooldown = 0.0
	GameState.escape_grace = 0.0
	scene._apply_player_event({
		"what": "capture",
		"hunter_id": scene.hunter_view.brain.hunter_id,
		"inescapable": false,
	})
	_expect(GameState.escape_active,
		"a host-issued capture did not open the target player's escape struggle")
	_expect(GameState.escape_hunter_id == scene.hunter_view.brain.hunter_id,
		"the escape struggle names a different hunter than the host's capture")
	GameState.escape_active = false
	scene.player.input_frozen = false

	# Continuous and one-shot hunter meter mutations are targeted owner events,
	# not writes to a temporary host-side reconstruction.
	scene.player.meters.exposure = 10.0
	scene.player.meters.noise_meter = 20.0
	scene.player.meters.temperature = 60.0
	scene._apply_player_event({
		"what": "meter_effect",
		"exposure_add": 25.0,
		"noise_add": 8.0,
		"noise_reclaim": 5.0,
		"temperature_add": -10.0,
	})
	_expect(is_equal_approx(scene.player.meters.exposure, 35.0),
		"a host-issued exposure effect did not reach the target owner")
	_expect(is_equal_approx(scene.player.meters.noise_meter, 15.0)
			and is_equal_approx(scene.player.meters.pending_noise_input(), 8.0),
		"a host-issued noise add/reclaim did not reach the target owner")
	_expect(is_equal_approx(scene.player.meters.temperature, 50.0),
		"a host-issued temperature effect did not reach the target owner")

	GameState.coins = 9
	GameState.score = 400
	var canonical: Dictionary = scene._remotes._canonical_world_event({"what": "coins"})
	_expect(int(canonical.get("coins", -1)) == 9 and int(canonical.get("score", -1)) == 400,
		"the host did not attach authoritative totals to a shared event")


func _authoritative_world_request(scene: Node) -> void:
	var coin := _first(scene, RouteInteractable3D.Kind.COIN)
	if coin == null:
		_fail("no coin exists for the host-authority interaction check")
		return
	GameState.coins = 0
	scene._remotes._states[2] = {
		"peer_id": 2,
		"position": Vector2(coin.source_cell) + Vector2(0.5, 0.5),
		"facing": Vector2(1, 0),
		"depth": GameState.depth,
		"received_usec": Time.get_ticks_usec(),
	}
	var request := {"what": "pickup", "cell": coin.source_cell,
		"kind": int(RouteInteractable3D.Kind.COIN)}
	scene._apply_world_request(2, request)
	_expect(coin.completed and GameState.coins == GameConfig.COIN_PICKUP_VALUE,
		"the host did not accept a valid guest coin pickup")
	scene._apply_world_request(2, request)
	_expect(GameState.coins == GameConfig.COIN_PICKUP_VALUE,
		"the host awarded the same guest pickup twice")

	var locked := _first_locked(scene)
	if locked == null:
		_fail("no locked relay cache exists for host-authority validation")
	else:
		scene._remotes._states[2]["position"] = Vector2(locked.source_cell) + Vector2(.5, .5)
		scene._remotes._states[2]["selected_item"] = "flashlight"
		var locked_request := {"what": "pickup", "cell": locked.source_cell,
			"kind": int(RouteInteractable3D.Kind.RELAY), "locked_cache": true,
			"tool": "lockpick"}
		scene._apply_world_request(2, locked_request)
		_expect(not locked.completed,
			"host accepted a locked-cache request without the tool selected")
		scene._remotes._states[2]["selected_item"] = "lockpick"
		scene._remotes._states[2]["owned_items"] = {"lockpick": true}
		scene._remotes._states[2]["item_durability"] = {"lockpick": 12}
		scene._apply_world_request(2, locked_request)
		_expect(locked.completed,
			"host rejected a valid lockpick request for a relay cache")

	var barrier := _first(scene, RouteInteractable3D.Kind.BOARDED_PATH)
	if barrier == null:
		_fail("no boarded path exists for host-authority validation")
	else:
		scene._remotes._states[2]["position"] = Vector2(barrier.source_cell) + Vector2(.5, .5)
		scene._remotes._states[2]["selected_item"] = "lockpick"
		var breach_request := {"what": "boarded_path", "cell": barrier.source_cell,
			"opened": true, "tool": "crowbar"}
		scene._apply_world_request(2, breach_request)
		_expect(not barrier.opened,
			"host accepted a boarded-path request with the wrong selected tool")
		scene._remotes._states[2]["selected_item"] = "crowbar"
		scene._remotes._states[2]["owned_items"] = {"crowbar": true}
		scene._remotes._states[2]["item_durability"] = {"crowbar": 40}
		scene._apply_world_request(2, breach_request)
		_expect(barrier.opened,
			"host rejected a valid crowbar request for a boarded path")


func _first(scene: Node, kind: RouteInteractable3D.Kind) -> RouteInteractable3D:
	for child in scene.facility_view.get_children():
		var item := child as RouteInteractable3D
		if item and item.kind == kind and not item.completed:
			return item
	return null


func _first_locked(scene: Node) -> RouteInteractable3D:
	for child in scene.facility_view.get_children():
		var item := child as RouteInteractable3D
		if item and item.kind == RouteInteractable3D.Kind.RELAY \
				and item.locked_cache and not item.completed:
			return item
	return null


## What the player sees, not what the flag says. A pickup that stays on screen
## reads as a failed interaction however correct its state is.
func _visible(node: RouteInteractable3D) -> bool:
	for child in node.get_children():
		if child is Node3D and (child as Node3D).visible and not (child is Light3D):
			return true
	return false


func _marked(entries: Array, cell: Vector2i) -> bool:
	for entry in entries:
		if Vector2i(entry["x"], entry["y"]) == cell:
			return bool(entry.get("collected", false))
	return false
