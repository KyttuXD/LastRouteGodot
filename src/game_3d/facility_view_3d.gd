class_name FacilityView3D
extends Node3D

## 3D counterpart to src/game/facility_view.gd. Renders the SAME
## facility_generator.gd grid data (unchanged, engine-agnostic) via a
## GridMap — the 3D equivalent of the 2D renderer's TileMapLayer — with
## physics collision. Placeholder box meshes stand in for real 3D art; see
## art/props-3d/README.md for the scale/pivot convention this mirrors:
## 1 grid cell = 1 meter, ground plane is XZ (Godot is Y-up).

const CELL_SIZE := 1.0
const WALL_HEIGHT := 2.4
const FLOOR_THICKNESS := 0.1
const FLOOR_COLOR := Color(0.09, 0.13, 0.15)
const WALL_COLOR := Color(0.18, 0.27, 0.30)

const ITEM_FLOOR := 0
const ITEM_WALL := 1

var generator: FacilityGenerator

var _grid_map: GridMap
var _interactables: Array = []


func _ready() -> void:
	_grid_map = GridMap.new()
	_grid_map.cell_size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	_grid_map.mesh_library = _build_mesh_library()
	add_child(_grid_map)


func generate_floor(seed_text: String) -> void:
	generator = FacilityGenerator.new(seed_text)
	_paint_grid()
	_spawn_interactables()


## World-space size of the facility footprint on the XZ ground plane.
func facility_extent() -> Vector3:
	return Vector3(generator.cols, 0.0, generator.rows) * CELL_SIZE


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)


func start_world_position() -> Vector3:
	return cell_to_world(generator.start)


func _paint_grid() -> void:
	_grid_map.clear()
	for y in generator.rows:
		for x in generator.cols:
			var item := ITEM_FLOOR if generator.grid[y][x] == 0 else ITEM_WALL
			_grid_map.set_cell_item(Vector3i(x, 0, y), item)


func _spawn_interactables() -> void:
	for node in _interactables:
		node.queue_free()
	_interactables.clear()

	for relay in generator.relays:
		_spawn_interactable(RouteInteractable3D.Kind.RELAY, Vector2i(relay["x"], relay["y"]), "RECOVER SIGNAL RELAY", Color(0.26, 0.88, 0.92))
	for battery in generator.batteries:
		_spawn_interactable(RouteInteractable3D.Kind.BATTERY, Vector2i(battery["x"], battery["y"]), "COLLECT BATTERY", Color(0.95, 0.82, 0.25))
	for zone in generator.safe_zones:
		_spawn_interactable(RouteInteractable3D.Kind.SAFE_ZONE, Vector2i(zone["x"], zone["y"]), "REST AT SAFE ZONE", Color(0.35, 0.95, 0.52))
	_spawn_interactable(RouteInteractable3D.Kind.LIFT, generator.exit_cell, "USE SERVICE LIFT", Color(0.76, 0.55, 0.96))


func _spawn_interactable(kind: RouteInteractable3D.Kind, cell: Vector2i, prompt_text: String, accent_color: Color) -> void:
	var node := RouteInteractable3D.new()
	node.position = cell_to_world(cell)
	node.kind = kind
	node.prompt_text = prompt_text
	node.accent_color = accent_color
	add_child(node)
	_interactables.append(node)


func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(CELL_SIZE, FLOOR_THICKNESS, CELL_SIZE)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = FLOOR_COLOR
	floor_mesh.material = floor_material
	var floor_transform := Transform3D(Basis(), Vector3(0, -FLOOR_THICKNESS / 2.0, 0))
	var floor_shape := BoxShape3D.new()
	floor_shape.size = floor_mesh.size
	library.create_item(ITEM_FLOOR)
	library.set_item_mesh(ITEM_FLOOR, floor_mesh)
	library.set_item_mesh_transform(ITEM_FLOOR, floor_transform)
	library.set_item_shapes(ITEM_FLOOR, [floor_shape, floor_transform])

	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE)
	var wall_material := StandardMaterial3D.new()
	wall_material.albedo_color = WALL_COLOR
	wall_mesh.material = wall_material
	var wall_transform := Transform3D(Basis(), Vector3(0, WALL_HEIGHT / 2.0, 0))
	var wall_shape := BoxShape3D.new()
	wall_shape.size = wall_mesh.size
	library.create_item(ITEM_WALL)
	library.set_item_mesh(ITEM_WALL, wall_mesh)
	library.set_item_mesh_transform(ITEM_WALL, wall_transform)
	library.set_item_shapes(ITEM_WALL, [wall_shape, wall_transform])

	return library
