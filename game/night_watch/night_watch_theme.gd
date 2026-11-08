class_name NightWatchTheme
extends RefCounted

## The one Theme every Night Watch screen uses (menus, HUD, the admin menu inside it): theme_nightwatch.tres for buttons, panels and labels, plus the controls that file does not define --
## sliders, check boxes, text fields, tabs, scroll bars, drop-downs -- in the same amber-on-black, so none of them falls back to the project's purple Last Route theme.
## `meta night_watch` marks it for tests/night_watch_ui_audit.gd.

const PATH := "res://game/night_watch/theme_nightwatch.tres"
const INK := Color("e8e2d0")
const BODY := Color("c9c3b0")
const MUTED := Color("9b947f")
const AMBER := Color("e0b04a")
const AMBER_DEEP := Color("5a3f10")
const PANEL := Color("0f0d0a")
const INSET := Color("060504")
const EDGE := Color("2a2620")
const EDGE_LIGHT := Color("4a443a")

static var _theme: Theme = null


static func get_theme() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	if ResourceLoader.exists(PATH) and load(PATH) is Theme:
		t = (load(PATH) as Theme).duplicate() as Theme
	# sliders
	t.set_stylebox("slider", "HSlider", _box(EDGE, EDGE, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", _box(AMBER, AMBER, 0, 2))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(AMBER, AMBER, 0, 2))
	var knob := _icon(AMBER, AMBER, 8)
	for name_value in ["grabber", "grabber_highlight", "grabber_disabled"]:
		t.set_icon(name_value, "HSlider", knob)
	# check boxes
	for type_name in ["CheckBox", "CheckButton"]:
		t.set_icon("unchecked", type_name, _icon(INSET, AMBER, 9))
		t.set_icon("checked", type_name, _icon(AMBER, AMBER, 9))
		t.set_icon("unchecked_disabled", type_name, _icon(INSET, EDGE_LIGHT, 9))
		t.set_icon("checked_disabled", type_name, _icon(EDGE_LIGHT, EDGE_LIGHT, 9))
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(color_name, type_name, BODY if color_name == "font_color" else INK)
		t.set_stylebox("focus", type_name, _box(Color(0, 0, 0, 0), AMBER, 1, 2, false))
	# text fields
	t.set_stylebox("normal", "LineEdit", _box(INSET, EDGE_LIGHT, 1, 3))
	t.set_stylebox("focus", "LineEdit", _box(INSET, AMBER, 2, 3))
	t.set_stylebox("read_only", "LineEdit", _box(INSET, EDGE, 1, 3))
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", MUTED)
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_color("selection_color", "LineEdit", Color(AMBER, 0.45))
	# tabs, scroll bars, bars
	for kind in ["selected", "unselected", "hovered", "disabled"]:
		var box := _box(AMBER if kind == "selected" else (EDGE if kind == "hovered" else PANEL), AMBER if kind == "selected" else EDGE, 1, 3)
		t.set_stylebox("tab_%s" % kind, "TabBar", box)
	t.set_color("font_selected_color", "TabBar", PANEL)
	t.set_color("font_unselected_color", "TabBar", BODY)
	t.set_color("font_hovered_color", "TabBar", INK)
	t.set_color("font_disabled_color", "TabBar", MUTED)
	t.set_stylebox("scroll", "VScrollBar", _box(INSET, INSET, 0, 2))
	t.set_stylebox("grabber", "VScrollBar", _box(EDGE_LIGHT, EDGE_LIGHT, 0, 2))
	t.set_stylebox("grabber_highlight", "VScrollBar", _box(AMBER, AMBER, 0, 2))
	t.set_stylebox("grabber_pressed", "VScrollBar", _box(AMBER, AMBER, 0, 2))
	t.set_stylebox("background", "ProgressBar", _box(INSET, EDGE, 1, 2))
	t.set_stylebox("fill", "ProgressBar", _box(AMBER, AMBER, 0, 2))
	# drop-downs and their pop-ups
	t.set_stylebox("panel", "PopupMenu", _box(PANEL, AMBER, 1, 3))
	t.set_stylebox("hover", "PopupMenu", _box(AMBER_DEEP, AMBER_DEEP, 0, 3))
	t.set_color("font_color", "PopupMenu", BODY)
	t.set_color("font_hover_color", "PopupMenu", INK)
	t.set_color("font_disabled_color", "PopupMenu", MUTED)
	t.set_meta("night_watch", true)
	_theme = t
	return t


static func _box(fill: Color, edge: Color, border: int, margin: int, draw_center := true) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.draw_center = draw_center
	box.border_color = edge
	box.set_border_width_all(border)
	box.set_content_margin_all(margin)
	return box


static func _icon(fill: Color, edge: Color, size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(edge)
	for x in range(1, size - 1):
		for y in range(1, size - 1):
			img.set_pixel(x, y, fill)
	return ImageTexture.create_from_image(img)
