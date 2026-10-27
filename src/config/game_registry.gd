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
		"scene": "res://scenes/main_menu.tscn",
		"theme": "res://src/ui/theme_lastroute.tres",
		"locked": false,
		"locked_note": "",
	},
	{
		"id": "night_watch",
		"title": "NIGHT WATCH",
		"kicker": "CAMERA FEED // OVERNIGHT SHIFT",
		"tagline": "Hold the desk through the night. Watch the feeds, keep them out.",
		"scene": "",
		"theme": "res://src/ui/theme_nightwatch.tres",
		"locked": true,
		"locked_note": "3D PORT IN PLANNING // SEE docs/GAME_HUB.md",
	},
]

## The hub is the main menu: the first screen after boot and the one every game returns to.
const HUB_SCENE := "res://scenes/game_hub.tscn"
const DEFAULT_ID := "last_route"
## The game whose menus are open (set when the hub launches one); settings and the controls tabs follow it.
static var active_game_id := "last_route"
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
	return not game.is_empty() and not bool(game["locked"]) and not String(game["scene"]).is_empty()


static func launchable_ids() -> Array:
	var out := []
	for game in all():
		if is_launchable(String(game["id"])):
			out.append(String(game["id"]))
	return out
