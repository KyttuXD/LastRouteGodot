class_name NightWatchBot
extends BotAdapter

## Night Watch adapter stub. The Night Watch lane registers the real one (shift clock, doors/vents/camera/power policy) through
## GameRegistry's "playtest_bot" key; until then scenarios that need it are skipped.


func available() -> bool:
	return false


func start_run(_params: Dictionary) -> Dictionary:
	return {"ok": false, "error": "night_watch playtest bot not implemented yet (Night Watch lane: register a BotAdapter via GameRegistry 'playtest_bot')"}
