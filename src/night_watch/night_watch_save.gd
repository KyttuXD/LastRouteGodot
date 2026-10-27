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


## Calm mode (no lamp flicker or glitching), the 2D settings' second row. The shared reduced-motion setting is the switch the game reads.
static func calm() -> bool:
	return bool(_load().get_value(SECTION, "calm", false))


static func set_calm(on: bool) -> void:
	var cfg := _load()
	cfg.set_value(SECTION, "calm", on)
	cfg.save(path)


## Scare (Full / Short / Off), as in the 2D settings: Short is a quick one, Off is just the card.
const SCARE_SETTINGS := ["full", "short", "off"]


static func scare() -> String:
	var value := String(_load().get_value(SECTION, "scare", "full"))
	return value if SCARE_SETTINGS.has(value) else "full"


static func set_scare(value: String) -> void:
	if not SCARE_SETTINGS.has(value):
		return
	var cfg := _load()
	cfg.set_value(SECTION, "scare", value)
	cfg.save(path)


# --- progress keyed by mode (the framework's save: one `night_watch` section, one key family per mode) ---------------------
# Classic keeps the keys it always had (`cleared`, `unlocked`); every other mode uses `cleared_<mode>`. A level is 1-based.

static func _cleared_key(mode: String) -> String:
	return "cleared" if mode == "classic" else "cleared_%s" % mode


static func cleared_levels(mode: String) -> Array:
	var value = _load().get_value(SECTION, _cleared_key(mode), [])
	var out := []
	if value is Array:
		for n in value:
			if int(n) >= 1 and not out.has(int(n)):
				out.append(int(n))
	out.sort()
	return out


static func record_level_clear(mode: String, level: int) -> void:
	if level < 1:
		return
	var cfg := _load()
	var list := cleared_levels(mode)
	if not list.has(level):
		list.append(level)
		list.sort()
	cfg.set_value(SECTION, _cleared_key(mode), list)
	if mode == "classic":
		cfg.set_value(SECTION, "unlocked", clampi(maxi(unlocked_night(), level + 1), 1, NightWatchData.NIGHTS))
	cfg.save(path)


## A level is open when it is the first, the one before it is cleared, or the mode opens everything (Mixed Shift).
static func level_open(mode: String, level: int, open_all := false) -> bool:
	return open_all or level <= 1 or cleared_levels(mode).has(level - 1)


## A mode's Custom Night opens once its Night 5 is cleared (the 2D rule).
static func custom_unlocked(mode: String) -> bool:
	return cleared_levels(mode).has(5)


static func stars(mode: String) -> Array:
	var value = _load().get_value(SECTION, "stars_%s" % mode, [])
	return value if value is Array else []


static func record_star(mode: String, preset_id: String) -> void:
	var cfg := _load()
	var list := stars(mode)
	if not list.has(preset_id):
		list.append(preset_id)
	cfg.set_value(SECTION, "stars_%s" % mode, list)
	cfg.save(path)


static func best_score(mode: String) -> int:
	return int(_load().get_value(SECTION, "best_%s" % mode, 0))


static func record_best(mode: String, score: int) -> void:
	if score > best_score(mode):
		var cfg := _load()
		cfg.set_value(SECTION, "best_%s" % mode, score)
		cfg.save(path)


## The Custom Night sliders last used, per mode: {hunter: 0..20}.
static func custom_values(mode: String) -> Dictionary:
	var value = _load().get_value(SECTION, "custom_%s" % mode, {})
	return value if value is Dictionary else {}


static func set_custom_values(mode: String, values: Dictionary) -> void:
	var cfg := _load()
	cfg.set_value(SECTION, "custom_%s" % mode, values)
	cfg.save(path)


## A stable guest name for the Account page (GUEST_ plus eight hex digits), made once.
static func guest_name() -> String:
	var name_value := String(_load().get_value(SECTION, "guest", ""))
	if name_value.is_empty():
		name_value = "GUEST_%08X" % (randi() & 0x7fffffff)
		var cfg := _load()
		cfg.set_value(SECTION, "guest", name_value)
		cfg.save(path)
	return name_value


## Rebound Night Watch keys: {action name: physical keycode}, applied by NightWatchControls.register() (so a rebind of a camera or door key survives a restart).
static func key_overrides() -> Dictionary:
	var value = _load().get_value(SECTION, "keys", {})
	return value if value is Dictionary else {}


static func set_key_override(action: String, keycode: int) -> void:
	var cfg := _load()
	var keys := key_overrides()
	keys[action] = keycode
	cfg.set_value(SECTION, "keys", keys)
	cfg.save(path)


static func clear_key_overrides() -> void:
	var cfg := _load()
	cfg.set_value(SECTION, "keys", {})
	cfg.save(path)
