extends RefCounted

## The game hub: the registry is consistent, themes load, the hub builds a card per game, Night Watch stays locked,
## the shared entries exist, and boot opens the hub.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var ids := []
	for game in GameRegistry.all():
		var id := String(game["id"])
		_expect(not ids.has(id), "duplicate game id %s" % id)
		ids.append(id)
		_expect(ResourceLoader.exists(String(game["theme"])) and load(String(game["theme"])) is Theme,
			"%s has no loadable theme" % id)
		if bool(game["locked"]):
			_expect(not String(game["locked_note"]).is_empty(), "%s is locked without a reason" % id)
			_expect(not GameRegistry.is_launchable(id) or GameRegistry.dev_unlocked(id), "%s is locked but launchable for players" % id)
		else:
			_expect(ResourceLoader.exists(String(game["scene"])), "%s launches a missing scene" % id)
	_expect(GameRegistry.is_launchable("last_route"), "Last Route is not launchable from the hub")
	# Night Watch is locked for players (until it is data-driven) and opens for testers: headless validation is one
	_expect(bool(GameRegistry.get_game("night_watch")["locked"]) and GameRegistry.is_launchable("night_watch"), "Night Watch is not locked-with-dev-access")
	Build.deny_admin_for_test = true
	_expect(not GameRegistry.is_launchable("night_watch") or OS.has_environment("KYTTU_DEV"), "a player (no admin) can launch the locked Night Watch")
	_expect(GameRegistry.locked_line(GameRegistry.get_game("night_watch")) == "NIGHT WATCH // COMING BACK SOON", "the locked card does not read NIGHT WATCH // COMING BACK SOON")
	Build.deny_admin_for_test = false
	_expect(GameRegistry.get_game(GameRegistry.DEFAULT_ID).size() > 0, "default game is missing")

	var hub: Control = (load("res://game/menus/game_hub.tscn") as PackedScene).instantiate()
	host.add_child(hub)
	await host.get_tree().process_frame
	for game in GameRegistry.all():
		var id := String(game["id"])
		var button := hub.find_child("Launch_%s" % id, true, false) as Button
		_expect(button != null, "no launch button for %s" % id)
		if button != null:
			_expect(button.disabled == not GameRegistry.is_launchable(id), "%s launch button state disagrees with the registry" % id)
	for shared in ["AccountButton", "SettingsButton", "AdminButton"]:
		_expect(hub.find_child(shared, true, false) != null, "hub is missing the %s entry" % shared)
	# QUIT lives on the hub (hidden on web), behind a "QUIT TO DESKTOP?" question; the menu shares it while the hub is skipped (skip_hub suite)
	var quit_button := hub.find_child("QuitButton", true, false) as Button
	_expect(OS.has_feature("web") or quit_button != null, "hub has no QUIT button")
	if quit_button != null:
		quit_button.pressed.emit()
		await host.get_tree().process_frame
		_expect(hub.find_child("QuitDialog", true, false) != null and hub.find_child("QuitNoButton", true, false) != null,
			"QUIT did not ask QUIT TO DESKTOP?")
		var dialog := hub.find_child("QuitDialog", true, false) as Control
		var top_card := 0
		for card in hub.find_children("*", "Control", true, false):
			if not dialog.is_ancestor_of(card) and card != dialog:
				top_card = maxi(top_card, (card as Control).z_index)
		_expect(dialog.z_index > top_card, "the QUIT question draws under a carousel card (z %d vs %d)" % [dialog.z_index, top_card])
		var yes_button := hub.find_child("QuitYesButton", true, false) as Button
		var no_button := hub.find_child("QuitNoButton", true, false) as Button
		_expect(yes_button != null and no_button != null and yes_button.get_index() < no_button.get_index(),
			"QUIT TO DESKTOP? must show YES on the left and NO on the right")
		_expect(no_button != null and (no_button.has_focus() or no_button.is_inside_tree()), "NO is not the default answer")
		_expect(yes_button != null and no_button != null and yes_button.get_node(yes_button.focus_neighbor_right) == no_button,
			"keyboard right from YES does not reach NO")
		no_button.pressed.emit()
		await host.get_tree().process_frame
		_expect(hub.find_child("QuitDialog", true, false) == null or (hub.find_child("QuitDialog", true, false) as Node).is_queued_for_deletion(),
			"NO did not close the quit question")
	# nothing but the hub / shared quit question (and the updater, after staging an update) quits the app
	for path in ["res://game/menus/main_menu.gd", "res://game/menus/pause_menu.gd", "res://game/menus/room_lobby.gd", "res://game/menus/run_report.gd",
			"res://game/main_3d.gd", "res://game/infinite_route/infinite_route_test.gd", "res://game/admin/admin_menu.gd"]:
		_expect(not FileAccess.get_file_as_string(path).contains("get_tree().quit()"), "%s quits the app; only PlatformProfile.quit_app (via the shared quit question) may" % path)
	_expect(FileAccess.get_file_as_string("res://game/menus/main_menu.gd").contains("GameRegistry.HUB_SCENE"), "the Last Route menu does not return to the hub")
	_expect(FileAccess.get_file_as_string("res://game/menus/main_menu.tscn").contains('text = "BACK TO GAMES"'), "the menu's last button is not BACK TO GAMES")
	hub.queue_free()
	# boot and the update screen ask the one switch (GameRegistry.landing_scene: the hub, or the Last Route menu while it is skipped)
	for path in ["res://game/boot/boot_loading.gd", "res://game/boot/update_progress.gd"]:
		var source := FileAccess.get_file_as_string(path)
		_expect(source.contains("GameRegistry.landing_scene()"), "%s does not ask GameRegistry.landing_scene()" % path)
		_expect(not source.contains("game_hub.tscn"), "%s hard-codes the hub scene" % path)
	# with the switch off (and with a second unlocked game) boot opens the hub, as it always did
	GameRegistry.skip_hub_override = 0
	_expect(GameRegistry.landing_scene() == GameRegistry.HUB_SCENE, "boot does not open the hub with SKIP_HUB off")
	GameRegistry.skip_hub_override = -1
	if _failures == 0:
		print("  hub  registry, themes, cards, shared entries, locked Night Watch, boot target")
	return _failures
