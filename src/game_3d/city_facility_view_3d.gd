class_name CityFacilityView3D
extends StreamedFacilityView3D

## The City renderer. It replaces how a chunk is BUILT (open streets, tall lit facades, interiors with a ceiling, street
## furniture, the dome rim) and inherits everything else from the streamed view: chunk streaming, pickups, fixtures
## (hiding spots, vents), region props, the lamp field and the multiplayer mutations. Collision still comes from the
## GridMap (floor slabs and wall blocks); every visible surface is batched by CitySurface into one mesh per chunk.

const CITY_CEILING := 4.0
const DOOR_HEIGHT := 3.0
const RIM_HEIGHT := 11.0
const GATE_HEIGHT := 7.0
## A basin's lip and a flower bed are solid, readable obstacles at eye level, not a ground texture.
const WATER_RIM := 0.9
const BED_HEIGHT := 1.0
const LAMP_COLOR := Color(1.0, 0.68, 0.32)
const INTERIOR_LAMP_COLOR := Color(1.0, 0.74, 0.42)

## The City is five chunks wide and three deep: with radius 2 every chunk of it is resident from the spawn (the maze
## streams only the 3 x 3 around the runner, which here left the far end of every long street empty).
const CITY_STREAM_RADIUS := 2

var city_generator: CityRouteGenerator
var _sky: CitySky
var _dome_frame: CityDomeFrame


func begin(seed_text: String, player: PlayerController3D,
		state: StreamedWorldState = null) -> void:
	clear()
	city_generator = CityRouteGenerator.new(seed_text)
	generator = city_generator
	tracked_player = player
	world_state = state if state != null else StreamedWorldState.new()
	_tracked_level = 0
	# The runner starts inside the spawn kiosk: face its doorway (south, toward the roundabout's bridge), not a wall.
	if player != null:
		player._yaw = PI
		player._pitch = 0.0
		player._apply_look_rotation()
	_ensure_sky()
	_apply_environment()
	_refresh_stream(true)


## The maze's stream with a wider window: every chunk within CITY_STREAM_RADIUS of the runner stays loaded.
func _refresh_stream(force: bool) -> void:
	var center := current_chunk_coord()
	if not force and center == _last_player_chunk:
		return
	var previous := _last_player_chunk
	_last_player_chunk = center
	var wanted := {}
	for z in range(center.z - CITY_STREAM_RADIUS, center.z + CITY_STREAM_RADIUS + 1):
		for x in range(center.x - CITY_STREAM_RADIUS, center.x + CITY_STREAM_RADIUS + 1):
			var coord := Vector3i(x, center.y, z)
			if generator.is_chunk_allowed(coord):
				wanted[coord] = true
	var immediate := force or previous.x == 999999 or previous.y != center.y \
		or absi(previous.x - center.x) > 1 or absi(previous.z - center.z) > 1
	_pending_loads.clear()
	_pending_unloads.clear()
	if not _active_build.is_empty():
		var active_coord: Vector3i = _active_build.get("coord", Vector3i.ZERO)
		if not wanted.has(active_coord):
			_discard_active_build()
	for coord_value in wanted:
		var coord: Vector3i = coord_value
		if not _loaded.has(coord) and (_active_build.is_empty() \
				or _active_build.get("coord", Vector3i.ZERO) != coord):
			_pending_loads.append(coord)
	for coord_value in _loaded.keys().duplicate():
		var coord: Vector3i = coord_value
		if not wanted.has(coord):
			_pending_unloads.append(coord)
	_pending_loads.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _chunk_distance(a, center) < _chunk_distance(b, center))
	_pending_unloads.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return _chunk_distance(a, center) > _chunk_distance(b, center))
	_stream_queue_center = center
	_stream_completion_pending = not immediate \
		and (not _pending_loads.is_empty() or not _pending_unloads.is_empty())
	if immediate:
		_discard_active_build()
		while not _pending_loads.is_empty():
			_load_chunk(_pending_loads.pop_front())
		while not _pending_unloads.is_empty():
			_unload_chunk(_pending_unloads.pop_front())
	var data: Dictionary = _chunk_data.get(center,
		generator.chunk(center) if generator != null else {})
	chunk_changed.emit(center, data.duplicate(false))


