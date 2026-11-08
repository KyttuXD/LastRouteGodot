class_name NightWatchMode
extends Node3D

## The base of every Night Watch mode scene (Classic, Masked Hours, Dead Air, ...). It owns what the 2D game's shift runner owns in
## `core/scene.js`: which mode and level this run is (from NightWatchSession, set by the menu), the seed, the Custom Night sliders, saving
## a win into the mode-keyed save, and the Retry / Next / Menu actions. A mode subclass builds its own world and rules and calls:
##   read_session()                 first thing in _ready()
##   record_win(score)              when the shift is won (saves the clear, or the star and best score of a Custom Night)
##   retry() / next_level()         the end card's buttons (Retry replays the same seed)
##   back_to_board()                QUIT TO HUB / MENU: the Shift Board, as the 2D game returns to its hub
## and emits `finished("win" | "caught" | ...)` once. The menu finds the scene through NightWatchModeRegistry.SCENES. Validators build the
## scene, set `manual_clock = true` and step it with advance_ms() (every mode implements that), so a shift is deterministic.
## See docs/NIGHT_WATCH_MODES.md for the contract and the per-mode checklist.

signal finished(result: String)

const BOARD_SCENE := "res://game/night_watch/night_watch_menu.tscn"

var mode_id := "classic"
var level := 1            # 1-based shift of the mode (a night, a week, a watch, a descent)
var seed_value := 0
var custom := {}          # {hunter id: 0..20} for a Custom Night, else {}
var is_custom := false
var manual_clock := false


func read_session() -> void:
	mode_id = NightWatchSession.mode_id
	level = NightWatchSession.night
	seed_value = NightWatchSession.seed_value
	if seed_value == 0:
		seed_value = int(Time.get_ticks_usec() & 0x7fffffff)
	custom = NightWatchSession.custom_levels
	is_custom = NightWatchSession.is_custom


func mode_data() -> Dictionary:
	return NightWatchModesData.mode(mode_id)


## How many shifts of this mode count (Mixed Shift's Endless is the fifth but not scored).
func scored_levels() -> int:
	return int(mode_data().get("scored", 1))


func level_count() -> int:
	return (mode_data().get("levels", []) as Array).size()


func level_name() -> String:
	var levels: Array = mode_data().get("levels", [])
	return String(levels[level - 1]) if level >= 1 and level <= levels.size() else ""


func has_next_level() -> bool:
	return not is_custom and level < scored_levels()


## A won shift: the level is cleared (and opens the next); a Custom Night saves its best score and, when its sliders equal a preset's,
## that preset's star. Returns the Custom Night's score, else 0.
func record_win(score := 0) -> int:
	if not is_custom:
		NightWatchSave.record_level_clear(mode_id, level)
		return 0
	var total := 0
	for k in custom:
		total += clampi(int(custom[k]), 0, NightWatchModesData.MAX_AI)
	total *= NightWatchModesData.POINTS_PER_LEVEL
	NightWatchSave.record_best(mode_id, total)
	for p in mode_data().get("presets", []):
		var same := true
		for k in (p["ai"] as Dictionary):
			if int(custom.get(k, 0)) != int((p["ai"] as Dictionary)[k]):
				same = false
		if same:
			NightWatchSave.record_star(mode_id, String(p["id"]))
	return total


func retry() -> void:
	NightWatchSession.start_mode(mode_id, level, custom, seed_value)
	get_tree().paused = false
	get_tree().reload_current_scene()


func next_level() -> void:
	if not has_next_level():
		return
	NightWatchSession.start_mode(mode_id, level + 1)
	get_tree().paused = false
	get_tree().reload_current_scene()


func back_to_board() -> void:
	get_tree().paused = false
	MouseLock.release_all()
	NightWatchSession.menu_screen = "board"
	get_tree().change_scene_to_file(BOARD_SCENE)


## Night Watch is locked for players (GameRegistry): a mode scene reached by any path but the menu (a deep link, a stale scene path) goes
## back to the hub at once; testers (admin, KYTTU_DEV, validation) play it as before.
func _enter_tree() -> void:
	if not NightWatchSession.is_open():
		GameRegistry.active_game_id = GameRegistry.DEFAULT_ID   # the hub set the Last Route scheme on arrival; the menu does not
		get_tree().change_scene_to_file.call_deferred(GameRegistry.landing_scene())
