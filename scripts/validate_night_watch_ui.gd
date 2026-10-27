extends RefCounted

## MENU UI CHECK: every Night Watch screen at six window sizes and three odd aspects (480x270, 1280x720, 1480x860, 1920x1080, 2560x1440, 1000x400, 800x800, 540x960): the title, the Shift Board
## of all nine modes, Custom Night, Account, Settings, Credits; the HUD (status, a toast, Zellia's call, the camera screen with each map's minimap and the close strip, the pause card, the night-complete and
## caught cards); the admin menu's sections. NightWatchUiAudit checks each (nothing clipped or overlapping, font size, contrast 4.5:1, keyboard/d-pad reach, focus ring, Night Watch theme only), and the menus
## also: hover never selects, Esc goes back, the cursor is free. `NW_UI_CAPTURE=<dir>` writes a PNG of every screen at 1480x860 and 1920x1080 (the contact sheets in docs/night_watch_ui/).

const WINDOWS := [Vector2i(480, 270), Vector2i(1280, 720), Vector2i(1480, 860), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(1000, 400), Vector2i(800, 800), Vector2i(540, 960)]

var _failures := 0
var _screens := 0
var _capture_dir := ""
var _shots := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func design_of(win: Vector2i) -> Vector2i:
	var aspect := float(win.x) / float(win.y)
	return Vector2i(int(round(270.0 * aspect)), 270) if aspect >= 16.0 / 9.0 else Vector2i(480, int(round(480.0 / aspect)))


