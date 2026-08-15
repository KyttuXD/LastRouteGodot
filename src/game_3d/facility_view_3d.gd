class_name FacilityView3D
extends Node3D

## 3D counterpart to src/game/facility_view.gd. Renders the SAME
## facility_generator.gd grid data (unchanged, engine-agnostic) via a
## GridMap — the 3D equivalent of the 2D renderer's TileMapLayer — with
## physics collision. Floor/wall visuals and collision come from
## art/props-3d/environment/ via ModelSlot, not hardcoded geometry — see
## art/props-3d/README.md for the scale/pivot convention this mirrors:
## 1 grid cell = 1 meter, ground plane is XZ (Godot is Y-up).

const CELL_SIZE := 1.0
const FLOOR_SCENE := "res://art/props-3d/environment/floor_tile.tscn"
const WALL_SCENE := "res://art/props-3d/environment/wall_block.tscn"

const ITEM_FLOOR := 0
const ITEM_WALL := 1

var generator: FacilityGenerator

var _grid_map: GridMap
var _interactables: Array = []
## The floor's single heater station, read by Wynelle's gimmick each frame.
var heater_station: RouteInteractable3D


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
		_spawn_interactable(RouteInteractable3D.Kind.RELAY, Vector2i(relay["x"], relay["y"]), "RECOVER SIGNAL RELAY")
	for battery in generator.batteries:
		_spawn_interactable(RouteInteractable3D.Kind.BATTERY, Vector2i(battery["x"], battery["y"]), "COLLECT BATTERY")
	for zone in generator.safe_zones:
		_spawn_interactable(RouteInteractable3D.Kind.SAFE_ZONE, Vector2i(zone["x"], zone["y"]), "REST AT SAFE ZONE")
	_spawn_interactable(RouteInteractable3D.Kind.LIFT, generator.exit_cell, "USE SERVICE LIFT")
	# One heater station per floor — Wynelle's counterplay. Placed at the
	# facility's start so it's findable without hunting for it, matching the
	# original's "single station, known location" role.
	heater_station = _spawn_interactable(RouteInteractable3D.Kind.HEATER_STATION, generator.start, "USE HEATER STATION")


func _spawn_interactable(kind: RouteInteractable3D.Kind, cell: Vector2i, prompt_text: String) -> RouteInteractable3D:
	var node := RouteInteractable3D.new()
	node.position = cell_to_world(cell)
	node.kind = kind
	node.prompt_text = prompt_text
	node.source_cell = cell
	node.generator = generator
	add_child(node)
	_interactables.append(node)
	return node


func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	_add_item(library, ITEM_FLOOR, FLOOR_SCENE)
	_add_item(library, ITEM_WALL, WALL_SCENE)
	return library


static func _add_item(library: MeshLibrary, id: int, scene_path: String) -> void:
	var loaded := ModelSlot.load_gridmap_item(scene_path)
	library.create_item(id)
	if loaded["mesh"]:
		library.set_item_mesh(id, loaded["mesh"])
		library.set_item_mesh_transform(id, loaded["mesh_transform"])
	if loaded["shape"]:
		library.set_item_shapes(id, [loaded["shape"], loaded["shape_transform"]])
