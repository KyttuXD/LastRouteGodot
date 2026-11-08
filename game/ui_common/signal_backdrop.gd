class_name SignalBackdrop
extends Control

## Shared title/staging backdrop from the original web build.
##
## The checker pattern, scanlines, vignette and double inset frame used to be
## CSS layers around the 480x270 canvas. Drawing them here keeps the same look
## on every native target without baking a resolution-specific screenshot into
## the game. The two perimeter lines are deliberately separate: the darker
## outside rail and slightly brighter inside rail are part of the game's frame.

@export var pattern_strength := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var bounds := Rect2(Vector2.ZERO, size)
	draw_rect(bounds, Palette.BACKDROP)
	_draw_warm_field(bounds)
	_draw_checker_archive(bounds)
	_draw_scanlines(bounds)
	_draw_dual_frame(bounds)


func _draw_warm_field(bounds: Rect2) -> void:
	# A cheap CanvasItem approximation of the web build's left-to-right overlay
	# and radial violet glow. The strips are intentionally subtle and never
	# obscure controls placed above this node.
	# half the strip/glow draws — look stays soft, menus repaint cheaper.
	const STRIPS := 8
	for index in STRIPS:
		var ratio := float(index) / float(STRIPS - 1)
		var strip := Rect2(bounds.size.x * ratio, 0.0,
			bounds.size.x / float(STRIPS) + 1.0, bounds.size.y)
		var tint := Color(0.027 + ratio * 0.016, 0.014, 0.025 + ratio * 0.018,
			0.42 - ratio * 0.16)
		draw_rect(strip, tint)
	for radius in range(90, 8, -12):
		var alpha := 0.0024 * pattern_strength * (1.0 - float(radius) / 100.0)
		draw_circle(Vector2(bounds.size.x * 0.74, bounds.size.y * 0.38),
			float(radius), Color(0.45, 0.18, 0.34, alpha))


func _draw_checker_archive(bounds: Rect2) -> void:
	# larger tiles (~40% fewer diamonds) on menu/hub resize redraws.
	var tile := maxf(28.0, minf(bounds.size.x, bounds.size.y) * 0.13)
	var start_x := bounds.size.x * 0.24
	var y := -tile
	var row := 0
	while y < bounds.size.y + tile:
		var x := start_x + (-tile if row % 2 else 0.0)
		while x < bounds.size.x + tile:
			var centre := Vector2(x, y)
			var diamond := PackedVector2Array([
				centre + Vector2(0.0, -tile * 0.48),
				centre + Vector2(tile * 0.7, 0.0),
				centre + Vector2(0.0, tile * 0.48),
				centre + Vector2(-tile * 0.7, 0.0),
			])
			var fade := clampf((x - start_x) / maxf(1.0, bounds.size.x - start_x),
				0.0, 1.0)
			var alpha := (0.012 + fade * 0.018) * pattern_strength
			draw_colored_polygon(diamond, Color(0.56, 0.43, 0.49, alpha))
			x += tile * 1.42
		y += tile * 0.98
		row += 1


func _draw_scanlines(bounds: Rect2) -> void:
	# 8px pitch (~half the lines) + 56px grid — same look, fewer strokes.
	var y := 1.0
	while y < bounds.size.y:
		draw_line(Vector2(0.0, y), Vector2(bounds.size.x, y),
			Color(0.82, 0.68, 0.76, 0.022), 1.0)
		y += 8.0
	# A faint signal grid sits behind the checker floor in the web version.
	var x := 56.0
	while x < bounds.size.x:
		draw_line(Vector2(x, 0.0), Vector2(x, bounds.size.y),
			Color(1.0, 1.0, 1.0, 0.008), 1.0)
		x += 56.0


func _draw_dual_frame(bounds: Rect2) -> void:
	if bounds.size.x < 20.0 or bounds.size.y < 20.0:
		return
	# Keep the rails inside the canvas so neither one is clipped by a window or
	# by Web export scaling. Their spacing mirrors the CSS frame + box shadows.
	draw_rect(Rect2(Vector2(5.0, 4.0), bounds.size - Vector2(10.0, 8.0)),
		Color(0.16, 0.12, 0.16, 0.94), false, 1.0)
	draw_rect(Rect2(Vector2(7.0, 6.0), bounds.size - Vector2(14.0, 12.0)),
		Color(0.28, 0.22, 0.28, 0.86), false, 1.0)
