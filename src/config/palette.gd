class_name Palette
extends RefCounted

## THE colour scheme of the Godot 2 app, in one place (retune here and everything follows).
##
## Godot 2 palette: near-black plum ground, cream text, a PURPLE accent (Kathy's purple, sampled
## from her sprite #9870a0 and lifted for contrast: primary actions, the route line of the logo)
## and TEAL for secondary/active highlights (the terminal colour: selection marker, focus rings,
## cool HUD bars). Red stays reserved for danger. NB: the constant names AMBER*/ON_AMBER predate
## the purple (the first pass was amber #c98a2b/#e0a339/#e8b84b); they now hold the purple family. assets/branding/logo.svg uses the same values; tools/branding/build_logo.gd
## re-renders the icons from it. Text/background pairs were checked for WCAG AA (>= 4.5:1).
##
## (Older note, kept for history:)
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
static var BACKDROP := Color("0d0810")
## A panel standing on that ground, and the hairline around it.
static var PANEL := Color("170e19")
static var PANEL_EDGE := Color("2e1f33")
## Inset blocks inside a panel -- the seed readout, a player row.
static var INSET := Color("1e1322")
## What the pause overlay lays over the running game.
static var SCRIM := Color(0.05, 0.03, 0.07, 0.82)

# -- type --------------------------------------------------------------------
## Headlines and anything the eye should land on first.
static var INK := Color("f2ede1")
## Body copy.
static var BODY := Color("bcb3a8")
## Captions, hints, and the small print under a control.
static var MUTED := Color("8c817e")
## Disabled controls and their labels.
static var DIM := Color("4c4449")
## Label colour of a disabled control: dim, but still 3:1 against the panel (DIM is for decoration, not text).
static var DISABLED := Color("766e72")

# -- accents -----------------------------------------------------------------
## Section labels, seed text, the selected state of a toggle. The web build
## uses amber for "this is a system readout" and crimson for "this does
## something", and keeping that split is most of why it reads correctly.
static var AMBER := Color("c9a9d8")
static var AMBER_FILL := Color("b48ec0")
## Text printed ON an amber fill, which is the only place dark type appears.
static var ON_AMBER := Color("1a0f14")

## Primary action: a purple slab with a brighter edge; text on it is ON_AMBER (dark).
static var ACCENT := Color("a67fb0")
static var ACCENT_EDGE := Color("c4a2d0")
## Secondary action sitting beside a primary one, deep borders.
static var ACCENT_DEEP := Color("5a3f63")

## Secondary / active highlight: the selection marker ">>", focus rings, cool meters.
static var TEAL := Color("37b9b0")
static var TEAL_BRIGHT := Color("bff5ec")
static var TEAL_DEEP := Color("1f6e6a")

## Danger and failure readouts.
static var ALERT := Color("e2515d")
## Success, and the "signal stable" states.
static var STABLE := Color("6fbf8a")

## Field and keycap outlines, and the per-game frame style: corner radius and the tracking of tracked captions.
static var FIELD_EDGE := Color("4b3948")
static var KEYCAP_EDGE := Color("6a5264")
static var CORNER := 0
static var EDGE_WIDTH := 1

# -- metrics -----------------------------------------------------------------
## The web build's rhythm, in design pixels: a panel's inner padding, the gap
## between stacked blocks, and the letterspacing on its uppercase labels.
const PAD := 12
const GAP := 8
static var LABEL_TRACKING := 2

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
	box.set_border_width_all(EDGE_WIDTH)
	box.set_corner_radius_all(CORNER)
	box.content_margin_left = pad
	box.content_margin_right = pad
	box.content_margin_top = pad
	box.content_margin_bottom = pad
	return box


## A button face. The primary is a flat amber slab with a
## brighter edge; its secondary is the panel colour with the same edge.
static func button_box(fill: Color, edge: Color, horizontal_margin: int = 10,
		vertical_margin: int = 4) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(EDGE_WIDTH)
	box.set_corner_radius_all(CORNER)
	box.content_margin_left = horizontal_margin
	box.content_margin_right = horizontal_margin
	box.content_margin_top = vertical_margin
	box.content_margin_bottom = vertical_margin
	return box


