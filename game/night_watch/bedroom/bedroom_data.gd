class_name BedroomData
extends RefCounted

## Bedtime (mode `bedroom`): names, where each hunter sounds from and Zellia's script. Pure data from
## games/night-watch/src/modes/bedroom/bedroom-data.js.

const CAST := ["loxelle", "javelle", "haelith"]
const NAMES := {"loxelle": "Loxelle", "javelle": "Javelle", "haelith": "Haelith"}
## Where each one sounds from (-1 left to +1 right): the closet, the hall door, the bed.
const PAN := {"loxelle": -0.85, "javelle": 0.85, "haelith": 0.0}

const CALLS := {
	1: ["Zellia. This room is quiet and there are no cameras. You'll hear things before you see them.",
		"Loxelle is in the closet. You won't see her, but you'll hear her breathing on the left, and her breath gets heavy when she's close. A holds it shut until it stops.",
		"D puts a light on the hall, F on the bed. You only have one free hand, so choose.",
		"The battery is limited, and it doesn't come back. Don't waste it."],
	2: ["Javelle is awake. She stays where the light ends. A little light on the hall is usually enough."],
	3: ["Haelith only moves when the room is dark, and a light on the bed pushes her back. Keep that in mind when you're saving the battery."],
	4: ["The house is louder tonight. Listen for which side it's coming from, and answer that side.",
		"It also notices stillness. If you lie there doing nothing for too long, they get restless. The closet door costs nothing to hold."],
	5: ["All three are awake. Listen first, then act, and save the battery for the side that needs it."],
	6: ["Last night in this room. The battery is the shortest it has been. Same as before: listen first, then act."],
}


static func call_lines(night: int) -> Array:
	return CALLS.get(night, [])


static func identity(id: String) -> Dictionary:
	return HunterRoster.get_identity(id)
