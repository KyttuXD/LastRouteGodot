class_name PlaytestAdapters
extends RefCounted

## Finds the bot adapter for a game id: the GameRegistry entry's "playtest_bot" script if it has one, else the built-in table
## below (so the City and Night Watch lanes can register their own adapter with one registry key and no edit here).

const BUILT_IN := {
	"last_route": "res://src/playtest/bots/last_route_bot.gd",
	"night_watch": "res://src/playtest/bots/night_watch_bot.gd",
}


static func script_path(game_id: String) -> String:
	var entry := GameRegistry.get_game(game_id)
	var from_registry := String(entry.get("playtest_bot", "")) if not entry.is_empty() else ""
	if not from_registry.is_empty():
		return from_registry
	return String(BUILT_IN.get(game_id, ""))


static func create(game_id: String, tree: SceneTree) -> BotAdapter:
	var path := script_path(game_id)
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	var adapter: BotAdapter = (load(path) as GDScript).new()
	adapter.game_id = game_id
	adapter.tree = tree
	return adapter


static func game_ids() -> Array:
	var ids: Array = []
	for id in BUILT_IN:
		ids.append(id)
	for game in GameRegistry.all():
		var id := String(game["id"])
		if not ids.has(id):
			ids.append(id)
	return ids
