class_name FacilityView
extends Node2D

## Renders the procedurally generated facility (facility_generator.gd) as a
## collidable TileMapLayer and spawns its relay/battery/safe-zone/lift
## interactables. Placeholder flat-color tiles stand in for real tile art —
## see MIGRATION.md for the open rendering-architecture question (the
## original's real art targets a custom fake-3D "2.5D diorama" renderer,
## not a flat top-down tilemap).

const TILE := GameConfig.TILE_SIZE
const FLOOR_COLOR := Color(0.025, 0.045, 0.055)
const WALL_COLOR := Color(0.18, 0.27, 0.30)
const GRID_LINE_COLOR := Color(0.10, 0.16, 0.19)

const ATLAS_FLOOR := Vector2i(0, 0)
const ATLAS_WALL := Vector2i(1, 0)

var generator: FacilityGenerator

var _tile_map: TileMapLayer
var _interactables: Array = []


func _ready() -> void:
	_tile_map = TileMapLayer.new()
	_tile_map.tile_set = _build_tile_set()
	add_child(_tile_map)


func generate_floor(seed_text: String) -> void:
	generator = FacilityGenerator.new(seed_text)
	_paint_grid()
	_spawn_interactables()


func facility_pixel_size() -> Vector2:
	return Vector2(generator.cols, generator.rows) * TILE


func cell_to_world(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) * TILE


func start_world_position() -> Vector2:
	return cell_to_world(generator.start)


func _paint_grid() -> void:
	_tile_map.clear()
	for y in generator.rows:
		for x in generator.cols:
			var atlas_coords := ATLAS_FLOOR if generator.grid[y][x] == 0 else ATLAS_WALL
			_tile_map.set_cell(Vector2i(x, y), 0, atlas_coords)


func _spawn_interactables() -> void:
	for node in _interactables:
		node.queue_free()
	_interactables.clear()

	for relay in generator.relays:
		_spawn_interactable(RouteInteractable.Kind.RELAY, Vector2i(relay["x"], relay["y"]), "RECOVER SIGNAL RELAY", Color(0.26, 0.88, 0.92))
	for battery in generator.batteries:
		_spawn_interactable(RouteInteractable.Kind.BATTERY, Vector2i(battery["x"], battery["y"]), "COLLECT BATTERY", Color(0.95, 0.82, 0.25))
	for zone in generator.safe_zones:
		_spawn_interactable(RouteInteractable.Kind.SAFE_ZONE, Vector2i(zone["x"], zone["y"]), "REST AT SAFE ZONE", Color(0.35, 0.95, 0.52))
	_spawn_interactable(RouteInteractable.Kind.LIFT, generator.exit_cell, "USE SERVICE LIFT", Color(0.76, 0.55, 0.96))


func _spawn_interactable(kind: RouteInteractable.Kind, cell: Vector2i, prompt_text: String, accent_color: Color) -> void:
	var node := RouteInteractable.new()
	node.position = cell_to_world(cell)
	node.kind = kind
	node.prompt_text = prompt_text
	node.accent_color = accent_color
	add_child(node)
	_interactables.append(node)


func _build_tile_set() -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE, TILE)
	tile_set.add_physics_layer()
	var physics_layer_index := 0

	var source := TileSetAtlasSource.new()
	source.texture = _build_tile_texture()
	source.texture_region_size = Vector2i(TILE, TILE)
	source.create_tile(ATLAS_FLOOR)
	source.create_tile(ATLAS_WALL)
	# The source must be attached to the TileSet before its TileData knows
	# about the TileSet's physics layers — add_collision_polygon() below
	# fails with an out-of-bounds physics layer if called any earlier.
	tile_set.add_source(source, 0)

	var wall_tile_data := source.get_tile_data(ATLAS_WALL, 0)
	var half := TILE / 2.0
	var polygon := PackedVector2Array([
		Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half),
	])
	wall_tile_data.add_collision_polygon(physics_layer_index)
	wall_tile_data.set_collision_polygon_points(physics_layer_index, 0, polygon)

	return tile_set


func _build_tile_texture() -> ImageTexture:
	var image := Image.create(TILE * 2, TILE, false, Image.FORMAT_RGBA8)
	image.fill_rect(Rect2i(0, 0, TILE, TILE), FLOOR_COLOR)
	for x in TILE:
		image.set_pixel(x, 0, GRID_LINE_COLOR)
	for y in TILE:
		image.set_pixel(0, y, GRID_LINE_COLOR)
	image.fill_rect(Rect2i(TILE, 0, TILE, TILE), WALL_COLOR)
	return ImageTexture.create_from_image(image)
