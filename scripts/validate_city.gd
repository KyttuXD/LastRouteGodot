extends RefCounted

## KYTTU: The City: the master layout and chunk provider (deterministic, connected, every building enterable, shelters on
## chunk centres, relay/pickup/hunter coverage, seams), plus the hub entry, theme, menus and the room game id.

const SEED := "CITY-VALIDATE"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_registry(host)
	await host.get_tree().process_frame
	var layout := CityLayout.build(SEED)
	_check_determinism(layout)
	_check_shape(layout)
	_check_connectivity(layout)
	_check_streets(layout)
	_check_buildings(layout)
	_check_shelters(layout)
	_check_chunks()
	await _check_run_scene(host)
	await _check_saved_run(host)
	_check_daytime()
	if _failures == 0:
		print("  city  layout, connectivity, streets, buildings, shelters, chunks, registry, game id")
	return _failures


func _hash(layout: CityLayout) -> int:
	return hash(layout.kinds)


func _check_registry(host: Node) -> void:
	_expect(GameRegistry.is_launchable("city"), "the City is not launchable from the hub")
	var game := GameRegistry.get_game("city")
	_expect(String(game.get("title", "")) == "KYTTU: THE CITY", "City hub title is wrong")
	_expect(load(String(game.get("theme", ""))) is Theme, "City theme does not load")
	_expect(ResourceLoader.exists("res://scenes/city_menu.tscn"), "City menu scene is missing")
	var menu: Control = (load("res://scenes/city_menu.tscn") as PackedScene).instantiate()
	host.add_child(menu)
	for node_name in ["NewRunButton", "HostButton", "JoinButton", "BackToGamesButton", "RoomCodeInput", "PublicButton",
			"AccountButton", "SettingsButton", "TimeButton", "ContinueRunButton", "ClearRunButton", "SettingsOverlay"]:
		_expect(menu.find_child(node_name, true, false) != null, "City menu lacks %s" % node_name)
	_expect(not (menu.find_child("ContinueRunButton", true, false) as Button).visible, "CONTINUE RUN shows without a saved run")
	var overlay := menu.find_child("SettingsOverlay", true, false)
	if overlay != null:
		overlay.call("open")
		await host.get_tree().process_frame
		var tabs := overlay.get("_section_tabs") as TabBar
		_expect(tabs != null and tabs.tab_count == 3, "the City's controls tabs are not MOVEMENT / ACTIONS / SYSTEM")
	_expect(ControlsRegistry.tabs_for("city") == ControlsRegistry.tabs_for("last_route"), "the City does not share Last Route's controls")
	menu.queue_free()
	# run save: JSON-safe round trip, rejects junk
	var save := CityRunSave.make("SEED-X", "standard", 40, 3, 7, 0, ["1:0:0:PICKUP:RELAY:0"], Vector3(4.5, 0.05, -12.0), 3.1)
	var round_trip = JSON.parse_string(JSON.stringify(save))
	_expect(round_trip is Dictionary and CityRunSave.valid(round_trip), "a City run save does not survive JSON")
	_expect(not CityRunSave.valid({}), "an empty City run save was accepted")
	var outside := save.duplicate(true)
	outside["x"] = 5000.0
	_expect(not CityRunSave.valid(outside), "a City run save outside the dome was accepted")
	_expect(String(GameRegistry.save_summary("city").get("text", "")) != "", "the account SAVES row has no City text")
	var prepared := RoomState.prepare_city_run(save)
	_expect(prepared.is_empty() and RoomState.is_city() and RoomState.seed_text == "SEED-X" and not RoomState.pending_city_save.is_empty(),
		"prepare_city_run did not queue the saved run: %s" % prepared)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.pending_city_save.is_empty(), "a new room kept a queued City save")
	_expect(RoomState.Mode.CITY != RoomState.Mode.DEFAULT, "Mode.CITY collides with another mode")
	_expect(RoomState.mode_available(RoomState.Mode.CITY), "Mode.CITY is not selectable")
	_expect(String(RoomState.MODE_SCENES[RoomState.Mode.CITY]) == RoomState.CITY_ROUTE_SCENE, "City mode opens the wrong scene")
	_expect(RoomState.game_matches("", RoomState.GAME_LAST_ROUTE), "a missing game must mean last_route")
	_expect(RoomState.game_matches("city", RoomState.GAME_CITY), "city room does not match the City")
	_expect(not RoomState.game_matches("city", RoomState.GAME_LAST_ROUTE), "a City room matched Last Route")
	_expect(not RoomState.game_matches("last_route", RoomState.GAME_CITY), "a Last Route room matched the City")
	var saved_mode := RoomState.mode
	RoomState.mode = RoomState.Mode.CITY
	_expect(RoomState.game_id() == "city", "game_id() is not city in a City room")
	_expect(RoomState.menu_scene_path() == RoomState.CITY_MENU_SCENE, "City rooms leave to the wrong menu")
	_expect(RoomState.session_scene_path() == RoomState.CITY_ROUTE_SCENE, "City rooms open the wrong run scene")
	RoomState.mode = saved_mode


func _check_determinism(layout: CityLayout) -> void:
	_expect(_hash(CityLayout.build(SEED)) == _hash(layout), "the layout is not deterministic for one seed")
	var other := CityLayout.build("CITY-OTHER-SEED")
	_expect(other.buildings.size() > 0 and other.shelters.size() == layout.shelters.size(),
		"a different seed breaks the fixed skeleton")
	_expect(_hash(other) != _hash(layout), "two seeds gave the same city (buildings should vary)")


