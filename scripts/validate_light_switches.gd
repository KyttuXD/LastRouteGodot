extends RefCounted

## Room light switches in the streamed world (docs/LIGHT_SWITCHES.md): lit rooms with a door get a switch inside beside
## the doorway at a reachable height; flipping it puts the room's lamps (the rendered pool lights and the light-sight
## field) out and back on; the state survives a chunk unload/reload and a save/load (world state snapshot); a guest's
## request and the host's relayed event both apply it.
##
##   godot --headless --path . res://scenes/validate.tscn -- light_switches

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _exposure_in(route: Node, room_id: String) -> float:
	var facility: StreamedFacilityView3D = route.facility
	var entries: Array = facility._room_lamps.get(room_id, [])
	if entries.is_empty():
		return 0.0
	var lamp: Array = (entries[0] as Array)[0]
	var at: Vector3 = lamp[0]
	return float(LightField.exposure_at(Vector3(at.x, 1.0, at.z), facility._lamp_field._chunks)["value"])


## KT: "doors collide with light switches". Over many generated chunks, no switch (and, reported, no wall-mounted
## prop) sits within a door's frame plus FRAME_CLEAR beyond the opening's edge, inside its swing (the opening's width on
## either side of the wall, as a leaf may swing in or out).
const CLEAR_SEEDS := ["SWITCH-A", "SWITCH-B", "SWITCH-C", "ENDLESS-ROUTE"]
const FRAME_CLEAR := .5


static func in_door_zone(at: Vector2, door: Dictionary) -> bool:
	var cells: Array = door.get("doorway_cells", [door.get("cell", Vector2i.ZERO)])
	var centre := Vector2.ZERO
	for cell_value in cells:
		centre += Vector2(cell_value as Vector2i) + Vector2(.5, .5)
	centre /= float(maxi(1, cells.size()))
	var inward := Vector2(door.get("inward", Vector2i(0, 1)) as Vector2i)
	var across := Vector2(door.get("across", Vector2i(1, 0)) as Vector2i)
	var rel := at - centre
	var half := float(cells.size()) * .5
	return absf(rel.dot(across)) < half + FRAME_CLEAR and absf(rel.dot(inward)) < float(cells.size()) + .2


func _check_door_clearance() -> void:
	var switches := 0
	var bad := []
	var mounted_near := []
	for seed_text in CLEAR_SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-5, 6):
			for dx in range(-5, 6):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				var doors := []
				var main_door := {}
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					if bool(prop.get("room_door", false)):
						doors.append(prop)
						if not main_door.has(String(prop.get("room_id", ""))):
							main_door[String(prop.get("room_id", ""))] = prop
				for room_id in main_door:
					var at := StreamedFacilityView3D.switch_spot(main_door[room_id], data.get("grid", []))
					if at.x == INF:
						continue
					switches += 1
					for door in doors:
						if in_door_zone(at, door):
							bad.append("%s %s by %s" % [coord, room_id, (door as Dictionary).get("id", "")])
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					if not PropModelCatalog.is_wall_mounted(String(prop.get("type", ""))):
						continue
					var at := Vector2(prop.get("cell", Vector2i.ZERO)) + Vector2(.5, .5) + (prop.get("placement_offset", Vector2.ZERO) as Vector2) \
						+ (prop.get("mount_offset", Vector2.ZERO) as Vector2)
					for door in doors:
						if in_door_zone(at, door):
							mounted_near.append("%s %s" % [coord, prop.get("type", "")])
							break
	_expect(switches > 200, "only %d switches in the door-clearance sample" % switches)
	_expect(bad.is_empty(), "%d light switches inside a door's frame or swing: %s" % [bad.size(), bad.slice(0, 6)])
	metrics["door_clear_switches"] = switches
	metrics["wall_props_in_door_zones"] = mounted_near.size()
	if not mounted_near.is_empty():
		print("  note  %d wall-mounted props in a door zone (other lanes' recipes), e.g. %s" % [mounted_near.size(), mounted_near.slice(0, 5)])


