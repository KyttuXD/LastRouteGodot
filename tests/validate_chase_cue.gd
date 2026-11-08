extends RefCounted

## B4 (docs/WAYPOINTS.md is unrelated; see game/infinite_route/chase_cue.gd): the chase cue for the runner's floor. A hunter in CHASE on
## another floor, directly above or below the runner in plan view, is not a chase for this floor, and a hunter far off after the chase
## (state CHASE, no sight of the runner) is not either. A chase on this floor that she can see, or one close by, still is.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- chase_cue

const CHASE_CUE := preload("res://game/infinite_route/chase_cue.gd")

var _failures := 0


class FakeView:
	extends RefCounted
	var brain: HunterBrain


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _brain(position: Vector2, state: HunterBrain.State, sees: bool) -> HunterBrain:
	var brain := HunterBrain.new(position, "CHASE-CUE", "dovelle", "standard")
	brain.active = true
	brain.state = state
	brain.stun_timer = 0.0
	brain.direct_chase_visible = sees
	return brain


func run(_host: Node) -> int:
	var runner := Vector2(20.5, 20.5)
	var views := {}
	var levels := {}
	# 1. a hunter on this floor she can see, close by: a chase
	var seen := FakeView.new()
	seen.brain = _brain(runner + Vector2(5.0, 0.0), HunterBrain.State.CHASE, true)
	views["seen"] = seen
	levels["seen"] = -1
	_expect(CHASE_CUE.pursued_on_floor(views, levels, -1, runner), "a chase on this floor that she can see did not count")
	# 2. the same hunter one floor below, directly under the runner in plan view: not this floor's chase
	var below := FakeView.new()
	below.brain = _brain(runner + Vector2(0.5, 0.0), HunterBrain.State.CHASE, true)
	views.clear()
	levels.clear()
	views["below"] = below
	levels["below"] = -2
	_expect(not CHASE_CUE.pursued_on_floor(views, levels, -1, runner),
		"a hunter one floor down, directly under the runner, counted as a chase on the runner's floor")
	_expect(CHASE_CUE.pursued_on_floor(views, levels, -2, runner) == below.brain.pursuit_cue(runner),
		"a hunter on her own floor disagreed with her brain's pursuit cue")
	# 3. this floor, still in CHASE but far off after the chase, no sight of the runner: not a chase
	var lost := FakeView.new()
	lost.brain = _brain(runner + Vector2(40.0, 0.0), HunterBrain.State.CHASE, false)
	views.clear()
	levels.clear()
	views["lost"] = lost
	levels["lost"] = -1
	_expect(not CHASE_CUE.pursued_on_floor(views, levels, -1, runner),
		"a hunter 40 cells off, out of sight after the chase, counted as a chase")
	# 4. not chasing at all, or stunned: not a chase
	var idle := FakeView.new()
	idle.brain = _brain(runner + Vector2(2.0, 0.0), HunterBrain.State.INVESTIGATE, false)
	views.clear()
	levels.clear()
	views["idle"] = idle
	levels["idle"] = -1
	_expect(not CHASE_CUE.pursued_on_floor(views, levels, -1, runner), "an investigating hunter counted as a chase")
	# 5. a hunter with no recorded level is not on any floor
	views.clear()
	levels.clear()
	views["unplaced"] = seen
	_expect(not CHASE_CUE.pursued_on_floor(views, levels, -1, runner), "an unplaced hunter counted on the runner's floor")
	if _failures == 0:
		print("  chase_cue  the chase cue counts only hunters on the runner's floor, and only while they are chasing in range or sight")
	return _failures
