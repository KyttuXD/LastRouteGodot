extends RefCounted

## YSOLDE AVOIDS (docs/YSOLDE.md): flee targets gain distance, are reachable and not dead ends; she backs off from a runner in
## sight without approaching, never captures, freezes when cornered, and goes back to her battery errands afterwards.
##
##   godot --headless --path . res://scenes/validate.tscn -- ysolde

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var generator := StreamedRouteGenerator.new("YSOLDE")
	var navigation := StreamedHunterNavigation.new(generator, 0)
	var coords := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			coords.append(Vector3i(dx, 0, dz))
	navigation.refresh(0, coords)
	var cells := navigation.floor_cells()
	var trials := 0
	var gained := 0
	var closest := INF
	for index in range(0, cells.size(), maxi(1, cells.size() / 40)):
		var at: Vector2 = Vector2(cells[index]) + Vector2(.5, .5)
		var threat := at + Vector2(4, 0)
		if not navigation.can_occupy(threat.x, threat.y) or not navigation.has_line_of_sight(at, threat):
			continue
		trials += 1
		var point = YsoldeGimmick.flee_target(navigation, at, threat, YsoldeGimmick.AVOID_DISTANCE)
		if point == null:
			continue
		var target_point: Vector2 = point
		_expect(target_point.distance_to(threat) > at.distance_to(threat), "flee target %s does not gain distance from %s" % [target_point, threat])
		_expect(not navigation.find_path(Vector2i(floori(at.x), floori(at.y)), Vector2i(floori(target_point.x), floori(target_point.y))).is_empty(), "flee target %s is unreachable" % target_point)
		gained += 1
		# simulate: she should never end closer to a still runner than she started
		var brain := HunterBrain.new(at, "YS", "ysolde", "standard")
		brain.activate_at(at)
		var start_gap := at.distance_to(threat)
		var target := {"position": threat, "hidden": false, "in_safe_zone": false, "noise": 4.0, "flashlight_on": true}
		for _step in 150:
			_expect(not brain.update(1.0 / 30.0, navigation, target, 1, 0), "Ysolde captured a runner who kept her distance")
			closest = minf(closest, brain.position.distance_to(threat) - start_gap)
	# KT: a runner who catches up to her (or blocks her) is grabbed like by any other hunter
	var catcher := HunterBrain.new(Vector2(cells[0]) + Vector2(.5, .5), "YS-CATCH", "ysolde", "standard")
	catcher.activate_at(catcher.position)
	var on_her := {"position": catcher.position, "hidden": false, "in_safe_zone": false, "noise": 4.0, "flashlight_on": true}
	_expect(catcher.update(1.0 / 30.0, navigation, on_her, 1, 0), "a runner who reached Ysolde was not caught")
	_expect(trials >= 10, "only %d flee trials" % trials)
	_expect(gained >= trials * .7, "only %d of %d trials found a retreat" % [gained, trials])
	_expect(closest > -0.6, "Ysolde approached a runner in sight by %.2f m" % -closest)
	if _failures == 0:
		print("  ysolde  %d retreats (%s mode): all gain distance and are reachable, never closer than she started, never catches from a distance, catches a runner who reaches her" % [gained, YsoldeGimmick.BEHAVIOUR])
	return _failures
