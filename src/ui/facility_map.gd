class_name FacilityMap
extends Control

## The full-screen facility map — the original's "radar".
##
## It replaces a placeholder that was a coloured rectangle with the words
## FACILITY MAP on it. That was harmless while nothing depended on it, and stops
## being harmless with Porcelle on the floor: she is invisible in the room and
## visible ONLY here, so this panel is the whole of her counterplay. The cost
## the original charges for using it is exactly what makes her fair — reading
## the map means giving up your view of the room you are standing in.
##
## Everything drawn is passed in rather than looked up, so this stays a widget:
## it never reaches into the world for a hunter or a player.

const WALL := 0

var generator: FacilityGenerator
var player_at := Vector2.ZERO
var player_facing := Vector2(0, 1)
## [{ "at": Vector2, "name": String, "active": bool }]
var hunters: Array = []


func show_state(from: FacilityGenerator, at: Vector2, facing: Vector2, marks: Array) -> void:
	generator = from
	player_at = at
	player_facing = facing
	hunters = marks
	queue_redraw()


func _draw() -> void:
	if generator == null or generator.cols <= 0:
		return
	var cell := minf(size.x / float(generator.cols), size.y / float(generator.rows))
	var origin := (size - Vector2(generator.cols, generator.rows) * cell) * 0.5

	# Floor first as one rect, then walls over it: two thousand cells of
	# per-tile floor drawing is most of the frame, and the floor is one colour.
	draw_rect(Rect2(origin, Vector2(generator.cols, generator.rows) * cell),
		Palette.BACKDROP)
	var wall_size := Vector2(cell, cell)
	for y in generator.rows:
		var row: Array = generator.grid[y]
		for x in generator.cols:
			if row[x] != WALL:
				continue
			draw_rect(Rect2(origin + Vector2(x, y) * cell, wall_size), Palette.PANEL)

	_dots(origin, cell, generator.relays, Palette.AMBER, 0.34)
	_dots(origin, cell, generator.batteries, Color(0.95, 0.82, 0.25), 0.26)
	if generator.exit_cell.x >= 0:
		draw_circle(origin + (Vector2(generator.exit_cell) + Vector2(0.5, 0.5)) * cell,
			cell * 0.4, Color(0.76, 0.55, 0.96))

	# Hunters over objectives, because a hunter standing on a relay is the thing
	# you most need to see.
	for mark in hunters:
		if not bool(mark.get("active", true)):
			continue
		var at: Vector2 = origin + (mark["at"] as Vector2) * cell
		draw_circle(at, cell * 0.55, Palette.CRIMSON)
		var label := String(mark.get("name", "?")).substr(0, 1).to_upper()
		var font := ThemeDB.fallback_font
		var glyph := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		draw_string(font, at - glyph * 0.5 + Vector2(0, glyph.y * 0.5), label,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.BACKDROP)

	_draw_player(origin, cell)


func _dots(origin: Vector2, cell: float, entries: Array, tint: Color, scale: float) -> void:
	for entry in entries:
		if entry.get("collected", false):
			continue
		draw_circle(origin + (Vector2(entry["x"], entry["y"]) + Vector2(0.5, 0.5)) * cell,
			cell * scale, tint)


## A wedge rather than a dot, because on a map of a maze "which way am I facing"
## is most of what you came here to find out.
func _draw_player(origin: Vector2, cell: float) -> void:
	var at := origin + player_at * cell
	var forward := player_facing.normalized() if player_facing.length() > 0.01 else Vector2(0, 1)
	var side := Vector2(-forward.y, forward.x)
	var reach := cell * 0.95
	draw_colored_polygon(PackedVector2Array([
		at + forward * reach,
		at - forward * reach * 0.5 + side * reach * 0.6,
		at - forward * reach * 0.5 - side * reach * 0.6,
	]), Palette.INK)
