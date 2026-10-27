class_name CityBot
extends BotAdapter

## KYTTU: The City adapter. The City lane registers the real one through GameRegistry's "playtest_bot" key (same BotAdapter
## interface as LastRouteBot); until the City scene exists this stub reports itself unavailable so scenarios skip cleanly.


func available() -> bool:
	return false


func start_run(_params: Dictionary) -> Dictionary:
	return {"ok": false, "error": "city playtest bot not implemented yet (City lane: register a BotAdapter via GameRegistry 'playtest_bot')"}
