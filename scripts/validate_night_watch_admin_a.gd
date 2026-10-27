extends RefCounted

## The admin menu for Dead Air, Bedtime and The Facility (NightWatchAdmin on the shared AdminMenu): the gate (null for a non-admin, "admin" in the hint line only for an admin), the
## sections (SHIFT, the hunters, the mode's own), a permission on every entry, the layout of the tabs at 480x270 / 1280x720 / 1920x1080, and that EVERY control really changes the
## game's state through its public hook: each entry is run from a prepared state and the game's state is compared before and after (an items group is run last item first, then in order,
## so each item has to move the state). Win and lose are run on fresh games.

var _failures := 0
const MODES := {
	"lure": {"scene": "res://scenes/night_watch_lure.tscn", "title": "DEAD AIR", "level": 4},
	"bedroom": {"scene": "res://scenes/night_watch_bedroom.tscn", "title": "BEDTIME", "level": 4},
	"story": {"scene": "res://scenes/night_watch_story.tscn", "title": "THE FACILITY", "level": 4},
}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _game(host: Node, mode: String) -> Node:
	NightWatchSession.start_mode(mode, int(MODES[mode]["level"]), {}, 4242)
	var game := (load(String(MODES[mode]["scene"])) as PackedScene).instantiate()
	game.set("manual_clock", true)
	host.add_child(game)
	return game


## What the game's state is, for before / after comparisons.
func _snap(mode: String, game: Node) -> String:
	var sim = game.get("sim")
	var d := {"session": [NightWatchSession.mode_id, NightWatchSession.night], "call": [game.hud.call_script != null, game.hud.call_script != null and game.hud.call_script.done, game.hud.call_script != null and game.hud.call_script.muted, game.hud.shown_call],
		"flags": [game.admin_is_frozen(), game.admin_is_god(), game.admin_no_scare(), game.admin_infinite_power(), game.has_method("admin_is_noclip") and game.admin_is_noclip(),
			game.has_method("admin_is_reveal") and game.admin_is_reveal()], "over": sim.over, "speed": sim.hunter_speed, "elapsed": sim.elapsed}
	match mode:
		"lure":
			var k: Dictionary = sim.killer
			d["l"] = [sim.stress, sim.temp, sim.cold, sim.heat, sim.heater_on, sim.fan_on, sim.seals, sim.systems, k["room"], k["lureLeft"], k["target"], sim.phantom, sim.lure_cool, sim.lvl,
				sim.climate, sim.phantom_levels, game.hud.cam_map.blips]
		"bedroom":
			d["b"] = [sim.battery, sim.loxelle["state"], sim.javelle["state"], sim.haelith["p"], sim.idle, sim.levels, game.held, sim.restless, (game._models["javelle"] as Node3D).visible]
		"story":
			d["s"] = [sim.noise, sim.charge, sim.task_idx, sim.puzzle.get("kind", ""), sim.room, sim.quenelle["state"], sim.opalie["dist"], sim.porcelle["dist"], sim.levels]
	return JSON.stringify(d)


## A state in which every control has something to change.
func _prep(mode: String, game: Node) -> void:
	var sim = game.get("sim")
	game.admin_skip_call()
	match mode:
		"lure":
			sim.lure_cool = 5000.0
			sim.cold = 40.0
			sim.heat = 40.0
			sim.temp = 85.0
			sim.stress = 30.0
			sim.has_climate = true
			sim.has_fan = true
		"bedroom":
			sim.idle = 0.0
			sim.haelith["p"] = 20.0
			sim.battery = 80.0
		"story":
			sim.noise = 10.0
			sim.charge = 70.0
			sim.quenelle["state"] = "open"


func run(host: Node) -> int:
	for mode in MODES:
		await _check_mode(host, String(mode))
	# win and lose on fresh games
	for mode in MODES:
		for verb in ["win", "lose"]:
			var g := await _fresh(host, String(mode))
			g.admin_set_no_scare(true)
			g.call("admin_%s" % verb)
			var want_state := 2 if verb == "win" else 3   # State.WON / State.LOST in all three scenes
			_expect(int(g.get("state")) == want_state and g.hud.end_root.visible, "%s: the admin %s did not end the shift" % [mode, verb])
			g.queue_free()
			await host.get_tree().process_frame
	NightWatchSession.start(1)
	if _failures == 0:
		print("  night_watch_admin_a  gate, sections, layout at three sizes and every control changes state, for Dead Air, Bedtime and The Facility")
	return _failures