func _check_shape(layout: CityLayout) -> void:
	_expect(layout.kinds.size() == CityLayout.WIDTH * CityLayout.HEIGHT, "layout size is wrong")
	var downtown := layout.buildings.filter(func(b: Dictionary) -> bool: return not ["house", "barn"].has(String(b["kind"])))
	_expect(downtown.size() >= 45 and downtown.size() <= 70, "downtown building count %d is outside 45..70" % downtown.size())
	var kinds_seen := {}
	var partitioned := 0
	var sealed := 0
	for building in layout.buildings:
		if bool(building.get("sealed", false)):
			sealed += 1
			continue
		kinds_seen[String(building["kind"])] = true
		if not (building["partition"] as Array).is_empty():
			partitioned += 1
	var decor_counts := {}
	for entry in layout.decor.values():
		decor_counts[String(entry["type"])] = int(decor_counts.get(String(entry["type"]), 0)) + 1
	for type in CityProps.TYPES:
		_expect(int(decor_counts.get(type, 0)) >= 2, "City prop %s is placed %d times" % [type, int(decor_counts.get(type, 0))])
	_expect(int(decor_counts.get("plaza_light", 0)) >= 8, "the grand plaza has only %d lights" % int(decor_counts.get("plaza_light", 0)))
	print("  city: street furniture %s" % [decor_counts])
	_expect(sealed <= 3, "%d buildings are sealed shut" % sealed)
	print("  city: %d buildings (%d sealed), kinds %s, %d with two rooms" % [layout.buildings.size(), sealed, kinds_seen.keys(), partitioned])
	_expect(kinds_seen.size() >= 7, "only %d building kinds" % kinds_seen.size())
	_expect(partitioned >= 3, "only %d buildings have a partition" % partitioned)
	_expect(layout.shelters.size() == 5, "expected 5 shelters, got %d" % layout.shelters.size())
	_expect(layout.gardens.size() == 2, "expected two gardens")
	var open := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			_expect(layout.kind_at(gx, gz) != CityLayout.BLOCK, "unfinished block cell at %d,%d" % [gx, gz])
			if layout.is_open(gx, gz):
				open += 1
			if layout.is_outside(gx, gz) and layout.is_open(gx, gz):
				_expect(false, "open cell outside the rim at %d,%d" % [gx, gz])
				return
	_expect(open > 9000, "the city is too small (%d open cells)" % open)
	var centre := CityLayout.ROUNDABOUT_CENTER
	_expect(layout.kind_at(centre.x, centre.y) == CityLayout.KIOSK_FLOOR, "the spawn is not inside the central kiosk")
	_expect(layout.spawn == centre, "spawn is not the roundabout centre")
	_expect(Vector2i(centre.x - CityLayout.ORIGIN_OFFSET.x, centre.y - CityLayout.ORIGIN_OFFSET.y)
		== Vector2i(StreamedRouteGenerator.CHUNK_SIZE / 2, StreamedRouteGenerator.CHUNK_SIZE / 2),
		"the spawn is not chunk (0,0)'s centre cell")


func _flood(layout: CityLayout, from: Vector2i, blocked: Dictionary = {}) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + (step as Vector2i)
			if seen.has(next) or blocked.has(next) or not layout.is_open(next.x, next.y):
				continue
			seen[next] = true
			queue.append(next)
	return seen


func _check_connectivity(layout: CityLayout) -> void:
	var reached := _flood(layout, layout.spawn)
	var open := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			if layout.is_open(gx, gz):
				open += 1
	_expect(reached.size() == open, "%d of %d open cells are unreachable from the spawn" % [open - reached.size(), open])


func _check_streets(layout: CityLayout) -> void:
	# Every road cell has a run of at least three road-ish cells across one axis (streets are never 1-2 wide).
	var narrow := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			var kind := layout.kind_at(gx, gz)
			if kind != CityLayout.ROAD:
				continue
			var best := 0
			for axis in [Vector2i(1, 0), Vector2i(0, 1)]:
				var run := 1
				for sign in [-1, 1]:
					var at := Vector2i(gx, gz) + (axis as Vector2i) * int(sign)
					while [CityLayout.ROAD, CityLayout.CROSS_NS, CityLayout.CROSS_EW].has(layout.kind_at(at.x, at.y)):
						run += 1
						at += (axis as Vector2i) * int(sign)
				best = maxi(best, run)
			if best < 3:
				narrow += 1
	_expect(narrow == 0, "%d road cells are narrower than 3" % narrow)
	# Alleys are exactly 3 wide, never 1-2.
	var thin_alley := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			if layout.kind_at(gx, gz) != CityLayout.ALLEY:
				continue
			var across_x := 1
			var across_z := 1
			for sign in [-1, 1]:
				var x := gx + int(sign)
				while layout.kind_at(x, gz) == CityLayout.ALLEY:
					across_x += 1
					x += int(sign)
				var z := gz + int(sign)
				while layout.kind_at(gx, z) == CityLayout.ALLEY:
					across_z += 1
					z += int(sign)
			if mini(across_x, across_z) < 3:
				thin_alley += 1
	_expect(thin_alley == 0, "%d alley cells are narrower than 3" % thin_alley)


func _check_buildings(layout: CityLayout) -> void:
	var ids := {}
	for building in layout.buildings:
		var id := String(building["id"])
		_expect(not ids.has(id), "duplicate building id %s" % id)
		if bool(building.get("sealed", false)):
			continue
		ids[id] = true
		var doors: Array = building["doors"]
		_expect(doors.size() >= 2, "%s has no usable door" % id)
		var interior: Rect2i = building["interior"]
		_expect(interior.size.x >= 7 and interior.size.y >= 7, "%s interior is too small" % id)
		for door_value in doors:
			var door: Vector2i = door_value
			_expect(layout.kind_at(door.x, door.y) == CityLayout.DOOR, "%s door cell is not a door" % id)
			var outside := 0
			var inside := 0
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = door + (step as Vector2i)
				if CityLayout.OUTDOOR_KINDS.has(layout.kind_at(next.x, next.y)):
					outside += 1
				if layout.kind_at(next.x, next.y) == CityLayout.FLOOR:
					inside += 1
			_expect(outside >= 1 and inside >= 1, "%s door does not join a street and its interior" % id)
		# Interior furniture never blocks the doors, stays on floor cells, and keeps every floor cell reachable.
		var blocked := {}
		var props: Array = layout.building_props(building)
		for prop in props:
			var cell: Vector2i = prop["cell"]
			_expect(layout.kind_at(cell.x, cell.y) == CityLayout.FLOOR, "%s prop %s is not on a floor cell" % [id, prop["type"]])
			blocked[cell] = true
			for door_value in doors:
				_expect(maxi(absi(cell.x - (door_value as Vector2i).x), absi(cell.y - (door_value as Vector2i).y)) > 2,
					"%s prop %s sits in a doorway" % [id, prop["type"]])
			_expect(PropModelCatalog.has_model(String(prop["type"])), "%s uses a prop with no model: %s" % [id, prop["type"]])
		var from: Vector2i = doors[0]
		var reached := _flood(layout, from, blocked)
		var missed := 0
		for gz in range(interior.position.y, interior.end.y):
			for gx in range(interior.position.x, interior.end.x):
				var cell := Vector2i(gx, gz)
				if layout.kind_at(gx, gz) == CityLayout.FLOOR and not blocked.has(cell) and not reached.has(cell):
					missed += 1
		_expect(missed == 0, "%s has %d floor cells cut off by furniture" % [id, missed])


