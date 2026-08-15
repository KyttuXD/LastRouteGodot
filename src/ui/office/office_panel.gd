class_name OfficePanel
extends SubViewport

## The desk console's display: a live floor plan of the facility, rendered
## under the physical button caps that sit on its glass.
##
## The console is a MAP, not a numbered keypad. Each cap stands where its room
## actually is, so choosing a camera is reading a plan of the building you can
## now walk through -- which is the whole reason the map was merged into one
## connected facility in the first place.
##
## Nothing here decides anything. It draws OfficeSimulation's state and the
## geometry in OfficeLayout (generated from the map that was built), and the
## caps' own positions are handed in by OfficeView3D, measured off the model.
## That is deliberate: a plan drawn from a second, hand-kept copy of the layout
## would drift from the buttons the moment a room moved, and a console whose
## map disagrees with its buttons is worse than no map at all.

const PANEL_SIZE := Vector2i(320, 206)

const BG := Color(0.021, 0.034, 0.039)
const ROOM_FILL := Color(0.055, 0.115, 0.125)
const ROOM_EDGE := Color(0.15, 0.32, 0.34)
const HALL_FILL := Color(0.042, 0.086, 0.094)
const OFFICE_FILL := Color(0.10, 0.20, 0.19)
const INK := Color(0.42, 0.70, 0.70)
const LIVE := Color(0.38, 1.0, 0.92)
const DEAD := Color(0.95, 0.28, 0.32)

## Room names as printed on the panel. The simulation's own labels are written
## for a full-width readout ("EAST PASSAGE"); at this size they crowd their
## neighbours, so the console gets the abbreviations a real one would carry.
const SHORT := {
	"cam1": "W HALL", "cam2": "E HALL", "cam3": "STORE", "cam4": "ARCHIVE",
	"cam5": "E PASS", "cam6": "W PASS", "cam7": "ELEC", "cam8": "BAY",
	"cam9": "ARCADE", "cam10": "DINE A", "cam11": "DINE B",
}

var simulation: OfficeSimulation
## Map metres -> texture pixels. Measured off the caps by OfficeView3D rather
## than assumed, so the drawn plan lands exactly under the physical buttons.
var to_tex := Transform2D()
## Camera id -> cap centre in texture pixels.
var cap_tex := {}
## Camera the player is currently pointing at, and where on the plan the ray
## lands, in map metres. An empty id means the pointer is off the console.
var hovered := ""
var pointer := Vector2.ZERO
var pointing := false

var _canvas: Control
var _font: Font
var _pulse := 0.0


func _ready() -> void:
	size = PANEL_SIZE
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	transparent_bg = false
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.size = Vector2(PANEL_SIZE)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_plan)
	add_child(_canvas)


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, 1.0)
	if _canvas != null:
		_canvas.queue_redraw()


## True once OfficeView3D has measured the console. Until then there is nothing
## meaningful to draw, and drawing with an identity transform would pile the
## whole facility into one corner.
func ready_to_draw() -> bool:
	return not cap_tex.is_empty()


func _draw_plan() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_SIZE)), BG)
	if not ready_to_draw():
		return

	var dark := simulation != null and (simulation.blackout_timer > 0.0
		or simulation.is_system_disabled("cameras"))
	var dim := 0.28 if dark else 1.0

	for corridor in OfficeLayout.CORRIDORS:
		_draw_run(corridor, HALL_FILL * dim)
	for room in OfficeLayout.ROOMS:
		var fill: Color = OFFICE_FILL if room["key"] == "Office" else ROOM_FILL
		if float(room["d"]) <= 3.5:
			fill = HALL_FILL
		_draw_room(room, fill * dim, ROOM_EDGE * dim)

	_draw_labels(dim)
	_draw_markers(dim)

	if dark:
		var text := "SIGNAL LOST" if simulation.blackout_timer > 0.0 else "CAMS OFFLINE"
		var w := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
		_canvas.draw_string(_font, Vector2((PANEL_SIZE.x - w) * 0.5, PANEL_SIZE.y * 0.5),
			text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, DEAD)
	elif pointing:
		_draw_pointer()


func _draw_room(room: Dictionary, fill: Color, edge: Color) -> void:
	var half := Vector2(float(room["w"]), float(room["d"])) * 0.5
	var a: Vector2 = to_tex * (Vector2(float(room["x"]), float(room["z"])) - half)
	var b: Vector2 = to_tex * (Vector2(float(room["x"]), float(room["z"])) + half)
	var rect := Rect2(a, b - a).abs()
	_canvas.draw_rect(rect, fill)
	_canvas.draw_rect(rect, edge, false, 1.0)


