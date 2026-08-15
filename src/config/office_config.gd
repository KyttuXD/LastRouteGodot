class_name OfficeConfig
extends RefCounted

## Office Mode's static data, ported from LastRoute's
## src/game/office-survivor-system.js. Office is a completely separate mode
## from Last Route's maze/relay/hunter loop: a stationary desk-defense shift
## against ten "Void" signals, which are deliberately NOT the A-Z hunter
## roster (see the mode's own note in src/game/modes/office-survivor.js).
## Nothing here touches GameConfig, HunterRoster, or FacilityGenerator.

## The camera map is also the threat-navigation graph — one office described
## once, rather than separate flat routes per threat.
const CAMERAS := ["cam1", "cam2", "cam3", "cam4", "cam5", "cam6", "cam7", "cam8",
	"cam9", "cam10", "cam11"]

const CAMERA_GRAPH := {
	"cam1": ["cam3", "cam6", "cam9"],
	"cam2": ["cam4", "cam5", "cam11"],
	"cam3": ["cam8", "cam1", "cam6"],
	"cam4": ["cam8", "cam2", "cam5"],
	"cam5": ["cam4", "cam2", "cam7"],
	"cam6": ["cam3", "cam1", "cam7"],
	"cam7": ["cam6", "cam5"],
	"cam8": ["cam3", "cam4"],
	# South wing, reached from the two halls.
	"cam9": ["cam1", "cam10"],
	"cam10": ["cam9", "cam11"],
	"cam11": ["cam10", "cam2"],
}

## Room identities are simulation-owned metadata: the presentation layer reads
## these stable keys to draw a feed, and never invents its own state or decides
## independently which threats are visible on a camera.
const CAMERA_VIEWS := {
	"cam1": {"room": "WEST HALL", "layout": "hall", "accent": Color("785457")},
	"cam2": {"room": "EAST HALL", "layout": "hall", "accent": Color("785457")},
	"cam3": {"room": "STORAGE", "layout": "storage", "accent": Color("5d6970")},
	"cam4": {"room": "ARCHIVE", "layout": "archive", "accent": Color("766154")},
	# 5 and 6 were ducts; they are walk-height passages now, and the only
	# crawlable vent left in the map is the office's own back-wall duct.
	"cam5": {"room": "EAST PASSAGE", "layout": "passage", "accent": Color("54756a")},
	"cam6": {"room": "WEST PASSAGE", "layout": "passage", "accent": Color("54756a")},
	"cam7": {"room": "ELECTRICAL", "layout": "electrical", "accent": Color("8a7045")},
	"cam8": {"room": "LOADING", "layout": "loading", "accent": Color("6b5d70")},
	"cam9": {"room": "ARCADE", "layout": "arcade", "accent": Color("6d4f7a")},
	"cam10": {"room": "DINING A", "layout": "dining", "accent": Color("7a5a4a")},
	"cam11": {"room": "DINING B", "layout": "dining", "accent": Color("4a6a7a")},
}

const SHIFT_DURATION := 180.0
## Only these three are accepted as a custom shift length; anything else falls
## back to SHIFT_DURATION.
const SHIFT_DURATION_CHOICES := [90.0, 180.0, 300.0]

## Per-second power drain, by whichever systems are currently running. `base`
## is always charged; the rest add on top while active.
const POWER_BASE := 0.12
const POWER_DOOR := 0.48
const POWER_LIGHT := 0.62
const POWER_CAMERAS := 0.34
const POWER_VENT := 0.42
const POWER_RADIO := 0.2

const REAR_FLASH_COST := 3.0
const VENT_SEAL_DURATION := 8.0
const EMERGENCY_STUN_DURATION := 5.0
const GRAY_CHALLENGE_DURATION := 6.0
const JUMPSCARE_DURATION := 1.35

## Each Void signal's AI level is an independent 0-20 dial (Custom Night).
## 0 means genuinely disabled — no timer, movement, sabotage, challenge or
## failure path runs for it at all.
const AI_MIN := 0
const AI_MAX := 20
const AI_DEFAULT := 12

## Ordered — creation walks this list, and the RNG draw order depends on it.
const THREATS := [
	{"id": "crimson", "label": "CRIMSON", "color": Color("d7464f")},
	{"id": "azure", "label": "AZURE", "color": Color("4e91d8")},
	{"id": "amber", "label": "AMBER", "color": Color("e2a83e")},
	{"id": "emerald", "label": "EMERALD", "color": Color("4eaa70")},
	{"id": "rose", "label": "ROSE", "color": Color("e06d9d")},
	{"id": "orange", "label": "ORANGE", "color": Color("e87b36")},
	{"id": "violet", "label": "VIOLET", "color": Color("9a62d5")},
	{"id": "white", "label": "WHITE", "color": Color("e7e5df")},
	{"id": "gray", "label": "GRAY", "color": Color("8b8d92")},
	{"id": "black", "label": "BLACK", "color": Color("77727b")},
]

## Only the three threats that physically traverse the office have camera
## routes; the rest are either stationary, ambient, or never on a feed.
const THREAT_ROUTES := {
	"crimson": {"start": "cam8", "left": "cam1", "right": "cam2"},
	"amber": {"start": "cam3", "destination": "cam2"},
	"emerald": {"start": "cam6", "destination": "cam5"},
}

## Systems Orange can knock offline, and which the breaker restores.
const SABOTAGE_SYSTEMS := ["leftDoor", "rightDoor", "deskLight", "cameras", "vent", "radio"]


static func threat_ids() -> Array:
	var ids: Array = []
	for definition in THREATS:
		ids.append(definition["id"])
	return ids