## The zone under a world position (route metres) for the HUD.
func zone_name(world_position: Vector3) -> String:
	if city_generator == null:
		return ""
	return city_generator.layout.zone_name(floori(world_position.x) + CityLayout.ORIGIN_OFFSET.x,
		floori(world_position.z) + CityLayout.ORIGIN_OFFSET.y)


## The gate is an interactable (the lift kind) built from a "gate" pickup entity; every other pickup is the route's own.
func _spawn_pickup(parent: Node3D, data: Dictionary, pickup_data: Dictionary) -> void:
	if String(pickup_data.get("kind", "")) != "gate":
		super(parent, data, pickup_data)
		return
	var entity_id := String(pickup_data.get("id", ""))
	if not world_state.pickup_available(entity_id):
		return
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var cell: Vector2i = pickup_data.get("cell", Vector2i.ZERO)
	var gate := RouteInteractable3D.new()
	gate.name = "DomeGate"
	gate.kind = RouteInteractable3D.Kind.LIFT
	gate.prompt_text = "OPEN THE DOME GATE // %d RELAYS" % CityLayout.gate_relays_required(RoomState.difficulty_id())
	gate.source_cell = Vector2i(coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y)
	gate.position = Vector3(cell.x + .5, .04, cell.y + .5)
	gate.set_meta("streamed_entity_id", entity_id)
	if pickup_requester.is_valid():
		gate.activation_override = pickup_requester.bind(entity_id, "gate", "")
	parent.add_child(gate)
	_pickup_nodes[entity_id] = gate


func _ensure_sky() -> void:
	if _sky == null:
		_sky = CitySky.new()
		_sky.name = "CitySky"
		add_child(_sky)
		_sky.set_day(RoomState.is_day())
		CitySurface.set_day(RoomState.is_day())
	if _dome_frame == null:
		_dome_frame = CityDomeFrame.new()
		_dome_frame.name = "CityDomeFrame"
		add_child(_dome_frame)


## A dark night: the dome sky supplies the picture, the environment only the faint moonlit ambient. No post effects.
func _apply_environment() -> void:
	var world_env := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.07)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.20, 0.23, 0.42)
	env.ambient_light_energy = 0.42
	var sun := get_tree().root.find_child("RouteLight", true, false) as DirectionalLight3D
	if RoomState.is_day():
		# Daytime: a bright sky-coloured ambient and a warm sun with shadows, so building interiors (roofed) stay dim.
		env.background_color = Color(0.55, 0.75, 0.95)
		env.ambient_light_color = Color(0.62, 0.72, 0.90)
		env.ambient_light_energy = 0.34
		if sun != null:
			sun.light_color = Color(1.0, 0.94, 0.8)
			sun.light_energy = 1.35
			sun.shadow_enabled = true
			sun.directional_shadow_max_distance = 70.0
	elif sun != null:
		sun.light_energy = 0.10


# ---------------------------------------------------------------- chunk build

func _create_chunk_build(coord: Vector3i) -> Dictionary:
	var data := generator.chunk(coord)
	var root := Node3D.new()
	root.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	root.position = Vector3(coord.x * StreamedRouteGenerator.CHUNK_SIZE, 0.0,
		coord.z * StreamedRouteGenerator.CHUNK_SIZE)
	root.set_meta("ref_region", "city")
	root.set_meta("ref_heights", {})
	root.set_meta("ref_corridor_h", CITY_CEILING)
	add_child(root)
	var grid := GridMap.new()
	grid.name = "Structure"
	_configure_grid(grid)
	var city: Dictionary = data.get("city", {})
	return {
		"coord": coord, "data": data, "root": root, "grid": grid, "surface": CitySurface.new(),
		"kinds": city.get("kinds", PackedByteArray()), "origin": CityLayout.chunk_origin(coord),
		"safe": bool(data.get("safe_room", false)), "lamps": [], "props_body": StaticBody3D.new(),
		"cell_index": 0, "phase": 0, "prop_index": 0, "fixture_index": 0, "pickup_index": 0,
	}


