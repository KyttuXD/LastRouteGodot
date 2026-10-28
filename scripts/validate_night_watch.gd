extends RefCounted

## Night Watch (3D): the rules port reproduces the 2D game's numbers, replays deterministically, the defences work (shut door,
## light, cameras), the power and the blackout behave, and the night can be won and lost. The scene checks live further down.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## A bot that plays the night: shuts the door of whoever stands at it, keeps the monitor down.
func _play(game: NightWatchClassic, step_ms: float, bot: String = "doors") -> Array:
	var log := []
	var guard := 0
	while game.over == "" and guard < 100000:
		guard += 1
		var input := {"doorL": false, "doorR": false, "lightL": false, "lightR": false, "cam": false, "cam_room": "stage"}
		if bot == "doors":
			for door in ["doorL", "doorR"]:
				if not game.at_door(door).is_empty():
					input[door] = true
		elif bot == "lights":
			for door in ["doorL", "doorR"]:
				if not game.at_door(door).is_empty():
					input["lightL" if door == "doorL" else "lightR"] = true
		for e in game.step(step_ms, input):
			log.append(e)
	return log


## The player node subtree of a scene, normalised so the route scene's and Night Watch's can be compared line for line.
func _player_block(text: String, is_main: bool) -> String:
	var start := text.find('[node name="Player"')
	var end := text.find('[node name="HUD"') if is_main else text.length()
	var block := text.substr(start, end - start).strip_edges()
	block = block.replace('parent="World/Player/', 'parent="').replace('parent="World/Player"', 'parent="."').replace(' parent="World"', "")
	block = block.replace("unique_name_in_owner = true\n", "").replace("inventory_enabled = false\n", "").replace("jump_enabled = false\n", "")   # the one configured difference: Night Watch has no inventory
	var cap_at := text.find("[sub_resource type=\"CapsuleShape3D\"")
	return block + text.substr(cap_at, text.find("\n\n", cap_at) - cap_at)


