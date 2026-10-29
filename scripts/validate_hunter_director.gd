extends RefCounted

## HunterDirector: hunters cooperate on every mode, scaled by difficulty. Sightings are shared, teams split (flank / cover an exit),
## crowded hunters spread out, and no runner gets more than the mode's cap of hunters committed to them.
##
##   godot --headless --path . res://scenes/validate.tscn -- hunter_director

var _failures := 0


class Field:
	var relays: Array = [{"x": 30, "y": 10}]

	func nearest_open_position(x: float, y: float, _radius: float = 1.0, _blocked = null) -> Dictionary:
		return {"x": x, "y": y}

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		return [from, to]


class Wall:
	extends Field
	func can_occupy(_x: float, _y: float, _radius: float = .23, _a = null) -> bool:
		return false


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _entry(id: String, mode: String, at: Vector2, state: int, target: Dictionary = {}) -> Dictionary:
	var brain := HunterBrain.new(at, "DIR-%s-%s" % [id, mode], "dovelle", mode)
	brain.activate_at(at)
	brain.state = state
	return {"id": id, "brain": brain, "target": target}


func _scene(mode: String, wanderers: int) -> Array:
	var runner := Vector2(20, 10)
	var target := {"position": runner}
	var entries := [_entry("spotter", mode, Vector2(16, 10), HunterBrain.State.CHASE, target)]
	entries[0]["brain"].direct_chase_visible = true
	for i in wanderers:
		entries.append(_entry("w%d" % i, mode, Vector2(26 + i * 2, 4 + i), HunterBrain.State.WANDER, target))
	return entries


