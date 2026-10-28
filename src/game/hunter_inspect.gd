class_name HunterInspect
extends RefCounted

## Locker inspection (KT 2026-10-28; the trailer's "locker breath" shot, VIDEO lane tools/playtest/shots/nyxie_locker.json).
## Every route hunter can do it (KT: "for all hunters if you can make it work 100% from different directions"); Nyxie
## keeps the trailer's version as a rare easter egg, a closer lean and a longer breath. A hunter passing a slatted hiding spot (a locker or wardrobe) with a runner inside, who did NOT see them go in,
## sometimes stops, turns to the slats, bends in close and lingers, breathing, then moves on without finding them. If
## she did see them hide, the ordinary hide check (HunterBrain.hide_check_triggers) runs instead and gets them.
##
## Timing follows the shot, compressed: walk up (~0.55 m/s), turn to face the slats (the shot's 0.6 s blend), bend in
## over 1.6 s (its bow_in), linger, straighten over 1.2 s (its bow_off), walk on. The host decides and the brain state
## carries it to guests.

const REACH := 3.0                 # she has to be passing this close to the spot
const STAND_OUT := 1.95            # where she stops, from the spot centre out through its door: leaning in, her eyes fill the slats
const STAND_MIN := 1.3             # a tighter hall: the nearest stand that still clears her lean of the locker
const TURN_SECONDS := .6
const LEAN_SECONDS := 1.6
const RISE_SECONDS := 1.2
const WALK_SCALE := .6             # of her base speed, stepping up to the slats
const WALK_LIMIT := 8.0            # gives up walking to the spot after this (blocked), and turns where she is
const SPOT_COOLDOWN := 25.0        # the same spot is not inspected again for this long
const LEAVE_DISTANCE := 4.0

## How often per qualifying pass (scaled by difficulty below). Every route hunter, except the ones whose own rules drive
## them and so cannot stop for it (EXCLUDED, see the locker_inspect validator); Nyxie's is the rare trailer easter egg:
## stand (closer), linger_scale and breaths.
const DEFAULT := {"chance": 0.3, "stand": STAND_OUT, "linger_scale": 1.0, "breaths": 1}
const TUNING := {"nyxie": {"chance": 0.12, "stand": 1.8, "linger_scale": 2.0, "breaths": 2}}
## Never inspect: the locker_inspect validator's 100% run (every hunter x 4 facings x 2 approach sides) fails for these,
## because their own rules drive them: Wynelle and Gray Void are dormant until their trigger, Ilyra and Zellia keep their
## posts, Verrine lives in the vents, Ferryn stalks from a fixed origin, and Javelle's gimmick re-aims her every frame.
## The validator also fails if one of these starts passing, so the list stays exact.
const EXCLUDED := ["wynelle", "void_gray", "ilyra", "zellia", "verrine", "ferryn", "javelle"]
## Difficulty: chance scale, linger seconds at the slats, per-hunter cooldown between inspections.
const DIFFICULTY := {
	"standard": {"chance": 1.0, "linger": 1.5, "cooldown": 40.0},
	"hard": {"chance": 1.15, "linger": 2.0, "cooldown": 30.0},
	"nightmare": {"chance": 1.3, "linger": 2.5, "cooldown": 22.0},
}


static func difficulty(difficulty_id: String) -> Dictionary:
	return DIFFICULTY.get(difficulty_id, DIFFICULTY["standard"])


static func tuning(hunter_id: String) -> Dictionary:
	return TUNING.get(hunter_id, DEFAULT)


static func chance(hunter_id: String, difficulty_id: String) -> float:
	if hunter_id in EXCLUDED or SecretCreatures.uses_creature_rig(hunter_id):
		return 0.0
	return clampf(float(tuning(hunter_id)["chance"]) * float(difficulty(difficulty_id)["chance"]), 0.0, 1.0)


static func linger(hunter_id: String, difficulty_id: String) -> float:
	return float(difficulty(difficulty_id)["linger"]) * float(tuning(hunter_id)["linger_scale"])


## Where she stands for this spot: out through its door at her stand distance, or nearer (down to STAND_MIN) when the
## hall is tighter; INF when no stand clears her body (she skips that spot rather than clipping a wall).
static func stand_point(hunter_id: String, spot_centre: Vector2, door: Vector2, generator, radius: float) -> Vector2:
	var out := float(tuning(hunter_id)["stand"])
	while out >= STAND_MIN - .001:
		var at := spot_centre + door.normalized() * out
		if generator.can_occupy(at.x, at.y, radius):
			return at
		out -= .1
	return Vector2.INF


## Slatted spots she can look into: lockers (no style) and wardrobes; not beds.
static func slatted(style: String) -> bool:
	return style != "bed"


## Whether this pass qualifies (the dice roll is the caller's): a hunter wandering, searching or investigating, close to
## the spot, off cooldown, who would NOT trigger the hide check (she did not see the runner go in).
static func qualifies(brain: HunterBrain, spot_centre: Vector2, saw_hide: bool) -> bool:
	if saw_hide or not brain.active or brain.stun_timer > 0.0 or brain.inspect_cooldown > 0.0:
		return false
	if brain.state not in [HunterBrain.State.WANDER, HunterBrain.State.SEARCH, HunterBrain.State.INVESTIGATE, HunterBrain.State.IDLE]:
		return false
	return brain.position.distance_to(spot_centre) <= REACH


## The spot's door side in route space from its fixture yaw: the authored door faces local -Z.
static func door_direction(yaw: float) -> Vector2:
	return Vector2(-sin(yaw), -cos(yaw))
