class_name LoxelleGimmick
extends HunterGimmick

## Loxelle's passive incinerator (hunterAbilities.loxelle.passiveIncinerator /
## breaksHiding). Ported from loxelle.js's updateLoxellePassive.
##
## While she is not actively chasing or investigating, every
## LOXELLE_INTERVAL seconds she has a LOXELLE_CHANCE roll to burn the nearest
## hiding spot in her OWN room. An empty spot goes dark for a while and comes
## back; an OCCUPIED one gets you pulled out of it, non-lethally, the same
## shape as Javelle's ejection.
##
## What is deliberately simplified: the original destroys a *prop* and regrows
## it from a `temporaryHidingDamage` list keyed to the game clock; this port has
## no elapsed-time clock on gimmicks, so regeneration counts down locally by
## delta instead — same effect, no dependency on a clock nothing else needs.
## The Nightmare/Standard regen-time split is also absent, since there is no
## difficulty selection yet; every floor uses the Standard (faster) rate,
## `plan.regenerateSeconds * easyRegenerateScale`, matching what most players
## will actually see.
##
## `resonancePlate`/`resolvePlateCharge` from her original file is NOT ported:
## HUNTER_ROSTER.md already recorded it as dead code, unreachable in the
## original because nothing wires `resonancePlate` to any hunter's abilities.

## Cell -> seconds remaining before it relights. Drained by the scene the same
## way world_events are, so a client sees the same spots dark as the host.
var toggles: Array = []

var _passive_timer := 0.0
var _regenerating := {}
var _charge_phase := ""
var _charge_cell := Vector2i(-1, -1)
var _charge_timer := 0.0
var _charge_candidate := {}
## Chase-only room-door breach. This is separate from the passive locker
## charge so opening an ordinary door can never accidentally burn a hiding
## spot or inherit its long post-impact stun.
var _door_charge_phase := ""
var _door_charge_id := ""
var _door_charge_position := Vector2.ZERO
var _door_charge_timer := 0.0


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	if not _door_charge_phase.is_empty():
		_update_door_charge(brain, delta, generator)
		return
	# Zellia's pesticide trade pauses her passive routine entirely --
	# regeneration included, matching the original's full early-return.
	if bool(target.get("pesticide_active", false)):
		return
	_tick_regeneration(delta)
	if not _charge_phase.is_empty():
		_update_charge(brain, delta, target, generator)
		return

	if brain.state == HunterBrain.State.CHASE or brain.state == HunterBrain.State.INVESTIGATE:
		_passive_timer = 0.0
		return
	_passive_timer += delta
	if _passive_timer < GameConfig.LOXELLE_INTERVAL:
		return
	_passive_timer = 0.0
	if brain.next_random_index(1000) >= int(GameConfig.LOXELLE_CHANCE * 1000.0):
		return

	var room: Dictionary = generator.room_at(brain.position.x, brain.position.y)
	if room.is_empty():
		return
	var candidate := _nearest_live_spot(brain.position, generator, String(room["id"]))
	if candidate.is_empty():
		return
	var cell := Vector2i(candidate["x"], candidate["y"])
	# Mark the locker, approach it, visibly brace, then charge. The old immediate
	# toggle made a locker disappear with no action from Loxelle at all.
	_charge_cell = cell
	_charge_candidate = candidate.duplicate(true)
	_charge_phase = "approach"
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = Vector2(cell) + Vector2(.5, .5)


func _update_charge(brain: HunterBrain, delta: float, target: Dictionary,
		generator) -> void:
	var impact := Vector2(_charge_cell) + Vector2(.5, .5)
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = impact
	match _charge_phase:
		"approach":
			if brain.position.distance_to(impact) <= GameConfig.LOXELLE_CHARGE_START_DISTANCE:
				_charge_phase = "windup"
				_charge_timer = GameConfig.LOXELLE_CHARGE_WINDUP
		"windup":
			_charge_timer -= delta
			if _charge_timer <= 0.0:
				_charge_phase = "charge"
				_charge_timer = GameConfig.LOXELLE_CHARGE_SECONDS
		"charge":
			_charge_timer -= delta
			var offset := impact - brain.position
			if offset.length() > GameConfig.LOXELLE_CHARGE_IMPACT_DISTANCE:
				var travel := minf(GameConfig.LOXELLE_CHARGE_SPEED * delta,
					offset.length())
				var direction := offset.normalized()
				brain.facing = direction
				var next := brain.position + direction * travel
				if generator.can_occupy(next.x, next.y, brain.radius):
					brain.position = next
			if brain.position.distance_to(impact) <= GameConfig.LOXELLE_CHARGE_IMPACT_DISTANCE \
					or _charge_timer <= 0.0:
				_resolve_charge(brain, target, generator)


