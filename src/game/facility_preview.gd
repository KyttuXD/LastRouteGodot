extends Node2D

## Temporary visual test room. This will be replaced by the deterministic facility
## generator and TileMapLayer renderer during the procedural-facility milestone.

const GRID_COLOR := Color(0.10, 0.16, 0.19, 0.42)
const WALL_COLOR := Color(0.18, 0.27, 0.30, 1.0)

const WALLS: Array[Rect2] = [
	Rect2(0, 0, 480, 8),
	Rect2(0, 262, 480, 8),
	Rect2(0, 0, 8, 270),
	Rect2(472, 0, 8, 270),
	Rect2(112, 48, 8, 78),
	Rect2(112, 158, 8, 64),
	Rect2(360, 48, 8, 64),
	Rect2(360, 144, 8, 78),
	Rect2(176, 79, 52, 8),
	Rect2(252, 79, 52, 8),
	Rect2(176, 183, 52, 8),
	Rect2(252, 183, 52, 8),
]


func _ready() -> void:
	for wall_rect in WALLS:
		_create_wall_collision(wall_rect)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GameConfig.INTERNAL_SIZE)), Color(0.025, 0.045, 0.055))

	for x in range(0, GameConfig.INTERNAL_SIZE.x + 1, GameConfig.TILE_SIZE):
		draw_line(Vector2(x, 0), Vector2(x, GameConfig.INTERNAL_SIZE.y), GRID_COLOR)
	for y in range(0, GameConfig.INTERNAL_SIZE.y + 1, GameConfig.TILE_SIZE):
		draw_line(Vector2(0, y), Vector2(GameConfig.INTERNAL_SIZE.x, y), GRID_COLOR)

	for wall_rect in WALLS:
		draw_rect(wall_rect, WALL_COLOR)

	draw_rect(Rect2(176, 79, 128, 112), Color(0.15, 0.24, 0.26, 0.55), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(12, 22), "GODOT MIGRATION TEST FLOOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.86, 0.82))


func _create_wall_collision(wall_rect: Rect2) -> void:
	var body := StaticBody2D.new()
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = wall_rect.size
	collision.shape = shape
	body.position = wall_rect.get_center()
	body.add_child(collision)
	add_child(body)
