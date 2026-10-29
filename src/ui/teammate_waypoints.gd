class_name TeammateWaypoints
extends Control

## On-screen markers for co-op teammates in view: name and distance in metres at their world position. Teammates off screen or behind
## you get no marker here; the minimap shows them as a small arrow on its border (FacilityMap). Positions come from the room's replicated player states (RemotePlayers
## .remote_player_marks), never from loaded player nodes, so they work beyond chunk and stream range. Another floor gets an up/down
## triangle with the level ("+1"); a teammate quiet for more than STALE_MS is dimmed; DOWN / CAUGHT states are labelled.
## `update_marks(camera, viewer_position, marks)` once per frame; `layout_for()` is the pure projection, testable without a camera.

const STALE_MS := 3000
const EDGE_MARGIN := 14.0
const HEAD_HEIGHT := 1.7
const LEVEL_HEIGHT := 4.0

var camera: Camera3D
var _entries: Array = []


func _init() -> void:
	name = "TeammateWaypoints"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func entry_count() -> int:
	return _entries.size()


func entries() -> Array:
	return _entries


const FRONT_EPSILON := .05

## marks: RemotePlayers.remote_player_marks(depth, true) entries. viewer: the local player's world position.
func update_marks(cam: Camera3D, viewer: Vector3, marks: Array) -> void:
	camera = cam
	_entries.clear()
	if cam == null or not Settings.teammate_waypoints:
		visible = false
		queue_redraw()
		return
	visible = true
	var to_canvas := get_global_transform_with_canvas().affine_inverse()
	for mark in marks:
		if mark.has("exit_direction"):
			continue
		var at: Vector2 = mark.get("at", Vector2.ZERO)
		var level := int(mark.get("level", 0))
		var world := Vector3(at.x, float(level) * LEVEL_HEIGHT + HEAD_HEIGHT, at.y)
		var local := cam.global_transform.affine_inverse() * world
		# only points in front of the camera project: one level with the camera plane (a teammate right beside you)
		# divided by zero inside Camera3D and logged an engine error every update (773 in one co-op session on the
		# Windows guest, where each logged error is a real cost). At or behind the plane the edge arrow takes over.
		var behind := local.z > -FRONT_EPSILON
		var viewport_point := Vector2.ZERO if behind else cam.unproject_position(world)
		var canvas_point: Vector2 = to_canvas * viewport_point
		var entry := layout_for(canvas_point, Vector2(local.x, -local.y), behind, size, EDGE_MARGIN)
		if entry["clamped"]:
			continue   # off screen or behind you: the minimap's border arrow points to them instead (KT 2026-10-28)
		entry["name"] = String(mark.get("name", "?")).to_upper().substr(0, 14)
		entry["distance"] = roundi(viewer.distance_to(world))
		entry["colour"] = mark.get("colour", Color("63d9f1"))
		entry["level"] = level
		entry["other_floor"] = bool(mark.get("other_floor", false))
		entry["above"] = world.y > viewer.y + 2.0
		entry["stale"] = int(mark.get("age_ms", 0)) > STALE_MS
		entry["state"] = "DOWN" if bool(mark.get("spectating", false)) else ("CAUGHT" if bool(mark.get("caught", false)) else "")
		_entries.append(entry)
	queue_redraw()


## Where a marker goes. point: the projected position (canvas px); direction: the world vector in screen axes (right, up-flipped)
## used when the target is behind or off screen; behind: it is behind the camera. Returns {at, clamped, angle}.
static func layout_for(point: Vector2, direction: Vector2, behind: bool, area: Vector2, margin: float) -> Dictionary:
	var inner := Rect2(Vector2.ZERO, area).grow(-margin)
	if not behind and inner.has_point(point):
		return {"at": point, "clamped": false, "angle": 0.0}
	var centre := inner.get_center()
	var dir := direction
	if not behind and dir.length_squared() < 0.0001:
		dir = point - centre
	if dir.length_squared() < 0.0001:
		dir = Vector2.DOWN   # straight behind: point down the screen edge
	dir = dir.normalized()
	var half := inner.size * 0.5
	var t := minf(half.x / maxf(absf(dir.x), 0.0001), half.y / maxf(absf(dir.y), 0.0001))
	return {"at": centre + dir * t, "clamped": true, "angle": dir.angle()}


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var used: Array[Rect2] = []   # label boxes already drawn: later ones step down so edge markers never print over each other
	for entry in _entries:
		var at: Vector2 = entry["at"]
		var alpha := 0.45 if entry["stale"] else 1.0
		var colour: Color = entry["colour"]
		colour = Color(colour, alpha)
		var ink := Color(0.01, 0.04, 0.05, 0.9 * alpha)
		if entry["clamped"]:
			var angle: float = entry["angle"]
			var forward := Vector2.RIGHT.rotated(angle)
			var side := Vector2(-forward.y, forward.x)
			var tip := at + forward * 5.0
			var pointer := PackedVector2Array([tip, at - forward * 3.0 + side * 3.5, at - forward * 3.0 - side * 3.5])
			draw_colored_polygon(pointer, colour)
		else:
			draw_circle(at, 3.0, ink)
			draw_circle(at, 2.3, colour)
		var label := String(entry["name"])
		var distance_text := "%d M" % int(entry["distance"])
		if entry["other_floor"]:
			distance_text = "%s %+d  %d M" % ["UP" if entry["above"] else "DOWN", int(entry["level"]), int(entry["distance"])]
		var state := String(entry["state"])
		var lines := [label, distance_text]
		if not state.is_empty():
			lines.append(state)
		var line_y := 0.0
		var widest := 0.0
		for line in lines:
			widest = maxf(widest, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 6).x)
		var origin := at + Vector2(6.0, -6.0)
		if origin.x + widest > size.x - 2.0:
			origin.x = at.x - 6.0 - widest
		origin.y = clampf(origin.y, 8.0, size.y - 8.0 - 8.0 * (lines.size() - 1))
		var box := Rect2(origin + Vector2(0, -7.0), Vector2(widest, 7.0 * lines.size()))
		for _step in 8:
			var clash := false
			for other in used:
				if other.intersects(box):
					clash = true
					break
			if not clash:
				break
			box.position.y += 7.0 * lines.size() + 2.0
			origin.y += 7.0 * lines.size() + 2.0
		if origin.y > size.y - 8.0:
			origin.y = size.y - 8.0
		used.append(box)
		for line in lines:
			var tint := colour
			if line == state:
				tint = Color(Palette.ALERT, alpha)
			elif line == distance_text:
				tint = Color(Palette.INK, alpha)
			draw_string_outline(font, origin + Vector2(0, line_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, 3, ink)
			draw_string(font, origin + Vector2(0, line_y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 6, tint)
			line_y += 7.0
		if entry["other_floor"]:
			var up: bool = entry["above"]
			if not entry["clamped"]:
				draw_circle(at, 5.5, ink)
				draw_circle(at, 4.6, colour)
			var tri := PackedVector2Array()
			var d := -1.0 if up else 1.0
			tri.append(at + Vector2(0, d * 3.2))
			tri.append(at + Vector2(-2.8, -d * 1.8))
			tri.append(at + Vector2(2.8, -d * 1.8))
			draw_colored_polygon(tri, Color(0.01, 0.04, 0.05, 1.0))
