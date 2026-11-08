extends Node

## Navigation round trips with real scene changes (the validate suite cannot swap its own scene):
##   godot --headless --path . res://tests/scenes/hub_nav_test.tscn
## With GameRegistry.SKIP_HUB off: boot on the hub -> Last Route menu -> back to games, twice. With it on: boot on the Last Route
## menu, QUIT asks (NO and Esc close it). Then menu -> solo lobby -> a real route -> leave -> lobby -> back to the menu.
## Checks the current scene each step, that nothing quits the app by itself, and that
## orphan nodes and the node count do not grow between round trips.

var _failures := 0
var _driver := false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _scene_name() -> String:
	var scene := get_tree().current_scene
	return scene.scene_file_path.get_file() if scene != null else ""


func _settle(frames: int = 12) -> void:
	for _i in frames:
		await get_tree().process_frame


func _go(path: String) -> void:
	get_tree().change_scene_to_file(path)
	await _settle(20)


func _press(node_name: String) -> void:
	var button := get_tree().current_scene.find_child(node_name, true, false) as Button
	_expect(button != null and not button.disabled, "%s missing or disabled on %s" % [node_name, _scene_name()])
	if button != null:
		button.pressed.emit()
	await _settle(25)


func _ready() -> void:
	# The scene this script sits in is replaced by the first change_scene: drive from a node under the root instead.
	if not _driver:
		var driver := Node.new()
		driver.name = "HubNavDriver"
		driver.set_script(get_script())
		driver.set("_driver", true)
		get_tree().root.add_child.call_deferred(driver)
		return
	await _settle(5)
	# pass 1: GameRegistry.SKIP_HUB off = the hub is the main menu (today's flow)
	GameRegistry.skip_hub_override = 0
	await _go(GameRegistry.landing_scene())
	_expect(_scene_name() == "game_hub.tscn", "did not boot to the hub with the switch off (%s)" % _scene_name())
	var baseline_nodes := -1
	for trip in 2:
		await _press("Launch_last_route")
		_expect(_scene_name() == "main_menu.tscn", "PLAY did not open the Last Route menu (%s)" % _scene_name())
		await _press("QuitButton")
		_expect(_scene_name() == "game_hub.tscn", "the menu's last button did not return to the hub (%s)" % _scene_name())
		await _settle(10)
		var nodes := get_tree().get_node_count()
		if baseline_nodes < 0:
			baseline_nodes = nodes
		else:
			_expect(nodes <= baseline_nodes + 8, "node count grew from %d to %d after a menu round trip" % [baseline_nodes, nodes])
	# Esc on the hub leaves it where it is
	await _escape()
	_expect(_scene_name() == "game_hub.tscn", "Esc on the hub left it")

	# pass 2: the hub skipped (one unlocked game) = boot lands on the Last Route menu, whose QUIT asks before it quits
	GameRegistry.skip_hub_override = 1
	await _go(GameRegistry.landing_scene())
	_expect(_scene_name() == "main_menu.tscn", "did not boot to the Last Route menu with the hub skipped (%s)" % _scene_name())
	baseline_nodes = -1
	for trip in 2:
		var quit_button := get_tree().current_scene.find_child("QuitButton", true, false) as Button
		_expect(quit_button != null and quit_button.text == "QUIT", "the skipped-hub menu has no QUIT button")
		# never press YES: it quits this process
		await _press("QuitButton")
		_expect(_scene_name() == "main_menu.tscn", "QUIT left the menu without asking (%s)" % _scene_name())
		_expect(get_tree().current_scene.find_child("QuitDialog", true, false) != null, "QUIT did not ask")
		await _press("QuitNoButton")
		await _settle(5)
		_expect(_scene_name() == "main_menu.tscn" and get_tree().current_scene.find_child("QuitDialog", true, false) == null,
			"NO did not close the quit question")
		await _press("QuitButton")
		await _escape()
		_expect(_scene_name() == "main_menu.tscn" and get_tree().current_scene.find_child("QuitDialog", true, false) == null,
			"Esc did not close the quit question (or left the menu)")
		var nodes := get_tree().get_node_count()
		if baseline_nodes < 0:
			baseline_nodes = nodes
		else:
			_expect(nodes <= baseline_nodes + 8, "node count grew from %d to %d after a quit question round trip" % [baseline_nodes, nodes])
	# a real solo route and back out through the lobby
	RoomState.create_local(RoomState.Mode.DEFAULT)
	await _go("res://game/infinite_route/infinite_route_test.tscn")
	_expect(_scene_name() == "infinite_route_test.tscn", "the route scene did not load (%s)" % _scene_name())
	await _settle(30)
	get_tree().current_scene.call("_leave_test")
	await _settle(30)
	_expect(_scene_name() == "room_lobby.tscn", "leaving a solo route did not return to the lobby (%s)" % _scene_name())
	await _press("BackToMenuButton")
	_expect(_scene_name() == "main_menu.tscn", "the lobby's back button did not return to the Last Route menu (%s)" % _scene_name())
	_expect(Settings.hub_last_game == "last_route", "the hub would not open on the Last Route card")
	_expect(not GameState.game_over and not get_tree().paused, "game state leaked into the hub")
	GameRegistry.skip_hub_override = -1
	await _settle(20)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_expect(orphans < 40, "%d orphan nodes after the round trips" % int(orphans))
	print("hub_nav  %s" % ("hub -> menu -> hub x2, Esc stays; hub skipped: boot -> menu, QUIT asks, NO/Esc close; route -> lobby -> Last Route menu, no leaks" if _failures == 0 else "FAILED"))
	get_tree().quit(1 if _failures > 0 else 0)


func _escape() -> void:
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	Input.parse_input_event(escape)
	await _settle(5)
