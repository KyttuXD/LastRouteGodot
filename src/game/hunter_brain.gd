class_name HunterBrain
extends RefCounted

## Presentation-agnostic hunter simulation, ported from LastRoute's shared
## hunter-ai.js brain (perception, state machine, patrol/chase movement,
## capture trigger) scoped to Dovelle — the zero-gimmick baseline hunter
## (HUNTER_ABILITIES.dovelle = {} in the original: no bespoke behavior at
## all, just the shared rules). Operates entirely in facility_generator.gd's
## grid-cell coordinate space; presentation layers (src/game_3d/
## hunter_view_3d.gd) read `position` each frame and convert to their own
## world units.
##
## Deferred (see MIGRATION.md): multi-hunter separation, lures, temperature/
## power-state sight modifiers, per-hunter gimmicks, difficulty scaling
## (no difficulty selection exists yet, so it's fixed at the Standard 1.0
## multiplier throughout) — all no-ops for a solo Dovelle per the banked
## research, so nothing here is a stub for them, they're simply absent.

enum State { IDLE, WANDER, INVESTIGATE, CHASE, SEARCH }

const ARRIVAL_DISTANCE := 0.65
const WAYPOINT_DISTANCE := 0.18

var position: Vector2
var state: State = State.IDLE
var active := false

var radius := GameConfig.HUNTER_RADIUS
var base_speed := GameConfig.DOVELLE_BASE_SPEED
var chase_speed := GameConfig.DOVELLE_CHASE_SPEED
var chase_progression_scale := GameConfig.DOVELLE_CHASE_PROGRESSION_SCALE
var sight_range := GameConfig.DOVELLE_SIGHT_RANGE
var hearing_scale := GameConfig.DOVELLE_HEARING_SCALE

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

var _path: Array = []
var _path_timer := 0.0
var _has_path_target := false
var _path_target_cell := Vector2i.ZERO

var _rng: SeededRandom


func _init(spawn_position: Vector2, rng_seed_text: String) -> void:
	position = spawn_position
	_rng = SeededRandom.new(rng_seed_text)


## Mirrors applyRelayActivation(): a hunter isn't just "spawned", it starts
## fully inert until the run activates it, then jumps straight to
## investigating wherever the target was standing at that moment.
func activate_at(target_position: Vector2) -> void:
	active = true
	state = State.INVESTIGATE
	has_last_known = true
	last_known = target_position


## target: {"position": Vector2, "hidden": bool, "in_safe_zone": bool,
## "noise": float, "flashlight_on": bool}. Returns true if this frame
## captured the target (pure proximity check, hidden/safe-zone exempt).
func update(delta: float, generator: FacilityGenerator, target: Dictionary, depth: int, relays_collected: int) -> bool:
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

	_update_perception(delta, generator, target_position, target_hidden, target_in_safe_zone, target_noise, target_flashlight_on)
	_update_stamina(delta)
	_update_movement(delta, generator, depth, relays_collected)

	if not target_hidden and not target_in_safe_zone:
		var reach := (GameConfig.PLAYER_RADIUS + radius) * GameConfig.CAPTURE_DISTANCE_SCALE
		if position.distance_to(target_position) < reach:
			return true
	return false


## Stops the hunter dead — cannot chase, grab, or even perceive — for
## `duration` seconds. Used after a broken grip (hunter-ai.js's
## ESCAPE_STUN_DURATION) and after a respawn (RESPAWN_STUN_DURATION).
func apply_stun(duration: float) -> void:
	stun_timer = maxf(stun_timer, duration)
	_path.clear()
	_has_path_target = false


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


## Mirrors respawnAfterCapture()'s hunter reset: back to a calm, unalerted
## idle instead of remembering anything about the run that just ended.
func calm_reset(stun_duration: float) -> void:
	state = State.IDLE
	has_last_known = false
	idle_timer = 0.6 + _rng.next_float() * 1.4
	_path.clear()
	_has_path_target = false
	apply_stun(stun_duration)


func _update_perception(delta: float, generator: FacilityGenerator, target_position: Vector2, target_hidden: bool, target_in_safe_zone: bool, target_noise: float, target_flashlight_on: bool) -> void:
	var direct_distance := position.distance_to(target_position)
	var can_sense := not target_in_safe_zone and not target_hidden

	var sees_target := false
	if can_sense:
		var sight_scale := 1.0 if target_flashlight_on else GameConfig.UNLIT_SIGHT_SCALE
		if direct_distance < sight_range * sight_scale:
			sees_target = generator.has_line_of_sight(position, target_position)

	var hears_target := false
	sense_timer -= delta
	if sense_timer <= 0.0:
		sense_timer = GameConfig.HUNTER_SENSE_INTERVAL
		if can_sense and direct_distance < target_noise * GameConfig.HEARING_OUTER_SCALE * hearing_scale:
			var sound_path := generator.find_path(_cell_of(position), _cell_of(target_position))
			hears_target = sound_path.size() > 0 and sound_path.size() <= int(ceil(target_noise * hearing_scale))

	if sees_target:
		state = State.CHASE
		has_last_known = true
		last_known = target_position
		lost_sight_timer = 0.0
	elif hears_target:
		state = State.INVESTIGATE
		has_last_known = true
		last_known = target_position
	elif state == State.CHASE:
		lost_sight_timer += delta
		if lost_sight_timer > GameConfig.HUNTER_LOST_SIGHT_GRACE:
			state = State.INVESTIGATE


