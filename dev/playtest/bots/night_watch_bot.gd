class_name NightWatchBot
extends BotAdapter

## Night Watch adapter stub. The real one is registered by the Night Watch mode (shift clock, doors/vents/camera/power policy) through
## GameRegistry's "playtest_bot" key; until then scenarios that need it are skipped.


func available() -> bool:
	return false


func start_run(_params: Dictionary) -> Dictionary:
	return {"ok": false, "error": "night_watch playtest bot not implemented yet (Night Watch mode: register a BotAdapter via GameRegistry 'playtest_bot')"}
