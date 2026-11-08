class_name NightWatchModeRegistry
extends RefCounted

## Which of the 2D game's modes the 3D game can play, and the scene each one runs in. The mode TABLE (titles, shifts, presets) is
## NightWatchModesData, copied from the 2D registry; this file only says what is built. To add a mode: write its scene (a shift scene
## built on NightWatchMode, game/night_watch/night_watch_mode.gd), add one line to SCENES, add a validator suite. The menus pick it up.

const SCENES := {
	"classic": "res://game/night_watch/night_watch.tscn",
	"lure": "res://game/night_watch/lure/night_watch_lure.tscn",
	"bedroom": "res://game/night_watch/bedroom/night_watch_bedroom.tscn",
	"story": "res://game/night_watch/story/night_watch_story.tscn",
	"mask": "res://game/night_watch/mask/night_watch_mask.tscn",
	"dayshift": "res://game/night_watch/dayshift/night_watch_dayshift.tscn",
	"mixed": "res://game/night_watch/mixed/night_watch_mixed.tscn",
	"descent": "res://game/night_watch/descent/night_watch_descent.tscn",
	"extra": "res://game/night_watch/night_watch_extra.tscn",
}


static func playable(mode_id: String) -> bool:
	return SCENES.has(mode_id) and ResourceLoader.exists(String(SCENES[mode_id]))


static func scene_for(mode_id: String) -> String:
	return String(SCENES.get(mode_id, ""))


## Start `level` (1-based) of `mode_id`: record it in the session and return the scene to change to ("" when not built).
## `custom` is a Custom Night's sliders ({hunter id: 0..20}); an empty dictionary is a normal shift.
static func prepare(mode_id: String, level: int, custom := {}) -> String:
	if not playable(mode_id):
		return ""
	NightWatchSession.start_mode(mode_id, level, custom)
	return scene_for(mode_id)