func _advance_chunk_build(build: Dictionary, immediate: bool) -> bool:
	var root := build["root"] as Node3D
	if root == null or not is_instance_valid(root):
		return true
	var data: Dictionary = build["data"]
	while true:
		match int(build["phase"]):
			0:
				var total := StreamedRouteGenerator.CHUNK_SIZE * StreamedRouteGenerator.CHUNK_SIZE
				var finish := total if immediate else mini(total, int(build["cell_index"]) + STREAM_CELLS_PER_FRAME)
				while int(build["cell_index"]) < finish:
					_build_city_cell(build, int(build["cell_index"]))
					build["cell_index"] = int(build["cell_index"]) + 1
				if int(build["cell_index"]) < total:
					return false
				build["phase"] = 1
				if not immediate:
					return false
			1:
				_build_city_decor(build)
				build["phase"] = 2
				if not immediate:
					return false
			2:
				root.add_child(build["grid"] as GridMap)
				var props_body := build["props_body"] as StaticBody3D
				props_body.name = "StreetFurnitureColliders"
				root.add_child(props_body)
				var surface_node := MeshInstance3D.new()
				surface_node.name = "Surface"
				surface_node.mesh = (build["surface"] as CitySurface).build()
				surface_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				root.add_child(surface_node)
				build["phase"] = 3
				if not immediate:
					return false
			3:
				var region_props: Array = data.get("region_props", [])
				var prop_index := int(build["prop_index"])
				if prop_index < region_props.size():
					_spawn_region_prop(root, build["coord"], region_props[prop_index])
					build["prop_index"] = prop_index + 1
					if not immediate:
						return false
					continue
				build["phase"] = 4
			4:
				if bool(build["safe"]):
					_spawn_safe_room_light(root)
				if build["coord"] == Vector3i.ZERO:
					_spawn_start_marker(root)
				build["phase"] = 5
				if not immediate:
					return false
			5:
				var fixtures: Array = data.get("fixtures", [])
				var fixture_index := int(build["fixture_index"])
				if fixture_index < fixtures.size():
					_spawn_fixture(root, data, fixtures[fixture_index])
					build["fixture_index"] = fixture_index + 1
					if not immediate:
						return false
					continue
				build["phase"] = 6
			6:
				var pickups: Array = data.get("pickups", [])
				var pickup_index := int(build["pickup_index"])
				if pickup_index < pickups.size():
					_spawn_pickup(root, data, pickups[pickup_index])
					build["pickup_index"] = pickup_index + 1
					if not immediate:
						return false
					continue
				build["phase"] = 7
			7:
				var coord: Vector3i = build["coord"]
				root.add_to_group("streamed_chunk")
				if _lamp_field != null:
					_lamp_field.register(coord, (build["lamps"] as Array) + (root.get_meta("extra_lamps", []) as Array))
				if not _all_lights_enabled:
					_set_lights_recursive(root, false)
				_loaded[coord] = root
				_chunk_data[coord] = data
				return true
			_:
				return true
	return false


# ---------------------------------------------------------------- cells

func _floor_tile(kind: int, gx: int, gz: int) -> int:
	var h := absi(hash(Vector2i(gx, gz))) % 100
	match kind:
		CityLayout.ROAD:
			if h < 7:
				return CityAtlas.tile("petals")
			return CityAtlas.tile("cobble_wet") if h < 62 else CityAtlas.tile("cobble")
		CityLayout.PAVE:
			return CityAtlas.tile("petals") if h < 4 else CityAtlas.tile("sidewalk")
		CityLayout.PLAZA, CityLayout.POST:
			return CityAtlas.tile("plaza") if kind == CityLayout.PLAZA else CityAtlas.tile("sidewalk")
		CityLayout.GRASS:
			return CityAtlas.tile("grass")
		CityLayout.PATH:
			return CityAtlas.tile("path")
		CityLayout.ALLEY:
			return CityAtlas.tile("alley")
		CityLayout.COMPASS:
			return CityAtlas.tile("compass")
		CityLayout.CROSS_NS:
			return CityAtlas.tile("cross_ns")
		CityLayout.CROSS_EW:
			return CityAtlas.tile("cross_ew")
		CityLayout.BRIDGE:
			return CityAtlas.tile("bridge")
		CityLayout.KIOSK_FLOOR:
			return CityAtlas.tile("kiosk_floor")
		CityLayout.FLOOR:
			return CityAtlas.tile("wood_floor")
		CityLayout.DOOR:
			return CityAtlas.tile("stone_dark")
		_:
			return CityAtlas.tile("cobble")


