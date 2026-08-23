class_name HunterBrain
extends RefCounted

## Presentation-agnostic hunter simulation, ported from LastRoute's shared
## hunter-ai.js brain (perception, state machine, patrol/chase movement,
## capture trigger). The shared rules here are exactly Dovelle's zero-gimmick
## baseline (HUNTER_ABILITIES.dovelle = {} in the original: no bespoke
## behavior at all) — any hunter whose gimmick only changes tuning numbers,
## not behavior, works with zero changes here (see HunterRoster). A hunter
## whose gimmick changes actual behavior gets a HunterGimmick instead (see
## src/game/hunter_gimmicks/ — one script per hunter, mirroring the
## original's one-file-per-hunter layout); `gimmick` is null for every
## tuning-only hunter, so its hooks below are simply skipped. Operates
## entirely in the shared grid-cell navigation contract. Fixed floors provide
## it through FacilityGenerator; endless floors provide it through
## StreamedHunterNavigation. Presentation layers
## (src/game_3d/hunter_view_3d.gd) read `position` each frame and convert to
## their own world units.
##
## Deferred (see MIGRATION.md): multi-hunter separation, lures, and room-power
## sight modifiers. Relaxed/Standard/Hard difficulty scaling is applied here;
## Nightmare and its larger active lineup remain intentionally unavailable.

enum State { IDLE, WANDER, INVESTIGATE, CHASE, SEARCH }

const ARRIVAL_DISTANCE := 0.65
const WAYPOINT_DISTANCE := 0.18
const PATH_LOOKAHEAD_NODES := 4

var position: Vector2
var state: State = State.IDLE
var active := false
var hunter_id: String
var gimmick: HunterGimmick
var difficulty_id := "standard"
var difficulty_profile: Dictionary = GameConfig.DIFFICULTY_PROFILES["standard"]

## Changes a gimmick made to the shared world, for the scene above to drain.
##
## A hunter who takes a battery off the floor -- Ysolde -- has changed something
## every player can see, and the brain is presentation-agnostic and knows
## nothing about peers. So it records what happened and main_3d applies and
## broadcasts it, the same way it already drains _hunter_report. Same event
## shape a player's own pickup uses, because it IS the same event.
var world_events: Array = []
## Unit vector she last actually moved along — the equivalent of the
## original's per-hunter facingX/facingY, which its beam checks read. Only
## updated by real movement, so it persists while she stands still.
var facing := Vector2(0, 1)

var radius := GameConfig.HUNTER_RADIUS
var base_speed: float
var chase_speed: float
var chase_progression_scale: float
var sight_range: float
var hearing_scale: float

var stamina := GameConfig.HUNTER_STAMINA_MAX
var winded := false

var stun_timer := 0.0
var idle_timer := 0.0
var search_timer := 0.0
var search_visits := 0
var lost_sight_timer := 0.0
var sense_timer := 0.0

var has_wander_target := false
var wander_target := Vector2.ZERO
var has_search_target := false
var search_target := Vector2.ZERO
var has_last_known := false
var last_known := Vector2.ZERO
## True only while the latest perception sample (or a hunter-specific visual
## ability such as Kathy's cone) has an unobstructed live runner. Direct chase
## steering uses this to avoid both A* latency and unnecessary path searches.
var direct_chase_visible := false
var _ability_direct_sight := false

var _path: Array = []
var _path_timer := 0.0
var _has_path_target := false
var _path_target_cell := Vector2i.ZERO

var _rng: SeededRandom


func _init(spawn_position: Vector2, rng_seed_text: String,
		id: String = HunterRoster.DEFAULT_ID, route_difficulty: String = "standard") -> void:
	position = spawn_position
	_rng = SeededRandom.new(rng_seed_text)
	hunter_id = id
	difficulty_id = route_difficulty if GameConfig.DIFFICULTY_PROFILES.has(
		route_difficulty) else "standard"
	difficulty_profile = GameConfig.difficulty_profile(difficulty_id)
	gimmick = HunterGimmick.for_id(id)
	var identity := HunterRoster.get_identity(id)
	base_speed = identity["base_speed"]
	chase_speed = identity["chase_speed"]
	chase_progression_scale = identity["chase_progression_scale"]
	sight_range = identity["sight_range"]
	hearing_scale = identity["hearing_scale"]