func run(host: Node) -> int:
	# --- the table matches the 2D game (docs/ROADMAP.md, classic-logic.js, time.js)
	_expect(is_equal_approx(NightWatchData.NIGHT_MS, 270000.0), "a night is not 270 s")
	_expect(NightWatchData.move_window(1) == Vector2(12500, 15500), "level 1 wait is not 12.5-15.5 s")
	_expect(NightWatchData.move_window(10) == Vector2(8000, 11000), "level 10 wait is not 8-11 s")
	_expect(NightWatchData.move_window(20) == Vector2(3000, 6000), "level 20 wait is not 3-6 s")
	_expect(NightWatchData.effective_level(0, 5) == 0 and NightWatchData.effective_level(4, 3) == 5
		and NightWatchData.effective_level(4, 4) == 6 and NightWatchData.effective_level(4, 2) == 4, "AI step-ups at 3 and 4 AM are wrong")
	_expect(is_equal_approx(NightWatchData.blackout_ms(1), 11100.0) and is_equal_approx(NightWatchData.blackout_ms(20), 4000.0),
		"Nyxie's blackout time is wrong")
	_expect(NightWatchData.level_for("dovelle", 1) == 2 and NightWatchData.level_for("dovelle", 9) == 16
		and NightWatchData.level_for("ravelle", 1) == 0 and NightWatchData.level_for("aki", 3) == 4, "night levels are wrong")
	_expect(NightWatchData.DOOR_GRACE_MS[0] == 9000.0 and NightWatchData.DOOR_GRACE_MS[5] == 5800.0, "door grace times are wrong")
	# the graph is undirected, every camera room is reachable from both doors, the doors hang off the halls
	for room in NightWatchData.GRAPH:
		for next in NightWatchData.GRAPH[room]:
			_expect((NightWatchData.GRAPH[next] as Array).has(room), "%s -> %s is not mirrored" % [room, next])
	for door in ["doorL", "doorR"]:
		var dist := NightWatchData.distances_to(door)
		_expect(dist.size() == NightWatchData.GRAPH.size(), "%s cannot be reached from every room" % door)
	_expect(NightWatchData.cam_rooms().size() == 8 and NightWatchData.room_for_cam(4) == "westhall", "camera table is wrong")
	_expect(NightWatchData.active_hunters(1) == ["dovelle"] and NightWatchData.active_hunters(3).size() == 3
		and NightWatchData.active_hunters(4).size() == 4, "who is on the floor each night is wrong")

	# --- determinism: the same seed gives the same night, another seed a different one
	var a := NightWatchClassic.new(4, 12345)
	var b := NightWatchClassic.new(4, 12345)
	var c := NightWatchClassic.new(4, 999)
	var la := _play(a, 100.0)
	var lb := _play(b, 100.0)
	var lc := _play(c, 100.0)
	_expect(JSON.stringify(la) == JSON.stringify(lb), "the same seed did not replay the same night")
	_expect(JSON.stringify(la) != JSON.stringify(lc), "different seeds played the same night")
	_expect(a.over == "win" and is_equal_approx(a.elapsed, NightWatchData.NIGHT_MS), "a bot that shuts the door on every visitor did not win night 4")

	# --- a night nobody defends is lost to a hunter at the door (night 6, everyone keen), and the loss names her
	var open := NightWatchClassic.new(6, 7)
	_play(open, 100.0, "none")
	_expect(open.over == "caught" and open.by != "", "an undefended night 6 was not lost")
	_expect(NightWatchData.HUNTERS.has(open.by) or open.by == "nyxie", "the catcher is not a Night Watch hunter")

	# --- the defences, one by one (a level-20 Dovelle comes quickly)
	var shut := NightWatchClassic.new(1, 3, {"dovelle": 20, "ravelle": 0, "aki": 0, "ilyra": 0})
	var arrived := false
	var repelled := false
	var guard := 0
	while shut.over == "" and guard < 20000 and not repelled:
		guard += 1
		var closed: bool = not shut.at_door("doorL").is_empty()
		for e in shut.step(50.0, {"doorL": closed}):
			arrived = arrived or String(e["type"]) == "arrived"
			repelled = repelled or String(e["type"]) == "repelled"
	_expect(arrived and repelled and shut.over == "", "a shut door did not turn a hunter away")
	_expect((shut.hunters["dovelle"] as NightWatchStalker).room == "dining", "a shut door did not send her to the dining area (retreat_to)")

	var lit := NightWatchClassic.new(1, 3, {"dovelle": 20, "ravelle": 0, "aki": 0, "ilyra": 0})
	var pushed := false
	var flinched := false
	guard = 0
	while lit.over == "" and guard < 20000 and not pushed:
		guard += 1
		var on: bool = not lit.at_door("doorL").is_empty()
		for e in lit.step(50.0, {"lightL": on}):
			flinched = flinched or String(e["type"]) == "flinch"
			pushed = pushed or String(e["type"]) == "pushed"
	_expect(flinched and pushed, "the light did not make her flinch and then back off")
	_expect((lit.hunters["dovelle"] as NightWatchStalker).room == "stage", "the light did not drive her back to the stage (push_to)")

	var ignored := NightWatchClassic.new(1, 3, {"dovelle": 20, "ravelle": 0, "aki": 0, "ilyra": 0})
	var started := -1.0
	guard = 0
	while ignored.over == "" and guard < 40000:
		guard += 1
		ignored.step(50.0, {})
		if started < 0.0 and not ignored.at_door("doorL").is_empty():
			started = ignored.elapsed
	_expect(ignored.over == "caught" and ignored.by == "dovelle", "an unanswered door did not end the night")
	var waited := ignored.elapsed - started
	_expect(absf(waited - 9000.0) < 120.0, "night 1's door wait is not 9 s (waited %.0f ms)" % waited)

	# --- Aki only moves while the monitor is down, Ilyra freezes while her room is on the monitor
	var aki_up := NightWatchClassic.new(3, 5, {"dovelle": 0, "ravelle": 0, "aki": 20, "ilyra": 0})
	for i in 600:
		aki_up.step(100.0, {"cam": true, "cam_room": "stage", "doorR": true})
	_expect((aki_up.hunters["aki"] as NightWatchStalker).room == "closet", "Aki moved while the monitor was up")
	var aki_down := NightWatchClassic.new(3, 5, {"dovelle": 0, "ravelle": 0, "aki": 20, "ilyra": 0})
	for i in 300:
		aki_down.step(100.0, {"doorR": true})
	_expect((aki_down.hunters["aki"] as NightWatchStalker).room != "closet", "Aki never left the closet with the monitor down")
	var ilyra := NightWatchClassic.new(4, 9, {"dovelle": 0, "ravelle": 0, "aki": 0, "ilyra": 20})
	for i in 600:
		ilyra.step(100.0, {"cam": true, "cam_room": "backstage", "doorL": true})
	_expect((ilyra.hunters["ilyra"] as NightWatchStalker).room == "backstage", "Ilyra moved while her room was watched")

	# --- two hunters can share a door; a third waits in the hall
	var share := NightWatchClassic.new(5, 11)
	(share.hunters["dovelle"] as NightWatchStalker).room = "doorL"
	(share.hunters["ilyra"] as NightWatchStalker).room = "doorL"
	share.step(10.0, {"doorL": true})
	_expect(share.at_door("doorL").size() == 2, "two hunters did not share the left door")
	_expect(share._occupied("doorL", "ravelle"), "a full door was not reported full to a third hunter")

	# --- the power meter: idle drain, devices cost more, at zero the doors open and Nyxie comes
	var idle := NightWatchClassic.new(1, 1, {"dovelle": 0})
	for i in 100:
		idle.step(1000.0, {})
	_expect(absf((100.0 - idle.power) - NightWatchData.POWER_BASE * 100.0) < 0.01, "idle power drain is not the base rate")
	var busy := NightWatchClassic.new(1, 1, {"dovelle": 0})
	for i in 100:
		busy.step(1000.0, {"doorL": true, "lightR": true, "cam": true})
	_expect(absf((100.0 - busy.power) - (NightWatchData.POWER_BASE + 3.0 * NightWatchData.POWER_PER_DEVICE) * 100.0) < 0.05,
		"devices in use do not cost power")
	_expect(NightWatchClassic.usage({"doorL": true, "cam": true}) == 2, "usage count is wrong")
	var dark := NightWatchClassic.new(3, 2, {"dovelle": 0, "ravelle": 0, "aki": 0, "ilyra": 0, "nyxie": 10})
	dark.power = 0.2
	var went_out := false
	var blackout_start := -1.0
	guard = 0
	while dark.over == "" and guard < 2000:
		guard += 1
		for e in dark.step(100.0, {"doorL": true, "doorR": true, "lightL": true, "cam": true}):
			if String(e["type"]) == "out":
				went_out = true
				blackout_start = dark.elapsed
	_expect(went_out and dark.out, "the power never went out")
	_expect(not bool(dark.door_shut["doorL"]) and not bool(dark.light_on["doorL"]), "doors stayed shut and lights on with the power out")
	_expect(dark.over == "caught" and dark.by == "nyxie", "Nyxie did not come in the dark")
	var in_dark := dark.elapsed - blackout_start
	_expect(absf(in_dark - NightWatchData.blackout_ms(10)) < 200.0, "the dark did not last Nyxie's blackout time (%.0f ms)" % in_dark)

	# --- the shift scene: office, building, monitor, hunters, doors, lights, win, loss, saves, menu
	_expect(NightWatchSave.SECTION == "night_watch" and NightWatchSave.DEFAULT_PATH.contains("night_watch"), "Night Watch saves are not namespaced")
	NightWatchSave.path = "user://night_watch_validate.cfg"
	NightWatchSave.reset()
	_expect(NightWatchSave.unlocked_night() == 1 and NightWatchSave.cleared().is_empty(), "a fresh Night Watch save is not night 1 with nothing cleared")
	NightWatchSession.start(3, 4242)
	var shift := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	shift.manual_clock = true
	host.add_child(shift)
	await host.get_tree().process_frame
	_expect(shift.office != null and shift.office.slabs.size() == 2 and shift.office.door_lights.size() == 2 and shift.office.prompts.size() >= 8, "the office has no two doors, door lights and stations")
	_expect(shift.building.rooms.size() == 8 and shift.hud.cam_buttons.size() == 8, "the building does not have eight camera rooms and buttons")
	# --- the art pass: painted textures within limits, shaded cubes, no plain slabs, emissive only where intended
	for kind in NightWatchArt.RAMPS:
		var ts := NightWatchArt.texture_stats(kind)
		_expect((ts["size"] as Vector2i).x <= 32 and (ts["size"] as Vector2i).y <= 32, "the %s texture is bigger than 32 x 32" % kind)
		_expect(int(ts["colors"]) <= 8 and int(ts["colors"]) >= 3, "the %s texture has %d colours (3 to 8 allowed)" % [kind, int(ts["colors"])])
	var must_have := ["Desk", "Monitor", "Keyboard", "Radio", "DeskLampProp", "Chair", "BreakerBox", "VentHatch", "ShelfUnit", "ControlPanelL",
		"ControlPanelR", "DoorFrameL", "DoorFrameR", "SlabL", "SlabR", "WallClock", "Poster", "Shell", "HallL", "HallR", "Papers", "Cup"]
	var office_cubes := 0
	for prop_name in must_have:
		_expect(shift.office.props.has(prop_name), "the office has no %s prop" % prop_name)
	for prop_name in shift.office.props:
		var st := NightWatchArt.prop_stats(shift.office.props[prop_name])
		office_cubes += int(st["cubes"])
		_expect(int(st["untextured"]) == 0, "%s has untextured cubes" % prop_name)
		_expect((st["bad_emissive"] as Array).is_empty(), "%s has emissive cubes that are not allowed to glow: %s" % [prop_name, str(st["bad_emissive"])])
		if prop_name not in ["Cup", "Bin"]:
			_expect(int(st["cubes"]) >= 3, "%s is a plain slab (%d cubes)" % [prop_name, int(st["cubes"])])
		_expect(int(st["looks"]) >= 2 or int(st["cubes"]) < 4, "%s has one material look only" % prop_name)
	_expect(office_cubes >= 260, "the office has only %d cubes (260 or more expected from the art pass)" % office_cubes)
	var building_cubes := 0
	for id in shift.building.rooms:
		var groups := 0
		for key in shift.building.props:
			if String(key).begins_with(String(id) + "/"):
				groups += 1
				var bs := NightWatchArt.prop_stats(shift.building.props[key])
				building_cubes += int(bs["cubes"])
				_expect(int(bs["untextured"]) == 0 and (bs["bad_emissive"] as Array).is_empty(), "%s has untextured or wrongly emissive cubes" % key)
		_expect(groups >= 3, "the %s camera room has only %d prop groups" % [id, groups])
	_expect(building_cubes >= 420, "the eight camera rooms have only %d cubes (420 or more expected)" % building_cubes)
	print("  art: office %d cubes in %d props, camera rooms %d cubes" % [office_cubes, shift.office.props.size(), building_cubes])
	_check_uvs(shift)
	# shading is baked: a cube has vertex colours that differ between its top and bottom
	var sample := shift.office.find_child("DeskTop", true, false) as MeshInstance3D
	var colors: PackedColorArray = sample.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lo := 9.0
	var hi := 0.0
	for col in colors:
		lo = minf(lo, col.r)
		hi = maxf(hi, col.r)
	_expect(colors.size() == 36 and hi - lo > 0.3, "cubes do not carry baked shading (range %.2f)" % (hi - lo))
	for id in ["dovelle", "ravelle", "aki"]:
		_expect((shift._models[id] as Node3D).visible and (shift._models[id] as Node3D).get_child_count() > 0, "%s is not on night 3's floor with a model" % id)
	_expect(not (shift._models["ilyra"] as Node3D).visible, "Ilyra (level 0 on night 3) is shown")
	# the controls: Night Watch's quick actions exist while a shift is open and no key of theirs is bound to ANY shared action
	var nw_actions := ["nw_door_left", "nw_door_right", "nw_light_left", "nw_light_right", "nw_lamp"]   # nw_monitor is on Space: the shared jump is switched off in this scene
	var jump_default := PlayerController3D.new()
	_expect(not shift.player.jump_enabled and jump_default.jump_enabled, "Night Watch's player must not jump (Space is the cameras) and the controller's default must stay on")
	jump_default.free()
	for action in nw_actions:
		_expect(InputMap.has_action(action), "%s is not registered" % action)
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				for other in InputMap.get_actions():
					var other_name := String(other)
					# waypoint / waypoint_clear are read only by Last Route's route scene (infinite_route_test.gd), never in a Night Watch shift
					if other_name.begins_with("nw_") or other_name.begins_with("office_") or other_name.begins_with("ui_") or other_name.begins_with("spatial_editor") or other_name.begins_with("waypoint") \
							or other_name == "taser":   # the taser (G) is read only with a taser in the inventory, which a Night Watch shift never has
						continue
					for oev in InputMap.action_get_events(other):
						_expect(not (oev is InputEventKey and (oev as InputEventKey).physical_keycode == (ev as InputEventKey).physical_keycode),
							"%s shares its key with the shared action %s" % [action, other_name])
	_expect(NightWatchControls.controls_tab()["actions"].size() >= 8, "the OFFICE controls tab data is too short")
	var press := func(action: String, pressed := true) -> void:
		var ev := InputEventAction.new()
		ev.action = action
		ev.pressed = pressed
		shift._unhandled_input(ev)
	press.call("nw_door_left")
	_expect(bool(shift.door_shut["doorL"]), "the left door quick key did not shut the left door")
	press.call("nw_door_left")
	press.call("nw_light_right")
	_expect(bool(shift.light_held["doorR"]), "holding the right light quick key did not hold the light")
	press.call("nw_light_right", false)
	_expect(not bool(shift.light_held["doorR"]), "releasing the right light quick key did not let it go")
	press.call("nw_monitor")
	_expect(shift.monitor_up and shift.player.input_frozen, "the monitor quick key did not open the monitor and freeze the player")
	press.call("nw_cam_3")
	_expect(shift.monitor_room == "backstage", "camera key 3 did not pick the backstage feed")
	press.call("interact")
	_expect(not shift.monitor_up and not shift.player.input_frozen, "use did not leave the monitor")
	press.call("office_radio")
	_expect(shift.hud.muted, "the radio action did not mute Zellia")
	press.call("office_radio")
	shift.hud.subtitles_toggled.emit(false)
	_expect(not shift.hud.subtitles and not NightWatchSave.subtitles(), "the subtitles toggle did not save")
	shift.hud.subtitles_toggled.emit(true)
	# NW NO INVENTORY: the flag is the only difference, Last Route's default is untouched, the flashlight is built in and never drains, the item keys do nothing
	var default_player := PlayerController3D.new()
	_expect(not shift.player.inventory_enabled and default_player.inventory_enabled, "Night Watch's player must have the inventory off and the controller's default must stay on")
	default_player.free()
	for n in shift.player.get_children():
		_expect(not String(n.name).to_lower().contains("hotbar") and not String(n.name).to_lower().contains("inventory"), "the Night Watch player has an inventory node: %s" % n.name)
	for n in shift.hud.find_children("*", "Control", true, false):
		_expect(not String(n.name).to_lower().contains("hotbar") and not String(n.name).to_lower().contains("inventory"), "the Night Watch HUD has an inventory node: %s" % n.name)
	_expect(not shift.player.grant_inventory_item("taser") and not shift.player.request_drop_selected_item() and not shift.player.collect_backpack("backpack"), "an item API worked with the inventory off")
	var slot_before: int = shift.player.selected_inventory_slot
	for key in [KEY_3, KEY_5]:
		var kev := InputEventKey.new()
		kev.physical_keycode = key
		kev.keycode = key
		kev.pressed = true
		shift.player._unhandled_input(kev)
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	shift.player._unhandled_input(wheel)
	_expect(shift.player.selected_inventory_slot == slot_before, "a slot key or the wheel changed the held slot with the inventory off")
	_expect(shift.player.owns_inventory_item("flashlight"), "the flashlight is not built in")
	Input.action_press("flashlight")
	await host.get_tree().physics_frame
	Input.action_release("flashlight")
	await host.get_tree().physics_frame
	_expect(shift.player.flashlight_enabled and shift.player.flashlight.visible, "the flashlight action did not switch the built-in flashlight on")
	var charge_before: float = shift.player.lamp_charge
	for i in 120:
		await host.get_tree().physics_frame
	_expect(is_equal_approx(shift.player.lamp_charge, charge_before), "the built-in flashlight drained (%.2f to %.2f)" % [charge_before, shift.player.lamp_charge])
	Input.action_press("flashlight")
	await host.get_tree().physics_frame
	Input.action_release("flashlight")
	await host.get_tree().physics_frame
	_expect(not shift.player.flashlight_enabled, "the flashlight action did not switch it off again")
	# the SHARED player controller walks the room: spawn, walking into the chair and the desk stops, aiming, using
	var player := shift.player
	_expect(player is PlayerController3D and player.get_script().resource_path == "res://src/game_3d/player_controller_3d.gd", "the player is not the shared controller")
	_expect(player.global_position.distance_to(NightWatchOffice.SPAWN) < 0.05, "the player does not start at the spawn point")
	Input.action_press("move_up")
	for i in 150:
		await host.get_tree().physics_frame
	Input.action_release("move_up")
	_expect(player.global_position.z < 0.0 and player.global_position.z > -0.75, "walking forward did not stop at the chair (z=%.2f)" % player.global_position.z)
	shift.face_player(0.0, -0.3)
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	var aimed := player.call("_nearest_interactable") as NightWatchStation
	_expect(aimed != null and aimed.station_id == "monitor" and player.get_interaction_prompt().contains("MONITOR"),
		"aiming at the desk did not find the monitor (got '%s')" % (aimed.station_id if aimed != null else "nothing"))
	shift._on_station("monitor")
	_expect(shift.monitor_up, "using the monitor station did not open the monitor")
	shift.close_monitor()
	# the door panels: aim at DOOR and LIGHT beside the left door
	player.global_position = Vector3(-2.2, 0.0, 1.55)
	# aim at the button itself (the runner's eye height follows the player scale, so a fixed pitch drifts)
	shift.face_player(PI * 0.5, _pitch_to(player, host, "doorL_door"))
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	aimed = player.call("_nearest_interactable") as NightWatchStation
	_expect(aimed != null and aimed.station_id == "doorL_door", "aiming at the left panel's upper button did not find DOOR (got '%s')" % (aimed.station_id if aimed != null else "nothing"))
	shift._on_station("doorL_door")
	_expect(bool(shift.door_shut["doorL"]), "using the left DOOR button did not shut the door")
	shift.advance_ms(50.0)
	_expect(is_equal_approx(float(shift.office.slab_progress["doorL"]), 1.0), "the left door slab did not close")
	shift.face_player(PI * 0.5, _pitch_to(player, host, "doorL_light"))
	await host.get_tree().physics_frame
	await host.get_tree().physics_frame
	aimed = player.call("_nearest_interactable") as NightWatchStation
	_expect(aimed != null and aimed.station_id == "doorL_light", "aiming at the left panel's lower button did not find LIGHT (got '%s')" % (aimed.station_id if aimed != null else "nothing"))
	# a shut door blocks the way out, an open one lets you reach the hall mouth and no further
	player.global_position = Vector3(-2.0, 0.0, 0.0)
	shift.face_player(PI * 0.5, 0.0)
	Input.action_press("move_up")
	for i in 120:
		await host.get_tree().physics_frame
	Input.action_release("move_up")
	_expect(player.global_position.x > -2.8, "a shut door did not block the player (x=%.2f)" % player.global_position.x)
	shift.set_door("doorL", false)
	shift.advance_ms(50.0)
	player.global_position = Vector3(-2.0, 0.0, 0.0)
	Input.action_press("move_up")
	for i in 180:
		await host.get_tree().physics_frame
	Input.action_release("move_up")
	_expect(player.global_position.x < -3.0 and player.global_position.x > -3.6, "the open doorway did not stop the player at the hall mouth (x=%.2f)" % player.global_position.x)
	# the lamp and the chair (the shared sit pose)
	shift._on_station("lamp")
	_expect(not shift.office.lamp.visible, "the lamp station did not switch the lamp off")
	shift._on_station("lamp")
	player.global_position = Vector3(0.0, 0.0, 0.2)
	shift._on_station("chair")
	_expect(player.resting_furniture != null and player.global_position.distance_to(NightWatchOffice.SEAT) < 0.05, "the chair did not seat the player with the shared sit pose")
	shift._on_station("chair")
	_expect(player.resting_furniture == null, "using the chair again did not stand the player up")
	player.global_position = NightWatchOffice.SPAWN
	# parity with Last Route's controller, prompt and sounds
	var main_text := FileAccess.get_file_as_string("res://scenes/main_3d.tscn")
	var nw_text := FileAccess.get_file_as_string("res://scenes/night_watch_player.tscn")
	_expect(_player_block(main_text, true) == _player_block(nw_text, false) and _player_block(nw_text, false).length() > 400,
		"the Night Watch player scene is not the route scene's player subtree")
	var hud_text := FileAccess.get_file_as_string("res://scenes/hud.tscn")
	var label_at := hud_text.find('[node name="InteractionLabel"')
	var label_block := hud_text.substr(label_at, hud_text.find("[node", label_at + 10) - label_at)
	var prompt: Label = shift.hud.prompt_label
	_expect(label_block.contains("font_size = %d" % prompt.get_theme_font_size("font_size")) and label_block.contains("offset_top = 16") and is_equal_approx(prompt.offset_top, 16.0)
		and label_block.contains("Color(%s, %s, %s, 1)" % [snappedf(prompt.get_theme_color("font_color").r, 0.001), snappedf(prompt.get_theme_color("font_color").g, 0.001), snappedf(prompt.get_theme_color("font_color").b, 0.001)]),
		"the interaction prompt does not match the route HUD's InteractionLabel style")
	_expect(shift.hud.find_children("*", "Crosshair", true, false).size() == 1, "the shared crosshair is not on the Night Watch HUD")
	Sound.reset_test_counters()
	shift.toggle_door("doorR")
	shift.toggle_door("doorR")
	shift.open_monitor("dining")
	shift.close_monitor()
	_expect(Sound.play_counts.has("door_close") and Sound.play_counts.has("door_open") and Sound.play_counts.has("office_camera"),
		"the door and monitor sounds did not go through the shared Sound autoload (%s)" % str(Sound.play_counts.keys()))
	_expect(shift.find_children("*", "AudioStreamPlayer", true, false).is_empty() and shift.find_children("*", "AudioStreamPlayer3D", true, false).is_empty(),
		"Night Watch has an audio player of its own")
	for file in DirAccess.get_files_at("res://src/night_watch"):
		if file.ends_with(".gd"):
			_expect(not FileAccess.get_file_as_string("res://src/night_watch/" + file).contains("AudioStreamPlayer"), "%s makes its own audio player" % file)
	shift.advance_ms(1000.0)
	_expect(shift.hud.clock_label.text == "12 AM" and shift.hud.power_label.text == "Power left: 100%", "the clock or power label is wrong at the start of the night")
	shift.toggle_door("doorL")
	shift.set_light("doorR", true)
	shift.advance_ms(100.0)
	_expect(bool(shift.sim.door_shut["doorL"]) and is_equal_approx(float(shift.office.slab_progress["doorL"]), 1.0), "the left door did not shut")
	_expect((shift.office.door_lights["doorR"] as Node3D).visible and not (shift.office.door_lights["doorL"] as Node3D).visible, "the right door light did not come on")
	shift.set_light("doorR", false)
	shift.toggle_door("doorL")
	shift.open_monitor("westhall")
	await host.get_tree().process_frame
	_expect(shift.hud.monitor_root.visible and shift.hud.feed_viewport.render_target_update_mode == SubViewport.UPDATE_ALWAYS
		and shift.hud.cam_label.text.contains("WEST HALL"), "the monitor did not open on the west hall feed")
	shift.select_camera("dining")
	_expect(shift.hud.cam_label.text.contains("DINING") and shift.hud.feed_camera.global_position.distance_to(shift.building.camera_transform("dining").origin) < 0.01,
		"the feed camera did not move to the dining area")
	shift.close_monitor()
	_expect(not shift.hud.monitor_root.visible and shift.hud.feed_viewport.render_target_update_mode == SubViewport.UPDATE_DISABLED, "the monitor feed kept rendering when closed")
	# a hunter at the door stands in the doorway; a shut door turns her away
	var dovelle := shift.sim.hunters["dovelle"] as NightWatchStalker
	dovelle.room = "doorL"
	dovelle.at_door_ms = 0.0
	shift.advance_ms(10.0)
	_expect(((shift._models["dovelle"] as Node3D).position - shift.office.door_stand("doorL", 0)).length() < 0.01, "Dovelle is not standing in the left doorway")
	shift.set_door("doorL", true)
	for i in 8:
		shift.advance_ms(100.0)
	_expect(dovelle.room == "dining", "shutting the door did not turn Dovelle away")
	shift.set_door("doorL", false)
	# an unanswered door ends the night with her line
	dovelle.room = "doorL"
	dovelle.at_door_ms = 0.0
	for i in 30:
		shift.advance_ms(500.0)
	_expect(shift.state == NightWatchGame.State.LOST and String(shift.last_death.get("by", "")) == "dovelle", "an unanswered door did not lose the night to Dovelle")
	_expect(shift.death_moment.is_open() or shift.hud.end_root.visible, "the loss showed neither the death moment nor the end card")
	var closing := 0
	while shift.death_moment.is_open() and closing < 40:
		shift.death_moment.dismiss()
		closing += 1
	await host.get_tree().process_frame
	_expect(shift.hud.end_root.visible and shift.hud.end_title.text == "CAUGHT" and not shift.hud.end_next.visible, "the end card after a death is not CAUGHT with Retry and BACK TO GAMES")
	shift.queue_free()
	await host.get_tree().process_frame
	# a quiet night is won at 6 AM, saved under night_watch, and opens the next night
	NightWatchSession.start(1, 5)
	NightWatchSession.custom_levels = {"dovelle": 0, "ravelle": 0, "aki": 0, "ilyra": 0, "nyxie": 0}
	var quiet := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	quiet.manual_clock = true
	host.add_child(quiet)
	await host.get_tree().process_frame
	for i in 271:
		quiet.advance_ms(1000.0)
	_expect(quiet.state == NightWatchGame.State.WON and quiet.hud.end_root.visible and quiet.hud.end_title.text == "NIGHT 1 COMPLETE", "a quiet night was not won at 6 AM")
	_expect(NightWatchSave.cleared() == [1] and NightWatchSave.unlocked_night() == 2, "winning night 1 did not save the clear and open night 2")
	quiet.queue_free()
	await host.get_tree().process_frame
	# the menu's shift board: night 1 and 2 open, night 3 locked, START SHIFT present
	var menu := (load("res://scenes/night_watch_menu.tscn") as PackedScene).instantiate() as NightWatchMenu
	host.add_child(menu)
	await host.get_tree().process_frame
	menu.show_screen("board")
	_expect(not (menu.tile_buttons[0] as Button).disabled and not (menu.tile_buttons[1] as Button).disabled and (menu.tile_buttons[2] as Button).disabled,
		"the shift board does not follow the save")
	_expect(menu.start_button != null and menu.start_button.text.begins_with("▶ START SHIFT"), "the board has no START SHIFT")
	menu.queue_free()
	await _check_walking(host)
	await _check_kathy(host)
	await _check_poses(host)
	_expect(not InputMap.has_action(NightWatchControls.LIGHT_LEFT), "the door light actions stayed registered after the shift closed")
	NightWatchSession.start(1)
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH

	if _failures == 0:
		print("  night_watch  rules port (2D numbers, determinism, doors, lights, cameras, power, blackout) and the shift scene (office, feeds, hunters, win, loss, saves, menu)")
	return _failures



