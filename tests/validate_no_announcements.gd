extends RefCounted

## Hunter callouts and the in-game tutorial are gone on purpose: players discover the game on their own.
##
##  - HunterBrain.ANNOUNCE_HUNTER_EVENTS is off, and HunterBrain.emit_world_event() drops pure announcements and strips the
##    "message" / "alert" stinger keys from mechanic events (real world sounds keep their cue).
##  - Every gimmick queues its world events through emit_world_event() (none appends to world_events directly).
##  - Ysolde still takes the battery; Briselle's relay lock-on and the void powers still raise their mechanic events, silently.
##  - The main menu has no TUTORIAL button, no tutorial dialog, and an old settings file carrying tutorial flags still loads.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- no_announcements

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_expect(not HunterBrain.ANNOUNCE_HUNTER_EVENTS, "hunter announcements are switched on")
	_helper_filters()
	_gimmicks_use_the_helper()
	_mechanics_stay_silent()
	await _main_menu_has_no_tutorial(host)
	_old_settings_with_tutorial_flags_load()
	print("  announce  hunter callouts off, mechanics intact, tutorial gone")
	return _failures


func _brain(id: String) -> HunterBrain:
	var brain := HunterBrain.new(Vector2(10, 10), "NOANN-%s" % id, id, "standard")
	brain.activate_at(Vector2(10, 10))
	return brain


func _helper_filters() -> void:
	var brain := _brain("ysolde")
	brain.world_events.clear()
	brain.emit_world_event({"what": "message", "sound": "alert", "message": "SOMETHING DETECTED"})
	_expect(brain.world_events.is_empty(), "a pure announcement event was queued")
	brain.emit_world_event({"what": "facility_alert", "at": Vector2(1, 1), "sound": "alert", "message": "BELLS"})
	var alert: Dictionary = brain.world_events[0]
	_expect(String(alert.get("what", "")) == "facility_alert" and alert.has("at"), "the alarm lost its mechanic keys")
	_expect(not alert.has("message") and not alert.has("sound"), "an alarm still carries its toast or stinger")
	brain.emit_world_event({"what": "vent_burst", "grate": "g", "sound": "vent_burst"})
	_expect(String(brain.world_events[1].get("sound", "")) == "vent_burst", "a real world sound lost its cue")
	# Void Pink's false footsteps are audio only: a mechanic event with no text, so the filter keeps it.
	var pink := _brain("void_pink")
	pink.world_events.clear()
	pink.emit_world_event({"what": "fake_footsteps", "steps": 5, "pan": 0.2, "gap": .42, "distance": 6.0, "approach": false})
	_expect(pink.world_events.size() == 1 and String(pink.world_events[0].get("what", "")) == "fake_footsteps",
		"the filter dropped Void Pink's footsteps event")
	var heard_pink := false
	var pink_target := {"peer_id": 1, "position": Vector2(30, 30), "hidden": false, "in_safe_zone": false, "facing": Vector2(0, 1)}
	pink.world_events.clear()
	for i in int(120.0 * 30.0):
		pink.gimmick.after_perception(pink, 1.0 / 30.0, pink_target, null)
		for event in pink.world_events:
			heard_pink = heard_pink or String(event.get("what", "")) == "fake_footsteps"
		pink.world_events.clear()
	_expect(heard_pink, "Void Pink never queued her footsteps event in two minutes")


## Source scan: a gimmick that appends to world_events itself would skip the filter.
func _gimmicks_use_the_helper() -> void:
	var dir := "res://game/hunters/gimmicks"
	var checked := 0
	for file in DirAccess.get_files_at(dir):
		if not file.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("%s/%s" % [dir, file])
		checked += 1
		_expect(not text.contains("world_events.append("), "%s appends to world_events directly (use emit_world_event)" % file)
	_expect(checked > 10, "found only %d gimmick scripts to scan" % checked)


func _mechanics_stay_silent() -> void:
	# (Ysolde's theft is covered by validate_hunters: still reported by cell and kind, without text.)
	# Aki / Quenelle / Briselle / Void Pink callouts used to be events of their own; whatever they queue now must carry no text.
	for id in ["aki", "quenelle", "void_pink", "void_blue", "void_cyan"]:
		var brain := _brain(id)
		var target := {"peer_id": 1, "position": Vector2(30, 30), "hidden": false, "in_safe_zone": false,
			"facing": Vector2(0, 1), "flashlight_on": true}
		for i in 900:
			brain.gimmick.before_perception(brain, 1.0 / 30.0, target, null)
			brain.gimmick.after_perception(brain, 1.0 / 30.0, target, null)
		for event in brain.world_events:
			_expect(String(event.get("what", "")) != "message", "%s queued an announcement event" % id)
			_expect(not event.has("message"), "%s queued an event with toast text" % id)
			_expect(String(event.get("sound", "")) != "alert", "%s queued an event with the alert stinger" % id)


func _main_menu_has_no_tutorial(host: Node) -> void:
	var packed := load("res://game/menus/main_menu.tscn") as PackedScene
	_expect(packed != null, "the main menu did not load")
	if packed == null:
		return
	var menu: Node = packed.instantiate()
	host.get_tree().root.add_child(menu)
	await host.get_tree().process_frame
	_expect(menu.find_child("TutorialButton", true, false) == null, "the main menu still has a TUTORIAL button")
	_expect(not menu.has_method("_on_tutorial_pressed"), "the main menu still has the tutorial dialog")
	for node in menu.find_children("*", "Button", true, false):
		var button := node as Button
		_expect(not button.text.to_upper().contains("TUTORIAL") and not button.text.to_upper().contains("HOW TO PLAY"),
			"a menu button still offers the tutorial (%s)" % button.text)
	menu.queue_free()
	await host.get_tree().process_frame


## Old settings files may carry tutorial/hint flags from earlier builds; they must be ignored, never an error.
func _old_settings_with_tutorial_flags_load() -> void:
	var path: String = Settings.SETTINGS_PATH
	var before := FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()
	var config := ConfigFile.new()
	config.load(path)
	config.set_value("game", "tutorial_seen", true)
	config.set_value("game", "hints_enabled", true)
	config.set_value("tutorial", "step", 4)
	config.set_value("audio", "master_volume_percent", 37.0)
	config.save(path)
	Settings.call("_load")
	_expect(is_equal_approx(Settings.master_volume_percent, 37.0), "settings with legacy tutorial flags did not load")
	# put the file back exactly as it was
	if before.is_empty():
		DirAccess.remove_absolute(path)
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_buffer(before)
			file.close()
	Settings.call("_load")
