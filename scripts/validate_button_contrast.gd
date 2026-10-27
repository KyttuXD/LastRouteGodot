extends RefCounted

## Every button the player can see keeps a readable label in every state (normal / hover / pressed / hover_pressed / focus /
## disabled): the font colour needs at least 4.5:1 contrast against the box it is drawn on (3:1 for disabled, which is
## deliberately dim). The hub card's PLAY button lost its label on focus because the focus box was an opaque dark fill drawn
## over the light button. Checked on the real scenes (hub, Last Route menu, lobby, run report, admin menu) and on every Theme
## resource, so a new theme or a restyled button cannot bring it back.

const MIN_RATIO := 4.5
const MIN_RATIO_DISABLED := 3.0
const GROUND := Color("0d0810")
const STATES := [
	["normal", "font_color", MIN_RATIO],
	["hover", "font_hover_color", MIN_RATIO],
	["pressed", "font_pressed_color", MIN_RATIO],
	["hover_pressed", "font_hover_pressed_color", MIN_RATIO],
	["focus", "font_focus_color", MIN_RATIO],
	["disabled", "font_disabled_color", MIN_RATIO_DISABLED],
]
const THEMES := ["res://src/ui/theme_lastroute.tres", "res://src/ui/theme_nightwatch.tres", "res://src/ui/theme_city.tres",
	"res://src/ui/ref_theme.tres"]
const THEME_BUTTON_TYPES := ["Button", "PrimaryButton", "OptionButton", "CheckBox", "CheckButton"]

var _failures := 0
var _checked := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func luminance(color: Color) -> float:
	var parts := [color.r, color.g, color.b]
	var out := 0.0
	var weights := [0.2126, 0.7152, 0.0722]
	for i in 3:
		var v: float = parts[i]
		out += weights[i] * (v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4))
	return out


static func contrast(a: Color, b: Color) -> float:
	var la := luminance(a)
	var lb := luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


## The colour a state's box actually shows: its fill blended over the ground, or the underlying normal box when the state's
## box does not fill (the focus outline).
static func fill_of(box: StyleBox, underlying: Color) -> Color:
	if box is StyleBoxFlat:
		var flat := box as StyleBoxFlat
		if flat.draw_center and flat.bg_color.a > 0.0:
			var base := underlying
			return Color(base.r * (1.0 - flat.bg_color.a) + flat.bg_color.r * flat.bg_color.a,
				base.g * (1.0 - flat.bg_color.a) + flat.bg_color.g * flat.bg_color.a,
				base.b * (1.0 - flat.bg_color.a) + flat.bg_color.b * flat.bg_color.a)
		return underlying
	return underlying


func _check_button(button: Control, label: String) -> void:
	if button is Button and (button as Button).flat:
		return
	var normal_box := button.get_theme_stylebox("normal")
	var normal_fill := fill_of(normal_box, GROUND)
	for entry in STATES:
		var state: String = entry[0]
		var box := button.get_theme_stylebox(state)
		var fill: Color
		if state == "focus":
			fill = fill_of(box, normal_fill)
		else:
			fill = fill_of(box, GROUND)
		var font := button.get_theme_color(entry[1])
		var ratio := contrast(font, fill)
		_checked += 1
		_expect(ratio >= float(entry[2]), "%s %s: label %s on %s is %.1f:1 (needs %.1f)" % [
			label, state, font.to_html(false), fill.to_html(false), ratio, float(entry[2])])


func _check_scene_buttons(root: Node, scene_name: String) -> void:
	for node in root.find_children("*", "BaseButton", true, false):
		var control := node as Control
		if control is Button or control is CheckBox or control is CheckButton:
			if not control.is_visible_in_tree():
				continue
			_check_button(control, "%s/%s" % [scene_name, node.name])


func _check_theme(path: String, host: Node) -> void:
	if not ResourceLoader.exists(path):
		return
	var theme := load(path) as Theme
	if theme == null:
		return
	var holder := Button.new()
	holder.theme = theme
	host.add_child(holder)
	for type_name in THEME_BUTTON_TYPES:
		if not theme.has_stylebox("normal", type_name) and type_name != "Button":
			continue
		if type_name == "Button":
			continue
		holder.theme_type_variation = StringName(type_name) if type_name == "PrimaryButton" else &""
		_check_button(holder, "%s %s" % [path.get_file(), type_name])
	holder.theme_type_variation = &""
	_check_button(holder, "%s Button" % path.get_file())
	holder.free()


func run(host: Node) -> int:
	for path in THEMES:
		_check_theme(path, host)
	# the real scenes
	var scenes := {
		"game_hub": "res://scenes/game_hub.tscn", "main_menu": "res://scenes/main_menu.tscn",
		"room_lobby": "res://scenes/room_lobby.tscn", "run_report": "res://scenes/run_report.tscn",
		"city_menu": "res://scenes/city_menu.tscn",
	}
	for name in scenes:
		var path: String = scenes[name]
		if not ResourceLoader.exists(path):
			continue
		var scene := (load(path) as PackedScene).instantiate()
		host.add_child(scene)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		if scene is RunReport:
			(scene as RunReport).open({"online": false, "respawn": true, "title": "YOU DIED", "reason": "CAUGHT BY AKI"})
			await host.get_tree().process_frame
		_check_scene_buttons(scene, name)
		scene.queue_free()
		await host.get_tree().process_frame
	# the settings overlay and the admin menu are built into the menu / the run: check their buttons too
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	host.add_child(menu)
	await host.get_tree().process_frame
	var settings := menu.find_child("SettingsOverlay", true, false)
	if settings != null:
		(settings as Control).visible = true
		_check_scene_buttons(settings, "settings")
	menu.queue_free()
	var admin := AdminMenu.attach(host, func() -> String: return "ROUTE DEBUG", [], [])
	if admin != null:
		admin._set_open(true)
		await host.get_tree().process_frame
		_check_scene_buttons(admin, "admin_menu")
		admin._set_open(false)
	_expect(_checked > 100, "only %d button states were checked" % _checked)
	if _failures == 0:
		print("  button_contrast  %d button states readable (>= %.1f:1) across the hub, menus, settings, admin and all themes" % [_checked, MIN_RATIO])
	return _failures
