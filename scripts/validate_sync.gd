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
	_pickups_travel(alice, bob)
	print("  pickups   a relay collected on one peer leaves the floor on the other")
	_heater_travels(alice, bob)
	print("  heater    the station's three states hold across the room")
	await _snapshot_catches_up(host, alice)
	print("  latecomer a peer joining mid-floor is told what it missed")

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


func _cells(entries: Array) -> Array:
	var out := []
	for entry in entries:
		out.append(Vector2i(entry["x"], entry["y"]))
	return out


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
	var state: Dictionary = alice._build_snapshot()
	_expect(not state.get("taken", []).is_empty(),
		"the snapshot forgot the relay that was already collected")
	_expect(int(state.get("heater", -1)) == int(RouteInteractable3D.HeaterState.POWERED),
		"the snapshot forgot the heater station")

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
	latecomer.queue_free()


func _first(scene: Node, kind: RouteInteractable3D.Kind) -> RouteInteractable3D:
	for child in scene.facility_view.get_children():
		var item := child as RouteInteractable3D
		if item and item.kind == kind and not item.completed:
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
