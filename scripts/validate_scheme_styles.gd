extends RefCounted

## Last Route and the City dress the SHARED screens in their own colour scheme (Palette.apply_scheme, driven by
## GameRegistry.active_game_id). For each scheme this opens the settings overlay, pause menu, account panel, room lobby, the
## results/death screen and the HUD frames and checks: the two schemes' tokens differ (and the shared screens actually
## render with the active scheme's colours, not the other game's), every text/background pair keeps its contrast, and
## Last Route's own colours come back when its scheme is re-applied.
##
##   godot --headless --path . res://scenes/validate.tscn -- scheme_styles

const SCHEMES := ["last_route", "city"]
## token pairs that carry text: [text, ground, minimum ratio]
const PAIRS := [
	["INK", "PANEL", 4.5], ["BODY", "PANEL", 4.5], ["MUTED", "PANEL", 4.5], ["AMBER", "PANEL", 4.5], ["TEAL", "PANEL", 4.5],
	["ALERT", "PANEL", 4.5], ["STABLE", "PANEL", 4.5], ["DISABLED", "PANEL", 3.0], ["INK", "INSET", 4.5], ["BODY", "INSET", 4.5],
	["AMBER", "INSET", 4.5], ["ON_AMBER", "ACCENT", 4.5], ["ON_AMBER", "AMBER_FILL", 4.5], ["INK", "ACCENT_DEEP", 4.5],
	["INK", "BACKDROP", 4.5], ["BODY", "BACKDROP", 4.5],
]
## tokens the two schemes must not share (the identity of each game's menus)
const MUST_DIFFER := ["BACKDROP", "PANEL", "PANEL_EDGE", "INSET", "ACCENT", "ACCENT_EDGE", "ACCENT_DEEP", "AMBER", "TEAL", "CORNER"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _luminance(color: Color) -> float:
	var channels := []
	for value in [color.r, color.g, color.b]:
		channels.append(value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## Every colour a screen draws with: the style boxes and font colours its controls resolve (theme + overrides).
static func colours_in(root: Node) -> Dictionary:
	var found := {}
	var controls: Array = root.find_children("*", "Control", true, false)
	controls.append(root)
	for node in controls:
		var control := node as Control
		if control == null:
			continue
		for style_name in ["normal", "hover", "pressed", "focus", "panel", "disabled"]:
			var box := control.get_theme_stylebox(style_name) as StyleBoxFlat
			if box != null:
				found[box.bg_color.to_html(false)] = true
				found[box.border_color.to_html(false)] = true
		for color_name in ["font_color", "font_hover_color", "font_pressed_color"]:
			found[control.get_theme_color(color_name).to_html(false)] = true
	return found


func _check_tokens() -> void:
	var seen := {}
	for scheme in SCHEMES:
		Palette.apply_scheme(scheme)
		seen[scheme] = Palette.tokens()
		_expect(Palette.scheme_id == scheme, "apply_scheme(%s) left the scheme at %s" % [scheme, Palette.scheme_id])
		for pair in PAIRS:
			var ratio := _contrast(seen[scheme][pair[0]], seen[scheme][pair[1]])
			_expect(ratio >= float(pair[2]), "%s: %s on %s is %.2f:1 (< %.1f)" % [scheme, pair[0], pair[1], ratio, float(pair[2])])
	for token in MUST_DIFFER:
		_expect(seen["last_route"][token] != seen["city"][token], "the schemes share %s (%s)" % [token, seen["last_route"][token]])
	var differing := 0
	for token in seen["city"]:
		if seen["city"][token] != seen["last_route"][token]:
			differing += 1
	_expect(differing >= 18, "only %d tokens differ between Last Route and the City" % differing)
	Palette.apply_scheme("city")
	_expect(Palette.theme_for("city") != null and Palette.theme_for("last_route") == null, "the City must carry a window theme, Last Route none")
	var city_theme := Palette.theme_for("city")
	if city_theme != null:
		_expect(city_theme.get_stylebox("grabber_area", "HSlider") != null and city_theme.has_stylebox("tab_selected", "TabBar"),
			"the City theme does not restyle sliders and tabs")
	# Night Watch has its own scheme for the shared screens that run inside it: readable pairs, and not Last Route's purple
	Palette.apply_scheme("night_watch")
	var nw := Palette.tokens()
	_expect(Palette.scheme_for("night_watch") == "night_watch" and Palette.theme_for("night_watch") != null, "night_watch lost its scheme or window theme")
	for pair in PAIRS:
		var ratio := _contrast(nw[pair[0]], nw[pair[1]])
		_expect(ratio >= float(pair[2]), "night_watch: %s on %s is %.2f:1 (< %.1f)" % [pair[0], pair[1], ratio, float(pair[2])])
	_expect(nw["PANEL"] != seen["last_route"]["PANEL"] and nw["ACCENT"] != seen["last_route"]["ACCENT"], "the night_watch scheme is Last Route's")
	Palette.apply_scheme("last_route")


## Build one shared screen under a scheme and return the colours it draws with.
func _screen(host: Node, name: String) -> Node:
	var node: Node
	match name:
		"settings":
			var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
			host.add_child(menu)
			await host.get_tree().process_frame
			node = menu.find_child("SettingsOverlay", true, false)
			(node as Control).visible = true
			node.set_meta("owner_scene", menu)
		"pause":
			node = PauseMenu.new()
			host.add_child(node)
			await host.get_tree().process_frame
			(node as PauseMenu).open()
		"account":
			node = AccountPanel.open(host)
		"lobby":
			node = (load("res://scenes/room_lobby.tscn") as PackedScene).instantiate()
			host.add_child(node)
		"results":
			node = (load("res://scenes/run_report.tscn") as PackedScene).instantiate()
			host.add_child(node)
			await host.get_tree().process_frame
			(node as RunReport).open({"online": false, "respawn": true, "title": "YOU DIED", "reason": "CAUGHT BY AKI"})
		"hud":
			node = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
			host.add_child(node)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	return node


func _dispose(host: Node, node: Node) -> void:
	if node is PauseMenu:
		(node as PauseMenu).close()
	var owner_scene: Node = node.get_meta("owner_scene") if node.has_meta("owner_scene") else node
	owner_scene.queue_free()
	await host.get_tree().process_frame


func _check_screens(host: Node) -> void:
	var screens := ["settings", "pause", "account", "lobby", "results", "hud"]
	var palettes := {}   # screen -> scheme -> colours
	for scheme in SCHEMES:
		GameRegistry.active_game_id = scheme
		for name in screens:
			var node: Node = await _screen(host, name)
			if node == null:
				_expect(false, "%s did not open under %s" % [name, scheme])
				continue
			if not palettes.has(name):
				palettes[name] = {}
			palettes[name][scheme] = colours_in(node)
			await _dispose(host, node)
	GameRegistry.active_game_id = "last_route"
	Palette.apply_scheme("last_route")
	var tokens_last := Palette.tokens()
	Palette.apply_scheme("city")
	var tokens_city := Palette.tokens()
	Palette.apply_scheme("last_route")
	for name in screens:
		if not palettes.has(name) or palettes[name].size() < 2:
			continue
		var last: Dictionary = palettes[name]["last_route"]
		var city: Dictionary = palettes[name]["city"]
		var differ := 0
		for hex in city:
			if not last.has(hex):
				differ += 1
		_expect(differ >= 3, "%s: only %d colours differ between Last Route and the City" % [name, differ])
		# the City's primary action and panel never show up in Last Route's screen, nor Last Route's in the City's
		for token in ["ACCENT", "PANEL"]:
			var city_hex: String = (tokens_city[token] as Color).to_html(false)
			var last_hex: String = (tokens_last[token] as Color).to_html(false)
			_expect(not last.has(city_hex), "%s under Last Route draws the City's %s %s" % [name, token, city_hex])
			if name != "settings" and name != "hud":
				_expect(not city.has(last_hex), "%s under the City still draws Last Route's %s %s" % [name, token, last_hex])


func run(host: Node) -> int:
	var old_game := GameRegistry.active_game_id
	_check_tokens()
	await _check_screens(host)
	# Last Route's tokens come back exactly
	Palette.apply_scheme("last_route")
	_expect(Palette.ACCENT == Color("a67fb0") and Palette.PANEL == Color("170e19") and Palette.CORNER == 0,
		"Last Route's own palette did not come back after the City's")
	GameRegistry.active_game_id = old_game
	if _failures == 0:
		print("  scheme    Last Route and City tokens differ, keep contrast, and shared screens draw with the active scheme")
	return _failures