func _check_shelters(layout: CityLayout) -> void:
	for shelter in layout.shelters:
		var center: Vector2i = shelter["center"]
		var local := center - CityLayout.ORIGIN_OFFSET
		_expect(posmod(local.x, StreamedRouteGenerator.CHUNK_SIZE) == 22 and posmod(local.y, StreamedRouteGenerator.CHUNK_SIZE) == 22,
			"shelter %s is not on a chunk centre" % shelter["id"])
		for dz in range(-3, 4):
			for dx in range(-3, 4):
				_expect(layout.kind_at(center.x + dx, center.y + dz) == CityLayout.KIOSK_FLOOR,
					"shelter %s interior is not clear" % shelter["id"])
		_expect((shelter["doors"] as Array).size() == 3, "shelter %s has no 3-wide door" % shelter["id"])


func _check_chunks() -> void:
	var generator := CityRouteGenerator.new(SEED)
	var allowed := 0
	var relays := 0
	var safe_chunks := 0
	var props := 0
	for cz in range(-2, 3):
		for cx in range(-3, 4):
			var coord := Vector3i(cx, 0, cz)
			var inside := CityLayout.chunk_in_range(coord)
			_expect(generator.is_chunk_allowed(coord) == (inside and generator.layout.chunk_has_open_cells(coord)),
				"chunk %s allowance is inconsistent" % coord)
			var data := generator.chunk(coord)
			_expect(not data.is_empty() and (data["grid"] as Array).size() == StreamedRouteGenerator.CHUNK_SIZE,
				"chunk %s has no 45 x 45 grid" % coord)
			if not generator.is_chunk_allowed(coord):
				_expect(String(data["region"]) == "sealed", "chunk %s outside the city is not sealed" % coord)
				continue
			allowed += 1
			for key in ["rooms", "region_props", "fixtures", "pickups", "hunter_spawns", "safe_room", "safe_room_data",
					"edges", "city", "difficulty", "stairs", "floor_voids"]:
				_expect(data.has(key), "chunk %s lacks %s" % [coord, key])
			if bool(data["safe_room"]):
				safe_chunks += 1
				_expect(not (data["city"]["shelter"] as Dictionary).is_empty(), "safe chunk %s has no shelter" % coord)
				_expect((data["pickups"] as Array).is_empty(), "safe chunk %s has pickups" % coord)
			else:
				var kinds := {}
				for pickup in data["pickups"]:
					kinds[String(pickup["kind"])] = true
					relays += 1 if String(pickup["kind"]) == "relay" else 0
				# A rim sliver chunk (a corner with a few open field cells) may hold no pickup spot at all.
				var open_cells := 0
				for row in data["grid"]:
					for value in row:
						open_cells += 1 if int(value) == 0 else 0
				_expect(kinds.has("relay") or open_cells < 300, "chunk %s has no relay (%d open cells)" % [coord, open_cells])
			props += (data["region_props"] as Array).size()
			# Seams: the open cells of a shared border line up on both sides.
			var east_neighbour := coord + Vector3i(1, 0, 0)
			if generator.is_chunk_allowed(east_neighbour):
				_expect((data["edges"]["east"] as Array) == (generator.chunk(east_neighbour)["edges"]["west"] as Array),
					"seam between %s and %s does not match" % [coord, east_neighbour])
			var south_neighbour := coord + Vector3i(0, 0, 1)
			if generator.is_chunk_allowed(south_neighbour):
				_expect((data["edges"]["south"] as Array) == (generator.chunk(south_neighbour)["edges"]["north"] as Array),
					"seam between %s and %s does not match" % [coord, south_neighbour])
	_expect(allowed >= 13, "only %d chunks are part of the city" % allowed)
	_expect(safe_chunks == 5, "expected 5 safe chunks, got %d" % safe_chunks)
	_expect(relays >= 16, "only %d relays across the city" % relays)
	_expect(props >= 100, "only %d interior props across the city" % props)
	_expect(generator.is_safe_room(Vector3i.ZERO), "the spawn chunk is not a safe room")
	_expect((generator.chunk(Vector3i(1, 0, 0))["hunter_spawns"] as Array).size() >= 1, "chunk (1,0) has no hunter spawn")
	_expect(generator.spawn_chunk() == Vector3i.ZERO and generator.spawn_cell() == Vector2i(22, 22), "spawn chunk/cell changed")


