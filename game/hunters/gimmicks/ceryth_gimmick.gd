class_name CerythGimmick
extends HunterGimmick

## Ceryth's hiding trap (hunterAbilities.ceryth.hidingTrap). Ported from
## the original's updateHidingTrapHunter/resolveHidingTrapEntry.
##
## She does not chase. The whole of her original file is two methods and
## neither one is pursuit: once, she picks a hiding spot and a colour of eyes
## (red or blue) and posts herself beside it; from then on she never moves
## again, chase or no chase — the original's dispatcher gives `hidingTrap`
## hunters an early return past the entire ordinary movement selection, and
## `holds_position()` is this port's equivalent gate.
##
## The trap itself fires on the INTERACTION path, not her update loop: walking
## up to her spot and pressing the key to hide asks the riddle. Red eyes means
## answer by having the flashlight genuinely off (or dead); blue means the
## opposite. Answer wrong and you are hidden, but locked in for
## CERYTH_LOCK_SECONDS with the flashlight forced off — answer right and she
## disperses for the rest of the floor, and the spot is safe from her for
## everyone from then on.

var trap_spot := Vector2i(-1, -1)
var eyes_red := true
## Only when a correct answer finds no other hiding spot to flee to (2D falls back to leaving the floor). The scene
## reads this to retire her.
var dispersed := false
## 2D hidingTrap: a correct answer makes her a visible runner who sprints to a NEW spot at least
## CERYTH_MINIMUM_RETREAT away and settles there with fresh eyes.
var retreating := false
var _answered := false
var _next_spot := Vector2i(-1, -1)


func after_perception(brain: HunterBrain, _delta: float, _target: Dictionary, generator) -> void:
	if dispersed:
		return
	if _answered and not retreating:
		_answered = false
		_start_retreat(brain, generator)
		if dispersed:
			return
	if retreating:
		var perch: Vector2 = generator.hiding_exit_position({"x": _next_spot.x, "y": _next_spot.y,
			"open_direction": _spot_direction(generator, _next_spot)})
		brain.state = HunterBrain.State.INVESTIGATE
		brain.has_last_known = true
		brain.last_known = perch
		if brain.position.distance_to(perch) < 0.9:
			retreating = false
			trap_spot = _next_spot
			eyes_red = brain.next_random_index(2) == 0
			brain.position = perch
		return
	if trap_spot.x < 0:
		if generator.hiding_spots.is_empty():
			return
		var spot: Dictionary = generator.hiding_spots[brain.next_random_index(generator.hiding_spots.size())]
		trap_spot = Vector2i(spot["x"], spot["y"])
		eyes_red = brain.next_random_index(2) == 0
		var perch: Vector2 = generator.hiding_exit_position(spot)
		brain.position = perch


func holds_position() -> bool:
	return not dispersed and not retreating and trap_spot.x >= 0


func speed_scale(brain: HunterBrain) -> float:
	return GameConfig.CERYTH_RETREAT_SPEED / maxf(0.1, brain.base_speed) if retreating else 1.0


func _spot_direction(generator, cell: Vector2i) -> Vector2i:
	for spot in generator.hiding_spots:
		if int(spot["x"]) == cell.x and int(spot["y"]) == cell.y:
			return spot.get("open_direction", Vector2i.ZERO)
	return Vector2i.ZERO


func _start_retreat(brain: HunterBrain, generator) -> void:
	var options := []
	for spot in generator.hiding_spots:
		var cell := Vector2i(int(spot["x"]), int(spot["y"]))
		if cell == trap_spot:
			continue
		if Vector2(cell).distance_to(brain.position) < GameConfig.CERYTH_MINIMUM_RETREAT:
			continue
		options.append(cell)
	if options.is_empty():
		dispersed = true
		return
	_next_spot = options[brain.next_random_index(options.size())]
	retreating = true
	trap_spot = Vector2i(-2, -2)


## Dispersed, like Porcelle -- gone from the room, not from the simulation.
## brain.active still reads true (nothing here should have to know that; only
## the model needs to vanish), but her AI has nothing left to do: dispersed
## short-circuits after_perception above, and holds_position keeps whatever
## residual state machine motion permanently pinned in place.
func hidden_from_view() -> bool:
	return dispersed


## flashlight_active: genuinely on AND the lamp is alive, matching the
## original's `flashlightOn && lamp > 0`. Called from the interaction path,
## before the player is actually hidden.
func resolve_entry(cell: Vector2i, flashlight_active: bool) -> Dictionary:
	if dispersed or cell != trap_spot:
		return {}
	var answered := (not flashlight_active) if eyes_red else flashlight_active
	if not answered:
		# The riddle's rule is for the player to work out; the callout only exists behind HunterBrain.ANNOUNCE_HUNTER_EVENTS.
		return {"trapped": true, "message": ("CERYTH %s EYES // LOCKED FOR %d s"
			% ["RED" if eyes_red else "BLUE", int(GameConfig.CERYTH_LOCK_SECONDS)]) if HunterBrain.ANNOUNCE_HUNTER_EVENTS else ""}
	_answered = true
	return {"trapped": false, "cleared": true,
		"message": "CERYTH FLEES // HIDING SPOT CLEARED" if HunterBrain.ANNOUNCE_HUNTER_EVENTS else ""}


func network_state() -> Dictionary:
	return {"trap_spot": trap_spot, "eyes_red": eyes_red, "dispersed": dispersed, "retreating": retreating}


func apply_network_state(state: Dictionary) -> void:
	var spot = state.get("trap_spot")
	if spot is Vector2i:
		trap_spot = spot
	eyes_red = bool(state.get("eyes_red", eyes_red))
	dispersed = bool(state.get("dispersed", dispersed))
	retreating = bool(state.get("retreating", retreating))


## Non-lethal in 2D (nonLethal / specialist early return): she can never trigger a capture.
func immune_to_capture() -> bool:
	return true
