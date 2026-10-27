class_name NightWatchCamMap
extends Control

## The camera screen's minimap, in the style of the 2D game's cam map and FNAF's camera tablet: a schematic floor plan in a corner, a CAM n button at the real position
## of every camera room, the active camera lit, the routes drawn between rooms (vent shafts dashed), and a YOU marker for the office the hunters come to. It is DATA-DRIVEN: it is built
## from a mode's layout dictionary (NightWatchMapRegistry.layout_for(mode)), so every mode's map is its own:
##   rooms     {id: Vector3 centre}  every node of the walkable map (cameras, halls, vent shafts)
##   edges     [[a, b], ...]         the routes
##   entrances [room ids]            where the office is reached from (a line to YOU is drawn from each)
##   cams      [room ids]            the camera rooms in camera order: camera n is cams[n-1]
##   labels    {id: text}            the room names shown on the feed ("SHOW STAGE")
##   vents     [room ids]            vent shafts: edges touching them are dashed (modes with vents)
##   office    Vector3 (optional)    where YOU is drawn (default: below the entrances)
## Buttons are pushed apart if two rooms would overlap; positions are scaled to fit the box. Signals: camera_selected(room).

signal camera_selected(room: String)

const SIZE := Vector2(120, 92)
const BTN := Vector2(30, 13)
const PAD := Vector2(3, 3)
const INK := Color(0.8, 1.0, 0.85)
const AMBER := Color(1.0, 0.85, 0.4)

var layout := {}
var buttons := {}          # room id -> Button
var points := {}           # node id -> Vector2 (centre, map pixels)
var office_point := Vector2.ZERO
var active := ""


func _init() -> void:
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS


func setup(new_layout: Dictionary) -> void:
	layout = new_layout
	for b in buttons.values():
		(b as Node).queue_free()
	buttons.clear()
	points.clear()
	var rooms: Dictionary = layout.get("rooms", {})
	var cams: Array = layout.get("cams", [])
	if rooms.is_empty():
		queue_redraw()
		return
	# the office sits below the entrances unless the layout says where
	var entrances: Array = layout.get("entrances", [])
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for id in rooms:
		var p := Vector2((rooms[id] as Vector3).x, (rooms[id] as Vector3).z)
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var span := (max_p - min_p).max(Vector2(1.0, 1.0))
	var office := Vector2(INF, INF)
	if layout.has("office"):
		office = Vector2((layout["office"] as Vector3).x, (layout["office"] as Vector3).z)
	else:
		var sx := 0.0
		var n := 0
		for e in entrances:
			if rooms.has(e):
				sx += (rooms[e] as Vector3).x
				n += 1
		office = Vector2(sx / maxf(1.0, float(n)) if n > 0 else (min_p.x + max_p.x) * 0.5, max_p.y + span.y * 0.3)
	min_p = min_p.min(office)
	max_p = max_p.max(office)
	span = (max_p - min_p).max(Vector2(1.0, 1.0))
	var inner := SIZE - BTN - PAD * 2.0 - Vector2(0, 6)
	var origin := PAD + BTN * 0.5
	for id in rooms:
		var p := Vector2((rooms[id] as Vector3).x, (rooms[id] as Vector3).z)
		points[id] = origin + (p - min_p) / span * inner
	office_point = origin + (office - min_p) / span * inner
	# camera buttons, pushed apart when two would overlap
	var centres := {}
	for room in cams:
		if points.has(room):
			centres[room] = points[room]
	_relax(centres)
	for room in cams:
		if not centres.has(room):
			continue
		# a fixed-size holder, so the button can never grow past its slot whatever the theme's margins and font make of it
		var holder := Control.new()
		holder.name = "Slot_%s" % room
		holder.size = BTN
		holder.custom_minimum_size = BTN
		holder.position = (centres[room] as Vector2) - BTN * 0.5
		holder.clip_contents = true
		add_child(holder)
		var b := Button.new()
		b.name = "Cam_%s" % room
		b.text = "CAM %d" % (cams.find(room) + 1)
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_theme_font_size_override("font_size", 6)
		for state in ["normal", "hover", "pressed", "hover_pressed", "focus", "disabled"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.05, 0.08, 0.07, 0.95) if state != "hover" else Color(0.12, 0.16, 0.14, 0.95)
			sb.border_color = Color(0.3, 0.38, 0.33)
			sb.set_border_width_all(1)
			sb.set_content_margin_all(1)
			b.add_theme_stylebox_override(state, sb)
		b.pressed.connect(func(): camera_selected.emit(room))
		holder.add_child(b)
		buttons[room] = b
		points[room] = centres[room]
	set_active(active)
	queue_redraw()


