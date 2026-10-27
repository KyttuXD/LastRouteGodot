class_name LureData
extends RefCounted

## Dead Air (mode `lure`): the attraction hall, its cameras and Zellia's script. Pure data from games/night-watch/src/modes/lure/lure-data.js.
## `pan` is where a room sounds from (-1 left to +1 right).

const CAST := ["wynelle", "xivvy", "mavrine", "briselle", "solyth", "ferryn"]
const NAMES := {"xivvy": "Xivvy", "ferryn": "Ferryn", "briselle": "Briselle", "mavrine": "The air", "solyth": "Solyth", "wynelle": "Wynelle"}

const ROOMS := ["lobby", "arcade", "party", "ballpit", "prize", "storage", "ventl", "ventr"]   # camera 1..8
const INFO := {
	"lobby": {"label": "LOBBY", "pan": 0.0, "grid": Vector2i(0, 0)},
	"arcade": {"label": "ARCADE", "pan": -0.6, "grid": Vector2i(0, 1)},
	"party": {"label": "PARTY ROOM", "pan": 0.6, "grid": Vector2i(1, 0)},
	"ballpit": {"label": "BALL PIT", "pan": 0.0, "grid": Vector2i(1, 1)},
	"prize": {"label": "PRIZE COUNTER", "pan": 0.7, "grid": Vector2i(2, 0)},
	"storage": {"label": "STORAGE", "pan": 0.0, "grid": Vector2i(2, 1)},
	"ventl": {"label": "LEFT VENT", "pan": -0.9, "grid": Vector2i(2, 2)},
	"ventr": {"label": "RIGHT VENT", "pan": 0.9, "grid": Vector2i(3, 1)},
	"officeL": {"label": "LEFT VENT OPENING", "pan": -1.0},
	"officeR": {"label": "RIGHT VENT OPENING", "pan": 1.0},
}

## Walkable connections (undirected). The storage room feeds both vents; each vent ends at an office opening.
const GRAPH := {
	"lobby": ["arcade", "party"],
	"arcade": ["lobby", "ballpit"],
	"party": ["lobby", "prize", "ballpit"],
	"ballpit": ["arcade", "party", "storage"],
	"prize": ["party", "storage"],
	"storage": ["prize", "ballpit", "ventl", "ventr"],
	"ventl": ["storage", "officeL"],
	"ventr": ["storage", "officeR"],
	"officeL": ["ventl"],
	"officeR": ["ventr"],
}

## Each phantom breaks one system.
const SYSTEM_OF := {"ferryn": "cams", "briselle": "audio", "mavrine": "vent"}
const SYSTEMS := {
	"audio": {"label": "AUDIO", "key": "Q", "climate": false},
	"cams": {"label": "CAMERAS", "key": "W", "climate": false},
	"vent": {"label": "VENTS", "key": "E", "climate": false},
	"heater": {"label": "HEATER", "key": "R", "climate": true},
	"fan": {"label": "FAN", "key": "T", "climate": true},
}

## Zellia's calls, nights 1-6 (the 2D lines; the keys are this game's: the wall panels seal the vents, the monitor reboots and lures).
const CALLS := {
	1: ["Zellia. This is the attraction hall. Only one of them is active tonight, and she's harmless: she takes the cameras.",
		"When something goes dark, reboot it from the monitor with Q, W or E.",
		"The wall panels seal the vents. The monitor is on your desk, and L plays a sound in the room you're watching.",
		"Sealed vents make the air heavy, so don't leave them closed for long."],
	2: ["Xivvy is awake now, and she's the real one. She picks a vent and keeps to it until something turns her away.",
		"Use the lure sparingly. The speakers don't like being asked twice in a row."],
	3: ["Briselle is in tonight. She takes the audio, and with no audio there's no lure. Reboot it on Q.",
		"They take more than their usual now. Check what is down, not only what you expect."],
	4: ["The building has a temperature tonight, and it is falling. That's Wynelle. There's a heater on the left panel, and it reboots on R.",
		"Don't leave the heater running for long. It costs air."],
	5: ["Mavrine is in tonight. She takes the vents, and the heater with them. Keep an eye on the air.",
		"That's five of them. The routine is the same. Keep the reboots going."],
	6: ["Last night in the hall. Ferryn is resting, but the heat has someone of its own: Solyth. Too much heater and she cooks the office.",
		"There's a fan on the right panel, and it reboots on T. The cold bites hardest tonight and the hunter is quickest. I'll be on the line if you need me."],
}


static func call_lines(night: int) -> Array:
	return CALLS.get(night, [])


## Steps from every room to `target` (core/graph.js distancesTo).
static func distances_to(target: String) -> Dictionary:
	var dist := {target: 0}
	var queue := [target]
	while not queue.is_empty():
		var room: String = queue.pop_front()
		for nxt in GRAPH.get(room, []):
			if not dist.has(nxt):
				dist[nxt] = int(dist[room]) + 1
				queue.append(nxt)
	return dist
