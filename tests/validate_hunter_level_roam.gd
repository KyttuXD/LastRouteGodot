extends RefCounted

## HunterLevelRoam (089): on Normal and up more hunters take ladders, ramps and stairwells to other levels on their own,
## up as well as down; Relaxed keeps the pre-089 rule; sewer-shy hunters never roam; followers may use stairwells.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_level_roam

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _share(difficulty: String, affinity: String, level: int) -> float:
	var hits := 0
	var total := 0
	for n in 60:
		for window in 40:
			total += 1
			if HunterLevelRoam.rolls("HUNTER:%d" % n, difficulty, affinity, level, window * HunterLevelRoam.WINDOW + 1.0):
				hits += 1
	return float(hits) / float(total)


func run(host: Node) -> int:
	await host.get_tree().process_frame
	# Relaxed is the old rule exactly: prefer hunters, level 0 only, one in three
	for n in 60:
		for window in 20:
			var id := "HUNTER:%d" % n
			var now := window * 20.0 + 3.0
			var legacy := absi(hash("%s:%d" % [id, floori(now / 20.0)])) % 3 == 0
			_expect(HunterLevelRoam.rolls(id, "relaxed", "prefer", 0, now) == legacy, "relaxed prefer roll differs from pre-089")
			_expect(not HunterLevelRoam.rolls(id, "relaxed", "follow", 0, now), "relaxed: a follow hunter roamed")
			_expect(not HunterLevelRoam.rolls(id, "relaxed", "prefer", -1, now), "relaxed: a prefer hunter roamed off level 0")
	for mode in ["relaxed", "standard", "hard", "nightmare"]:
		_expect(_share(mode, "avoid", 0) == 0.0, "%s: a sewer-shy hunter roamed" % mode)
	# Normal: follow hunters roam on any level, about CHANCE of the windows; harder modes roam at least as often
	var standard := _share("standard", "follow", 0)
	_expect(absf(standard - float(HunterLevelRoam.CHANCE["standard"])) < .08, "standard follow share %.2f" % standard)
	_expect(_share("standard", "follow", -9) > .3, "standard: no roaming at depth 10")
	_expect(_share("standard", "prefer", -3) >= standard - .05, "standard: prefer hunters roam less than followers")
	_expect(_share("nightmare", "follow", 0) >= standard, "nightmare roams less than standard")
	_expect(HunterLevelRoam.LINK_KINDS.has("stairs") and HunterLevelRoam.LINK_KINDS.has("spiral"),
		"stairwells are not hunter links")
	# link_ok: up and down on Normal, only down on Relaxed, never to a level the route does not have
	var down := LevelLink.make("ladder", Vector3i(0, 0, 0), 0, Vector2i(10, 10), -1, Vector2i(10, 10))
	var up := LevelLink.make("stairs", Vector3i(0, 0, 0), -2, Vector2i(10, 10), -3, Vector2i(10, 10))
	_expect(HunterLevelRoam.link_ok(null, down, 0, "standard"), "standard: ladder down refused")
	_expect(HunterLevelRoam.link_ok(null, up, -3, "standard"), "standard: stairs up refused")
	_expect(HunterLevelRoam.link_ok(null, down, 0, "relaxed"), "relaxed: ladder down refused")
	_expect(not HunterLevelRoam.link_ok(null, up, -3, "relaxed"), "relaxed: roamed up")
	_expect(not HunterLevelRoam.link_ok(null, {}, 0, "standard"), "empty link accepted")
	var vent := LevelLink.make("grate", Vector3i(0, 0, 0), 0, Vector2i(10, 10), -1, Vector2i(10, 10))
	_expect(not HunterLevelRoam.link_ok(null, vent, 0, "standard"), "a vent grate accepted")
	var generator := StreamedRouteGenerator.new("ROAM-089")
	var too_high := LevelLink.make("stairs", Vector3i(7, 0, 7), 5, Vector2i(10, 10), 4, Vector2i(10, 10))
	_expect(not HunterLevelRoam.link_ok(generator, too_high, 4, "standard"), "roamed to a level the route does not have")
	# the game uses it: follow and roam both search the hunter link kinds, and the cooldown is kept
	var source := FileAccess.get_file_as_string("res://game/infinite_route/infinite_route_test.gd")
	_expect(source.count("HunterLevelRoam.LINK_KINDS") >= 2, "follow / roam do not search stairwells")
	_expect(source.contains("HunterLevelRoam.rolls(") and source.contains("HunterLevelRoam.link_ok("), "roam rule not wired")
	_expect(source.contains("_level_roam_until[entity_id]"), "no stay after a roam")
	print("  hunter_level_roam: standard share %.2f, %d failures" % [standard, _failures])
	return _failures
