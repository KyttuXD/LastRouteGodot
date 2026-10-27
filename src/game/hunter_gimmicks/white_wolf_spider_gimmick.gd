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
## The black variant (BlackWolfSpiderGimmick, below this class's file) subclasses it with harsher numbers.

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

## Per-variant tuning (the black variant overrides these in its _init; the consts above are the white defaults).
var alert_radius := ALERT_RADIUS
var bark_seconds := BARK_SECONDS
var hunt_seconds := HUNT_SECONDS
var cooldown_seconds := COOLDOWN_SECONDS
var hunt_speed_scale := HUNT_SPEED_SCALE
var retreat_speed_scale := RETREAT_SPEED_SCALE
## Seconds of flashlight beam on it that drive it off (0 = the moment it is alerted); INF = it ignores the light.
var flash_hold := 0.0
## Which cue announces it ("bark" or "hiss"; the clip is always `bark`).
var tell := "bark"

## Set when the two are a pair (SecretCreatures.link_admin_pair links them): shared rest and recall, see SpiderPack.
var pack: SpiderPack = null
var rest_scale := 1.0

var phase: Phase = Phase.LURK
var bark_seq := 0
var lair := Vector2.ZERO
var has_lair := false

var _timer := 0.0
var _beam_time := 0.0
var _cooldown := 0.0
var _sense_left := 0.0
var _spawn_barks := false
var _spawn_bark_delay := 0.0
var _delay_left := 0.0
var _delay_target := Vector2.ZERO
var _seen_recall := 0


## A spawner may start it already marking its runner (set right after creating the brain). `delay` staggers the tell
## of the second creature of a pair (the first barks at once, the other follows `delay` seconds later).
func start_with_bark(delay: float = 0.0) -> void:
	_spawn_barks = true
	_spawn_bark_delay = delay


## Per-difficulty multipliers (SecretCreatures.DIFFICULTY knobs): notice = sight range, chase = chase speed, rest = rest time, alert = alert radius.
func apply_knobs(brain: HunterBrain, knobs: Dictionary) -> void:
	brain.sight_range *= float(knobs.get("notice", 1.0))
	brain.chase_speed *= float(knobs.get("chase", 1.0))
	rest_scale = float(knobs.get("rest", 1.0))
	alert_radius *= float(knobs.get("alert", 1.0))


func runs_while_inactive() -> bool:
	return false


func holds_position() -> bool:
	return phase == Phase.LURK or phase == Phase.BARK


func speed_scale(_brain: HunterBrain) -> float:
	match phase:
		Phase.HUNT:
			return hunt_speed_scale
		Phase.RETREAT:
			return retreat_speed_scale
	return 1.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	if not has_lair:
		lair = brain.position
		has_lair = true
		if _spawn_barks:
			_spawn_barks = false
			if _spawn_bark_delay > 0.0:
				_delay_left = _spawn_bark_delay
				_delay_target = target.get("position", brain.position)
			else:
				_begin_bark(brain, target.get("position", brain.position))
	if pack != null:
		pack.tick(self, delta)
	if _delay_left > 0.0 and phase == Phase.LURK:
		_delay_left -= delta
		if _delay_left <= 0.0:
			_begin_bark(brain, _delay_target)
	_cooldown = maxf(0.0, _cooldown - delta)
	var target_position: Vector2 = target.get("position", brain.position)
	var exposed: bool = not bool(target.get("hidden", false)) and not bool(target.get("in_safe_zone", false))
	match phase:
		Phase.LURK:
			_sense_left -= delta
			var packed_rest := pack != null and pack.resting()
			if _cooldown <= 0.0 and not packed_rest and _delay_left <= 0.0 and exposed and _sense_left <= 0.0:
				_sense_left = SENSE_EVERY
				if _notices(brain, target, target_position, generator):
					_begin_bark(brain, target_position)
		Phase.BARK:
			_timer -= delta
			_face(brain, target_position)
			if _timer <= 0.0:
				phase = Phase.HUNT
				_timer = hunt_seconds
				brain.state = HunterBrain.State.CHASE
				brain.has_last_known = true
				brain.last_known = target_position
		Phase.HUNT:
			_timer -= delta
			_beam_time = _beam_time + delta if brain.beam_alerted else 0.0
			if pack != null and pack.recall_seq != _seen_recall:
				_seen_recall = pack.recall_seq          # the other one gave up: both go home together
				_begin_retreat(brain, false)
			elif not exposed or brain.winded or _timer <= 0.0 or (_beam_time > flash_hold and flash_hold != INF and brain.beam_alerted):
				_begin_retreat(brain)
			else:
				brain.state = HunterBrain.State.CHASE   # it does not lose a runner it has marked: it follows sound and light
				brain.has_last_known = true
				brain.last_known = target_position
				brain.lost_sight_timer = 0.0
		Phase.RETREAT:
			if brain.position.distance_to(lair) <= LAIR_RADIUS:
				phase = Phase.LURK
				_cooldown = cooldown_seconds * rest_scale
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
	if distance <= alert_radius and generator.has_line_of_sight(brain.position, target_position):
		return true
	return noise > 0.0 and distance <= noise and generator.has_line_of_sight(brain.position, target_position)


func _begin_bark(brain: HunterBrain, target_position: Vector2) -> void:
	phase = Phase.BARK
	_timer = bark_seconds
	bark_seq += 1
	brain.state = HunterBrain.State.IDLE
	_face(brain, target_position)


func _begin_retreat(brain: HunterBrain, call_pack: bool = true) -> void:
	if pack != null and call_pack:
		pack.start_rest(cooldown_seconds * rest_scale)
		pack.recall()
		_seen_recall = pack.recall_seq
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
