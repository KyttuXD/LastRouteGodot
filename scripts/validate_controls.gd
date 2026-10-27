extends RefCounted

## Controls are game-aware (docs/CONTROLS.md): Last Route's settings show MOVEMENT / ACTIONS / SYSTEM only, office controls
## belong to Night Watch's own tab, no action sits on two tabs, every rebindable action has an owner (nothing falls under
## OTHER), and a saved office rebind still round-trips through the settings file.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	# registry shape
	var owner_of := {}
	for game_id in ControlsRegistry.game_ids():
		var seen_in_game := {}
		for tab in ControlsRegistry.tabs_for(game_id):
			for action in tab["actions"]:
				_expect(not seen_in_game.has(action), "%s lists %s on two tabs" % [game_id, action])
				seen_in_game[action] = true
				_expect(not owner_of.has(action) or owner_of[action] == game_id, "%s is claimed by %s and %s" % [action, owner_of.get(action), game_id])
				owner_of[action] = game_id
	for action in Settings.REBINDABLE_ACTIONS:
		_expect(owner_of.has(action), "%s is rebindable but no game's controls tab owns it" % action)
	var last_route_titles := []
	for tab in ControlsRegistry.tabs_for("last_route"):
		last_route_titles.append(String(tab["title"]))
	_expect(last_route_titles == ["MOVEMENT", "ACTIONS", "SYSTEM"], "Last Route tabs are %s" % [last_route_titles])
	_expect(ControlsRegistry.tabs_for("night_watch")[0]["title"] == "OFFICE", "Night Watch has no OFFICE tab registered")

	# the real settings panel in the Last Route menu
	GameRegistry.active_game_id = "last_route"
	var menu: Node = (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	host.add_child(menu)
	await host.get_tree().process_frame
	var settings := menu.find_child("SettingsOverlay", true, false)
	_expect(settings != null, "no settings overlay in the Last Route menu")
	if settings != null:
		var tabs := settings.get("_section_tabs") as TabBar
		_expect(tabs != null and tabs.tab_count == 3, "Last Route's controls show %d tabs, not 3" % (tabs.tab_count if tabs != null else -1))
		if tabs != null:
			for index in tabs.tab_count:
				settings.call("_show_control_section", index)
				await host.get_tree().process_frame
				_expect(not tabs.get_tab_title(index).to_upper().contains("OFFICE"), "an OFFICE tab is shown in Last Route")
				for label in settings.find_children("*", "Label", true, false):
					var text := String((label as Label).text).to_upper()
					_expect(not text.contains("OFFICE") and text != "OTHER", "Last Route's controls mention %s" % text)
	menu.queue_free()

	# saved office bindings round-trip even though Last Route hides them
	var original_path: String = Settings.SETTINGS_PATH
	var original_events := InputMap.action_get_events("office_left_door")
	Settings.SETTINGS_PATH = "user://controls_roundtrip_test.cfg"
	var key := InputEventKey.new()
	key.physical_keycode = KEY_F9
	Settings.set_action_binding("office_left_door", key, false)
	for event in InputMap.action_get_events("office_left_door"):
		InputMap.action_erase_event("office_left_door", event)
	Settings._load()
	var restored := false
	for event in InputMap.action_get_events("office_left_door"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F9:
			restored = true
	_expect(restored, "a saved office rebind did not survive save + load")
	for event in InputMap.action_get_events("office_left_door"):
		InputMap.action_erase_event("office_left_door", event)
	for event in original_events:
		InputMap.action_add_event("office_left_door", event)
	Settings.SETTINGS_PATH = original_path
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://controls_roundtrip_test.cfg"))
	if _failures == 0:
		print("  controls  Last Route shows MOVEMENT / ACTIONS / SYSTEM, office keys owned by Night Watch, saved binds round-trip")
	return _failures