## The City run scene boots: the City generator and view, nine chunks around the spawn, the runner on the spawn.
func _check_run_scene(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.CITY)
	RoomState.seed_text = SEED
	Backend.enable_offline_mode()
	var scene: Node = (load(RoomState.CITY_ROUTE_SCENE) as PackedScene).instantiate()
	host.add_child(scene)
	for _frame in 6:
		await host.get_tree().process_frame
	var facility := scene.get_node("%StreamedFacility") as StreamedFacilityView3D
	_expect(facility is CityFacilityView3D, "the City run scene does not use the City view")
	_expect(facility.generator is CityRouteGenerator, "the City view does not use the City generator")
	var expected_chunks := 0
	for cz in range(-CityFacilityView3D.CITY_STREAM_RADIUS, CityFacilityView3D.CITY_STREAM_RADIUS + 1):
		for cx in range(-CityFacilityView3D.CITY_STREAM_RADIUS, CityFacilityView3D.CITY_STREAM_RADIUS + 1):
			if facility.generator.is_chunk_allowed(Vector3i(cx, 0, cz)):
				expected_chunks += 1
	var allowed_total := 0
	for cz in range(CityLayout.CHUNK_MIN.y, CityLayout.CHUNK_MAX.y + 1):
		for cx in range(CityLayout.CHUNK_MIN.x, CityLayout.CHUNK_MAX.x + 1):
			if facility.generator.is_chunk_allowed(Vector3i(cx, 0, cz)):
				allowed_total += 1
	_expect(expected_chunks == allowed_total and allowed_total >= 30, "from the spawn the whole city (%d chunks) must be in range, got %d" % [allowed_total, expected_chunks])
	_expect(facility.loaded_chunk_count() == expected_chunks,
		"expected every city chunk resident from the spawn (%d), got %d" % [expected_chunks, facility.loaded_chunk_count()])
	var player := scene.get_node("%Player") as PlayerController3D
	_expect(player.global_position.distance_to(Vector3(22.5, .04, 22.5)) < 2.0, "the runner did not start on the spawn")
	_expect(facility.get_node_or_null("CitySky") != null, "the dome sky is missing")
	var started := Time.get_ticks_msec()
	_check_far_rendering(facility)
	print("  city: far-rendering check %d ms" % (Time.get_ticks_msec() - started))
	started = Time.get_ticks_msec()
	_check_invisible_walls(facility)
	await _check_entrances(host, facility, scene)
	await _check_life(host, facility)
	print("  city: invisible-wall check %d ms" % (Time.get_ticks_msec() - started))
	_expect(absf(wrapf(player._yaw - PI, -PI, PI)) < .01, "the runner does not start facing the kiosk doorway (south)")
	var layout := (facility.generator as CityRouteGenerator).layout
	_expect(layout.kind_at(layout.spawn.x, layout.spawn.y + 4) == CityLayout.DOOR, "no doorway straight ahead of the spawn")
	_check_gate(facility, layout)
	_check_outskirts(layout)
	_check_outskirt_lots(layout)
	_check_water(layout)
	scene.queue_free()
	await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)


## Distance rendering (the "buildings look wrong from far away" bug): tiles must be sampled per layer (no atlas mipmap
## bleed), every chunk mesh must carry correct bounds, nothing may draw twice in the same place (z-fighting at range),
## and no City mesh may carry mesh LODs.
func _check_far_rendering(facility: StreamedFacilityView3D) -> void:
	var materials := CitySurface.materials()
	for index in 2:
		var material := materials[index] as ShaderMaterial
		_expect(material != null, "City ground/solid materials must be tile-array shaders, not a mipmapped atlas")
		if material == null:
			continue
		var tiles := material.get_shader_parameter("tiles") as Texture2DArray
		_expect(tiles != null and tiles.get_layers() == CityAtlas.NAMES.size(),
			"the tile array does not hold one layer per atlas tile")
		_expect(tiles != null and tiles.get_width() == CityAtlas.TILE_PX and tiles.get_height() == CityAtlas.TILE_PX,
			"tile layers are not %d px" % CityAtlas.TILE_PX)
		_expect((material.shader.code as String).contains("filter_nearest_mipmap"),
			"the tile shader must sample nearest with per-layer mipmaps")
	_expect(CityAtlas.NAMES.size() <= CityAtlas.COLUMNS * CityAtlas.ROWS, "more tiles than the atlas sheet holds")
	var sheet := (load(CityAtlas.ALBEDO_PATH) as Texture2D).get_image()
	_expect(sheet.get_width() == CityAtlas.SHEET_PX and sheet.get_height() == CityAtlas.ROWS * CityAtlas.TILE_PX, "atlas sheet size changed")
	var quads_checked := 0
	for chunk_value in facility._loaded.values():
		var chunk := chunk_value as Node3D
		var surface := chunk.get_node_or_null("Surface") as MeshInstance3D
		_expect(surface != null and surface.mesh is ArrayMesh, "chunk %s has no surface mesh" % chunk.name)
		if surface == null:
			continue
		var mesh := surface.mesh as ArrayMesh
		var seen := {}
		var bounds := mesh.get_aabb()
		for surface_index in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_index)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			_expect(arrays[Mesh.ARRAY_TEX_UV2] != null and (arrays[Mesh.ARRAY_TEX_UV2] as PackedVector2Array).size() == vertices.size(),
				"%s surface %d has no per-quad tile layer (UV2)" % [chunk.name, surface_index])
			_expect(mesh.surface_get_lod_count(surface_index) == 0 if mesh.has_method("surface_get_lod_count") else true,
				"%s surface %d carries mesh LODs" % [chunk.name, surface_index])
			for vertex in vertices:
				_expect(bounds.grow(0.01).has_point(vertex), "%s vertex outside the mesh bounds" % chunk.name)
				break
			var quad := 0
			while quad + 3 < vertices.size():
				var lo := vertices[quad]
				var hi := vertices[quad]
				for corner in 4:
					lo = lo.min(vertices[quad + corner])
					hi = hi.max(vertices[quad + corner])
				var key := "%d|%s|%s|%s" % [surface_index, str(lo.snappedf(.001)), str(hi.snappedf(.001)), str(normals[quad].snappedf(.01))]
				_expect(not seen.has(key), "%s draws the same quad twice (z-fighting) at %s" % [chunk.name, lo])
				seen[key] = true
				quad += 4
				quads_checked += 1
	_expect(quads_checked > 20000, "far-rendering check saw only %d quads" % quads_checked)


