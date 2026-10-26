class_name PublicRoster
extends RefCounted

## Hunter rules of the persistent PUBLIC route (the Godot twin of the 2D build's
## src/game/hunter-roster.js public helpers): the UTC day picks a stable featured
## pair, the rest of the lineup is a weighted draw mixed with the day, and the
## number of hunters scales with the players online.

const WEIGHTS := {"easy": .50, "intermediate": .40, "difficult": .10}
const FEATURED_COUNT := 2
const PLAYERS_PER_EXTRA_HUNTER := 2
const CAP := 8


## "YYYY-MM-DD" in UTC; the lineup reshuffles at 00:00 UTC.
static func day_key(unix_seconds: float = -1.0) -> String:
	var seconds := int(unix_seconds) if unix_seconds >= 0.0 else int(Time.get_unix_time_from_system())
	return Time.get_date_string_from_unix_time(seconds)


## 1 + floor((players - 1) / 2), clamped to 1..CAP: 1-2 players run 1 hunter, 3-4 run 2...
static func target_count(players: int) -> int:
	return clampi(1 + (maxi(1, players) - 1) / PLAYERS_PER_EXTRA_HUNTER, 1, CAP)


static func _pool() -> Array:
	var pool: Array = []
	for id in StreamedRouteGenerator.STREAMED_HUNTER_IDS:
		pool.append(String(id))
	return pool


## Weighted draw without replacement, deterministic for a given seed text.
static func draw(seed_text: String, pool: Array, count: int) -> Array:
	var rng := SeededRandom.new(seed_text)
	var remaining := pool.duplicate()
	var picked: Array = []
	while picked.size() < count and not remaining.is_empty():
		var total := 0.0
		for id in remaining:
			total += float(WEIGHTS.get(String(HunterRoster.get_identity(id).get("tier", "easy")), .3))
		var roll := rng.next_float() * total
		var chosen := remaining.size() - 1
		for index in remaining.size():
			roll -= float(WEIGHTS.get(String(HunterRoster.get_identity(remaining[index]).get("tier", "easy")), .3))
			if roll <= 0.0:
				chosen = index
				break
		picked.append(remaining.pop_at(chosen))
	return picked


## The day's featured pair depends on the date alone, so every client agrees.
static func featured(day: String = "") -> Array:
	return draw("PUBLIC-FEATURED:%s" % (day if not day.is_empty() else day_key()),
		_pool(), FEATURED_COUNT)


## Featured pair first, then the day-mixed weighted draw of everyone else.
static func lineup(seed_text: String, day: String = "") -> Array:
	var today := day if not day.is_empty() else day_key()
	var first := featured(today)
	var rest := _pool().filter(func(id) -> bool: return not first.has(id))
	return first + draw("%s:DAY-%s:LINEUP" % [seed_text, today], rest, rest.size())
