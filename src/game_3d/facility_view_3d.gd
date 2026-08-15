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

## Corridor height, and the thickness of the slabs that cap it. 3 m matches the
## office rooms, so a player moving between modes reads the same scale.
const WALL_HEIGHT := 3.0
const SLAB := 0.1

const ITEM_FLOOR := 0
const ITEM_WALL := 1
const ITEM_CEILING := 2

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
			var open: bool = generator.grid[y][x] == 0
			_grid_map.set_cell_item(Vector3i(x, 0, y),
				ITEM_FLOOR if open else ITEM_WALL)
			# The maze had no lid at all, so corridors opened onto the void and
			# lost every bounce of light. Only open cells need one -- a wall
			# already fills its cell to the ceiling. A GridMap cell holds one
			# item, so the lid lives a layer up.
			if open:
				_grid_map.set_cell_item(Vector3i(x, 1, y), ITEM_CEILING)


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
	# One heater station per floor — Wynelle's counterplay. NEAR the start so
	# it's findable without hunting for it, matching the original's "single
	# station, known location" role, but not ON it: placed on the spawn cell
	# it was the first thing the player saw, at arm's length, blocking the way
	# out of their own spawn.
	heater_station = _spawn_interactable(RouteInteractable3D.Kind.HEATER_STATION,
		_near_start(), "USE HEATER STATION")


## An open cell next to the spawn, or the spawn itself if it is somehow walled
## in. Prefers the cell furthest from the player's facing so the station is
## behind them rather than in the doorway they are about to walk through.
func _near_start() -> Vector2i:
	var taken := {}
	for relay in generator.relays:
		taken[Vector2i(relay["x"], relay["y"])] = true
	for battery in generator.batteries:
		taken[Vector2i(battery["x"], battery["y"])] = true
	for zone in generator.safe_zones:
		taken[Vector2i(zone["x"], zone["y"])] = true
	taken[generator.exit_cell] = true
	for step in [Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1)]:
		var cell: Vector2i = generator.start + step
		if cell.x < 0 or cell.y < 0 or cell.x >= generator.cols or cell.y >= generator.rows:
			continue
		if generator.grid[cell.y][cell.x] != 0 or taken.has(cell):
			continue
		return cell
	return generator.start


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


## Floor, wall and ceiling as plain boxes.
##
## The wall used to be the imported wall_block model dropped straight into the
## GridMap, and it landed at the wrong orientation -- a cell is a cube and the
## model is not, so every wall carried whatever rotation the export happened to
## bake in. Chasing that per-cell is a losing game when the thing being drawn is
## a 1 m cube: a box is unambiguously square to the grid and cannot be rotated
## wrongly, which is the whole point.
##
## The art is not thrown away. Each box takes the imported model's own material
## and samples the same patch of its atlas, so the pixel art survives -- see
## _cube_material for why the UVs have to be remapped to keep it.
func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	var floor_material := _cube_material(FLOOR_SCENE)
	var wall_material := _cube_material(WALL_SCENE)
	# A cell's origin is centred in X and Z but sits at its FLOOR in Y, which
	# is why every offset below is measured up from zero rather than from a
	# centre.
	_add_box(library, ITEM_FLOOR, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
		Vector3(0.0, -SLAB * 0.5, 0.0), floor_material, false)
	_add_box(library, ITEM_WALL, Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE),
		Vector3(0.0, WALL_HEIGHT * 0.5, 0.0), wall_material, true)
	# Painted a layer up, so subtract that layer back out of the offset.
	_add_box(library, ITEM_CEILING, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
		Vector3(0.0, WALL_HEIGHT - CELL_SIZE - SLAB * 0.5, 0.0),
		floor_material, false)
	return library


static func _add_box(library: MeshLibrary, id: int, size: Vector3,
		offset: Vector3, material: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	if material != null:
		mesh.material = material
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var placement := Transform3D(Basis.IDENTITY, offset)
	library.set_item_mesh_transform(id, placement)
	# Floors and ceilings are scenery; only walls need to stop anyone. Giving
	# the lid a collider would also give the player a head to bump.
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, placement])


## The imported model's material, retargeted at the patch of its atlas that
## model actually used.
##
## A BoxMesh generates its own 0..1 UVs, so dropping an atlas material onto one
## stretches the WHOLE sheet across every face -- several unrelated materials at
## once. Scaling by the inverse of the source mesh's UV bounds points the box at
## the same patch the model was drawn with. Same trick as the office screens,
## for the same reason.
static func _cube_material(scene_path: String) -> Material:
	var loaded := ModelSlot.load_gridmap_item(scene_path)
	var mesh: Mesh = loaded["mesh"]
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var source := mesh.surface_get_material(0)
	if not source is StandardMaterial3D:
		return source
	var material: StandardMaterial3D = (source as StandardMaterial3D).duplicate()
	var uvs: PackedVector2Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	if uvs.is_empty():
		return material
	var lo := uvs[0]
	var hi := uvs[0]
	for uv in uvs:
		lo = lo.min(uv)
		hi = hi.max(uv)
	var span := hi - lo
	if span.x <= 0.0 or span.y <= 0.0:
		return material
	material.uv1_scale = Vector3(span.x, span.y, 1.0)
	material.uv1_offset = Vector3(lo.x, lo.y, 0.0)
	return material