func _facade_tile(style: String, pier: int, y: int, top: int, salt: int) -> int:
	if y == 0:
		return CityAtlas.tile("stone_base")
	if y >= top - 1:
		return CityAtlas.tile("cornice")
	var storey := (y - 1) % 4
	var h := absi(hash(Vector3i(pier, (y - storey) / 4, salt))) % 100
	match style:
		"civic":
			if pier % 4 == 1 and storey == 0:
				return CityAtlas.tile("civic_arch_bot")
			if pier % 4 == 1 and storey == 1:
				return CityAtlas.tile("civic_arch_top")
			return CityAtlas.tile("civic_a")
		"industrial":
			if pier % 5 == 2 and storey == 1:
				return CityAtlas.tile("ind_port")
			return CityAtlas.tile("ind_panel")
		_:
			var window := pier % 3 == 1
			if window and y <= 2:
				return CityAtlas.tile("shop_bot" if y == 1 else "shop_top")
			if window and storey <= 1:
				var variant := "win_lit" if h < 34 else ("win_cyan" if h < 44 else "win_dark")
				return CityAtlas.tile("%s_%s" % [variant, "bot" if storey == 0 else "top"])
			return CityFacadeDetails.base_tile(CityFacadeDetails.variant_of(salt), y, h)


func _build_city_cell(build: Dictionary, index: int) -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var x := index % size
	var z := index / size
	var kinds: PackedByteArray = build["kinds"]
	var kind := int(kinds[index])
	var origin: Vector2i = build["origin"]
	var gx := origin.x + x
	var gz := origin.y + z
	var grid := build["grid"] as GridMap
	var surface := build["surface"] as CitySurface
	var layout := city_generator.layout
	if CityLayout.OPEN_KINDS.has(kind):
		grid.set_cell_item(Vector3i(x, 0, z), _col_floor_item)
		surface.floor_quad(x, z, _floor_tile(kind, gx, gz))
		match kind:
			CityLayout.FLOOR:
				surface.ceiling_quad(x, z, CITY_CEILING, CityAtlas.tile("ceiling"))
			CityLayout.KIOSK_FLOOR:
				surface.ceiling_quad(x, z, CITY_CEILING, CityAtlas.tile("ceiling"))
				surface.top_quad(x, z, CITY_CEILING, CityAtlas.tile("kiosk_roof"))
			CityLayout.DOOR:
				_build_door_cell(surface, layout, x, z, gx, gz)
		return
	grid.set_cell_item(Vector3i(x, 0, z), _col_wall_item)
	match kind:
		CityLayout.POST:
			# Street furniture blocks only what it draws (a pole, a trunk, a bench): the GridMap cell stays floor and a
			# matching box is added by _add_decor. The A* grid still treats the whole cell as blocked.
			grid.set_cell_item(Vector3i(x, 0, z), _col_floor_item)
			surface.floor_quad(x, z, _floor_tile(kind, gx, gz))
		CityLayout.HEDGE:
			surface.floor_quad(x, z, CityAtlas.tile("grass"))
			surface.box(Vector3(x, 0, z), Vector3(1, 1.5, 1), CityAtlas.tile("hedge"), CityAtlas.tile("hedge_top"))
		CityLayout.BED:
			surface.floor_quad(x, z, CityAtlas.tile("grass"))
			surface.box(Vector3(x, 0, z), Vector3(1, BED_HEIGHT, 1), CityAtlas.tile("bed_edge"), CityAtlas.tile("flowers"))
		CityLayout.WATER:
			surface.floor_quad(x, z, CityAtlas.tile("water"), 0.12)
			for dir_value in CitySurface.FACE_DIRS:
				var dir: Vector2i = dir_value
				if layout.is_open(gx + dir.x, gz + dir.y):
					surface.wall_face(x, z, dir, 0.0, WATER_RIM, CityAtlas.tile("water_edge"))
		CityLayout.RIM:
			for dir_value in CitySurface.FACE_DIRS:
				var dir: Vector2i = dir_value
				if layout.is_open(gx + dir.x, gz + dir.y):
					surface.wall_face(x, z, dir, 0.0, RIM_HEIGHT, 0, CitySurface.Mat.RIM, RIM_HEIGHT / 4.0)
		CityLayout.GATE:
			# A closed 7 m barrier across the avenue: panels, a glowing cyan port band, a cornice and a lit cap.
			surface.top_quad(x, z, GATE_HEIGHT, CityAtlas.tile("kiosk_roof"))
			for dir_value in CitySurface.FACE_DIRS:
				var dir: Vector2i = dir_value
				if not layout.is_open(gx + dir.x, gz + dir.y):
					continue
				for row in int(GATE_HEIGHT):
					var tile_name := "ind_panel"
					if row == 5:
						tile_name = "ind_port"
					elif row == int(GATE_HEIGHT) - 1:
						tile_name = "cornice"
					surface.wall_face(x, z, dir, row, row + 1, CityAtlas.tile(tile_name))
		CityLayout.KIOSK_WALL:
			surface.top_quad(x, z, CITY_CEILING, CityAtlas.tile("kiosk_roof"))
			for dir_value in CitySurface.FACE_DIRS:
				var dir: Vector2i = dir_value
				var neighbour := layout.kind_at(gx + dir.x, gz + dir.y)
				if neighbour == CityLayout.KIOSK_FLOOR or neighbour == CityLayout.DOOR and _inside_kiosk(layout, gx + dir.x, gz + dir.y):
					for row in 4:
						surface.wall_face(x, z, dir, row, row + 1, CityAtlas.tile("plaster"))
				elif layout.is_open(gx + dir.x, gz + dir.y):
					for row in 3:
						surface.wall_face(x, z, dir, row, row + 1, CityAtlas.tile("kiosk_wall"))
					surface.wall_face(x, z, dir, 3, 4, CityAtlas.tile("kiosk_sign"))
		_:
			_build_facade_cell(surface, layout, x, z, gx, gz)


