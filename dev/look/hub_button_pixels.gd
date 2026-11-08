extends Node

## RENDERED check of the hub's PLAY buttons: for every registered game (plus synthetic games on every theme, one of them
## locked) and every state (normal, hover, pressed, focus, focus+hover, disabled) the button is drawn by a real renderer and the
## label colour is measured against the fill colour from the actual pixels: contrast >= 4.5:1 (3:1 for the locked one).
## Needs a real display (needs a real display): godot --path . res://dev/look/hub_button_pixels.tscn
##   godot --path . res://dev/look/hub_button_pixels.tscn -- [OUTDIR]   (writes one PNG per game and state when given)
const MIN_RATIO := 4.5
const MIN_RATIO_LOCKED := 3.0
const STATES := ["normal", "hover", "pressed", "focus", "focus_hover", "disabled"]

var _failures := 0
var _checked := 0


func _ready() -> void:
	Build.capture_rig = true
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else ""
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
	GameHub.launch_override = func(_id: String) -> void: pass   # releasing a "pressed" capture must not leave the hub
	var synthetic: Array = load("res://tests/validate_hub_carousel.gd").synthetic_games(5)
	var batches := [[], synthetic]   # [] = the real registry
	for games in batches:
		GameRegistry.test_games = games
		var ids: Array = []
		for game in GameRegistry.all():
			ids.append(String(game["id"]))
		for id in ids:
			await _check_game(id, out)
	GameRegistry.test_games = []
	print("hub_button_pixels: %d renders checked, %d failures" % [_checked, _failures])
	get_tree().quit(1 if _failures > 0 else 0)


static func _luminance(color: Color) -> float:
	var channels := []
	for value in [color.r, color.g, color.b]:
		channels.append(value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


static func _contrast(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _check_game(id: String, out: String) -> void:
	var pixels := Vector2i(1280, 720)
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://tests/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(holder)
	var old_last := Settings.hub_last_game
	Settings.hub_last_game = id
	var hub := (load("res://game/menus/game_hub.tscn") as PackedScene).instantiate() as GameHub
	holder.add_child(hub)
	for _i in 10:
		await get_tree().process_frame
	var button := hub.find_child("Launch_%s" % id, true, false) as Button
	var scale := float(pixels.x) / units.x
	for state in STATES:
		if (state == "disabled") != button.disabled:
			continue
		button.release_focus()
		_move_mouse(holder, Vector2(2, 2))
		await get_tree().process_frame
		var centre := button.get_global_rect().get_center()
		if state in ["hover", "focus_hover", "pressed"]:
			_move_mouse(holder, centre)
		if state in ["focus", "focus_hover"]:
			button.grab_focus()
		if state == "pressed":
			var press := InputEventMouseButton.new()
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			press.position = centre
			holder.push_input(press, true)
		for _i in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var image := holder.get_texture().get_image()
		if state in ["hover", "focus_hover"] and not button.is_hovered():
			print("  FAIL  %s %s: the pointer did not register as hovering" % [id, state])
			_failures += 1
		_measure(id, state, image, button.get_global_rect(), scale, button.disabled)
		if not out.is_empty():
			image.save_png("%s/play_%s_%s.png" % [out, id, state])
		if state == "pressed":
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			release.position = Vector2(2, 2)
			holder.push_input(release, true)
	Settings.hub_last_game = old_last
	holder.queue_free()
	await get_tree().process_frame


func _move_mouse(holder: SubViewport, at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	motion.global_position = at
	holder.push_input(motion, true)


## Fill = the most common colour inside the button (inset past the border and focus outline); label = the pixel furthest
## from it in luminance.
func _measure(id: String, state: String, image: Image, rect: Rect2, scale: float, locked: bool) -> void:
	var inset := 10
	var box := Rect2i(Vector2i((rect.position * scale).round()), Vector2i((rect.size * scale).round())).grow(-inset)
	box = box.intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	if box.size.x < 8 or box.size.y < 6:
		print("  FAIL  %s %s: button region is too small to measure (%s)" % [id, state, box])
		_failures += 1
		return
	var counts := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var key := image.get_pixel(x, y).to_html(false)
			counts[key] = int(counts.get(key, 0)) + 1
	var fill := Color.BLACK
	var best := 0
	for key in counts:
		if int(counts[key]) > best:
			best = int(counts[key])
			fill = Color(String(key))
	var label := fill
	var worst := -1.0
	for key in counts:
		var color := Color(String(key))
		var difference := absf(_luminance(color) - _luminance(fill))
		if difference > worst:
			worst = difference
			label = color
	var ratio := _contrast(fill, label)
	var minimum := MIN_RATIO_LOCKED if locked else MIN_RATIO
	_checked += 1
	if ratio < minimum:
		print("  FAIL  %s %s: PLAY label %s on fill %s is %.2f:1 (< %.1f)" % [id, state, label.to_html(false), fill.to_html(false), ratio, minimum])
		_failures += 1
