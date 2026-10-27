class_name NightWatchOfficeRegistry
extends RefCounted

## Which office each mode uses: ONE OFFICE PER MODE, all different (the validator suite `night_watch_offices` enforces it). `OFFICES` maps the 2D mode id to the
## office id and its script (a NightWatchOfficeBase subclass with `static func make_spec()`); a mode whose office is not built yet has `script` empty and keeps
## using the Classic room meanwhile (`PLANNED_*` is the identity chosen for it in docs/NIGHT_WATCH_OFFICES.md). To add an office: write its script in your
## own folder, set `script` here (one line per mode, in mode order).

const CLASSIC_SCRIPT := "res://src/night_watch/night_watch_office.gd"

const OFFICES := {
	"classic":  {"id": "classic_security", "script": CLASSIC_SCRIPT},
	"mask":     {"id": "front_office", "script": "res://src/night_watch/mask/mask_office.gd"},
	"lure":     {"id": "broadcast_booth", "script": ""},
	"bedroom":  {"id": "child_bedroom", "script": ""},
	"story":    {"id": "control_room", "script": ""},
	"descent":  {"id": "lift_landing", "script": ""},
	"dayshift": {"id": "cargo_bay", "script": "res://src/night_watch/dayshift/cargo_bay.gd"},
	"extra":    {"id": "watch_post", "script": ""},
	"mixed":    {"id": "hub_office", "script": ""},
}


static func office_id(mode_id: String) -> String:
	return String(OFFICES.get(mode_id, {}).get("id", ""))


static func built(mode_id: String) -> bool:
	var script_path := String(OFFICES.get(mode_id, {}).get("script", ""))
	return not script_path.is_empty() and ResourceLoader.exists(script_path)


## The spec of a mode's office (the Classic room's until its own is built).
static func spec_for(mode_id: String) -> NightWatchOfficeSpec:
	var script_path := String(OFFICES.get(mode_id, {}).get("script", ""))
	if script_path.is_empty() or not ResourceLoader.exists(script_path):
		script_path = CLASSIC_SCRIPT
	return (load(script_path) as GDScript).call("make_spec")


## A new office node for the mode (the Classic room until its own is built).
static func make(mode_id: String) -> NightWatchOfficeBase:
	var script_path := String(OFFICES.get(mode_id, {}).get("script", ""))
	if script_path.is_empty() or not ResourceLoader.exists(script_path):
		script_path = CLASSIC_SCRIPT
	return (load(script_path) as GDScript).new() as NightWatchOfficeBase