## Collision and visuals agree. A blocked cell next to open ground must have something drawn on it (no invisible wall),
## every plain wall cell has the full wall collider, floor-like cells have the floor slab, and street furniture
## (which keeps its GridMap cell walkable) blocks only a box no wider than what is drawn. Zero mismatches in the spawn
## area and in every resident chunk.
func _check_invisible_walls(facility: StreamedFacilityView3D) -> void:
	var layout := (facility.generator as CityRouteGenerator).layout
	var cell_count := 0
	var invisible: Array = []
	var missing_collider: Array = []
	var spawn_invisible := 0
	for chunk_value in facility._loaded.values():
		var chunk := chunk_value as Node3D
		var coord := Vector3i(roundi(chunk.position.x / StreamedRouteGenerator.CHUNK_SIZE), 0,
			roundi(chunk.position.z / StreamedRouteGenerator.CHUNK_SIZE))
		var origin := CityLayout.chunk_origin(coord)
		var surface := chunk.get_node_or_null("Surface") as MeshInstance3D
		var grid_map := chunk.get_node_or_null("Structure") as GridMap
		var bodies := chunk.get_node_or_null("StreetFurnitureColliders") as StaticBody3D
		_expect(grid_map != null and bodies != null and surface != null, "chunk %s lacks structure, furniture colliders or surface" % chunk.name)
		if grid_map == null or bodies == null or surface == null:
			continue
		var mesh := surface.mesh as ArrayMesh
		var seen := {}
		for surface_index in mesh.get_surface_count():
			var vertices: PackedVector3Array = mesh.surface_get_arrays(surface_index)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				if vertex.y < .15:
					continue
				for dz in [0, -1]:
					for dx in [0, -1]:
						var x: int = floori(vertex.x) + int(dx)
						var z: int = floori(vertex.z) + int(dz)
						if absf(vertex.x - roundf(vertex.x)) > .001 and int(dx) == -1:
							continue
						if absf(vertex.z - roundf(vertex.z)) > .001 and int(dz) == -1:
							continue
						seen[Vector2i(x, z)] = true
		var posts := 0
		for z in StreamedRouteGenerator.CHUNK_SIZE:
			for x in StreamedRouteGenerator.CHUNK_SIZE:
				var kind := layout.kind_at(origin.x + x, origin.y + z)
				var item := grid_map.get_cell_item(Vector3i(x, 0, z))
				var blocked := not CityLayout.OPEN_KINDS.has(kind)
				cell_count += 1
				if kind == CityLayout.POST:
					posts += 1
					if item != facility._col_floor_item:
						missing_collider.append("%s,%s post cell is not walkable at the GridMap level" % [origin.x + x, origin.y + z])
				elif blocked:
					if item != facility._col_wall_item:
						missing_collider.append("%d,%d wall cell has no wall collider" % [origin.x + x, origin.y + z])
				elif item != facility._col_floor_item:
					missing_collider.append("%d,%d open cell has no floor collider" % [origin.x + x, origin.y + z])
				if not blocked or kind == CityLayout.POST:
					continue
				var next_to_open := false
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if layout.is_open(origin.x + x + (step as Vector2i).x, origin.y + z + (step as Vector2i).y):
						next_to_open = true
				if next_to_open and not seen.has(Vector2i(x, z)):
					invisible.append("%d,%d (%s)" % [origin.x + x, origin.y + z, CityLayout.KIND_NAMES[kind]])
					if maxi(absi(origin.x + x - layout.spawn.x), absi(origin.y + z - layout.spawn.y)) <= 14:
						spawn_invisible += 1
		_expect(bodies.get_child_count() == (layout.chunk_decor(coord) as Array).filter(
			func(entry: Dictionary) -> bool: return CityLayout.DECOR_COLLIDERS.has(String(entry["type"]))).size(),
			"chunk %s: furniture collider count differs from its street furniture" % chunk.name)
	_expect(cell_count > 8000, "invisible-wall check saw only %d cells" % cell_count)
	_expect(missing_collider.is_empty(), "%d cells with the wrong collider kind, e.g. %s" % [missing_collider.size(), missing_collider.slice(0, 5)])
	_expect(invisible.is_empty(), "%d invisible-wall cells (blocked, next to open ground, nothing drawn), e.g. %s" % [invisible.size(), invisible.slice(0, 6)])
	_expect(spawn_invisible == 0, "%d invisible-wall cells within 14 cells of the spawn" % spawn_invisible)
	for entry in layout.decor.values():
		var type := String(entry["type"])
		var collider: Vector3 = CityLayout.DECOR_COLLIDERS.get(type, Vector3.ZERO)
		var visible: Vector3 = CityLayout.DECOR_VISIBLE.get(type, Vector3.ZERO)
		_expect(collider != Vector3.ZERO, "%s street furniture has no collider" % type)
		_expect(maxf(collider.x, collider.z) <= maxf(visible.x, visible.z) + .06 and collider.y <= visible.y + .06,
			"%s collider (%s) is bigger than what is drawn (%s)" % [type, collider, visible])


## The dome gate: nine blocked cells across the avenue, one gate pickup in the loaded chunks, relay requirement per difficulty.
func _check_gate(facility: StreamedFacilityView3D, layout: CityLayout) -> void:
	for gx in range(CityLayout.GATE_X.x, CityLayout.GATE_X.y + 1):
		_expect(layout.kind_at(gx, CityLayout.GATE_ROW) == CityLayout.GATE, "gate cell %d is not blocked" % gx)
	_expect(layout.is_open(CityLayout.GATE_CELL.x, CityLayout.GATE_CELL.y), "no open cell in front of the gate")
	_expect(layout.zone_name(CityLayout.GATE_CELL.x, CityLayout.GATE_CELL.y) == "DOME GATE", "gate zone name missing")
	var found := 0
	var gate_chunk := Vector3i(floori(float(CityLayout.GATE_CELL.x - CityLayout.ORIGIN_OFFSET.x) / 45.0), 0, floori(float(CityLayout.GATE_CELL.y - CityLayout.ORIGIN_OFFSET.y) / 45.0))
	var data: Dictionary = facility.generator.chunk(gate_chunk)
	for pickup_value in data.get("pickups", []):
		var pickup: Dictionary = pickup_value
		if String(pickup.get("kind", "")) == "gate":
			found += 1
	var gate_node: Node = facility.find_child("DomeGate", true, false)
	_expect(gate_node != null, "the dome gate interactable was not built")
	_expect(found == 1, "expected exactly one gate pickup, found %d" % found)
	var easy := CityLayout.gate_relays_required("relaxed")
	var normal := CityLayout.gate_relays_required("standard")
	var hard := CityLayout.gate_relays_required("nightmare")
	_expect(easy < normal and normal < hard, "gate relay requirement does not rise with difficulty")


