class_name NightWatchSave
extends RefCounted

## Night Watch progress, kept apart from Last Route's: its own file and section (`night_watch`), so the two games never share
## a key (docs/NIGHT_WATCH_3D.md). Highest night unlocked and the nights cleared. Account sync (the backend `game` field the
## City lane added) is a later milestone; this is the device cache the 2D game also keeps in localStorage.

const GAME_ID := NightWatchData.GAME_ID
const SECTION := "night_watch"
const DEFAULT_PATH := "user://night_watch.cfg"

## Tests point this at a temporary file.
static var path := DEFAULT_PATH


static func _load() -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)
	return cfg


## Highest night the player may start (1 at first; a cleared night unlocks the next, up to NIGHTS).
static func unlocked_night() -> int:
	return clampi(int(_load().get_value(SECTION, "unlocked", 1)), 1, NightWatchData.NIGHTS)


static func cleared() -> Array:
	var value = _load().get_value(SECTION, "cleared", [])
	var out := []
	if value is Array:
		for n in value:
			if int(n) >= 1 and int(n) <= NightWatchData.NIGHTS and not out.has(int(n)):
				out.append(int(n))
	out.sort()
	return out


static func record_clear(night: int) -> void:
	if night < 1 or night > NightWatchData.NIGHTS:
		return
	var cfg := _load()
	var list := cleared()
	if not list.has(night):
		list.append(night)
		list.sort()
	cfg.set_value(SECTION, "cleared", list)
	cfg.set_value(SECTION, "unlocked", clampi(maxi(unlocked_night(), night + 1), 1, NightWatchData.NIGHTS))
	cfg.save(path)


static func reset() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Night Watch's own settings (the rest, such as sensitivity and volume, are the shared ones): Zellia's subtitles.
static func subtitles() -> bool:
	return bool(_load().get_value(SECTION, "subtitles", true))


static func set_subtitles(on: bool) -> void:
	var cfg := _load()
	cfg.set_value(SECTION, "subtitles", on)
	cfg.save(path)