func run(host: Node) -> int:
	_check_door_clearance()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "LIGHT-SWITCH"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 240:
		await host.get_tree().physics_frame
	var facility: StreamedFacilityView3D = route.facility
	var player: PlayerController3D = route.player
	var rooms: Array = facility.lit_rooms()
	var switched := []
	for room_id in rooms:
		if facility.room_light_switch(String(room_id)) != null:
			switched.append(String(room_id))
	metrics["lit_rooms"] = rooms.size()
	metrics["switches"] = switched.size()
	_expect(rooms.size() >= 4, "only %d lit rooms loaded" % rooms.size())
	_expect(switched.size() * 2 >= rooms.size(), "only %d of %d lit rooms have a switch" % [switched.size(), rooms.size()])
	var dark_at_start := 0
	for room_id in rooms:
		if not route.world_state.room_light_on(String(room_id)):
			dark_at_start += 1
			_expect(facility.room_lamp_energy(String(room_id)) == 0.0, "%s starts dark but its lamps are lit" % room_id)
	metrics["dark_at_start"] = dark_at_start
	for room_id in switched:
		var switch := facility.room_light_switch(room_id)
		var height := switch.global_position.y - player.global_position.y
		_expect(height >= 1.0 and height <= 2.1, "%s switch at %.2f m, out of a runner's reach" % [room_id, height])
	if switched.is_empty():
		route.queue_free()
		return _failures
	# flip one: the lamps, the light field and the switch follow
	var room := String(switched[0])
	var switch := facility.room_light_switch(room)
	if not route.world_state.room_light_on(room):
		switch.activate(player)
	_expect(route.world_state.room_light_on(room) and facility.room_lamp_energy(room) > 0.0, "%s did not come on" % room)
	var lit := _exposure_in(route, room)
	Sound.reset_test_counters()
	switch.activate(player)
	_expect(not route.world_state.room_light_on(room) and facility.room_lamp_energy(room) == 0.0, "the switch did not put %s out" % room)
	_expect(not switch.light_enabled, "the switch does not show off")
	var dark := _exposure_in(route, room)
	_expect(dark < lit - .1, "the light field did not darken (%.2f -> %.2f)" % [lit, dark])
	_expect(int(Sound.play_counts.get("light_switch", 0)) >= 1, "the switch made no click")
	metrics["exposure"] = [snappedf(lit, .01), snappedf(dark, .01)]
	# save/load: the world state snapshot carries it
	var copy := StreamedWorldState.new()
	_expect(copy.adopt(route.world_state.snapshot()) and not copy.room_light_on(room), "the switched-off room is lit again after save/load")
	# unload and rebuild every chunk: the room comes back dark
	facility.refresh_mutations()
	for _i in 240:
		await host.get_tree().physics_frame
	_expect(facility.room_lamp_energy(room) == 0.0 and facility._room_lamps.has(room), "%s was lit again after the chunk reloaded" % room)
	var rebuilt := facility.room_light_switch(room)
	_expect(rebuilt != null and not rebuilt.light_enabled, "the rebuilt switch forgot it was off")
	# co-op: a guest's request on the host, and the relayed event on a guest, both apply
	route._on_remote_interaction_request(2, {"what": "stream_room_light", "room_id": room, "on": true})
	_expect(route.world_state.room_light_on(room) and facility.room_lamp_energy(room) > 0.0, "a guest's switch request did not apply on the host")
	route._apply_stream_world_event({"what": "stream_room_light", "room_id": room, "on": false})
	_expect(not route.world_state.room_light_on(room) and facility.room_lamp_energy(room) == 0.0, "the relayed switch event did not apply")
	route.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	if _failures == 0:
		print("  light_switches  %s" % [metrics])
	return _failures
