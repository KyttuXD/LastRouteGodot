class_name OfficePanel
extends SubViewport

## The desk console's screen: which camera is live, where it is in the
## building, and what the two buttons below will switch to.
##
## The console used to BE the map -- eleven caps laid out as a floor plan, one
## per camera. It read well and aimed badly. Seated, the cursor swings the head
## as well as the aiming ray, so the whole console is only about 64 x 55 pixels
## of cursor travel at this project's 480 x 270 base resolution, and eleven
## buttons inside that are dots you hunt for. PREV and NEXT are 36 cm slabs
## instead, and the plan moved here, where it costs nothing to read.
##
## Nothing here decides anything. It draws OfficeSimulation's state over the
## geometry in OfficeLayout, which is generated from the map that was actually
## built -- so the plan cannot show a building the facility no longer is.

## Matches the screen's 0.796 x 0.354 m face, so the plan is not stretched.
const PANEL_SIZE := Vector2i(320, 142)
## The square the floor plan is drawn in, with the two text columns either
## side lining up over the buttons they describe.
const PLAN_RECT := Rect2(103, 24, 114, 114)
const COLUMN := 95.0

const BG := Color(0.021, 0.034, 0.039)
const ROOM_FILL := Color(0.055, 0.115, 0.125)
const ROOM_EDGE := Color(0.15, 0.32, 0.34)
const HALL_FILL := Color(0.042, 0.086, 0.094)
const OFFICE_FILL := Color(0.10, 0.20, 0.19)
const INK := Color(0.42, 0.70, 0.70)
const FAINT := Color(0.24, 0.40, 0.42)
const LIVE := Color(0.38, 1.0, 0.92)
const DEAD := Color(0.95, 0.28, 0.32)

## Room names as printed on the console. The simulation's own labels are
## written for a full-width readout ("EAST PASSAGE"); at this size they crowd
## their column, so the console gets the abbreviations a real one would carry.
const SHORT := {
	"cam1": "W HALL", "cam2": "E HALL", "cam3": "STORE", "cam4": "ARCHIVE",
	"cam5": "E PASS", "cam6": "W PASS", "cam7": "ELEC", "cam8": "BAY",
	"cam9": "ARCADE", "cam10": "DINE A", "cam11": "DINE B",
}

var simulation: OfficeSimulation
## Which physical button the player is pointing at: "prev", "next", or "".
var hovered := ""
## The desk control under the pointer, named and with its current state. The
## keys themselves are too small to print on, so the screen above them says
## what the hand is about to work.
var control_hint := ""

var _canvas: Control
var _font: Font
var _pulse := 0.0
## Map metres -> plan pixels. Uniform scale, so the facility keeps its shape.
var _to_plan := Transform2D()


func _ready() -> void:
	size = PANEL_SIZE
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	transparent_bg = false
	_font = ThemeDB.fallback_font
	_to_plan = _plan_transform()
	_canvas = Control.new()
	_canvas.size = Vector2(PANEL_SIZE)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_console)
	add_child(_canvas)


func _process(delta: float) -> void:
	_pulse = fmod(_pulse + delta, 1.0)
	if _canvas != null:
		_canvas.queue_redraw()


## Fit the facility into PLAN_RECT at ONE scale for both axes. Stretching each
## axis to fill would square up a building that is not square and make the plan
## a worse guide to a place the player now walks around in.
func _plan_transform() -> Transform2D:
	var span := Vector2(
		OfficeLayout.BOUNDS["x1"] - OfficeLayout.BOUNDS["x0"],
		OfficeLayout.BOUNDS["z1"] - OfficeLayout.BOUNDS["z0"])
	var scale: float = minf(PLAN_RECT.size.x / span.x, PLAN_RECT.size.y / span.y)
	var origin := PLAN_RECT.position + (PLAN_RECT.size - span * scale) * 0.5
	return Transform2D(Vector2(scale, 0.0), Vector2(0.0, scale), origin
		- Vector2(OfficeLayout.BOUNDS["x0"], OfficeLayout.BOUNDS["z0"]) * scale)


## The camera `step` places away from the live one, wrapping. The buttons and
## the labels above them read from the same function, so a label can never
## promise a camera the button does not go to.
func neighbour(step: int) -> String:
	var cameras: Array = OfficeConfig.CAMERAS
	if simulation == null:
		return String(cameras[0])
	var index: int = cameras.find(simulation.current_camera)
	return String(cameras[posmod(maxi(index, 0) + step, cameras.size())])


func _draw_console() -> void:
	_canvas.draw_rect(Rect2(Vector2.ZERO, Vector2(PANEL_SIZE)), BG)
	if simulation == null:
		return
	var offline := simulation.blackout_timer > 0.0 \
		or simulation.is_system_disabled("cameras")
	_draw_header(offline)
	_draw_plan(offline)
	_draw_column("prev", -1, Rect2(4, 24, COLUMN, 114), HORIZONTAL_ALIGNMENT_LEFT, offline)
	_draw_column("next", 1, Rect2(221, 24, COLUMN, 114), HORIZONTAL_ALIGNMENT_RIGHT, offline)
	_draw_control_hint()