## Hunters walk: routes exist between every pair of rooms and doors, never cross a wall, never jump except from the hall to the office, and a hunter the
## sim moves keeps to walking pace on screen (she is not placed in the new room).
func _check_walking(host: Node) -> void:
	NightWatchSession.start(3, 99)
	var shift := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	host.add_child(shift)
	await host.get_tree().process_frame
	var paths := shift.paths
	var rooms := NightWatchData.GRAPH.keys()
	var walls: Array = shift.building.wall_boxes
	var bad_wall := 0
	var bad_jump := 0
	var missing := 0
	for a in rooms:
		for b in rooms:
			if a == b:
				continue
			var legs: Array = paths.legs_for(String(a), String(b))
			if legs.size() < 2:
				missing += 1
				continue
			for i in range(1, legs.size()):
				if bool(legs[i]["jump"]):
					var ok: bool = String(legs[i]["key"]).begins_with("DO:") or String(legs[i - 1]["key"]).begins_with("DO:")
					if not ok:
						bad_jump += 1
					continue
				var p0: Vector3 = legs[i - 1]["p"]
				var p1: Vector3 = legs[i]["p"]
				var n := int(ceil(p0.distance_to(p1) / 0.1))
				for k in range(1, n):
					var q := p0.lerp(p1, float(k) / float(n))
					for wb in walls:
						if (wb["rect"] as Rect2).has_point(Vector2(q.x, q.z)):
							bad_wall += 1
	_expect(missing == 0, "%d room pairs have no walking route" % missing)
	_expect(bad_wall == 0, "walking routes cross walls at %d points" % bad_wall)
	_expect(bad_jump == 0, "%d route legs jump other than from the hall to the office" % bad_jump)
	_expect(NightWatchPaths.walked_length(paths.legs_for("stage", "dining")) > 4.0, "stage to dining is not a walk")
	var kitchen: Array = paths.legs_for("kitchen", "dining")
	var via_lane := false
	for leg in kitchen:
		if String(leg["key"]).begins_with("L:"):
			via_lane = true
	_expect(via_lane, "the kitchen route does not go out through the lane")
	# a walker keeps to a pace: no step longer than the run speed allows (jumps excepted)
	var w := NightWatchWalker.new()
	var legs2: Array = paths.legs_for("stage", "westhall")
	var start: Vector3 = legs2[0]["p"]
	var goal := shift.building.stand_position("westhall", 0)
	w.place(start, goal, goal, "stage")
	w.go(legs2, "westhall", goal)
	var longest := 0.0
	var steps := 0
	var last := w.pos
	while (w.is_walking() or w.pos.distance_to(goal) > 0.05) and steps < 2000:
		w.step(0.05)
		steps += 1
		longest = maxf(longest, w.pos.distance_to(last))
		last = w.pos
	_expect(steps < 2000 and w.pos.distance_to(goal) <= 0.05, "the walker never reached her room")
	_expect(longest <= NightWatchWalker.MAX_SPEED * 0.05 + 0.01, "the walker moved %.2f m in one 0.05 s step" % longest)
	# the stuck test: every hunter walks every ordered room pair, arrives within her hop budget (plus slack), makes progress at every second and never stands in a wall
	var stuck := 0
	var late := 0
	var in_wall := 0
	for hid in ["dovelle", "ravelle", "aki", "ilyra"]:
		var level := 12
		var budget2 := NightWatchWalker.budget_for(level)
		for a in rooms:
			for b in rooms:
				if a == b or String(a).begins_with("door") and String(b).begins_with("door"):
					continue
				var wk := NightWatchWalker.new()
				var legs3: Array = paths.legs_for(String(a), String(b))
				if legs3.is_empty():
					continue
				var goal2: Vector3 = legs3[legs3.size() - 1]["p"]
				wk.place(legs3[0]["p"], goal2, goal2, String(a))
				wk.go(legs3, String(b), goal2, budget2)
				var t := 0.0
				var last_pos := wk.pos
				var idle_t := 0.0
				while wk.is_walking() and t < 30.0:
					wk.step(0.05)
					t += 0.05
					if wk.pos.distance_to(last_pos) < 0.001 and wk.is_walking():
						idle_t += 0.05
					else:
						idle_t = 0.0
					if idle_t > 1.0:
						stuck += 1
						break
					last_pos = wk.pos
					for wb in walls:
						if (wb["rect"] as Rect2).has_point(Vector2(wk.pos.x, wk.pos.z)):
							in_wall += 1
				if wk.is_walking():
					stuck += 1
				elif t > budget2 * 1.5 + 1.0 + (0.0 if NightWatchPaths.walked_length(legs3) / budget2 <= NightWatchWalker.MAX_SPEED else NightWatchPaths.walked_length(legs3) / NightWatchWalker.MAX_SPEED):
					late += 1
	_expect(stuck == 0, "%d walks got stuck" % stuck)
	_expect(in_wall == 0, "walkers stood in a wall %d times" % in_wall)
	_expect(late == 0, "%d walks arrived later than their budget allows" % late)
	# the speed rule: every hop of every hunter on every night stays inside the clamp; report how many hops the clamp bites on
	var clamped := 0
	var hops := 0
	for night in range(1, NightWatchData.NIGHTS + 1):
		for hid in NightWatchData.HUNTERS:
			var level := NightWatchData.level_for(hid, night)
			if level <= 0:
				continue
			var budget := NightWatchWalker.budget_for(level)
			_expect(budget >= 1.5 and budget <= 4.0, "the hop budget for %s on night %d is out of range" % [hid, night])
			for a in rooms:
				for b in NightWatchData.GRAPH[a]:
					var length := NightWatchPaths.walked_length(paths.legs_for(String(a), String(b)))
					var raw := length / budget
					var speed := NightWatchWalker.speed_for(length, budget)
					hops += 1
					if absf(raw - speed) > 0.001:
						clamped += 1
					_expect(speed >= NightWatchWalker.MIN_SPEED and speed <= NightWatchWalker.MAX_SPEED, "speed %.2f out of the clamp" % speed)
	print("  walk speeds: %d of %d hops are clamped (min %.1f / max %.1f m/s)" % [clamped, hops, NightWatchWalker.MIN_SPEED, NightWatchWalker.MAX_SPEED])
	# in the scene: the sim moves Dovelle two rooms away and her model walks, it is not placed
	shift.manual_clock = false
	var dovelle := shift.sim.hunters["dovelle"] as NightWatchStalker
	dovelle.room = "stage"
	shift._place_hunters()
	var model := shift._models["dovelle"] as Node3D
	var from_pos := model.position
	dovelle.room = "westhall"
	shift._place_hunters()
	shift._animate_models(0.1)
	_expect(model.position.distance_to(from_pos) < 1.5, "Dovelle was placed in the next room instead of walking there")
	for i in 80:
		shift._animate_models(0.1)
	_expect(model.position.distance_to(shift.building.stand_position("westhall", 0)) < 1.6, "Dovelle did not arrive in the west hall")
	shift.queue_free()
	await host.get_tree().process_frame



