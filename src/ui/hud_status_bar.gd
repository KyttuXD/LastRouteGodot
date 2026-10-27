class_name HudStatusBar
extends PanelContainer

## One compact top-centre status bar: BETA / TEST SERVER tag, ADMIN ACTIVE, the public route line, SOLO / ROOM.
## Each source owns a named segment (set_segment); empty segments vanish, the bar shrinks to the visible ones and
## hides when none are left. Segments never wrap and are ellipsised to the room the window leaves, so the bar can
## neither overlap another HUD panel nor cross the window edge. HUD._layout_hud() sets max_width and the top margin.

const GROUP := "hud_status_bar"
const ORDER := ["env", "admin", "public"]
const MIN_SEGMENT_WIDTH := 48.0

var max_width := 9999.0
## Segment font size in HUD units; HUD._layout_hud() raises it on small windows so text stays readable.
var font_units := 7
var _row: HBoxContainer
var _segments := {}


static func find(tree: SceneTree) -> HudStatusBar:
	return tree.get_first_node_in_group(GROUP) as HudStatusBar if tree != null else null


func _init() -> void:
	name = "HudStatusBar"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	add_to_group(GROUP)
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.078, 0.043, 0.063, 0.88)
	box.border_color = Color(0.3, 0.14, 0.18, 0.95)
	box.set_border_width_all(1)
	box.set_corner_radius_all(2)
	box.content_margin_left = 2
	box.content_margin_right = 2
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	add_theme_stylebox_override("panel", box)
	_row = HBoxContainer.new()
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row.add_theme_constant_override("separation", 2)
	add_child(_row)
	visible = false


## kind: "env" (amber tag), "admin" (teal tag) or "line" (plain amber text).
func set_segment(key: String, text: String, kind: String = "line") -> void:
	var label := _segments.get(key) as Label
	if text.is_empty():
		if label != null:
			label.visible = false
		_refresh()
		return
	if label == null:
		label = Label.new()
		label.name = "Segment_%s" % key
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.add_theme_font_size_override("font_size", font_units)
		label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_segments[key] = label
		_row.add_child(label)
		var ordered: Array = ORDER.duplicate()
		var at := ordered.find(key)
		_row.move_child(label, mini(maxi(at, 0), _row.get_child_count() - 1))
	match kind:
		"env":
			label.add_theme_color_override("font_color", Palette.ON_AMBER)
			label.add_theme_stylebox_override("normal", _tag_box(Palette.ACCENT))
		"admin":
			label.add_theme_color_override("font_color", Palette.ON_AMBER)
			label.add_theme_stylebox_override("normal", _tag_box(Palette.TEAL))
		_:
			label.add_theme_color_override("font_color", Palette.AMBER)
			label.remove_theme_stylebox_override("normal")
	label.text = text
	label.visible = true
	_refresh()


func segment_text(key: String) -> String:
	var label := _segments.get(key) as Label
	return label.text if label != null and label.visible else ""


func _tag_box(color: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.content_margin_left = 4
	box.content_margin_right = 4
	box.content_margin_top = 1
	box.content_margin_bottom = 1
	return box


func _refresh() -> void:
	var any := false
	for key in _segments:
		if (_segments[key] as Label).visible:
			any = true
	visible = any
	reset_size()


func _label_width(label: Label) -> float:
	var style := label.get_theme_stylebox("normal")
	var pad := style.get_minimum_size().x if style != null else 0.0
	return label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_units).x + pad + 1.0


## Width the visible segments want, at their natural (un-ellipsised) size.
func natural_width() -> float:
	var total := 4.0
	var count := 0
	for key in _segments:
		var label := _segments[key] as Label
		if label.visible:
			total += _label_width(label)
			count += 1
	return total + 2.0 * maxi(count - 1, 0)


## Squeeze the segments into `available`: the server tag gives way first (ellipsis), the others keep their text.
## An ellipsis label reports almost no minimum width, so every segment gets its width pinned here.
func fit(available: float, units: int = 7) -> void:
	max_width = available
	font_units = units
	var widths := {}
	for key in _segments:
		var label := _segments[key] as Label
		label.add_theme_font_size_override("font_size", font_units)
		widths[key] = _label_width(label)
	var over := natural_width() - available
	for key in ["public", "env", "admin"]:
		if over <= 0.0 or not widths.has(key) or not (_segments[key] as Label).visible:
			continue
		var cut := minf(over, maxf(0.0, widths[key] - MIN_SEGMENT_WIDTH))
		widths[key] -= cut
		over -= cut
	for key in _segments:
		(_segments[key] as Label).custom_minimum_size.x = ceilf(widths[key])
	reset_size()