## Dress a Button in one of the two web-build styles.
static func style_button(button: Button, primary: bool, compact: bool = false) -> void:
	var fill := ACCENT if primary else PANEL
	var edge := ACCENT_EDGE if primary else PANEL_EDGE
	var horizontal_margin := 5 if compact else 10
	var vertical_margin := 3 if compact else 4
	button.add_theme_stylebox_override("normal", button_box(fill, edge,
		horizontal_margin, vertical_margin))
	button.add_theme_stylebox_override("hover",
		button_box(fill.lightened(0.12), edge.lightened(0.2), horizontal_margin,
			vertical_margin))
	# pressed: a deeper fill so the light label keeps 4.5:1 (the darkened accent only reached 4.2:1)
	button.add_theme_stylebox_override("pressed",
		button_box(ACCENT_DEEP if primary else fill.darkened(0.2), edge, horizontal_margin, vertical_margin))
	button.add_theme_stylebox_override("focus", button_box(fill,
		TEAL, horizontal_margin, vertical_margin))
	button.add_theme_stylebox_override("disabled", button_box(PANEL, PANEL_EDGE,
		horizontal_margin, vertical_margin))
	button.add_theme_color_override("font_color", ON_AMBER if primary else BODY)
	button.add_theme_color_override("font_hover_color", ON_AMBER if primary else INK)
	button.add_theme_color_override("font_pressed_color", INK)
	button.add_theme_color_override("font_focus_color", ON_AMBER if primary else INK)
	button.add_theme_color_override("font_disabled_color", DISABLED)


## Text fields in the join/account dialogs. Keeping this here prevents the
## native platform theme from dropping a bright grey box into the dark frame.
static func style_line_edit(field: LineEdit) -> void:
	var normal := panel_box(INSET, FIELD_EDGE, 6)
	var focus := panel_box(INSET, TEAL, 6)
	# User-entered codes, names, passwords and URLs are all left-to-right even
	# when the operating-system locale uses an RTL interface direction.
	field.text_direction = Control.TEXT_DIRECTION_LTR
	field.alignment = HORIZONTAL_ALIGNMENT_LEFT
	field.add_theme_stylebox_override("normal", normal)
	field.add_theme_stylebox_override("focus", focus)
	field.add_theme_color_override("font_color", INK)
	field.add_theme_color_override("font_placeholder_color", MUTED)
	field.add_theme_color_override("caret_color", TEAL)


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
		KEYCAP_EDGE, 3, 1))
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
	_hide_check_icons(button)
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


static var _blank_icon: Texture2D


## A toggle row already shows its state in the ON/OFF chip. A CheckBox/CheckButton would also draw its own check icon at the
## left, on top of the row's caption (the admin VISUAL tab read "..XEL EFFECT"), so the icons are blanked: the chip is the
## one indicator and the whole row stays clickable and focusable.
static func _hide_check_icons(button: Button) -> void:
	if not (button is CheckBox or button is CheckButton):
		return
	if _blank_icon == null:
		var image := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		_blank_icon = ImageTexture.create_from_image(image)
	for icon_name in ["checked", "unchecked", "checked_disabled", "unchecked_disabled",
			"radio_checked", "radio_unchecked", "radio_checked_disabled", "radio_unchecked_disabled"]:
		button.add_theme_icon_override(icon_name, _blank_icon)
	button.add_theme_constant_override("h_separation", 0)


static func set_state_toggle(button: Button, enabled: bool) -> void:
	var chip := button.get_node_or_null("StateToggleContent/StateChip") as Label
	if chip == null:
		return
	chip.text = "ON" if enabled else "OFF"
	chip.add_theme_color_override("font_color", STABLE if enabled else MUTED)
	chip.add_theme_stylebox_override("normal", button_box(INSET,
		STABLE if enabled else KEYCAP_EDGE, 3, 1))


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


