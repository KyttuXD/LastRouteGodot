class_name StreamedFacilityView3D
extends Node3D

## Live debug renderer for StreamedRouteGenerator. It keeps a 3x3 horizontal
## window around the runner plus the matching chunks immediately above/below,
## so the route can extend forever without retaining every visited mesh.

signal chunk_changed(coord: Vector3i, data: Dictionary)
signal pickup_claimed(entity_id: String)

const CELL_SIZE := 1.0
const LEVEL_HEIGHT := 4.0
const STREAM_RADIUS := 1
const WALL_HEIGHT := 3.0
const SLAB := 0.1
const STAIR_RUN := 8.0
const STAIR_RISE := LEVEL_HEIGHT
const STAIR_WIDTH := 1.8
const STAIR_STEPS := 16

const FLOOR_TEXTURE := "res://art/props-3d/environment/floor_texture.png"
const WALL_TEXTURE := "res://art/props-3d/environment/wall_texture.png"
const PRISON_MODELS := {
	"gate": "res://art/props-3d/props/prison/prison_cell_gate.glb",
	"bunk": "res://art/props-3d/props/prison/prison_bunk.glb",
	"cage": "res://art/props-3d/props/prison/dungeon_cage.glb",
	"chair": "res://art/props-3d/props/prison/restraint_chair.glb",
}
const REGION_COLORS := {
	"maze": Color("77756d"),
	"mansion": Color("765146"),
	"hotel": Color("80725f"),
	"apartment": Color("62717a"),
	"beach": Color("89aeb5"),
	"gothic": Color("4b3b59"),
	"prison": Color("48535a"),
	"inferno": Color("7e352a"),
}
const REGION_WALL_COLORS := {
	"maze": Color("3d3b38"),
	"mansion": Color("4c342d"),
	"hotel": Color("50483d"),
	"apartment": Color("394958"),
	"beach": Color("61747b"),
	"gothic": Color("34283e"),
	"prison": Color("303940"),
	"inferno": Color("4f2626"),
}

var generator: StreamedRouteGenerator
var world_state: StreamedWorldState
var tracked_player: PlayerController3D

var _library: MeshLibrary
var _floor_items := {}
var _wall_items := {}
var _safe_floor_item := -1
var _loaded := {}
var _chunk_data := {}
var _pickup_nodes := {}
var _last_player_chunk := Vector3i(999999, 999999, 999999)


func _ready() -> void:
	_library = _build_mesh_library()


func begin(seed_text: String, player: PlayerController3D,
		state: StreamedWorldState = null) -> void:
	clear()
	generator = StreamedRouteGenerator.new(seed_text)
	tracked_player = player
	world_state = state if state != null else StreamedWorldState.new()
	_refresh_stream(true)


func clear() -> void:
	for node_value in _loaded.values():
		var node := node_value as Node
		if node != null:
			node.queue_free()
	_loaded.clear()
	_chunk_data.clear()
	_pickup_nodes.clear()
	_last_player_chunk = Vector3i(999999, 999999, 999999)


func spawn_position() -> Vector3:
	if generator == null:
		return Vector3.ZERO
	var cell := generator.spawn_cell()
	return Vector3(cell.x + .5, .04, cell.y + .5)


func current_level() -> int:
	if tracked_player == null:
		return 0
	return roundi(tracked_player.global_position.y / LEVEL_HEIGHT)


func current_chunk_coord() -> Vector3i:
	if tracked_player == null:
		return Vector3i.ZERO
	return Vector3i(
		floori(tracked_player.global_position.x / StreamedRouteGenerator.CHUNK_SIZE),
		current_level(),
		floori(tracked_player.global_position.z / StreamedRouteGenerator.CHUNK_SIZE))


func current_chunk_data() -> Dictionary:
	var coord := current_chunk_coord()
	if _chunk_data.has(coord):
		return (_chunk_data[coord] as Dictionary).duplicate(false)
	return generator.chunk(coord) if generator != null else {}


func loaded_chunk_count() -> int:
	return _loaded.size()


func _process(_delta: float) -> void:
	if generator == null or tracked_player == null:
		return
	_refresh_stream(false)
	_collect_taken_pickups()


