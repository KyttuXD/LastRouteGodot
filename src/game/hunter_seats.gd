class_name HunterSeats
extends RefCounted

## Hunters taking a seat (docs/SEATING.md). Host-side, like HunterNaps: now and then a patrolling hunter (wandering or
## idle, no runner close) walks to a free seat nearby and sits for a while. Seated she still hunts with her senses: the
## brain is not stepped, but she gets up at once on a noise or on sight of a runner and goes to look (sight wins: she
## chases). Rare, and rarer the harder the difficulty; never for Voids or the secret creatures.

const CHANCE_PER_SECOND := {"relaxed": .012, "standard": .007, "hard": .002, "nightmare": 0.0}
const SEAT_SEARCH_RADIUS := 12.0
const NO_RUNNER_WITHIN := 14.0
const WALK_TIMEOUT := 18.0
const SIT_SECONDS := Vector2(12.0, 28.0)
const HEAR_NOISE := 2.0
const HEAR_DISTANCE := 12.0
const SIGHT_DISTANCE := 14.0
const POSE := "sit"

## entity_id -> {"phase": "walk" | "seated", "seat": seat spot, "t": seconds}
var sitting := {}


static func can_sit(hunter_id: String, difficulty_id: String) -> bool:
	if float(CHANCE_PER_SECOND.get(difficulty_id, 0.0)) <= 0.0:
		return false
	return not (hunter_id.begins_with("void_") or HunterRoster.VOID_IDS.has(hunter_id) or SecretCreatures.has(hunter_id))


func is_seated(entity_id: String) -> bool:
	return String(sitting.get(entity_id, {}).get("phase", "")) == "seated"


func seat_of(entity_id: String) -> Dictionary:
	return sitting.get(entity_id, {}).get("seat", {})


## Seats another hunter has taken or is walking to (plan positions, like SeatOccupancy).
func _taken() -> Array:
	var out := []
	for id in sitting:
		out.append((sitting[id] as Dictionary)["seat"].get("seat_at", Vector2(INF, INF)))
	return out


## Pure get-up rule, shared with the validator: a loud runner within earshot, or one she can see.
static func gets_up_for(hunter_at: Vector2, target: Dictionary, navigation: StreamedHunterNavigation) -> bool:
	if target.is_empty() or bool(target.get("hidden", false)):
		return false
	var at: Vector2 = target.get("position", Vector2(INF, INF))
	var distance := hunter_at.distance_to(at)
	if float(target.get("noise", 0.0)) >= HEAR_NOISE and distance <= HEAR_DISTANCE:
		return true
	if distance > SIGHT_DISTANCE:
		return false
	return navigation == null or navigation.has_line_of_sight(hunter_at, at)


## Returns true when the seat owns the hunter this tick (seated): the caller skips brain.update.
func update(entity_id: String, brain: HunterBrain, navigation: StreamedHunterNavigation, target: Dictionary,
		delta: float, roll: float, difficulty_id: String) -> bool:
	var target_at: Vector2 = target.get("position", Vector2(INF, INF)) if not target.is_empty() else Vector2(INF, INF)
	if not sitting.has(entity_id):
		if not brain.active or brain.state not in [HunterBrain.State.WANDER, HunterBrain.State.IDLE] \
				or brain.position.distance_to(target_at) < NO_RUNNER_WITHIN or not can_sit(brain.hunter_id, difficulty_id):
			return false
		if roll >= float(CHANCE_PER_SECOND.get(difficulty_id, 0.0)) * delta:
			return false
		var taken := _taken()
		taken.append_array(SeatOccupancy.taken)
		var seat := _nearest_seat(brain.position, navigation, taken)
		if seat.is_empty():
			return false
		sitting[entity_id] = {"phase": "walk", "seat": seat, "t": WALK_TIMEOUT}
	var entry: Dictionary = sitting[entity_id]
	var seat: Dictionary = entry["seat"]
	var stand_at: Vector2 = seat.get("stand_at", brain.position)
	match String(entry["phase"]):
		"walk":
			entry["t"] = float(entry["t"]) - delta
			if brain.state not in [HunterBrain.State.WANDER, HunterBrain.State.IDLE] or float(entry["t"]) <= 0.0:
				sitting.erase(entity_id)
				return false
			brain.has_wander_target = true
			brain.wander_target = stand_at
			if brain.position.distance_to(stand_at) <= 1.0:
				entry["phase"] = "seated"
				entry["t"] = lerpf(SIT_SECONDS.x, SIT_SECONDS.y, fposmod(roll * 6151.0, 1.0))
				brain.position = seat.get("seat_at", stand_at)
			return false
		"seated":
			entry["t"] = float(entry["t"]) - delta
			if gets_up_for(brain.position, target, navigation):
				stand_up(entity_id, brain, target)
				return false
			if float(entry["t"]) <= 0.0:
				stand_up(entity_id, brain, {})
				return false
			return true
	return false


## Up from the seat onto the floor in front of it. Disturbed: she goes to look where the runner was.
func stand_up(entity_id: String, brain: HunterBrain, disturbed_by: Dictionary) -> void:
	var seat := seat_of(entity_id)
	sitting.erase(entity_id)
	brain.position = seat.get("stand_at", brain.position)
	if disturbed_by.is_empty():
		brain.state = HunterBrain.State.WANDER
		return
	brain.has_last_known = true
	brain.last_known = disturbed_by.get("position", brain.position)
	brain.state = HunterBrain.State.INVESTIGATE


func forget(entity_id: String) -> void:
	sitting.erase(entity_id)


static func _nearest_seat(from: Vector2, navigation: StreamedHunterNavigation, taken: Array) -> Dictionary:
	if navigation == null:
		return {}
	var best := {}
	var best_distance := SEAT_SEARCH_RADIUS
	for spot_value in navigation.seat_spots:
		var spot: Dictionary = spot_value
		var at: Vector2 = spot.get("seat_at", Vector2(INF, INF))
		if taken.any(func(p: Vector2) -> bool: return p.distance_to(at) <= SeatOccupancy.NEAR):
			continue
		var distance := from.distance_to(spot.get("seat_at", Vector2(INF, INF)))
		if distance < best_distance:
			best = spot
			best_distance = distance
	return best