## A queued City run save is applied once on entry: progress, claimed pickups and the runner's spot come back.
func _check_saved_run(host: Node) -> void:
	var claimed_id := "0:0:0:PICKUP:RELAY:0"
	var claims: Array = []
	for index in 6:
		claims.append("0:0:0:PICKUP:RELAY:%d" % index)
	claims.append("0:0:0:PICKUP:COIN:0")
	RoomState.create_local(RoomState.Mode.CITY)
	var error := RoomState.prepare_city_run(CityRunSave.make("SAVED-SEED", "standard", 55, 4, 6, 0, claims,
		Vector3(40.5, 0.05, 20.5), 1.25))
	_expect(error.is_empty(), "could not queue the saved run: %s" % error)
	Backend.enable_offline_mode()
	var scene: Node = (load(RoomState.CITY_ROUTE_SCENE) as PackedScene).instantiate()
	host.add_child(scene)
	for _frame in 6:
		await host.get_tree().process_frame
	var player: Node3D = scene.get("player")
	_expect(GameState.relays_collected == 6 and GameState.coins == GameConfig.COIN_PICKUP_VALUE and GameState.score == 55, "saved progress was not restored")
	_expect(scene.get("world_state").claimed_pickups.has(claimed_id), "saved claimed pickups were not restored")
	_expect(absf(player.global_position.x - 40.5) < .5 and absf(player.global_position.z - 20.5) < .5, "the runner was not put back at the saved spot")
	_expect(RoomState.pending_city_save.is_empty(), "the queued City save was not consumed")
	scene.queue_free()
	await host.get_tree().process_frame


## City DAYTIME: the vision table covers every hunter, daylight lengthens sight outdoors only, Nyxie is weaker by day, the
## flag lives on the room and in run saves, and the hunter population is thinned a little.
func _check_daytime() -> void:
	var ids: Array = HunterRoster.PROFILES.keys()
	for id in ids:
		var entry := HunterVision.entry(String(id))
		_expect(float(entry["night"]) > 0.0 and float(entry["day"]) > 0.0 and float(entry["notice"]) >= 0.0, "bad vision entry for %s" % id)
	_expect(HunterVision.day_multiplier("nyxie") < 0.6 and HunterVision.night_multiplier("nyxie") > 1.0, "Nyxie is not light-sensitive")
	_expect(HunterVision.notice_seconds("nyxie") > 0.0, "Nyxie is not slower to notice by day")
	_expect(HunterVision.day_multiplier("kathy") > 1.0, "no hunter sees better by day")
	var outdoors := func(_p: Vector2) -> bool: return false
	var indoors := func(_p: Vector2) -> bool: return true
	var spot := Vector2(10, 10)
	var aki := HunterBrain.new(spot, "DAY-TEST", "aki", "standard")
	var nyxie := HunterBrain.new(spot, "DAY-TEST", "nyxie", "standard")
	var hard := HunterBrain.new(spot, "DAY-TEST", "aki", "hard")
	var relaxed := HunterBrain.new(spot, "DAY-TEST", "aki", "relaxed")
	var night_unlit := aki.sight_limit_for(spot, false)
	var night_lit := aki.sight_limit_for(spot, true)
	for brain in [aki, nyxie, hard, relaxed]:
		(brain as HunterBrain).day_mode = true
		(brain as HunterBrain).indoor_check = outdoors
	var day_unlit := aki.sight_limit_for(spot, false)
	_expect(day_unlit > night_unlit * 3.0, "daylight does not lengthen sight outdoors (%.1f vs %.1f unlit)" % [day_unlit, night_unlit])
	_expect(is_equal_approx(day_unlit, aki.sight_limit_for(spot, true)), "the flashlight still matters outdoors in daytime")
	_expect(nyxie.sight_limit_for(spot, false) < day_unlit * 0.7, "Nyxie does not see worse than Aki by day")
	_expect(hard.sight_limit_for(spot, false) > day_unlit and relaxed.sight_limit_for(spot, false) < day_unlit, "difficulty no longer scales daytime sight")
	aki.indoor_check = indoors
	_expect(is_equal_approx(aki.sight_limit_for(spot, true), night_lit) and is_equal_approx(aki.sight_limit_for(spot, false), night_unlit),
		"indoors in daytime the night sight rules must still apply")
	var night_brain := HunterBrain.new(spot, "DAY-TEST", "aki", "standard")
	_expect(is_equal_approx(night_brain.sight_limit_for(spot, true), night_lit), "a night brain changed its sight")
	# room flag
	RoomState.create_local(RoomState.Mode.CITY)
	_expect(not RoomState.is_day(), "a new City room starts in daytime")
	RoomState.set_daytime(true)
	_expect(RoomState.is_day(), "set_daytime did not stick")
	var save := CityRunSave.make("DAY-SEED", "standard", 0, 0, 0, 0, [], Vector3(0, 0, 0), 0.0, true)
	var round_trip = JSON.parse_string(JSON.stringify(save))
	_expect(round_trip is Dictionary and bool(round_trip.get("daytime", false)), "daytime is not saved with a City run")
	RoomState.create_local(RoomState.Mode.CITY)
	_expect(RoomState.prepare_city_run(round_trip).is_empty() and RoomState.is_day(), "a saved daytime run did not restore daytime")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.daytime = true
	_expect(not RoomState.is_day(), "Last Route rooms must never be day")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	print("  city: daytime vision table, sight ranges, room flag, run save")