func _inside_kiosk(layout: CityLayout, gx: int, gz: int) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if layout.kind_at(gx + (step as Vector2i).x, gz + (step as Vector2i).y) == CityLayout.KIOSK_FLOOR:
			return true
	return false


func _build_facade_cell(surface: CitySurface, layout: CityLayout, x: int, z: int, gx: int, gz: int) -> void:
	var building := layout.building_at(gx, gz)
	var height := float(building.get("height", 6.0))
	var style := String(building.get("style", "brick"))
	var top := int(height)
	var salt := absi(hash(String(building.get("id", "W"))))
	for dir_value in CitySurface.FACE_DIRS:
		var dir: Vector2i = dir_value
		var neighbour := layout.kind_at(gx + dir.x, gz + dir.y)
		if CityLayout.OUTDOOR_KINDS.has(neighbour):
			var pier := gx if dir.y != 0 else gz
			for y in top:
				surface.wall_face(x, z, dir, y, y + 1, _facade_tile(style, pier, y, top, salt))
			if style == "brick":
				CityFacadeDetails.add_face(surface, building, dir, x, z, pier, top, salt)
		elif neighbour == CityLayout.FLOOR or neighbour == CityLayout.DOOR or neighbour == CityLayout.KIOSK_FLOOR:
			for row in int(CITY_CEILING):
				surface.wall_face(x, z, dir, row, row + 1, CityAtlas.tile("plaster"))


