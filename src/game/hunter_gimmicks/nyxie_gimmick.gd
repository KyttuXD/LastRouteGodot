class_name NyxieGimmick
extends HunterGimmick

## Nyxie's darkness stalker (hunterAbilities.nyxie.darknessStalker). Ported
## from nyxie.js's updateDarknessWatch / syncNyxieState.
##
## She is a **special**: always present on the floor but inert, woken by her
## own rule rather than the relay schedule, and hunting alongside whichever
## route hunter was drawn (which is why main_3d.gd holds a collection).
##
## Two wake modes, and the difference matters:
##   - TIMER: the flashlight has been off for NYXIE_TIMER_DELAY seconds. She
##     spawns and chases, and can be **dispelled** by aiming a live beam at
##     her within NYXIE_DESPAWN_RANGE — which resets the darkness clock.
##   - EMPTY: the lamp has been dead for NYXIE_EMPTY_DELAY seconds. She is
##     already on top of you: the capture is inescapable, skipping the escape
##     struggle entirely (the original calls triggerGameOver directly).
##
## Any light resets the darkness clock, so simply keeping the lamp alive is
## the whole counterplay for the timer mode.

enum Wake { NONE, TIMER, EMPTY }

var wake_mode: Wake = Wake.NONE

var _darkness_elapsed := 0.0
var _empty_elapsed := 0.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator: FacilityGenerator) -> void:
	var lamp_charge: float = target.get("lamp_charge", 100.0)
	var flashlight_on: bool = target.get("flashlight_on", false)
	var lamp_lit := flashlight_on and lamp_charge > 0.0
	var target_position: Vector2 = target["position"]

	if lamp_lit:
		_darkness_elapsed = 0.0
		_empty_elapsed = 0.0
	else:
		_darkness_elapsed += delta
		_empty_elapsed = _empty_elapsed + delta if lamp_charge <= 0.0 else 0.0

	if wake_mode == Wake.NONE:
		if _empty_elapsed >= GameConfig.NYXIE_EMPTY_DELAY:
			wake_mode = Wake.EMPTY
		elif _darkness_elapsed >= GameConfig.NYXIE_TIMER_DELAY:
			wake_mode = Wake.TIMER

	match wake_mode:
		Wake.NONE:
			# Fully inert until woken — not merely calm, but not hunting at all.
			brain.active = false
			brain.state = HunterBrain.State.IDLE
			return
		Wake.EMPTY:
			# She was already right on top of you: manifest at the target so the
			# capture check lands this frame rather than after a walk.
			brain.active = true
			brain.position = target_position
		Wake.TIMER:
			if not brain.active:
				brain.active = true
				brain.position = _spawn_position(target_position, generator)
			elif _dispelled_by_beam(brain, target, generator):
				wake_mode = Wake.NONE
				brain.active = false
				brain.state = HunterBrain.State.IDLE
				_darkness_elapsed = 0.0
				return

	# Darkness is exactly where she hunts best: she tracks through it rather
	# than relying on the shared sight/hearing pass (her hearing scale is 0).
	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = target_position
	brain.lost_sight_timer = 0.0


## Only the dead-lamp wake is inescapable; a timer wake is a normal grab that
## still gets the escape struggle.
func capture_is_inescapable() -> bool:
	return wake_mode == Wake.EMPTY


## A live beam aimed at her, within range, breaks a timer wake.
func _dispelled_by_beam(brain: HunterBrain, target: Dictionary, generator: FacilityGenerator) -> bool:
	if not target.get("flashlight_on", false) or float(target.get("lamp_charge", 0.0)) <= 0.0:
		return false
	var facing: Vector2 = target.get("facing", Vector2.ZERO)
	return brain.beam_reaches(
		target["position"], facing, brain.position,
		GameConfig.NYXIE_DESPAWN_RANGE, GameConfig.NYXIE_DISPEL_HALF_ANGLE, generator
	)


## Mirrors pickSummonSpawn: a reachable spot roughly spawnDistance away, so she
## arrives from somewhere rather than appearing in your face.
func _spawn_position(target_position: Vector2, generator: FacilityGenerator) -> Vector2:
	var best := target_position
	var best_error := INF
	for cell in generator.floor_cells():
		var candidate := Vector2(cell) + Vector2(0.5, 0.5)
		var error: float = absf(candidate.distance_to(target_position) - GameConfig.NYXIE_SPAWN_DISTANCE)
		if error < best_error:
			best_error = error
			best = candidate
	return best


## She wakes herself, so she must keep evaluating while inert.
func runs_while_inactive() -> bool:
	return true
