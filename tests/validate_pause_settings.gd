extends RefCounted

## The SETTINGS button on the in-run pause menu. It opens the shared SettingsPanel above the pause page; BACK, ESC, the pause key
## and B (ui_cancel) close only that panel (the pause menu stays up and the run stays paused); the panel keeps working while the
## SceneTree is paused; and the tabs that are unsafe over a live run (SKIN: 3D preview viewport, file dialogs, uploads; MODS: can
## unload the content packs the run uses) are neither built nor listed. Checked at 480x270, 1024x768, a phone and an XR panel.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- pause_settings

const SIZES := {"480x270": Vector2i(480, 270), "1024x768": Vector2i(1024, 768), "phone844x390": Vector2i(844, 390), "xr640x360": Vector2i(640, 360)}
const RUN_TABS := ["AUDIO", "DISPLAY", "CONTROLS", "VOICE"]

var _failures := 0
var _host: Node


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _frames(count := 2) -> void:
	for _i in count:
		await _host.get_tree().process_frame


static func _action(name: String) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = true
	return event


static func _escape_key() -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	return event


func _tab_titles(overlay: SettingsPanel) -> Array:
	var tabs := overlay.find_child("SettingsCategoryTabs", true, false) as TabBar
	var titles := []
	if tabs != null:
		for i in tabs.tab_count:
			titles.append(tabs.get_tab_title(i))
	return titles


func run(host: Node) -> int:
	_host = host
	var old_fov := Settings.field_of_view
	var old_volume := Settings.master_volume_percent
	for key in SIZES:
		await _check_size(key, SIZES[key])
	await _check_escape_flow()
	await _check_paused_tree()
	await _check_main_menu_tabs()
	Settings.set_field_of_view(old_fov)
	Settings.set_master_volume(old_volume)
	if _failures == 0:
		print("  pausesettings SETTINGS button opens the run-safe panel (no SKIN/MODS) above pause; ESC/B/BACK close only it, also while the tree is paused; fits 480x270, 1024x768, phone, XR panel")
	return _failures


func _make_menu(size: Vector2i, pauses_tree: bool) -> Array:
	var holder := SubViewport.new()
	holder.size = size
	var units: Vector2 = load("res://tests/validate_admin_layout.gd").units_for(size)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	_host.add_child(holder)
	var menu := PauseMenu.new()
	menu.pauses_tree = pauses_tree
	menu.save_status_source = func() -> String: return "RUN SAVED AT LEVEL -3, 14:05"
	holder.add_child(menu)
	return [holder, menu, units]


