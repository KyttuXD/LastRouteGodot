extends Node2D

## Temporary visual test room. This will be replaced by the deterministic facility
## generator and TileMapLayer renderer during the procedural-facility milestone.

const GRID_COLOR := Color(0.10, 0.16, 0.19, 0.42)
const WALL_COLOR := Color(0.18, 0.27, 0.30, 1.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(GameConfig.INTERNAL_SIZE)), Color(0.025, 0.045, 0.055))

	for x in range(0, GameConfig.INTERNAL_SIZE.x + 1, GameConfig.TILE_SIZE):
		draw_line(Vector2(x, 0), Vector2(x, GameConfig.INTERNAL_SIZE.y), GRID_COLOR)
	for y in range(0, GameConfig.INTERNAL_SIZE.y + 1, GameConfig.TILE_SIZE):
		draw_line(Vector2(0, y), Vector2(GameConfig.INTERNAL_SIZE.x, y), GRID_COLOR)

	var bounds := Rect2(4, 4, GameConfig.INTERNAL_SIZE.x - 8, GameConfig.INTERNAL_SIZE.y - 8)
	draw_rect(bounds, WALL_COLOR, false, 4.0)
	draw_rect(Rect2(176, 79, 128, 112), Color(0.15, 0.24, 0.26, 0.55), false, 2.0)
	draw_string(ThemeDB.fallback_font, Vector2(12, 22), "GODOT MIGRATION TEST FLOOR", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.55, 0.86, 0.82))

