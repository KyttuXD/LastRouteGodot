class_name YsoldeGimmick
extends HunterGimmick

## Ysolde's battery theft (hunterAbilities.ysolde.batteryThief). Ported from
## ysolde.js: she walks to the nearest UNCOLLECTED battery and, within
## YSOLDE_STEAL_RANGE, takes it -- permanently. It is off the floor; the player
## does not get to race her to it afterwards.
##
## She is the first hunter who changes the world rather than only chasing
## through it, so her theft goes out as a world event (see
## HunterBrain.world_events) instead of being applied here. It has to reach
## every peer the same way a player's pickup does -- a battery stolen on the
## host and still glowing on a client is a battery two people walk to.
##
## Her torch retaliation is NOT ported: it triggers on `player.torchUntil`, and
## the player has no torch. It summons a dormant hunter and teleports Ysolde
## away, so it is a real absence, not a cosmetic one -- she currently has no
## answer to being confronted. The pesticide check above it belongs to
## Zephyra's shop, which likewise does not exist.


func after_perception(brain: HunterBrain, _delta: float, _target: Dictionary, generator: FacilityGenerator) -> void:
	var index := _nearest_uncollected(brain.position, generator.batteries)
	if index < 0:
		return

	var entry: Dictionary = generator.batteries[index]
	var at := Vector2(entry["x"] + 0.5, entry["y"] + 0.5)
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = at

	if brain.position.distance_to(at) > GameConfig.YSOLDE_STEAL_RANGE:
		return
	# Marked here as well as broadcast, so her next frame does not re-target the
	# battery she just took while the event is still in flight.
	entry["collected"] = true
	stolen += 1
	brain.world_events.append({
		"what": "pickup",
		"cell": Vector2i(entry["x"], entry["y"]),
		"kind": RouteInteractable3D.Kind.BATTERY,
		"message": "YSOLDE STOLE A BATTERY PACK",
	})


var stolen := 0


static func _nearest_uncollected(from: Vector2, entries: Array) -> int:
	var best := -1
	var best_distance := INF
	for i in entries.size():
		var entry: Dictionary = entries[i]
		if entry.get("collected", false):
			continue
		var distance := from.distance_to(Vector2(entry["x"] + 0.5, entry["y"] + 0.5))
		if distance < best_distance:
			best_distance = distance
			best = i
	return best