## Every enterable building has a real City entrance: a CityDoor wide and high enough, whose leaves only block the doorway while
## closed, and a player-sized capsule can walk street -> doorway -> interior once they open (no wall, prop or collider across it).
func _check_entrances(host: Node, facility: StreamedFacilityView3D, scene: Node) -> void:
	var layout := (facility.generator as CityRouteGenerator).layout
	var enterable := 0
	for building in layout.buildings:
		if bool(building.get("sealed", false)):
			continue
		enterable += 1
		var doors: Array = building["doors"]
		var width := 0
		for door_value in doors:
			var door_cell: Vector2i = door_value
			if layout.kind_at(door_cell.x, door_cell.y) == CityLayout.DOOR:
				width += 1
		_expect(width >= 2 and doors.size() % 2 == 0, "%s has a doorway narrower than 2 m (%d door cells)" % [building["id"], width])
	var doors_found: Array = []
	for chunk_value in facility._loaded.values():
		for child in (chunk_value as Node).get_children():
			if child is CityDoor:
				doors_found.append(child)
	_expect(doors_found.size() >= enterable, "only %d City doors for %d enterable buildings" % [doors_found.size(), enterable])
	var capsule := CapsuleShape3D.new()
	capsule.radius = .35
	capsule.height = 1.7
	var space := facility.get_world_3d().direct_space_state
	var player_rid: RID = (scene.get("player") as CollisionObject3D).get_rid()
	var blocked: Array = []
	var leaky: Array = []
	var closed_free := 0
	for door_value in doors_found:
		var door: CityDoor = door_value
		var forward := door.global_transform.basis.z
		door.set_open_instant(true)
		for _tick in 2:
			await host.get_tree().physics_frame
		for step in range(-4, 5):
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = capsule
			query.exclude = [player_rid]
			query.transform = Transform3D(Basis(), door.global_position + forward * (float(step) * .5) + Vector3(0, .95, 0))
			if not space.intersect_shape(query, 1).is_empty():
				blocked.append("%s at %.1f m" % [door.name, float(step) * .5])
				break
		door.set_open_instant(false)
		for _tick in 2:
			await host.get_tree().physics_frame
		var closed_query := PhysicsShapeQueryParameters3D.new()
		closed_query.shape = capsule
		closed_query.exclude = [player_rid]
		closed_query.transform = Transform3D(Basis(), door.global_position + Vector3(0, .95, 0))
		if space.intersect_shape(closed_query, 1).is_empty():
			leaky.append(door.name)
		var away_query := PhysicsShapeQueryParameters3D.new()
		away_query.shape = capsule
		away_query.exclude = [player_rid]
		away_query.transform = Transform3D(Basis(), door.global_position + forward * 2.0 + Vector3(0, .95, 0))
		if space.intersect_shape(away_query, 1).is_empty():
			closed_free += 1
		door.set_open_instant(true)
	_expect(blocked.is_empty(), "%d City doors are blocked when open, e.g. %s" % [blocked.size(), blocked.slice(0, 5)])
	_expect(leaky.size() < doors_found.size(), "no door leaf collides when closed")
	_expect(closed_free >= doors_found.size() * 9 / 10, "street in front of doors is blocked (%d of %d clear)" % [closed_free, doors_found.size()])
	print("  city: %d entrances, all walkable when open" % doors_found.size())


## Life and sound: the sound bed exists and its levels follow indoors/outdoors and the mute, rain follows the setting and
## pauses indoors, the trams exist, move and stay above head height over the streets.
func _check_life(host: Node, facility: StreamedFacilityView3D) -> void:
	var ambience := facility.get_node_or_null("CityAmbience") as CityAmbience
	var rain := facility.get_node_or_null("CityRain") as CityRain
	var tram := facility.get_node_or_null("CityTram") as CityTram
	_expect(ambience != null and rain != null and tram != null, "City life nodes missing (ambience %s, rain %s, tram %s)" % [ambience != null, rain != null, tram != null])
	if ambience == null or rain == null or tram == null:
		return
	var outside := ambience.targets()
	_expect(float(outside["hum"]) > 0.0 and float(outside["rumble"]) > 0.0, "the street sound bed is silent outdoors")
	var was_muted := Sound.muted
	Sound.muted = true
	var muted := ambience.targets()
	_expect(float(muted["hum"]) == 0.0 and float(muted["rain"]) == 0.0, "mute does not silence the City sound bed")
	Sound.muted = was_muted
	ambience.set_rain(true)
	var raining := ambience.targets()
	ambience.set_rain(false)
	var dry := ambience.targets()
	_expect(float(raining["rain"]) > 0.0 and float(dry["rain"]) == 0.0, "the rain loop does not follow the rain setting")
	ambience.set_rain(Settings.city_rain)
	var saved_rain := Settings.city_rain
	rain.set_raining(true)
	_expect(rain.is_raining() and rain.visible, "rain does not start")
	rain.set_raining(false)
	_expect(not rain.is_raining() and not rain.visible, "rain does not stop")
	rain.set_raining(saved_rain)
	_expect(tram.car_count() == 4, "expected 4 tram cars, got %d" % tram.car_count())
	var before := []
	for car in tram.get_children():
		if car.name.begins_with("Tram_"):
			before.append((car as Node3D).position)
	for _frame in 20:
		await host.get_tree().process_frame
	var moved := 0
	var index := 0
	var layout := (facility.generator as CityRouteGenerator).layout
	for car in tram.get_children():
		if not car.name.begins_with("Tram_"):
			continue
		var now: Vector3 = (car as Node3D).position
		if now.distance_to(before[index]) > .05:
			moved += 1
		var cell := Vector2i(floori(now.x), floori(now.z)) + CityLayout.ORIGIN_OFFSET
		_expect(layout.kind_at(cell.x, cell.y) == CityLayout.ROAD or layout.kind_at(cell.x, cell.y) == CityLayout.CROSS_NS
			or layout.kind_at(cell.x, cell.y) == CityLayout.CROSS_EW or layout.kind_at(cell.x, cell.y) == CityLayout.BRIDGE
			or layout.kind_at(cell.x, cell.y) == CityLayout.KIOSK_FLOOR or layout.kind_at(cell.x, cell.y) == CityLayout.KIOSK_WALL
			or layout.kind_at(cell.x, cell.y) == CityLayout.WATER or layout.kind_at(cell.x, cell.y) == CityLayout.COMPASS
			or layout.kind_at(cell.x, cell.y) == CityLayout.PAVE or layout.kind_at(cell.x, cell.y) == CityLayout.POST,
			"tram %s is over %s, not a street" % [car.name, CityLayout.KIND_NAMES[layout.kind_at(cell.x, cell.y)]])
		index += 1
	_expect(moved >= 2, "the trams do not move (%d of 4 moved)" % moved)
	_expect(CityTram.RAIL_Y >= 5.5, "the tram rail is low enough to hit a runner")
	print("  city: sound bed, rain setting, %d trams moving" % moved)


