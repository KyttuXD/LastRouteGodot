class_name GrabStyles
extends RefCounted

## How each hunter takes hold of a runner it has caught. "neck_lift" is NeckLift (one hand at the neck, the runner's feet leave the
## floor, a short hold, then game over); "classic" is the plain catch every other hunter still has. Every roster id must be listed
## so a new hunter cannot ship without someone deciding how it grabs: the `neck_lift` suite checks it.

const NECK_LIFT := "neck_lift"
const CLASSIC := "classic"

const STYLES := {
	"kathy": NECK_LIFT, "xivvy": NECK_LIFT, "umbriel": NECK_LIFT, "elise": NECK_LIFT, "wynelle": NECK_LIFT, "ravelle": NECK_LIFT,
}


static func style_for(hunter_id: String) -> String:
	return String(STYLES.get(hunter_id, CLASSIC))


static func lifts(hunter_id: String) -> bool:
	return style_for(hunter_id) == NECK_LIFT