# -- per-game colour schemes --------------------------------------------------
## Each game's menus read THIS table, never their own colours: GameRegistry.active_game_id applies the scheme the
## moment a game is opened (and the hub puts Last Route's back), so settings, pause, account, lobby, results, loading,
## admin and the HUD frames all follow. Last Route keeps the purple route identity above; the City is a night city:
## deep navy ink, neon amber for primary actions, ice cyan for readouts, softly rounded glass-like panels. Night Watch
## is the 2D game's CRT amber-on-black: its own menus and HUD are dressed by theme_nightwatch.tres, and this scheme
## gives the SHARED screens that run inside it (the admin menu, results, the death moment) the same colours.
const SCHEMES := {
	"last_route": {},   # the defaults above
	"city": {
		"BACKDROP": "070a18", "PANEL": "0d1128", "PANEL_EDGE": "2a3a7a", "INSET": "141a3c", "SCRIM": "04061488",
		"INK": "eaf2ff", "BODY": "b9c4de", "MUTED": "8a94b4", "DIM": "454c6a", "DISABLED": "7d87a8",
		"AMBER": "8fe3f5", "AMBER_FILL": "55c7e0", "ON_AMBER": "070a18",
		"ACCENT": "f5a742", "ACCENT_EDGE": "ffd28a", "ACCENT_DEEP": "6b4412",
		"TEAL": "4ff0d2", "TEAL_BRIGHT": "c8fff4", "TEAL_DEEP": "1b7a70",
		"ALERT": "ff5c7a", "STABLE": "5de0a0", "FIELD_EDGE": "3b4c96", "KEYCAP_EDGE": "56689f",
		"CORNER": 3, "EDGE_WIDTH": 1, "LABEL_TRACKING": 3,
	},
	"night_watch": {
		"BACKDROP": "0a0907", "PANEL": "0f0d0a", "PANEL_EDGE": "2a2620", "INSET": "060504", "SCRIM": "000000cc",
		"INK": "e8e2d0", "BODY": "c9c3b0", "MUTED": "8a8472", "DIM": "5a5648", "DISABLED": "7a7566",
		"AMBER": "e0b04a", "AMBER_FILL": "c4902e", "ON_AMBER": "0f0d0a",
		"ACCENT": "e0b04a", "ACCENT_EDGE": "f2d089", "ACCENT_DEEP": "5a3f10",
		"TEAL": "5fa88a", "TEAL_BRIGHT": "a8e0c8", "TEAL_DEEP": "245a46",
		"ALERT": "e0504a", "STABLE": "6fbf8a", "FIELD_EDGE": "4a443a", "KEYCAP_EDGE": "6a6455",
		"CORNER": 0, "EDGE_WIDTH": 1, "LABEL_TRACKING": 1,
	},
}
static var scheme_id := "last_route"
static var _last_route_tokens := {}
static var _project_theme: Theme = null


## Remember Last Route's tokens the first time a scheme is applied, so "last_route" can restore them.
static func _snapshot() -> void:
	if not _last_route_tokens.is_empty():
		return
	for key in ["BACKDROP", "PANEL", "PANEL_EDGE", "INSET", "SCRIM", "INK", "BODY", "MUTED", "DIM", "DISABLED", "AMBER",
			"AMBER_FILL", "ON_AMBER", "ACCENT", "ACCENT_EDGE", "ACCENT_DEEP", "TEAL", "TEAL_BRIGHT", "TEAL_DEEP", "ALERT",
			"STABLE", "FIELD_EDGE", "KEYCAP_EDGE", "CORNER", "EDGE_WIDTH", "LABEL_TRACKING"]:
		_last_route_tokens[key] = tokens().get(key)


## All scheme tokens as they are right now (name -> Color/int).
static func tokens() -> Dictionary:
	return {
		"BACKDROP": BACKDROP, "PANEL": PANEL, "PANEL_EDGE": PANEL_EDGE, "INSET": INSET, "SCRIM": SCRIM, "INK": INK,
		"BODY": BODY, "MUTED": MUTED, "DIM": DIM, "DISABLED": DISABLED, "AMBER": AMBER, "AMBER_FILL": AMBER_FILL,
		"ON_AMBER": ON_AMBER, "ACCENT": ACCENT, "ACCENT_EDGE": ACCENT_EDGE, "ACCENT_DEEP": ACCENT_DEEP, "TEAL": TEAL,
		"TEAL_BRIGHT": TEAL_BRIGHT, "TEAL_DEEP": TEAL_DEEP, "ALERT": ALERT, "STABLE": STABLE, "FIELD_EDGE": FIELD_EDGE,
		"KEYCAP_EDGE": KEYCAP_EDGE, "CORNER": CORNER, "EDGE_WIDTH": EDGE_WIDTH, "LABEL_TRACKING": LABEL_TRACKING,
	}


## The scheme a game id uses (unknown ids keep Last Route's).
static func scheme_for(game_id: String) -> String:
	return game_id if SCHEMES.has(game_id) else "last_route"


## Switch every token to a game's scheme; screens built afterwards read the new values. The game's Theme resource
## (button/panel/label variations) goes on the root window so shared scenes without their own theme follow too.
static func apply_scheme(game_id: String) -> void:
	_snapshot()
	var id := scheme_for(game_id)
	var values: Dictionary = _last_route_tokens.duplicate()
	var overrides: Dictionary = SCHEMES[id]
	for key in overrides:
		values[key] = overrides[key]
	for key in values:
		var value = values[key]
		if value is String:
			value = Color(String(value))
		_set_token(String(key), value)
	scheme_id = id
	_apply_window_theme(game_id)


