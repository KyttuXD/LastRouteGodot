extends RefCounted

## Hunters on the City: the real HunterBrain.update() driven through the City's streets, plazas and building doors
## (the hunter_real machinery, pointed at CityRouteGenerator): all 38 hunters at their real speeds, chasing a runner and
## patrolling, in the spawn roundabout, the avenue, a shelter plaza, a garden quarter and the dense building blocks.
## A trial is stuck when the hunter stands still more than a second while it should be moving.

const SEED := "CITY-NAV"
const WINDOWS := [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(-1, 0, 1), Vector3i(1, 0, -1)]
const STUCK_LIMIT := 1.0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var real: RefCounted = (load("res://scripts/validate_hunter_real.gd") as GDScript).new()
	var generator := CityRouteGenerator.new(SEED)
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(SEED)
	var trials := 0
	var stuck := 0
	var worst := 0.0
	var worst_case := ""
	var samples: Array = []
	for coord_value in WINDOWS:
		var coord: Vector3i = coord_value
		_expect(generator.is_chunk_allowed(coord), "window chunk %s is not part of the city" % coord)
		var navigation: StreamedHunterNavigation = real._navigation(generator, coord)
		var cells := navigation.floor_cells()
		_expect(cells.size() > 400, "window %s has too few walkable cells (%d)" % [coord, cells.size()])
		for hunter_id in ids:
			for mode in ["direct", "patrol"]:
				var setup: Dictionary = real._pick(navigation, cells, rng, mode == "direct")
				if setup.is_empty():
					continue
				var result: Dictionary = real._simulate(navigation, setup, String(hunter_id), mode)
				trials += 1
				var still := float(result["still"])
				if still > STUCK_LIMIT:
					stuck += 1
					if samples.size() < 6:
						samples.append("%s %s %s at %s still %.1fs" % [coord, hunter_id, mode, result["where"], still])
				if still > worst:
					worst = still
					worst_case = "%s %s %s" % [coord, hunter_id, mode]
	_expect(trials >= 240, "only %d nav trials ran" % trials)
	_expect(stuck == 0, "%d of %d City hunter trials stood still more than %.1f s (worst %.2f s %s; e.g. %s)" % [
		stuck, trials, STUCK_LIMIT, worst, worst_case, samples])
	if _failures == 0:
		print("  city_nav  %d trials on City geometry (38 hunters, 4 districts), none stuck over %.1f s (worst %.2f s)" % [
			trials, STUCK_LIMIT, worst])
	return _failures
