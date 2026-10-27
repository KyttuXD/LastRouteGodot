extends Node

## City navigation round trips with real scene changes (the validate suite cannot swap its own scene):
##   godot --headless --path . res://scenes/city_nav_test.tscn
## hub -> City menu -> back to games, twice; then City menu -> a real City run -> leave (solo) -> City menu -> back to
## games -> hub; then a staged City room: lobby -> back lands on the City menu; and Last Route's own lobby still lands on
## the hub. Checks the scene at each step, the City wording of the screens, and that nodes do not leak.

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
	if not _driver:
		var driver := Node.new()
		driver.name = "CityNavDriver"
		driver.set_script(get_script())
		driver.set("_driver", true)
		get_tree().root.add_child.call_deferred(driver)
		return
	await _settle(5)
	await _go(GameRegistry.HUB_SCENE)
	_expect(_scene_name() == "game_hub.tscn", "did not boot to the hub")
	var baseline_nodes := -1
	for trip in 2:
		await _press("Launch_city")
		_expect(_scene_name() == "city_menu.tscn", "the City card did not open the City menu (%s)" % _scene_name())
		await _press("BackToGamesButton")
		_expect(_scene_name() == "game_hub.tscn", "BACK TO GAMES did not return to the hub (%s)" % _scene_name())
		await _settle(10)
		var nodes := get_tree().get_node_count()
		if baseline_nodes < 0:
			baseline_nodes = nodes
		else:
			_expect(nodes <= baseline_nodes + 8, "node count grew from %d to %d after a City menu round trip" % [baseline_nodes, nodes])
	# a real solo City run, left from the run scene
	await _press("Launch_city")
	RoomState.create_local(RoomState.Mode.CITY)
	await _go(RoomState.CITY_ROUTE_SCENE)
	_expect(_scene_name() == "city_route.tscn", "the City run scene did not load (%s)" % _scene_name())
	await _settle(30)
	var hud_label := get_tree().current_scene.get_node("%HUD").find_child("DepthLabel", true, false) as Label
	_expect(hud_label == null or hud_label.text.begins_with("THE CITY"), "the HUD still shows maze wording: %s" % (hud_label.text if hud_label != null else ""))
	get_tree().current_scene.call("_leave_test")
	await _settle(30)
	_expect(_scene_name() == "city_menu.tscn", "leaving a solo City run did not return to the City menu (%s)" % _scene_name())
	await _press("BackToGamesButton")
	_expect(_scene_name() == "game_hub.tscn", "BACK TO GAMES did not return to the hub after a run (%s)" % _scene_name())
	# a staged City room: the lobby's back button lands on the City menu
	RoomState.create_local(RoomState.Mode.CITY)
	await _go("res://scenes/room_lobby.tscn")
	await _press("BackToMenuButton")
	_expect(_scene_name() == "city_menu.tscn", "the City lobby's back button did not return to the City menu (%s)" % _scene_name())
	_expect(RoomState.menu_scene_path() == RoomState.CITY_MENU_SCENE or RoomState.mode == RoomState.Mode.DEFAULT, "menu path is not the City menu")
	# the end-of-run report in a City run says CITY, not ROUTE
	RoomState.create_local(RoomState.Mode.CITY)
	var report_scene := (load("res://scenes/run_report.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(report_scene)
	await _settle(3)
	report_scene.call("open", {"depth": 1, "score": 0, "relays": 0, "relay_target": 0, "coins": 0, "seed": "X"})
	var texts := ""
	for label in report_scene.find_children("*", "Label", true, false):
		texts += (label as Label).text + "|"
	for button in report_scene.find_children("*", "Button", true, false):
		texts += (button as Button).text + "|"
	_expect(texts.contains("RUN ENDED") and texts.contains("CITY MENU") and not texts.contains("MAIN MENU"),
		"the City run report still has Last Route wording: %s" % texts)
	report_scene.queue_free()
	# Last Route keeps its own behaviour
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.menu_scene_path() == GameRegistry.HUB_SCENE, "Last Route's exit is not the hub")
	_expect(not GameState.game_over and not get_tree().paused, "game state leaked into the hub")
	await _settle(20)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	_expect(orphans < 60, "%d orphan nodes after the City round trips" % int(orphans))
	print("city_nav_flow  %s" % ("hub -> City menu -> hub x2, run -> City menu, lobby -> City menu, wording, no leaks" if _failures == 0 else "FAILED"))
	get_tree().quit(1 if _failures > 0 else 0)
