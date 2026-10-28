class_name NightWatchOfficeSpec
extends RefCounted

## The data side of the OFFICE CONTRACT (docs/NIGHT_WATCH_OFFICES.md): everything the framework, the validators and the menus need to know about a
## mode's office without building it. Every office script has `static func make_spec() -> NightWatchOfficeSpec`; NightWatchOfficeRegistry maps a mode to it.

const ENTRANCE_KINDS := ["door_slab", "door_wood", "curtain", "hatch", "vent", "window", "stairs", "lift", "gate", "opening"]
const MOODS := ["warm_lamp", "cold_monitor", "emergency_red", "daylight", "night_outdoor", "dusk", "fluorescent"]
## Real lights an office may have switched on at once (docs/REF_LOOK.md budget): the desk lamp and the two entrance lights, no shadow casters.
const MAX_REAL_LIGHTS := 3

var id := ""                       # unique across all modes ("classic_security", "broadcast_booth", ...)
var title := ""                    # the name the docs and the captures use
var mode_ids: Array = []           # the 2D mode ids that use this office (one office per mode; Mixed Shift rotates through `rotation`)
var rotation: Array = []           # Mixed Shift only: office ids it cycles through
var footprint := Rect2()           # walkable floor rectangle on the XZ plane, in the office's local space (metres)
var spawn := Vector3.ZERO          # where the player starts (local)
## Where hunters, vents and so on reach the office: [{id, kind (ENTRANCE_KINDS), position (local, floor level), outward (unit XZ vector pointing away from the
## office), sim_room (the mode's graph node that arrives here), blockable (the player can shut it)}]
var entrances: Array = []
## Station ids the office must expose in `stations` (NightWatchStation nodes): e.g. "monitor", "chair", "lamp", "doorL_door".
var required_stations: Array = []
var has_monitor := true            # false for Bedtime-style offices with no camera monitor
var mood := {"kind": "warm_lamp", "ambient": Color(0.38, 0.40, 0.55), "lamp": Color(1.0, 0.82, 0.55), "accent": Color(0.96, 0.72, 0.28)}
var tone_cue := "presence"         # one of NightWatchSounds.OFFICE_TONES, the room tone
## The Night Watch quick-key actions that apply in this office (NightWatchControls names); others are inactive and hidden from the hint line.
var controls: Array = []
var references := {}               # {"2d_screenshot": "docs/night_watch_offices/<id>_2d.png", "concept": "..."} for the docs


static func make(fields: Dictionary) -> NightWatchOfficeSpec:
	var s := NightWatchOfficeSpec.new()
	for k in fields:
		s.set(k, fields[k])
	return s


## Problems with the spec itself (empty list when it is complete); the registry validator prints these.
func problems() -> Array:
	var out := []
	if id.is_empty() or title.is_empty():
		out.append("no id or title")
	if mode_ids.is_empty() and rotation.is_empty():
		out.append("%s: no mode uses it" % id)
	if footprint.size.x < 2.0 or footprint.size.y < 2.0:
		out.append("%s: footprint %s is smaller than 2 x 2 m" % [id, str(footprint)])
	if not footprint.has_point(Vector2(spawn.x, spawn.z)):
		out.append("%s: the spawn is outside the footprint" % id)
	if entrances.is_empty():
		out.append("%s: no entrances" % id)
	var seen := {}
	for e in entrances:
		for key in ["id", "kind", "position", "outward", "sim_room", "blockable"]:
			if not (e as Dictionary).has(key):
				out.append("%s: entrance %s lacks %s" % [id, str(e.get("id", "?")), key])
		if not ENTRANCE_KINDS.has(String(e.get("kind", ""))):
			out.append("%s: entrance kind %s unknown" % [id, str(e.get("kind", ""))])
		if seen.has(String(e.get("id", ""))):
			out.append("%s: entrance %s twice" % [id, str(e.get("id", ""))])
		seen[String(e.get("id", ""))] = true
	if not MOODS.has(String(mood.get("kind", ""))):
		out.append("%s: mood %s unknown" % [id, str(mood.get("kind", ""))])
	if not NightWatchSounds.OFFICE_TONES.has(tone_cue):
		out.append("%s: tone cue %s is not a shared cue" % [id, tone_cue])
	if has_monitor and not required_stations.has("monitor"):
		out.append("%s: has a monitor but does not require the monitor station" % id)
	return out
