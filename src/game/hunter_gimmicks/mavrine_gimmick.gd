class_name MavrineGimmick
extends HunterGimmick

## Mavrine's lattice mark (hunterAbilities.mavrine.latticeMark). Ported from
## mavrine.js plus the phase machine in hunter-gimmicks.js's
## updateLatticeMark(): she cycles
##   COOLDOWN -> SURVEY (holds position) -> PROJECT (an armed frame somewhere
##   on the floor) -> PING (on a crossing) -> COOLDOWN
## and pursues the frame's position if the target crosses it.
##
## Close pursuit always outranks the remote frame: while she is actually
## chasing, cooldown/survey are held off rather than advancing, so she never
## stops a live chase to go plant a wire.
##
## The candidate search is the original's filter chain, minus the hiding-spot
## exclusion (no hiding spots exist yet — the filter would be a no-op over an
## empty list rather than a behaviour change).

enum Phase { COOLDOWN, SURVEY, PROJECT, PING }

var phase: Phase = Phase.COOLDOWN
var has_mark := false
var mark := Vector2.ZERO

var _timer := GameConfig.MAVRINE_COOLDOWN_DURATION
var _last_mark_cell := Vector2i(-1, -1)


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator: FacilityGenerator) -> void:
	# An armed frame stays live, but a direct chase is never interrupted to
	# replace it (hunter-gimmicks.js's first branch).
	if brain.state == HunterBrain.State.CHASE and phase in [Phase.COOLDOWN, Phase.SURVEY]:
		_timer = maxf(_timer, GameConfig.MAVRINE_SURVEY_DELAY * 0.35)
		return

	_timer -= delta
	if _timer <= 0.0:
		match phase:
			Phase.COOLDOWN:
				_enter(Phase.SURVEY)
			Phase.SURVEY:
				has_mark = false
				_place_mark(brain, generator)
				_enter(Phase.PROJECT)
			Phase.PROJECT, Phase.PING:
				has_mark = false
				_enter(Phase.COOLDOWN)

	if phase != Phase.PROJECT or not has_mark:
		return
	if target.get("hidden", false) or target.get("in_safe_zone", false):
		return
	var target_position: Vector2 = target["position"]
	if target_position.distance_to(mark) > GameConfig.MAVRINE_MARK_TRIGGER_RADIUS:
		return

	# Crossed the frame: investigate the frame's own position, not the
	# target's — she knows where the trip happened, not where they went.
	_enter(Phase.PING)
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = mark


## SURVEY freezes her in place, matching the original's movementScale 0 /
## holdPosition modifier for that phase.
func holds_position() -> bool:
	return phase == Phase.SURVEY


func _enter(next_phase: Phase) -> void:
	phase = next_phase
	match next_phase:
		Phase.COOLDOWN:
			_timer = GameConfig.MAVRINE_COOLDOWN_DURATION
		Phase.SURVEY:
			_timer = GameConfig.MAVRINE_SURVEY_DURATION
		Phase.PROJECT:
			_timer = GameConfig.MAVRINE_PROJECTION_DURATION
		Phase.PING:
			_timer = GameConfig.MAVRINE_PING_DURATION


func _place_mark(brain: HunterBrain, generator: FacilityGenerator) -> void:
	var start_position := Vector2(generator.start) + Vector2(0.5, 0.5)
	var lift_position := Vector2(generator.exit_cell) + Vector2(0.5, 0.5)
	var blocked := generator.get_safe_zone_blocked_cells()

	var candidates: Array = []
	for cell in generator.floor_cells():
		if cell == _last_mark_cell or blocked.has(cell):
			continue
		var candidate := Vector2(cell) + Vector2(0.5, 0.5)
		if candidate.distance_to(start_position) < 4.0 or candidate.distance_to(lift_position) < 2.5:
			continue
		if candidate.distance_to(brain.position) < 3.0:
			continue
		if _floor_neighbor_count(generator, cell) < 3:
			continue
		if not generator.can_occupy(candidate.x, candidate.y, 0.16, blocked):
			continue
		var too_near_relay := false
		for relay in generator.relays:
			if candidate.distance_to(Vector2(relay["x"], relay["y"]) + Vector2(0.5, 0.5)) < 1.25:
				too_near_relay = true
				break
		if too_near_relay:
			continue
		candidates.append(cell)

	if candidates.is_empty():
		return

	# Shuffle, then take the first reachable one — the original caps this at
	# 48 pathfind attempts so a pathological floor can't stall a frame.
	for index in range(candidates.size() - 1, 0, -1):
		var swap_index := brain.next_random_index(index + 1)
		var temporary = candidates[index]
		candidates[index] = candidates[swap_index]
		candidates[swap_index] = temporary

	var attempts: int = mini(48, candidates.size())
	for index in attempts:
		var cell: Vector2i = candidates[index]
		if generator.find_path(HunterBrain._cell_of(brain.position), cell).is_empty():
			continue
		mark = Vector2(cell) + Vector2(0.5, 0.5)
		has_mark = true
		_last_mark_cell = cell
		return


static func _floor_neighbor_count(generator: FacilityGenerator, cell: Vector2i) -> int:
	var count := 0
	for offset in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		if generator.is_floor(cell.x + offset.x + 0.5, cell.y + offset.y + 0.5):
			count += 1
	return count
