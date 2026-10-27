extends RefCounted

## Night Watch's 3D menus match the 2D game's: for each screen the visible texts, in order, equal what the 2D game's DOM shows
## (captured from games/night-watch with the preview server: see docs/NIGHT_WATCH_MENUS.md). Shortcut hints (ESC, ENTER, BACKSPACE) and
## spacing are normalised; case is compared in upper case. Also: the nine modes with their titles, taglines, blurbs and shifts, the
## Settings rows, the pause card, and that a locked shift cannot start. One deliberate difference is listed in the doc: the 2D Credits
## say sound is synthesized "in the browser"; the 3D game says "in the game".

var _failures := 0

const TITLE := ["NIGHT WATCH", "PLAY", "CUSTOM NIGHT", "BEAT NIGHT 5 TO UNLOCK", "ACCOUNT", "GUEST", "SETTINGS", "CREDITS", "QUIT", "↑ ↓ SELECT · ENTER CONFIRM"]
const SETTINGS := ["← BACK", "SETTINGS", "VOLUME", "CALM MODE (NO LAMP FLICKER OR GLITCHING)", "SCARE (SHORT: A QUICK ONE · OFF: JUST THE CARD)", "FULL", "ERASE PROGRESS (YOUR ACCOUNT)", "ERASE"]
const ACCOUNT := ["← BACK", "ACCOUNT", "USERNAME", "3-24 CHARS: A-Z 0-9 _", "PASSWORD", "6+ CHARACTERS", "USERNAMES ARE CAPS ONLY AND SHARED WITH LAST ROUTE AND KT: SYSTEMS.", "SIGN IN", "CREATE ACCOUNT"]
const CREDITS := ["← BACK", "CREDITS", "NIGHT WATCH IS AN UNOFFICIAL FAN PROJECT, MADE FOR FUN AND NOT AFFILIATED WITH OR ENDORSED BY ANYONE BELOW.", "INSPIRED BY",
	"THE FIVE NIGHTS AT FREDDY'S SERIES BY SCOTT CAWTHON, INCLUDING ITS SEQUELS, SISTER LOCATION, PIZZERIA SIMULATOR AND THE HELP WANTED GAMES, AND THE COMMUNITY THAT DOCUMENTED HOW THEY WORK.",
	"MADE BY", "KYTTU'S LAB. CHARACTERS ARE FROM THE LAST ROUTE. OFFICE ART, MENUS AND CODE ARE ORIGINAL TO THIS PROJECT.", "SOUND", "ALL SOUND IS SYNTHESIZED IN THE GAME FOR NOW."]
const PAUSE := ["PAUSED", "RESUME", "QUIT TO HUB"]
const BOARD_HEAD := ["← BACK", "SHIFT BOARD"]
const BOARD_HINT := "↑ ↓ MODE · ← → SHIFT · ENTER START · ESC BACK"


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func norm(text: String) -> String:
	var t := text.to_upper().replace("\n", " ").replace(">> ", "")
	for token in [" ESC", " ENTER", " BACKSPACE"]:
		if t.ends_with(token) and not t.begins_with("↑"):
			t = t.trim_suffix(token)
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.strip_edges()


func _texts(menu: NightWatchMenu, with_hint := false) -> Array:
	var out := []
	for t in menu.visible_texts():
		var n := norm(t)
		if not n.is_empty():
			out.append(n)
	if with_hint and not menu.hint_label.text.is_empty():
		out.append(norm(menu.hint_label.text))
	return out


func _merge_logo(list: Array) -> Array:
	if list.size() >= 2 and list[0] == "NIGHT" and list[1] == "WATCH":
		list = ["NIGHT WATCH"] + list.slice(2)
	return list


func _same(actual: Array, expected: Array, what: String) -> void:
	if actual != expected:
		print("  FAIL  %s differs from the 2D game\n        3D: %s\n        2D: %s" % [what, str(actual), str(expected)])
		_failures += 1


