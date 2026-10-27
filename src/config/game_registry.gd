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
## Per-run choice of what the hub opens when the player has used it before.
const SETTINGS_SECTION := "hub"


static func all() -> Array:
	return GAMES


static func get_game(id: String) -> Dictionary:
	for game in GAMES:
		if String(game["id"]) == id:
			return game
	return {}


static func is_launchable(id: String) -> bool:
	var game := get_game(id)
	return not game.is_empty() and not bool(game["locked"]) and not String(game["scene"]).is_empty()


static func launchable_ids() -> Array:
	var out := []
	for game in GAMES:
		if is_launchable(String(game["id"])):
			out.append(String(game["id"]))
	return out
