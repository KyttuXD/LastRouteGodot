class_name MaskData
extends RefCounted

## Masked Hours' constants, copied from the 2D game's Masked Hours data (the wing, the graph, where each hunter waits, the tune,
## Zellia's script). Pure data. The tuning numbers live in MaskLogic (the original's T, LEVELS, ...).

const CAST := ["verrine", "thessine", "glyra", "nyxie", "umbriel", "haelith", "ilyra"]
const NAMES := {"thessine": "Thessine", "umbriel": "Umbriel", "verrine": "Verrine", "glyra": "Glyra", "nyxie": "Nyxie", "haelith": "Haelith", "ilyra": "Ilyra"}

## The wing, FNAF 2 style: eight camera rooms around a main hall and two air vents (3D names; the ids and the graph are the 2D game's). Prize Corner (music box), Parts / Service,
## Show Stage, Game Area (the junction), Vent Hub, Left / Right Air Vent, Main Hall. `cam` is the camera number, `pan` where the room sounds from the office
## (-1 left to +1 right), `map` the room's place on the camera map (percent). The hall (CAM 8) is the office's own right-hand corridor in 3D.
const ROOMS := {
	"music": {"cam": 1, "label": "PRIZE CORNER", "pan": 0.0, "map": Vector2(15, 33), "grid": Vector2i(1, 0)},
	"costume": {"cam": 2, "label": "PARTS / SERVICE", "pan": 0.5, "map": Vector2(85, 33), "grid": Vector2i(0, 0)},
	"gallery": {"cam": 3, "label": "SHOW STAGE", "pan": 0.0, "map": Vector2(50, 11), "grid": Vector2i(2, 0)},
	"ballroom": {"cam": 4, "label": "GAME AREA", "pan": 0.0, "map": Vector2(50, 33), "grid": Vector2i(1, 1)},
	"crawl": {"cam": 5, "label": "VENT HUB", "pan": 0.0, "map": Vector2(50, 78), "grid": Vector2i(0, 1)},
	"ductL": {"cam": 6, "label": "LEFT AIR VENT", "pan": -0.9, "map": Vector2(15, 61.5), "grid": Vector2i(0, 2)},
	"ductR": {"cam": 7, "label": "RIGHT AIR VENT", "pan": 0.9, "map": Vector2(85, 61.5), "grid": Vector2i(2, 2)},
	"hall": {"cam": 8, "label": "MAIN HALL", "pan": 0.0, "map": Vector2(50, 61.5), "grid": Vector2i(-1, -1)},
	"office": {"cam": 0, "label": "OFFICE", "pan": 0.0, "map": Vector2(50, 94), "grid": Vector2i(-1, -1)},
	"ventL": {"cam": 0, "label": "LEFT VENT", "pan": -1.0, "map": Vector2(32.5, 77.75), "grid": Vector2i(-1, -1)},
	"ventR": {"cam": 0, "label": "RIGHT VENT", "pan": 1.0, "map": Vector2(67.5, 77.75), "grid": Vector2i(-1, -1)},
}

## Walkable connections (undirected). The hall hunters cross the ballroom to the hall; the vent hunters crawl the ducts to a vent.
const GRAPH := {
	"music": ["ballroom"],
	"costume": ["ballroom"],
	"gallery": ["ballroom"],
	"ballroom": ["music", "costume", "gallery", "hall"],
	"hall": ["ballroom", "office"],
	"office": ["hall", "ventL", "ventR"],
	"crawl": ["ductL", "ductR"],
	"ductL": ["crawl", "ventL"],
	"ductR": ["crawl", "ventR"],
	"ventL": ["ductL", "office"],
	"ventR": ["ductR", "office"],
}

## Where each hunter waits between visits.
const HOME := {"thessine": "costume", "umbriel": "gallery", "verrine": "crawl", "haelith": "crawl", "ilyra": "crawl", "glyra": "music"}
const DUCTS := ["ductL", "ductR"]
const DUCT_SIDE := {"ductL": "L", "ductR": "R"}
const DUCT_CAM := {"L": "ductL", "R": "ductR"}
const VENT_HUNTERS := ["verrine", "haelith", "ilyra"]
const HALL_HUNTERS := ["thessine"]
const RUSHER := "umbriel"
const TUNE := [659, 587, 523, 587, 659, 659, 659, 587, 587, 587, 659, 784, 784]

## Zellia's calls, nights 1-6 (the original's CALLS). The keys she names are the 2D game's; the 3D controls are in the hint line.
const CALLS := {
	1: ["Zellia. This wing has no doors, so the usual routine doesn't apply.",
		"Thessine will use the hall. If she walks into the office, put the mask on and keep it on until she leaves. The hall light lights the hall.",
		"The cameras are on the monitor, and the music box is on camera 1. Hold to wind it. It starts to run down at 2 AM tonight.",
		"Watch the ballroom. Whoever is standing there takes the hall next. Camera 8 is the hall itself, right outside your door.",
		"While you watch one of them on camera on her way here, she holds still. The cameras run off your battery, though, and so does the desk lamp.",
		"Your flashlight is limited, and it doesn't come back. If it dies, don't wait in the dark."],
	2: ["Verrine is out tonight. She stays in the vents, and it is dark in there, so she only shows in the light. Light the left vent or the right one. A light on her usually settles things.",
		"Cameras 6 and 7 show the ducts, and the ducts are dark too. Hold the vent light on camera 6 or 7 to light the duct. If she's crawling down one, you know which vent to light."],
	3: ["Umbriel is out tonight, and she doesn't walk. She runs. When you hear her break into a run, she's coming down the hall.",
		"The mask does nothing to her. Flash the hall light at her, a few quick flashes, and she backs off to the gallery.",
		"If she's crouched by the hall doors on camera 4, she's about to go. Watching her there holds her, but once she runs, the cameras won't stop her.",
		"Each flash costs a little battery, so don't waste them."],
	4: ["The music box runs down faster now. Listen to the tune. When it slows, it needs winding.",
		"Haelith is out tonight. She runs the ducts fast, and a quick light sends her off. She doesn't go far: she comes back down the other duct."],
	5: ["Everyone in this wing is awake tonight. The routine hasn't changed.",
		"Ilyra is out tonight too. She creeps along the ducts while it is dark and freezes when the light is on her. Only one of them is ever in the vents at a time."],
	6: ["This is the last night in this wing, and the box runs down fastest of all. Keep to the routine, and keep the flashlight for when it counts."],
}


static func call_lines(night: int) -> Array:
	return CALLS.get(clampi(night, 1, 6), [])


static func cam_rooms() -> Array:
	var out := []
	for id in ROOMS:
		if int(ROOMS[id]["cam"]) > 0:
			out.append(id)
	out.sort_custom(func(a, b): return int(ROOMS[a]["cam"]) < int(ROOMS[b]["cam"]))
	return out


static func room_for_cam(cam: int) -> String:
	for id in ROOMS:
		if int(ROOMS[id]["cam"]) == cam:
			return id
	return ""


static func cam_label(room: String) -> String:
	return "CAM %d · %s" % [int(ROOMS[room]["cam"]), String(ROOMS[room]["label"])]