## A strip across the foot of the screen naming the desk key being pointed at.
## Drawn over everything else because it is momentary and only appears when the
## pointer is actually on a control.
func _draw_control_hint() -> void:
	if control_hint.is_empty():
		return
	var band := Rect2(0, PANEL_SIZE.y - 15, PANEL_SIZE.x, 15)
	_canvas.draw_rect(band, Palette.INSET)
	_canvas.draw_line(band.position, band.position + Vector2(band.size.x, 0),
		Palette.AMBER, 1.0)
	var width := _font.get_string_size(control_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x
	_canvas.draw_string(_font, Vector2((PANEL_SIZE.x - width) * 0.5, PANEL_SIZE.y - 4),
		control_hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Palette.AMBER)


func _draw_header(offline: bool) -> void:
	var cam: String = simulation.current_camera
	var view = simulation.camera_view(cam)
	var tint := LIVE
	var text := "CAM %s   %s" % [cam.substr(3), view["room"] if view else "?"]
	if offline:
		tint = DEAD
		text = "SIGNAL LOST" if simulation.blackout_timer > 0.0 else "CAMS OFFLINE"
	elif simulation.corrupted_cameras.has(cam):
		tint = DEAD
		text = "CAM %s   FEED CORRUPTED" % cam.substr(3)
	var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	_canvas.draw_string(_font, Vector2((PANEL_SIZE.x - width) * 0.5, 17),
		text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, tint)


func _draw_plan(offline: bool) -> void:
	var dim := 0.3 if offline else 1.0
	for corridor in OfficeLayout.CORRIDORS:
		_draw_run(corridor, HALL_FILL * dim)
	for room in OfficeLayout.ROOMS:
		var fill: Color = OFFICE_FILL if room["key"] == "Office" else ROOM_FILL
		if float(room["d"]) <= 3.5:
			fill = HALL_FILL
		var half := Vector2(float(room["w"]), float(room["d"])) * 0.5
		var centre := Vector2(float(room["x"]), float(room["z"]))
		var a: Vector2 = _to_plan * (centre - half)
		var b: Vector2 = _to_plan * (centre + half)
		var rect := Rect2(a, b - a).abs()
		_canvas.draw_rect(rect, fill * dim)
		_canvas.draw_rect(rect, ROOM_EDGE * dim, false, 1.0)

	for cam in OfficeConfig.CAMERAS:
		if not OfficeLayout.CAMERA_XZ.has(cam):
			continue
		var at: Vector2 = _to_plan * (OfficeLayout.CAMERA_XZ[cam] as Vector2)
		var live: bool = cam == simulation.current_camera
		var tint := FAINT
		if simulation.corrupted_cameras.has(cam):
			tint = DEAD
		if live:
			tint = LIVE
		_canvas.draw_circle(at, 3.0 if live else 2.0, tint * dim)
		if live and not offline:
			# A ring the eye lands on immediately, so the plan answers "where
			# am I looking" without being read.
			_canvas.draw_arc(at, 6.0, 0.0, TAU, 18, LIVE, 1.0)
		if offline:
			continue
		var seen: Array = simulation.camera_signals(cam)
		if seen.is_empty():
			continue
		var colour: Color = simulation.threats[seen[0]]["color"]
		_canvas.draw_arc(at, 8.0, 0.0, TAU, 20,
			colour * (0.55 + 0.45 * sin(_pulse * TAU)), 2.0)


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
	var p: Vector2 = _to_plan * (a.min(b) - pad)
	var q: Vector2 = _to_plan * (a.max(b) + pad)
	_canvas.draw_rect(Rect2(p, q - p).abs(), fill)


## Each column sits directly above the button it describes and names the camera
## that button switches to. Cycling blind through eleven feeds would be far
## worse than the eleven small caps this replaced.
func _draw_column(key: String, step: int, rect: Rect2,
		align: HorizontalAlignment, offline: bool) -> void:
	var cam := neighbour(step)
	var view = simulation.camera_view(cam)
	var lit := key == hovered and not offline
	var heading := "< PREV" if step < 0 else "NEXT >"
	var tint := FAINT if offline else (Color.WHITE if lit else INK)

	_write(rect.position + Vector2(0, 12), rect.size.x, heading, 9, align,
		tint if lit else FAINT)
	if offline:
		return
	_write(rect.position + Vector2(0, 38), rect.size.x, "CAM %s" % cam.substr(3),
		13, align, tint)
	_write(rect.position + Vector2(0, 54), rect.size.x,
		String(SHORT.get(cam, "")), 9, align, tint.darkened(0.25))

	# What is waiting on that feed, so the button is a decision rather than a
	# shuffle. Corrupted first: it is the reason a feed shows nothing.
	var note := ""
	var note_tint := FAINT
	if simulation.corrupted_cameras.has(cam):
		note = "CORRUPTED"
		note_tint = DEAD
	else:
		var seen: Array = simulation.camera_signals(cam)
		if not seen.is_empty():
			note = String(simulation.threats[seen[0]]["label"])
			note_tint = simulation.threats[seen[0]]["color"]
	if note != "":
		_write(rect.position + Vector2(0, 76), rect.size.x, note, 9, align, note_tint)


func _write(at: Vector2, width: float, text: String, size: int,
		align: HorizontalAlignment, tint: Color) -> void:
	var span := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var x := at.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = at.x + width - span
	_canvas.draw_string(_font, Vector2(x, at.y), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size, tint)
