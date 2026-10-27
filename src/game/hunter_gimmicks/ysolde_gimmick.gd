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
## answer to being confronted. The pesticide guard at the top of
## after_perception IS ported -- Zellia's shop now exists, and
## `target["pesticide_active"]` is threaded in from main_3d the same way
## heater_unfrozen/heater_powered already are.


## YSOLDE AVOIDS (docs/YSOLDE.md): she is timid. When the runner is close and in sight she does not come closer: she backs
## off along the real nav graph to a reachable, non-dead-end cell that gains distance. KT picks the style here:
##   "avoid" keeps about AVOID_DISTANCE away and slips around (normal pace, short retreats),
##   "run"   bolts away faster and farther and gives up the area for a while.
const BEHAVIOUR := "avoid"
const AVOID_DISTANCE := 9.0
const RUN_DISTANCE := 14.0
const RUN_SPEED_SCALE := 1.35
const RUN_LOSE_INTEREST := 6.0
const FLEE_REPLAN := 0.6

var fleeing := false
## Standing her ground on purpose (cornered, or watching a nearby runner): movement stops, perception keeps running.
var holding := false
var _flee_timer := 0.0
var _replan := 0.0
var _flee_point := Vector2.ZERO
## Set when she noticed the runner this retreat (for the scared emote / squeak cue).
var noticed_at_msec := 0


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	if _update_flee(brain, delta, target, generator):
		return
	if bool(target.get("pesticide_active", false)):
		return
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


## True while she is retreating (perception overridden this frame).
func _update_flee(brain: HunterBrain, delta: float, target: Dictionary, generator) -> bool:
	holding = false
	_flee_timer = maxf(0.0, _flee_timer - delta)
	_replan = maxf(0.0, _replan - delta)
	var threat = target.get("position")
	var keep := RUN_DISTANCE if BEHAVIOUR == "run" else AVOID_DISTANCE
	var sees := false
	if threat is Vector2 and not bool(target.get("hidden", false)):
		var gap: float = brain.position.distance_to(threat)
		sees = gap < keep and (not generator.has_method("has_line_of_sight") or generator.has_line_of_sight(brain.position, threat))
		if sees:
			if not fleeing:
				noticed_at_msec = Time.get_ticks_msec()
			fleeing = true
			_flee_timer = RUN_LOSE_INTEREST if BEHAVIOUR == "run" else 1.5
	if _flee_timer <= 0.0 and fleeing:
		# retreat over: forget the spot she ran to (no search of her own hiding place), back to wandering
		fleeing = false
		brain.has_last_known = false
		brain.state = HunterBrain.State.WANDER
	if not fleeing:
		# Out of reach but still close: perception may want to chase the runner she just fled. She never closes in:
		# she holds where she is (watching) until the runner is well away, then her own errands take over again.
		if threat is Vector2 and brain.position.distance_to(threat) < keep * 1.6 \
				and brain.state in [HunterBrain.State.CHASE, HunterBrain.State.INVESTIGATE] \
				and brain.last_known.distance_to(threat) < 2.5:
			brain.state = HunterBrain.State.INVESTIGATE
			brain.has_last_known = true
			brain.last_known = brain.position
			holding = true
			return true
		return false
	if threat is Vector2 and (_replan <= 0.0 or brain.position.distance_to(_flee_point) < .8):
		_replan = FLEE_REPLAN
		var point = flee_target(generator, brain.position, threat, keep)
		if point is Vector2:
			_flee_point = point
		else:
			_flee_point = brain.position   # cornered: freeze instead of teleporting
			holding = true
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = _flee_point
	return true


func holds_position() -> bool:
	return holding


func speed_scale(_brain: HunterBrain) -> float:
	return RUN_SPEED_SCALE if fleeing and BEHAVIOUR == "run" else 1.0


## The best retreat cell: reachable from `from` on the real nav, at least two open neighbours (not a dead end), and the
## largest distance gain from `threat`; ring search 3..`keep` cells, deterministic order. null when cornered.
static func flee_target(generator, from: Vector2, threat: Vector2, keep: float):
	if not (generator.has_method("can_occupy") and generator.has_method("find_path")):
		return null
	var start := Vector2i(floori(from.x), floori(from.y))
	var best = null
	var best_score := from.distance_to(threat) + .75
	for ring in range(3, int(keep) + 1, 2):
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				var cell := start + Vector2i(dx, dz)
				var centre := Vector2(cell) + Vector2(.5, .5)
				if not generator.can_occupy(centre.x, centre.y):
					continue
				var score := centre.distance_to(threat)
				if score <= best_score:
					continue
				var exits := 0
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					if generator.can_occupy(centre.x + d.x, centre.y + d.y):
						exits += 1
				if exits < 2:
					continue
				var path: Array = generator.find_path(start, cell)
				if path.is_empty():
					continue
				# the way there must lead away: a retreat whose route passes the runner is no retreat
				var gap := from.distance_to(threat)
				var approaches := false
				for step_cell in path:
					if (Vector2(step_cell) + Vector2(.5, .5)).distance_to(threat) < gap - .5:
						approaches = true
						break
				if approaches:
					continue
				best = centre
				best_score = score
	return best


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


## 2D batteryThief never targets or attacks the player.
func immune_to_capture() -> bool:
	return true