## A doorway is 3 m high; the facade continues above it and the lintel's underside closes the opening.
func _build_door_cell(surface: CitySurface, layout: CityLayout, x: int, z: int, gx: int, gz: int) -> void:
	var building := layout.building_at(gx, gz)
	var kiosk := building.is_empty()
	var height := CITY_CEILING if kiosk else float(building.get("height", 6.0))
	var style := String(building.get("style", "brick"))
	var top := int(height)
	var salt := absi(hash(String(building.get("id", "K"))))
	surface.ceiling_quad(x, z, DOOR_HEIGHT, CityAtlas.tile("stone_dark"))
	if not kiosk:
		# A low stone threshold across the doorway (visual only; the floor collider stays flat).
		surface.box(Vector3(x, 0, z), Vector3(1, .1, 1), CityAtlas.tile("stone_base"), CityAtlas.tile("stone_dark"))
	for dir_value in CitySurface.FACE_DIRS:
		var dir: Vector2i = dir_value
		var neighbour := layout.kind_at(gx + dir.x, gz + dir.y)
		if CityLayout.OUTDOOR_KINDS.has(neighbour):
			var pier := gx if dir.y != 0 else gz
			for y in range(int(DOOR_HEIGHT), top):
				var tile := CityAtlas.tile("kiosk_wall") if kiosk else _facade_tile(style, pier, y, top, salt)
				surface.wall_face(x, z, dir, y, y + 1, tile)
		elif neighbour == CityLayout.FLOOR or neighbour == CityLayout.KIOSK_FLOOR:
			surface.wall_face(x, z, dir, DOOR_HEIGHT, CITY_CEILING, CityAtlas.tile("plaster"))


# ---------------------------------------------------------------- street furniture and lights

func _build_city_decor(build: Dictionary) -> void:
	var surface := build["surface"] as CitySurface
	var root := build["root"] as Node3D
	var lamps: Array = build["lamps"]
	var data: Dictionary = build["data"]
	var city: Dictionary = data.get("city", {})
	for entry_value in city.get("decor", []):
		var entry: Dictionary = entry_value
		var cell: Vector2i = entry["cell"]
		_add_decor(build["props_body"] as StaticBody3D, surface, root, lamps, String(entry["type"]), cell, float(entry["yaw"]))
	# One warm lamp inside every building whose middle lies in this chunk.
	for building_value in city.get("buildings", []):
		var building: Dictionary = building_value
		var rect: Rect2i = building["rect"]
		var middle := rect.position + rect.size / 2
		if middle.x < 1 or middle.y < 1 or middle.x > 43 or middle.y > 43:
			continue
		lamps.append([root.position + Vector3(middle.x + .5, 3.3, middle.y + .5), INTERIOR_LAMP_COLOR, .9, 0, 6.5])
		if String(building["style"]) == "brick":
			CityFacadeDetails.add_roof(surface, building, absi(hash(String(building["id"]))))


func _add_decor_collider(body: StaticBody3D, type: String, cell: Vector2i, yaw: float) -> void:
	if body == null or not CityLayout.DECOR_COLLIDERS.has(type):
		return
	var size: Vector3 = CityLayout.DECOR_COLLIDERS[type]
	if absf(sin(yaw)) > .5:
		size = Vector3(size.z, size.y, size.x)
	var shape := BoxShape3D.new()
	shape.size = size
	var owner_node := CollisionShape3D.new()
	owner_node.shape = shape
	owner_node.position = Vector3(cell.x + .5, size.y * .5, cell.y + .5)
	body.add_child(owner_node)


