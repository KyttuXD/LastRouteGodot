extends RefCounted

## The mode framework: the 2D mode table is intact (nine modes, shifts, presets with a full slider set), the registry only lists scenes that
## exist and extend NightWatchMode, the session carries mode/level/seed/sliders, and a win is saved per mode (a clear opens the next
## shift; a Custom Night saves its best score and the matching preset's star). Per-mode rules are in each mode's own suite.

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	NwLeakProbe.fresh()
	NightWatchSave.path = "user://night_watch_modes_test.cfg"
	NightWatchSave.reset()
	var modes: Array = NightWatchModesData.MODES
	_expect(modes.size() == 9, "the mode table has %d modes, not 9" % modes.size())
	var ids := []
	for m in modes:
		ids.append(String(m["id"]))
		_expect(not (m["levels"] as Array).is_empty() and int(m["scored"]) >= 1, "%s has no shifts" % m["id"])
		if not (m["presets"] as Array).is_empty():
			_expect((m["presets"] as Array).size() == 4, "%s does not have four presets" % m["id"])
			_expect((m["custom"] as Array).size() == (m["cast"] as Array).size(), "%s: a slider per cast member is missing" % m["id"])
			for p in m["presets"]:
				_expect((p["ai"] as Dictionary).size() == (m["custom"] as Array).size(), "%s preset %s does not name every slider" % [m["id"], p["id"]])
	_expect(ids == ["classic", "mask", "lure", "bedroom", "story", "descent", "dayshift", "extra", "mixed"], "the mode order differs from the 2D game's: %s" % str(ids))
	for id in NightWatchModeRegistry.SCENES:
		var path := String(NightWatchModeRegistry.SCENES[id])
		_expect(ResourceLoader.exists(path), "%s's scene %s does not exist" % [id, path])
		var scene := (load(path) as PackedScene).instantiate()
		_expect(scene is NightWatchMode, "%s's scene does not extend NightWatchMode" % id)
		scene.free()
	_expect(NightWatchModeRegistry.prepare("mask", 1) == "" or NightWatchModeRegistry.playable("mask"), "an unbuilt mode returned a scene")
	# the session and the mode-keyed save
	_expect(NightWatchModeRegistry.prepare("classic", 3, {"dovelle": 5}) != "", "classic did not prepare")
	_expect(NightWatchSession.mode_id == "classic" and NightWatchSession.night == 3 and NightWatchSession.is_custom and NightWatchSession.custom_levels == {"dovelle": 5}, "the session did not keep mode, level and sliders")
	var seed_before := NightWatchSession.seed_value
	_expect(seed_before != 0, "the session has no seed")
	var mode := NightWatchMode.new()
	host.add_child(mode)
	mode.read_session()
	_expect(mode.mode_id == "classic" and mode.level == 3 and mode.is_custom and mode.seed_value == seed_before, "read_session lost something")
	var score := mode.record_win()
	_expect(score == 50 and NightWatchSave.best_score("classic") == 50 and NightWatchSave.cleared_levels("classic").is_empty(), "a Custom Night win must save its score, not clear a night")
	NightWatchSession.start_mode("classic", 1)
	mode.read_session()
	mode.record_win()
	_expect(NightWatchSave.cleared_levels("classic") == [1] and NightWatchSave.level_open("classic", 2) and not NightWatchSave.level_open("classic", 3), "a clear did not open exactly the next shift")
	NightWatchSession.start_mode("classic", 1, {"dovelle": 8, "nyxie": 0, "ravelle": 0, "ilyra": 0, "aki": 0})
	mode.read_session()
	mode.record_win()
	_expect(NightWatchSave.stars("classic") == ["first-shift"], "a Custom Night equal to a preset did not earn its star")
	# other modes keep their own keys; Mixed Shift opens all five shifts
	NightWatchSave.record_level_clear("mask", 1)
	_expect(NightWatchSave.cleared_levels("mask") == [1] and NightWatchSave.cleared_levels("lure").is_empty(), "mode progress leaked between modes")
	_expect(NightWatchSave.level_open("mixed", 5, true), "Mixed Shift's Endless is not open")
	_expect(not NightWatchSave.custom_unlocked("mask"), "Custom Night opened before Night 5")
	for n in range(1, 6):
		NightWatchSave.record_level_clear("mask", n)
	_expect(NightWatchSave.custom_unlocked("mask"), "Custom Night did not open after Night 5")
	_expect(NightWatchModesData.rating_of(0, 400) == "Great Job!" and NightWatchModesData.rating_of(400, 400) == "Unbeatable!" and NightWatchModesData.rating_of(160, 400) == "Amazing!", "ratings differ from the 2D game's")
	mode.queue_free()
	NightWatchSave.reset()
	NightWatchSave.path = NwLeakProbe.scratch_path()
	NightWatchSession.start(1)
	if _failures == 0:
		print("  night_watch_modes  nine-mode table, registry, session and the mode-keyed save (clear, star, best score)")
	return _failures