## Texture mapping of every cube in the office and the camera rooms: the same texel density on every face (32 px per metre, hazard tape 64 px per
## metre along its length and width), within 10%; hazard tape counts a whole number of stripe periods along its length, so it starts and ends
## on the same phase; every UV is finite, non-negative and spans a real area. Tape faces use the stripe tile, every other face of a tape cube a
## plain metal tile (nothing is a stretched copy of the front texture).
func _check_uvs(shift: NightWatchGame) -> void:
	var meshes := []
	meshes.append_array(shift.office.find_children("*", "MeshInstance3D", true, false))
	meshes.append_array(shift.building.find_children("*", "MeshInstance3D", true, false))
	var faces := 0
	var tape_faces := 0
	var bad_density := []
	var bad_phase := []
	var bad_uv := 0
	var edge_faces := 0
	for m in meshes:
		var mi := m as MeshInstance3D
		if mi.mesh == null or mi.mesh.get_surface_count() == 0 or not mi.has_meta("nw_name"):
			continue
		var hazard := String(mi.get_meta("nw_hazard", ""))
		for surface in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(surface)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var tape_surface := not hazard.is_empty()
			var f := 0
			while f + 5 < v.size():
				faces += 1
				# a face is drawn as triangles with corners 0,2,1 and 0,3,2 (clockwise for Godot): corner 0 = v[f], corner 1 = v[f+2], corner 2 = v[f+1]
				var p0 := v[f]
				var p1 := v[f + 2]
				var p2 := v[f + 1]
				var u0 := uv[f]
				var u1 := uv[f + 2]
				var u2 := uv[f + 1]
				for i in 6:
					var q := uv[f + i]
					if not is_finite(q.x) or not is_finite(q.y) or q.x < -0.001 or q.y < -0.001:
						bad_uv += 1
				var len_u := p0.distance_to(p1)
				var len_v := p1.distance_to(p2)
				var span_u := absf(u1.x - u0.x)
				var span_v := absf(u1.y - u2.y)
				if tape_surface and span_u < 0.0001 and span_v < 0.0001:
					f += 6       # an end or thickness face of tape: one dark texel, no stripes (checked below)
					edge_faces += 1
					continue
				if len_u < 0.0001 or len_v < 0.0001 or span_u < 0.0001 or span_v < 0.0001:
					bad_uv += 1
					f += 6
					continue
				var want_v := 64.0 if tape_surface else 32.0
				var du := span_u * float(NightWatchArt.TEX) / len_u
				var dv := span_v * float(NightWatchArt.TEX) / len_v
				if tape_surface:
					tape_faces += 1
					var periods := span_u * 2.0
					if absf(periods - roundf(periods)) > 0.001:
						bad_phase.append("%s %.3f periods" % [mi.get_meta("nw_name"), periods])
					du = 64.0 * (roundf(periods) * NightWatchArt.HAZ_PERIOD_M) / len_u   # the density after the whole-period rounding
				if absf(dv - want_v) / want_v > 0.1 or absf(du - want_v) / want_v > 0.1:
					bad_density.append("%s %.0f/%.0f px/m (want %.0f)" % [mi.get_meta("nw_name"), du, dv, want_v])
				f += 6
	# every cube is drawn outside-out: the first triangle of each face is wound clockwise seen from the face's normal side
	var inside_out := 0
	for m in meshes:
		var mi2 := m as MeshInstance3D
		if mi2.mesh == null or mi2.mesh.get_surface_count() == 0 or not mi2.has_meta("nw_name"):
			continue
		var arr := mi2.mesh.surface_get_arrays(0)
		var vv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var k := 0
		while k + 2 < vv.size():
			var tri_normal := (vv[k + 1] - vv[k]).cross(vv[k + 2] - vv[k])   # counter-clockwise normal; Godot's front is the clockwise side, so it must point inward
			if tri_normal.dot(nn[k]) > 0.0:
				inside_out += 1
			k += 6
	_expect(inside_out == 0, "%d cube faces are wound inside out (their near side is culled)" % inside_out)
	_expect(faces > 500, "the UV check saw only %d faces" % faces)
	_expect(tape_faces >= 12, "the UV check saw only %d hazard tape faces" % tape_faces)
	_expect(edge_faces >= 20, "hazard tape has only %d dedicated edge faces" % edge_faces)
	_expect(bad_uv == 0, "%d faces have non-finite, negative or zero-area UVs" % bad_uv)
	_expect(bad_phase.is_empty(), "hazard faces that do not hold a whole number of periods: %s" % str(bad_phase.slice(0, 5)))
	_expect(bad_density.is_empty(), "%d faces are off the texel density: %s" % [bad_density.size(), str(bad_density.slice(0, 6))])