static func _set_token(key: String, value) -> void:
	match key:
		"BACKDROP": BACKDROP = value
		"PANEL": PANEL = value
		"PANEL_EDGE": PANEL_EDGE = value
		"INSET": INSET = value
		"SCRIM": SCRIM = value
		"INK": INK = value
		"BODY": BODY = value
		"MUTED": MUTED = value
		"DIM": DIM = value
		"DISABLED": DISABLED = value
		"AMBER": AMBER = value
		"AMBER_FILL": AMBER_FILL = value
		"ON_AMBER": ON_AMBER = value
		"ACCENT": ACCENT = value
		"ACCENT_EDGE": ACCENT_EDGE = value
		"ACCENT_DEEP": ACCENT_DEEP = value
		"TEAL": TEAL = value
		"TEAL_BRIGHT": TEAL_BRIGHT = value
		"TEAL_DEEP": TEAL_DEEP = value
		"ALERT": ALERT = value
		"STABLE": STABLE = value
		"FIELD_EDGE": FIELD_EDGE = value
		"KEYCAP_EDGE": KEYCAP_EDGE = value
		"CORNER": CORNER = int(value)
		"EDGE_WIDTH": EDGE_WIDTH = int(value)
		"LABEL_TRACKING": LABEL_TRACKING = int(value)


## The Theme a game puts on the root window: its own theme resource (buttons, cards, labels) plus a generated layer for the
## shared controls that theme does not define (sliders, tabs, checkboxes, scrollbars) so they stop falling back to Last
## Route's purple project theme. null for Last Route (it keeps the project theme).
static var _theme_cache := {}


static func theme_for(game_id: String) -> Theme:
	if scheme_for(game_id) == "last_route":
		return null
	var game := GameRegistry.get_game(game_id)
	if game.is_empty() or String(game.get("theme", "")).is_empty():
		return null
	var key := "%s|%s" % [game_id, str(ACCENT)]
	if _theme_cache.has(key):
		return _theme_cache[key]
	var theme := (load(String(game["theme"])) as Theme).duplicate() as Theme
	var line := panel_box(PANEL_EDGE, PANEL_EDGE, 0)
	line.content_margin_top = 2
	line.content_margin_bottom = 2
	var fill := panel_box(ACCENT, ACCENT, 0)
	fill.content_margin_top = 2
	fill.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", line)
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)
	for kind in ["selected", "unselected", "hovered", "disabled"]:
		var box := panel_box(ACCENT if kind == "selected" else (PANEL_EDGE if kind == "hovered" else PANEL),
			ACCENT_EDGE if kind == "selected" else PANEL_EDGE, 4)
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		theme.set_stylebox("tab_%s" % kind, "TabBar", box)
	theme.set_color("font_selected_color", "TabBar", ON_AMBER)
	theme.set_color("font_unselected_color", "TabBar", BODY)
	theme.set_color("font_hovered_color", "TabBar", INK)
	theme.set_color("font_disabled_color", "TabBar", DISABLED)
	theme.set_color("font_outline_color", "TabBar", Color(0, 0, 0, 0))
	for type_name in ["CheckBox", "CheckButton"]:
		theme.set_color("font_color", type_name, BODY)
		theme.set_color("font_hover_color", type_name, INK)
		theme.set_color("font_pressed_color", type_name, INK)
		theme.set_color("font_focus_color", type_name, INK)
	theme.set_stylebox("background", "ProgressBar", panel_box(INSET, PANEL_EDGE, 0))
	theme.set_stylebox("fill", "ProgressBar", panel_box(ACCENT, ACCENT, 0))
	theme.set_stylebox("scroll", "VScrollBar", panel_box(INSET, INSET, 0))
	theme.set_stylebox("grabber", "VScrollBar", panel_box(PANEL_EDGE, PANEL_EDGE, 0))
	theme.set_stylebox("grabber_highlight", "VScrollBar", panel_box(ACCENT, ACCENT, 0))
	theme.set_stylebox("grabber_pressed", "VScrollBar", panel_box(ACCENT_EDGE, ACCENT_EDGE, 0))
	_theme_cache[key] = theme
	return theme


static func _apply_window_theme(game_id: String) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null or loop.root == null:
		return
	loop.root.theme = theme_for(game_id)
