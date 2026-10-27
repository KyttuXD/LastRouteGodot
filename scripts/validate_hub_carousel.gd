extends RefCounted

## The hub's arrow carousel: at every window size KT uses (UI units come from the real expand-stretch rule) with 1, 3, 5 and
## 12 registered games, the focused card, both arrows, the stage, the indicator and the shared row all sit inside the
## viewport without overlapping; neighbours either peek whole or stay out of the stage; Left/Right/A/D/wheel/swipe/arrows
## step through the games and wrap; Enter launches the focused game (and nothing when it is locked); the last game played is
## the default focus.

const WINDOWS := {
	"1280x720": Vector2i(1280, 720), "1440x840": Vector2i(1440, 840), "1920x1080": Vector2i(1920, 1080),
	"2560x1440": Vector2i(2560, 1440), "ultrawide3440x1440": Vector2i(3440, 1440), "phone844x390": Vector2i(844, 390),
}
const COUNTS := [1, 3, 5, 12]
const EPS := 0.75

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## N synthetic games on the real themes (every fourth one locked, the first always launchable).
static func synthetic_games(count: int) -> Array:
	var themes := ["res://src/ui/theme_lastroute.tres", "res://src/ui/theme_nightwatch.tres"]
	if ResourceLoader.exists("res://src/ui/theme_city.tres"):
		themes.append("res://src/ui/theme_city.tres")
	var out := []
	for i in count:
		var locked := i % 4 == 3
		out.append({
			"id": "game_%d" % i, "title": "GAME NUMBER %d" % (i + 1), "kicker": "TEST // SLOT %d" % i,
			"tagline": "A test game with a tagline long enough to wrap onto a second line.",
			"scene": "res://scenes/main_menu.tscn", "theme": themes[i % themes.size()],
			"locked": locked, "locked_note": "TEST LOCK REASON" if locked else "",
		})
	return out


static func _rect_of(control: Control) -> Rect2:
	return control.get_global_transform() * Rect2(Vector2.ZERO, control.size)