## The outskirts (pass 3): the avenue and the main street reach the outer rim as 9-wide asphalt arterials, the suburb ring
## road is one closed loop, the farmland is there, the farm tracks join the ring road, the gate on the outer rim is reached
## from the roundabout on foot, and the outer wall seals the whole thing.
func _check_outskirts(layout: CityLayout) -> void:
	var fields := 0
	var dirt := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			var kind := layout.kind_at(gx, gz)
			if kind == CityLayout.FIELD:
				fields += 1
			elif kind == CityLayout.DIRT:
				dirt += 1
	_expect(fields > 4000, "only %d field cells of farmland" % fields)
	_expect(dirt > 200, "only %d farm-track cells" % dirt)
	# arterials: every row/column between downtown and the rim holds a 5-wide ROAD run with 2 PAVE each side
	var avenue_rows := 0
	for gz in CityLayout.HEIGHT:
		if CityLayout.ellipse_r(CityLayout.AVENUE_X, gz) < 1.0 or CityLayout.outer_r(CityLayout.AVENUE_X, gz) >= CityLayout.OUTER_WALL_FROM:
			continue
		if gz >= CityLayout.GATE_ROW - 2:
			continue
		avenue_rows += 1
		var ok := true
		for dx in range(-2, 3):
			ok = ok and layout.kind_at(CityLayout.AVENUE_X + dx, gz) == CityLayout.ROAD
		for dx in [-4, -3, 3, 4]:
			ok = ok and [CityLayout.PAVE, CityLayout.POST, CityLayout.ROAD].has(layout.kind_at(CityLayout.AVENUE_X + dx, gz))   # ROAD = a junction
		_expect(ok, "the avenue is broken at row %d" % gz)
	_expect(avenue_rows > 80, "the avenue runs only %d rows through the outskirts" % avenue_rows)
	# suburb ring road: a closed loop (flood along ROAD cells of the band comes back round)
	var band := {}
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			var r := CityLayout.ellipse_r(gx, gz)
			var t := CityLayout.band_t(gx, gz)
			if r >= 1.0 and t >= CityLayout.RING_ROAD.x and t < CityLayout.RING_ROAD.y and layout.kind_at(gx, gz) == CityLayout.ROAD:
				band[Vector2i(gx, gz)] = true
	var start: Vector2i = band.keys()[0]
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	var cursor := 0
	while cursor < queue.size():
		var cell: Vector2i = queue[cursor]
		cursor += 1
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + (step as Vector2i)
			if band.has(next) and not seen.has(next):
				seen[next] = true
				queue.append(next)
	_expect(seen.size() == band.size(), "the suburb ring road is not one loop (%d of %d cells joined)" % [seen.size(), band.size()])
	# gate reachable from the spawn on foot
	var reached := _flood(layout, layout.spawn, {})
	_expect(reached.has(CityLayout.GATE_CELL), "the outer gate is not reachable from the roundabout")
	_expect(layout.zone_name(CityLayout.AVENUE_X, CityLayout.GATE_ROW - 8).contains("FARM"), "no FARMLAND zone on the way to the gate")
	_expect(layout.zone_name(CityLayout.AVENUE_X + 20, CityLayout.ELLIPSE_CENTER.y + CityLayout.ELLIPSE_AXES.y * 1.1) in ["SUBURBS", "HOUSE", "AVENUE // SUBURBS"], "no SUBURBS zone past the downtown edge")
	print("  city: outskirts: %d field cells, %d track cells, avenue %d rows, ring road %d cells" % [fields, dirt, avenue_rows, band.size()])


## Suburb houses and farms exist in numbers, sit in their bands, and keep clear of every road and track.
func _check_outskirt_lots(layout: CityLayout) -> void:
	var houses := 0
	var barns := 0
	for building in layout.buildings:
		var kind := String(building["kind"])
		var rect: Rect2i = building["rect"]
		var centre := rect.position + rect.size / 2
		if kind == "house":
			houses += 1
			_expect(CityLayout.ellipse_r(centre.x, centre.y) >= 1.0 and CityLayout.band_t(centre.x, centre.y) < CityLayout.SUBURB_TO, "house %s is outside the suburbs" % building["id"])
		elif kind == "barn":
			barns += 1
			_expect(CityLayout.band_t(centre.x, centre.y) >= CityLayout.FARM_FROM, "barn %s is not in the farmland" % building["id"])
		else:
			continue
		for gz in range(rect.position.y - 1, rect.end.y + 1):
			for gx in range(rect.position.x - 1, rect.end.x + 1):
				var k := layout.kind_at(gx, gz)
				_expect(k != CityLayout.ROAD and k != CityLayout.DIRT and k != CityLayout.PAVE, "%s %s touches a road at %d,%d" % [kind, building["id"], gx, gz])
	_expect(houses >= 15, "only %d suburb houses" % houses)
	_expect(barns >= 4, "only %d barns" % barns)
	var counts := {}
	for entry in layout.decor.values():
		counts[String(entry["type"])] = int(counts.get(String(entry["type"]), 0)) + 1
	for type in ["mailbox", "silo", "tractor", "hay_bale", "water_pump"]:
		_expect(int(counts.get(type, 0)) >= 3, "farm/suburb prop %s placed %d times" % [type, int(counts.get(type, 0))])
	print("  city: outskirts: %d houses, %d barns, props %s" % [houses, barns, counts])


## Water bodies: present, never walkable, nothing built or placed on them, and every enterable building's doorway and the
## gate stay reachable from the spawn (the canal is crossed by bridges and roads).
func _check_water(layout: CityLayout) -> void:
	var water := 0
	var outskirts_water := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			if layout.kind_at(gx, gz) != CityLayout.WATER:
				continue
			water += 1
			if CityLayout.ellipse_r(gx, gz) >= 1.0:
				outskirts_water += 1
			_expect(not layout.is_open(gx, gz), "water cell %d,%d is walkable" % [gx, gz])
			_expect(layout.building_index[CityLayout.index_of(gx, gz)] == 0, "a building stands on water at %d,%d" % [gx, gz])
			_expect(not layout.decor.has(Vector2i(gx, gz)), "street furniture on water at %d,%d" % [gx, gz])
	_expect(outskirts_water > 600, "only %d outskirt water cells (canal, lake, ponds)" % outskirts_water)
	var reached := _flood(layout, layout.spawn, {})
	var cut := []
	for building in layout.buildings:
		if bool(building.get("sealed", false)):
			continue
		var ok := false
		for door_value in building["doors"]:
			if reached.has(door_value):
				ok = true
		if not ok:
			cut.append(building["id"])
	_expect(cut.is_empty(), "%d buildings cut off from the spawn (water?): %s" % [cut.size(), cut.slice(0, 6)])
	var bridges := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			if layout.kind_at(gx, gz) == CityLayout.BRIDGE and CityLayout.ellipse_r(gx, gz) >= 1.0:
				bridges += 1
	_expect(bridges >= 12, "only %d footbridge cells over the canal" % bridges)
	print("  city: water %d cells (%d in the outskirts), %d footbridge cells, every building reachable" % [water, outskirts_water, bridges])