## Mirrors applyRelayActivation(): a hunter isn't just "spawned", it starts
## fully inert until the run activates it, then jumps straight to
## investigating wherever the target was standing at that moment.
func activate_at(target_position: Vector2) -> void:
	active = true
	state = State.INVESTIGATE
	has_last_known = true
	last_known = target_position
	direct_chase_visible = false


## target: {"position": Vector2, "hidden": bool, "in_safe_zone": bool,
## "noise": float, "flashlight_on": bool}. Returns true if this frame
## captured the target (pure proximity check, hidden/safe-zone exempt).
func update(delta: float, generator, target: Dictionary, depth: int, relays_collected: int) -> bool:
	# A rule-summoned hunter decides her own activation inside her gimmick, so
	# it has to run before the inactive check that would otherwise stop it.
	var self_summoning := gimmick != null and gimmick.runs_while_inactive()
	if self_summoning:
		gimmick.before_perception(self, delta, target, generator)

	if not active:
		return false
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		return false

	var target_position: Vector2 = target["position"]
	var target_hidden: bool = target.get("hidden", false)
	var target_in_safe_zone: bool = target.get("in_safe_zone", false)
	var target_noise: float = target.get("noise", 0.0)
	var target_flashlight_on: bool = target.get("flashlight_on", true)
	_ability_direct_sight = false

	if gimmick and not self_summoning:
		gimmick.before_perception(self, delta, target, generator)

	_update_beam_attention(delta, generator, target)
	_update_perception(delta, generator, target_position, target_hidden, target_in_safe_zone, target_noise, target_flashlight_on)
	if gimmick:
		gimmick.after_perception(self, delta, target, generator)
	_update_stamina(delta)
	_update_movement(delta, generator, depth, relays_collected)

	# Account/room-proof authorization belongs to the owning gameplay scene,
	# not this presentation-agnostic brain. Trusting a replicated `god_mode`
	# boolean here let an ordinary peer suppress capture whenever the host itself
	# happened to be an admin. The authoritative capture boundary rechecks the
	# signed player permission before applying any result.
	if not target_hidden and not target_in_safe_zone \
			and not (gimmick and gimmick.immune_to_capture()):
		var reach := (GameConfig.PLAYER_RADIUS + radius) \
			* GameConfig.CAPTURE_DISTANCE_SCALE \
			* float(difficulty_profile["capture_distance"])
		if position.distance_to(target_position) < reach:
			return true
	return false


## Keep an active hunter's ordinary idle/wander simulation alive when every
## runner has opted out of targeting. Clearing chase memory is important: the
## old no-target path skipped update() entirely and left hunters frozen in the
## last pose/state they had before the target disappeared.
func update_without_target(delta: float, generator,
		depth: int, relays_collected: int) -> void:
	if not active:
		return
	if stun_timer > 0.0:
		stun_timer = maxf(0.0, stun_timer - delta)
		return
	if state == State.CHASE or state == State.INVESTIGATE or state == State.SEARCH:
		state = State.IDLE
		has_last_known = false
		has_search_target = false
		lost_sight_timer = 0.0
		idle_timer = 0.35 + _rng.next_float() * 0.65
		_path.clear()
		_has_path_target = false
	direct_chase_visible = false
	_ability_direct_sight = false
	_update_stamina(delta)
	_update_movement(delta, generator, depth, relays_collected)


## Stops the hunter dead — cannot chase, grab, or even perceive — for
## `duration` seconds. Used after a broken grip (hunter-ai.js's
## ESCAPE_STUN_DURATION) and after a respawn (RESPAWN_STUN_DURATION).
func apply_stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false


## Mirrors breakFree()'s hunter-side effect: knocked into a short search at
## the target's post-knockback position rather than an immediate re-chase.
func enter_search_from(position_hint: Vector2, duration: float) -> void:
	state = State.SEARCH
	has_last_known = true
	last_known = position_hint
	search_timer = duration
	search_visits = 0
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false


## A floor transition is part of an existing pursuit, not a loss-of-contact
## event. Preserve the runner sample while the presentation walks the physical
## stair ramp, then resume routed chase on the destination floor.
func continue_chase_from(position_hint: Vector2) -> void:
	state = State.CHASE
	has_last_known = true
	last_known = position_hint
	lost_sight_timer = 0.0
	search_timer = 0.0
	has_search_target = false
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false


