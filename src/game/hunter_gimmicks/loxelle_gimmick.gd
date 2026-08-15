class_name LoxelleGimmick
extends HunterGimmick

## Loxelle's passive incinerator (hunterAbilities.loxelle.passiveIncinerator /
## breaksHiding). Ported from loxelle.js's updateLoxellePassive.
##
## While she is not actively chasing or investigating, every
## LOXELLE_INTERVAL seconds she has a LOXELLE_CHANCE roll to burn the nearest
## hiding spot in her OWN room. An empty spot goes dark for a while and comes
## back; an OCCUPIED one gets you pulled out of it, non-lethally, the same
## shape as Jyvra's ejection.
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


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, generator: FacilityGenerator) -> void:
	_tick_regeneration(delta)

	if brain.state == HunterBrain.State.CHASE or brain.state == HunterBrain.State.INVESTIGATE:
		_passive_timer = 0.0
		return
	_passive_timer += delta
	if _passive_timer < GameConfig.LOXELLE_INTERVAL:
		return
	_passive_timer = 0.0
	if brain.next_random_index(1000) >= int(GameConfig.LOXELLE_CHANCE * 1000.0):
		return

	var room := generator.room_at(brain.position.x, brain.position.y)
	if room.is_empty():
		return
	var candidate := _nearest_live_spot(brain.position, generator, String(room["id"]))
	if candidate.is_empty():
		return
	var cell := Vector2i(candidate["x"], candidate["y"])

	if bool(target.get("hidden", false)) and Vector2i(target.get("hiding_spot", Vector2i(-1, -1))) == cell:
		# Occupied: eject rather than burn. Mirrors Jyvra's ejection shape,
		# stalling her briefly so the player she just exposed gets a beat.
		toggles.append({"cell": cell, "eject_to": generator.hiding_exit_position(candidate)})
		brain.apply_stun(GameConfig.LOXELLE_BREAK_STALL)
		return

	toggles.append({"cell": cell, "disabled": true})
	_regenerating[cell] = GameConfig.LOXELLE_REGEN_SECONDS


func _tick_regeneration(delta: float) -> void:
	for cell in _regenerating.keys().duplicate():
		_regenerating[cell] -= delta
		if _regenerating[cell] <= 0.0:
			_regenerating.erase(cell)
			toggles.append({"cell": cell, "disabled": false})


func _nearest_live_spot(from: Vector2, generator: FacilityGenerator, room_id: String) -> Dictionary:
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