func _relax(centres: Dictionary) -> void:
	var ids := centres.keys()
	var lo := BTN * 0.5 + Vector2(1, 1)
	var hi := SIZE - BTN * 0.5 - Vector2(1, 1)
	for iteration in 200:
		var moved := false
		for i in ids.size():
			for j in range(i + 1, ids.size()):
				var a: Vector2 = centres[ids[i]]
				var b: Vector2 = centres[ids[j]]
				var d := b - a
				var ox := BTN.x + 1.0 - absf(d.x)
				var oy := BTN.y + 1.0 - absf(d.y)
				if ox > 0.0 and oy > 0.0:
					moved = true
					if oy < ox:
						var s := 1.0 if d.y >= 0.0 else -1.0
						centres[ids[i]] = a - Vector2(0, s * oy * 0.5)
						centres[ids[j]] = b + Vector2(0, s * oy * 0.5)
					else:
						var s2 := 1.0 if d.x >= 0.0 else -1.0
						centres[ids[i]] = a - Vector2(s2 * ox * 0.5, 0)
						centres[ids[j]] = b + Vector2(s2 * ox * 0.5, 0)
		for id in ids:
			centres[id] = (centres[id] as Vector2).clamp(lo, hi)
		if not moved:
			break
	if _overlaps(centres):
		_pack(centres)


func _overlaps(centres: Dictionary) -> bool:
	var ids := centres.keys()
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var d: Vector2 = (centres[ids[i]] as Vector2) - (centres[ids[j]] as Vector2)
			if absf(d.x) < BTN.x and absf(d.y) < BTN.y:
				return true
	return false


## Too crowded to keep the real positions: lay the buttons out on a grid in reading order (top to bottom, left to right) so none overlaps.
func _pack(centres: Dictionary) -> void:
	var ids := centres.keys()
	ids.sort_custom(func(a, b):
		var pa: Vector2 = centres[a]
		var pb: Vector2 = centres[b]
		return pa.y < pb.y - 6.0 or (absf(pa.y - pb.y) <= 6.0 and pa.x < pb.x))
	var cols := maxi(1, int(floor((SIZE.x - 2.0) / (BTN.x + 1.0))))
	var rows := int(ceil(float(ids.size()) / float(cols)))
	var step_x := (SIZE.x - BTN.x - 2.0) / maxf(1.0, float(cols - 1)) if cols > 1 else 0.0
	var step_y := minf(BTN.y + 2.0, (SIZE.y - BTN.y - 2.0) / maxf(1.0, float(rows - 1))) if rows > 1 else 0.0
	for i in ids.size():
		centres[ids[i]] = Vector2(1.0 + BTN.x * 0.5 + float(i % cols) * step_x, 1.0 + BTN.y * 0.5 + float(i / cols) * step_y)


## The active camera is lit (amber); "" lights none.
func set_active(room: String) -> void:
	active = room
	for r in buttons:
		(buttons[r] as Button).modulate = AMBER if r == room else Color(1, 1, 1)


func label_for(room: String) -> String:
	return String((layout.get("labels", {}) as Dictionary).get(room, ""))


func number_for(room: String) -> int:
	return (layout.get("cams", []) as Array).find(room) + 1


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.04, 0.08, 0.06, 0.8))
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color(0.25, 0.3, 0.27), false, 1.0)
	var vents: Array = layout.get("vents", [])
	for e in layout.get("edges", []):
		if not points.has(e[0]) or not points.has(e[1]):
			continue
		var a: Vector2 = points[e[0]]
		var b: Vector2 = points[e[1]]
		var is_vent := vents.has(e[0]) or vents.has(e[1])
		if is_vent:
			draw_dashed_line(a, b, Color(0.55, 0.8, 0.9, 0.8), 1.0, 2.0)
		else:
			draw_line(a, b, Color(0.5, 0.6, 0.52, 0.9), 1.0)
	for e in layout.get("entrances", []):
		if points.has(e):
			draw_dashed_line(points[e], office_point, Color(0.96, 0.72, 0.28, 0.8), 1.0, 2.0)
	for v in vents:
		if points.has(v) and not buttons.has(v):
			draw_circle(points[v], 1.6, Color(0.55, 0.8, 0.9))
	var font := ThemeDB.fallback_font
	draw_string(font, office_point + Vector2(-8, 3), "YOU", HORIZONTAL_ALIGNMENT_CENTER, 16, 6, AMBER)
