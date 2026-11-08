extends SceneTree

## Regenerates the per-game Theme resources the hub uses:
##   godot --headless --path . -s tools/build_game_themes.gd
## theme_lastroute.tres follows Palette (violet/amber on near-black); theme_nightwatch.tres follows the Night Watch web
## build (warm paper ink, dim stone, red accent, amber highlights on black).

const THEMES := {
	"res://game/ui_common/theme_lastroute.tres": {
		"ground": "0d0810", "panel": "170e19", "edge": "2e1f33", "ink": "f2ede1", "body": "bcb3a8", "muted": "8c817e",
		"accent": "a67fb0", "accent_edge": "c4a2d0", "kicker": "c9a9d8", "on_accent": "1a0f14", "alert": "e2515d",
	},
	"res://game/night_watch/theme_nightwatch.tres": {
		"ground": "050403", "panel": "0f0d0a", "edge": "2a2620", "ink": "e8e2d0", "body": "b8b19c", "muted": "8a8472",
		"accent": "c4302b", "accent_edge": "e0b04a", "kicker": "e0b04a", "on_accent": "f6f0e2", "alert": "c4302b", "dark_hover": true,
	},
}


func _box(fill: Color, edge: Color, pad_x: int, pad_y: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


func _init() -> void:
	for path in THEMES:
		var c: Dictionary = THEMES[path]
		var theme := Theme.new()
		theme.set_default_font_size(8)
		theme.set_color("font_color", "Label", Color(c["body"]))
		theme.set_stylebox("panel", "PanelContainer", _box(Color(c["panel"]), Color(c["edge"]), 8, 8))
		for button_state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var fill := Color(c["panel"])
			var edge := Color(c["edge"])
			match button_state:
				"hover":
					fill = fill.lightened(0.12)
					edge = Color(c["accent_edge"])
				"pressed", "hover_pressed":
					fill = Color(c["accent"]).darkened(0.3)
				"disabled":
					fill = Color(c["ground"])
			theme.set_stylebox(button_state, "Button", _box(fill, edge, 8, 4))
		# The focus box is drawn ON TOP of the state's own box, so it must not fill: an opaque focus fill hid the label
		# (dark text on the dark fill) on a focused primary button.
		var focus := _box(Color(0, 0, 0, 0), Color(c["accent_edge"]), 8, 4)
		focus.draw_center = false
		focus.set_border_width_all(2)
		theme.set_stylebox("focus", "Button", focus)
		theme.set_color("font_color", "Button", Color(c["body"]))
		theme.set_color("font_hover_color", "Button", Color(c["ink"]))
		theme.set_color("font_focus_color", "Button", Color(c["ink"]))
		theme.set_color("font_pressed_color", "Button", Color(c["ink"]))
		theme.set_color("font_hover_pressed_color", "Button", Color(c["ink"]))
		theme.set_color("font_disabled_color", "Button", Color(c["muted"]))
		# variations used by the hub card
		theme.set_type_variation("GameCard", "PanelContainer")
		theme.set_stylebox("panel", "GameCard", _box(Color(c["panel"]), Color(c["accent"]), 10, 10))
		theme.set_type_variation("LockedGameCard", "PanelContainer")
		theme.set_stylebox("panel", "LockedGameCard", _box(Color(c["ground"]), Color(c["edge"]), 10, 10))
		theme.set_type_variation("KickerLabel", "Label")
		theme.set_color("font_color", "KickerLabel", Color(c["kicker"]))
		theme.set_font_size("font_size", "KickerLabel", 6)
		theme.set_type_variation("TitleLabel", "Label")
		theme.set_color("font_color", "TitleLabel", Color(c["ink"]))
		theme.set_font_size("font_size", "TitleLabel", 16)
		theme.set_type_variation("MutedLabel", "Label")
		theme.set_color("font_color", "MutedLabel", Color(c["muted"]))
		theme.set_font_size("font_size", "MutedLabel", 6)
		theme.set_type_variation("PrimaryButton", "Button")
		theme.set_stylebox("normal", "PrimaryButton", _box(Color(c["accent"]), Color(c["accent_edge"]), 8, 4))
		theme.set_stylebox("hover", "PrimaryButton", _box(Color(c["accent"]).darkened(0.12) if c.get("dark_hover", false) else Color(c["accent"]).lightened(0.12), Color(c["accent_edge"]), 8, 4))
		theme.set_stylebox("pressed", "PrimaryButton", _box(Color(c["accent"]).darkened(0.1), Color(c["accent_edge"]), 8, 4))
		theme.set_stylebox("hover_pressed", "PrimaryButton", _box(Color(c["accent"]).darkened(0.1), Color(c["accent_edge"]), 8, 4))
		theme.set_stylebox("disabled", "PrimaryButton", _box(Color(c["ground"]), Color(c["edge"]), 8, 4))
		theme.set_stylebox("focus", "PrimaryButton", focus)
		for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color"]:
			theme.set_color(color_name, "PrimaryButton", Color(c["on_accent"]))
		theme.set_color("font_disabled_color", "PrimaryButton", Color(c["muted"]))
		var err := ResourceSaver.save(theme, path)
		print("%s %s" % [path, "saved" if err == OK else "ERROR %d" % err])
	quit()
