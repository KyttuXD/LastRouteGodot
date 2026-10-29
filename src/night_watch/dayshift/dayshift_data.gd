class_name DayshiftData
extends RefCounted

## Salvage Run's constants, copied from the 2D game's modes/dayshift/dayshift-data.js: the three hunters, the shop's upgrades, the weekly
## budget / quota / AI levels, what turns up on the rack, the three decks it is dealt from and Zellia's script. Pure data.

const CAST := ["ravelle", "ceryth", "ysolde"]
const NAMES := {"ravelle": "Ravelle", "ceryth": "Ceryth", "ysolde": "Ysolde"}
const PAN := {"ravelle": -0.8, "ceryth": 0.8, "ysolde": 0.0}

const UPGRADES := [
	{"id": "hinges", "name": "Sturdy hinges", "cost": 30, "blurb": "Doors cost half as much power while shut."},
	{"id": "cell", "name": "Extra cell", "cost": 40, "blurb": "Power drains a quarter slower."},
	{"id": "soles", "name": "Soft soles", "cost": 35, "blurb": "The doors' visitors are two levels less keen."},
	{"id": "gloves", "name": "Salvage gloves", "cost": 45, "blurb": "Salvaging is 30% faster."},
	{"id": "bench", "name": "Padded bench", "cost": 40, "blurb": "Salvaging makes half the noise."},
]

const BUDGET := [90, 100, 110, 120, 130]
const QUOTA := [140, 210, 280, 340, 380]
const LEVELS := {"ravelle": [4, 7, 10, 13, 15], "ceryth": [0, 5, 8, 12, 14], "ysolde": [0, 0, 6, 10, 13]}
## What a week's surplus adds to the next week's budget when you play on.
const CARRY_CAP := 40

## What turns up on the rack: its worth and how long you hold to take it (before gloves). Order matters (the deck is built in this order).
const ITEM_KINDS := ["scrap", "parts", "prize"]
const ITEMS := {
	"scrap": {"label": "Scrap", "value": 10, "ms": 2000.0, "weight": 5},
	"parts": {"label": "Parts", "value": 25, "ms": 3500.0, "weight": 3},
	"prize": {"label": "Prize", "value": 60, "ms": 5500.0, "weight": 1},
}
const DECKS := [
	{"id": "steady", "weight": 2, "scrap": 5, "parts": 3, "prize": 1},
	{"id": "lumpy", "weight": 1, "scrap": 7, "parts": 0, "prize": 2},
	{"id": "parts", "weight": 1, "scrap": 3, "parts": 6, "prize": 0},
]

## Zellia's calls (dayshift-data.js CALLS); the keys she names are the 2D game's, the 3D controls are in the hint line.
const CALLS := {
	1: ["Zellia. This is a work week, so the day comes first. Spend your budget in the shop, then start the shift.",
		"At night, pick a piece on the rack and hold to take it. The quota is shown at the top. Noise is a cost, and you'll want to keep an eye on it.",
		"The two doors are the side doors, with a light on each. Ravelle comes to the left one, and if you close it she goes."],
	2: ["There's a second visitor this week: Ceryth, at the right-hand door. The same doors and lights apply, and when one of them is turned away she warns the other.",
		"A light on a doorway is enough to keep someone from moving. It uses power, so use it sparingly."],
	3: ["The window at the back is used after closing. When you hear a knock, Ysolde is there.",
		"Until she's gone, let go of the rack and keep the lights off. The doors make no sound, so shut one if someone's there."],
	4: ["Everyone is on this week and the quota is higher. Any surplus from last week carries over, up to a point.",
		"Choose the pieces you take. Not all of them are worth the noise."],
	5: ["This is the last week of the schedule, and the highest quota. A prize is the quickest way there, if you can afford the noise."],
}


static func call_lines(week: int) -> Array:
	return CALLS.get(clampi(week, 1, 5), [])
