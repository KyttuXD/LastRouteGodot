class_name GameRegistry
extends RefCounted

## Every game the hub can list. The hub, the shared account/settings/admin entries and any future "continue where you
## left off" read from here, so adding Night Watch's 3D port later is one entry flip (`locked` -> false and a scene).
## Each game carries its own Theme resource: the hub dresses that game's card (and, once it has a scene, its menus) with it.

const GAMES := [
	{
		"id": "last_route",
		"title": "THE LAST ROUTE",
		"kicker": "SIGNAL ARCHIVE // ROUTE UNSTABLE",
		"tagline": "Run the endless route, collect relays, outlast the hunters.",
		"scene": "res://game/menus/main_menu.tscn",
		"theme": "res://game/ui_common/theme_lastroute.tres",
		"locked": false,
		"locked_note": "",
		# Playtest bot adapter (see docs/PLAYTEST.md); a game without the key falls back to PlaytestAdapters.BUILT_IN.
		"playtest_bot": "res://dev/playtest/bots/last_route_bot.gd",
	},
	{
		"id": "night_watch",
		"title": "NIGHT WATCH",
		"kicker": "CAMERA FEED // OVERNIGHT SHIFT",
		"tagline": "Hold the desk through the night. Watch the feeds, keep them out.",
		"scene": "res://game/night_watch/night_watch_menu.tscn",
		"theme": "res://game/night_watch/theme_nightwatch.tres",
		# locked for players until Night Watch is fully data-driven and moddable; admins and devs still open it to test.
		"locked": true,
		"locked_note": "NIGHT WATCH // COMING BACK SOON",
		"dev_open": true,
	},
]

## The game hub: a shell above the games. Boot lands here only when `hub_skipped()` is false (see SKIP_HUB).
const HUB_SCENE := "res://game/menus/game_hub.tscn"
## THE switch for skipping the hub (Night Watch is not ready, so Last Route is the only playable game).
## True: while exactly one game is unlocked, boot, the update screen and the locked-game bounces land on that game's menu
## (the Last Route menu), which then carries ACCOUNT / SETTINGS / ADMIN / QUIT itself. A second unlocked game (a `locked`
## flag flipped to false) brings the hub back by itself. False: today's behaviour exactly (boot lands on the hub, the menu's
## last button is BACK TO GAMES). Everything that decides where "the main menu" is asks `landing_scene()` / `hub_skipped()`.
const SKIP_HUB := true
## Tests: -1 follows SKIP_HUB, 0 forces it off, 1 forces it on (a const cannot be flipped at run time).
static var skip_hub_override := -1
const DEFAULT_ID := "last_route"
## The game whose menus are open (set when the hub launches one); settings and the controls tabs follow it.
static var active_game_id := "last_route":
	set(value):
		active_game_id = value
		Palette.apply_scheme(value)
## Per-run choice of what the hub opens when the player has used it before.
const SETTINGS_SECTION := "hub"


## What the shared account panel lists under SAVES for a game: {has_save, text}. Last Route reads its route checkpoint; any
## other game reads `games.<id>.summary` from the account document (the game writes it with
## Backend.account_save_game_progress), so a new game appears with no change to the panel.
static func save_summary(id: String) -> Dictionary:
	if id == "last_route":
		if Backend.has_route_checkpoint():
			var checkpoint := Backend.account_progress
			return {"has_save": true, "text": "DEPTH %d // SCORE %d // %s" % [int(checkpoint.get("depth", 1)),
				int(checkpoint.get("score", 0)), String(checkpoint.get("difficulty_id", "standard")).to_upper()]}
		return {"has_save": false, "text": "NONE"}
	var data := Backend.game_progress(id)
	if data.is_empty():
		return {"has_save": false, "text": "NONE"}
	return {"has_save": true, "text": String(data.get("summary", "SAVED")).to_upper()}


## Tests register a synthetic list (1..12 games) here; empty means the real GAMES.
static var test_games: Array = []


static func all() -> Array:
	return test_games if not test_games.is_empty() else GAMES


static func get_game(id: String) -> Dictionary:
	for game in all():
		if String(game["id"]) == id:
			return game
	return {}


static func is_launchable(id: String) -> bool:
	var game := get_game(id)
	return not game.is_empty() and (not bool(game["locked"]) or dev_unlocked(id)) and not String(game["scene"]).is_empty()


## A locked game with "dev_open" still opens for whoever may test it: a signed-in admin (the admin overlay's login), headless
## validation, or a debug build started with KYTTU_DEV set. Players see the locked card and cannot reach the scene by any path.
static func dev_unlocked(id: String) -> bool:
	var game := get_game(id)
	if game.is_empty() or not bool(game.get("dev_open", false)):
		return false
	return Build.tools_enabled() or (OS.is_debug_build() and OS.has_environment("KYTTU_DEV"))


## The card's line for a locked game: the note as written when it carries its own "//" label, else "LOCKED // note".
static func locked_line(game: Dictionary) -> String:
	var note := String(game.get("locked_note", ""))
	return note if note.contains("//") else "LOCKED // %s" % note


## Games a player can open: not `locked` (what the hub shows as PLAY). Dev-open games (Night Watch) are NOT counted, so an
## admin or a headless validator gets the same landing as a player; the boot decision is made before anyone signs in.
static func unlocked_ids() -> Array:
	var out := []
	for game in all():
		if not bool(game["locked"]) and not String(game["scene"]).is_empty():
			out.append(String(game["id"]))
	return out


static func skip_hub_enabled() -> bool:
	return SKIP_HUB if skip_hub_override < 0 else skip_hub_override == 1


## True when the hub is not the main menu right now: the switch is on and exactly one game is unlocked.
static func hub_skipped() -> bool:
	return skip_hub_enabled() and unlocked_ids().size() == 1


## The first scene after boot and where "back to the menu" lands when no specific game owns it: the sole unlocked game's
## menu while the hub is skipped, else the hub.
static func landing_scene() -> String:
	if hub_skipped():
		return String(get_game(String(unlocked_ids()[0]))["scene"])
	return HUB_SCENE


static func launchable_ids() -> Array:
	var out := []
	for game in all():
		if is_launchable(String(game["id"])):
			out.append(String(game["id"]))
	return out