func _run_mode(mode: String, seed_text: String) -> Dictionary:
	var director := HunterDirector.new(mode, seed_text)
	var entries := _scene(mode, 6)
	for i in 4:
		director.tick(1.0, entries, Field.new())
	var stats: Dictionary = director.stats
	var directed: int = int(stats["shares"]) + int(stats["flanks"]) + int(stats["covers"])
	return {"directed": directed, "stats": director.stats}


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var cap := {}
	for mode in ["relaxed", "standard", "hard", "nightmare"]:
		cap[mode] = int(HunterDirector.PROFILES[mode]["cap"])
		# no overload: never more committed to one runner than the cap, over many seeds
		var flanks := 0
		var shares := 0
		for n in 40:
			var result := _run_mode(mode, "SEED-%d" % n)
			# the spotter plus those it called up stay within the cap
			_expect(int(result["directed"]) + 1 <= cap[mode], "%s: %d hunters committed to one runner, cap %d" % [mode, int(result["directed"]) + 1, cap[mode]])
			flanks += int(result["stats"]["flanks"]) + int(result["stats"]["covers"])
			shares += int(result["stats"]["shares"])
		_expect(shares > 0, "%s: sightings are shared" % mode)
		if mode == "relaxed":
			_expect(flanks == 0, "Relaxed never flanks (%d)" % flanks)
		else:
			_expect(flanks > 0, "%s splits to flank or cover an exit (%d)" % [mode, flanks])
	# teams grow with the mode
	var teams := []
	for mode in ["relaxed", "standard", "hard", "nightmare"]:
		teams.append(int(HunterDirector.PROFILES[mode]["team"]))
	_expect(teams[0] <= teams[1] and teams[1] <= teams[2] and teams[2] <= teams[3] and teams[3] == 3 and teams[0] == 1, "teams of 1 / 2 / 2 / up to 3 (%s)" % str(teams))
	var radius := []
	for mode in ["relaxed", "standard", "hard", "nightmare"]:
		radius.append(float(HunterDirector.PROFILES[mode]["share_radius"]))
	_expect(radius[0] < radius[1] and radius[1] < radius[2] and radius[2] < radius[3], "the call reaches further on harder modes")
	# nightmare calls more hunters than relaxed in the same scene
	_expect(int(_run_mode("nightmare", "SEED-1")["directed"]) > int(_run_mode("relaxed", "SEED-1")["directed"]), "Nightmare calls up a bigger team than Relaxed")

	# scatter: three hunters standing together walk apart, on every mode, and are left alone near a runner
	for mode in ["relaxed", "standard", "hard", "nightmare"]:
		var director := HunterDirector.new(mode, "SCATTER")
		var pile := [
			_entry("a", mode, Vector2(50, 50), HunterBrain.State.WANDER, {"position": Vector2(5, 5)}),
			_entry("b", mode, Vector2(51, 50), HunterBrain.State.WANDER, {"position": Vector2(5, 5)}),
			_entry("c", mode, Vector2(50, 51), HunterBrain.State.WANDER, {"position": Vector2(5, 5)})]
		director.tick(5.0, pile, Field.new())
		_expect(int(director.stats["scatters"]) >= 2, "%s: a crowd of three spreads out (%d sent)" % [mode, int(director.stats["scatters"])])
		var sent_apart := 0
		for entry in pile:
			if (entry["brain"] as HunterBrain).last_known.distance_to(Vector2(50, 50)) > 6.0:
				sent_apart += 1
		_expect(sent_apart >= 2, "%s: scattered hunters are sent well away (%d)" % [mode, sent_apart])
	# a chasing hunter is never pulled off
	var chase_director := HunterDirector.new("nightmare", "CHASE")
	var chasing := _scene("nightmare", 2)
	chasing.append(_entry("x", "nightmare", Vector2(21, 10), HunterBrain.State.CHASE, {"position": Vector2(20, 10)}))
	chase_director.tick(5.0, chasing, Field.new())
	_expect((chasing[3]["brain"] as HunterBrain).state == HunterBrain.State.CHASE, "a chasing hunter keeps chasing")
	# a stunned or inactive hunter is left alone
	var idle := _scene("hard", 1)
	(idle[1]["brain"] as HunterBrain).stun_timer = 2.0
	HunterDirector.new("hard", "STUN").tick(5.0, idle, Field.new())
	_expect((idle[1]["brain"] as HunterBrain).state == HunterBrain.State.WANDER, "a stunned hunter is not sent anywhere")

	# separation: hunters on top of each other push apart, every mode; a wall stops the push
	var stack := [_entry("p", "nightmare", Vector2(30, 30), HunterBrain.State.CHASE),
		_entry("q", "nightmare", Vector2(30, 30), HunterBrain.State.CHASE),
		_entry("r", "nightmare", Vector2(30.3, 30), HunterBrain.State.CHASE)]
	for _i in 60:
		HunterDirector.separate(1.0 / 60.0, stack, Field.new())
	var closest := INF
	for i in stack.size():
		for j in range(i + 1, stack.size()):
			closest = minf(closest, (stack[i]["brain"] as HunterBrain).position.distance_to((stack[j]["brain"] as HunterBrain).position))
	_expect(closest > .7, "three stacked hunters did not separate (closest %.2f)" % closest)
	var walled := [_entry("w", "hard", Vector2(10, 10), HunterBrain.State.CHASE), _entry("v", "hard", Vector2(10.2, 10), HunterBrain.State.CHASE)]
	_expect(HunterDirector.separate(.1, walled, Wall.new()) == 0
		and (walled[0]["brain"] as HunterBrain).position == Vector2(10, 10), "separation pushed a hunter into a wall")
	var apart := [_entry("a", "hard", Vector2(10, 10), HunterBrain.State.CHASE), _entry("b", "hard", Vector2(14, 10), HunterBrain.State.CHASE)]
	_expect(HunterDirector.separate(.1, apart, Field.new()) == 0, "hunters already apart were pushed")
	if _failures == 0:
		print("  ok    hunter_director: sightings shared, teams per mode, flank / cover, scatter, cap per runner, chasers left alone")
	return _failures
