extends RefCounted

## Hunters never stay stuck. Drives real HunterBrains through generated routes (every district) and measures
## the longest time one stood still while it still had somewhere to go. Two trials per hunter: an INVESTIGATE walk to a far
## reachable point (patrol/search style pathing), and a CHASE after a runner who walks a long path (the runner stays out of
## sight, so the hunter follows its path rather than steering straight at it). Several A-Z speeds plus a Void hunter.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_nav
##
## Fails on any stand-still longer than STUCK_LIMIT seconds or a trip that does not arrive.

const HUNTERS := ["dovelle", "kathy", "loxelle", "aki", "elise", "void_black"]
const TRIALS_PER_HUNTER := 5
const STUCK_LIMIT := 1.0
const STEP := 1.0 / 30.0
const WINDOWS := [
	{"seed": "NAV-A", "from": Vector2i(-3, -3), "to": Vector2i(3, 3)},
	{"seed": "MAP-CHECK", "from": Vector2i(0, 3), "to": Vector2i(6, 6)},
]

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	# Same contract as hunter_real: every shard draws every trial (one rng per window) and simulates every n-th one.
	# The shards together are the unsharded run. run_suites.py spreads hunter_nav#i/4.
	var shard_index := 0
	var shard_count := 1
	var shard := OS.get_environment("VALIDATE_SHARD")
	if shard.contains("/"):
		shard_index = int(shard.get_slice("/", 0))
		shard_count = maxi(1, int(shard.get_slice("/", 1)))
	_expect(shard_index >= 0 and shard_index < shard_count, "bad shard %s" % shard)
	var ordinal := -1
	var total_trials := 0
	var stuck_trials := 0
	var timeouts := 0
	var worst_still := 0.0
	var worst_case := ""
	var timeout_sample := ""
	for window in WINDOWS:
		var generator := StreamedRouteGenerator.new(String(window["seed"]))
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(String(window["seed"]))
		for hunter_id in HUNTERS:
			for trial in TRIALS_PER_HUNTER:
				var setup := _pick_trial(generator, rng, window)
				if setup.is_empty():
					continue
				for mode in ["investigate", "chase"]:
					ordinal += 1
					if ordinal % shard_count != shard_index:
						continue
					var result := _simulate(generator, setup, String(hunter_id), mode)
					total_trials += 1
					if float(result["still"]) > STUCK_LIMIT:
						stuck_trials += 1
					# a chase target outruns a slow hunter, so only the investigate trips must arrive
					if mode == "investigate" and not bool(result["arrived"]):
						timeouts += 1
						if timeout_sample.is_empty():
							timeout_sample = "%s %s %s -> %s stuck at %s" % [window["seed"], hunter_id, setup["start"], setup["goal"], result["where"]]
					if float(result["still"]) > worst_still:
						worst_still = float(result["still"])
						worst_case = "%s %s %s from %s to %s at %s" % [window["seed"], hunter_id, mode,
							setup["start"], setup["goal"], result["where"]]
	metrics = {"trials": total_trials, "stuck": stuck_trials, "timeouts": timeouts, "worst_still": worst_still}
	_expect(stuck_trials == 0, "%d of %d hunter trips stood still for more than %.1f s (worst %.2f s: %s)" % [
		stuck_trials, total_trials, STUCK_LIMIT, worst_still, worst_case])
	_expect(timeouts == 0, "%d investigate trips never arrived (e.g. %s)" % [timeouts, timeout_sample])
	if _failures == 0:
		print("  hunter_nav  %d trips, none stood still over %.1f s (worst %.2f s), all arrived" % [
			total_trials, STUCK_LIMIT, worst_still])
	else:
		print("  hunter_nav metrics: %s" % [metrics])
	return _failures