func _refresh_stream(force: bool) -> void:
	var center := current_chunk_coord()
	if not force and center == _last_player_chunk:
		return
	_last_player_chunk = center
	var wanted := {}
	for z in range(center.z - STREAM_RADIUS, center.z + STREAM_RADIUS + 1):
		for x in range(center.x - STREAM_RADIUS, center.x + STREAM_RADIUS + 1):
			wanted[Vector3i(x, center.y, z)] = true
	# The current shaft remains present on both adjacent floors while walking a
	# flight, preventing the ramp from unloading halfway through the crossing.
	wanted[Vector3i(center.x, center.y - 1, center.z)] = true
	wanted[Vector3i(center.x, center.y + 1, center.z)] = true
	for coord_value in _loaded.keys().duplicate():
		var coord: Vector3i = coord_value
		if not wanted.has(coord):
			_unload_chunk(coord)
	for coord_value in wanted:
		var coord: Vector3i = coord_value
		if not _loaded.has(coord):
			_load_chunk(coord)
	var data: Dictionary = _chunk_data.get(center, {})
	chunk_changed.emit(center, data.duplicate(false))


func _load_chunk(coord: Vector3i) -> void:
	var data := generator.chunk(coord)
	var root := Node3D.new()
	root.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	root.position = Vector3(coord.x * StreamedRouteGenerator.CHUNK_SIZE,
		coord.y * LEVEL_HEIGHT, coord.z * StreamedRouteGenerator.CHUNK_SIZE)
	add_child(root)
	var grid := GridMap.new()
	grid.name = "Structure"
	_configure_grid(grid)
	root.add_child(grid)
	var ceiling := GridMap.new()
	ceiling.name = "Ceiling"
	_configure_grid(ceiling)
	root.add_child(ceiling)

	var region := String(data.get("region", "maze"))
	var floor_item := int(_floor_items.get(region, _floor_items["maze"]))
	var wall_item := int(_wall_items.get(region, _wall_items["maze"]))
	var ceiling_voids := _stair_voids(data, "up")
	var floor_voids := _stair_voids(data, "down")
	var grid_data: Array = data["grid"]
	var safe := bool(data.get("safe_room", false))
	var center := StreamedRouteGenerator.CHUNK_SIZE / 2
	for z in StreamedRouteGenerator.CHUNK_SIZE:
		for x in StreamedRouteGenerator.CHUNK_SIZE:
			var cell := Vector2i(x, z)
			if int(grid_data[z][x]) == 0:
				if not floor_voids.has(cell):
					var item := _safe_floor_item if safe and abs(x - center) <= 3 \
						and abs(z - center) <= 3 else floor_item
					grid.set_cell_item(Vector3i(x, 0, z), item)
				if not ceiling_voids.has(cell):
					ceiling.set_cell_item(Vector3i(x, 1, z), 2)
			else:
				grid.set_cell_item(Vector3i(x, 0, z), wall_item)
	_spawn_stairs(root, data)
	if region == "prison":
		_spawn_prison_props(root, data)
	if safe:
		_spawn_safe_room_light(root)
	_spawn_pickups(root, data)
	_loaded[coord] = root
	_chunk_data[coord] = data


func _unload_chunk(coord: Vector3i) -> void:
	var root := _loaded.get(coord) as Node
	if root != null:
		for entity_id in _pickup_nodes.keys().duplicate():
			var pickup := _pickup_nodes[entity_id] as Node
			if pickup == null or root.is_ancestor_of(pickup):
				_pickup_nodes.erase(entity_id)
		root.queue_free()
	_loaded.erase(coord)
	_chunk_data.erase(coord)


func _configure_grid(grid: GridMap) -> void:
	grid.cell_size = Vector3.ONE * CELL_SIZE
	grid.cell_center_y = false
	grid.mesh_library = _library


func _stair_voids(data: Dictionary, direction: String) -> Dictionary:
	var result := {}
	for stair_value in data.get("stairs", []):
		var stair: Dictionary = stair_value
		if String(stair.get("direction", "")) != direction:
			continue
		for cell in _stair_path(stair):
			result[cell] = true
	return result


