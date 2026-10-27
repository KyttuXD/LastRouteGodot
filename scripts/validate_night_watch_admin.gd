extends RefCounted

## The Night Watch admin menu (NightWatchAdmin on the shared AdminMenu): the gate (null for a non-admin, the "0 admin" hint only for an admin), the menu opens, every section exists
## (SHIFT controls, ZELLIA AND THE NIGHT, the mode's own), the layout fits at 480x270 / 1280x720 / 1920x1080, and EVERY control really changes game state through the game's public hooks
## (jump, time, freeze, power, infinite power, god, no jumpscare, speed, AI level, send a hunter, doors, door lights, call, reveal, win, lose, noclip, Kathy's meet). A mode with no provider
## still gets the common section; each lane adds its provider line in NightWatchAdmin.PROVIDERS and its section is checked here when it exists.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _find(entries: Array, key: String, value: String) -> Dictionary:
	for e in entries:
		if String(e.get(key, "")) == value:
			return e
	return {}


func _game(host: Node, level: int, custom := {}) -> NightWatchGame:
	NightWatchSession.start_mode("classic", level, custom, 4242)
	var game := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	game.manual_clock = true
	host.add_child(game)
	return game


func run(host: Node) -> int:
	var game := _game(host, 3)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	# --- the gate: a non-admin gets nothing, an admin gets the menu and the hint
	_expect(NightWatchAdmin.attach(game, false) == null, "a non-admin got the admin menu")
	_expect(game.admin_menu != null and game.admin_menu is AdminMenu, "an admin did not get the menu (headless validation counts as admin)")
	_expect(NightWatchControls.hint_line(false, game._hint_actions()).contains("0 admin"), "the hint line does not list the admin key for an admin")
	_expect(not NightWatchControls.hint_line(false, game.office.spec.controls).contains("admin"), "the hint line lists the admin key for everyone")
	var entries := NightWatchAdmin.entries(game)
	var headings := []
	for e in entries:
		if e.has("heading") and not e.has("items") and not e.has("hunter_tool") and not e.has("action"):
			headings.append(String(e["heading"]).split(" // ")[0])
	for want in ["SHIFT", "ZELLIA AND THE NIGHT", "CLASSIC SPECIFIC"]:
		_expect(headings.has(want), "the admin menu has no %s section: %s" % [want, str(headings)])
	for e in entries:
		if e.has("action") or e.has("hunter_tool"):
			_expect(String(e.get("permission", "")) != "", "an admin entry has no permission scope: %s" % str(e.get("label", e.get("heading", "?"))))
	# --- the menu opens and its layout fits at three sizes
	game.admin_menu.call("_set_open", true)
	_expect(game.admin_menu.is_open(), "the admin menu did not open")
	game.admin_menu.close()
	for size in [Vector2i(480, 270), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		host.add_child(vp)
		var holder := Node.new()
		vp.add_child(holder)
		var menu := AdminMenu.attach(holder, func() -> String: return NightWatchAdmin.status(game), entries)
		await host.get_tree().process_frame
		menu.call("_set_open", true)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var panel := menu.get("_panel") as Control
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		_expect(screen.encloses(panel.get_global_rect()), "[%s] the admin panel leaves the screen: %s" % [str(size), str(panel.get_global_rect())])
		var tabs := menu.get("_tabs") as TabBar
		var titles := []
		for i in tabs.tab_count:
			titles.append(tabs.get_tab_title(i))
		_expect(titles.has("SHIFT") and titles.has("CLASSIC SPECIFIC"), "[%s] the admin tabs lack a section: %s" % [str(size), str(titles)])
		vp.queue_free()
		await host.get_tree().process_frame
	# --- every control changes state through its hook
	var sim := game.sim
	game.admin_jump_to(5)
	_expect(NightWatchSession.mode_id == "classic" and NightWatchSession.night == 5, "JUMP TO SHIFT did not set the session")
	game.admin_set_hour(3)
	_expect(sim.hour() == 3 and game._elapsed_ms == sim.elapsed, "SET TIME did not move the clock")
	game.admin_set_frozen(true)
	var before := sim.elapsed
	game.advance_ms(5000.0)
	_expect(game.admin_is_frozen() and sim.elapsed == before, "the frozen clock still ran")
	game.admin_set_frozen(false)
	game.admin_set_power(10.0)
	_expect(is_equal_approx(sim.power, 10.0) and not sim.out, "SET POWER 10 did not set the power")
	game.admin_set_infinite_power(true)
	game.advance_ms(20000.0)
	_expect(game.admin_infinite_power() and is_equal_approx(sim.power, 10.0), "infinite power still drained")
	game.admin_set_infinite_power(false)
	game.admin_set_power(0.0)
	_expect(sim.out, "SET POWER 0 did not put the power out")
	game.admin_set_power(100.0)
	game.admin_set_hunter_speed(4.0)
	_expect(is_equal_approx(sim.hunter_speed, 4.0), "the hunter speed did not change")
	game.admin_set_hunter_speed(1.0)
	game.admin_set_hunter_level("aki", 17)
	_expect((sim.hunters["aki"] as NightWatchStalker).base == 17, "AI LEVEL did not change Aki")
	game.admin_place_hunter("aki", "kitchen")
	_expect((sim.hunters["aki"] as NightWatchStalker).room == "kitchen", "SEND TO KITCHEN did not move Aki")
	game.admin_place_hunter("dovelle", "doorR")
	var dv := sim.hunters["dovelle"] as NightWatchStalker
	_expect(dv.room == "doorR" and dv.door() == "doorR", "SEND TO RIGHT DOOR did not make doorR her door")
	game.admin_set_door("doorR", true)
	_expect(bool(game.door_shut["doorR"]), "SHUT RIGHT DOOR did not shut it")
	game.admin_set_door("doorR", false)
	game.set_light("doorL", true)
	_expect(bool(game.light_held["doorL"]), "LEFT LIGHT ON did not hold the light")
	game.set_light("doorL", false)
	# god mode: an unanswered door does not catch you; without it, it does
	game.admin_set_god(true)
	dv.admin_send(dv.door())
	for i in 80:
		game.advance_ms(250.0)
	_expect(game.state == NightWatchGame.State.PLAYING, "god mode still got caught")
	game.admin_set_god(false)
	dv.admin_send(dv.door())
	for i in 80:
		game.advance_ms(250.0)
	_expect(game.state == NightWatchGame.State.LOST, "without god mode the open door did not catch her prey")
	game.queue_free()
	await host.get_tree().process_frame
	# call, reveal, noclip, no jumpscare, win, lose on fresh games
	var g2 := _game(host, 2)
	await host.get_tree().process_frame
	g2.admin_play_call()
	g2.advance_ms(100.0)
	g2.advance_ms(3000.0)
	_expect(g2.hud.call_script != null and g2.hud.call_script.open, "PLAY ZELLIA'S CALL did not open the call")
	g2.admin_skip_call()
	_expect(not g2.hud.call_script.open and not g2.hud.call_panel.visible, "SKIP THE CALL did not end the call")
	g2.admin_set_reveal(true)
	_expect(g2.admin_is_reveal() and g2.hud.cam_map.blips.size() > 0, "REVEAL HUNTERS put nothing on the map")
	g2.admin_set_reveal(false)
	_expect(g2.hud.cam_map.blips.is_empty(), "turning REVEAL off left the dots")
	g2.admin_set_noclip(true)
	_expect(g2.admin_is_noclip() and g2.player.admin_noclip, "NOCLIP did not switch the player to noclip")
	g2.admin_set_noclip(false)
	g2.admin_set_no_scare(true)
	g2.admin_lose()
	_expect(g2.state == NightWatchGame.State.LOST and g2.hud.end_root.visible, "LOSE THE SHIFT with no jumpscare did not show the card at once")
	g2.queue_free()
	await host.get_tree().process_frame
	var g3 := _game(host, 2)
	await host.get_tree().process_frame
	g3.admin_win()
	_expect(g3.state == NightWatchGame.State.WON and g3.hud.end_root.visible, "WIN THE SHIFT did not win")
	g3.queue_free()
	await host.get_tree().process_frame
	# Night 7: force Kathy's meet
	var g7 := _game(host, 7)
	await host.get_tree().process_frame
	_expect(g7.admin_force_meet() == "met", "KATHY: FORCE MEET did not meet her eyes")
	_expect(_find(NightWatchAdmin.entries(g7), "label", "KATHY: FORCE MEET HER EYES").size() > 0, "the Kathy entry is missing on Night 7")
	_expect(_find(g7.admin_menu.get("_actions"), "label", "KATHY: FORCE MEET HER EYES").size() > 0, "the live menu on Night 7 has no Kathy entry (it was built before the sim existed?)")
	g7.queue_free()
	await host.get_tree().process_frame
	NightWatchSession.start(1)
	if _failures == 0:
		print("  night_watch_admin  gate, sections, layout at three sizes, and every Classic control changes game state through its hook")
	return _failures
