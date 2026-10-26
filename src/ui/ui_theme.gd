class_name UiTheme
extends RefCounted

## The shared Theme for every menu and overlay: the Courier/monospace body of the
## Night Watch and Last Route web builds, the ink/crimson/amber palette from
## Palette, flat panels with hairline edges, crimson slab buttons.
##
## The Theme is generated here and saved as res://src/ui/ref_theme.tres (see
## tools/ui/build_theme.gd), which project.godot uses as the default GUI theme.
## Per-node overrides in scenes still win, so a screen can opt out.

const THEME_PATH := "res://src/ui/ref_theme.tres"
const DEFAULT_SIZE := 8

static var _body_font: SystemFont


## "Courier New, ui-monospace, monospace" in the web CSS; Godot asks each platform
## for the same faces and falls back to its own monospace.
static func body_font() -> SystemFont:
	if _body_font == null:
		_body_font = SystemFont.new()
		_body_font.font_names = PackedStringArray(["Courier New", "Courier", "Menlo",
			"Monaco", "DejaVu Sans Mono", "Liberation Mono", "monospace"])
		_body_font.font_weight = 600
		_body_font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_body_font.hinting = TextServer.HINTING_LIGHT
	return _body_font


static func _box(fill: Color, edge: Color, margin_h: int = 8, margin_v: int = 4,
		border: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(border)
	box.content_margin_left = margin_h
	box.content_margin_right = margin_h
	box.content_margin_top = margin_v
	box.content_margin_bottom = margin_v
	return box


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = DEFAULT_SIZE

	# Labels and rich text
	t.set_color("font_color", "Label", Palette.BODY)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_color("default_color", "RichTextLabel", Palette.BODY)

	# Buttons: crimson slab with a brighter edge is the primary look; the default
	# Button is the secondary (panel colour, hairline edge). Marker-style menu
	# lists use the "MenuItem" variation below.
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		pass
	t.set_stylebox("normal", "Button", _box(Palette.PANEL, Palette.PANEL_EDGE))
	t.set_stylebox("hover", "Button", _box(Palette.PANEL.lightened(.1), Palette.CRIMSON_EDGE))
	t.set_stylebox("pressed", "Button", _box(Palette.CRIMSON_DEEP, Palette.CRIMSON_EDGE))
	t.set_stylebox("focus", "Button", _box(Palette.PANEL.lightened(.06), Palette.AMBER))
	t.set_stylebox("disabled", "Button", _box(Palette.PANEL, Palette.PANEL_EDGE))
	t.set_color("font_color", "Button", Palette.BODY)
	t.set_color("font_hover_color", "Button", Palette.INK)
	t.set_color("font_pressed_color", "Button", Palette.INK)
	t.set_color("font_focus_color", "Button", Palette.INK)
	t.set_color("font_disabled_color", "Button", Palette.DIM)

	t.add_type("PrimaryButton")
	t.set_type_variation("PrimaryButton", "Button")
	t.set_stylebox("normal", "PrimaryButton", _box(Palette.CRIMSON, Palette.CRIMSON_EDGE, 10, 4))
	t.set_stylebox("hover", "PrimaryButton", _box(Palette.CRIMSON.lightened(.12), Palette.CRIMSON_EDGE.lightened(.2), 10, 4))
	t.set_stylebox("pressed", "PrimaryButton", _box(Palette.CRIMSON.darkened(.2), Palette.CRIMSON_EDGE, 10, 4))
	t.set_stylebox("focus", "PrimaryButton", _box(Palette.CRIMSON, Palette.AMBER, 10, 4))
	t.set_color("font_color", "PrimaryButton", Palette.INK)

	# Night Watch menu entry: no box, ">>" marker on the selected one (UiMenuList)
	var flat := StyleBoxEmpty.new()
	flat.content_margin_left = 6
	flat.content_margin_right = 6
	flat.content_margin_top = 2
	flat.content_margin_bottom = 2
	t.add_type("MenuItem")
	t.set_type_variation("MenuItem", "Button")
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		t.set_stylebox(state, "MenuItem", flat)
	t.set_color("font_color", "MenuItem", Palette.INK)
	t.set_color("font_hover_color", "MenuItem", Color.WHITE)
	t.set_color("font_focus_color", "MenuItem", Color.WHITE)
	t.set_color("font_disabled_color", "MenuItem", Color("4a463c"))

	# Panels
	t.set_stylebox("panel", "PanelContainer", _box(Palette.PANEL, Palette.PANEL_EDGE, 8, 8))
	t.set_stylebox("panel", "Panel", _box(Palette.PANEL, Palette.PANEL_EDGE, 8, 8))

	# Text fields
	t.set_stylebox("normal", "LineEdit", _box(Palette.INSET, Color("4b3948"), 6, 3))
	t.set_stylebox("focus", "LineEdit", _box(Palette.INSET, Palette.AMBER, 6, 3))
	t.set_color("font_color", "LineEdit", Palette.INK)
	t.set_color("font_placeholder_color", "LineEdit", Palette.MUTED)
	t.set_color("caret_color", "LineEdit", Palette.AMBER)
	t.set_color("selection_color", "LineEdit", Color(Palette.CRIMSON, .45))

	# Bars
	t.set_stylebox("background", "ProgressBar", _box(Palette.INSET, Palette.PANEL_EDGE, 0, 0))
	t.set_stylebox("fill", "ProgressBar", _box(Palette.CRIMSON, Palette.CRIMSON, 0, 0, 0))
	t.set_color("font_color", "ProgressBar", Palette.INK)
	for kind in [["HudBarWarn", Palette.AMBER_FILL], ["HudBarSafe", Palette.STABLE],
			["HudBarLow", Palette.CRIMSON_EDGE]]:
		t.add_type(kind[0])
		t.set_type_variation(kind[0], "ProgressBar")
		t.set_stylebox("fill", kind[0], _box(kind[1], kind[1], 0, 0, 0))

	# Sliders, checks, scroll
	t.set_stylebox("slider", "HSlider", _box(Palette.INSET, Palette.PANEL_EDGE, 0, 2))
	t.set_stylebox("grabber_area", "HSlider", _box(Palette.CRIMSON, Palette.CRIMSON, 0, 2, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(Palette.CRIMSON_EDGE, Palette.CRIMSON_EDGE, 0, 2, 0))
	t.set_color("font_color", "CheckBox", Palette.BODY)
	t.set_color("font_hover_color", "CheckBox", Palette.INK)
	t.set_stylebox("grabber", "VScrollBar", _box(Palette.CRIMSON_DEEP, Palette.CRIMSON_DEEP, 0, 0, 0))
	t.set_stylebox("scroll", "VScrollBar", _box(Palette.INSET, Palette.INSET, 0, 0, 0))

	# Tooltips
	t.set_stylebox("panel", "TooltipPanel", _box(Palette.PANEL, Palette.AMBER, 4, 3))
	t.set_color("font_color", "TooltipLabel", Palette.INK)
	return t
