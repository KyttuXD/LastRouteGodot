extends RefCounted

const StreamedWorldStateScript := preload("res://src/game/streamed_world_state.gd")

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	Settings.set_admin_preferences(Settings.ADMIN_PREFERENCE_DEFAULTS)
	var world := StreamedRouteGenerator.new("STREAM-CHECK")
	_expect(StreamedRouteGenerator.CORRIDOR_WIDTH == 3,
		"Infinite corridors are no longer three cells wide")
	_expect(world.stair_links(Vector3i.ZERO).is_empty() and not world.is_chunk_allowed(Vector3i(0, 1, 0)) \
		and not world.is_chunk_allowed(Vector3i(0, -1, 0)) and world.is_chunk_allowed(Vector3i(9, 0, -9)),
		"the route is not a single unbounded level")
	_expect(FacilityMap.RELAY_TEAL_BLUE.is_equal_approx(Color("32c9d8")),
		"relay map markers are not the distinct teal-blue palette colour")
	_expect(FacilityMap.STAIR_ICON_WHITE.is_equal_approx(Color("f4f7f6")),
		"admin/fullscreen stair markers are not the requested white icon")
	var map_region_colours := {}
	for region in StreamedRouteGenerator.BIOMES:
		_expect(ResourceLoader.exists("res://art/props-3d/environment/floor_%s.png" % region) \
			and ResourceLoader.exists("res://art/props-3d/environment/wall_%s.png" % region),
			"%s is missing its regional floor/wall texture pair" % region)
		_expect(FacilityMap.REGION_COLORS.has(region),
			"admin maps have no colour assigned for the %s region" % region)
		var colour_key := FacilityMap.region_color(region).to_html(false)
		_expect(not map_region_colours.has(colour_key),
			"admin map region colour is duplicated for %s" % region)
		map_region_colours[colour_key] = region
	for office_void in HunterRoster.OFFICE_VOID_IDS:
		_expect(HunterRoster.VOID_IDS.has(office_void) \
			and String(HunterRoster.get_identity(office_void).get("category", "")) == "void",
			"Office rare-spawn mapping points at an unsupported Void: %s" % office_void)
	var coords := [Vector3i.ZERO, Vector3i(1, 0, 0), Vector3i(-3, 0, 4)]
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
	var map_probe := FacilityMap.new()
	map_probe.interactive = true
	map_probe.size = Vector2(480, 320)
	host.get_tree().root.add_child(map_probe)
	map_probe.show_streamed_state({Vector3i.ZERO: lower}, 0,
		StreamedRouteGenerator.CHUNK_SIZE, Vector2.ZERO, Vector2.DOWN, [],
		true, 0, [], true)
	await host.get_tree().process_frame
	_expect(map_probe.streamed_show_regions,
		"streamed facility map ignored an authenticated region-overlay request")
	map_probe.show_streamed_state({Vector3i.ZERO: lower}, 0,
		StreamedRouteGenerator.CHUNK_SIZE, Vector2.ZERO, Vector2.DOWN, [])
	_expect(not map_probe.streamed_show_regions,
		"region-overlay state leaked into a normal player map update")
	map_probe.queue_free()
	await host.get_tree().process_frame
	var map_peer_source := RemotePlayers.new()
	map_peer_source.set("_states", {
		2: {"position": Vector2(9.5, 10.5), "depth": 0,
			"facing": Vector2.RIGHT, "display_name": "MAP-PEER",
			"received_usec": Time.get_ticks_usec()},
	})
	_expect(map_peer_source.remote_player_marks(0).size() == 1 \
		and map_peer_source.remote_player_marks(1).is_empty(),
		"replicated co-op player marks are not filtered by fresh same-floor depth")
	map_peer_source.free()
	_expect(world.is_safe_room(Vector3i.ZERO), "origin chunk is not a temporary safe room")
	var chunk_center := StreamedRouteGenerator.CHUNK_SIZE / 2
	_expect(world.spawn_chunk() == Vector3i.ZERO \
		and world.spawn_cell() == Vector2i(chunk_center, chunk_center),
		"streamed spawn is not centered on level zero")
	var origin_floor_count := 0
	for row in lower["grid"]:
		for cell in row:
			origin_floor_count += 1 if int(cell) == 0 else 0
	_expect(origin_floor_count >= 400,
		"spawn chunk is effectively empty (%d open floor cells)" % origin_floor_count)
	_expect(GameConfig.hunter_activation_relay_count("relaxed") == 3 \
		and GameConfig.hunter_activation_relay_count("standard") == 1 \
		and GameConfig.hunter_activation_relay_count("hard") == 0,
		"Infinite hunter activation does not follow relaxed=3/standard=1/hard=instant")
	_expect(GameConfig.streamed_hunter_population("relaxed", 2) == 0 \
		and GameConfig.streamed_hunter_population("relaxed", 3) == 1 \
		and GameConfig.streamed_hunter_population("relaxed", 6) == 2 \
		and GameConfig.streamed_hunter_population("standard", 1) == 1 \
		and GameConfig.streamed_hunter_population("standard", 3) == 2 \
		and GameConfig.streamed_hunter_population("hard", 0) == 1 \
		and GameConfig.streamed_hunter_population("hard", 1) == 2 \
		and GameConfig.streamed_hunter_population("standard", 101) == 51 \
		and GameConfig.streamed_hunter_population("hard", 100) == 101,
		"relay count does not progressively expand the Infinite hunter population")
	_expect(GameConfig.anti_idle_hunter_seconds("relaxed") \
			> GameConfig.anti_idle_hunter_seconds("standard") \
			and GameConfig.anti_idle_hunter_seconds("standard") \
			> GameConfig.anti_idle_hunter_seconds("hard") \
			and GameConfig.anti_afk_hunter_seconds("standard") \
			< GameConfig.anti_idle_hunter_seconds("standard") \
			and GameConfig.anti_afk_warning_seconds() > 0.0 \
			and GameConfig.anti_afk_warning_seconds() \
				< GameConfig.anti_afk_hunter_seconds("nightmare") \
			and HunterRoster.VOID_IDS.has("void_gray"),
		"Gray Void anti-AFK/relay-inactivity pressure is not difficulty tuned")
	var arrival_hunters: Array = world.chunk(Vector3i(1, 0, 0))["hunter_spawns"]
	_expect(not arrival_hunters.is_empty(),
		"initial streamed window contains no deterministic hunter")
	if not arrival_hunters.is_empty():
		var activation_state := StreamedWorldStateScript.new()
		var arrival_state := activation_state.ensure_hunter(arrival_hunters[0])
		_expect(not bool(arrival_state.get("active", true)),
			"streamed hunter state starts active before its difficulty gate")

	var biomes := {}
	var pickup_ids := {}
	var hunter_ids := {}
	var dressed_biomes := {}
	var first_hunter_spawn: Dictionary = {}
	var saw_hotel_layout := false
	var saw_prison_layout := false
	var room_sizes := {}
	var pickup_kinds := {}
	var fixture_count := 0
	var furniture_actions := {}
	var rug_types_seen := {}
	var first_relay_id := ""
	var room_templates_seen := {}
	var suite_kinds_seen := {}
	var suite_roles_seen := {}
	var saw_multi_unit_apartment_hall := false
	var restaurant_room_props := {}
	var prison_cafeteria_props := {}
	var saw_office_job_desk := false
	var saw_prison_cell_generic := false
	var saw_dual_lower := false
	var saw_dual_upper := false
	var saw_dual_carousel := false
	var saw_two_cell_double_door := false
	for level in [0]:
		for z in range(-12, 13):
			for x in range(-12, 13):
				var sampled_coord := Vector3i(x, level, z)
				if not world.is_chunk_allowed(sampled_coord):
					continue
				var data := world.chunk(sampled_coord)
				biomes[data["biome"]] = true
				var dual_contract: Dictionary = data.get("dual_level_room", {})
				if not dual_contract.is_empty():
					if String(dual_contract.get("role", "")) == "lower":
						saw_dual_lower = true
						_expect(not (data.get("ceiling_voids", []) as Array).is_empty(),
							"dual-level lower room retained a blocking middle ceiling")
					else:
						saw_dual_upper = true
						_expect(not (data.get("floor_voids", []) as Array).is_empty() \
							and not (data.get("structural_voids", []) as Array).is_empty(),
							"dual-level upper volume retained a duplicate floor/wall stack")
				for suite_value in data.get("suites", []):
					var suite: Dictionary = suite_value
					var suite_id := String(suite.get("id", ""))
					var suite_kind := String(suite.get("kind", ""))
					var suite_rect: Rect2i = suite.get("rect", Rect2i())
					suite_kinds_seen[suite_kind] = true
					var parent_count := 0
					var child_ids := []
					var child_roles := {}
					for suite_room_value in data.get("rooms", []):
						var suite_room: Dictionary = suite_room_value
						if String(suite_room.get("suite_id", "")) != suite_id:
							continue
						if bool(suite_room.get("suite_parent", false)):
							parent_count += 1
							_expect(String(suite_room.get("id", "")) \
								== String(suite.get("parent_room_id", "")) \
								and suite_room.get("doorway", Vector2i(-1, -1)) \
								== suite.get("entry_doorway", Vector2i(-2, -2)),
								"%s suite entry room lost its shared exterior threshold" % suite_id)
						else:
							var child_id := String(suite_room.get("id", ""))
							var child_role := String(suite_room.get("suite_role", ""))
							child_ids.append(child_id)
							child_roles[child_role] = true
							suite_roles_seen[child_role] = true
					_expect(suite_kind in ["apartment", "office"] \
						and suite_rect.size == Vector2i(17, 17),
						"unsupported or clipped generated suite: %s" % suite)
					_expect(parent_count == 1 and child_ids.size() == 4,
						"%s is not one shared entry plus four amenity rooms" % suite_id)
					var recorded_children: Array = suite.get("room_ids", [])
					_expect(recorded_children.size() == 4 \
						and recorded_children.all(func(child_id: String) -> bool:
							return child_ids.has(child_id)),
						"%s suite metadata does not own its four generated rooms" % suite_id)
					var expected_roles := ["bedroom", "kitchen", "living_room",
						"house_bathroom"] if suite_kind == "apartment" else [
						"office_reception", "cubicle_room", "office_job",
						"private_office"]
					_expect(child_roles.size() == expected_roles.size() \
						and expected_roles.all(func(role: String) -> bool:
							return child_roles.has(role)),
						"%s suite omitted a required amenity: %s" % [suite_id,
							expected_roles])
				if String(data.get("biome", "")) == "apartment":
					var apartment_units := (data.get("suites", []) as Array).filter(
						func(suite: Dictionary) -> bool:
							return String(suite.get("kind", "")) == "apartment")
					saw_multi_unit_apartment_hall = saw_multi_unit_apartment_hall \
						or apartment_units.size() >= 2
				for room in data["rooms"]:
					var size: Vector2i = room["size"]
					room_sizes["%dx%d" % [size.x, size.y]] = true
				var occupied_stair_bays := {}
				var occupied_stair_access := {}
				for stair_value in data.get("stairs", []):
					var stair: Dictionary = stair_value
					var bay := StreamedRouteGenerator.stair_bay_index(
						stair.get("cell", Vector2i.ZERO))
					_expect(not occupied_stair_bays.has(bay),
						"%s put multiple vertical flights in stairwell bay %d" \
						% [data["coord"], bay])
					occupied_stair_bays[bay] = stair.get("id", "")
					for access_cell in StreamedRouteGenerator.stair_access_cells(
							stair.get("cell", Vector2i.ZERO)):
						_expect(not occupied_stair_access.has(access_cell),
							"%s generated intersecting stair access at %s" \
							% [data["coord"], access_cell])
						occupied_stair_access[access_cell] = stair.get("id", "")
				if data["biome"] == "hotel":
					saw_hotel_layout = data["rooms"].size() >= 6 \
						and data["corridors"].any(func(hall):
							return bool(hall.get("serves_many_rooms", false)))
				if data["biome"] == "prison":
					saw_prison_layout = saw_prison_layout or (data["rooms"].size() >= 6 \
						and data["rooms"].all(func(room):
							return room["room_type"] in ["prison_cell",
								"prison_cafeteria", "stairwell"]))
				var center := StreamedRouteGenerator.CHUNK_SIZE / 2
				for axis_offset in range(-1, 2):
					for axis_cell in range(1, StreamedRouteGenerator.CHUNK_SIZE - 1):
						_expect(int(data["grid"][center + axis_offset][axis_cell]) == 0 \
							and int(data["grid"][axis_cell][center + axis_offset]) == 0,
							"%s central hall narrowed below three cells" % data["coord"])
				for corridor_value in data["corridors"]:
					var corridor: Dictionary = corridor_value
					_expect(int(corridor.get("width", 0)) == StreamedRouteGenerator.CORRIDOR_WIDTH,
						"recorded corridor is not three cells wide: %s" % corridor)
				_expect((data["corridors"] as Array).any(func(corridor: Dictionary) -> bool:
					return bool(corridor.get("branch", false)) \
						and bool(corridor.get("from_main_hall", false))),
					"%s has no secondary hall branching from its main cross" % data["coord"])
				for room_value in data["rooms"]:
					var room: Dictionary = room_value
					var stair_rect: Rect2i = room.get("rect", Rect2i())
					if String(room.get("room_type", "")) != "stairwell":
						var canonical_doorway: Vector2i = room.get("doorway",
							Vector2i(-999, -999))
						var expected_doorway_cells := [canonical_doorway]
						for door_value in data.get("region_props", []):
							var candidate_door: Dictionary = door_value
							if bool(candidate_door.get("room_door", false)) \
									and String(candidate_door.get("room_id", "")) \
									== String(room.get("id", "")):
								expected_doorway_cells = candidate_door.get(
									"doorway_cells", [candidate_door.get("cell",
										canonical_doorway)])
								break
						var open_boundary := []
						for horizontal_x in range(stair_rect.position.x, stair_rect.end.x):
							for horizontal_z in [stair_rect.position.y, stair_rect.end.y - 1]:
								var horizontal_boundary := Vector2i(horizontal_x, horizontal_z)
								if int(data["grid"][horizontal_z][horizontal_x]) == 0 \
										and not open_boundary.has(horizontal_boundary):
									open_boundary.append(horizontal_boundary)
						for vertical_z in range(stair_rect.position.y, stair_rect.end.y):
							for vertical_x in [stair_rect.position.x, stair_rect.end.x - 1]:
								var vertical_boundary := Vector2i(vertical_x, vertical_z)
								if int(data["grid"][vertical_z][vertical_x]) == 0 \
										and not open_boundary.has(vertical_boundary):
									open_boundary.append(vertical_boundary)
						# Rooms of one apartment share walls: openings that are another room's door
						# (or declared extra doorways) on this boundary are legitimate.
						var allowed_openings: Array = expected_doorway_cells.duplicate()
						if room.has("suite_id"):
							for extra_value in room.get("extra_doorways", []):
								allowed_openings.append(extra_value)
							for door_value in data.get("region_props", []):
								var shared_door: Dictionary = door_value
								if bool(shared_door.get("room_door", false)):
									for shared_cell in shared_door.get("doorway_cells", []):
										allowed_openings.append(shared_cell)
							for sibling_value in data.get("rooms", []):
								var sibling: Dictionary = sibling_value
								if String(sibling.get("suite_id", "")) == String(room.get("suite_id", "")):
									if sibling.get("doorway") is Vector2i:
										allowed_openings.append(sibling["doorway"])
									for sibling_extra in sibling.get("extra_doorways", []):
										allowed_openings.append(sibling_extra)
						_expect((open_boundary.size() == expected_doorway_cells.size() \
								or (room.has("suite_id") and open_boundary.all(func(at):
									return allowed_openings.has(at)))) \
							and expected_doorway_cells.all(func(at):
								return open_boundary.has(at)),
							"room owns multiple hallway entrances: %s openings=%s doorway=%s" \
							% [room.get("id", ""), open_boundary, expected_doorway_cells])
						var corners := [stair_rect.position,
							Vector2i(stair_rect.end.x - 1, stair_rect.position.y),
							Vector2i(stair_rect.position.x, stair_rect.end.y - 1),
							stair_rect.end - Vector2i.ONE]
						for corner in corners:
							_expect(int(data["grid"][corner.y][corner.x]) != 0,
								"room can be entered through a cut corner: %s at %s" \
								% [room.get("id", ""), corner])
						continue
					_expect((room.get("stair_ids", []) as Array).size() == 1,
						"dedicated stairwell contains zero or multiple flights: %s" % room)
					for prop_value in data.get("region_props", []):
						var room_prop: Dictionary = prop_value
						_expect(not stair_rect.has_point(room_prop.get("cell", Vector2i.ZERO)),
							"stairwell contains an ordinary prop: %s" % room_prop)
				for prop_value in data.get("region_props", []):
					var prop: Dictionary = prop_value
					dressed_biomes[data["biome"]] = true
					_expect(PropModelCatalog.has_model(String(prop.get("type", ""))) \
							or bool(prop.get("arch", false)),
						"streamed region prop has no authored model: %s" % prop)
					var prop_cell: Vector2i = prop.get("cell", Vector2i.ZERO)
					_expect(int(data["grid"][prop_cell.y][prop_cell.x]) == 0,
						"streamed region prop landed off-floor at %s" % prop)
					var prop_yaw := float(prop.get("yaw", 999.0))
					_expect(is_equal_approx(prop_yaw,
						snappedf(prop_yaw, PI * .25)) and prop.has("facing_target"),
						"streamed prop is not room-facing on a 45-degree angle: %s" % prop)
					var prop_type := String(prop.get("type", ""))
					var room_template := String(prop.get("room_template", ""))
					if not room_template.is_empty():
						room_templates_seen[room_template] = true
						var owning_room_id := String(prop.get("room_id", ""))
						_expect((data.get("rooms", []) as Array).any(
							func(room: Dictionary) -> bool:
								return String(room.get("id", "")) == owning_room_id),
							"furnished prop lost its owning generated room: %s" % prop)
						if room_template == "restaurant_dining":
							var restaurant_counts: Dictionary = restaurant_room_props.get(
								owning_room_id, {})
							restaurant_counts[prop_type] = int(restaurant_counts.get(
								prop_type, 0)) + 1
							restaurant_room_props[owning_room_id] = restaurant_counts
						if room_template == "prison_cafeteria":
							var cafeteria_counts: Dictionary = prison_cafeteria_props.get(
								owning_room_id, {})
							cafeteria_counts[prop_type] = int(cafeteria_counts.get(
								prop_type, 0)) + 1
							prison_cafeteria_props[owning_room_id] = cafeteria_counts
						if room_template == "office_job" \
								and prop_type == "officeDesk":
							saw_office_job_desk = true
					if RoomCatalog.is_surface_prop(prop_type) \
							and float(prop.get("mount_y", 0.0)) > 0.0:
						var seated := (data.get("region_props", []) as Array).any(
							func(other_value) -> bool:
								return RoomCatalog.surface_parent_covers(
									other_value, prop))
						_expect(seated,
							"surface prop %s is floating off its desk/table: %s" \
							% [prop_type, prop.get("id", prop_type)])
					if data["biome"] == "prison" \
							and prop_type in ["restaurantPartyTable",
								"woodenTable", "woodenChair",
								"normalKitchenCounter", "normalKitchenSink"]:
						saw_prison_cell_generic = true
					if bool(prop.get("dual_level_activity", false)) \
							and prop_type == "carouselCenterpiece":
						saw_dual_carousel = true
					if PropModelCatalog.is_floor_dressing(prop_type):
						rug_types_seen[prop_type] = true
						_expect(not bool(prop.get("solid", true)),
							"room rug unexpectedly blocks movement: %s" % prop)
					elif not bool(prop.get("solid", true)):
						_expect(PropModelCatalog.is_empty_frame(prop_type) \
							or bool(prop.get("arch", false)) \
							or PropModelCatalog.is_room_door(prop_type) \
							or PropModelCatalog.is_wall_mounted(prop_type) \
							or PropModelCatalog.is_ceiling_mounted(prop_type) \
							or RoomCatalog.is_surface_prop(prop_type),
							"unknown non-solid streamed decoration: %s" % prop_type)
					if PropModelCatalog.is_wall_mounted(prop_type):
						var mount_wall: Vector2i = prop.get("backing_wall", Vector2i.ZERO)
						var mount_open: Vector2i = prop.get("open_direction", Vector2i.ZERO)
						var mount_offset: Vector2 = prop.get("mount_offset", Vector2.ZERO)
						_expect(bool(prop.get("wall_mounted", false)) \
							and not bool(prop.get("solid", true)) \
							and mount_wall == -mount_open \
							and int(data["grid"][prop_cell.y + mount_wall.y]
								[prop_cell.x + mount_wall.x]) != 0 \
							and int(data["grid"][prop_cell.y + mount_open.y]
								[prop_cell.x + mount_open.x]) == 0,
							"mirror/frame is not mounted on a real room wall: %s" % prop)
						_expect(mount_offset.length() >= .42 \
							and mount_offset.normalized().is_equal_approx(Vector2(mount_wall)),
							"mirror/frame was not moved flush toward its backing wall: %s" % prop)
					if bool(prop.get("room_door", false)):
						_expect((PropModelCatalog.is_room_door(prop_type) or bool(prop.get("arch", false))) \
							and not bool(prop.get("solid", true)),
							"room threshold does not use a passable authored door: %s" % prop)
						var door_room: Dictionary = {}
						for room_value in data.get("rooms", []):
							var room: Dictionary = room_value
							if String(room.get("id", "")) == String(prop.get("room_id", "")):
								door_room = room
								break
						var door_rect: Rect2i = door_room.get("rect", Rect2i())
						var inward: Vector2i = prop.get("inward", Vector2i.ZERO)
						var outward: Vector2i = prop.get("outward", Vector2i.ZERO)
						var across: Vector2i = prop.get("across", Vector2i.ZERO)
						var door_span := int(prop.get("door_span", 1))
						var doorway_cells: Array = prop.get("doorway_cells", [prop_cell])
						var expects_double := prop_type.contains("Double")
						var placement_offset: Vector2 = prop.get(
							"placement_offset", Vector2.ZERO)
						var blocker_size: Vector3 = prop.get("blocker_size", Vector3.ZERO)
						_expect(door_span == (3 if bool(prop.get("arch", false)) else (2 if expects_double else 1)) \
							and doorway_cells.size() == door_span,
							"room door model/span mismatch: %s" % prop)
						_expect(is_equal_approx(float(prop.get("yaw", 0.0)),
							StreamedRouteGenerator._room_facing_yaw(prop_cell,
								prop_cell + inward)),
							"room door is not perpendicular to its wall: %s" % prop)
						if expects_double and doorway_cells.size() == 2:
							saw_two_cell_double_door = true
							_expect(doorway_cells[1] == prop_cell + across \
								and placement_offset.is_equal_approx(Vector2(across) * .5) \
								and blocker_size.x >= 2.0,
								"double door is not centered across two grid cells: %s" % prop)
						for doorway_value in doorway_cells:
							var doorway_cell: Vector2i = doorway_value
							_expect(not door_room.is_empty() \
								and door_rect.has_point(doorway_cell) \
								and door_rect.has_point(doorway_cell + inward) \
								and not door_rect.has_point(doorway_cell + outward),
								"room door lane is not across its room boundary: %s" % prop)
							_expect(int(data["grid"][doorway_cell.y][doorway_cell.x]) == 0 \
								and int(data["grid"][doorway_cell.y + outward.y]
									[doorway_cell.x + outward.x]) == 0 \
								and int(data["grid"][doorway_cell.y + inward.y]
									[doorway_cell.x + inward.x]) == 0,
								"room door lane does not connect traversable sides: %s" % prop)
						_expect(int(data["grid"][prop_cell.y - across.y]
							[prop_cell.x - across.x]) != 0 \
							and int(data["grid"][prop_cell.y + across.y * door_span]
								[prop_cell.x + across.x * door_span]) != 0,
							"room door has no structural wall frame: %s" % prop)
						for stair_value in data.get("stairs", []):
							var stair: Dictionary = stair_value
							for stair_cell in StreamedRouteGenerator.stair_path_cells(
									stair.get("cell", Vector2i.ZERO)):
								for doorway_value in doorway_cells:
									var doorway_cell: Vector2i = doorway_value
									_expect(doorway_cell.distance_to(stair_cell) > 3.0,
										"room door intersects a stair/access footprint: %s" % prop)
					var furniture_action := PropModelCatalog.interaction_for(prop_type)
					if not furniture_action.is_empty():
						furniture_actions[furniture_action] = true
				for pickup in data["pickups"]:
					pickup_kinds[String(pickup.get("kind", ""))] = true
					_expect(not pickup_ids.has(pickup["id"]),
						"duplicate streamed pickup id %s" % pickup["id"])
					pickup_ids[pickup["id"]] = true
					if String(pickup.get("kind", "")) == "relay" \
							and first_relay_id.is_empty():
						first_relay_id = String(pickup["id"])
				for fixture in data.get("fixtures", []):
					fixture_count += 1
					var fixture_cell: Vector2i = fixture.get("cell", Vector2i.ZERO)
					_expect(int(data["grid"][fixture_cell.y][fixture_cell.x]) == 0,
						"streamed hiding fixture landed off-floor at %s" % fixture)
					var backing_wall: Vector2i = fixture.get("backing_wall", Vector2i.ZERO)
					var open_direction: Vector2i = fixture.get("open_direction", Vector2i.ZERO)
					_expect(backing_wall == -open_direction \
						and int(data["grid"][fixture_cell.y + backing_wall.y]
							[fixture_cell.x + backing_wall.x]) != 0 \
						and int(data["grid"][fixture_cell.y + open_direction.y]
							[fixture_cell.x + open_direction.x]) == 0,
						"streamed locker/vent is not wall-backed with an open front: %s" % fixture)
					_expect(is_equal_approx(float(fixture.get("yaw", 999.0)),
						StreamedRouteGenerator._room_facing_yaw(fixture_cell,
							fixture_cell + open_direction)),
						"streamed locker/vent front is rotated toward its backing wall: %s" % fixture)
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
	_expect(suite_kinds_seen.has("apartment") and suite_kinds_seen.has("office"),
		"sampled world did not generate both apartment and office room suites")
	_expect(saw_multi_unit_apartment_hall,
		"apartment region never placed multiple complete units off one main hall")
	for suite_role in ["bedroom", "kitchen", "living_room", "house_bathroom",
			"office_reception", "cubicle_room", "office_job", "private_office"]:
		_expect(suite_roles_seen.has(suite_role),
			"generated suites never exposed the %s amenity" % suite_role)
	for biome in StreamedRouteGenerator.BIOMES:
		if biome != "prison":
			_expect(dressed_biomes.has(biome),
				"%s region produced no authored streamed dressing" % biome)
	# Rooms are furnished properly now: nothing below 7x7 (no closets or 3x3 cells).
	for expected_size in [Vector2i(7, 7), Vector2i(9, 7), Vector2i(7, 9), Vector2i(9, 9)]:
		_expect(StreamedRouteGenerator.ROOM_SIZES.has(expected_size),
			"requested room size %s is missing from the streamed catalog" % expected_size)
	for tiny_size in [Vector2i(3, 3), Vector2i(3, 5), Vector2i(5, 5), Vector2i(5, 7), Vector2i(7, 5)]:
		_expect(not StreamedRouteGenerator.ROOM_SIZES.has(tiny_size),
			"room size %s is too small to furnish and should not be generated" % tiny_size)
	_expect(room_sizes.size() >= 6,
		"streamed rooms did not vary enough in size: %s" % [room_sizes.keys()])
	_expect(room_sizes.has("15x15"),
		"15x15 landmark rooms were clipped out of generated topology")
	_expect(not rug_types_seen.is_empty(),
		"restored authored rugs/mats never appeared in sampled Infinite rooms")
	for expected_template in [
			"bedroom", "kitchen", "mansion_dining", "apartment_living",
			"restaurant_dining", "arcade", "house_bathroom",
			"hotel_bathroom", "luxury_bathroom", "public_restroom",
			"carnival_midway", "carnival_game_stall", "carnival_backstage",
			"frozen_tideline", "beach_hut", "lounge", "office_reception",
			"office_cubicles", "office_job", "private_office",
		]:
		_expect(room_templates_seen.has(expected_template),
			"streamed sample never furnished the %s room recipe" % expected_template)
	_expect(saw_office_job_desk,
		"office suites never furnished the office_job desk layout")
	_expect(not saw_prison_cell_generic,
		"prison rooms still scatter generic dining/kitchen silhouettes")
	_expect(not prison_cafeteria_props.is_empty(),
		"streamed sample produced no auditable prison cafeteria")
	var saw_complete_prison_cafeteria := false
	for cafeteria_room_id in prison_cafeteria_props:
		var cafeteria_counts: Dictionary = prison_cafeteria_props[cafeteria_room_id]
		if int(cafeteria_counts.get("prisonServingCounter", 0)) >= 1 \
				and int(cafeteria_counts.get("prisonCafeteriaTable", 0)) >= 1 \
				and int(cafeteria_counts.get("prisonTrayReturn", 0)) >= 1 \
				and int(cafeteria_counts.get("prisonKitchenRack", 0)) >= 1:
			saw_complete_prison_cafeteria = true
	_expect(saw_complete_prison_cafeteria,
		"no prison cafeteria received the dedicated serving set: %s" \
		% [prison_cafeteria_props])
	_expect(not restaurant_room_props.is_empty(),
		"streamed sample produced no auditable restaurant dining room")
	for restaurant_room_id in restaurant_room_props:
		var restaurant_counts: Dictionary = restaurant_room_props[restaurant_room_id]
		_expect(int(restaurant_counts.get("restaurantPartyTable", 0)) >= 2 \
			and int(restaurant_counts.get("woodenChairCushion", 0)) >= 12,
			"restaurant room %s lacks two complete six-chair party rows: %s" \
			% [restaurant_room_id, restaurant_counts])
	_expect(saw_two_cell_double_door,
		"sampled world never generated a true two-cell double doorway")
	_expect(furniture_actions.has("sit") and furniture_actions.has("lay") \
		and furniture_actions.has("mirror"),
		"streamed dressing omitted sit, lay, or mirror interactions")
	_expect(not pickup_ids.is_empty(), "streamed chunks produced no collectible ids")
	_expect(pickup_kinds.has("relay") and pickup_kinds.has("battery") \
		and pickup_kinds.has("tool") and pickup_kinds.has("backpack"),
		"streamed collectibles omitted a required pickup kind: %s" % [pickup_kinds.keys()])
	_expect(fixture_count > 0, "streamed chunks produced no hiding fixtures")
	_expect(not hunter_ids.is_empty(), "streamed chunks produced no persistent hunters")
	_expect(world.cached_chunk_count() <= StreamedRouteGenerator.CHUNK_CACHE_LIMIT,
		"deterministic chunk cache exceeded its bounded limit")
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
	_expect(mutations.apply_safe_room_status(safe_info["id"], 67, false) \
		and int(mutations.safe_room_status(safe_info)["integrity"]) == 67,
		"authoritative safe-room status could not be adopted")
	_expect(mutations.apply_checkpoint(safe_info["checkpoint_id"]),
		"authoritative checkpoint id could not be adopted")
	_expect(mutations.claim_pickup("test:item") and not mutations.claim_pickup("test:item"),
		"host mutation ledger allowed duplicate pickup ownership")
	_expect(not first_relay_id.is_empty() and mutations.claim_pickup(first_relay_id) \
		and mutations.set_relay_sabotaged(first_relay_id, true) \
		and mutations.relay_sabotaged(first_relay_id),
		"streamed relay sabotage was not retained by the host ledger")
	var drop := mutations.create_drop("crowbar", 17, Vector3(2, .1, 3), 0, 7)
	_expect(not drop.is_empty() and mutations.dropped_items.has(drop["id"]),
		"host could not create a durable dropped item")
	var door_id := "0:0:0:DOOR:99"
	_expect(mutations.apply_room_door_state(door_id, true, true) \
		and bool(mutations.room_door_status(door_id).get("broken", false)),
		"host could not retain an authoritative breached room door")
	var restored = StreamedWorldStateScript.new()
	_expect(restored.adopt(mutations.snapshot()) and not restored.pickup_available("test:item") \
		and restored.relay_sabotaged(first_relay_id) \
		and restored.dropped_items.has(drop["id"]) \
		and bool(restored.room_door_status(door_id).get("broken", false)),
		"late-join snapshot lost pickups, sabotage, dropped equipment, or door damage")
	_expect(not restored.claim_drop(String(drop["id"])).is_empty() \
		and restored.claim_drop(String(drop["id"])).is_empty(),
		"dropped item could be claimed more than once")
	var navigation_entities := StreamedHunterNavigation.new(world, 0, mutations)
	navigation_entities.refresh(0, [Vector3i.ZERO, Vector3i(1, 0, 0)])
	var first_refresh_generation := navigation_entities.refresh_generation()
	navigation_entities.refresh(0, [Vector3i(1, 0, 0), Vector3i.ZERO,
		Vector3i.ZERO])
	_expect(navigation_entities.refresh_generation() == first_refresh_generation,
		"unchanged hunter authority window rebuilt all navigation chunks")
	mutations.navigation_revision += 1
	navigation_entities.refresh(0, [Vector3i.ZERO, Vector3i(1, 0, 0)])
	_expect(navigation_entities.refresh_generation() == first_refresh_generation + 1,
		"hunter navigation ignored a real world mutation revision")
	_expect(not navigation_entities.relays.is_empty() \
		and not navigation_entities.batteries.is_empty() \
		and not navigation_entities.vents.is_empty() \
		and not navigation_entities.hiding_spots.is_empty(),
		"streamed hunter navigation omitted objectives, vents, or hiding fixtures")
	for backpack_id in PlayerController3D.BACKPACK_CAPACITY:
		_expect(ResourceLoader.exists(String(
			RouteInteractable3D.TOOL_PICKUP_MODELS.get(backpack_id, ""))),
			"%s is missing its authored world model" % backpack_id)
		_expect(not PlayerController3D.INVENTORY_ITEMS.has(backpack_id),
			"%s still occupies a physical inventory slot" % backpack_id)
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
	var active := world.coordinates_around(Vector2(
		StreamedRouteGenerator.CHUNK_SIZE + 1.0, -1.0), 0, 2)
	_expect(active.size() == 25 and active.has(Vector3i(1, 0, -1)),
		"stream radius did not produce the expected 5x5 active set")
	var arrival := world.coordinates_around(Vector2.ZERO, 0, 4)
	_expect(arrival.size() == 81 and arrival.has(Vector3i(-4, 0, -4)) \
		and arrival.has(Vector3i(4, 0, 4)) and world.is_chunk_allowed(Vector3i(2, 0, 0)),
		"the single floor is not unbounded horizontally")
	var seam_offset: int = world.edge_openings(Vector3i.ZERO, Vector2i.RIGHT)[0]
	var navigation := StreamedHunterNavigation.new(world, 0)
	navigation.refresh(0, [Vector3i.ZERO, Vector3i(1, 0, 0)])
	var seam_left := StreamedRouteGenerator.CHUNK_SIZE - 1
	var seam_right := StreamedRouteGenerator.CHUNK_SIZE
	var seam_path := navigation.find_path(Vector2i(seam_left, seam_offset),
		Vector2i(seam_right, seam_offset))
	_expect(seam_path.size() == 2,
		"streamed hunter navigation did not cross a canonical chunk seam")
	var floor_lookup := {}
	for cell_value in navigation.floor_cells():
		floor_lookup[cell_value] = true
	var diagonal_start: Variant = null
	var blocked_corner_start: Variant = null
	for cell_value in floor_lookup:
		var cell: Vector2i = cell_value
		var diagonal := cell + Vector2i.ONE
		if not floor_lookup.has(diagonal):
			continue
		var east_open := floor_lookup.has(cell + Vector2i.RIGHT)
		var south_open := floor_lookup.has(cell + Vector2i.DOWN)
		if east_open and south_open and diagonal_start == null:
			diagonal_start = cell
		elif (not east_open or not south_open) and blocked_corner_start == null:
			blocked_corner_start = cell
		if diagonal_start != null and blocked_corner_start != null:
			break
	_expect(diagonal_start != null,
		"streamed navigation fixture has no open diagonal test square")
	if diagonal_start != null:
		var open_start: Vector2i = diagonal_start
		var open_diagonal := navigation.find_path(open_start,
			open_start + Vector2i.ONE)
		_expect(open_diagonal.size() == 2,
			"streamed hunter navigation did not take an open diagonal step")
	_expect(blocked_corner_start != null,
		"streamed navigation fixture has no blocked-corner diagonal test square")
	if blocked_corner_start != null:
		var corner_start: Vector2i = blocked_corner_start
		var corner_path := navigation.find_path(corner_start,
			corner_start + Vector2i.ONE)
		_expect(corner_path.is_empty() or corner_path.size() > 2,
			"streamed hunter navigation cut diagonally through a blocked corner")
	_expect(navigation.has_line_of_sight(Vector2(seam_left + .5, seam_offset + .5),
		Vector2(seam_right + .5, seam_offset + .5)),
		"streamed hunter line of sight stopped at a matching chunk seam")

	# The data contract is only useful once a runner can stand on it. Instantiate
	# the debug route and exercise its real GridMap collision window, forced
	# vertical flights, chunk eviction and authored prison dressing.
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "VALIDATE-ONE-LEVEL"
	RoomState.map_scale = RoomState.Scale.INFINITE
	var live_scene: Node = (load("res://scenes/infinite_route_test.tscn") \
		as PackedScene).instantiate()
	host.get_tree().root.add_child(live_scene)
	await host.get_tree().process_frame
	# The streamed facility builds its initial collision window incrementally;
	# wait through that registration before asserting grounded contact.
	for _index in 8:
		await host.get_tree().physics_frame
	var facility := live_scene.get_node("World/StreamedFacility") as StreamedFacilityView3D
	var player := live_scene.get_node("World/Player") as PlayerController3D
	var remotes := live_scene.get_node("World/RemotePlayers") as RemotePlayers
	var pixel_effect := live_scene.get("pixel_signal_effect") as PixelSignalEffect
	_expect(pixel_effect != null and Settings.DEFAULT_PIXEL_EFFECT_PERCENT > 0.0 \
		and PixelSignalEffect.SHADER_CODE.contains("floor(pixel / block_size)"),
		"Infinite route has no persistent default pixel treatment")
	if pixel_effect != null:
		var old_pixel_strength: float = Settings.pixel_effect_percent
		Settings.pixel_effect_percent = 0.0
		pixel_effect.call("_refresh")
		var pixel_surface := pixel_effect.get("_surface") as ColorRect
		_expect(pixel_surface != null and not pixel_surface.visible,
			"zero pixel-effect strength still leaves a screen-space filter visible")
		Settings.pixel_effect_percent = old_pixel_strength
		pixel_effect.call("_refresh")
	_expect(facility != null and facility.loaded_chunk_count() == 9,
		"live stream did not hold the 3x3 chunk window of the single floor")
	_expect(not facility.get_tree().get_nodes_in_group("streamed_region_prop").is_empty(),
		"live streamed regions loaded no authored dressing models")
	var live_lower := facility.generator.chunk(Vector3i.ZERO)
	var regional_floor_items: Dictionary = facility.get("_floor_items")
	_expect(not regional_floor_items.is_empty() \
			and not regional_floor_items.values().has(1),
		"streamed view still reserves a regional floor item for seam overlays")
	var origin_structure := facility.get_node_or_null(
		"Chunk_0_0_0/Structure") as GridMap
	_expect(origin_structure != null and origin_structure.get_used_cells().size() \
		>= StreamedRouteGenerator.CHUNK_SIZE * StreamedRouteGenerator.CHUNK_SIZE,
		"live streamed chunk omitted structure")
	_expect(host.get_tree().get_nodes_in_group("streamed_stair").is_empty(),
		"the single-level route built a stair")
	var navigations: Dictionary = live_scene.get("_navigations")
	_expect(not host.get_tree().get_nodes_in_group("streamed_hiding_spot").is_empty(),
		"live streamed window contains no rendered hiding spots")
	_expect(host.get_tree().get_nodes_in_group("streamed_spawn_marker").size() == 1,
		"central Infinite spawn has no unique physical safe-zone marker")
	var live_relays := 0
	var live_batteries := 0
	var live_tools := 0
	for candidate in host.get_tree().get_nodes_in_group("interactable"):
		var interaction := candidate as RouteInteractable3D
		if interaction == null:
			continue
		match interaction.kind:
			RouteInteractable3D.Kind.RELAY:
				live_relays += 1
			RouteInteractable3D.Kind.BATTERY:
				live_batteries += 1
			RouteInteractable3D.Kind.TOOL_PICKUP:
				live_tools += 1
	_expect(live_relays >= 8 and live_batteries >= 4 and live_tools >= 1,
		"live Infinite window is under-populated (relays %d, batteries %d, tools %d)" \
		% [live_relays, live_batteries, live_tools])
	# One level: the freed height goes to the rooms. Corridors stay low, ordinary
	# rooms are one storey, halls two, greenhouses three.
	# One level: the freed height goes to the rooms, each picking its own ceiling
	# from the range for its kind (seeded by room id, so every peer agrees).
	var height_ok := true
	for room_id in ["a", "b", "c", "d", "e"]:
		height_ok = height_ok \
			and RefLook.room_height("maze", "", room_id) >= RefLook.CORRIDOR_RANGE.x \
			and RefLook.room_height("maze", "", room_id) <= RefLook.CORRIDOR_RANGE.y \
			and RefLook.room_height("maze", "office_job", room_id) >= RefLook.ROOM_RANGE.x \
			and RefLook.room_height("maze", "office_job", room_id) <= RefLook.ROOM_RANGE.y \
			and RefLook.room_height("mansion", "dining_room", room_id) >= RefLook.HALL_RANGE.x \
			and RefLook.room_height("mansion", "dining_room", room_id) <= RefLook.HALL_RANGE.y \
			and RefLook.room_height("beach", "cove", room_id) >= RefLook.GREENHOUSE_RANGE.x \
			and RefLook.room_height("beach", "cove", room_id) <= RefLook.MAX_HEIGHT
	_expect(height_ok and RefLook.room_height("maze", "office_job", "x") == RefLook.room_height("maze", "office_job", "x") \
		and RefLook.CORRIDOR_RANGE.y <= RefLook.HALL_RANGE.y and RefLook.ROOM_RANGE.y <= RefLook.HALL_RANGE.y \
		and RefLook.HALL_RANGE.y <= RefLook.GREENHOUSE_RANGE.y,
		"room heights leave their per-kind ranges or are not deterministic")
	_expect(RefLook.MAX_HEIGHT <= 7.5 and RefLook.CORRIDOR_RANGE.x >= 3.0,
		"ceiling heights are outside the playable range")
	_expect(player.is_on_floor(), "streamed player did not settle on generated floor collision")
	player.admin_god_mode = true
	player.stamina = 7.0
	player.exhausted = true
	player.call("_update_stamina", 1.0, true)
	_expect(is_equal_approx(player.stamina, GameConfig.MAX_STAMINA) \
		and not player.exhausted,
		"god mode still consumes stamina or leaves the runner exhausted")
	player.admin_god_mode = false
	var runtime_hunters: Dictionary = live_scene.get("_hunter_views")
	_expect(runtime_hunters.is_empty(),
		"Standard spawned a hunter before its first relay")
	GameState.relays_collected = 1
	live_scene.call("_refresh_hunter_stream")
	var one_relay_population := runtime_hunters.size()
	GameState.relays_collected = 3
	live_scene.call("_refresh_hunter_stream")
	_expect(one_relay_population == 1 and runtime_hunters.size() >= 2,
		"collecting more relays did not materialize additional hunters")
	# Infinite is the primary route now, so Porcelle's map counterplay must not
	# exist only in the retained finite implementation. She keeps the ghost-tagged
	# fullscreen floor-map marker while remaining absent from the always-on minimap.
	if not runtime_hunters.is_empty():
		var map_entity_id := String(runtime_hunters.keys()[0])
		var map_test_hunter := runtime_hunters[map_entity_id] as HunterView3D
		var map_hunter_levels: Dictionary = live_scene.get("_hunter_levels")
		var original_hunter_level := int(map_hunter_levels.get(map_entity_id,
			facility.current_level()))
		var original_hunter_id := map_test_hunter.brain.hunter_id
		map_hunter_levels[map_entity_id] = facility.current_level()
		map_test_hunter.brain.hunter_id = "porcelle"
		map_test_hunter.brain.active = true
		var original_reveal := bool(live_scene.get("_admin_reveal_hunters"))
		live_scene.set("_admin_reveal_hunters", false)
		var full_marks: Array = live_scene.call("_streamed_map_marks",
			facility.current_level(), true)
		var minimap_marks: Array = live_scene.call("_streamed_map_marks",
			facility.current_level(), false)
		_expect(full_marks.any(func(mark: Dictionary) -> bool:
			return String(mark.get("hunter_id", "")) == "porcelle" \
				and bool(mark.get("ghost", false))),
			"Infinite fullscreen map lacks Porcelle's faint ghost marker")
		_expect(not minimap_marks.any(func(mark: Dictionary) -> bool:
			return String(mark.get("hunter_id", "")) == "porcelle"),
			"Infinite minimap exposes Porcelle without opening the floor map")
		map_test_hunter.brain.hunter_id = original_hunter_id
		map_hunter_levels[map_entity_id] = original_hunter_level
		live_scene.set("_admin_reveal_hunters", original_reveal)
	var pressure_world_state: StreamedWorldState = live_scene.get("world_state")
	var saved_hunter_states := pressure_world_state.hunters.duplicate(true)
	pressure_world_state.hunters.clear()
	_expect(not bool(live_scene.call("_void_auto_spawn_allowed", "void_red")),
		"a non-Gray Void hunter spawned before the A-Z roster was complete")
	_expect(bool(live_scene.call("_void_auto_spawn_allowed", "void_gray")),
		"Gray anti-idle hunter was incorrectly blocked before the A-Z roster")
	for hunter_id in HunterRoster.A_Z_IDS:
		pressure_world_state.hunters["ROSTER-CHECK:%s" % hunter_id] = {
			"hunter_id": hunter_id}
	_expect(bool(live_scene.call("_void_auto_spawn_allowed", "void_red")),
		"Void hunters stayed blocked after all 26 A-Z hunters were present")
	pressure_world_state.hunters = saved_hunter_states
	var unique_identities := {}
	for hunter_state_value in pressure_world_state.hunters.values():
		var hunter_state: Dictionary = hunter_state_value
		unique_identities[String(hunter_state.get("hunter_id", ""))] = true
	_expect(unique_identities.size() == pressure_world_state.hunters.size(),
		"streamed population spawned duplicate hunter characters before exhausting the roster")
	var pressure_hunter_count := pressure_world_state.hunters.size()
	live_scene.set("_anti_idle_last_relay_count", GameState.relays_collected)
	live_scene.set("_relay_inactivity_seconds",
		GameConfig.anti_idle_hunter_seconds(RoomState.difficulty_id()))
	live_scene.call("_update_anti_idle_pressure", .01)
	var gray_pressure_hunters := pressure_world_state.hunters.values().filter(
		func(state_value) -> bool:
			var state: Dictionary = state_value
			return String(state.get("hunter_id", "")) == "void_gray" \
				and bool(state.get("active", false)))
	# A generated Gray may already be part of the unique roster. In that case
	# pressure wakes and redirects her instead of manufacturing a duplicate.
	_expect(pressure_world_state.hunters.size() >= pressure_hunter_count \
			and pressure_world_state.hunters.size() <= pressure_hunter_count + 1 \
			and gray_pressure_hunters.size() == 1,
		"relay inactivity did not wake one active Gray Void hunter (%d -> %d, gray %d)" \
			% [pressure_hunter_count, pressure_world_state.hunters.size(),
				gray_pressure_hunters.size()])
	var after_first_gray := pressure_world_state.hunters.size()
	live_scene.set("_relay_inactivity_seconds",
		GameConfig.anti_idle_hunter_seconds(RoomState.difficulty_id()))
	live_scene.call("_update_anti_idle_pressure", .01)
	var gray_after_repeat := pressure_world_state.hunters.values().filter(
		func(state_value) -> bool:
			return String((state_value as Dictionary).get("hunter_id", "")) == "void_gray")
	_expect(pressure_world_state.hunters.size() == after_first_gray \
			and gray_after_repeat.size() == 1,
		"repeated anti-idle pressure cloned the Gray Void hunter")
	pressure_world_state.claimed_pickups["TEST:PICKUP:RELAY:RESET"] = true
	live_scene.call("_sync_stream_progress")
	var gray_after_relay := pressure_world_state.hunters.values().filter(
		func(state_value) -> bool:
			return String((state_value as Dictionary).get("hunter_id", "")) == "void_gray")
	_expect(gray_after_relay.is_empty(),
		"collecting a relay did not despawn Gray Void pressure immediately")
	var idle_target := {"peer_id": 1, "position": player.grid_position(),
		"game_over": false}
	live_scene.set("_party_activity_anchors", {})
	var first_idle_sample := bool(live_scene.call(
		"_party_moved_since_pressure_sample", [idle_target]))
	var second_idle_sample := bool(live_scene.call(
		"_party_moved_since_pressure_sample", [idle_target]))
	_expect(first_idle_sample and not second_idle_sample,
		"anti-AFK tracking does not distinguish movement from a stationary party")
	var afk_delay := GameConfig.anti_afk_hunter_seconds(RoomState.difficulty_id())
	var warning_window := GameConfig.anti_afk_warning_seconds()
	live_scene.set("_party_afk_seconds", afk_delay - warning_window + 0.5)
	_expect(float(live_scene.call("_afk_void_warning_remaining")) > 0.0,
		"AFK warning did not arm before the existing kill delay")
	live_scene.call("_present_afk_void_warning")
	var hold_text := String(live_scene.hud.get("_hold_message"))
	var toast_text := String(live_scene.hud.message_label.text)
	_expect(hold_text.begins_with("STATIONARY // THREAT") \
			and toast_text == "STATIONARY // THREAT APPROACHING" \
			and not hold_text.contains("VOID") and not toast_text.contains("VOID") \
			and not hold_text.contains("GRAY") and not toast_text.contains("GRAY"),
		"AFK warning still names a hunter")
	var facing_target := idle_target.duplicate()
	facing_target["facing"] = Vector2(0, 1)
	live_scene.call("_party_moved_since_pressure_sample", [facing_target])
	var turned_target := facing_target.duplicate()
	turned_target["facing"] = Vector2(1, 0)
	_expect(bool(live_scene.call("_party_moved_since_pressure_sample",
			[turned_target])),
		"looking around did not break the AFK warning sample")
	live_scene.set("_party_afk_seconds", 0.0)
	live_scene.call("_present_afk_void_warning")
	_expect(is_equal_approx(float(live_scene.call("_afk_void_warning_remaining")),
			0.0),
		"AFK warning stayed armed after idle broke")
	if not runtime_hunters.is_empty():
		var test_hunter_id := String(runtime_hunters.keys()[0])
		var test_hunter := runtime_hunters[test_hunter_id] as HunterView3D
		var hunter_levels: Dictionary = live_scene.get("_hunter_levels")
		hunter_levels[test_hunter_id] = facility.current_level()
		test_hunter.brain.active = true
		test_hunter.brain.position = player.grid_position() + Vector2(2.0, 0.0)
		test_hunter.target_peer_id = 1
		_expect(bool(live_scene.call("_hunter_audio_on_floor", test_hunter_id,
			facility.current_level())), "same-floor hunter was incorrectly muted")
		hunter_levels[test_hunter_id] = facility.current_level() + 1
		_expect(not bool(live_scene.call("_hunter_audio_on_floor", test_hunter_id,
			facility.current_level())), "hunter audio leaked from an adjacent floor")
		hunter_levels[test_hunter_id] = facility.current_level()
		live_scene.set("_admin_reveal_hunters", true)
		live_scene.call("_update_streamed_maps")
		_expect(not live_scene.hud.minimap.hunters.is_empty(),
			"admin hunter reveal does not place hunters on the minimap")
		live_scene.set("_admin_reveal_hunters", false)
		_expect(test_hunter is CharacterBody3D \
			and test_hunter.get_node_or_null("HunterCollision") is CollisionShape3D,
			"streamed hunter has no grounded gravity/collision body")
		var unsafe_data := facility.generator.chunk(Vector3i(1, 0, 0))
		_expect(int(live_scene.call("_live_danger_percent", live_lower)) == 0 \
			and int(live_scene.call("_live_danger_percent", unsafe_data)) > 0,
			"live danger meter ignores safe-room protection or active pressure")
		test_hunter.brain.apply_stun(60.0)
	var minimap_panel: Control = live_scene.hud.minimap.get_parent() as Control
	var discovered: Dictionary = live_scene.get("_discovered_chunks")
	_expect(minimap_panel != null and minimap_panel.visible and not discovered.is_empty(),
		"Infinite discovered minimap is hidden or contains no generated chunks")
	var origin_map: Dictionary = discovered.get(Vector3i.ZERO, {})
	_expect(origin_map.get("spawn", Vector2i(-1, -1)) == world.spawn_cell(),
		"starting safe-zone marker is absent from discovered map data")
	var claimed_map_test_id := "VALIDATION:CLAIMED:MAP:ITEM"
	var map_world_state: StreamedWorldState = live_scene.get("world_state")
	map_world_state.claim_pickup(claimed_map_test_id)
	var filtered_map_test: Dictionary = live_scene.call(
		"_map_chunk_with_available_pickups", {"pickups": [
			{"id": claimed_map_test_id, "kind": "relay", "cell": Vector2i.ONE},
			{"id": "VALIDATION:AVAILABLE:MAP:ITEM", "kind": "battery",
				"cell": Vector2i(2, 2)},
		]})
	_expect((filtered_map_test.get("pickups", []) as Array).size() == 1 \
		and String(filtered_map_test["pickups"][0].get("id", "")) \
			== "VALIDATION:AVAILABLE:MAP:ITEM",
		"claimed relay/item marker remained on the Infinite minimap")
	var hidden_marker_id := "VALIDATION:HIDDEN:ROOM:RELAY"
	var hidden_prop_id := "VALIDATION:HIDDEN:ROOM:PROP"
	var discovery_test: Dictionary = live_scene.call(
		"_map_chunk_with_available_pickups", {
			"pickups": [{"id": hidden_marker_id, "discovery_id": hidden_marker_id,
				"kind": "relay", "cell": Vector2i(3, 3)}],
			"props": [{"id": hidden_prop_id, "discovery_id": hidden_prop_id,
				"kind": "prop", "cell": Vector2i(4, 3)}],
		})
	_expect((discovery_test.get("pickups", []) as Array).is_empty() \
		and (discovery_test.get("props", []) as Array).is_empty(),
		"undiscovered room markers leaked onto the player map")
	var discovered_markers: Dictionary = live_scene.get("_discovered_map_markers")
	discovered_markers[hidden_marker_id] = true
	discovered_markers[hidden_prop_id] = true
	discovery_test = live_scene.call("_map_chunk_with_available_pickups", {
		"pickups": [{"id": hidden_marker_id, "discovery_id": hidden_marker_id,
			"kind": "relay", "cell": Vector2i(3, 3)}],
		"props": [{"id": hidden_prop_id, "discovery_id": hidden_prop_id,
			"kind": "prop", "cell": Vector2i(4, 3)}],
	})
	_expect((discovery_test.get("pickups", []) as Array).size() == 1 \
		and (discovery_test.get("props", []) as Array).size() == 1,
		"entering/discovering a room did not reveal its relay and prop markers")
	# The room seed is intentionally random in this live-scene pass, so a fixed
	# map coordinate can be a wall. Choose the farthest currently discovered
	# open cell which the real GPS grid can actually reach from the player.
	var waypoint_player_cell := Vector2i(floori(player.global_position.x),
		floori(player.global_position.z))
	var validation_waypoint_cell := waypoint_player_cell
	var validation_waypoint_route := []
	for waypoint_z in StreamedRouteGenerator.CHUNK_SIZE:
		for waypoint_x in StreamedRouteGenerator.CHUNK_SIZE:
			var candidate_waypoint := Vector2i(waypoint_x, waypoint_z)
			var candidate_route: Array = live_scene.call("_discovered_waypoint_path",
				waypoint_player_cell, candidate_waypoint, facility.current_level())
			if candidate_route.size() > validation_waypoint_route.size():
				validation_waypoint_cell = candidate_waypoint
				validation_waypoint_route = candidate_route
	_expect(validation_waypoint_route.size() >= 2,
		"discovered floor produced no reachable waypoint destination")
	live_scene.call("_on_map_waypoint_requested",
		Vector2(validation_waypoint_cell) + Vector2(.2, .2),
		facility.current_level())
	var waypoints: Array = live_scene.get("_map_waypoints")
	_expect(waypoints.size() == 1 \
		and (waypoints[0].get("at", Vector2.ZERO) as Vector2).is_equal_approx(
			Vector2(validation_waypoint_cell) + Vector2(.5, .5)) \
		and live_scene.hud.plan.waypoints.size() == 1,
		"fullscreen map did not create and render a snapped player waypoint")
	var gps_route: Array = live_scene.get("_waypoint_route")
	var gps_trail := live_scene.get("_waypoint_trail") as MeshInstance3D
	_expect(gps_route.size() >= 2 \
		and live_scene.hud.minimap.waypoint_path == gps_route \
		and live_scene.hud.plan.waypoint_path == gps_route,
		"player waypoint did not produce a discovery-safe GPS map line")
	_expect(gps_trail != null and gps_trail.mesh != null,
		"player waypoint did not produce a visible ground trail")
	var waypoint_player_position := player.global_position
	var waypoint_at: Vector2 = waypoints[0].get("at", Vector2.ZERO)
	player.global_position = Vector3(waypoint_at.x + 4.0,
		waypoint_player_position.y, waypoint_at.y)
	live_scene.call("_clear_reached_waypoints", facility.current_level())
	_expect((live_scene.get("_map_waypoints") as Array).is_empty(),
		"waypoint remained after the player entered its five-cell arrival radius")
	player.global_position = waypoint_player_position
	live_scene.hud.map_overlay.visible = true
	live_scene.call("_update_hud")
	_expect(not live_scene.hud.minimap.streamed_show_stairs \
		and live_scene.hud.plan.streamed_show_stairs,
		"minimap/full-map stair visibility is not separated")
	for coord_value in live_scene.hud.minimap.streamed_chunks:
		_expect((coord_value as Vector3i).y == facility.current_level(),
			"minimap leaked geometry from another vertical floor")
	var current_level := facility.current_level()
	var mixed_floor_chunks := {
		Vector3i(0, current_level, 0): {"walls": PackedByteArray()},
		Vector3i(0, current_level + 1, 0): {"walls": PackedByteArray()},
	}
	var mixed_floor_players := [
		{"at": Vector2(2.5, 3.5), "name": "SAME-FLOOR", "level": current_level},
		{"at": Vector2(4.5, 5.5), "name": "OTHER-FLOOR", "level": current_level + 1},
	]
	live_scene.hud.update_streamed_minimap(mixed_floor_chunks, current_level,
		StreamedRouteGenerator.CHUNK_SIZE, Vector2.ZERO, Vector2.UP, [],
		mixed_floor_players)
	_expect(live_scene.hud.minimap.streamed_chunks.size() == 1 \
		and live_scene.hud.minimap.streamed_chunks.has(Vector3i(0, current_level, 0)),
		"minimap accepted mixed-floor data instead of enforcing one current floor")
	_expect(live_scene.hud.minimap.players.size() == 1 \
		and String(live_scene.hud.minimap.players[0].get("name", "")) == "SAME-FLOOR",
		"co-op map leaked an off-floor runner or hid the same-floor runner")
	_expect(live_scene.hud.minimap.streamed_focus_radius_cells \
		== HUD.STREAMED_MINIMAP_RADIUS_CELLS \
		and HUD.STREAMED_MINIMAP_RADIUS_CELLS <= 18,
		"Infinite minimap remains too far zoomed out around the runner")
	live_scene.hud.map_overlay.visible = false
	_expect(not discovered.has(Vector3i(20, 0, 20)),
		"undiscovered distant chunk leaked onto the Infinite map")
	var live_admin: AdminMenu = live_scene.get("_admin_menu") as AdminMenu
	_expect(live_admin != null, "Infinite route did not attach its admin menu")
	if live_admin != null:
		var admin_labels := []
		var admin_headings := {}
		for entry in live_admin._actions:
			admin_labels.append(String(entry.get("label", "")))
			if entry.has("heading"):
				admin_headings[String(entry["heading"])] = entry
			if entry.has("label") and not entry.has("heading"):
				_expect(entry.has("action") and (entry["action"] as Callable).is_valid(),
					"Infinite admin button is a stub: %s" % entry.get("label", ""))
		for required in ["TOGGLE NO TARGET", "TOGGLE GOD MODE", "TOGGLE NOCLIP",
				"STUN ALL HUNTERS", "WAKE ALL HUNTERS", "CALM ALL HUNTERS",
				"TOGGLE ALL REGION LIGHTS", "TOGGLE PIXEL EFFECT",
				"STOP STORY / CUTSCENE", "RESET STORY STATE"]:
			_expect(admin_labels.has(required),
				"Infinite admin menu is missing %s from the finite toolset" % required)
		for heading in ["SUMMON A-Z HUNTER", "REMOVE A-Z HUNTER // ALL MATCHES"]:
			var entry: Dictionary = admin_headings.get(heading, {})
			_expect(not entry.is_empty() \
					and (entry.get("items", []) as Array).size() == 26 \
					and (entry.get("action", Callable()) as Callable).is_valid(),
				"Infinite admin menu lacks a complete callable %s roster" % heading)
		for heading in ["SUMMON VOID HUNTER", "REMOVE VOID HUNTER // ALL MATCHES"]:
			var entry: Dictionary = admin_headings.get(heading, {})
			_expect(not entry.is_empty() \
					and (entry.get("items", []) as Array).size() \
					== HunterRoster.VOID_IDS.size() \
					and (entry.get("action", Callable()) as Callable).is_valid(),
				"Infinite admin menu lacks a complete callable %s roster" % heading)
		var story_picker: Dictionary = admin_headings.get(
			"PLAY STORY / CUTSCENE", {})
		_expect(not story_picker.is_empty() \
				and not (story_picker.get("items", []) as Array).is_empty() \
				and (story_picker.get("action", Callable()) as Callable).is_valid() \
				and String(story_picker.get("permission", "")) == "world",
			"Infinite admin menu lacks its authenticated story/cutscene picker")
		var aki_before := 0
		for state_value in map_world_state.hunters.values():
			if String((state_value as Dictionary).get("hunter_id", "")) == "aki":
				aki_before += 1
		live_scene.call("_admin_summon_hunter_authoritative", 1, "aki")
		var aki_after := 0
		for state_value in map_world_state.hunters.values():
			if String((state_value as Dictionary).get("hunter_id", "")) == "aki":
				aki_after += 1
		_expect(aki_after == aki_before + 1,
			"admin A-Z summon did not create one unique active hunter")
		live_scene.call("_admin_remove_hunter_authoritative", 1, "aki")
		var aki_remaining := 0
		for state_value in map_world_state.hunters.values():
			if String((state_value as Dictionary).get("hunter_id", "")) == "aki":
				aki_remaining += 1
		_expect(aki_remaining == 0 and not map_world_state.removed_hunters.is_empty(),
			"admin A-Z removal did not persistently remove every matching hunter")
		live_scene.call("_admin_summon_hunter_authoritative", 1, "void_red")
		var void_present := map_world_state.hunters.values().any(
			func(state_value) -> bool:
				return String((state_value as Dictionary).get(
					"hunter_id", "")) == "void_red")
		_expect(void_present, "admin Void summon did not create the selected hunter")
		live_scene.call("_admin_remove_hunter_authoritative", 1, "void_red")
		_expect(not map_world_state.hunters.values().any(
			func(state_value) -> bool:
				return String((state_value as Dictionary).get(
					"hunter_id", "")) == "void_red"),
			"admin Void removal left a selected hunter active")
		# Keep this test's removal-pressure tombstones from suppressing the later
		# long-distance persistence fixture in the same temporary scene.
		map_world_state.removed_hunters.clear()
		var light_action: Callable
		for entry in live_admin._actions:
			if String(entry.get("label", "")) == "TOGGLE ALL REGION LIGHTS":
				light_action = entry.get("action", Callable())
		var lights_before := facility.all_lights_enabled()
		if light_action.is_valid():
			light_action.call()
			_expect(facility.all_lights_enabled() != lights_before,
				"Infinite admin light toggle did not alter streamed region lights")
			light_action.call()
		live_admin._set_open(true)
		await host.get_tree().physics_frame
		_expect(player.input_frozen and player.velocity.is_zero_approx(),
			"Infinite player/tools remain active behind the admin menu")
		_expect(live_admin._panel.size.x >= 360.0 and live_admin._panel.size.y >= 220.0,
			"Infinite admin menu does not occupy a usable modal area")
		live_admin._set_open(false)
		# A raw CharacterBody teleport used to leave the streamed window on the
		# departed floor. Opening the fullscreen map immediately afterward then
		# received no current-floor chunks and appeared blank.
		player.global_position = Vector3(
			StreamedRouteGenerator.CHUNK_SIZE * 2.5,
			StreamedFacilityView3D.LEVEL_HEIGHT,
			StreamedRouteGenerator.CHUNK_SIZE * 2.5)
		facility.refresh_at_tracked_player()
		live_admin._set_open(true)
		var teleport_action := Callable()
		for entry in live_admin._actions:
			if String(entry.get("label", "")) == "TELEPORT TO START":
				teleport_action = entry.get("action", Callable())
		if teleport_action.is_valid():
			teleport_action.call()
		live_scene.hud.set_map_open(true)
		live_scene.call("_update_streamed_maps")
		_expect(not live_admin.is_open() and facility.current_chunk_coord() == Vector3i.ZERO \
			and not live_scene.hud.plan.streamed_chunks.is_empty(),
			"admin teleport left modal/stream state stale and blanked the fullscreen map")
		live_scene.hud.set_map_open(false)
	var discovered_before := discovered.size()
	live_scene.call("_admin_toggle_map_reveal")
	discovered = live_scene.get("_discovered_chunks")
	_expect(discovered.size() >= discovered_before \
		and not discovered.has(Vector3i(5, 0, 5)) \
		and discovered.has(Vector3i(4, 0, 4)),
		"admin reveal left its bounded local survey or lost its boundary chunks")
	live_scene.call("_admin_toggle_map_reveal")
	var snapshot: Dictionary = live_scene.call("_build_stream_snapshot")
	_expect(int(snapshot.get("snapshot_protocol", 0)) == live_scene.SNAPSHOT_PROTOCOL \
		and int(snapshot.get("seed", 0)) == RoomState.run_seed() \
		and snapshot.get("world_state") is Dictionary \
		and snapshot.get("hunters") is Array \
		and snapshot.get("story") is Dictionary,
		"Infinite late-join snapshot is incomplete")
	var local_packet: Dictionary = remotes.call("_local_state")
	_expect(int(local_packet.get("depth", 999999)) == -facility.current_level() \
		and local_packet.has("in_safe_zone"),
		"Infinite replication packet lacks streamed level/safe-room state")
	_expect(facility.pickup_requester.is_valid(),
		"streamed pickup interaction bypasses host arbitration")
	_expect(facility.door_requester.is_valid(),
		"streamed room doors bypass host arbitration")
	var lamp_before_drop := player.item_durability("flashlight")
	live_scene.call("_on_item_drop_requested", "flashlight", lamp_before_drop,
		player.selected_inventory_slot)
	var live_world_state: StreamedWorldState = live_scene.get("world_state")
	_expect(not player.owns_inventory_item("flashlight") \
		and live_world_state.dropped_items.size() == 1,
		"offline host drop did not remove the held item and create shared state")
	if live_world_state.dropped_items.size() == 1:
		var drop_id := String(live_world_state.dropped_items.keys()[0])
		var record: Dictionary = live_world_state.dropped_items[drop_id]
		player.global_position = record.get("position", player.global_position)
		live_scene.call("_accept_stream_drop", 1, {"action": "claim",
			"drop_id": drop_id})
		_expect(live_world_state.dropped_items.is_empty() \
			and player.owns_inventory_item("flashlight") \
			and player.item_durability("flashlight") == lamp_before_drop,
			"E-style dropped-item claim lost ownership or remaining durability")

	var hunter_coord := Vector3i(999, 999, 999)
	for level in [0]:
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
			_expect(facility.loaded_chunk_count() == 9,
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
				(hunter_coord.x + 4 + step * 3) * StreamedRouteGenerator.CHUNK_SIZE + chunk_center,
				hunter_coord.y * StreamedFacilityView3D.LEVEL_HEIGHT + .2,
				(hunter_coord.z - 2 - step * 2) * StreamedRouteGenerator.CHUNK_SIZE + chunk_center)
			await host.get_tree().process_frame
			await host.get_tree().process_frame
			_expect(facility.loaded_chunk_count() == 9,
				"long-session stream exceeded its nine-chunk window at step %d" % step)
			_expect(host.get_tree().get_nodes_in_group("streamed_chunk").size() == 9,
				"long-session scene retained an evicted chunk at step %d" % step)
		var live_navigation := live_scene.get("_navigation") as StreamedHunterNavigation
		# Stair selection samples a five-by-five ring, while an active hunter may
		# contribute one overlapping three-by-three residency window. Both remain
		# constant-size regardless of total distance travelled.
		_expect(live_navigation != null and live_navigation.cached_chunk_count() <= 36,
			"streamed navigation cache grew with travel distance")

	var prison_coord := Vector3i(999, 999, 999)
	for level in [0]:
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
		_expect(facility.loaded_chunk_count() == 9,
			"moving far away leaked old streamed chunks instead of evicting them")
		_expect(host.get_tree().get_nodes_in_group("streamed_chunk").size() == 9,
			"streamed scene tree retained evicted chunk nodes")

	# The live Infinite route -- not the legacy main_3d.tscn -- is what a
	# captured player actually sees, so the whole grab -> escape -> jumpscare
	# -> death report handoff has to be proven here too.
	_expect(live_scene.jumpscare != null,
		"the live Infinite route has no capture jumpscare director")
	if live_scene.jumpscare != null:
		# An ordinary A-Z hunter gives a real escape chance: mashing past the
		# requirement should free the runner without ever reaching a report.
		await live_scene._apply_player_event({"what": "capture", "streamed": true,
			"hunter_id": "kathy", "entity_id": "VALIDATION:KATHY"})
		_expect(GameState.escape_active and live_scene.jumpscare.holding,
			"an escapable capture did not start the grab hold/struggle")
		GameState.escape_progress = GameState.escape_required
		await live_scene._update_escape_struggle(0.0)
		await host.get_tree().process_frame
		_expect(not GameState.escape_active and not live_scene.jumpscare.holding,
			"beating the struggle did not release the grab hold")
		_expect(not player.input_frozen and not player.look_frozen,
			"a successful escape left the runner unable to act")
		_expect(not live_scene.run_report.is_open(),
			"a successful escape opened the death report anyway")
		# A successful escape starts its own re-grab cooldown; clear both so the
		# next scenario exercises an ordinary escapable grab, not that cooldown.
		GameState.escape_grace = 0.0
		GameState.escape_cooldown = 0.0

		# Running out of time on the same kind of grab has to fail into the
		# same jumpscare -> death report path an inescapable grab uses.
		await live_scene._apply_player_event({"what": "capture", "streamed": true,
			"hunter_id": "kathy", "entity_id": "VALIDATION:KATHY"})
		GameState.escape_remaining = 0.0
		await live_scene._update_escape_struggle(0.0)
		_expect(live_scene.jumpscare.last_hunter_id == "kathy",
			"a failed struggle did not present a jumpscare for the catching hunter")
		_expect(not live_scene.jumpscare.playing,
			"the jumpscare camera did not release control after playing")
		_expect(player.input_frozen,
			"a captured Infinite runner can still move behind the death report")
		_expect(live_scene.run_report.is_open(),
			"a failed struggle never reached the death report")
		live_scene.run_report.close()
		live_scene._death_screen_open = false
		GameState.game_over = false

		# A void/gimmick-forced grab skips the struggle entirely.
		await live_scene._apply_player_event({"what": "capture", "streamed": true,
			"hunter_id": "void_red", "inescapable": true})
		_expect(not GameState.escape_active,
			"an inescapable capture still opened an escape struggle")
		_expect(live_scene.jumpscare.last_hunter_id == "void_red",
			"an inescapable capture did not present its own jumpscare")
		_expect(live_scene.run_report.is_open(),
			"an inescapable capture never reached the death report")
		live_scene.run_report.close()
		live_scene._death_screen_open = false
		GameState.game_over = false

	live_scene.queue_free()
	await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)

	if _failures == 0:
		print("  chunks    deterministic topology, canonical seams and stable pickup ids")
		print("  vertical  unbounded levels; central spawn links both up and down")
		print("  regions   %d area identities; Gothic/Prison/Inferno constrained below" \
			% StreamedRouteGenerator.BIOMES.size())
		print("  rooms     %d sizes; hotel/prison corridors serve many rooms" % room_sizes.size())
		print("  survival  checkpoints, pickups and hunter state persist across unload")
		print("  hunters   deterministic spawns, seam navigation and live pursuit load")
		print("  renderer  bounded collidable stream, vertical flights and regional art load")
		print("streamed_world OK")
	return _failures