## Presentation-only look direction. A hunter may receive a runner snapshot for
## target selection, but the model must not stare at that runner unless the
## brain is actually investigating, searching, or chasing. This keeps wander
## behavior from looking omniscient (especially while an admin has NO TARGET
## enabled) and gives the head scanner control during ordinary patrols.
func presentation_look_target() -> Variant:
	if not active or stun_timer > 0.0:
		return null
	match state:
		State.CHASE, State.INVESTIGATE:
			return last_known if has_last_known else null
		State.SEARCH:
			return search_target if has_search_target else (last_known if has_last_known else null)
		_:
			return null


## Mirrors respawnAfterCapture()'s hunter reset: back to a calm, unalerted
## idle instead of remembering anything about the run that just ended.
func calm_reset(stun_duration: float) -> void:
	state = State.IDLE
	has_last_known = false
	idle_timer = 0.6 + _rng.next_float() * 1.4
	_path.clear()
	_has_path_target = false
	direct_chase_visible = false
	apply_stun(stun_duration)


func _update_perception(delta: float, generator, target_position: Vector2, target_hidden: bool, target_in_safe_zone: bool, target_noise: float, target_flashlight_on: bool) -> void:
	var direct_distance := position.distance_to(target_position)
	var can_sense := not target_in_safe_zone and not target_hidden
	if not can_sense:
		direct_chase_visible = false
	sense_timer -= delta
	if sense_timer > 0.0:
		# Keep following the most recent runner sample between sensory probes.
		# Collision/path movement still runs at the simulation tick; only the
		# expensive LOS and sound-path evidence is sampled at its designed rate.
		if state == State.CHASE and can_sense:
			last_known = target_position
		return
	sense_timer = GameConfig.HUNTER_SENSE_INTERVAL

	var sees_target := false
	var perception_line_clear := false
	var difficulty_sight := float(difficulty_profile["hunter_sight"])
	var difficulty_hearing := float(difficulty_profile["hunter_hearing"])
	var sight_limit := sight_range * GameConfig.UNLIT_SIGHT_SCALE * difficulty_sight
	if target_flashlight_on:
		sight_limit = maxf(GameConfig.FLASHLIGHT_SIGHT_MIN,
			sight_range * GameConfig.FLASHLIGHT_SIGHT_SCALE) * difficulty_sight
	var hearing_limit := target_noise * hearing_scale * difficulty_hearing
	if can_sense:
		# One throttled grid ray serves exposed sight and open-air hearing. Walls
		# stop visual detection; obstructed sound falls back to path distance.
		var ray_range := maxf(sight_limit,
			hearing_limit * GameConfig.HEARING_OPEN_AIR_SCALE)
		if direct_distance < ray_range:
			perception_line_clear = generator.has_line_of_sight(position, target_position)
		sees_target = direct_distance < sight_limit and perception_line_clear

	var hears_target := false
	# Sight already wins below. Avoid a second full navigation search merely
	# to prove the hunter can also hear a runner she is currently looking at.
	# With several active hunters this was the largest relay-on CPU spike.
	if not sees_target and can_sense:
		if perception_line_clear and direct_distance \
				<= hearing_limit * GameConfig.HEARING_OPEN_AIR_SCALE:
			hears_target = true
		elif direct_distance < hearing_limit * GameConfig.HEARING_OUTER_SCALE:
			var sound_path: Array = generator.find_path(_cell_of(position),
				_cell_of(target_position))
			hears_target = sound_path.size() > 0 \
				and sound_path.size() <= int(ceil(hearing_limit))
			# Reuse the one hearing route as this frame's chase route. Without
			# this, every hunter performed a second A* immediately after hearing
			# the runner turn a corner.
			if hears_target and state == State.CHASE:
				_path = sound_path
				_path_timer = GameConfig.HUNTER_REPATH_CHASE
				_path_target_cell = _cell_of(target_position)
				_has_path_target = true

	if sees_target:
		state = State.CHASE
		has_last_known = true
		last_known = target_position
		lost_sight_timer = 0.0
		direct_chase_visible = true
	elif hears_target:
		has_last_known = true
		last_known = target_position
		direct_chase_visible = false
		if state == State.CHASE:
			# Breaking visual contact at a corner is not an escape. Movement noise
			# maintains the chase and the sound path leads around the obstruction.
			lost_sight_timer = 0.0
		else:
			state = State.INVESTIGATE
	elif state == State.CHASE:
		direct_chase_visible = _ability_direct_sight
		lost_sight_timer += GameConfig.HUNTER_SENSE_INTERVAL
		if lost_sight_timer > GameConfig.HUNTER_LOST_SIGHT_GRACE:
			state = State.INVESTIGATE
			direct_chase_visible = false
	else:
		direct_chase_visible = false


