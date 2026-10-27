class_name CityRunSave
extends RefCounted

## The City's run save: a small JSON-safe checkpoint stored in the shared account under `games.city` (Backend.
## account_save_game_progress), so it shows in the account panel's SAVES section and the City menu offers CONTINUE / CLEAR.
## It keeps the run's progress (score, coins, relays, which pickups are gone) and where the runner stood; hunters, doors
## and the day's weather start fresh. Solo and host-with-no-guests runs write it; it is cleared when the dome gate opens.

const SCHEMA := 1
const KIND := "city_run"
const MAX_CLAIMS := 600


static func make(seed_text: String, difficulty_id: String, score: int, coins: int, relays: int, sabotaged: int,
		claimed: Array, position: Vector3, yaw: float) -> Dictionary:
	var ids: Array = []
	for value in claimed:
		if ids.size() >= MAX_CLAIMS:
			break
		ids.append(String(value))
	return {
		"schema": SCHEMA, "kind": KIND,
		"seed_text": seed_text, "difficulty_id": difficulty_id,
		"score": score, "coins": coins, "relays": relays, "sabotaged": sabotaged,
		"claimed": ids,
		"x": snappedf(position.x, 0.01), "z": snappedf(position.z, 0.01), "yaw": snappedf(yaw, 0.001),
		"saved_at": int(Time.get_unix_time_from_system()),
		"summary": "%d RELAYS // %d COINS // %s" % [relays, coins, difficulty_id.to_upper()],
	}


static func valid(data: Dictionary) -> bool:
	if int(data.get("schema", 0)) != SCHEMA or String(data.get("kind", "")) != KIND:
		return false
	if String(data.get("seed_text", "")).is_empty() or not data.get("claimed") is Array:
		return false
	var gx := float(data.get("x", 1e9)) + CityLayout.ORIGIN_OFFSET.x
	var gz := float(data.get("z", 1e9)) + CityLayout.ORIGIN_OFFSET.y
	return gx >= 0.0 and gz >= 0.0 and gx < CityLayout.WIDTH and gz < CityLayout.HEIGHT
