class_name HunterNaps
extends RefCounted

## Hunters napping in beds (docs/REST_AND_SLEEP.md). Host-side, alongside the brain: now and then a patrolling hunter
## (wandering or idle, no runner close) walks to a nearby bed, yawns, lies down and sleeps. Asleep it does not hunt: the
## brain is not updated at all. A runner close by, a loud runner, or a torch beam in its face wakes it with a startle
## (flinch, a short stun, then it investigates where the runner was). Otherwise it wakes on its own after a while.
## Chance per second of patrol by difficulty; never for Voids, creatures, or hunters whose persona never yawns.

const CHANCE_PER_SECOND := {"relaxed": .02, "standard": .012, "hard": .003, "nightmare": 0.0}
const BED_SEARCH_RADIUS := 14.0
const NO_RUNNER_WITHIN := 14.0
const WALK_TIMEOUT := 20.0
const YAWN_SECONDS := 2.0
const SLEEP_SECONDS := Vector2(25.0, 45.0)
const WAKE_RUNNER_DISTANCE := 3.0
const WAKE_NOISE := 3.0
const WAKE_NOISE_DISTANCE := 10.0
const WAKE_TORCH_DISTANCE := 7.0

## Wake meter ("if you enter a room with a sleeping hunter, they should eventually wake up and notice you"): while a
## runner is in her room (or in sight within METER_SIGHT), it fills every second by METER_BASE (so she always wakes,
## sneaking and dark included) plus closeness, noise, sprinting and a torch on her. Cues as it fills: a stir, a turn over,
## the snore stopping (`stage` 1-3). Full: she wakes and goes straight for the runner. Out of her room it drains slowly.
## For JUST_WOKE_SECONDS after that wake a catch is instant (no escape struggle), reason WOKE_GRAB_REASON.
const METER_BASE := .03
const METER_CLOSE := .12
const METER_NOISE := .04
const METER_SPRINT := .15
const METER_TORCH := .25
const METER_DECAY := .02
const METER_SIGHT := 10.0
const STAGE_AT := [.35, .6, .85]
const JUST_WOKE_SECONDS := 3.0
const WOKE_GRAB_REASON := "woke_grab"

## entity_id -> {"phase": "walk" | "yawn" | "asleep", "bed": nav spot, "t": seconds, "meter": 0..1}
var naps := {}
## entity_id -> seconds left in which a catch is the instant "woke up and grabbed you"
var just_woke := {}


static func can_sleep(hunter_id: String, difficulty_id: String) -> bool:
	if float(CHANCE_PER_SECOND.get(difficulty_id, 0.0)) <= 0.0:
		return false
	if hunter_id.begins_with("void_") or HunterRoster.VOID_IDS.has(hunter_id) or SecretCreatures.has(hunter_id):
		return false
	return HunterEmotePersonality.weight(hunter_id, HunterEmoteCatalog.YAWN) > 0.0


func is_asleep(entity_id: String) -> bool:
	return String(naps.get(entity_id, {}).get("phase", "")) == "asleep"


func meter_of(entity_id: String) -> float:
	return float(naps.get(entity_id, {}).get("meter", 0.0))


## 0 sound asleep, 1 stirring, 2 turned over, 3 snore stopped (about to wake).
func stage_of(entity_id: String) -> int:
	var meter := meter_of(entity_id)
	var stage := 0
	for threshold in STAGE_AT:
		if meter >= float(threshold):
			stage += 1
	return stage


func instant_catch(entity_id: String) -> bool:
	return float(just_woke.get(entity_id, 0.0)) > 0.0


## Per-second meter gain for a runner in the room (pure, shared with the validator); 0 when the runner is not there.
static func meter_rate(hunter_at: Vector2, target: Dictionary, in_room: bool) -> float:
	if target.is_empty() or bool(target.get("hidden", false)) or not in_room:
		return 0.0
	var at: Vector2 = target.get("position", Vector2(INF, INF))
	var distance := hunter_at.distance_to(at)
	var rate := METER_BASE + METER_CLOSE * clampf(1.0 - distance / METER_SIGHT, 0.0, 1.0)
	rate += METER_NOISE * maxf(0.0, float(target.get("noise", 0.0)))
	if bool(target.get("sprinting", false)):
		rate += METER_SPRINT
	if bool(target.get("flashlight_on", false)):
		var facing: Vector2 = target.get("facing", Vector2.ZERO)
		if facing.length_squared() > 0.0 and facing.normalized().dot((hunter_at - at).normalized()) > .7:
			rate += METER_TORCH
	return rate


func bed_of(entity_id: String) -> Dictionary:
	return naps.get(entity_id, {}).get("bed", {})