func _add_decor(build_body: StaticBody3D, surface: CitySurface, root: Node3D, lamps: Array, type: String, cell: Vector2i, yaw: float) -> void:
	var cx := cell.x + .5
	var cz := cell.y + .5
	var pole := CityAtlas.tile("pole")
	var wide_along_x := absf(sin(yaw)) < .5
	_add_decor_collider(build_body, type, cell, yaw)
	match type:
		"lamp":
			var arm := Vector3(roundf(sin(yaw)), 0, roundf(-cos(yaw))) * .28
			surface.box(Vector3(cx - .07, 0, cz - .07), Vector3(.14, 3.1, .14), pole)
			surface.box(Vector3(cx - .06 + arm.x * .5, 3.0, cz - .06 + arm.z * .5), Vector3(.12 + absf(arm.x), .1, .12 + absf(arm.z)), pole)
			surface.box(Vector3(cx + arm.x - .14, 2.98, cz + arm.z - .14), Vector3(.28, .46, .28), CityAtlas.tile("lantern"))
			surface.box(Vector3(cx + arm.x - .18, 3.44, cz + arm.z - .18), Vector3(.36, .07, .36), pole)
			lamps.append([root.position + Vector3(cx + arm.x, 3.2, cz + arm.z), LAMP_COLOR, 0.0 if RoomState.is_day() else 1.0, 0, 7.5])
		"tree":
			surface.box(Vector3(cx - .14, 0, cz - .14), Vector3(.28, 2.7, .28), CityAtlas.tile("trunk"))
			surface.box(Vector3(cx - .85, 2.5, cz - .85), Vector3(1.7, .9, 1.7), CityAtlas.tile("blossom"))
			surface.box(Vector3(cx - 1.1, 3.3, cz - 1.1), Vector3(2.2, 1.0, 2.2), CityAtlas.tile("blossom"))
			surface.box(Vector3(cx - .7, 4.2, cz - .7), Vector3(1.4, .8, 1.4), CityAtlas.tile("blossom"))
		"cypress":
			surface.box(Vector3(cx - .55, 0, cz - .55), Vector3(1.1, 1.6, 1.1), CityAtlas.tile("cypress"))
			surface.box(Vector3(cx - .42, 1.6, cz - .42), Vector3(.84, 1.7, .84), CityAtlas.tile("cypress"))
			surface.box(Vector3(cx - .26, 3.3, cz - .26), Vector3(.52, 1.5, .52), CityAtlas.tile("cypress"))
		"bench":
			var wood := CityAtlas.tile("wood_bench")
			var along := Vector3(.9, 0, .4) if wide_along_x else Vector3(.4, 0, .9)
			surface.box(Vector3(cx - along.x * .5, .38, cz - along.z * .5), Vector3(along.x, .08, along.z), wood)
			if wide_along_x:
				surface.box(Vector3(cx - .45, .46, cz - .24), Vector3(.9, .42, .07), wood)
				surface.box(Vector3(cx - .4, 0, cz - .16), Vector3(.08, .38, .32), pole)
				surface.box(Vector3(cx + .32, 0, cz - .16), Vector3(.08, .38, .32), pole)
			else:
				surface.box(Vector3(cx - .24, .46, cz - .45), Vector3(.07, .42, .9), wood)
				surface.box(Vector3(cx - .16, 0, cz - .4), Vector3(.32, .38, .08), pole)
				surface.box(Vector3(cx - .16, 0, cz + .32), Vector3(.32, .38, .08), pole)
		"planter":
			surface.box(Vector3(cx - .42, 0, cz - .42), Vector3(.84, .5, .84), CityAtlas.tile("planter"), CityAtlas.tile("flowers"))
			surface.box(Vector3(cx - .3, .5, cz - .3), Vector3(.6, .35, .6), CityAtlas.tile("blossom"))
		"bollard":
			surface.box(Vector3(cx - .12, 0, cz - .12), Vector3(.24, .75, .24), pole)
			surface.box(Vector3(cx - .12, .75, cz - .12), Vector3(.24, .08, .24), CityAtlas.tile("cyan_lamp"))
		"statue":
			var stone := CityAtlas.tile("statue_stone")
			surface.box(Vector3(cx - 1.5, 0, cz - 1.5), Vector3(3, 1.2, 3), stone)
			surface.box(Vector3(cx - 1.0, 1.2, cz - 1.0), Vector3(2, .35, 2), stone)
			surface.box(Vector3(cx - .45, 1.55, cz - .3), Vector3(.9, 1.5, .6), stone)
			surface.box(Vector3(cx - .3, 3.05, cz - .3), Vector3(.6, .6, .6), stone)
			surface.box(Vector3(cx + .45, 1.9, cz - .2), Vector3(.22, 1.2, .4), stone)
		_:
			CityProps.add(type, surface, root, lamps, cx, cz, yaw)
