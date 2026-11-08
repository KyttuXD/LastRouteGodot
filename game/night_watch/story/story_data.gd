class_name StoryData
extends RefCounted

## The Facility (mode `story`): the six rooms, each night's task list, and Zellia's script. Pure data from the original game's Facility data.
## A night is a list of tasks, not a clock: it ends when the last one is done.

const CAST := ["opalie", "porcelle", "quenelle"]
const NAMES := {"opalie": "Opalie", "porcelle": "Porcelle", "quenelle": "Quenelle"}
## The 3D roster has no Quenelle model yet: Verrine stands in (docs/NIGHT_WATCH_MODES.md).
const MODEL_STANDIN := {"quenelle": "verrine"}
const PAN := {"opalie": -0.8, "porcelle": 0.8, "quenelle": 0.0}

## exits: L = left door, R = right door, C = the lift door. A side with a door but no exit is a way through for hunters only.
const ROOMS := {
	"breaker": {"label": "BREAKER ROOM", "exits": {"R": "gallery"}},
	"gallery": {"label": "GALLERY", "exits": {"L": "breaker", "R": "control"}},
	"control": {"label": "CONTROL", "exits": {"L": "gallery", "R": "workshop", "C": "lift"}},
	"workshop": {"label": "WORKSHOP", "exits": {"L": "control", "R": "auditorium"}},
	"auditorium": {"label": "AUDITORIUM", "exits": {"L": "workshop"}},
	"lift": {"label": "LIFT", "exits": {"C": "control"}},
}

static func _t(room: String, label: String, kind: String, n := 0, ms := 0) -> Dictionary:
	var d := {"room": room, "label": label, "kind": kind}
	if kind == "hold":
		d["ms"] = ms
	else:
		d["n"] = n
	return d


## Tasks per night, in order: code (key the number on the note), dials (turn each lamp's dial to its mark), collect (every part off the bench),
## crank (turn the stage crank), switches (flip the breakers in their numbered order), hold (hold the lift's call button).
static func tasks(night: int) -> Array:
	match night:
		1:
			return [_t("control", "Log in", "code", 3), _t("gallery", "Calibrate the lamps", "dials", 3), _t("workshop", "Collect the parts", "collect", 4), _t("control", "Sign off", "code", 3)]
		2:
			return [_t("control", "Log in", "code", 3), _t("gallery", "Calibrate the lamps", "dials", 3), _t("breaker", "Reset the breaker", "switches", 4),
				_t("gallery", "Check the lamps", "dials", 4), _t("control", "Sign off", "code", 4)]
		3:
			return [_t("control", "Log in", "code", 3), _t("workshop", "Collect the parts", "collect", 5), _t("auditorium", "Service the stage", "crank", 14),
				_t("gallery", "Check the lamps", "dials", 4), _t("control", "Sign off", "code", 4)]
		4:
			return [_t("control", "Log in", "code", 4), _t("lift", "Check the floor above", "hold", 0, 4500), _t("breaker", "Reset the breaker", "switches", 5),
				_t("gallery", "Check the lamps", "dials", 4), _t("control", "Sign off", "code", 4)]
		5:
			return [_t("control", "Log in", "code", 4), _t("auditorium", "Service the stage", "crank", 14), _t("breaker", "Reset the breaker", "switches", 5),
				_t("lift", "Check the floor above", "hold", 0, 4500), _t("gallery", "Calibrate the lamps", "dials", 4), _t("control", "Sign off", "code", 4)]
		_:
			return [_t("control", "Log in", "code", 5), _t("workshop", "Collect the parts", "collect", 6), _t("auditorium", "Service the stage", "crank", 16),
				_t("breaker", "Reset the breaker", "switches", 6), _t("lift", "Check the floor above", "hold", 0, 5000), _t("gallery", "Calibrate the lamps", "dials", 5),
				_t("control", "Sign off", "code", 5)]


## The orders a night's list may be done in (indexes into tasks(night)); the night draws one from its variety stream. Log in stays first, Sign off last.
const TASK_ORDERS := {
	1: [[0, 1, 2, 3]],
	2: [[0, 1, 2, 3, 4], [0, 1, 3, 2, 4], [0, 2, 1, 3, 4]],
	3: [[0, 1, 2, 3, 4], [0, 2, 1, 3, 4]],
	4: [[0, 1, 2, 3, 4]],
	5: [[0, 1, 2, 3, 4, 5], [0, 1, 4, 3, 2, 5]],
	6: [[0, 1, 2, 3, 4, 5, 6], [0, 1, 2, 5, 4, 3, 6]],
}

const CALLS := {
	1: ["Zellia. Tonight is orientation. I'll give you tasks and you'll carry them out in order.",
		"Your list is on the left. Walk through the side doors, and the lift door off Control. Each room's task is done at its own station, so look around.",
		"Nothing is active tonight. Take your time and learn the layout."],
	2: ["The gallery has a resident, and the lamps there need you twice tonight. Opalie responds to noise, and everything you do at a station is a little loud, so work quietly there.",
		"Hold C as you go through a door to crawl, which is slower but quiet. The red line on your noise meter is what she can hear. Under it she still creeps in, slowly, so don't dawdle.",
		"If she gets to your door, leave. Getting through a door takes a moment, so go at one step, not at the last second."],
	3: ["The workshop and the auditorium are watched by Porcelle. She comes closer when it's dark.",
		"The beacon on F holds her still, and held long enough it pushes her back. It does run down, so don't leave it on. When Opalie hears something, Porcelle is warned.",
		"Leaving a room doesn't make them forget you. They wait near the door for you to come back. The list ends in the gallery again, so keep it quiet."],
	4: ["The lift runs between floors on a schedule, and Quenelle rides it. A bell sounds shortly before it opens at Control. The gallery lamps want checking again before you sign off.",
		"If you're in Control when it opens, hide with H until it leaves. Don't be in the lift itself when it opens; get out when the bell goes. The lamp under your list lights with it."],
	5: ["Everything is active tonight, and the list covers the whole building.", "Keep your routes short and keep the noise down."],
	6: ["This is the last list, and the longest. Every room is on it, and everyone is keener than before, and keener the longer you take.",
		"Do it in order and don't hurry. Hurrying is loud."],
}


static func call_lines(night: int) -> Array:
	return CALLS.get(night, [])


static func identity(id: String) -> Dictionary:
	return HunterRoster.get_identity(String(MODEL_STANDIN.get(id, id)))
