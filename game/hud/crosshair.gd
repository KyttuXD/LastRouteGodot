class_name Crosshair
extends Control

## A centre reticle, drawn only while the mouse is actually aiming the view.
##
## Both 3D modes point at things with the middle of the screen -- the maze
## interacts with whatever the camera faces, and the office console is worked
## with a ray from the standing player's centre. Without a mark there, "look at
## it and press E" is guesswork.
##
## It follows MouseLock rather than a flag of its own: if the cursor is free,
## the pointer IS the pointer and a second one in the middle of the screen is
## just clutter. So it disappears at the desk, under the tablet, and whenever
## the pause menu is up, without anyone telling it to.

## Half-length of each arm and the gap left open at the centre, in design
## pixels. Small: this is a 480 x 270 canvas, and a reticle big enough to
## notice at 1080p would be a plus sign across the middle of the screen.
const ARMS: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]
const ARM := 3.0
const GAP := 2.0
const THICKNESS := 1.0

@export var tint := Palette.INK
@export var shadow := Color(0.0, 0.0, 0.0, 0.55)

var _shown := false


func _ready() -> void:
	# Visible while the tree is paused would mean a reticle over the pause
	# menu, but MouseLock frees the cursor there, so this follows along.
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	var wanted := MouseLock.is_captured()
	if wanted != _shown:
		_shown = wanted
		queue_redraw()


func _draw() -> void:
	if not _shown:
		return
	var centre := (size * 0.5).round()
	for arm in ARMS:
		var from: Vector2 = centre + arm * GAP
		var to: Vector2 = centre + arm * (GAP + ARM)
		# A dark pass one pixel down and right keeps the reticle readable on a
		# white wall as well as in a dark corridor.
		draw_line(from + Vector2.ONE, to + Vector2.ONE, shadow, THICKNESS)
		draw_line(from, to, tint, THICKNESS)
	draw_rect(Rect2(centre - Vector2(0.5, 0.5), Vector2.ONE), tint)
