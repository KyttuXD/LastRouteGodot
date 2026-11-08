class_name SolythGimmick
extends HunterGimmick

## Solyth's heat manifest (hunterAbilities.solyth.heatManifest). Ported from
## solyth.js's syncSyttuState / updateSyttuBatteryBurn.
##
## The other **special**: always present but inert, summoned by temperature
## rather than the relay schedule, hunting alongside the drawn route hunter.
##
## The summon is deliberately one-way. Temperature reaching 100 latches
## PlayerMeters.heat_locked, which in turn pins temperature to a 90F floor —
## so unlike Nyxie, cooling down can never send her away again. She is
## permanent for the rest of the run once she wakes, which is exactly the
## original's behaviour and the reason the latch lives on the meters rather
## than here.
##
## While locked in she burns one uncollected battery every
## SOLYTH_BATTERY_BURN_INTERVAL seconds — a slow strangling of the lamp
## supply. Her hiding-spot burn is not ported: no hiding spots exist yet, so
## it would iterate an empty list rather than change behaviour.

var summoned := false

var _burn_timer := 0.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	# Relaxed disables the heat summon in the original. The brain remains in
	# the floor roster for stable co-op snapshots, but can never wake there.
	if brain.difficulty_id == "relaxed":
		brain.active = false
		brain.state = HunterBrain.State.IDLE
		return
	var meters: PlayerMeters = target.get("meters")
	if meters == null:
		return

	if not summoned:
		if not meters.heat_locked:
			brain.active = false
			brain.state = HunterBrain.State.IDLE
			return
		# Wakes once, at the extreme, somewhere away from the player.
		summoned = true
		brain.active = true
		brain.position = _spawn_position(target["position"], generator)

	_burn_batteries(delta, generator)

	brain.state = HunterBrain.State.CHASE
	brain.has_last_known = true
	brain.last_known = target["position"]
	brain.lost_sight_timer = 0.0


## Removes an uncollected battery on an interval. Reads the generator's own
## collected flags, which only became meaningful once activate() started
## writing them (see FacilityGenerator.mark_collected).
func _burn_batteries(delta: float, generator) -> void:
	_burn_timer += delta
	if _burn_timer < GameConfig.SOLYTH_BATTERY_BURN_INTERVAL:
		return
	_burn_timer -= GameConfig.SOLYTH_BATTERY_BURN_INTERVAL
	var remaining: Array = generator.uncollected(generator.batteries)
	if remaining.is_empty():
		return
	# Burned, not collected — the supply is gone rather than picked up.
	remaining[0]["collected"] = true


func _spawn_position(target_position: Vector2, generator) -> Vector2:
	var best := target_position
	var best_error := INF
	for cell in generator.floor_cells():
		var candidate := Vector2(cell) + Vector2(0.5, 0.5)
		var error: float = absf(candidate.distance_to(target_position) - GameConfig.SOLYTH_SPAWN_DISTANCE)
		if error < best_error:
			best_error = error
			best = candidate
	return best


## She wakes herself, so she must keep evaluating while inert.
func runs_while_inactive() -> bool:
	return true
