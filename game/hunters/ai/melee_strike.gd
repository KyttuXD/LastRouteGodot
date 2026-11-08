class_name MeleeStrike
extends RefCounted

## Crowbar and rescue axe hits on a hunter: a swing with nothing to breach or cut free in reach. The host decides the hit
## (InfiniteRouteTest._accept_hunter_strike) and stuns her for the tool's profile value, which is longer than a taser or a
## grab break-free, and tags the stun STUN_KIND_HEAVY so every peer shows the reel (HunterView3D). Pure rules, shared with the
## validator.

const STUN_KIND_HEAVY := "heavy"
const ITEMS := ["crowbar", "rescue_axe"]


static func handles(item_id: String) -> bool:
	return item_id in ITEMS


## Stun seconds a hit with `item_id` gives on `difficulty_id`, or 0.0 for a tool that cannot hit a hunter.
static func stun_seconds(item_id: String, difficulty_id: String) -> float:
	match item_id:
		"crowbar":
			return GameConfig.profile_value(difficulty_id, "crowbar_stun")
		"rescue_axe":
			return GameConfig.profile_value(difficulty_id, "axe_stun")
	return 0.0


## True when a swing from `from`, facing `aim`, lands on `brain`: in reach, inside the forward cone and with a clear line.
## It is the taser beam's rule (HunterBrain.beam_reaches) at melee reach.
static func can_strike(brain: HunterBrain, from: Vector2, aim: Vector2, navigation) -> bool:
	if brain == null or navigation == null:
		return false
	return brain.beam_reaches(from, aim, brain.position, GameConfig.MELEE_STRIKE_RANGE,
		GameConfig.MELEE_STRIKE_HALF_ANGLE, navigation)


## True while a heavy (crowbar or axe) stun is what holds her.
static func reeling(brain: HunterBrain) -> bool:
	return brain != null and brain.stun_timer > 0.0 and brain.stun_kind == STUN_KIND_HEAVY