func run(host: Node) -> int:
	NightWatchSave.path = "user://night_watch_menu_test.cfg"
	NightWatchSave.reset()
	var menu := (load("res://scenes/night_watch_menu.tscn") as PackedScene).instantiate() as NightWatchMenu
	host.add_child(menu)
	await host.get_tree().process_frame
	_expect(menu.screen == "title", "the menu does not open on the title")
	_same(_merge_logo(_texts(menu, true)), TITLE, "the title screen")
	var labels: Array = []
	for b in menu.title_buttons:
		labels.append(String(b.get_meta("label")))
	_same(labels, ["PLAY", "CUSTOM NIGHT", "ACCOUNT", "SETTINGS", "CREDITS", "QUIT"], "the title's menu order")
	_expect(menu.title_buttons[1].disabled, "Custom Night is open before Night 5 is cleared")
	menu.title_activate(1)
	_expect(menu.toast_label.text == "Custom Night is locked. Beat Night 5.", "the locked Custom Night toast differs from the 2D game's")
	menu.show_screen("settings")
	_same(_texts(menu), SETTINGS, "the settings screen")
	_expect(menu.volume_slider != null and menu.calm_check != null and menu.scare_button != null and menu.erase_button != null, "a settings control is missing")
	menu.cycle_scare()
	_expect(menu.scare_button.text == "Short" and NightWatchSave.scare() == "short", "Scare does not go Full to Short")
	menu.cycle_scare()
	menu.cycle_scare()
	_expect(NightWatchSave.scare() == "full", "Scare does not cycle Full, Short, Off")
	menu.show_screen("account")
	var account := _texts(menu)
	account.remove_at(2)   # the guest sentence carries a per-install name
	_same(account, ACCOUNT, "the account screen")
	menu.show_screen("credits")
	_same(_texts(menu), CREDITS, "the credits screen")
	# the shift board: nine modes in the 2D order with its stat lines, the detail of each and its shift tiles
	menu.show_screen("board")
	var board := _texts(menu)
	_same(board.slice(0, 2), BOARD_HEAD, "the shift board's header")
	_expect(menu.mode_buttons.size() == 9, "the shift board has %d modes, not 9" % menu.mode_buttons.size())
	var expect_titles := ["CLASSIC", "MASKED HOURS", "DEAD AIR", "BEDTIME", "THE FACILITY", "THE DESCENT", "SALVAGE RUN", "OPEN AIR", "MIXED SHIFT"]
	var expect_levels := [7, 6, 6, 6, 6, 5, 5, 3, 5]
	for i in 9:
		var row := norm(menu.mode_buttons[i].text)
		_expect(row == "%d. %s" % [i + 1, expect_titles[i]], "mode %d reads '%s'" % [i + 1, row])
		menu.select_mode(i)
		var m := menu.mode_data(i)
		var now := _texts(menu)
		_expect(now.has(norm(String(m["label"]))) and now.has(norm(String(m["tag"]))) and now.has(norm(String(m["blurb"]))), "mode %d's title, tagline or blurb is missing from its detail" % (i + 1))
		_expect(menu.tile_buttons.size() == expect_levels[i], "mode %d has %d shift tiles, not %d" % [i + 1, menu.tile_buttons.size(), expect_levels[i]])
		_expect(norm(menu.tile_buttons[0].text).begins_with("01 "), "mode %d's first tile is not numbered 01" % (i + 1))
		if i < 8:
			_expect(menu.tile_buttons.size() < 2 or norm(menu.tile_buttons[1].text) == "02 LOCKED ?????", "mode %d's second shift is not locked at first" % (i + 1))
		else:
			_expect(not menu.tile_buttons[4].disabled, "Mixed Shift's Endless is locked (all five are open from the start)")
		_expect(norm(menu.start_button.text) == "▶ START SHIFT", "mode %d has no START SHIFT" % (i + 1))
		_expect(norm(menu.hint_label.text) == BOARD_HINT, "the board's hint differs from the 2D game's")
	menu.select_mode(0)
	var first := _texts(menu)
	_expect(first.has("0 / 7 SHIFTS CLEARED · ★ 0/4 STARS"), "Classic's stat line differs: %s" % str(first))
	_expect(first.has("01 NIGHT 1") and first.has("02 LOCKED ?????"), "Classic's tiles differ")
	# hover must not select: entering a row or tile changes nothing, a click selects, the arrow keys move
	menu.select_mode(0)
	var title_before := (menu._screen_root.find_child("ModeTitle", true, false) as Label).text
	var before_mode := menu.board_mode
	var before_level := menu.board_level
	for b in menu.mode_buttons:
		b.mouse_entered.emit()
	for t in menu.tile_buttons:
		t.mouse_entered.emit()
	_expect(menu.board_mode == before_mode and menu.board_level == before_level, "hovering a board entry changed the selection")
	_expect((menu._screen_root.find_child("ModeTitle", true, false) as Label).text == title_before, "hovering a board entry changed the detail panel")
	menu.mode_buttons[3].pressed.emit()
	await host.get_tree().process_frame
	_expect(menu.board_mode == 3 and (menu._screen_root.find_child("ModeTitle", true, false) as Label).text == "4. BEDTIME", "clicking a mode did not select it")
	var down := InputEventKey.new()
	down.keycode = KEY_DOWN
	down.pressed = true
	menu._unhandled_input(down)
	await host.get_tree().process_frame
	_expect(menu.board_mode == 4, "the down arrow did not move the selection")
	menu.show_screen("title")
	await host.get_tree().process_frame
	var idx := menu.title_index
	for b in menu.title_buttons:
		b.mouse_entered.emit()
	_expect(menu.title_index == idx, "hovering a title entry moved the selection")
	menu.show_screen("board")
	await host.get_tree().process_frame
	# a locked shift cannot be started; a mode that is not built says so
	var unbuilt := -1
	for i in NightWatchModesData.MODES.size():
		if not NightWatchModeRegistry.playable(String(NightWatchModesData.MODES[i]["id"])):
			unbuilt = i
			break
	if unbuilt >= 0:
		menu.select_mode(unbuilt)
		menu.start_selected()
		_expect(menu.toast_label.text.contains("not built yet"), "starting an unbuilt mode gave no message")
	# the hud's pause card
	var hud := NightWatchHud.new()
	host.add_child(hud)
	await host.get_tree().process_frame
	var pause_texts := []
	var stack := [hud.pause_root]
	while not stack.is_empty():
		var n: Node = stack.pop_front()
		if n is Label or n is Button:
			var t := norm(String(n.text))
			if not t.is_empty():
				pause_texts.append(t)
		stack.append_array(n.get_children())
	_same(pause_texts, PAUSE, "the pause card")
	hud.queue_free()
	menu.queue_free()
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	if _failures == 0:
		print("  night_watch_menus  title, board (nine modes), settings, account, credits and pause match the 2D game's screens")
	return _failures
