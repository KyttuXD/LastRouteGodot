extends RefCounted

## Mutual light sight (docs/LIGHT_SIGHT.md): exposure falls off with distance, walls block lamps, a dark runner is seen close
## and a lit one far, and a hunter standing in light (exposure >= VISIBLE_EXPOSURE) sees the runner at her full sight range
## even with the runner's flashlight off; with the rule off nothing changes.
##
##   godot --headless --path . res://scenes/validate.tscn -- light_sight

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var lamp := [Vector3(0, 2.5, 0), Color.WHITE, 1.0, 0]
	var lamps := {Vector3i.ZERO: [lamp]}
	var near := float(LightField.exposure_at(Vector3(0, 1.2, 1), lamps)["value"])
	var mid := float(LightField.exposure_at(Vector3(0, 1.2, 4), lamps)["value"])
	var far := float(LightField.exposure_at(Vector3(0, 1.2, 40), lamps)["value"])
	_expect(near > mid and mid > far, "exposure does not fall off with distance (%.2f, %.2f, %.2f)" % [near, mid, far])
	_expect(is_equal_approx(far, LightField.AMBIENT), "beyond reach only the ambient should remain (%.3f)" % far)
	_expect(near >= LightField.VISIBLE_EXPOSURE, "right under a lamp is not visible (%.2f)" % near)
	var blocked := float(LightField.exposure_at(Vector3(0, 1.2, 1), lamps, func(_a: Vector2, _b: Vector2) -> bool: return false)["value"])
	_expect(is_equal_approx(blocked, LightField.AMBIENT), "a wall did not block the lamp (%.2f)" % blocked)
	var flickering := {Vector3i.ZERO: [[Vector3(0, 2.5, 0), Color.WHITE, 0.0, 1]]}
	_expect(float(LightField.exposure_at(Vector3(0, 1.2, 1), flickering)["value"]) < LightField.VISIBLE_EXPOSURE, "a lamp at zero energy (flicker off) still lights")

	var brain := HunterBrain.new(Vector2(5.5, 5.5), "LIGHT", "aki", "standard")
	brain.activate_at(Vector2(5.5, 5.5))
	var target := Vector2(10.5, 5.5)
	var diff := float(brain.difficulty_profile["hunter_sight"])
	# rule off / unknown: the old unlit range
	brain.self_exposure = -1.0
	brain.target_exposure = -1.0
	var legacy := brain.sight_limit_for(target, false)
	_expect(is_equal_approx(legacy, brain.sight_range * GameConfig.UNLIT_SIGHT_SCALE * diff), "without exposure data the unlit range changed")
	# dark runner, dark hunter: close range only
	brain.self_exposure = 0.0
	brain.target_exposure = 0.0
	var dark := brain.sight_limit_for(target, false)
	_expect(dark < legacy, "a runner in pitch dark is not harder to see (%.2f vs %.2f)" % [dark, legacy])
	# runner in a lamp pool, flashlight off: farther
	brain.target_exposure = 1.0
	var lit := brain.sight_limit_for(target, false)
	_expect(lit > legacy, "a runner standing in light is not easier to see (%.2f)" % lit)
	# mutual: the runner (flashlight off, in shadow) can see a lit hunter -> the hunter sees her at full range
	brain.target_exposure = 0.0
	brain.self_exposure = LightField.VISIBLE_EXPOSURE + .05
	var mutual := brain.sight_limit_for(target, false)
	_expect(mutual >= brain.sight_range * diff - .001, "a lit hunter does not see the runner at her full range (%.2f)" % mutual)
	# the same positions with the lamp off: only close
	brain.self_exposure = LightField.AMBIENT
	_expect(brain.sight_limit_for(target, false) < mutual, "with the lamp off the hunter still sees as far")
	# admin off: back to the old rule
	LightField.enabled = false
	brain.self_exposure = 1.0
	brain.target_exposure = 1.0
	_expect(is_equal_approx(brain.sight_limit_for(target, false), legacy), "turning the rule off does not restore the old range")
	LightField.enabled = true
	if _failures == 0:
		print("  light_sight  falloff, wall occlusion, dark %.1f / old %.1f / lit %.1f m, mutual %.1f m, rule switch" % [dark, legacy, lit, mutual])
	return _failures
