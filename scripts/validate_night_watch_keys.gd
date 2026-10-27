extends RefCounted

## The camera keys and the whole key flow, one source of truth (NightWatchControls.ACTIONS): the table, the InputMap, the hint line, the controls tab and the
## handlers must agree; then for EVERY playable mode scene with a monitor the key flow runs with real key events: open the monitor, cycle all cameras forward and
## backward by Left/Right, pick each camera by number key and by number pad, gamepad d-pad cycling, keys do nothing while the monitor is down or the game is
## paused, keys still work after pause/resume and after leaving and re-entering the monitor, use closes it, the old office_camera_n actions are ignored, and a
## rebound key shows in the hint line and works. A mode scene without a monitor (Bedtime, ...) is skipped, with the reason listed.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _key(code: int, pressed := true) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _joy(button: int) -> InputEventJoypadButton:
	var e := InputEventJoypadButton.new()
	e.button_index = button
	e.pressed = true
	return e


func run(host: Node) -> int:
	NightWatchSave.path = "user://night_watch_keys_test.cfg"
	NightWatchSave.reset()
	# --- the table, the InputMap, the hint line and the controls tab
	NightWatchControls.register()
	var seen_keys := {}
	for entry in NightWatchControls.ACTIONS:
		var action: StringName = entry["action"]
		_expect(InputMap.has_action(action), "%s is in the table but not in the InputMap" % action)
		var k := int(entry["key"])
		_expect(not seen_keys.has(k), "%s and %s share the default key %s" % [action, seen_keys.get(k, ""), OS.get_keycode_string(k)])
		seen_keys[k] = action
		_expect(NightWatchControls.key_text(action) != "?", "%s has no key" % action)
		_expect(int(entry["joy"]) < 0 or InputMap.action_get_events(action).any(func(e): return e is InputEventJoypadButton), "%s has no gamepad button though the table names one" % action)
	var tab := NightWatchControls.controls_tab()
	var tab_actions := []
	for a in tab["actions"]:
		tab_actions.append(String(a["action"]))
	for entry in NightWatchControls.ACTIONS:
		_expect(tab_actions.has(String(entry["action"])), "%s is missing from the OFFICE controls tab" % entry["action"])
	var line := NightWatchControls.hint_line(false)
	for entry in NightWatchControls.ACTIONS:
		var a2 := String(entry["action"])
		if a2.begins_with("nw_cam_") or a2 == "nw_cam_prev" or a2 == "nw_cam_next" or a2 == "nw_meet":
			continue
		_expect(line.contains(NightWatchControls.key_text(StringName(a2))), "the hint line does not show %s's key %s: %s" % [a2, NightWatchControls.key_text(StringName(a2)), line])
	_expect(line.contains("WASD") or line.contains("W") and not line.contains("?"), "the hint line has a movement key it cannot name: %s" % line)
	_expect(NightWatchControls.hint_line(true, ["nw_meet"]).contains(NightWatchControls.key_text(NightWatchControls.MEET) + " meet her eyes"), "the Night 7 monitor hint does not show the meet key")
	var mline := NightWatchControls.hint_line(true)
	_expect(NightWatchControls.key_text(NightWatchControls.MONITOR) == "Space" and NightWatchControls.hint_line(false).contains("Space cameras"), "the hint line does not show Space for the cameras")
	_expect(mline.contains("1-8") and mline.contains("Left") and mline.contains("Right"), "the monitor hint line does not show the camera keys: %s" % mline)
	# a rebind: the hint line and the saved override follow
	NightWatchControls.rebind(NightWatchControls.MONITOR, KEY_O)
	_expect(not InputMap.action_get_events(NightWatchControls.MONITOR).any(func(e): return e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_U), "a rebind of the monitor key left the U alias behind")
	_expect(NightWatchControls.key_text(NightWatchControls.MONITOR) == "O" and NightWatchControls.hint_line(false).contains("O cameras"), "a rebind of the monitor key did not show in the hint line")
	_expect(int(NightWatchSave.key_overrides().get("nw_monitor", 0)) == KEY_O, "the rebind was not saved")
	NightWatchControls.unregister()
	NightWatchControls.register()
	_expect(NightWatchControls.key_text(NightWatchControls.MONITOR) == "O", "the saved rebind was not applied on the next register()")
	NightWatchSave.clear_key_overrides()
	NightWatchControls.unregister()
	# --- the key flow in every mode scene that has a monitor
	var skipped := []
	var tested := []
	for mode_id in NightWatchModeRegistry.SCENES:
		var spec := NightWatchOfficeRegistry.spec_for(String(mode_id))
		if not spec.has_monitor:
			skipped.append("%s (no monitor)" % mode_id)
			continue
		NightWatchSession.start_mode(String(mode_id), 1, {}, 77)
		var game := (load(String(NightWatchModeRegistry.SCENES[mode_id])) as PackedScene).instantiate()
		if not (game.has_method("cycle_camera") and game.has_method("select_camera_number") and game.has_method("is_playing")):
			skipped.append("%s (its scene does not offer the camera API: is_playing, cycle_camera, select_camera_number)" % mode_id)
			game.free()
			continue
		game.set("manual_clock", true)
		host.add_child(game)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		await _flow(host, game, String(mode_id))
		tested.append(String(mode_id))
		game.queue_free()
		await host.get_tree().process_frame
	var probe := NightWatchHud.new()
	host.add_child(probe)
	await host.get_tree().process_frame
	probe.set_monitor_available(false)
	_expect(not probe.cameras_button.visible, "set_monitor_available(false) did not hide the CAMERAS button")
	probe.set_monitor_available(true)
	_expect(probe.cameras_button.visible, "set_monitor_available(true) did not show the CAMERAS button")
	probe.queue_free()
	await _check_camera_screen(host)
	await _check_mouse_capture(host, tested)
	_expect(tested.has("classic"), "the camera key flow did not run for Classic")
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	if _failures == 0:
		print("  night_watch_keys  table, InputMap, hint line and controls tab agree; camera key flow passes in: %s; skipped: %s" % [", ".join(PackedStringArray(tested)), ", ".join(PackedStringArray(skipped)) if not skipped.is_empty() else "none"])
	return _failures