func _resolve_charge(brain: HunterBrain, target: Dictionary,
		generator) -> void:
	var occupied := bool(target.get("hidden", false)) \
		and Vector2i(target.get("hiding_spot", Vector2i(-1, -1))) == _charge_cell
	if occupied:
		toggles.append({"cell": _charge_cell,
			"eject_to": generator.hiding_exit_position(_charge_candidate),
			"charge_impact": true, "temperature_add": GameConfig.LOXELLE_BREAK_TEMPERATURE,
			"noise_add": GameConfig.LOXELLE_BREAK_NOISE})
	else:
		toggles.append({"cell": _charge_cell, "disabled": true,
			"charge_impact": true})
		_regenerating[_charge_cell] = GameConfig.LOXELLE_REGEN_SECONDS
	_charge_phase = ""
	_charge_cell = Vector2i(-1, -1)
	_charge_timer = 0.0
	_charge_candidate.clear()
	brain.apply_stun(GameConfig.LOXELLE_BREAK_STALL)


func start_door_breach(brain: HunterBrain, door_id: String,
		door_position: Vector2) -> bool:
	if door_id.is_empty() or brain.state != HunterBrain.State.CHASE \
			or not _charge_phase.is_empty() or not _door_charge_phase.is_empty():
		return false
	_door_charge_id = door_id
	_door_charge_position = door_position
	_door_charge_phase = "windup"
	_door_charge_timer = GameConfig.LOXELLE_CHARGE_WINDUP
	var facing := door_position - brain.position
	if facing.length_squared() > .0001:
		brain.facing = facing.normalized()
	return true


func _update_door_charge(brain: HunterBrain, delta: float, generator) -> void:
	brain.state = HunterBrain.State.CHASE
	match _door_charge_phase:
		"windup":
			_door_charge_timer -= delta
			var facing := _door_charge_position - brain.position
			if facing.length_squared() > .0001:
				brain.facing = facing.normalized()
			if _door_charge_timer <= 0.0:
				_door_charge_phase = "charge"
				_door_charge_timer = minf(.42, GameConfig.LOXELLE_CHARGE_SECONDS)
		"charge":
			_door_charge_timer -= delta
			var offset := _door_charge_position - brain.position
			if offset.length() > GameConfig.LOXELLE_CHARGE_IMPACT_DISTANCE:
				var travel := minf(GameConfig.LOXELLE_CHARGE_SPEED * delta,
					offset.length())
				var direction := offset.normalized()
				brain.facing = direction
				var next := brain.position + direction * travel
				if generator.can_occupy(next.x, next.y, brain.radius):
					brain.position = next
			if brain.position.distance_to(_door_charge_position) \
					<= GameConfig.LOXELLE_CHARGE_IMPACT_DISTANCE \
					or _door_charge_timer <= 0.0:
				brain.world_events.append({"what": "room_door",
					"door_id": _door_charge_id, "open": true, "broken": true})
				_door_charge_phase = ""
				_door_charge_id = ""
				_door_charge_timer = 0.0
				brain.apply_stun(.65)


func door_charge_active() -> bool:
	return not _door_charge_phase.is_empty()


func charge_active() -> bool:
	return _charge_phase in ["windup", "charge"] or door_charge_active()


func holds_position() -> bool:
	# Charge movement is applied explicitly above; ordinary path motion would
	# otherwise stack a second movement step onto the impact lunge.
	return charge_active()


func network_state() -> Dictionary:
	return {"charge_phase": _charge_phase, "charge_cell": _charge_cell,
		"door_charge_phase": _door_charge_phase,
		"door_charge_id": _door_charge_id,
		"door_charge_position": _door_charge_position}


func apply_network_state(state: Dictionary) -> void:
	_charge_phase = String(state.get("charge_phase", ""))
	_charge_cell = state.get("charge_cell", Vector2i(-1, -1))
	_door_charge_phase = String(state.get("door_charge_phase", ""))
	_door_charge_id = String(state.get("door_charge_id", ""))
	_door_charge_position = state.get("door_charge_position", Vector2.ZERO)


func _tick_regeneration(delta: float) -> void:
	for cell in _regenerating.keys().duplicate():
		_regenerating[cell] -= delta
		if _regenerating[cell] <= 0.0:
			_regenerating.erase(cell)
			toggles.append({"cell": cell, "disabled": false})


func _nearest_live_spot(from: Vector2, generator, room_id: String) -> Dictionary:
	var best := {}
	var best_distance := INF
	for spot in generator.hiding_spots:
		if String(spot.get("room_id", "")) != room_id:
			continue
		if _regenerating.has(Vector2i(spot["x"], spot["y"])):
			continue
		var distance := from.distance_to(Vector2(spot["x"] + 0.5, spot["y"] + 0.5))
		if distance < best_distance:
			best_distance = distance
			best = spot
	return best


## Non-lethal in 2D (nonLethal / specialist early return): she can never trigger a capture.
func immune_to_capture() -> bool:
	return true

