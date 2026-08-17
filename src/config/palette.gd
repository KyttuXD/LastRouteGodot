class_name Palette
extends RefCounted

## The colours of the original web build, in one place.
##
## The Godot port had drifted to a teal-on-black scheme of its own while the
## JS version it is a port OF is near-black, crimson and amber. Sampled from
## the live build's menu, room lobby, character files and pause overlay rather
## than guessed, so ported screens read as the same game rather than a
## lookalike.
##
## Everything that draws chrome reads from here. Colours written directly into
## a scene file are invisible to a palette change, which is how the drift
## happened in the first place.

# -- ground ------------------------------------------------------------------
## The page itself: black with a little warmth in it, never pure #000.
const BACKDROP := Color("0a0608")
## A panel standing on that ground, and the hairline around it.
const PANEL := Color("140b10")
const PANEL_EDGE := Color("2b1a22")
## Inset blocks inside a panel -- the seed readout, a player row.
const INSET := Color("1b1016")
## What the pause overlay lays over the running game.
const SCRIM := Color(0.04, 0.024, 0.031, 0.82)

# -- type --------------------------------------------------------------------
## Headlines and anything the eye should land on first.
const INK := Color("f2ede1")
## Body copy.
const BODY := Color("bab2a8")
## Captions, hints, and the small print under a control.
const MUTED := Color("7d746e")
## Disabled controls and their labels.
const DIM := Color("4c4449")

# -- accents -----------------------------------------------------------------
## Section labels, seed text, the selected state of a toggle. The web build
## uses amber for "this is a system readout" and crimson for "this does
## something", and keeping that split is most of why it reads correctly.
const AMBER := Color("e8b84b")
const AMBER_FILL := Color("f0c264")
## Text printed ON an amber fill, which is the only place dark type appears.
const ON_AMBER := Color("1a0f14")

## Primary action.
const CRIMSON := Color("c0303c")
const CRIMSON_EDGE := Color("e2515d")
## Secondary action sitting beside a primary one.
const CRIMSON_DEEP := Color("8c2530")

## Danger and failure readouts.
const ALERT := Color("e2515d")
## Success, and the "signal stable" states.
const STABLE := Color("6fbf8a")

# -- metrics -----------------------------------------------------------------
## The web build's rhythm, in design pixels: a panel's inner padding, the gap
## between stacked blocks, and the letterspacing on its uppercase labels.
const PAD := 12
const GAP := 8
const LABEL_TRACKING := 2

## The original title's CSS stack is `Arial Black, Impact, sans-serif`.
## It never shipped a proprietary font file, so Godot asks each platform for
## the same faces and falls back to a widely available heavy sans-serif.
static var _title_font: SystemFont


static func title_font() -> SystemFont:
	if _title_font == null:
		_title_font = SystemFont.new()
		_title_font.font_names = PackedStringArray([
			"Arial Black", "Impact", "Arial", "Liberation Sans", "DejaVu Sans",
		])
		_title_font.font_weight = 900
	return _title_font


## A filled panel with a hairline edge, as every block in the web build has.
static func panel_box(fill: Color = PANEL, edge: Color = PANEL_EDGE,
		pad: int = PAD) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box