func _update_stamina(delta: float) -> void:
	if state == State.CHASE:
		stamina = maxf(0.0, stamina - GameConfig.HUNTER_STAMINA_CHASE_DRAIN * delta)
		if stamina <= 0.0:
			winded = true
	else:
		stamina = minf(GameConfig.HUNTER_STAMINA_MAX, stamina + GameConfig.HUNTER_STAMINA_REGEN * delta)
		if winded and stamina >= GameConfig.HUNTER_STAMINA_RECOVER:
			winded = false


func _update_movement(delta: float, generator: FacilityGenerator, depth: int, relays_collected: int) -> void:
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


func _handle_arrival(generator: FacilityGenerator) -> void:
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
	return speed


func _pursue(move_target: Vector2, speed: float, delta: float, generator: FacilityGenerator) -> void:
	var target_cell := _cell_of(move_target)
	_path_timer -= delta
	# Chase repaths fast to track a live target; every other moving state
	# (investigate/search/wander) is walking to a fixed point and repaths
	# on the slower wander cadence.
	var repath_interval := GameConfig.HUNTER_REPATH_CHASE if state == State.CHASE else GameConfig.HUNTER_REPATH_WANDER
	if _path_timer <= 0.0 or _path.is_empty() or not _has_path_target or _path_target_cell != target_cell:
		_path = generator.find_path(_cell_of(position), target_cell)
		_path_timer = repath_interval
		_path_target_cell = target_cell
		_has_path_target = true

	var waypoint := move_target
	if not _path.is_empty():
		waypoint = Vector2(_path[0]) + Vector2(0.5, 0.5)
		if position.distance_to(waypoint) <= WAYPOINT_DISTANCE:
			_path.pop_front()
			if not _path.is_empty():
				waypoint = Vector2(_path[0]) + Vector2(0.5, 0.5)

	var to_waypoint := waypoint - position
	var distance := to_waypoint.length()
	if distance > 0.001:
		var travel := minf(speed * delta, distance)
		var direction := to_waypoint / distance
		_move_with_collision(direction.x * travel, direction.y * travel, generator)


func _move_with_collision(dx: float, dy: float, generator: FacilityGenerator) -> void:
	var total := Vector2(dx, dy).length()
	if total <= 0.0:
		return
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


func _pick_wander_target(generator: FacilityGenerator) -> Vector2:
	var safe_zone_room_ids := {}
	for zone in generator.safe_zones:
		safe_zone_room_ids[zone.get("room_id", "")] = true

	var candidates: Array = []
	for room in generator.rooms:
		if safe_zone_room_ids.has(room["id"]):
			continue
		var center: Vector2i = room["center"]
		var open := generator.nearest_open_position(center.x + 0.5, center.y + 0.5, radius)
		if open.is_empty():
			continue
		var candidate_pos := Vector2(open["x"], open["y"])
		if position.distance_to(candidate_pos) > 5.0:
			candidates.append(candidate_pos)

	if candidates.is_empty():
		return Vector2(generator.exit_cell) + Vector2(0.5, 0.5)
	return candidates[_rng.next_index(candidates.size())]


func _pick_search_target(generator: FacilityGenerator) -> Vector2:
	var offsets: Array = [Vector2(3, 0), Vector2(-3, 0), Vector2(0, 3), Vector2(0, -3), Vector2(2, 2), Vector2(-2, 2), Vector2(2, -2), Vector2(-2, -2)]
	for i in range(offsets.size() - 1, 0, -1):
		var swap_index := _rng.next_index(i + 1)
		var tmp = offsets[i]
		offsets[i] = offsets[swap_index]
		offsets[swap_index] = tmp

	for offset in offsets:
		var open := generator.nearest_open_position(last_known.x + offset.x, last_known.y + offset.y, radius)
		if not open.is_empty():
			var candidate := Vector2(open["x"], open["y"])
			if candidate.distance_to(position) > 0.5:
				return candidate
	return last_known


static func _cell_of(pos: Vector2) -> Vector2i:
	return Vector2i(int(floor(pos.x)), int(floor(pos.y)))