func _stair_path(stair: Dictionary) -> Array[Vector2i]:
	var start: Vector2i = stair.get("cell", Vector2i.ZERO)
	var center := Vector2i(StreamedRouteGenerator.CHUNK_SIZE / 2,
		StreamedRouteGenerator.CHUNK_SIZE / 2)
	var delta := center - start
	var direction := Vector2i(signi(delta.x), 0) if abs(delta.x) >= abs(delta.y) \
		else Vector2i(0, signi(delta.y))
	var cells: Array[Vector2i] = []
	for index in range(roundi(STAIR_RUN) + 1):
		cells.append(start + direction * index)
	return cells


func _spawn_stairs(parent: Node3D, data: Dictionary) -> void:
	for stair_value in data.get("stairs", []):
		var stair: Dictionary = stair_value
		if String(stair.get("direction", "")) != "up":
			continue
		var path := _stair_path(stair)
		if path.size() < 2:
			continue
		var start_cell := path[0]
		var direction_2d := path[1] - path[0]
		var direction := Vector3(direction_2d.x, 0.0, direction_2d.y)
		var start := Vector3(start_cell.x + .5, 0.0, start_cell.y + .5)
		var stair_root := Node3D.new()
		stair_root.name = String(stair.get("id", "Stair")).replace(":", "_")
		stair_root.add_to_group("streamed_stair")
		parent.add_child(stair_root)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("695947") if String(stair.get("style", "")) \
			== "grand_foyer" else Color("56616a")
		material.roughness = .86
		for step_index in STAIR_STEPS:
			var progress := float(step_index + 1) / STAIR_STEPS
			var step := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(STAIR_WIDTH, .12, STAIR_RUN / STAIR_STEPS)
			mesh.material = material
			step.mesh = mesh
			step.position = start + direction * ((step_index + .5) * STAIR_RUN / STAIR_STEPS)
			step.position.y = progress * STAIR_RISE - .06
			step.rotation.y = atan2(direction.x, direction.z)
			stair_root.add_child(step)
		var ramp := StaticBody3D.new()
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		var slope_length := Vector2(STAIR_RUN, STAIR_RISE).length()
		shape.size = Vector3(STAIR_WIDTH, .12, slope_length)
		collision.shape = shape
		var yaw := atan2(direction.x, direction.z)
		var angle := atan2(STAIR_RISE, STAIR_RUN)
		collision.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, -angle)
		collision.position = start + direction * (STAIR_RUN * .5) \
			+ Vector3.UP * (STAIR_RISE * .5)
		ramp.add_child(collision)
		stair_root.add_child(ramp)


func _spawn_prison_props(parent: Node3D, data: Dictionary) -> void:
	var rooms: Array = data.get("rooms", [])
	for room_index in mini(rooms.size(), 6):
		var room: Dictionary = rooms[room_index]
		var rect: Rect2i = room.get("rect", Rect2i())
		var above_hall := rect.position.y < StreamedRouteGenerator.CHUNK_SIZE / 2
		var gate_at := Vector3(rect.position.x + rect.size.x * .5, 0.0,
			rect.end.y - .15 if above_hall else rect.position.y + .15)
		_spawn_authored_prop(parent, PRISON_MODELS["gate"], gate_at,
			0.0 if above_hall else PI, Vector3(rect.size.x, 2.4, .16))
		var inside_z := rect.position.y + 1.0 if above_hall else rect.end.y - 1.0
		_spawn_authored_prop(parent, PRISON_MODELS["bunk"],
			Vector3(rect.position.x + 1.0, 0.0, inside_z), PI * .5,
			Vector3(.8, 1.55, 2.1))
		if room_index % 3 == 1:
			_spawn_authored_prop(parent, PRISON_MODELS["chair"],
				Vector3(rect.end.x - 1.0, 0.0, inside_z), 0.0,
				Vector3(.7, 1.2, .7))
	if not rooms.is_empty():
		var room: Dictionary = rooms[min(rooms.size() - 1, 2)]
		var center: Vector2i = room.get("center", Vector2i(16, 16))
		_spawn_authored_prop(parent, PRISON_MODELS["cage"],
			Vector3(center.x + .5, 0.0, center.y + .5), 0.0,
			Vector3(2.2, 2.3, 2.2))


