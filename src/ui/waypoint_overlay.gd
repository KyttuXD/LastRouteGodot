class_name WaypointOverlay
extends Control

## The waypoint pins on the gameplay HUD: a diamond over each waypoint (visible through walls) with the distance in metres,
## and, when the pin is off screen or behind the player and guidance is not "off", an arrow on the screen edge pointing
## at it. Your own pin is amber, teammates' are tinted per player and labelled with their name. Nothing here touches the
## crosshair: pins keep a clear radius around the screen centre. Pure drawing; the run scene feeds it `set_pins`.

const PIN_BASE := 7.0
const EDGE_MARGIN := 26.0
const CROSSHAIR_CLEAR := 22.0
const TEAM_COLORS := [Color("5ad6c7"), Color("ff8fb3"), Color("a58bff"), Color("9be564"), Color("ffd166")]

var _pins: Array = []
var _camera: Camera3D
var _origin := Vector3.ZERO


func _ready() -> void:
	name = "WaypointOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	z_index = 5


## pins: Array of {"world": Vector3, "mine": bool, "name": String, "peer_id": int}.
func set_pins(pins: Array, camera: Camera3D, origin: Vector3) -> void:
	_pins = pins
	_camera = camera
	_origin = origin
	queue_redraw()


func pin_count() -> int:
	return _pins.size()


## What would be drawn for each pin right now (used by the validators): {"position", "edge", "distance", "mine"}.
func layout(viewport: Vector2) -> Array:
	var result := []
	if _camera == null:
		return result
	for pin_value in _pins:
		var pin: Dictionary = pin_value
		var world: Vector3 = pin["world"]
		var behind := _camera.is_position_behind(world)
		var projected := _camera.unproject_position(world)
		var marker := WaypointState.screen_marker(projected, behind, viewport, EDGE_MARGIN)
		result.append({"position": marker["position"], "edge": bool(marker["edge"]),
			"angle": float(marker["angle"]), "distance": _origin.distance_to(world),
			"mine": bool(pin.get("mine", true)), "name": String(pin.get("name", ""))})
	return result


func _draw() -> void:
	if _pins.is_empty() or _camera == null:
		return
	var viewport := get_viewport_rect().size
	var scale := Settings.waypoint_scale * clampf(viewport.y / 540.0, .8, 1.8)
	var opacity := Settings.waypoint_opacity
	var show_arrow: bool = Settings.waypoint_guidance != "off"
	var font := ThemeDB.fallback_font
	var index := 0
	for item in layout(viewport):
		var pin: Dictionary = item
		var color: Color = Palette.AMBER if bool(pin["mine"]) else TEAM_COLORS[index % TEAM_COLORS.size()]
		color.a = opacity
		index += 1
		var at: Vector2 = pin["position"]
		if bool(pin["edge"]):
			if not show_arrow:
				continue
			_draw_arrow(at, float(pin["angle"]), PIN_BASE * scale, color)
		else:
			# keep the crosshair clear: nudge a pin that sits on it
			var centre := viewport * .5
			if at.distance_to(centre) < CROSSHAIR_CLEAR * scale:
				at = centre + Vector2(0, -CROSSHAIR_CLEAR * scale)
			_draw_diamond(at, PIN_BASE * scale, color)
		var label := ""
		if Settings.waypoint_show_distance:
			label = "%d M" % roundi(float(pin["distance"]))
		if not bool(pin["mine"]) and not String(pin["name"]).is_empty():
			label = ("%s  %s" % [String(pin["name"]), label]).strip_edges()
		if not label.is_empty():
			var size := 8 * scale
			var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size)).x
			var text_at := at + Vector2(-width * .5, PIN_BASE * scale + size + 3.0)
			text_at.x = clampf(text_at.x, 4.0, viewport.x - width - 4.0)
			text_at.y = clampf(text_at.y, size + 2.0, viewport.y - 4.0)
			draw_string(font, text_at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), Color(0, 0, 0, opacity * .8))
			draw_string(font, text_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), color)


func _draw_diamond(at: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array([at + Vector2(0, -radius * 1.3), at + Vector2(radius, 0),
		at + Vector2(0, radius * 1.3), at + Vector2(-radius, 0)])
	draw_colored_polygon(points, Color(color.r, color.g, color.b, color.a * .35))
	draw_polyline(PackedVector2Array([points[0], points[1], points[2], points[3], points[0]]),
		color, 1.5)


func _draw_arrow(at: Vector2, angle: float, radius: float, color: Color) -> void:
	var forward := Vector2.from_angle(angle)
	var side := forward.orthogonal()
	var points := PackedVector2Array([at + forward * radius * 1.4,
		at - forward * radius * .8 + side * radius,
		at - forward * radius * .8 - side * radius])
	draw_colored_polygon(points, color)