func _send(game: Node, ev: InputEvent) -> void:
	game.call("_unhandled_input", ev)


func _flow(host: Node, game: Node, mode_id: String) -> void:
	# a mode with its own rooms offers camera_rooms() (the cameras in order) and camera_room_for(n); a timed monitor offers advance_ms(ms)
	var rooms: Array = game.call("camera_rooms") if game.has_method("camera_rooms") else NightWatchData.cam_rooms()
	var room_for := func(n: int) -> String:
		if game.has_method("camera_room_for"):
			return String(game.call("camera_room_for", n))
		return String(rooms[n - 1]) if game.has_method("camera_rooms") and n - 1 < rooms.size() else NightWatchData.room_for_cam(n)
	var settle := func() -> void:
		if game.has_method("advance_ms"):
			game.call("advance_ms", 400.0)
	var tag := "[%s] " % mode_id
	_expect(not bool(game.get("monitor_up")), tag + "the monitor starts open")
	# camera keys do nothing with the monitor down
	_send(game, _key(KEY_3))
	_send(game, _key(KEY_RIGHT))
	_expect(not bool(game.get("monitor_up")), tag + "a camera key opened the monitor")
	# open by the monitor key (a real key event)
	_send(game, _key(KEY_SPACE))
	settle.call()
	_expect(bool(game.get("monitor_up")), tag + "Space did not open the monitor")
	_send(game, _key(KEY_SPACE))
	settle.call()
	_expect(not bool(game.get("monitor_up")), tag + "Space did not close the monitor")
	var shift_player = game.get("player")
	_expect(shift_player == null or not bool(shift_player.get("jump_enabled")), tag + "Space would also jump")
	_send(game, _key(KEY_U))
	settle.call()
	_expect(bool(game.get("monitor_up")), tag + "U (the alias) did not open the monitor")
	var start_room := String(game.get("monitor_room"))
	# cycle forward through all cameras and back
	var room := start_room
	for step in rooms.size():
		_send(game, _key(KEY_RIGHT))
		settle.call()
		var want := String(rooms[posmod(rooms.find(room) + 1, rooms.size())])
		_expect(String(game.get("monitor_room")) == want, tag + "Right from %s did not reach %s (got %s)" % [room, want, game.get("monitor_room")])
		room = String(game.get("monitor_room"))
	_expect(room == start_room, tag + "eight Right presses did not come back to the first camera")
	for step in rooms.size():
		_send(game, _key(KEY_LEFT))
		var want2 := String(rooms[posmod(rooms.find(room) - 1, rooms.size())])
		_expect(String(game.get("monitor_room")) == want2, tag + "Left from %s did not reach %s" % [room, want2])
		room = String(game.get("monitor_room"))
	# the number keys and the number pad pick each camera; the gamepad d-pad cycles
	for n in range(1, mini(9, rooms.size() + 1)):
		_send(game, _key(KEY_1 + n - 1))
		_expect(String(game.get("monitor_room")) == room_for.call(n), tag + "key %d did not pick camera %d" % [n, n])
		_send(game, _key(KEY_KP_1 + n - 1))
		_expect(String(game.get("monitor_room")) == room_for.call(n), tag + "number pad %d did not pick camera %d" % [n, n])
	_send(game, _key(KEY_1))
	_send(game, _joy(JOY_BUTTON_DPAD_RIGHT))
	_expect(String(game.get("monitor_room")) == room_for.call(2), tag + "the d-pad right did not go to camera 2")
	_send(game, _joy(JOY_BUTTON_DPAD_LEFT))
	_expect(String(game.get("monitor_room")) == room_for.call(1), tag + "the d-pad left did not go back to camera 1")
	# the old office_camera_n actions are not read any more
	var old := InputEventAction.new()
	old.action = "office_camera_5"
	old.pressed = true
	var before := String(game.get("monitor_room"))
	_send(game, old)
	_expect(String(game.get("monitor_room")) == before, tag + "the old office_camera_5 action still switches cameras")
	# pause with the monitor up: keys are ignored; resume: they work again
	var pause := InputEventAction.new()
	pause.action = "pause"
	pause.pressed = true
	_send(game, pause)
	_send(game, _key(KEY_5))
	_expect(String(game.get("monitor_room")) == before, tag + "a camera key worked while paused")
	_send(game, pause)
	_send(game, _key(KEY_5))
	_expect(String(game.get("monitor_room")) == room_for.call(5), tag + "camera keys stopped working after pause and resume")
	# close with the key, camera keys dead again, reopen, close with use
	_send(game, _key(KEY_U))
	_expect(not bool(game.get("monitor_up")), tag + "U did not close the monitor")
	var kept := String(game.get("monitor_room"))
	_send(game, _key(KEY_7))
	_send(game, _key(KEY_RIGHT))
	_expect(String(game.get("monitor_room")) == kept and not bool(game.get("monitor_up")), tag + "camera keys acted with the monitor down")
	_send(game, _key(KEY_U))
	_expect(bool(game.get("monitor_up")) and String(game.get("monitor_room")) == kept, tag + "re-entering the monitor lost the camera or did not open it")
	_send(game, _key(KEY_8))
	_expect(String(game.get("monitor_room")) == room_for.call(8), tag + "camera keys did not work after re-entering the monitor")
	var use := InputEventAction.new()
	use.action = "interact"
	use.pressed = true
	_send(game, use)
	_expect(not bool(game.get("monitor_up")), tag + "use did not close the monitor")
	# the key is not stuck: three open/close rounds
	for i in 3:
		_send(game, _key(KEY_U))
		_expect(bool(game.get("monitor_up")), tag + "open round %d failed" % i)
		_send(game, _key(KEY_U))
		_expect(not bool(game.get("monitor_up")), tag + "close round %d failed" % i)
	# the hint line follows the monitor
	_send(game, _key(KEY_U))
	var hud = game.get("hud")
	_expect(hud != null and String(hud.hint_label.text).contains("close"), tag + "the hint line does not switch to the monitor keys")
	_send(game, _key(KEY_U))
	_expect(hud != null and String(hud.hint_label.text).contains("doors"), tag + "the hint line did not come back")