func _draw_run(corridor: Dictionary, fill: Color) -> void:
	var a := Vector2(float(corridor["x0"]), float(corridor["z0"]))
	var b := Vector2(float(corridor["x1"]), float(corridor["z1"]))
	# Corridors are axis-aligned, so half the width on the perpendicular axis
	# turns the segment back into the rectangle it is in the world.
	var pad := Vector2(float(corridor["w"]), float(corridor["w"])) * 0.5
	if absf(a.x - b.x) > absf(a.y - b.y):
		pad.x = 0.0
	else:
		pad.y = 0.0
	var p: Vector2 = to_tex * (a.min(b) - pad)
	var q: Vector2 = to_tex * (a.max(b) + pad)
	_canvas.draw_rect(Rect2(p, q - p).abs(), fill)


## Greedy placement: each label takes the first free side of its own cap.
## Hand-tuned offsets would read better for exactly one floor plan and then be
## wrong the next time a room moves, which is the failure this whole file is
## arranged to avoid.
func _draw_labels(dim: float) -> void:
	const SIZE := 8
	var taken: Array[Rect2] = []
	for cam in OfficeConfig.CAMERAS:
		if cap_tex.has(cam):
			taken.append(Rect2(cap_tex[cam] - Vector2(8, 8), Vector2(16, 16)))
	var bounds := Rect2(Vector2(2, 2), Vector2(PANEL_SIZE) - Vector2(4, 4))
	for cam in OfficeConfig.CAMERAS:
		if not cap_tex.has(cam):
			continue
		var text: String = SHORT.get(cam, cam.to_upper())
		var span := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE)
		var centre: Vector2 = cap_tex[cam]
		for offset in [Vector2(11, -span.y * 0.5), Vector2(-11 - span.x, -span.y * 0.5),
				Vector2(-span.x * 0.5, 10), Vector2(-span.x * 0.5, -10 - span.y)]:
			var rect := Rect2(centre + offset, span)
			if not bounds.encloses(rect):
				continue
			var clear := true
			for other in taken:
				if other.intersects(rect):
					clear = false
					break
			if not clear:
				continue
			var tint := INK
			if simulation != null and simulation.current_camera == cam:
				tint = LIVE
			_canvas.draw_string(_font, rect.position + Vector2(0, span.y * 0.78),
				text, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, tint * dim)
			taken.append(rect)
			break


## A socket ring under every cap, so a button reads as seated in the panel
## rather than floating on it, plus the alarm states that ring has to carry.
func _draw_markers(dim: float) -> void:
	for cam in OfficeConfig.CAMERAS:
		if not cap_tex.has(cam):
			continue
		var centre: Vector2 = cap_tex[cam]
		_canvas.draw_circle(centre, 9.0, Color(0.10, 0.17, 0.18) * dim)
		var ring := ROOM_EDGE
		var width := 1.0
		if simulation != null:
			if simulation.corrupted_cameras.has(cam):
				ring = DEAD
				width = 2.0
			elif simulation.current_camera == cam:
				ring = LIVE
				width = 2.0
		if cam == hovered:
			ring = ring.lerp(Color.WHITE, 0.55)
			width = maxf(width, 2.0)
		_canvas.draw_arc(centre, 9.0, 0.0, TAU, 20, ring * dim, width)

		# A signal on a feed gets an outer ring in that threat's own colour,
		# pulsing so it is caught out of the corner of the eye.
		if simulation == null:
			continue
		var seen: Array = simulation.camera_signals(cam)
		if seen.is_empty():
			continue
		var colour: Color = simulation.threats[seen[0]]["color"]
		var beat := 0.55 + 0.45 * sin(_pulse * TAU)
		_canvas.draw_arc(centre, 13.0, 0.0, TAU, 24, colour * beat, 2.0)


func _draw_pointer() -> void:
	var p: Vector2 = to_tex * pointer
	var tint := LIVE if hovered != "" else INK
	_canvas.draw_line(p - Vector2(5, 0), p + Vector2(5, 0), tint, 1.0)
	_canvas.draw_line(p - Vector2(0, 5), p + Vector2(0, 5), tint, 1.0)
