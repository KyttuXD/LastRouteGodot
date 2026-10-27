extends RefCounted

## Real-play hunter movement on the real streamed geometry (props, doors, every district, several seeds), driving the
## real HunterBrain.update() with live perception -- including the direct-chase branch the abstract hunter_nav trips
## skip -- for all 26 A-Z hunters plus the 12 Void hunters at their real speeds.
##
##   godot --headless --path . res://scenes/validate.tscn -- hunter_real
##
## Per trial a hunter is stuck when it stays within 0.004 cells per tick for more than STUCK_LIMIT seconds while it
## is moving (not IDLE/SEARCH/stunned/held by a gimmick) and still more than 1.8 cells from where it wants to be.

const STUCK_LIMIT := 1.0
const STEP := 1.0 / 30.0
const SEEDS := ["REAL-A", "REAL-B"]
const SEARCH_RADIUS := 7
const TRIAL_SECONDS := 14.0
const PATROL_SECONDS := 20.0

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var trials := 0
	var stuck := 0
	var worst := 0.0
	var worst_case := ""
	var by_biome := {}
	var samples: Array = []
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(seed_text)
		for biome in StreamedRouteGenerator.BIOMES:
			var coord := _find_chunk(generator, biome)
			if coord.y == 999999:
				continue
			var navigation := _navigation(generator, coord)
			var cells := navigation.floor_cells()
			if cells.size() < 100:
				continue
			for hunter_id in ids:
				for mode in ["direct", "patrol"]:
					var setup := _pick(navigation, cells, rng, mode == "direct")
					if setup.is_empty():
						continue
					var result := _simulate(navigation, setup, String(hunter_id), mode)
					trials += 1
					if float(result["still"]) > STUCK_LIMIT:
						stuck += 1
						by_biome[biome] = int(by_biome.get(biome, 0)) + 1
						if samples.size() < 8:
							samples.append("%s %s %s %s at %s state %s still %.1fs" % [seed_text, biome,
								hunter_id, mode, result["where"], result["state"], float(result["still"])])
					if float(result["still"]) > worst:
						worst = float(result["still"])
						worst_case = "%s %s %s %s" % [seed_text, biome, hunter_id, mode]
	metrics = {"trials": trials, "stuck": stuck, "worst": worst, "by_biome": by_biome, "samples": samples}
	_expect(stuck == 0, "%d of %d real hunter trials stood still more than %.1f s (worst %.2f s %s; by district %s; e.g. %s)" % [
		stuck, trials, STUCK_LIMIT, worst, worst_case, by_biome, samples])
	if _failures == 0:
		print("  hunter_real  %d real-geometry trials (38 hunters, every district), none stuck over %.1f s (worst %.2f s)" % [
			trials, STUCK_LIMIT, worst])
	return _failures


func _find_chunk(generator: StreamedRouteGenerator, biome: String) -> Vector3i:
	for r in range(0, 14):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord) or generator.biome_for(coord) != biome:
					continue
				# the whole 3x3 window should be this district and allowed
				var ok := true
				for oz in range(-1, 2):
					for ox in range(-1, 2):
						var n := Vector3i(dx + ox, 0, dz + oz)
						if not generator.is_chunk_allowed(n) or generator.biome_for(n) != biome:
							ok = false
				if ok:
					return coord
	return Vector3i(0, 999999, 0)


func _navigation(generator: StreamedRouteGenerator, coord: Vector3i) -> StreamedHunterNavigation:
	var navigation := StreamedHunterNavigation.new(generator, 0)
	var coords := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			coords.append(Vector3i(coord.x + dx, 0, coord.z + dz))
	navigation.refresh(0, coords)
	return navigation


func _pick(navigation: StreamedHunterNavigation, cells: Array, rng: RandomNumberGenerator, need_los: bool) -> Dictionary:
	for _attempt in 60:
		var start: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		if not need_los:
			return {"start": start}
		var goal: Vector2i = cells[rng.randi_range(0, cells.size() - 1)]
		var distance := Vector2(start).distance_to(Vector2(goal))
		if distance < 4.0 or distance > 14.0:
			continue
		var path := navigation.find_path(start, goal)
		if path.size() < 6:
			continue
		return {"start": start, "goal": goal, "path": path}
	return {}


func _simulate(navigation: StreamedHunterNavigation, setup: Dictionary, hunter_id: String, mode: String) -> Dictionary:
	var start: Vector2i = setup["start"]
	var start_point := Vector2(start) + Vector2(.5, .5)
	var brain := HunterBrain.new(start_point, "REAL-%s" % hunter_id, hunter_id, "standard")
	brain.activate_at(start_point)
	var elapsed := 0.0
	var still := 0.0
	var worst := 0.0
	var where := start_point
	var worst_state := ""
	var previous := brain.position
	var runner := Vector2.ZERO
	var path: Array = setup.get("path", [])
	var runner_index := 0
	if mode == "direct":
		runner_index = mini(path.size() - 1, 6)
		runner = Vector2(path[runner_index]) + Vector2(.5, .5)
	var limit := TRIAL_SECONDS if mode == "direct" else PATROL_SECONDS
	while elapsed < limit:
		elapsed += STEP
		var wants := Vector2.ZERO
		if mode == "direct":
			# a runner that walks its planned path, close enough to be seen and heard
			var next_index := mini(path.size() - 1, runner_index + 1)
			var wanted := Vector2(path[next_index]) + Vector2(.5, .5)
			var runner_step := 2.4 * STEP
			if runner.distance_to(wanted) <= runner_step:
				runner_index = next_index
				runner = wanted
			else:
				runner += (wanted - runner).normalized() * runner_step
			var target := {"position": runner, "hidden": false, "in_safe_zone": false, "noise": 10.5,
				"flashlight_on": true, "sprinting": false,
				"in_vent": hunter_id == "verrine", "vent_time_in": 6.0}
			if brain.update(STEP, navigation, target, 1, 0) or brain.position.distance_to(runner) < 1.2:
				break   # caught the runner
			wants = runner
		else:
			brain.update_without_target(STEP, navigation, 1, 0)
			wants = brain.wander_target if brain.state == HunterBrain.State.WANDER else brain.last_known
		# every state that plays a walk/chase clip: standing still in one of these is "walking in place"
		var moving_state: bool = brain.state != HunterBrain.State.IDLE
		var held: bool = brain.stun_timer > 0.0 or (brain.gimmick != null and brain.gimmick.holds_position()) \
			or not brain.active or brain.emote_left > 0.0 \
			# Haelith guards the uncollected relay she reached: standing on it is her design
			or (hunter_id == "haelith" and brain.position.distance_to(brain.last_known) < 1.0)
		var moved := brain.position.distance_to(previous)
		previous = brain.position
		if moving_state and not held and (moved < 0.004 or brain.stuck_seconds > STUCK_LIMIT):
			still += STEP
			if still > worst:
				worst = still
				where = brain.position
				worst_state = "%s search=%s chase_visible=%s last_known=%s" % [brain.state, brain.search_target, brain.direct_chase_visible, brain.last_known]
		else:
			still = 0.0
	return {"still": worst, "where": where, "state": worst_state}