## Returns true when the nap owns the hunter this tick (yawning or asleep): the caller skips brain.update.
## `roll` is a uniform 0..1 sample for the start chance; `target` is the hunter's chosen target state (may be empty).
func update(entity_id: String, brain: HunterBrain, navigation: StreamedHunterNavigation, target: Dictionary,
		delta: float, roll: float, difficulty_id: String) -> bool:
	var target_at: Vector2 = target.get("position", Vector2(INF, INF)) if not target.is_empty() else Vector2(INF, INF)
	if just_woke.has(entity_id):
		just_woke[entity_id] = float(just_woke[entity_id]) - delta
		if float(just_woke[entity_id]) <= 0.0:
			just_woke.erase(entity_id)
	if not naps.has(entity_id):
		if not brain.active or brain.state not in [HunterBrain.State.WANDER, HunterBrain.State.IDLE] \
				or brain.position.distance_to(target_at) < NO_RUNNER_WITHIN or not can_sleep(brain.hunter_id, difficulty_id):
			return false
		if roll >= float(CHANCE_PER_SECOND.get(difficulty_id, 0.0)) * delta:
			return false
		var bed := _nearest_bed(brain.position, navigation, target)
		if bed.is_empty():
			return false
		naps[entity_id] = {"phase": "walk", "bed": bed, "t": WALK_TIMEOUT}
	var nap: Dictionary = naps[entity_id]
	var bed: Dictionary = nap["bed"]
	var approach := Vector2(float(bed.get("x", 0)) + .5, float(bed.get("y", 0)) + .5)
	match String(nap["phase"]):
		"walk":
			nap["t"] = float(nap["t"]) - delta
			if brain.state not in [HunterBrain.State.WANDER, HunterBrain.State.IDLE] or float(nap["t"]) <= 0.0:
				naps.erase(entity_id)    # it noticed something, or could not get there
				return false
			brain.has_wander_target = true
			brain.wander_target = approach
			if brain.position.distance_to(approach) <= 1.2:
				nap["phase"] = "yawn"
				nap["t"] = YAWN_SECONDS
				brain.start_emote(HunterEmoteCatalog.YAWN, YAWN_SECONDS)
			return false
		"yawn":
			nap["t"] = float(nap["t"]) - delta
			if float(nap["t"]) <= 0.0:
				nap["phase"] = "asleep"
				nap["t"] = lerpf(SLEEP_SECONDS.x, SLEEP_SECONDS.y, fposmod(roll * 7919.0, 1.0))
				brain.position = bed.get("prop_at", approach)
			return true
		"asleep":
			nap["t"] = float(nap["t"]) - delta
			var in_room := runner_in_room(brain.position, target, navigation)
			var rate := meter_rate(brain.position, target, in_room)
			nap["meter"] = clampf(float(nap.get("meter", 0.0)) + (rate if rate > 0.0 else -METER_DECAY) * delta, 0.0, 1.0)
			var startle := wakes_for(brain.position, target) or float(nap["meter"]) >= 1.0
			if startle:
				wake(entity_id, brain, approach, target, in_room)
			elif float(nap["t"]) <= 0.0 and float(nap["meter"]) <= 0.0:
				wake(entity_id, brain, approach, {})
			return true
	return false


## Pure wake rule, shared with the validator.
static func wakes_for(hunter_at: Vector2, target: Dictionary) -> bool:
	if target.is_empty() or bool(target.get("hidden", false)):
		return false
	var at: Vector2 = target.get("position", Vector2(INF, INF))
	var distance := hunter_at.distance_to(at)
	if distance <= WAKE_RUNNER_DISTANCE:
		return true
	if float(target.get("noise", 0.0)) >= WAKE_NOISE and distance <= WAKE_NOISE_DISTANCE:
		return true
	if bool(target.get("flashlight_on", false)) and distance <= WAKE_TORCH_DISTANCE:
		var facing: Vector2 = target.get("facing", Vector2.ZERO)
		if facing.length_squared() > 0.0 and facing.normalized().dot((hunter_at - at).normalized()) > .85:
			return true
	return false


## Same room as the bed (the navigation's room rects), or in line of sight within METER_SIGHT.
static func runner_in_room(hunter_at: Vector2, target: Dictionary, navigation: StreamedHunterNavigation) -> bool:
	if target.is_empty():
		return false
	var at: Vector2 = target.get("position", Vector2(INF, INF))
	if navigation != null:
		var room := navigation.room_at(hunter_at.x, hunter_at.y)
		if not room.is_empty() and room == navigation.room_at(at.x, at.y):
			return true
		return hunter_at.distance_to(at) <= METER_SIGHT and navigation.has_line_of_sight(hunter_at, at)
	return hunter_at.distance_to(at) <= METER_SIGHT


## Up again: back where it lay down. Woken by a runner: if the runner is still in the room (or in sight) she spots them
## and chases at once, and for JUST_WOKE_SECONDS a catch is instant; otherwise she flinches and goes to look.
func wake(entity_id: String, brain: HunterBrain, stand_at: Vector2, startled_by: Dictionary, sees_runner: bool = false) -> void:
	naps.erase(entity_id)
	brain.position = stand_at
	if startled_by.is_empty():
		brain.state = HunterBrain.State.WANDER
		return
	brain.has_last_known = true
	brain.last_known = startled_by.get("position", stand_at)
	if sees_runner:
		brain.state = HunterBrain.State.CHASE
		just_woke[entity_id] = JUST_WOKE_SECONDS
		return
	brain.start_emote(HunterEmoteCatalog.FLINCH, .8)
	brain.apply_stun(.5)
	brain.state = HunterBrain.State.INVESTIGATE


func forget(entity_id: String) -> void:
	naps.erase(entity_id)


static func _nearest_bed(from: Vector2, navigation: StreamedHunterNavigation, target: Dictionary) -> Dictionary:
	if navigation == null:
		return {}
	var occupied: Vector2i = target.get("hiding_spot", Vector2i(-1, -1)) if bool(target.get("hidden", false)) else Vector2i(-1, -1)
	var best := {}
	var best_distance := BED_SEARCH_RADIUS
	for spot_value in navigation.hiding_spots:
		var spot: Dictionary = spot_value
		if String(spot.get("style", "")) != "bed" or Vector2i(int(spot.get("x", 0)), int(spot.get("y", 0))) == occupied:
			continue
		var distance := from.distance_to(spot.get("prop_at", Vector2(INF, INF)))
		if distance < best_distance:
			best = spot
			best_distance = distance
	return best