func _spawn_authored_prop(parent: Node3D, path: String, at: Vector3,
		yaw: float, blocker_size: Vector3) -> void:
	var packed := load(path) as PackedScene
	if packed == null:
		return
	var visual := packed.instantiate() as Node3D
	if visual == null:
		return
	visual.position = at
	visual.rotation.y = yaw
	visual.add_to_group("streamed_prison_prop")
	parent.add_child(visual)
	var body := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = blocker_size
	collision.shape = shape
	collision.position = at + Vector3.UP * (blocker_size.y * .5)
	collision.rotation.y = yaw
	body.add_child(collision)
	parent.add_child(body)


func _spawn_safe_room_light(parent: Node3D) -> void:
	var light := OmniLight3D.new()
	light.name = "CheckpointLight"
	light.position = Vector3(StreamedRouteGenerator.CHUNK_SIZE * .5,
		2.35, StreamedRouteGenerator.CHUNK_SIZE * .5)
	light.light_color = Color("85d6ad")
	light.light_energy = 1.1
	light.omni_range = 8.0
	parent.add_child(light)


func _spawn_pickups(parent: Node3D, data: Dictionary) -> void:
	for pickup_value in data.get("pickups", []):
		var pickup_data: Dictionary = pickup_value
		var entity_id := String(pickup_data.get("id", ""))
		if not world_state.pickup_available(entity_id):
			continue
		var cell: Vector2i = pickup_data.get("cell", Vector2i.ZERO)
		var pickup := RouteInteractable3D.new()
		pickup.name = "Pickup_%s" % entity_id.replace(":", "_")
		pickup.kind = RouteInteractable3D.Kind.TOOL_PICKUP
		pickup.source_cell = cell
		pickup.position = Vector3(cell.x + .5, .04, cell.y + .5)
		pickup.set_meta("streamed_entity_id", entity_id)
		parent.add_child(pickup)
		pickup.configure_tool_pickup(String(pickup_data.get("item", "")))
		_pickup_nodes[entity_id] = pickup


func _collect_taken_pickups() -> void:
	for entity_id_value in _pickup_nodes.keys().duplicate():
		var entity_id := String(entity_id_value)
		var pickup := _pickup_nodes.get(entity_id) as RouteInteractable3D
		if pickup == null or not is_instance_valid(pickup):
			_pickup_nodes.erase(entity_id)
			continue
		if pickup.completed and world_state.claim_pickup(entity_id):
			pickup_claimed.emit(entity_id)
			_pickup_nodes.erase(entity_id)


func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var floor_texture := load(FLOOR_TEXTURE) as Texture2D
	var wall_texture := load(WALL_TEXTURE) as Texture2D
	var ceiling_material := _material(floor_texture, Color("77756d"), Vector3.ONE)
	_add_box(library, 2, Vector3(1.0, SLAB, 1.0),
		Vector3(0.0, WALL_HEIGHT - 1.0 - SLAB * .5, 0.0), ceiling_material, false)
	var next_id := 3
	for region in REGION_COLORS:
		var floor_material := _material(floor_texture, REGION_COLORS[region], Vector3.ONE)
		var wall_material := _material(wall_texture, REGION_WALL_COLORS[region],
			Vector3(1.0, WALL_HEIGHT, 1.0))
		_add_box(library, next_id, Vector3(1.0, SLAB, 1.0),
			Vector3(0.0, -SLAB * .5, 0.0), floor_material, true)
		_floor_items[region] = next_id
		next_id += 1
		_add_box(library, next_id, Vector3(1.0, WALL_HEIGHT, 1.0),
			Vector3(0.0, WALL_HEIGHT * .5, 0.0), wall_material, true)
		_wall_items[region] = next_id
		next_id += 1
	_safe_floor_item = next_id
	_add_box(library, next_id, Vector3(1.0, SLAB, 1.0),
		Vector3(0.0, -SLAB * .5, 0.0),
		_material(floor_texture, Color("5f9b78"), Vector3.ONE), true)
	return library


static func _material(texture: Texture2D, color: Color,
		repeat: Vector3) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.albedo_color = color
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.uv1_scale = repeat
	material.roughness = .88
	return material


static func _add_box(library: MeshLibrary, id: int, size: Vector3,
		offset: Vector3, material: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = material
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var placement := Transform3D(Basis.IDENTITY, offset)
	library.set_item_mesh_transform(id, placement)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, placement])
