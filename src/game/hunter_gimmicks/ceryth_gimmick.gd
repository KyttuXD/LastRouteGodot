class_name CerythGimmick
extends HunterGimmick

## Ceryth's hiding trap (hunterAbilities.ceryth.hidingTrap). Ported from
## ceryth.js's updateHidingTrapHunter/resolveHidingTrapEntry.
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
## Set once she has been answered correctly. The scene reads this to retire her.
var dispersed := false


func after_perception(brain: HunterBrain, _delta: float, _target: Dictionary, generator: FacilityGenerator) -> void:
	if dispersed:
		return
	if trap_spot.x < 0:
		if generator.hiding_spots.is_empty():
			return
		var spot: Dictionary = generator.hiding_spots[brain.next_random_index(generator.hiding_spots.size())]
		trap_spot = Vector2i(spot["x"], spot["y"])
		eyes_red = brain.next_random_index(2) == 0
		var perch := generator.hiding_exit_position(spot)
		brain.position = perch


func holds_position() -> bool:
	return not dispersed and trap_spot.x >= 0


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
		return {"trapped": true, "message": "CERYTH %s EYES // LOCKED FOR %d s"
			% ["RED" if eyes_red else "BLUE", int(GameConfig.CERYTH_LOCK_SECONDS)]}
	dispersed = true
	return {"trapped": false, "cleared": true,
		"message": "CERYTH DISPERSED // HIDING SPOT CLEARED"}


func network_state() -> Dictionary:
	return {"trap_spot": trap_spot, "eyes_red": eyes_red, "dispersed": dispersed}


func apply_network_state(state: Dictionary) -> void:
	var spot = state.get("trap_spot")
	if spot is Vector2i:
		trap_spot = spot
	eyes_red = bool(state.get("eyes_red", eyes_red))
	dispersed = bool(state.get("dispersed", dispersed))