## A start and a far, reachable goal inside a freshly built navigation window.
func _pick_trial(generator: StreamedRouteGenerator, rng: RandomNumberGenerator, window: Dictionary) -> Dictionary:
	var from: Vector2i = window["from"]
	var to: Vector2i = window["to"]
	var coord := Vector3i(rng.randi_range(from.x, to.x), 0, rng.randi_range(from.y, to.y))
	var navigation := StreamedHunterNavigation.new(generator, 0)
	var coords := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			coords.append(Vector3i(coord.x + dx, 0, coord.z + dz))
	navigation.refresh(0, coords)
	var cells := navigation.floor_cells()
	if cells.size() < 100:
		return {}
	for _attempt in 30:
		var start: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var goal: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var distance := Vector2(start).distance_to(Vector2(goal))
		if distance < 25.0 or distance > 70.0:
			continue
		var path := navigation.find_path(start, goal)
		if path.size() < 20:
			continue
		return {"navigation": navigation, "start": start, "goal": goal, "path": path, "coord": coord}
	return {}


func _simulate(generator: StreamedRouteGenerator, setup: Dictionary, hunter_id: String, mode: String) -> Dictionary:
	var navigation: StreamedHunterNavigation = setup["navigation"]
	var start: Vector2i = setup["start"]
	var path: Array = setup["path"]
	var brain := HunterBrain.new(Vector2(start) + Vector2(.5, .5), "NAV-%s" % hunter_id, hunter_id, "standard")
	brain.activate_at(Vector2(start) + Vector2(.5, .5))
	var goal_point := Vector2(setup["goal"]) + Vector2(.5, .5)
	var still := 0.0
	var worst_still := 0.0
	var where := Vector2.ZERO
	var elapsed := 0.0
	var arrived := false
	var previous := brain.position
	# the runner for the chase mode walks the planned path at a walking pace, out of the hunter's sight
	var runner_index := mini(path.size() - 1, 12)
	var runner_position := Vector2(path[runner_index]) + Vector2(.5, .5)
	# slow patrollers need time: allow 2.5x the path length at the hunter's own walking speed
	var limit := maxf(60.0, float(path.size()) / maxf(.3, brain.base_speed) * 2.5)
	if mode == "investigate":
		brain.state = HunterBrain.State.INVESTIGATE
		brain.has_last_known = true
		brain.last_known = goal_point
	while elapsed < limit:
		elapsed += STEP
		if mode == "chase":
			var next_cell := mini(path.size() - 1, runner_index + 1)
			var wanted := Vector2(path[next_cell]) + Vector2(.5, .5)
			var runner_step := 3.6 * STEP
			if runner_position.distance_to(wanted) <= runner_step:
				runner_index = next_cell
				runner_position = wanted
			else:
				runner_position += (wanted - runner_position).normalized() * runner_step
			var target := {"position": runner_position, "hidden": false, "in_safe_zone": false, "noise": 10.5,
				"flashlight_on": true, "sprinting": true}
			# a chase with a recent sighting but no line of sight: she follows the path to the last known point
			brain.state = HunterBrain.State.CHASE
			brain.has_last_known = true
			brain.last_known = runner_position
			brain.direct_chase_visible = false
			brain.update(STEP, navigation, target, 1, 0)
			if brain.position.distance_to(runner_position) < 1.2:
				arrived = true
				break
		else:
			# a runner far away and hidden: perception ignores it, so the hunter just walks its investigate target
			brain.update(STEP, navigation, {"position": Vector2(1.0e5, 1.0e5), "hidden": true, "in_safe_zone": false,
				"noise": 0.0, "flashlight_on": false}, 1, 0)
			if brain.state != HunterBrain.State.INVESTIGATE and brain.position.distance_to(goal_point) < 1.5:
				arrived = true
				break
			if brain.state == HunterBrain.State.SEARCH or brain.state == HunterBrain.State.IDLE:
				arrived = brain.position.distance_to(goal_point) < 2.0
				break
		var moved := brain.position.distance_to(previous)
		previous = brain.position
		# a corner peek stops on purpose for its look (bounded and checked by hunter_peek)
		if moved < 0.004 and brain.state != HunterBrain.State.PEEK:
			still += STEP
			if still > worst_still:
				worst_still = still
				where = brain.position
		else:
			still = 0.0
	return {"still": worst_still, "arrived": arrived, "where": where}
