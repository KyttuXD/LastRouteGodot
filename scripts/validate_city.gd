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
	for node_name in ["NewRunButton", "HostButton", "JoinButton", "BackToGamesButton", "RoomCodeInput"]:
		_expect(menu.find_child(node_name, true, false) != null, "City menu lacks %s" % node_name)
	menu.queue_free()
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
	_expect(layout.buildings.size() >= 20, "too few buildings (%d)" % layout.buildings.size())
	_expect(layout.shelters.size() == 5, "expected 5 shelters, got %d" % layout.shelters.size())
	_expect(layout.gardens.size() == 2, "expected two gardens")
	var open := 0
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			_expect(layout.kind_at(gx, gz) != CityLayout.BLOCK, "unfinished block cell at %d,%d" % [gx, gz])
			if layout.is_open(gx, gz):
				open += 1
			if CityLayout.ellipse_r(gx, gz) >= 1.0 and layout.is_open(gx, gz):
				_expect(false, "open cell outside the dome at %d,%d" % [gx, gz])
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
				if not blocked.has(cell) and not reached.has(cell):
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
				_expect(kinds.has("relay"), "chunk %s has no relay" % coord)
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
	_expect(facility.loaded_chunk_count() == 9, "expected 9 resident chunks around the spawn, got %d" % facility.loaded_chunk_count())
	var player := scene.get_node("%Player") as PlayerController3D
	_expect(player.global_position.distance_to(Vector3(22.5, .04, 22.5)) < 2.0, "the runner did not start on the spawn")
	_expect(facility.get_node_or_null("CitySky") != null, "the dome sky is missing")
	scene.queue_free()
	await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)