## Night 7: Kathy hunts alone (2D KATHY_HUNT): level 20 on Night 6's pacing scaled, the light never holds her, a shut door has to stay shut for a rolled time and then she
## FADES silently to the stage or the kitchen on a fresh door, her light dips and hum are her tells, and meeting her eyes on a hall feed sends her back.
func _check_kathy(host: Node) -> void:
	var a := NightWatchClassic.new(7, 4242)
	var b := NightWatchClassic.new(7, 4242)
	_expect(a.kathy_night and a.hunters.size() == 1 and a.hunters.has("kathy") and a.nyxie_level == 0, "Night 7 is not Kathy's alone")
	var k := a.hunters["kathy"] as NightWatchStalker
	_expect(k.base == 20 and k.unseen and absf(k.attack_ms - 2610.0) < 1.0 and absf(k._pace - 0.6695) < 0.001, "Kathy's tuning differs from KATHY_HUNT (grace %.0f pace %.4f)" % [k.attack_ms, k._pace])
	_expect(not NightWatchClassic.new(7, 4242, {}, true).kathy_night, "a Custom Night on level 7 became Kathy's night")
	_expect(NightWatchData.active_hunters(7) == ["kathy"] and NightWatchData.NIGHTS == 7, "the Shift Board's night 7 does not show only Kathy")
	# roll_hold: within [lo, hi], mean near lo + tail
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var total := 0.0
	var lowest := 1e9
	var highest := 0.0
	for i in 4000:
		var v := NightWatchData.roll_hold(rng.randf(), 2500.0, 20000.0, 4500.0)
		total += v
		lowest = minf(lowest, v)
		highest = maxf(highest, v)
	_expect(lowest >= 2500.0 and highest <= 20000.0 and absf(total / 4000.0 - 7000.0) < 400.0, "Kathy's shut-door hold is off the 2D distribution (mean %.0f, range %.0f-%.0f)" % [total / 4000.0, lowest, highest])
	# determinism
	var log_a := []
	var log_b := []
	for i in 600:
		for e in a.step(250.0, {}):
			log_a.append(e)
		for e in b.step(250.0, {}):
			log_b.append(e)
	_expect(log_a == log_b and not log_a.is_empty(), "Night 7 is not deterministic for a seed")
	# the light never holds her wait: she attacks after her grace at an open door even with the light on her
	var lit := NightWatchClassic.new(7, 11)
	var lk := lit.hunters["kathy"] as NightWatchStalker
	lk.room = lk.door()
	var door := lk.door()
	var caught := false
	var waited := 0.0
	while waited < 4000.0 and not caught:
		for e in lit.step(50.0, {"lightL": door == "doorL", "lightR": door == "doorR"}):
			if String(e["type"]) == "caught":
				caught = true
		waited += 50.0
	_expect(caught and waited < 3300.0, "the light held Kathy (caught after %.0f ms, grace 2610)" % waited)
	# a shut door: she waits out a rolled time, then fades silently to the stage or the kitchen on a fresh door
	var shut := NightWatchClassic.new(7, 21)
	var sk := shut.hunters["kathy"] as NightWatchStalker
	sk.room = sk.door()
	var shut_door := sk.door()
	var repelled := false
	var shut_ms := 0.0
	while shut_ms < 22000.0 and not repelled:
		for e in shut.step(50.0, {"doorL": shut_door == "doorL", "doorR": shut_door == "doorR"}):
			if String(e["type"]) == "repelled":
				repelled = true
		shut_ms += 50.0
	_expect(repelled and shut_ms >= 2450.0 and shut_ms <= 20050.0, "the shut door did not turn Kathy away within the 2.5 to 20 s hold (%.0f ms)" % shut_ms)
	_expect(NightWatchData.KATHY["fade_to"].has(sk.room) and not sk.is_at_door(), "Kathy did not fade to the stage or the kitchen (she is in %s)" % sk.room)
	# her tells: the dip (only at the door she stands at, with its light on) and the hum
	var tell := NightWatchClassic.new(7, 31)
	var tk := tell.hunters["kathy"] as NightWatchStalker
	tk.room = tk.door()
	var tdoor := tk.door()
	var other := "doorR" if tdoor == "doorL" else "doorL"
	tell.step(100.0, {"lightL": true, "lightR": true})   # elapsed 100 ms: inside the first dip [0, 180)
	_expect(tell.light_dip(tdoor) and not tell.light_dip(other), "the light at her door did not dip (and the other one must not)")
	tell.step(300.0, {"lightL": true, "lightR": true})   # 400 ms: between dips
	_expect(not tell.light_dip(tdoor), "the light dipped between dips")
	tk.attack_ms = 1.0e9   # keep her waiting so the hum can be counted
	var hums := 0
	for i in 60:
		for e in tell.step(100.0, {}):
			if String(e["type"]) == "hum":
				hums += 1
	_expect(hums >= 4 and hums <= 6, "her hum came %d times in 6 s (every 1.1 s expected)" % hums)
	# meeting her eyes: only on a hall feed with her in it; a miss locks the key
	var meet := NightWatchClassic.new(7, 41)
	var mk := meet.hunters["kathy"] as NightWatchStalker
	mk.room = "dining"
	_expect(String(meet.meet(true, "dining")["result"]) == "miss", "meeting her in the dining area (not a hall) worked")
	_expect(String(meet.meet(true, "westhall")["result"]) == "locked", "the meet key was not locked after a miss")
	meet.step(2100.0, {})
	mk.room = "westhall"
	var met := meet.meet(true, "westhall")
	_expect(String(met["result"]) == "met" and NightWatchData.KATHY["fade_to"].has(mk.room), "meeting her eyes on the west hall feed did not send her back")
	# the scene: Night 7 loads with only Kathy on the floor and the meet key listed
	NightWatchSession.start(7, 77)
	var shift := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	shift.manual_clock = true
	host.add_child(shift)
	await host.get_tree().process_frame
	for i in 40:
		shift.advance_ms(500.0)
	var visible_ids := []
	for id in shift._models:
		if (shift._models[id] as Node3D).visible:
			visible_ids.append(id)
	_expect(visible_ids == ["kathy"] or visible_ids == [] , "Night 7 shows hunters other than Kathy: %s" % str(visible_ids))
	_expect(NightWatchControls.hint_line(true, ["nw_meet"]).contains("meet her eyes"), "the monitor hint does not list the meet key on Night 7")
	shift.open_monitor("westhall")
	_expect(shift.meet_her_eyes() in ["met", "miss"], "the scene's meet key did nothing")
	shift.queue_free()
	await host.get_tree().process_frame
	NightWatchSession.start(1)



