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
static func button_box(fill: Color, edge: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	return box


## Dress a Button in one of the two web-build styles.
static func style_button(button: Button, primary: bool) -> void:
	var fill := CRIMSON if primary else PANEL
	var edge := CRIMSON_EDGE if primary else PANEL_EDGE
	button.add_theme_stylebox_override("normal", button_box(fill, edge))
	button.add_theme_stylebox_override("hover",
		button_box(fill.lightened(0.12), edge.lightened(0.2)))
	button.add_theme_stylebox_override("pressed",
		button_box(fill.darkened(0.2), edge))
	button.add_theme_stylebox_override("focus", button_box(fill, edge.lightened(0.35)))
	button.add_theme_stylebox_override("disabled", button_box(PANEL, PANEL_EDGE))
	button.add_theme_color_override("font_color", INK if primary else BODY)
	button.add_theme_color_override("font_hover_color", INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_disabled_color", DIM)


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


## Letterspacing by hand. Godot's Label has no tracking property, and these
## labels are short and uppercase, so padding the string is the honest way to
## get the web build's spaced-out system captions.
static func track(text: String, spaces: int = 1) -> String:
	var gap := " ".repeat(spaces)
	var out := PackedStringArray()
	for i in text.length():
		out.append(text[i])
	return gap.join(out)
