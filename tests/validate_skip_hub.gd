extends RefCounted

## GameRegistry.SKIP_HUB: while Last Route is the only unlocked game, boot and every "main menu" landing is the Last Route
## menu, which then carries the hub's ACCOUNT / SETTINGS / ADMIN / QUIT. A second unlocked game, or the switch off, brings the
## hub back exactly as it was.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- skip_hub
##
## (The real scene changes -- boot on the menu, QUIT asking, BACK TO GAMES returning to the hub -- run in tests/hub_nav_test.)

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _game(id: String, locked: bool) -> Dictionary:
	return {"id": id, "title": id.to_upper(), "kicker": "K", "tagline": "T", "scene": "res://game/menus/%s.tscn" % id,
		"theme": "res://game/ui_common/theme_lastroute.tres", "locked": locked, "locked_note": "SOON"}


func _menu(host: Node) -> Control:
	var menu := (load("res://game/menus/main_menu.tscn") as PackedScene).instantiate() as Control
	host.add_child(menu)
	return menu


func _frames(host: Node, count: int = 3) -> void:
	for _i in count:
		await host.get_tree().process_frame


func run(host: Node) -> int:
	var menu_scene := "res://game/menus/main_menu.tscn"
	GameRegistry.skip_hub_override = -1
	GameRegistry.test_games = []

	# --- which scene boot (and the update screen, and the locked-game bounces) land on -----------------------------------
	_expect(GameRegistry.SKIP_HUB, "the shipped switch is not on")
	_expect(GameRegistry.unlocked_ids() == ["last_route"], "the real registry does not have Last Route as the only unlocked game: %s" % [GameRegistry.unlocked_ids()])
	# dev access (admin, headless validation) must not change the landing: Night Watch is dev_open but still locked for players
	_expect(GameRegistry.is_launchable("night_watch") and GameRegistry.landing_scene() == menu_scene,
		"a dev-unlocked Night Watch changed the boot landing (%s)" % GameRegistry.landing_scene())
	_expect(GameRegistry.hub_skipped(), "the hub is not skipped with one unlocked game")
	GameRegistry.skip_hub_override = 0
	_expect(GameRegistry.landing_scene() == GameRegistry.HUB_SCENE and not GameRegistry.hub_skipped(), "switch off: boot is not the hub")
	GameRegistry.skip_hub_override = 1
	_expect(GameRegistry.landing_scene() == menu_scene, "switch on, one unlocked game: boot is not the Last Route menu")
	# one unlocked game (a second one locked) still skips; two unlocked games bring the hub back whatever the switch says
	GameRegistry.test_games = [_game("main_menu", false), _game("game_hub", true)]
	_expect(GameRegistry.landing_scene() == menu_scene and GameRegistry.hub_skipped(), "1 unlocked + 1 locked: the hub was not skipped")
	GameRegistry.test_games = [_game("main_menu", false), _game("game_hub", false)]
	_expect(GameRegistry.landing_scene() == GameRegistry.HUB_SCENE and not GameRegistry.hub_skipped(), "2 unlocked games: boot is not the hub")
	GameRegistry.test_games = [_game("main_menu", true), _game("game_hub", true)]
	_expect(GameRegistry.landing_scene() == GameRegistry.HUB_SCENE, "no unlocked game: boot is not the hub")
	GameRegistry.test_games = []
	GameRegistry.skip_hub_override = -1
	for path in ["res://game/boot/boot_loading.gd", "res://game/boot/update_progress.gd", "res://game/night_watch/night_watch_menu.gd",
			"res://game/night_watch/night_watch_mode.gd"]:
		_expect(FileAccess.get_file_as_string(path).contains("GameRegistry.landing_scene()"), "%s does not ask GameRegistry.landing_scene()" % path)
	# boot resolves the landing when it starts and keeps it
	GameRegistry.skip_hub_override = 0
	var boot := (load("res://game/boot/boot_loading.tscn") as PackedScene).instantiate()
	boot.set("auto_start", false)
	host.add_child(boot)
	await _frames(host, 1)
	_expect(String(boot.get("_menu_path")) == GameRegistry.HUB_SCENE, "boot with the switch off does not target the hub")
	boot.set("_menu_path", GameRegistry.landing_scene())
	boot.queue_free()
	GameRegistry.skip_hub_override = 1
	var boot_skipped := (load("res://game/boot/boot_loading.tscn") as PackedScene).instantiate()
	boot_skipped.set("auto_start", false)
	host.add_child(boot_skipped)
	await _frames(host, 1)
	_expect(String(boot_skipped.get("_menu_path")) == menu_scene, "boot with the hub skipped does not target the Last Route menu")
	boot_skipped.queue_free()

	# --- back-to-menu paths are the game's own menu whatever the switch says; the hub keeps the last game ------------------
	for skip in [0, 1]:
		GameRegistry.skip_hub_override = skip
		Settings.hub_last_game = ""
		_expect(RoomState.menu_scene_path() == menu_scene, "leaving a room does not land on the Last Route menu (switch %d)" % skip)
		_expect(Settings.hub_last_game == "last_route", "Settings.hub_last_game is not kept (switch %d)" % skip)

	# --- the menu with the hub skipped: QUIT, ADMIN, ACCOUNT, SETTINGS ----------------------------------------------------
	GameRegistry.skip_hub_override = 1
	GameHub.admin_override = 0
	var menu := _menu(host)
	await _frames(host)
	var quit_button := menu.find_child("QuitButton", true, false) as Button
	var admin_button := menu.find_child("AdminButton", true, false) as Button
	_expect(menu.find_child("AccountButton", true, false) != null and menu.find_child("SettingsButton", true, false) != null,
		"the skipped-hub menu lost ACCOUNT / SETTINGS")
	_expect(quit_button != null and quit_button.text == "QUIT", "the skipped-hub menu's last button is not QUIT")
	_expect(quit_button != null and quit_button.visible == PlatformProfile.can_quit(), "QUIT ignores PlatformProfile.can_quit (web / iOS)")
	_expect(not PlatformProfile.quit_allowed(false, true) and not PlatformProfile.quit_allowed(true, false), "web / iOS may quit")
	_expect(FileAccess.get_file_as_string("res://game/menus/main_menu.gd").contains("PlatformProfile.can_quit()"), "the menu does not hide QUIT where the app cannot quit")
	_expect(admin_button != null and not admin_button.visible, "a guest / normal account sees ADMIN on the menu")
	_expect(menu.find_child("QuitDialog", true, false) == null, "a quit question is open before QUIT was pressed")
	if quit_button != null and quit_button.visible:
		quit_button.pressed.emit()
		await _frames(host, 2)
		var dialog := menu.find_child("QuitDialog", true, false) as Control
		_expect(dialog != null, "QUIT did not ask QUIT TO DESKTOP?")
		var yes_button := menu.find_child("QuitYesButton", true, false) as Button
		var no_button := menu.find_child("QuitNoButton", true, false) as Button
		_expect(yes_button != null and no_button != null and yes_button.get_index() < no_button.get_index(), "YES must sit left of NO")
		_expect(yes_button != null and no_button != null and yes_button.get_node(yes_button.focus_neighbor_right) == no_button, "right from YES does not reach NO")
		_expect(dialog != null and menu.find_child("QuitBox", true, false) != null and menu.find_child("QuitChoices", true, false) != null, "the shared quit box is missing parts")
		_expect(dialog != null and dialog.z_index > 10, "the quit question can draw under the menu")
		# a second press does not stack another question
		quit_button.pressed.emit()
		_expect(menu.find_children("QuitDialog", "", true, false).size() == 1, "QUIT stacked a second question")
		# Esc closes the question (never quits) before anything else
		var escape := InputEventAction.new()
		escape.action = "ui_cancel"
		escape.pressed = true
		menu._unhandled_input(escape)
		await _frames(host, 2)
		_expect(menu.find_child("QuitDialog", true, false) == null, "Esc did not close the quit question")
		quit_button.pressed.emit()
		await _frames(host, 2)
		(menu.find_child("QuitNoButton", true, false) as Button).pressed.emit()
		await _frames(host, 2)
		_expect(menu.find_child("QuitDialog", true, false) == null, "NO did not close the quit question")
	# ADMIN follows the account like the hub's does
	GameHub.admin_override = 1
	menu._on_account_changed(true, "KYTTU", true, "")
	_expect(admin_button != null and admin_button.visible, "an owner / scoped admin / dev build does not see ADMIN on the menu")
	HubAdminPanel.fetch_override = func(_path: String, _body: Dictionary) -> Dictionary: return {}
	if admin_button != null:
		admin_button.pressed.emit()
		await _frames(host, 2)
		_expect(menu.find_child("HubAdminPanel", true, false) != null, "ADMIN does not open the admin panel on the menu")
	GameHub.admin_override = 0
	menu._on_account_changed(false, "", false, "")
	_expect(admin_button != null and not admin_button.visible, "signing out did not hide ADMIN on the menu")
	menu._on_admin_pressed()
	_expect(menu.find_children("HubAdminPanel", "", true, false).size() <= 1, "a non-admin press stacked admin panels")
	GameHub.admin_override = 1
	menu._on_account_changed(true, "KYTTU", true, "")
	# focus order in the button flow: ... TUTORIAL, UPDATE, ADMIN, QUIT (QUIT stays last)
	var box := quit_button.get_parent() if quit_button != null else null
	if box != null and admin_button != null:
		_expect(admin_button.get_index() == quit_button.get_index() - 1 and quit_button.get_index() == box.get_child_count() - 1,
			"ADMIN is not just before QUIT at the end of the button row")
		var update_button := menu.find_child("UpdateButton", true, false) as Button
		_expect(update_button != null and update_button.get_index() < admin_button.get_index(), "the update button moved after ADMIN")
		for child in box.get_children():
			if child is Button and (child as Button).visible:
				_expect((child as Button).focus_mode == Control.FOCUS_ALL, "%s cannot take focus" % child.name)
	menu.queue_free()
	await _frames(host, 1)

	# --- layout: every button in the worst case (ADMIN and UPDATE showing) clears the version line on the smallest window --
	for skip in [1, 0]:
		GameRegistry.skip_hub_override = skip
		GameHub.admin_override = 1
		var viewport := SubViewport.new()
		viewport.size = Vector2i(480, 270)
		host.add_child(viewport)
		var tight := (load(menu_scene) as PackedScene).instantiate() as Control
		viewport.add_child(tight)
		(tight.find_child("UpdateButton", true, false) as Button).visible = true
		await _frames(host, 4)
		var panel := tight.get_node("ButtonPanel") as Control
		var version := tight.find_child("VersionLabel", true, false) as Control
		var panel_rect := panel.get_global_rect()
		_expect(panel_rect.end.y <= version.get_global_rect().position.y + 0.5,
			"the button rows reach the version line at 480x270 (%.1f vs %.1f, switch %d)" % [panel_rect.end.y, version.get_global_rect().position.y, skip])
		_expect(panel_rect.position.x >= 0.0 and panel_rect.end.x <= 480.0 and panel_rect.end.y <= 270.0, "the button rows spill off the 480x270 window (switch %d)" % skip)
		viewport.queue_free()
		await _frames(host, 1)

	# --- the switch off, or a second unlocked game: today's menu (BACK TO GAMES, no ADMIN, no quit question) -------------
	for case in ["off", "two_games"]:
		GameRegistry.skip_hub_override = 0 if case == "off" else 1
		GameRegistry.test_games = [] if case == "off" else [_game("main_menu", false), _game("game_hub", false)]
		GameHub.admin_override = 1
		var classic := _menu(host)
		await _frames(host)
		var back := classic.find_child("QuitButton", true, false) as Button
		_expect(back != null and back.text == "BACK TO GAMES" and back.visible, "%s: the menu's last button is not BACK TO GAMES" % case)
		_expect(classic.find_child("AdminButton", true, false) == null, "%s: the menu grew an ADMIN button the hub already has" % case)
		classic.queue_free()
		await _frames(host, 1)

	GameRegistry.test_games = []
	GameRegistry.skip_hub_override = -1
	GameHub.admin_override = -1
	HubAdminPanel.fetch_override = Callable()
	if _failures == 0:
		print("  skip_hub  boot/update/bounce landing for 1 vs 2 games and both switch settings, menu QUIT (shared confirm) + ADMIN + focus order + 480x270 layout, BACK TO GAMES when the hub shows")
	return _failures
