class_name HaelithGimmick
extends HunterGimmick

## Haelith's relay pursuit (hunterAbilities.haelith.relayPursuer). Ported from
## the original's updateRelayPursuer: every frame she re-aims at the nearest
## UNCOLLECTED relay and investigates it. She does not chase the player to get
## there -- she simply goes where the objectives are, so the player keeps
## meeting her at the one place they have to be.
##
## This is the first gimmick that depends on the generator's `collected` flag
## being true, which for a long time nothing ever wrote. Relays she has already
## seen taken drop out of her search on their own.
##
## Her positional footsteps are presentation, so main_3d.gd reads this brain's
## position and plays them relative to the local runner. Keeping audio out of
## this simulation class also means a host does not accidentally play a remote
## runner's directional cue through the host's speakers.


func after_perception(brain: HunterBrain, _delta: float, _target: Dictionary, generator) -> void:
	# 2D relay-pursuer split: while more than one relay is still out, leave the one Opalie guards (the first) to her.
	var pursuit: Array = generator.relays
	var open_relays: Array = generator.uncollected(pursuit)
	if open_relays.size() > 1:
		pursuit = pursuit.filter(func(entry: Dictionary) -> bool: return entry != open_relays[0])
	var relay := _nearest_uncollected(brain.position, pursuit)
	if relay == Vector2.ZERO and generator.uncollected(pursuit).is_empty():
		return
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = relay


## Cell centres, like the original's `relay.x + .5`. Returns ZERO when every
## relay is already in, which the caller reads together with the emptiness
## check rather than as a position.
static func _nearest_uncollected(from: Vector2, entries: Array) -> Vector2:
	var best := Vector2.ZERO
	var best_distance := INF
	for entry in entries:
		if entry.get("collected", false):
			continue
		var at := Vector2(entry["x"] + 0.5, entry["y"] + 0.5)
		var distance := from.distance_to(at)
		if distance < best_distance:
			best_distance = distance
			best = at
	return best