func _update_stamina(delta: float) -> void:
	if state == State.CHASE:
		stamina = maxf(0.0, stamina - GameConfig.HUNTER_STAMINA_CHASE_DRAIN * delta)
		if stamina <= 0.0:
			winded = true
	else:
		stamina = minf(GameConfig.HUNTER_STAMINA_MAX, stamina + GameConfig.HUNTER_STAMINA_REGEN * delta)
		if winded and stamina >= GameConfig.HUNTER_STAMINA_RECOVER:
			winded = false


func _update_movement(delta: float, generator, depth: int, relays_collected: int) -> void:
	match state:
		State.IDLE:
			idle_timer -= delta
			if idle_timer <= 0.0:
				state = State.WANDER
				wander_target = _pick_wander_target(generator)
				has_wander_target = true
			return
		State.SEARCH:
			search_timer -= delta
			if search_timer <= 0.0:
				state = State.IDLE
				has_last_known = false
				idle_timer = 0.6 + _rng.next_float() * 1.4
				_path.clear()
				_has_path_target = false
				return

	# A gimmick can pin her in place (Mavrine's survey) without freezing the
	# state machine itself — timers above still ran, only movement stops.
	if gimmick and gimmick.holds_position():
		return

	var target_info := _current_move_target()
	if not target_info["has"]:
		return
	var move_target: Vector2 = target_info["pos"]
	var speed := _current_speed(depth, relays_collected)
	_pursue(move_target, speed, delta, generator)
	if position.distance_to(move_target) <= ARRIVAL_DISTANCE:
		_handle_arrival(generator)


func _current_move_target() -> Dictionary:
	match state:
		State.WANDER:
			return {"has": has_wander_target, "pos": wander_target}
		State.CHASE, State.INVESTIGATE:
			return {"has": has_last_known, "pos": last_known}
		State.SEARCH:
			return {"has": has_search_target, "pos": search_target}
		_:
			return {"has": false, "pos": Vector2.ZERO}


func _handle_arrival(generator) -> void:
	match state:
		State.WANDER:
			state = State.IDLE
			idle_timer = 0.7 + _rng.next_float() * 1.6
			has_wander_target = false
		State.CHASE, State.INVESTIGATE:
			state = State.SEARCH
			search_timer = GameConfig.HUNTER_SEARCH_TIME
			search_visits = 0
			search_target = _pick_search_target(generator)
			has_search_target = true
		State.SEARCH:
			search_visits += 1
			search_target = _pick_search_target(generator)
			has_search_target = true


func _current_speed(depth: int, relays_collected: int) -> float:
	var depth_boost := minf(GameConfig.HUNTER_DEPTH_SPEED_BONUS_MAX, (maxi(1, depth) - 1) * GameConfig.HUNTER_DEPTH_SPEED_BONUS_PER_LEVEL)
	var relay_boost := maxf(0.0, float(relays_collected)) * GameConfig.HUNTER_RELAY_SPEED_BONUS
	var progression := relay_boost + depth_boost
	var speed: float
	if state == State.CHASE:
		speed = chase_speed + progression * chase_progression_scale
	else:
		speed = base_speed + progression
	if winded:
		speed *= GameConfig.HUNTER_WINDED_SPEED_SCALE
	if gimmick:
		speed *= gimmick.speed_scale(self)
	return speed * float(difficulty_profile["hunter_speed"])