func _fresh(host: Node, mode: String) -> Node:
	var g := _game(host, mode)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	return g


func _check_mode(host: Node, mode: String) -> void:
	var game := await _fresh(host, mode)
	var tag := "[%s] " % mode
	# --- the gate and the hint
	_expect(NightWatchAdmin.attach(game, false) == null, tag + "a non-admin got the admin menu")
	_expect(game.admin_menu != null and game.admin_menu is AdminMenu, tag + "an admin did not get the menu")
	_expect(String(game.hud.hint_label.text).contains("admin"), tag + "the hint line does not list the admin key: " + String(game.hud.hint_label.text))
	var entries := NightWatchAdmin.entries(game)
	var headings := []
	for e in entries:
		if e.has("heading") and not e.has("items") and not e.has("hunter_tool") and not e.has("action"):
			headings.append(String(e["heading"]).split(" // ")[0])
	for want in ["SHIFT", "%s SPECIFIC" % MODES[mode]["title"]]:
		_expect(headings.has(want), tag + "no %s section: %s" % [want, str(headings)])
	var provider_entries := 0
	for e in entries:
		if e.has("action") or e.has("hunter_tool"):
			_expect(String(e.get("permission", "")) != "", tag + "an admin entry has no permission scope: %s" % str(e.get("label", e.get("heading", "?"))))
			provider_entries += 1
	_expect(provider_entries >= 10, tag + "too few admin controls (%d)" % provider_entries)
	# --- the menu opens and its tabs fit at three sizes
	game.admin_menu.call("_set_open", true)
	_expect(game.admin_menu.is_open(), tag + "the admin menu did not open")
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
		_expect(Rect2(Vector2.ZERO, Vector2(size)).encloses(panel.get_global_rect()), tag + "[%s] the admin panel leaves the screen: %s" % [str(size), str(panel.get_global_rect())])
		var tabs := menu.get("_tabs") as TabBar
		var titles := []
		for i in tabs.tab_count:
			titles.append(tabs.get_tab_title(i))
		_expect(titles.has("SHIFT") and titles.has("%s SPECIFIC" % MODES[mode]["title"]), tag + "[%s] the tabs lack a section: %s" % [str(size), str(titles)])
		vp.queue_free()
		await host.get_tree().process_frame
	# --- every control changes state
	_prep(mode, game)
	var exercised := 0
	for e in entries:
		var label := String(e.get("label", e.get("heading", "?")))
		if label.begins_with("WIN THE") or label.begins_with("LOSE THE") or label.begins_with("JUMP TO SHIFT"):
			continue
		if e.has("hunter_tool"):
			for act in e["hunter_tool"]:
				var changed := false
				for hid in e["hunters"]:
					var before := _snap(mode, game)
					(act["call"] as Callable).call(String(hid), "")
					if _snap(mode, game) != before:
						changed = true
				_expect(changed, tag + "the hunter control '%s' changed nothing for any hunter" % String(act["label"]))
				exercised += 1
		elif e.has("items"):
			var items: Array = e["items"]
			if items.is_empty():
				continue
			(e["action"] as Callable).call(String(items[items.size() - 1]))
			for item in items:
				var before2 := _snap(mode, game)
				(e["action"] as Callable).call(String(item))
				_expect(_snap(mode, game) != before2, tag + "'%s' item '%s' changed nothing" % [label, str(item)])
				exercised += 1
		elif e.has("action"):
			var before3 := _snap(mode, game)
			if e.has("state"):
				var s0: bool = (e["state"] as Callable).call()
				(e["action"] as Callable).call()
				_expect((e["state"] as Callable).call() != s0, tag + "toggle '%s' did not flip" % label)
			else:
				(e["action"] as Callable).call()
			_expect(_snap(mode, game) != before3, tag + "'%s' changed nothing" % label)
			exercised += 1
		# keep the clock and god out of the way of the rest
		game.admin_set_frozen(false)
		game.admin_set_god(false)
		if game.get("state") != null and int(game.get("state")) != 0:
			_expect(false, tag + "'%s' ended the shift" % label)
			break
	_expect(exercised >= 20, tag + "only %d admin controls were exercised" % exercised)
	# the jump sets the session
	NightWatchSession.start_mode(mode, 1)
	game.admin_jump_to(5)
	_expect(NightWatchSession.mode_id == mode and NightWatchSession.night == 5, tag + "JUMP TO SHIFT did not set the session")
	game.queue_free()
	await host.get_tree().process_frame
