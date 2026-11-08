class_name HunterLevelRoam
extends RefCounted

## Hunters changing level on their own (089, on Normal more hunters should also go up and down, not only the main
## floor). Pure rules, read by InfiniteRouteTest._hunter_ladder_step and validate_hunter_level_roam.
##
## Before: a hunter only took a level link to follow a runner, and only ladders and ramps (the stairwells to the decks
## above and to the sewer were never chosen, although LadderTraffic walks their `path`); on her own only the six sewer
## "prefer" hunters drifted, and only down from level 0. Now, while idle or wandering near a link, a hunter that is not
## sewer-shy rolls once per WINDOW seconds to take it, up or down, from any level, with a per-mode chance (Relaxed keeps
## the old rule exactly). After arriving she stays at least STAY seconds before she may roam again.

## Link kinds a hunter walks or climbs (an elevator, a drop or a vent grate is not hers).
const LINK_KINDS := ["ladder", "ramp", "stairs", "spiral"]
## Per difficulty: chance per WINDOW that an idle / wandering "follow" hunter near a link takes it ("prefer" ones at least
## PREFER_CHANCE, "avoid" ones never).
const CHANCE := {"relaxed": 0.0, "standard": .45, "hard": .5, "nightmare": .6}
const PREFER_CHANCE := 1.0 / 3.0
const WINDOW := 20.0
## A link this close (cells) is "near".
const REACH := 20.0
## Seconds a hunter stays on the level she roamed to before rolling again (no ping-pong on the same stairs).
const STAY := 60.0
## Seconds the roam plan may take to reach the link before it is dropped.
const PLAN_SECONDS := 25.0


static func chance(difficulty: String, affinity: String) -> float:
	if affinity == "avoid":
		return 0.0
	var base := float(CHANCE.get(difficulty, CHANCE["standard"]))
	return maxf(base, PREFER_CHANCE) if affinity == "prefer" else base


## Does this hunter roam to another level in this WINDOW? Deterministic from her entity id and the window index, so a
## replay (and the validator) gets the same answer. Relaxed keeps the pre-089 rule: only "prefer" hunters, only down from
## level 0, a one-in-three roll.
static func rolls(entity_id: String, difficulty: String, affinity: String, level: int, now: float) -> bool:
	var window := floori(now / WINDOW)
	if float(CHANCE.get(difficulty, CHANCE["standard"])) <= 0.0:
		return affinity == "prefer" and level == 0 and absi(hash("%s:%d" % [entity_id, window])) % 3 == 0
	var p := chance(difficulty, affinity)
	if p <= 0.0:
		return false
	var roll := float(absi(hash("%s:LEVEL-ROAM:%d" % [entity_id, window])) % 10000) / 10000.0
	return roll < p


## May a roam take `link` from `level`? Its other end must be a level the route has (is_chunk_allowed), and on Relaxed
## only the old way down from level 0.
static func link_ok(generator, link: Dictionary, level: int, difficulty: String) -> bool:
	if link.is_empty() or not LINK_KINDS.has(String(link.get("kind", ""))):
		return false
	var far := int(LevelLink.other_end(link, level)["level"])
	if far == level:
		return false
	if float(CHANCE.get(difficulty, CHANCE["standard"])) <= 0.0 and far > level:
		return false
	var chunk: Vector3i = link["chunk"]
	return generator == null or not generator.has_method("is_chunk_allowed") \
		or generator.is_chunk_allowed(Vector3i(chunk.x, far, chunk.z))