func _check_size(key: String, size: Vector2i) -> void:
	var made := _make_menu(size, false)
	var holder: SubViewport = made[0]
	var menu: PauseMenu = made[1]
	var window := Rect2(Vector2.ZERO, made[2]).grow(1.0)
	await _frames()
	menu.open()
	await _frames()
	var button := menu.find_child("PauseSettingsButton", true, false) as Button
	_expect(button != null and button.is_visible_in_tree(), "%s: the pause page has no SETTINGS button" % key)
	if button == null:
		holder.queue_free()
		return
	_expect(button.text == "SETTINGS" and button.focus_mode == Control.FOCUS_ALL, "%s: SETTINGS is not a focusable SETTINGS button" % key)
	var dossier: Button
	for candidate in menu.find_children("*", "Button", true, false):
		if (candidate as Button).text == "HUNTER DOSSIER":
			dossier = candidate
	_expect(dossier != null and button.custom_minimum_size == dossier.custom_minimum_size \
		and button.get_theme_font_size("font_size") == dossier.get_theme_font_size("font_size"),
		"%s: SETTINGS is not sized and styled like the dossier button" % key)
	# order in the column (top to bottom is the focus order): RETURN, HUNTER DOSSIER, SETTINGS, ABANDON
	var column := button.get_parent()
	_expect(column.get_child_count() > 0 and dossier != null and button.get_index() == dossier.get_index() + 1 \
		and menu._abandon_button.get_index() == button.get_index() + 1 and menu._resume_button.get_index() < dossier.get_index(),
		"%s: SETTINGS is not between HUNTER DOSSIER and the abandon button" % key)
	_expect(window.encloses(button.get_global_rect()), "%s: SETTINGS leaves the window (%s)" % [key, button.get_global_rect()])
	_expect(window.encloses(menu._panel.get_global_rect()), "%s: the pause panel leaves the window with SETTINGS added (%s)" % [key, menu._panel.get_global_rect()])
	_expect(menu._resume_button.has_focus(), "%s: opening pause no longer focuses RETURN" % key)

	button.pressed.emit()
	await _frames()
	var overlay := menu.find_child("PauseSettings", true, false) as SettingsPanel
	_expect(overlay != null and menu.settings_is_open() and overlay.is_visible_in_tree(), "%s: SETTINGS did not open the settings panel" % key)
	if overlay == null:
		holder.queue_free()
		return
	_expect(menu.is_open() and not menu._panel.visible, "%s: opening SETTINGS closed the pause menu or left its page showing under the panel" % key)
	_expect(window.encloses(overlay.get_global_rect()), "%s: the settings panel leaves the window (%s)" % [key, overlay.get_global_rect()])
	_expect(_tab_titles(overlay) == RUN_TABS, "%s: the run's settings tabs are %s, not %s" % [key, _tab_titles(overlay), RUN_TABS])
	_expect(overlay.find_child("SkinSection", true, false) == null and overlay.find_child("ModsSection", true, false) == null,
		"%s: SKIN or MODS was built inside a run" % key)
	var owner_control := holder.gui_get_focus_owner()
	_expect(owner_control != null and overlay.is_ancestor_of(owner_control), "%s: focus did not move into the settings panel (%s)" % [key, owner_control])
	for tab_button in overlay.find_children("*", "Button", true, false):
		var control := tab_button as Control
		if control.is_visible_in_tree():
			_expect(window.encloses(control.get_global_rect()), "%s: settings button %s leaves the window" % [key, control.name])
	# every run tab shows and fits
	var tabs := overlay.find_child("SettingsCategoryTabs", true, false) as TabBar
	for index in tabs.tab_count:
		tabs.current_tab = index
		await _frames(1)
		for child in overlay.get_children():
			if child is Control and (child as Control).is_visible_in_tree() and child != tabs and not (child is Label):
				_expect(Rect2(overlay.get_global_rect()).grow(1.0).encloses((child as Control).get_global_rect()),
					"%s: %s on the %s tab leaves the settings panel" % [key, child.name, tabs.get_tab_title(index)])
	tabs.current_tab = 0
	# BACK closes only the panel and hands focus back to SETTINGS
	var resumed := [0]
	menu.resumed.connect(func() -> void: resumed[0] += 1)
	overlay.close_button.pressed.emit()
	await _frames(1)
	_expect(not menu.settings_is_open() and menu.is_open() and menu._panel.visible and resumed[0] == 0,
		"%s: BACK closed more than the settings panel" % key)
	_expect(button.has_focus(), "%s: BACK did not return focus to SETTINGS" % key)
	# the panel is built once and reused
	button.pressed.emit()
	await _frames(1)
	_expect(menu.find_children("PauseSettings", "", true, false).size() == 1 and menu.settings_is_open(), "%s: reopening SETTINGS built a second panel" % key)
	# closing the pause menu with the panel up hides both and does not bring the page back
	menu.close()
	_expect(not menu.is_open() and not menu.settings_is_open() and not menu._panel.visible and resumed[0] == 1,
		"%s: closing pause left the settings panel up" % key)
	menu.open()
	await _frames(1)
	_expect(menu.is_open() and menu._panel.visible and not menu.settings_is_open() and menu._resume_button.has_focus(),
		"%s: reopening pause did not start on the pause page" % key)
	menu.close()
	holder.queue_free()
	await _frames(1)


## ESC (a real key through the viewport), the pause action, ui_cancel (B) and a rebind in progress.
func _check_escape_flow() -> void:
	var made := _make_menu(Vector2i(480, 270), false)
	var holder: SubViewport = made[0]
	var menu: PauseMenu = made[1]
	await _frames()
	var resumed := [0]
	var abandoned := [0]
	menu.resumed.connect(func() -> void: resumed[0] += 1)
	menu.abandoned.connect(func() -> void: abandoned[0] += 1)
	menu.open()
	menu._open_settings()
	await _frames()
	_expect(menu.settings_is_open(), "ESC flow: the panel did not open")
	# a real ESC key press, through the whole input path
	holder.push_input(_escape_key())
	await _frames(1)
	_expect(not menu.settings_is_open() and menu.is_open() and resumed[0] == 0 and abandoned[0] == 0 and menu._panel.visible,
		"ESC (key) with SETTINGS up closed the pause menu or the run instead of only the panel")
	_expect(menu._settings_button.has_focus(), "ESC did not put focus back on SETTINGS")
	# the next ESC is the ordinary one: it resumes
	holder.push_input(_escape_key())
	await _frames(1)
	_expect(not menu.is_open() and resumed[0] == 1, "ESC on the pause page no longer resumes")
	# the pause action and B
	for action in ["pause", "ui_cancel"]:
		menu.open()
		menu._open_settings()
		await _frames(1)
		menu._unhandled_input(_action(action))
		_expect(not menu.settings_is_open() and menu.is_open(), "%s with SETTINGS up did not close only the panel" % action)
	# B on the plain pause page is not ESC: it must not resume
	menu._unhandled_input(_action("ui_cancel"))
	_expect(menu.is_open(), "ui_cancel on the pause page closed pause")
	# a rebind in progress takes ESC for itself: the panel stays, the rebind ends
	menu._open_settings()
	await _frames(1)
	var overlay: SettingsPanel = menu._settings_overlay
	var tabs := overlay.find_child("SettingsCategoryTabs", true, false) as TabBar
	tabs.current_tab = 2   # CONTROLS
	await _frames(2)
	var change: Button
	for candidate in overlay.find_children("*", "Button", true, false):
		if (candidate as Button).text == "CHANGE" and (candidate as Button).is_visible_in_tree():
			change = candidate
			break
	_expect(change != null, "ESC flow: the CONTROLS tab has no CHANGE button")
	if change != null:
		change.pressed.emit()
		_expect(change.text == SettingsPanel.LISTENING_TEXT, "ESC flow: CHANGE did not start a rebind")
		holder.push_input(_escape_key())
		await _frames(1)
		_expect(menu.settings_is_open() and menu.is_open() and change.text == "CHANGE" and resumed[0] == 1,
			"ESC during a rebind closed the panel or pause instead of cancelling the rebind")
	menu.close()
	_expect(not menu.settings_is_open() and not overlay.visible, "ESC flow: the panel survived the pause menu closing")
	# the abandon question is unaffected by SETTINGS having been built and used
	menu.open()
	menu._open_settings()
	await _frames(1)
	menu._close_settings()
	menu._ask_abandon()
	_expect(menu._confirming and menu._confirm.visible and not menu._panel.visible, "the abandon question stopped working after SETTINGS")
	menu._unhandled_input(_action("pause"))
	_expect(not menu._confirming and menu.is_open() and menu._panel.visible, "ESC no longer backs out of the abandon question")
	menu._open_settings()
	menu._on_abandon()
	_expect(not menu.is_open() and not menu.settings_is_open() and abandoned[0] == 1, "abandoning with SETTINGS built did not close everything")
	holder.queue_free()
	await _frames(1)