static func _inside(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - EPS and rect.position.y >= bounds.position.y - EPS \
		and rect.end.x <= bounds.end.x + EPS and rect.end.y <= bounds.end.y + EPS


func _open_hub(host: Node, pixels: Vector2i, count: int) -> Array:
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	holder.gui_disable_input = false
	host.add_child(holder)
	GameRegistry.test_games = synthetic_games(count) if count > 0 else []
	var hub: Control = (load("res://scenes/game_hub.tscn") as PackedScene).instantiate()
	holder.add_child(hub)
	for _i in 5:
		await host.get_tree().process_frame
	return [holder, hub, Rect2(Vector2.ZERO, Vector2(holder.size_2d_override))]


func _close_hub(host: Node, holder: SubViewport) -> void:
	holder.queue_free()
	await host.get_tree().process_frame


func _check_layout(host: Node, key: String, pixels: Vector2i, count: int) -> void:
	var opened: Array = await _open_hub(host, pixels, count)
	var holder: SubViewport = opened[0]
	var hub: Control = opened[1]
	var view: Rect2 = opened[2]
	var games := GameRegistry.all().size()
	var where := "%s with %d games" % [key, games]
	var stage := (hub as GameHub).stage_rect()
	_expect(_inside(stage, view), "%s: the stage %s leaves the viewport %s" % [where, stage, view])
	var focused := (hub as GameHub).card_for((hub as GameHub).focused_id())
	_expect(focused != null, "%s: no focused card" % where)
	if focused != null:
		var rect := _rect_of(focused)
		_expect(_inside(rect, view), "%s: the focused card %s leaves the viewport %s" % [where, rect, view])
		_expect(_inside(rect, stage), "%s: the focused card %s is clipped by the stage %s" % [where, rect, stage])
		_expect(rect.size.x >= 90.0, "%s: the focused card is unreadably small (%s)" % [where, rect.size])
		for id in (hub as GameHub).game_ids():
			var card := (hub as GameHub).card_for(String(id))
			if card == focused or not card.visible:
				continue
			var other := _rect_of(card)
			if (hub as GameHub).peeking():
				_expect(_inside(other, stage), "%s: neighbour %s is clipped by the stage" % [where, id])
				_expect(not other.intersects(rect), "%s: neighbour %s overlaps the focused card" % [where, id])
			else:
				_expect(not other.intersects(stage), "%s: neighbour %s shows without room (stage %s, card %s)" % [where, id, stage, other])
	for arrow_name in ["LeftArrow", "RightArrow"]:
		var arrow := hub.find_child(arrow_name, true, false) as Button
		_expect(arrow != null, "%s: %s is missing" % [where, arrow_name])
		if arrow != null:
			_expect(arrow.visible == (games > 1), "%s: %s visibility is wrong" % [where, arrow_name])
			if arrow.visible:
				var arrow_rect := arrow.get_global_rect()
				_expect(_inside(arrow_rect, view), "%s: %s %s leaves the viewport" % [where, arrow_name, arrow_rect])
				_expect(not arrow_rect.intersects(stage), "%s: %s overlaps the stage" % [where, arrow_name])
				_expect(arrow_rect.size.x >= 16.0 and arrow_rect.size.y >= 30.0, "%s: %s is too small to hit" % [where, arrow_name])
	for shared in ["HubTitle", "HubSignedIn", "HubKicker", "HubIndicator", "AccountButton", "SettingsButton", "AdminButton", "QuitButton"]:
		var node := hub.find_child(shared, true, false) as Control
		if node != null and node.visible:
			_expect(_inside(node.get_global_rect(), view), "%s: %s %s leaves the viewport" % [where, shared, node.get_global_rect()])
	var count_label := hub.find_child("HubCount", true, false) as Label
	_expect(count_label != null and (count_label.text == "" if games == 1 else count_label.text.begins_with("1 /")),
		"%s: the position indicator reads '%s'" % [where, count_label.text if count_label != null else "?"])
	await _close_hub(host, holder)


func _step_key(hub: GameHub, keycode: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	hub._input(event)


func _check_navigation(host: Node) -> void:
	var was_reduced := Settings.reduced_motion
	Settings.reduced_motion = true
	var old_last := Settings.hub_last_game
	Settings.hub_last_game = ""
	for count in [3, 5]:
		var opened: Array = await _open_hub(host, Vector2i(1920, 1080), count)
		var holder: SubViewport = opened[0]
		var hub := opened[1] as GameHub
		var where := "navigation with %d games" % count
		_expect(hub.focused_index() == 0 and hub.focused_id() == "game_0", "%s: did not open on the first game" % where)
		hub.step(1)
		_expect(hub.focused_id() == "game_1", "%s: step right did not reach game_1 (%s)" % [where, hub.focused_id()])
		hub.step(-1)
		hub.step(-1)
		_expect(hub.focused_id() == "game_%d" % (count - 1), "%s: step left from the first game did not wrap to the last (%s)" % [where, hub.focused_id()])
		hub.step(1)
		_expect(hub.focused_id() == "game_0", "%s: step right from the last game did not wrap to the first" % where)
		for _i in count:
			hub.step(1)
		_expect(hub.focused_id() == "game_0", "%s: %d steps right did not come back to the start" % [where, count])
		# keyboard, arrows, wheel, swipe
		_step_key(hub, KEY_D)
		_expect(hub.focused_id() == "game_1", "%s: D did not step right" % where)
		_step_key(hub, KEY_A)
		_expect(hub.focused_id() == "game_0", "%s: A did not step left" % where)
		var left_arrow := hub.find_child("LeftArrow", true, false) as Button
		var right_arrow := hub.find_child("RightArrow", true, false) as Button
		right_arrow.pressed.emit()
		_expect(hub.focused_id() == "game_1", "%s: the right arrow did not step right" % where)
		left_arrow.pressed.emit()
		_expect(hub.focused_id() == "game_0", "%s: the left arrow did not step left" % where)
		var centre := hub.stage_rect().get_center()
		var wheel := InputEventMouseButton.new()
		wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
		wheel.pressed = true
		wheel.position = centre
		hub._input(wheel)
		_expect(hub.focused_id() == "game_1", "%s: the wheel down did not step right" % where)
		var press := InputEventMouseButton.new()
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		press.position = centre
		hub._input(press)
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		release.position = centre + Vector2(40, 2)
		hub._input(release)
		_expect(hub.focused_id() == "game_0", "%s: a swipe right did not bring the previous game back" % where)
		# a click on a peeking neighbour selects it
		if hub.peeking():
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			hub._on_card_input(click, "game_1")
			_expect(hub.focused_id() == "game_1", "%s: clicking the neighbour did not select it" % where)
		# Enter launches the focused game; a locked one launches nothing
		var launched := []
		GameHub.launch_override = func(id: String) -> void: launched.append(id)
		hub.select(0)
		hub.get_viewport().gui_release_focus()
		var accept := InputEventAction.new()
		accept.action = "ui_accept"
		accept.pressed = true
		hub._input(accept)
		_expect(launched == ["game_0"], "%s: Enter on game_0 launched %s" % [where, launched])
		_expect(Settings.hub_last_game == "game_0", "%s: the launched game was not remembered" % where)
		if count > 3:
			hub.select(3)
			hub.get_viewport().gui_release_focus()
			var before := launched.size()
			hub._input(accept)
			_expect(launched.size() == before, "%s: a locked game launched" % where)
			var locked_button := hub.find_child("Launch_game_3", true, false) as Button
			_expect(locked_button != null and locked_button.disabled and locked_button.text == "LOCKED", "%s: the locked game's PLAY does not say LOCKED" % where)
			_expect(hub.find_child("LockedNote", true, false) != null, "%s: a locked game shows no reason" % where)
		GameHub.launch_override = Callable()
		await _close_hub(host, holder)
	# the last game played is the default focus
	Settings.hub_last_game = "game_2"
	var reopened: Array = await _open_hub(host, Vector2i(1280, 720), 5)
	_expect((reopened[1] as GameHub).focused_id() == "game_2", "the hub did not open on the last game played (%s)" % (reopened[1] as GameHub).focused_id())
	await _close_hub(host, reopened[0])
	Settings.hub_last_game = "no_such_game"
	reopened = await _open_hub(host, Vector2i(1280, 720), 3)
	_expect((reopened[1] as GameHub).focused_index() == 0, "an unknown remembered game did not fall back to the first")
	await _close_hub(host, reopened[0])
	Settings.reduced_motion = was_reduced
	Settings.hub_last_game = old_last


## The keyboard path: Left/Right on a focused PLAY button change the game and the focus follows to the new PLAY button
## (or the stage when that game is locked); Down reaches the shared row, Up comes back; Enter launches.
func _check_keyboard(host: Node) -> void:
	var was_reduced := Settings.reduced_motion
	Settings.reduced_motion = true
	Settings.hub_last_game = ""
	var opened: Array = await _open_hub(host, Vector2i(1280, 720), 5)
	var holder: SubViewport = opened[0]
	var hub := opened[1] as GameHub
	var play := hub.find_child("Launch_game_0", true, false) as Button
	_expect(hub.get_viewport().gui_get_focus_owner() == play, "keyboard: the first PLAY button does not hold the focus on open")
	var accept := InputEventAction.new()
	accept.action = "ui_accept"
	accept.pressed = true
	for step in [["ui_right", "game_1"], ["ui_right", "game_2"], ["ui_left", "game_1"], ["ui_left", "game_0"], ["ui_left", "game_4"]]:
		var event := InputEventAction.new()
		event.action = step[0]
		event.pressed = true
		hub._input(event)
		_expect(hub.focused_id() == step[1], "keyboard: %s did not reach %s (%s)" % [step[0], step[1], hub.focused_id()])
		var owner := hub.get_viewport().gui_get_focus_owner()
		var expected := hub.find_child("Launch_%s" % step[1], true, false) as Button
		_expect(owner == expected, "keyboard: after %s the focus is on %s, not on the %s PLAY button" % [step[0], owner, step[1]])
	hub.select(0)
	play = hub.find_child("Launch_game_0", true, false) as Button
	play.grab_focus()
	var account := hub.find_child("AccountButton", true, false) as Control
	_expect(play.find_valid_focus_neighbor(SIDE_BOTTOM) == account, "keyboard: Down from PLAY does not reach the shared row")
	_expect(account.find_valid_focus_neighbor(SIDE_TOP) == play, "keyboard: Up from the shared row does not come back to PLAY")
	_expect(play.find_valid_focus_neighbor(SIDE_LEFT) == play and play.find_valid_focus_neighbor(SIDE_RIGHT) == play,
		"keyboard: Left/Right can leave the carousel through focus navigation")
	var launched := []
	GameHub.launch_override = func(id: String) -> void: launched.append(id)
	play.pressed.emit()
	_expect(launched == ["game_0"], "keyboard: PLAY pressed launched %s" % [launched])
	GameHub.launch_override = Callable()
	# every PLAY button keeps one label colour and an outline-only focus box
	for id in hub.game_ids():
		var button := hub.find_child("Launch_%s" % id, true, false) as Button
		var focus := button.get_theme_stylebox("focus") as StyleBoxFlat
		_expect(focus != null and not focus.draw_center, "%s: the PLAY focus box fills the button" % id)
		for pair in [["normal", "font_color"], ["hover", "font_hover_color"], ["pressed", "font_pressed_color"],
				["hover_pressed", "font_hover_pressed_color"]]:
			var fill := (button.get_theme_stylebox(pair[0]) as StyleBoxFlat).bg_color
			var ratio := GameHub._ratio(button.get_theme_color(pair[1]), fill)
			_expect(ratio >= 4.5, "%s: PLAY %s label is %.2f:1 on its fill" % [id, pair[0], ratio])
		var focus_label := button.get_theme_color("font_focus_color")
		var normal_fill := (button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color
		_expect(GameHub._ratio(focus_label, normal_fill) >= 4.5, "%s: PLAY focus label is unreadable" % id)
	await _close_hub(host, holder)
	Settings.reduced_motion = was_reduced


func run(host: Node) -> int:
	var old_last := Settings.hub_last_game
	Settings.hub_last_game = ""
	for key in WINDOWS:
		for count in COUNTS:
			await _check_layout(host, key, WINDOWS[key], count)
	await _check_navigation(host)
	await _check_keyboard(host)
	# the real registry also lays out cleanly at the smallest window
	GameRegistry.test_games = []
	await _check_layout(host, "real registry 1280x720", Vector2i(1280, 720), 0)
	GameRegistry.test_games = []
	Settings.hub_last_game = old_last
	if _failures == 0:
		print("  hub_carousel  6 window sizes x 1/3/5/12 games: card, arrows, stage and shared row inside the viewport; wrap, keys, wheel, swipe, Enter, last played")
	return _failures
