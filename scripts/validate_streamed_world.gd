extends RefCounted

const StreamedWorldStateScript := preload("res://src/game/streamed_world_state.gd")

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var world := StreamedRouteGenerator.new("STREAM-CHECK")
	var coords := [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-3, 1, 4)]
	for coord in coords:
		_expect(world.chunk(coord) == world.chunk(coord),
			"chunk %s does not regenerate identically" % coord)

	for z in range(-3, 4):
		for x in range(-3, 4):
			var at := Vector3i(x, 0, z)
			_expect(world.edge_openings(at, Vector2i(1, 0)) \
				== world.edge_openings(at + Vector3i(1, 0, 0), Vector2i(-1, 0)),
				"east/west seam disagrees at %s" % at)
			_expect(world.edge_openings(at, Vector2i(0, 1)) \
				== world.edge_openings(at + Vector3i(0, 0, 1), Vector2i(0, -1)),
				"north/south seam disagrees at %s" % at)

	var lower := world.chunk(Vector3i.ZERO)
	var upper := world.chunk(Vector3i(0, 1, 0))
	var lower_link: Dictionary
	for link in lower["stairs"]:
		if link["direction"] == "up":
			lower_link = link
			break
	var matching := false
	for link in upper["stairs"]:
		if link["id"] == lower_link["id"] and link["cell"] == lower_link["cell"] \
				and link["style"] == lower_link["style"]:
			matching = true
	_expect(matching, "the forced origin stair does not agree across vertical chunks")
	_expect(lower_link["direction"] == "up", "lower vertical link is not an up stair")
	var has_down := false
	for link in lower["stairs"]:
		has_down = has_down or link["direction"] == "down"
	_expect(has_down, "central spawn chunk has no downward stair")
	_expect(world.is_safe_room(Vector3i.ZERO), "origin chunk is not a temporary safe room")
	_expect(world.spawn_chunk() == Vector3i.ZERO and world.spawn_cell() == Vector2i(16, 16),
		"streamed spawn is not centered on level zero")

	var biomes := {}
	var pickup_ids := {}
	var saw_hotel_layout := false
	var saw_prison_layout := false
	var room_sizes := {}
	for level in range(-7, 4):
		for z in range(-5, 6):
			for x in range(-5, 6):
				var data := world.chunk(Vector3i(x, level, z))
				biomes[data["biome"]] = true
				_expect(not (data["biome"] == "inferno" and level > -3),
					"inferno leaked above deep floors at %s" % data["coord"])
				if level >= 0:
					_expect(data["biome"] != "gothic",
						"gothic biome leaked onto an upper floor at %s" % data["coord"])
				_expect(not (data["biome"] == "prison" and level > -2),
					"prison region leaked above lower floors at %s" % data["coord"])
				for room in data["rooms"]:
					var size: Vector2i = room["size"]
					room_sizes["%dx%d" % [size.x, size.y]] = true
				if data["biome"] == "hotel":
					saw_hotel_layout = data["rooms"].size() >= 6 \
						and data["corridors"].any(func(hall):
							return bool(hall.get("serves_many_rooms", false)))
				if data["biome"] == "prison":
					saw_prison_layout = data["rooms"].size() >= 6 \
						and data["rooms"].all(func(room):
							return room["room_type"] == "prison_cell")
				for pickup in data["pickups"]:
					_expect(not pickup_ids.has(pickup["id"]),
						"duplicate streamed pickup id %s" % pickup["id"])
					pickup_ids[pickup["id"]] = true
	_expect(biomes.size() == StreamedRouteGenerator.BIOMES.size(),
		"seeded sample did not produce every biome: %s" % [biomes.keys()])
	_expect(saw_hotel_layout,
		"hotel region did not create a long multi-room corridor floor")
	_expect(saw_prison_layout,
		"lower prison region did not create a multi-cell-block corridor")
	for expected_size in [Vector2i(3, 3), Vector2i(3, 5), Vector2i(5, 5),
			Vector2i(5, 7), Vector2i(7, 5), Vector2i(9, 9)]:
		_expect(StreamedRouteGenerator.ROOM_SIZES.has(expected_size),
			"requested room size %s is missing from the streamed catalog" % expected_size)
	_expect(room_sizes.size() >= 6,
		"streamed rooms did not vary enough in size: %s" % [room_sizes.keys()])
	_expect(room_sizes.has("15x15"),
		"15x15 landmark rooms were clipped out of generated topology")
	_expect(not pickup_ids.is_empty(), "streamed chunks produced no collectible ids")
	_expect(float(world.difficulty_for_level(-8)["danger"]) \
		> float(world.difficulty_for_level(5)["danger"]),
		"lower floors are not more dangerous than upper floors")
	var mutations = StreamedWorldStateScript.new()
	_expect(mutations.activate_checkpoint(lower), "origin safe room did not activate checkpoint")
	var safe_info: Dictionary = lower["safe_room_data"]
	var breached := mutations.damage_safe_room(safe_info, 100)
	_expect(bool(breached["breached"]), "safe room did not breach at zero integrity")
	_expect(not mutations.activate_checkpoint(lower), "breached safe room remained a checkpoint")
	var repaired := mutations.repair_safe_room(safe_info, 40)
	_expect(not bool(repaired["breached"]) and mutations.activate_checkpoint(lower),
		"repaired safe room did not become a usable checkpoint")
	_expect(mutations.claim_pickup("test:item") and not mutations.claim_pickup("test:item"),
		"host mutation ledger allowed duplicate pickup ownership")
	var restored = StreamedWorldStateScript.new()
	_expect(restored.adopt(mutations.snapshot()) and not restored.pickup_available("test:item"),
		"late-join mutation snapshot did not preserve claimed pickups")
	var active := world.coordinates_around(Vector2(17.0, -1.0), 2, 2)
	_expect(active.size() == 25 and active.has(Vector3i(1, 2, -1)),
		"stream radius did not produce the expected 5x5 active set")

	# The data contract is only useful once a runner can stand on it. Instantiate
	# the debug route and exercise its real GridMap collision window, forced
	# vertical flights, chunk eviction and authored prison dressing.
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.map_scale = RoomState.Scale.INFINITE
	var live_scene: Node = (load("res://scenes/infinite_route_test.tscn") \
		as PackedScene).instantiate()
	host.get_tree().root.add_child(live_scene)
	await host.get_tree().process_frame
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var facility := live_scene.get_node("World/StreamedFacility") as StreamedFacilityView3D
	var player := live_scene.get_node("World/Player") as PlayerController3D
	_expect(facility != null and facility.loaded_chunk_count() == 11,
		"live stream did not hold the 3x3 floor plus two vertical neighbours")
	var structures := facility.find_children("Structure", "GridMap", true, false)
	_expect(not structures.is_empty() and (structures[0] as GridMap).get_used_cells().size() \
		>= 950,
		"live streamed chunk did not paint a complete collidable grid")
	_expect(host.get_tree().get_nodes_in_group("streamed_stair").size() >= 2,
		"central live chunks did not build the forced up/down physical stairs")
	_expect(player.is_on_floor(), "streamed player did not settle on generated floor collision")

	var prison_coord := Vector3i(999, 999, 999)
	for level in range(-2, -8, -1):
		if prison_coord.x != 999:
			break
		for z in range(-6, 7):
			if prison_coord.x != 999:
				break
			for x in range(-6, 7):
				if facility.generator.biome_for(Vector3i(x, level, z)) == "prison":
					prison_coord = Vector3i(x, level, z)
					break
	_expect(prison_coord.x != 999, "validation seed produced no reachable prison test chunk")
	if prison_coord.x != 999:
		player.set_admin_noclip(true)
		player.global_position = Vector3(
			(prison_coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
			prison_coord.y * StreamedFacilityView3D.LEVEL_HEIGHT + .2,
			(prison_coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		_expect(facility.current_chunk_coord() == prison_coord,
			"live stream did not follow the runner into the lower prison region")
		_expect(not host.get_tree().get_nodes_in_group("streamed_prison_prop").is_empty(),
			"live prison chunk contains no authored prison models")
		_expect(facility.loaded_chunk_count() == 11,
			"moving far away leaked old streamed chunks instead of evicting them")
	live_scene.queue_free()
	await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)

	if _failures == 0:
		print("  chunks    deterministic topology, canonical seams and stable pickup ids")
		print("  vertical  unbounded levels; central spawn links both up and down")
		print("  regions   8 area identities; Gothic/Prison/Inferno constrained below")
		print("  rooms     %d sizes; hotel/prison corridors serve many rooms" % room_sizes.size())
		print("  survival  breachable/repairable checkpoints and pickup ledger persist")
		print("  renderer  collidable 3x3 stream, vertical flights and prison art load")
		print("streamed_world OK")
	return _failures