## The camera screen's CLOSE CAMERAS button and key guide: inside the viewport and clear of the picture, the camera map and the labels at the three test sizes, clickable
## (it asks to close), focusable, and its text follows a rebound key.
func _check_camera_screen(host: Node) -> void:
	NightWatchControls.register()
	for size in [Vector2i(480, 270), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		host.add_child(vp)
		var hud := NightWatchHud.new()
		vp.add_child(hud)
		await host.get_tree().process_frame
		hud.set_monitor_guide(NightWatchControls.hint_line(true, ["nw_meet"]), NightWatchControls.key_text(NightWatchControls.MONITOR))
		hud.show_monitor(true)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		var btn := hud.close_button.get_global_rect()
		var guide := hud.monitor_guide.get_global_rect()
		var feed := (hud.monitor_root.find_child("FeedContainer", true, false) as Control).get_global_rect()
		var map := (hud.monitor_root.find_child("CamMap", true, false) as Control).get_global_rect()
		var tag := "[%s] " % str(size)
		_expect(screen.encloses(btn) and screen.encloses(guide), tag + "the CLOSE CAMERAS button or the guide leaves the screen")
		_expect(not btn.intersects(feed) and not guide.intersects(feed), tag + "the close strip covers the camera picture")
		_expect(not btn.intersects(map) and not guide.intersects(map), tag + "the close strip covers the camera map")
		_expect(not btn.intersects(guide), tag + "the button and the guide overlap")
		_expect(not guide.intersects(hud.cam_label.get_global_rect()) and not guide.intersects(hud.rec_label.get_global_rect()), tag + "the guide covers the camera labels")
		_expect(hud.close_button.focus_mode == Control.FOCUS_NONE and hud.close_button.visible and not hud.close_button.disabled, tag + "the close button cannot be focused or clicked")
		_expect(hud.close_button.text.begins_with("CLOSE CAMERAS") and hud.close_button.text.to_upper().contains("SPACE"), tag + "the close button does not name the key: %s" % hud.close_button.text)
		_expect(hud.monitor_guide.text.contains("meet her eyes") and hud.monitor_guide.text.contains("1-8"), tag + "the guide lacks the camera keys or the Night 7 meet key: %s" % hud.monitor_guide.text)
		var clicks := [0]
		hud.cameras_requested.connect(func(): clicks[0] += 1)
		hud.close_button.pressed.emit()
		_expect(clicks[0] == 1, tag + "the close button did not ask to close the cameras")
		vp.queue_free()
		await host.get_tree().process_frame
	# the text follows a rebind
	NightWatchControls.rebind(NightWatchControls.MONITOR, KEY_O)
	var vp2 := SubViewport.new()
	vp2.size = Vector2i(480, 270)
	vp2.disable_3d = true
	host.add_child(vp2)
	var hud2 := NightWatchHud.new()
	vp2.add_child(hud2)
	await host.get_tree().process_frame
	hud2.set_monitor_guide(NightWatchControls.hint_line(true), NightWatchControls.key_text(NightWatchControls.MONITOR))
	_expect(hud2.close_button.text.ends_with("O") and hud2.monitor_guide.text.contains("O or"), "the close button and guide do not follow the rebound key: %s / %s" % [hud2.close_button.text, hud2.monitor_guide.text])
	vp2.queue_free()
	NightWatchSave.clear_key_overrides()
	NightWatchControls.unregister()
	await host.get_tree().process_frame


# --- the mouse follows the monitor ---------------------------------------------------------------------------------------------------------------------------

## Real events through the viewport (so the GUI sees them first, as in the app): after closing the monitor by ANY route the cursor is captured again with no click,
## a look motion turns the view, and opening it frees the cursor. Every mode with a monitor, every route, plus the Pause and CAMERAS buttons (unwired in all modes but Classic) and a timed monitor (Masked Hours).
func _check_mouse_capture(host: Node, modes: Array) -> void:
	for mode_id in modes:
		NightWatchSession.start_mode(String(mode_id), 1, {}, 77)
		var game := (load(String(NightWatchModeRegistry.SCENES[mode_id])) as PackedScene).instantiate()
		game.set("manual_clock", true)
		host.add_child(game)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var tag := "[%s mouse] " % mode_id
		var player = game.get("player")
		if player == null or not player.has_method("_apply_look_rotation"):
			game.queue_free()
			await host.get_tree().process_frame
			continue
		var hud = game.get("hud")
		var vp := host.get_viewport()
		var routes := {
			"Space": func(): _push(vp, _key(KEY_SPACE)),
			"U": func(): _push(vp, _key(KEY_U)),
			"use": func(): _push(vp, _key(KEY_E)),
			"button": func(): hud.cameras_requested.emit(),
			"pause and resume": func(): game.call("set_paused", true); game.call("set_paused", false); game.call("close_monitor"),
			"night ends": func(): game.call("close_monitor"),
		}
		for route in routes:
			game.call("open_monitor")
			await host.get_tree().process_frame
			_expect(bool(game.get("monitor_up")) and not MouseLock.is_captured(), tag + "opening the monitor did not free the cursor (%s)" % route)
			routes[route].call()
			if game.has_method("advance_ms"):
				game.call("advance_ms", 900.0)   # a timed monitor lowers over a moment; the cursor comes back when it is down
			await host.get_tree().process_frame
			_expect(not bool(game.get("monitor_up")), tag + "%s did not close the monitor" % route)
			_expect(MouseLock.is_captured(), tag + "after closing by %s the cursor is not captured again" % route)
			_expect(host.get_viewport().gui_get_focus_owner() == null, tag + "after closing by %s a control still holds focus (Space would press it)" % route)
			var yaw := float(player.get("_yaw"))
			var motion := InputEventMouseMotion.new()
			motion.relative = Vector2(30, 0)
			player._unhandled_input(motion)
			_expect(not is_equal_approx(yaw, float(player.get("_yaw"))), tag + "after closing by %s a mouse motion did not turn the view" % route)
		# the PAUSE button: the pause card frees the cursor, resuming takes it back
		hud.pause_requested.emit()
		_expect(not MouseLock.is_captured() and get_tree_paused(host), tag + "the Pause button did not pause with a free cursor")
		game.call("set_paused", false)
		_expect(MouseLock.is_captured(), tag + "resuming did not capture the cursor again")
		# the rapid Space: open, close, open, close with held-key repeats between
		for i in 4:
			_push(vp, _key(KEY_SPACE))
			var echo := _key(KEY_SPACE)
			echo.echo = true
			_push(vp, echo)
			_push(vp, _key(KEY_SPACE, false))
		if game.has_method("advance_ms"):
			game.call("advance_ms", 900.0)
		await host.get_tree().process_frame
		_expect(not bool(game.get("monitor_up")) and MouseLock.is_captured(), tag + "four Space taps (with repeats and releases) left the monitor/cursor in the wrong state")
		# the end of the night: the monitor closes by itself and the cursor is free for the end card, not captured
		game.call("open_monitor")
		game.call("_freeze_player")
		game.call("close_monitor")
		_expect(not MouseLock.is_captured(), tag + "the end card did not keep the cursor free")
		game.queue_free()
		await host.get_tree().process_frame
		MouseLock.release_all()


func _push(vp: Viewport, ev: InputEvent) -> void:
	vp.push_input(ev)


func get_tree_paused(host: Node) -> bool:
	return host.get_tree().paused
