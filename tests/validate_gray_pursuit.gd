extends RefCounted

## The anti-idle / anti-AFK trigger on an idle runner: Gray is handed the runner's exact position and reaches and captures them
## within a bounded time on the first trigger, whatever the light, line of sight or level depth -- she does not search, give up
## or retarget while the runner stays put. Without the trigger she stays dormant (the pre-fix behaviour), and a runner who moves
## away is hunted normally.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- gray_pursuit

const STEP := 1.0 / 30.0
## Seconds from the trigger to the catch, per mode (the pursuit itself takes a fraction of this).
const BOUND := {"relaxed": 55.0, "standard": 45.0, "hard": 40.0, "nightmare": 35.0}

var _failures := 0


class Field:
	var line_clear := true
	var safe_zones: Array = []
	var exit_cell := Vector2i(-1, -1)
	var rooms: Array = []
	var relays: Array = []
	var vents: Array = []
	var hiding_spots: Array = []

	func has_line_of_sight(_from: Vector2, _to: Vector2) -> bool:
		return line_clear

	func can_occupy(_x: float, _y: float, _radius: float = .23, _blocked_cells = null) -> bool:
		return true

	func nearest_open_position(x: float, y: float, _radius: float = 1.0, _blocked = null) -> Dictionary:
		return {"x": x, "y": y}

	func room_at(_x: float, _y: float) -> Dictionary:
		return {}

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		var result := [from]
		var cursor := from
		while cursor != to:
			if cursor.x != to.x:
				cursor.x += 1 if to.x > cursor.x else -1
			else:
				cursor.y += 1 if to.y > cursor.y else -1
			result.append(cursor)
		return result


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _target(at: Vector2, extra: Dictionary = {}) -> Dictionary:
	var target := {"peer_id": 1, "position": at, "hidden": false, "in_safe_zone": false, "noise": 0.0, "flashlight_on": false,
		"facing": Vector2(1, 0), "meters": null}
	target.merge(extra, true)
	return target


func _gray(mode: String, at: Vector2) -> HunterBrain:
	var brain := HunterBrain.new(at, "GRAY-%s" % mode, "void_gray", mode)
	brain.activate_at(at)
	brain.state = HunterBrain.State.SEARCH
	brain.has_last_known = true
	return brain


## Seconds until the capture, or INF.
func _catch_time(brain: HunterBrain, field: Field, runner: Vector2, depth: int, extra: Dictionary = {}) -> float:
	var clock := 0.0
	while clock < 120.0:
		clock += STEP
		if brain.update(STEP, field, _target(runner, extra), depth, 0):
			return clock
	return INF


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var runner := Vector2(40.5, 40.5)
	for mode in ["relaxed", "standard", "hard", "nightmare"]:
		for depth in [1, 3]:   # the surface, and a storey down (the sewer)
			for lit in [true, false]:
				for clear in [true, false]:
					var field := Field.new()
					field.line_clear = clear
					var brain := _gray(mode, Vector2(40.5, 22.5))
					(brain.gimmick as VoidGrayGimmick).force_hunt(brain, runner)
					var at := _catch_time(brain, field, runner, depth, {"flashlight_on": lit})
					_expect(at <= float(BOUND[mode]), "%s depth %d %s %s: Gray caught the idle runner in %.1f s (bound %.0f)" % [
						mode, depth, "lit" if lit else "dark", "in sight" if clear else "out of sight", at, float(BOUND[mode])])
	# a hidden runner is walked up to as well (the hide check is the scene's job): she reaches the spot
	var hidden_brain := _gray("standard", Vector2(40.5, 22.5))
	(hidden_brain.gimmick as VoidGrayGimmick).force_hunt(hidden_brain, runner)
	for i in 1800:
		hidden_brain.update(STEP, Field.new(), _target(runner, {"hidden": true}), 1, 0)
	_expect(hidden_brain.position.distance_to(runner) < 1.5, "Gray walks up to a hidden idle runner's spot (%.1f cells off)" % hidden_brain.position.distance_to(runner))
	# never gives up: a long wait out of sight keeps her on the runner
	var patient := _gray("standard", Vector2(40.5, 22.5))
	(patient.gimmick as VoidGrayGimmick).force_hunt(patient, runner)
	var blind := Field.new()
	blind.line_clear = false
	patient.stun_timer = 20.0   # held off for 20 s: no timer may expire into a wander
	var patient_caught := false
	for i in 1500:
		if patient.update(STEP, blind, _target(runner, {"noise": 0.0}), 1, 0):
			patient_caught = true
			break
	_expect(patient_caught, "a locked Gray still catches an out-of-sight idle runner after a 20 s stun")
	# no trigger, no hunt: she stays dormant and uncatchable
	var dormant := _gray("standard", Vector2(40.5, 22.5))
	var dormant_field := Field.new()
	var dormant_at := _catch_time(dormant, dormant_field, runner, 1)
	_expect(dormant_at == INF, "without the trigger Gray stays dormant")
	# a runner who walks away is hunted normally: the lock lets go
	var drifter := _gray("standard", Vector2(40.5, 22.5))
	(drifter.gimmick as VoidGrayGimmick).force_hunt(drifter, runner)
	drifter.update(STEP, Field.new(), _target(runner + Vector2(12, 0)), 1, 0)
	_expect(not (drifter.gimmick as VoidGrayGimmick).locked, "the lock lets go once the runner walks away")
	# replication
	var copy := _gray("standard", Vector2(0, 0))
	(copy.gimmick as VoidGrayGimmick).apply_network_state((drifter.gimmick as VoidGrayGimmick).network_state())
	var locked_one := _gray("standard", Vector2(0, 0))
	(locked_one.gimmick as VoidGrayGimmick).force_hunt(locked_one, runner)
	(copy.gimmick as VoidGrayGimmick).apply_network_state((locked_one.gimmick as VoidGrayGimmick).network_state())
	_expect((copy.gimmick as VoidGrayGimmick).locked and (copy.gimmick as VoidGrayGimmick).hunting, "the lock replicates to guests")

	if _failures == 0:
		print("  ok    gray_pursuit: an idle runner (surface and a storey down, lit / dark, in sight / out of sight) is caught within the bound on the first trigger")
	return _failures