## The route pauses the whole tree: the panel (a child of the always-processing pause layer) must still work, the game must not.
func _check_paused_tree() -> void:
	var made := _make_menu(Vector2i(480, 270), true)
	var holder: SubViewport = made[0]
	var menu: PauseMenu = made[1]
	var underneath := Node.new()   # stands in for the route: an ordinary pausable node (under root, not the always-on runner)
	_host.get_tree().root.add_child(underneath)
	await _frames()
	menu.open()
	_expect(_host.get_tree().paused, "paused tree: opening pause did not pause the SceneTree")
	menu._open_settings()
	await _frames()
	var overlay: SettingsPanel = menu._settings_overlay
	_expect(overlay != null and overlay.can_process() and overlay.is_visible_in_tree(), "paused tree: the settings panel does not process while paused")
	_expect(not underneath.can_process(), "paused tree: the game underneath still processes")
	# changes apply live, through the Settings autoload, exactly as from the main menu
	var visual := [0]
	var on_visual := func() -> void: visual[0] += 1
	Settings.visual_changed.connect(on_visual)
	overlay.fov_slider.value = 95.0
	_expect(is_equal_approx(Settings.field_of_view, 95.0) and visual[0] > 0, "paused tree: FOV did not apply live (fov %s, visual_changed x%d)" % [Settings.field_of_view, visual[0]])
	overlay.volume_slider.value = 40.0
	_expect(is_equal_approx(Settings.master_volume_percent, 40.0), "paused tree: master volume did not apply live")
	Settings.visual_changed.disconnect(on_visual)
	var tabs := overlay.find_child("SettingsCategoryTabs", true, false) as TabBar
	tabs.current_tab = 3   # VOICE (the fourth listed tab)
	await _frames(1)
	_expect(overlay.find_child("VoiceSection", true, false) != null and (overlay.find_child("VoiceSection", true, false) as Control).is_visible_in_tree(),
		"paused tree: the VOICE tab does not show the voice page")
	_expect(_host.get_tree().paused and menu.is_open(), "paused tree: changing settings resumed the game")
	menu._unhandled_input(_action("pause"))
	_expect(not menu.settings_is_open() and menu.is_open() and _host.get_tree().paused, "paused tree: ESC closed more than the panel or unpaused")
	menu.close()
	_expect(not _host.get_tree().paused, "paused tree: closing pause left the tree paused")
	underneath.queue_free()
	holder.queue_free()
	_host.get_tree().paused = false
	await _frames(1)


## The main menu's panel is untouched: all six tabs, SKIN and MODS built.
func _check_main_menu_tabs() -> void:
	var panel := (load("res://game/menus/settings_overlay.tscn") as PackedScene).instantiate() as SettingsPanel
	_host.add_child(panel)
	await _frames(1)
	_expect(_tab_titles(panel) == ["AUDIO", "DISPLAY", "CONTROLS", "SKIN", "VOICE", "MODS"], "the main menu's settings lost a tab: %s" % [_tab_titles(panel)])
	panel.queue_free()
	await _frames(1)
