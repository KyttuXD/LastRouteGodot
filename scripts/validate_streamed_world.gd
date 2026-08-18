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
	var hunter_ids := {}
	var first_hunter_spawn: Dictionary = {}
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
				for spawn_value in data["hunter_spawns"]:
					var spawn: Dictionary = spawn_value
					_expect(not hunter_ids.has(spawn["id"]),
						"duplicate streamed hunter id %s" % spawn["id"])
					hunter_ids[spawn["id"]] = true
					_expect(not bool(data["safe_room"]),
						"hunter spawned inside safe room %s" % data["coord"])
					_expect(StreamedRouteGenerator.STREAMED_HUNTER_IDS.has(
						spawn["hunter_id"]) or HunterRoster.VOID_IDS.has(spawn["hunter_id"]),
						"streamed route selected an unsupported hunter %s" % spawn["hunter_id"])
					if first_hunter_spawn.is_empty():
						first_hunter_spawn = spawn.duplicate(true)
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
	_expect(not hunter_ids.is_empty(), "streamed chunks produced no persistent hunters")
	_expect(world.chunk(Vector3i.ZERO)["hunter_spawns"].is_empty(),
		"central safe arrival chunk spawned a hunter")
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
	if not first_hunter_spawn.is_empty():
		var hunter_state := mutations.ensure_hunter(first_hunter_spawn)
		var brain := HunterBrain.new(hunter_state["position"], "STREAM-STATE",
			hunter_state["hunter_id"])
		mutations.restore_hunter(brain, hunter_state)
		brain.position += Vector2(.25, .5)
		brain.apply_stun(2.0)
		mutations.store_hunter(first_hunter_spawn["id"], brain,
			int(hunter_state["level"]), hunter_state["origin_chunk"])
		var hunter_restored = StreamedWorldStateScript.new()
		_expect(hunter_restored.adopt(mutations.snapshot()),
			"late-join mutation snapshot rejected hunter state")
		var persisted := hunter_restored.hunter_state(first_hunter_spawn["id"])
		_expect((persisted.get("position", Vector2.ZERO) as Vector2).is_equal_approx(
			brain.position) and float(persisted.get("stun_timer", 0.0)) >= 2.0,
			"streamed hunter position/stun did not survive a mutation snapshot")
	var active := world.coordinates_around(Vector2(17.0, -1.0), 2, 2)
	_expect(active.size() == 25 and active.has(Vector3i(1, 2, -1)),
		"stream radius did not produce the expected 5x5 active set")
	var seam_offset: int = world.edge_openings(Vector3i.ZERO, Vector2i.RIGHT)[0]
	var navigation := StreamedHunterNavigation.new(world, 0)
	navigation.refresh(0, [Vector3i.ZERO, Vector3i(1, 0, 0)])
	var seam_path := navigation.find_path(Vector2i(31, seam_offset),
		Vector2i(32, seam_offset))
	_expect(seam_path.size() == 2,
		"streamed hunter navigation did not cross a canonical chunk seam")
	_expect(navigation.has_line_of_sight(Vector2(31.5, seam_offset + .5),
		Vector2(32.5, seam_offset + .5)),
		"streamed hunter line of sight stopped at a matching chunk seam")

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

	var hunter_coord := Vector3i(999, 999, 999)
	for level in range(-2, -8, -1):
		if hunter_coord.x != 999:
			break
		for z in range(-8, 9):
			if hunter_coord.x != 999:
				break
			for x in range(-8, 9):
				var candidate := Vector3i(x, level, z)
				if not facility.generator.chunk(candidate)["hunter_spawns"].is_empty():
					hunter_coord = candidate
					break
	_expect(hunter_coord.x != 999, "validation seed produced no reachable hunter chunk")
	if hunter_coord.x != 999:
		player.set_admin_noclip(true)
		player.admin_god_mode = true
		player.global_position = Vector3(
			(hunter_coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
			hunter_coord.y * StreamedFacilityView3D.LEVEL_HEIGHT + .2,
			(hunter_coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var live_hunters := host.get_tree().get_nodes_in_group("streamed_hunter")
		_expect(not live_hunters.is_empty(),
			"live endless route did not instantiate deterministic hunter state")
		if not live_hunters.is_empty():
			var live_hunter := live_hunters[0] as HunterView3D
			var entity_id := String(live_hunter.get_meta("streamed_entity_id", ""))
			live_hunter.brain.apply_stun(60.0)
			var persisted_position := live_hunter.brain.position
			await host.get_tree().process_frame
			player.global_position += Vector3(
				StreamedRouteGenerator.CHUNK_SIZE * 20, 0.0, 0.0)
			await host.get_tree().process_frame
			await host.get_tree().process_frame
			_expect(facility.loaded_chunk_count() == 11,
				"long-distance hunter unload leaked streamed chunks")
			player.global_position = Vector3(
				(hunter_coord.x + .5) * StreamedRouteGenerator.CHUNK_SIZE,
				hunter_coord.y * StreamedFacilityView3D.LEVEL_HEIGHT + .2,
				(hunter_coord.z + .5) * StreamedRouteGenerator.CHUNK_SIZE)
			await host.get_tree().process_frame
			await host.get_tree().process_frame
			var reloaded: HunterView3D
			for candidate_view in host.get_tree().get_nodes_in_group("streamed_hunter"):
				if String(candidate_view.get_meta("streamed_entity_id", "")) == entity_id:
					reloaded = candidate_view
					break
			_expect(reloaded != null and reloaded.brain.position.is_equal_approx(
				persisted_position) and reloaded.brain.stun_timer > 50.0,
				"hunter movement/stun did not survive chunk unload and reload")
		# Cross dozens of chunk boundaries rather than checking one teleport. The
		# scene and navigation caches must stay proportional to the active window,
		# never to total distance travelled.
		for step in 12:
			player.global_position = Vector3(
				(hunter_coord.x + 4 + step * 3) * StreamedRouteGenerator.CHUNK_SIZE + 16,
				hunter_coord.y * StreamedFacilityView3D.LEVEL_HEIGHT + .2,
				(hunter_coord.z - 2 - step * 2) * StreamedRouteGenerator.CHUNK_SIZE + 16)
			await host.get_tree().process_frame
			await host.get_tree().process_frame
			_expect(facility.loaded_chunk_count() == 11,
				"long-session stream exceeded its eleven-chunk window at step %d" % step)
			_expect(host.get_tree().get_nodes_in_group("streamed_chunk").size() == 11,
				"long-session scene retained an evicted chunk at step %d" % step)
		var live_navigation := live_scene.get("_navigation") as StreamedHunterNavigation
		_expect(live_navigation != null and live_navigation.cached_chunk_count() <= 25,
			"streamed navigation cache grew with travel distance")

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
		_expect(host.get_tree().get_nodes_in_group("streamed_chunk").size() == 11,
			"streamed scene tree retained evicted chunk nodes")
	live_scene.queue_free()
	await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)

	if _failures == 0:
		print("  chunks    deterministic topology, canonical seams and stable pickup ids")
		print("  vertical  unbounded levels; central spawn links both up and down")
		print("  regions   8 area identities; Gothic/Prison/Inferno constrained below")
		print("  rooms     %d sizes; hotel/prison corridors serve many rooms" % room_sizes.size())
		print("  survival  checkpoints, pickups and hunter state persist across unload")
		print("  hunters   deterministic spawns, seam navigation and live pursuit load")
		print("  renderer  bounded collidable stream, vertical flights and prison art load")
		print("streamed_world OK")
	return _failures