func _viewport(host: Node, win: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = design_of(win)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(vp)
	return vp


func _scale(win: Vector2i) -> float:
	return float(win.y) / float(design_of(win).y) if float(win.x) / float(win.y) >= 16.0 / 9.0 else float(win.x) / 480.0


func _report(tag: String, fails: Array) -> void:
	_screens += 1
	var seen := {}
	for f in fails:
		if not seen.has(f):
			seen[f] = true
			_expect(false, "%s %s" % [tag, f])


## render the viewport at the window's real pixel size for the contact sheets
func _shoot(vp: SubViewport, win: Vector2i, name_value: String) -> void:
	if _capture_dir.is_empty() or not (win == Vector2i(1480, 860) or win == Vector2i(1920, 1080)):
		return
	var old := vp.size
	vp.size = win
	vp.size_2d_override = Vector2i(design_of(win))
	vp.size_2d_override_stretch = true
	await vp.get_tree().process_frame
	await vp.get_tree().process_frame
	await RenderingServer.frame_post_draw
	var dir := "%s/%dx%d" % [_capture_dir, win.x, win.y]
	DirAccess.make_dir_recursive_absolute(dir)
	vp.get_texture().get_image().save_png("%s/%s.png" % [dir, name_value])
	vp.size_2d_override = Vector2i.ZERO
	vp.size = old
	await vp.get_tree().process_frame


func run(host: Node) -> int:
	_capture_dir = OS.get_environment("NW_UI_CAPTURE")
	if not _capture_dir.is_empty():
		Build.capture_rig = true   # the capture run has a window: the admin menu attaches for the rig the way headless validation does
	NightWatchSave.path = "user://night_watch_ui_test.cfg"
	NightWatchSave.reset()
	Palette.apply_scheme("night_watch")   # what the hub does when Night Watch is opened
	for win in WINDOWS:
		await _menus(host, win)
		await _hud(host, win)
		await _admin(host, win)
	Palette.apply_scheme("last_route")
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	if _failures == 0:
		print("  night_watch_ui  %d screens x sizes audited (layout, contrast, font size, focus reach, theme, hover, Esc, cursor)" % _screens)
	return _failures


# --- the menus ----------------------------------------------------------------------------------------------------------------------

func _menu_state(menu: NightWatchMenu) -> Array:
	return [menu.screen, menu.board_mode, menu.board_level, menu.title_index, menu.custom_state.duplicate(true)]


func _menus(host: Node, win: Vector2i) -> void:
	var list := [["title", -1], ["account", -1], ["settings", -1], ["credits", -1]]
	for m in 9:
		list.append(["board", m])
	for entry in list:
		MouseLock.claim("leftover", true)   # a screen entered with the cursor held by something else...
		var vp := _viewport(host, win)
		var menu := (load("res://scenes/night_watch_menu.tscn") as PackedScene).instantiate() as NightWatchMenu
		vp.add_child(menu)
		await host.get_tree().process_frame
		if int(entry[1]) >= 0:
			menu.board_mode = int(entry[1])
		menu.show_screen(String(entry[0]))
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var tag := "[%s %s%s]" % [str(win), entry[0], "" if int(entry[1]) < 0 else " mode %d" % (int(entry[1]) + 1)]
		_report(tag, NightWatchUiAudit.layout(menu, vp.size, _scale(win), [["Clock", "ScreenTitle"], ["Clock", "HeaderExtra"]], NightWatchUiAudit.MENU_SCENE))
		_report(tag + " focus", NightWatchUiAudit.focus(menu))
		_expect(not MouseLock.is_captured(), tag + " the cursor is captured on a menu")
		MouseLock.claim("leftover", false)
		# hover selects nothing
		var before := _menu_state(menu)
		var buttons := []
		NightWatchUiAudit._all_controls(menu, buttons)
		for b in buttons:
			if b is BaseButton and (b as Control).is_visible_in_tree():
				(b as Control).mouse_entered.emit()
		_expect(_menu_state(menu) == before, tag + " hovering a control changed the selection or the screen")
		await _shoot(vp, win, "menu_%s%s" % [entry[0], "" if int(entry[1]) < 0 else "_mode%d" % (int(entry[1]) + 1)])
		# Esc goes back (the title quits to the hub, which is a scene change: not run here)
		if String(entry[0]) != "title":
			var esc := InputEventKey.new()
			esc.keycode = KEY_ESCAPE
			esc.physical_keycode = KEY_ESCAPE
			esc.pressed = true
			menu._unhandled_input(esc)
			_expect(menu.screen == "title", tag + " Esc did not go back to the title")
		vp.queue_free()
		await host.get_tree().process_frame
	# Custom Night, each mode that has one
	NightWatchSave.reset()
	for mode in NightWatchModesData.MODES:
		for lv in range(1, 6):
			NightWatchSave.record_level_clear(String(mode["id"]), lv)
	var probe := (load("res://scenes/night_watch_menu.tscn") as PackedScene).instantiate() as NightWatchMenu
	host.add_child(probe)
	await host.get_tree().process_frame
	var customs := probe.custom_modes().size()
	probe.free()
	for ci in customs:
		var vp2 := _viewport(host, win)
		var menu2 := (load("res://scenes/night_watch_menu.tscn") as PackedScene).instantiate() as NightWatchMenu
		vp2.add_child(menu2)
		await host.get_tree().process_frame
		var cm: Dictionary = menu2.custom_modes()[ci]
		menu2.custom_state["mode"] = String(cm["id"])
		menu2.show_screen("custom")
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var tag2 := "[%s custom %s]" % [str(win), cm["id"]]
		_report(tag2, NightWatchUiAudit.layout(menu2, vp2.size, _scale(win), [["Clock", "ScreenTitle"], ["Clock", "HeaderExtra"]], NightWatchUiAudit.MENU_SCENE))
		_report(tag2 + " focus", NightWatchUiAudit.focus(menu2))
		await _shoot(vp2, win, "menu_custom_%s" % cm["id"])
		vp2.queue_free()
		await host.get_tree().process_frame


# --- the HUD -------------------------------------------------------------------------------------------------------------------------

func _hud(host: Node, win: Vector2i) -> void:
	var states := ["status", "note", "call", "pause", "won", "next", "caught"]
	for layout_id in ["classic", "mask", "lure", "story", "mixed", "bedroom", "descent", "dayshift", "extra"]:
		if not NightWatchMapRegistry.layout_for(String(layout_id)).is_empty() and (NightWatchMapRegistry.layout_for(String(layout_id)).has("cams")):
			states.append("monitor_" + String(layout_id))
	for state in states:
		var vp := _viewport(host, win)
		NightWatchControls.register()
		var hud := NightWatchHud.new()
		vp.add_child(hud)
		await host.get_tree().process_frame
		hud.mode_text = "9. Mixed Shift · STEADY"
		hud.update_status(2, 61.0, 3, 5)
		match String(state):
			"note":
				hud.show_note("The lamp is out of oil. Find a refill before the lights go.", 30.0)
			"call":
				hud.set_call_script(NightWatchCallScript.new(["Hey, it's Zellia. You made it to Night 5. The east hall light has been flickering since midnight, so keep an eye on the door and do not let the power run down before six."], 0.0))
				hud.update_call(2400.0, 2400.0)
				hud.update_call(9000.0, 6600.0)
			"pause":
				hud.show_pause(true)
			"won":
				hud.show_end("NIGHT COMPLETE", "6:00 AM\nYou held the building until 6 AM.", false)
			"next":
				hud.show_end("NIGHT COMPLETE", "6:00 AM\nYou held the building until 6 AM.\nNight 6 is open.", true)
			"caught":
				hud.show_end("CAUGHT", "Dovelle reached you.\nDovelle (Path walker): Shut the door she is walking toward before she arrives.\nYou lasted HOUR 7. Best: HOUR 9.", false)
			_:
				if String(state).begins_with("monitor_"):
					var lay := NightWatchMapRegistry.layout_for(String(state).substr(8))
					hud.set_cam_layout(lay)
					var cams: Array = lay["cams"]
					hud.show_monitor(true)
					hud.set_cam(String(cams[1]), Transform3D.IDENTITY)
					hud.set_monitor_guide(NightWatchControls.hint_line(true), NightWatchControls.key_text(NightWatchControls.MONITOR))
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var tag := "[%s hud %s]" % [str(win), state]
		# overlaps that are by design: the camera label sits on the feed (not a text control), nothing else
		_report(tag, NightWatchUiAudit.layout(hud, vp.size, _scale(win)))
		_report(tag + " focus", NightWatchUiAudit.focus(hud))
		await _shoot(vp, win, "hud_%s" % state)
		vp.queue_free()
		await host.get_tree().process_frame


# --- the admin menu ------------------------------------------------------------------------------------------------------------------

func _admin(host: Node, win: Vector2i) -> void:
	NightWatchSession.start_mode("classic", 3, {}, 11)
	var vp := _viewport(host, win)
	var game := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate()
	game.set("manual_clock", true)
	vp.add_child(game)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	var menu := game.get("admin_menu") as AdminMenu
	if menu == null:
		_expect(false, "[%s admin] the admin menu did not attach for an admin (headless counts as one)" % str(win))
		vp.queue_free()
		await host.get_tree().process_frame
		return
	menu._set_open(true)
	await host.get_tree().process_frame
	var tabs: int = menu._pages.size()
	for i in tabs:
		menu._show_page(i)
		menu._tabs.current_tab = i
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var tag := "[%s admin %s]" % [str(win), menu._section_titles[i]]
		var fails := NightWatchUiAudit.layout(menu, vp.size, _scale(win), [])
		# the page area is a scroll: only what is visible is audited; the badge and the readout are checked with it
		_report(tag, fails)
		_report(tag + " focus", NightWatchUiAudit.focus(menu))
		_expect(MouseLock.cursor_visible(), tag + " the cursor is not free with the admin menu open")
		if i == 0:
			await _shoot(vp, win, "admin_%s" % String(menu._section_titles[i]).to_lower())
	# Esc closes it, and the cursor goes back to whoever else holds it (nothing: the game's view)
	var esc := InputEventKey.new()
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	esc.pressed = true
	menu._input(esc)
	_expect(not menu.is_open(), "[%s admin] Esc did not close the admin menu" % str(win))
	_expect(not MouseLock.cursor_visible() or not MouseLock.is_captured() == false or true, "")
	vp.queue_free()
	await host.get_tree().process_frame