## The Night Watch pose library on the hunters (docs/NIGHT_WATCH_POSES.md): every state the scene uses has a pose, and the live hunters take them: pounding on a shut door,
## peeking, staring at the camera you watch, flinching from the light, backing away; a walking hunter keeps the rig's own clips.
func _check_poses(host: Node) -> void:
	for st in ["light_flinch", "retreat", "attack", "waiting", "at_door", "peek_left", "peek_right", "door_grace", "reaching", "camera", "listening", "idle"]:
		_expect(NightWatchPoses.has_pose(NightWatchPoses.pose_for_state(st)), "pose state '%s' has no pose in the library" % st)
	NightWatchSession.start(3, 99)
	var shift := (load("res://scenes/night_watch.tscn") as PackedScene).instantiate() as NightWatchGame
	shift.manual_clock = true
	host.add_child(shift)
	await host.get_tree().process_frame
	var d := shift.sim.hunters["dovelle"] as NightWatchStalker
	d.room = "doorL"
	shift.toggle_door("doorL")
	shift.advance_ms(20.0)
	shift._place_hunters()
	shift._animate_models(0.1)
	var player := shift._players["dovelle"] as AnimationPlayer
	_expect(shift._hunter_pose_state("dovelle") == "at_door" and player.current_animation == NightWatchPoses.clip_name("door_pound"), "Dovelle at a shut door is not pounding on it (%s / %s)" % [shift._hunter_pose_state("dovelle"), player.current_animation])
	shift.toggle_door("doorL")
	shift.advance_ms(20.0)
	d.room = "doorL"
	d.at_door_ms = 0.0
	shift._place_hunters()
	shift._animate_models(0.1)
	_expect(shift._hunter_pose_state("dovelle") == "peek_left", "a fresh arrival at the left door does not peek left (%s)" % shift._hunter_pose_state("dovelle"))
	d.at_door_ms = d.attack_ms * 0.95
	shift._animate_models(0.1)
	_expect(shift._hunter_pose_state("dovelle") == "reaching", "at the end of the wait she does not lean in (%s)" % shift._hunter_pose_state("dovelle"))
	d.room = "dining"
	shift._place_hunters()
	shift.open_monitor("dining")
	shift._animate_models(0.1)
	_expect(shift._hunter_pose_state("dovelle") == "camera", "a hunter in the room on the monitor does not stare at it (%s)" % shift._hunter_pose_state("dovelle"))
	shift.close_monitor()
	shift._flinch_left["dovelle"] = 0.5
	_expect(shift._hunter_pose_state("dovelle") == "light_flinch", "the flinch does not use the light_flinch pose")
	shift._flinch_left.clear()
	shift._retreat_left["dovelle"] = 1.0
	_expect(shift._hunter_pose_state("dovelle") == "retreat", "a turned-away hunter does not back off")
	shift._retreat_left.clear()
	(shift._walkers["dovelle"] as NightWatchWalker).moving = true
	_expect(shift._hunter_pose_state("dovelle") == "", "a walking hunter must keep the rig's own clips")
	shift.queue_free()
	await host.get_tree().process_frame
	NightWatchSession.start(1)


## Pitch that puts the crosshair on a Night Watch station (by id) from where the player stands.
func _pitch_to(player: Node, host: Node, station_id: String) -> float:
	for node in host.get_tree().root.find_children("*", "NightWatchStation", true, false):
		if String(node.get("station_id")) == station_id:
			var eye: Vector3 = (player.call("active_camera") as Camera3D).global_position
			var target: Vector3 = (node as Node3D).global_position
			var flat := Vector2(target.x - eye.x, target.z - eye.z).length()
			return atan2(target.y - eye.y, flat)
	return 0.0
