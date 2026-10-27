class_name WhiteWolfSpiderGimmick
extends HunterGimmick

## The City's secret creature (SecretCreatures.WHITE_WOLF_SPIDER): a fast ambusher. It lurks motionless at its lair,
## barks ONCE to mark a runner it has seen or heard (the telegraph), bursts after them for a limited time, then
## gives up and goes home. It is survivable on purpose: the bark gives a head start, the burst is limited by its own
## stamina, a shelter ends the chase, and a flashlight beam held on it for a moment (brain.beam_alerted) drives it off.
##
##   LURK -> BARK (1.25 s, holds, bark clip + cue) -> HUNT (<= HUNT_SECONDS) -> RETREAT (to the lair) -> LURK (cooldown)
##
## Host-simulated like every hunter; guests only need `phase` and `bark_seq` (network_state) to play the bark.

enum Phase { LURK, BARK, HUNT, RETREAT }

## Cells. A runner this close that the creature can see (or any runner it hears inside HEAR_RADIUS_SCALE) is marked.
const ALERT_RADIUS := 15.0
const HEAR_RADIUS_SCALE := 1.0
const BARK_SECONDS := 1.25
const HUNT_SECONDS := 7.0
## After a retreat it ignores runners for this long (so a shelter dash is never an endless loop).
const COOLDOWN_SECONDS := 30.0
const HUNT_SPEED_SCALE := 1.0
const RETREAT_SPEED_SCALE := 3.2
const LAIR_RADIUS := 1.8
const SENSE_EVERY := 0.2

var phase: Phase = Phase.LURK
var bark_seq := 0
var lair := Vector2.ZERO
var has_lair := false

var _timer := 0.0
var _cooldown := 0.0
var _sense_left := 0.0
var _spawn_barks := false


## City secrets spawn it already marking its runner (CitySecrets sets this right after creating the brain).
func start_with_bark() -> void:
	_spawn_barks = true


func runs_while_inactive() -> bool:
	return false


func holds_position() -> bool:
	return phase == Phase.LURK or phase == Phase.BARK


func speed_scale(_brain: HunterBrain) -> float:
	match phase:
		Phase.HUNT:
			return HUNT_SPEED_SCALE
		Phase.RETREAT:
			return RETREAT_SPEED_SCALE
	return 1.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	if not has_lair:
		lair = brain.position
		has_lair = true
		if _spawn_barks:
			_spawn_barks = false
			_begin_bark(brain, target.get("position", brain.position))
	_cooldown = maxf(0.0, _cooldown - delta)
	var target_position: Vector2 = target.get("position", brain.position)
	var exposed: bool = not bool(target.get("hidden", false)) and not bool(target.get("in_safe_zone", false))
	match phase:
		Phase.LURK:
			_sense_left -= delta
			if _cooldown <= 0.0 and exposed and _sense_left <= 0.0:
				_sense_left = SENSE_EVERY
				if _notices(brain, target, target_position, generator):
					_begin_bark(brain, target_position)
		Phase.BARK:
			_timer -= delta
			_face(brain, target_position)
			if _timer <= 0.0:
				phase = Phase.HUNT
				_timer = HUNT_SECONDS
				brain.state = HunterBrain.State.CHASE
				brain.has_last_known = true
				brain.last_known = target_position
		Phase.HUNT:
			_timer -= delta
			if not exposed or brain.winded or _timer <= 0.0 or brain.beam_alerted:
				_begin_retreat(brain)
			else:
				brain.state = HunterBrain.State.CHASE   # it does not lose a runner it has marked: it follows sound and light
				brain.has_last_known = true
				brain.last_known = target_position
				brain.lost_sight_timer = 0.0
		Phase.RETREAT:
			if brain.position.distance_to(lair) <= LAIR_RADIUS:
				phase = Phase.LURK
				_cooldown = COOLDOWN_SECONDS
				brain.state = HunterBrain.State.IDLE
				brain.has_wander_target = false
			else:
				brain.state = HunterBrain.State.WANDER
				brain.has_wander_target = true
				brain.wander_target = lair


## Perception runs between the two hooks and may flip the state to CHASE (it sees the runner): a lurking or barking
## creature stands its ground instead, and a retreating one keeps walking home.
func after_perception(brain: HunterBrain, _delta: float, _target: Dictionary, _generator) -> void:
	match phase:
		Phase.LURK, Phase.BARK:
			brain.state = HunterBrain.State.IDLE
			brain.idle_timer = 5.0          # never tick over into WANDER (no wander-target search while it stands guard)
			brain.direct_chase_visible = false
		Phase.RETREAT:
			brain.state = HunterBrain.State.WANDER
			brain.has_wander_target = true
			brain.wander_target = lair
			brain.direct_chase_visible = false


func _notices(brain: HunterBrain, target: Dictionary, target_position: Vector2, generator) -> bool:
	var distance := brain.position.distance_to(target_position)
	var noise := float(target.get("noise", 0.0)) * brain.hearing_scale * HEAR_RADIUS_SCALE
	if distance <= ALERT_RADIUS and generator.has_line_of_sight(brain.position, target_position):
		return true
	return noise > 0.0 and distance <= noise and generator.has_line_of_sight(brain.position, target_position)


func _begin_bark(brain: HunterBrain, target_position: Vector2) -> void:
	phase = Phase.BARK
	_timer = BARK_SECONDS
	bark_seq += 1
	brain.state = HunterBrain.State.IDLE
	_face(brain, target_position)


func _begin_retreat(brain: HunterBrain) -> void:
	phase = Phase.RETREAT
	brain.state = HunterBrain.State.WANDER
	brain.has_wander_target = true
	brain.wander_target = lair
	brain.direct_chase_visible = false


func _face(brain: HunterBrain, at: Vector2) -> void:
	var look := at - brain.position
	if look.length_squared() > 0.0001:
		brain.facing = look.normalized()


func network_state() -> Dictionary:
	return {"phase": int(phase), "bark_seq": bark_seq}


func apply_network_state(state: Dictionary) -> void:
	phase = clampi(int(state.get("phase", int(phase))), int(Phase.LURK), int(Phase.RETREAT)) as Phase
	bark_seq = int(state.get("bark_seq", bark_seq))