func _pursue(move_target: Vector2, speed: float, delta: float, generator) -> void:
	var target_cell := _cell_of(move_target)
	_path_timer -= delta
	# A visible runner needs no route search: follow the fresh 30 Hz target
	# sample immediately. Grid collision still rejects a wall that enters the
	# line before the next throttled perception probe.
	if state == State.CHASE and direct_chase_visible:
		_path.clear()
		_has_path_target = false
		var direct_offset := move_target - position
		var direct_distance := direct_offset.length()
		if direct_distance > 0.001:
			var direct_direction := direct_offset / direct_distance
			var direct_travel := minf(speed \
				* GameConfig.HUNTER_VISIBLE_CHASE_SPEED_SCALE * delta,
				direct_distance)
			facing = direct_direction
			_move_with_collision(direct_direction.x * direct_travel,
				direct_direction.y * direct_travel, generator)
		return
	# Chase repaths fast to track a live target; every other moving state
	# (investigate/search/wander) is walking to a fixed point and repaths
	# on the slower wander cadence.
	var repath_interval := GameConfig.HUNTER_REPATH_CHASE if state == State.CHASE else GameConfig.HUNTER_REPATH_WANDER
	# A moving target commonly crosses 5-8 cells per second. Replanning on every
	# crossed cell bypassed HUNTER_REPATH_CHASE entirely and multiplied the BFS
	# cost by every active hunter. Follow the current path until the timer is due,
	# then plan toward the newest target cell.
	if _path_timer <= 0.0 or _path.is_empty() or not _has_path_target:
		_path = generator.find_path(_cell_of(position), target_cell)
		_path_timer = repath_interval
		_path_target_cell = target_cell
		_has_path_target = true
	# An empty route used to fall through to a straight-line move_target below.
	# That made a no-target patrol keep playing its walk into the wall separating
	# it from an unreachable room. Stop and choose another patrol instead; chase
	# and investigate also wait for a valid path rather than pushing into solids.
	if _path.is_empty() and _cell_of(position) != target_cell:
		if state == State.WANDER:
			state = State.IDLE
			has_wander_target = false
			idle_timer = 0.25 + _rng.next_float() * 0.5
			_has_path_target = false
		return

	var waypoint := move_target
	if not _path.is_empty():
		while not _path.is_empty() and position.distance_to(
				Vector2(_path[0]) + Vector2(0.5, 0.5)) <= WAYPOINT_DISTANCE:
			_path.pop_front()
		if not _path.is_empty():
			var waypoint_info := _smoothed_path_waypoint(generator)
			for _step in range(int(waypoint_info.get("consumed", 0))):
				if _path.is_empty():
					break
				_path.pop_front()
			waypoint = waypoint_info.get("point", Vector2(_path[0]) + Vector2(0.5, 0.5))

	var to_waypoint := waypoint - position
	var distance := to_waypoint.length()
	if distance > 0.001:
		var travel := minf(speed * delta, distance)
		var direction := to_waypoint / distance
		facing = direction
		var moved := _move_with_collision(direction.x * travel,
			direction.y * travel, generator)
		if moved <= 0.001 and not _path.is_empty():
			# Tight inside corners can leave the first waypoint just beyond the
			# capsule's current diagonal reach. Force an immediate repath next
			# frame instead of burning the whole chase interval pushing in place.
			_path_timer = 0.0
			if _path.size() > 1:
				_path.pop_front()


func _smoothed_path_waypoint(generator) -> Dictionary:
	if _path.is_empty():
		return {"point": position, "consumed": 0}
	var furthest_index := 0
	var furthest_point := Vector2(_path[0]) + Vector2(0.5, 0.5)
	var lookahead := mini(PATH_LOOKAHEAD_NODES, _path.size())
	for index in range(lookahead):
		var candidate := Vector2(_path[index]) + Vector2(0.5, 0.5)
		if not generator.can_occupy(candidate.x, candidate.y, radius):
			break
		if not generator.has_line_of_sight(position, candidate):
			break
		furthest_index = index
		furthest_point = candidate
	return {"point": furthest_point, "consumed": furthest_index}


func _move_with_collision(dx: float, dy: float, generator) -> float:
	var total := Vector2(dx, dy).length()
	if total <= 0.0:
		return 0.0
	var start := position
	var steps: int = maxi(1, int(ceil(total / GameConfig.MOVEMENT_STEP)))
	var step_dx := dx / steps
	var step_dy := dy / steps
	for i in steps:
		var next_x := position.x + step_dx
		if generator.can_occupy(next_x, position.y, radius):
			position.x = next_x
		var next_y := position.y + step_dy
		if generator.can_occupy(position.x, next_y, radius):
			position.y = next_y
	return position.distance_to(start)