## A button face. The web build's primary is a flat crimson slab with a
## brighter edge; its secondary is the panel colour with the same edge.
static func button_box(fill: Color, edge: Color, horizontal_margin: int = 10,
		vertical_margin: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = horizontal_margin
	box.content_margin_right = horizontal_margin
	box.content_margin_top = vertical_margin
	box.content_margin_bottom = vertical_margin
	return box


## Dress a Button in one of the two web-build styles.
static func style_button(button: Button, primary: bool, compact: bool = false) -> void:
	var fill := CRIMSON if primary else PANEL
	var edge := CRIMSON_EDGE if primary else PANEL_EDGE
	var horizontal_margin := 5 if compact else 10
	var vertical_margin := 3 if compact else 4
	button.add_theme_stylebox_override("normal", button_box(fill, edge,
		horizontal_margin, vertical_margin))
	button.add_theme_stylebox_override("hover",
		button_box(fill.lightened(0.12), edge.lightened(0.2), horizontal_margin,
			vertical_margin))
	button.add_theme_stylebox_override("pressed",
		button_box(fill.darkened(0.2), edge, horizontal_margin, vertical_margin))
	button.add_theme_stylebox_override("focus", button_box(fill,
		edge.lightened(0.35), horizontal_margin, vertical_margin))
	button.add_theme_stylebox_override("disabled", button_box(PANEL, PANEL_EDGE,
		horizontal_margin, vertical_margin))
	button.add_theme_color_override("font_color", INK if primary else BODY)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", DIM)


## Text fields in the join/account dialogs. Keeping this here prevents the
## native platform theme from dropping a bright grey box into the dark frame.
static func style_line_edit(field: LineEdit) -> void:
	var normal := panel_box(INSET, Color("4b3948"), 6)
	var focus := panel_box(INSET, AMBER, 6)
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", MUTED)
	field.add_theme_color_override("caret_color", AMBER)


## Compact close control used by the original web panels: one thin outer
## outline, a boxed ESC keycap, then the CLOSE label. Children ignore mouse so
## the whole face remains one accessible Button.
static func style_escape_close(button: Button) -> void:
	button.text = ""
	button.custom_minimum_size = Vector2(54, 16)
	button.add_theme_stylebox_override("normal", button_box(PANEL, PANEL_EDGE, 2, 2))
	button.add_theme_stylebox_override("hover",
		button_box(PANEL.lightened(0.08), PANEL_EDGE.lightened(0.2), 2, 2))
	button.add_theme_stylebox_override("pressed",
		button_box(PANEL.darkened(0.12), PANEL_EDGE, 2, 2))
	button.add_theme_stylebox_override("focus",
		button_box(PANEL, PANEL_EDGE.lightened(0.35), 2, 2))
	if button.get_node_or_null("EscCloseContent") != null:
		return
	var content := HBoxContainer.new()
	content.name = "EscCloseContent"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 3
	content.offset_top = 2
	content.offset_right = -3
	content.offset_bottom = -2
	content.add_theme_constant_override("separation", 4)
	button.add_child(content)
	var keycap := Label.new()
	keycap.text = "ESC"
	keycap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	keycap.add_theme_font_size_override("font_size", 6)
	keycap.add_theme_color_override("font_color", INK)
	keycap.add_theme_stylebox_override("normal", button_box(INSET,
		Color("6a5264"), 3, 1))
	content.add_child(keycap)
	var caption := Label.new()
	caption.text = "CLOSE"
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption.add_theme_font_size_override("font_size", 6)
	caption.add_theme_color_override("font_color", BODY)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	content.add_child(caption)


## A toggle uses the same nested-keycap grammar as ESC CLOSE: the action name
## stays readable on the left and a small boxed ON/OFF chip sits at the right.
static func style_state_toggle(button: Button, caption_text: String,
		enabled: bool, compact: bool = false) -> void:
	button.text = ""
	style_button(button, false, compact)
	var content := button.get_node_or_null("StateToggleContent") as HBoxContainer
	if content == null:
		content = HBoxContainer.new()
		content.name = "StateToggleContent"
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.offset_left = 5
		content.offset_top = 2
		content.offset_right = -5
		content.offset_bottom = -2
		content.add_theme_constant_override("separation", 4)
		button.add_child(content)
		var caption := Label.new()
		caption.name = "Caption"
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_font_size_override("font_size", 6 if compact else 7)
		caption.add_theme_color_override("font_color", BODY)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		content.add_child(caption)
		var chip := Label.new()
		chip.name = "StateChip"
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = Vector2(20, 0)
		chip.add_theme_font_size_override("font_size", 6)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		content.add_child(chip)
	(content.get_node("Caption") as Label).text = caption_text
	set_state_toggle(button, enabled)


static func set_state_toggle(button: Button, enabled: bool) -> void:
	var chip := button.get_node_or_null("StateToggleContent/StateChip") as Label
	if chip == null:
		return
	chip.text = "ON" if enabled else "OFF"
	chip.add_theme_color_override("font_color", STABLE if enabled else MUTED)
	chip.add_theme_stylebox_override("normal", button_box(INSET,
		STABLE if enabled else Color("6a5264"), 3, 1))


## An uppercase, letterspaced system label -- the amber "SIGNAL ARCHIVE //
## ROUTE UNSTABLE" line the web build puts above every heading.
static func style_label(label: Label, tint: Color, size: int,
		tracking: int = 0) -> void:
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", size)
	if tracking > 0:
		label.add_theme_constant_override("outline_size", 0)
		# Godot has no letterspacing constant on Label, so the web build's
		# tracked labels are spaced in the string instead; see `track()`.
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Heavy display treatment for screen titles; body copy deliberately keeps the
## compact fallback font that remains legible at the game's 480x270 canvas.
static func style_title(label: Label, tint: Color = INK) -> void:
	label.add_theme_font_override("font", title_font())
	label.add_theme_color_override("font_color", tint)


## Letterspacing by hand. Godot's Label has no tracking property, and these
## labels are short and uppercase, so padding the string is the honest way to
## get the web build's spaced-out system captions.
static func track(text: String, spaces: int = 1) -> String:
	# A normal monospace space was several times wider than CSS `letter-spacing`
	# and made short captions span half the 480px canvas. Thin spaces retain the
	# tracked signal-terminal feel without turning a heading into a word ladder.
	var gap := " ".repeat(spaces)
	var out := PackedStringArray()
	for i in text.length():
		out.append(text[i])
	return gap.join(out)