func _pick_wander_target(generator) -> Vector2:
	var safe_zone_room_ids := {}
	for zone in generator.safe_zones:
		safe_zone_room_ids[zone.get("room_id", "")] = true

	var candidates: Array = []
	for room in generator.rooms:
		if safe_zone_room_ids.has(room["id"]):
			continue
		var center: Vector2i = room["center"]
		var open: Dictionary = generator.nearest_open_position(
			center.x + 0.5, center.y + 0.5, radius)
		if open.is_empty():
			continue
		var candidate_pos := Vector2(open["x"], open["y"])
		if position.distance_to(candidate_pos) > 5.0:
			candidates.append(candidate_pos)

	if candidates.is_empty():
		return Vector2(generator.exit_cell) + Vector2(0.5, 0.5)
	return candidates[_rng.next_index(candidates.size())]


func _pick_search_target(generator) -> Vector2:
	var offsets: Array = [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3), Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2)]
	for i in range(offsets.size() - 1, 0, -1):
		var swap_index := _rng.next_index(i + 1)
		var tmp = offsets[i]
		offsets[i] = offsets[swap_index]
		offsets[swap_index] = tmp

	for offset in offsets:
		var open: Dictionary = generator.nearest_open_position(
			last_known.x + offset.x, last_known.y + offset.y, radius)
		if not open.is_empty():
			var candidate := Vector2(open["x"], open["y"])
			if candidate.distance_to(position) > 0.5:
				return candidate
	return last_known


## Gimmicks draw from the brain's own seeded stream rather than a global RNG,
## mirroring the original's shared `aiRandom` — so a replayed run reproduces
## gimmick decisions (wire placement, mark cells) as well as movement.
func next_random_float() -> float:
	return _rng.next_float()


func next_random_index(exclusive_max: int) -> int:
	return _rng.next_index(exclusive_max)


## Direct port of hunter-ai.js's beamIlluminates(): is `target` inside a cone
## of half-angle `half_angle` radians, centred on `from_facing`, within
## `range`, and in line of sight? Shared because several hunters' gimmicks are
## cone checks that differ only in whose facing and which constants they use
## (Kathy's search beam today; Aki/Ferryn/Ilyra read the *player's* beam the
## same way once player facing is threaded through — see HUNTER_ROSTER.md).
## How long the PLAYER's beam has been held on this hunter, and the two signals
## gimmicks read off it. Ported from hunter-ai.js's updateHunterBeamAttention.
##
## The distinction the original draws, and the reason this is not just "is she
## lit": `beam_alerted` is true for every frame the beam stays on target once
## the dwell completes, while `flash_triggered` is only the RISING EDGE of that
## — one deliberate flash, not a continuous stream. A gimmick that fired on the
## former when it meant the latter would retrigger sixty times a second.
##
## This is HUNTER_ROSTER.md's "directional flashlight beam-aim" unlock. It sat
## deferred because it unblocked nothing on its own: Kathy reads her own facing,
## and everyone who needs the player's was also blocked on a second system.
## Aki's is now the first gimmick that reads it.
var beam_attention := 0.0
var beam_alerted := false
var flash_triggered := false


func _update_beam_attention(delta: float, generator, target: Dictionary) -> void:
	var facing: Vector2 = target.get("facing", Vector2.ZERO)
	var lit := bool(target.get("flashlight_on", false)) and beam_reaches(
		target["position"], facing, position,
		GameConfig.BEAM_ATTENTION_RANGE, GameConfig.BEAM_ATTENTION_HALF_ANGLE, generator)

	var previous := beam_attention
	if lit:
		beam_attention = minf(GameConfig.BEAM_ATTENTION_TIME, previous + delta)
	else:
		beam_attention = maxf(0.0, previous - delta * GameConfig.BEAM_ATTENTION_DECAY)
	beam_alerted = lit and beam_attention >= GameConfig.BEAM_ATTENTION_TIME
	flash_triggered = beam_alerted and previous < GameConfig.BEAM_ATTENTION_TIME


func beam_reaches(from: Vector2, from_facing: Vector2, target: Vector2, range_limit: float, half_angle: float, generator) -> bool:
	var offset := target - from
	var distance := offset.length()
	if distance <= 0.001 or distance > range_limit:
		return false
	if from_facing.length() <= 0.001:
		return false
	if offset.normalized().dot(from_facing.normalized()) < cos(half_angle):
		return false
	return generator.has_line_of_sight(from, target)


static func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))
