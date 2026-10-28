class_name DeckPatches
extends RefCounted

## Where the Mezzanine decks (level +1) stand over the maze (KT: "catwalks over CERTAIN parts of the maze"): clustered
## patches of chunks, about COVERAGE of the maze, chosen by the seed with smooth value noise so each patch is a
## contiguous blob a few chunks across. Outside a patch level 0 keeps its ceilings and nothing is above it. Every patch
## has at least one spiral well up from level 0 (its anchor chunk, StreamedRouteGenerator._plan_maze_stairwell); the
## Mezzanine void (VoidRegion) joins any patch it touches through the catwalk cross, which runs to every chunk edge.

## Noise cell size in chunks: patches come out two to six chunks across.
const SCALE := 3.0
## value > THRESHOLD is a deck chunk: tuned so about 40% of chunks away from the spawn are decks.
const THRESHOLD := 0.575
## The spawn chunk and its ring stay under a ceiling.
const SPAWN_CLEAR := 1

static var _corners := {}


static func _corner(world_seed: String, ix: int, iz: int) -> float:
	var key := "%s:%d:%d" % [world_seed, ix, iz]
	if not _corners.has(key):
		if _corners.size() > 4096:
			_corners.clear()
		_corners[key] = SeededRandom.new("%s:DECKS:%d:%d" % [world_seed, ix, iz]).next_float()
	return float(_corners[key])


static func value(world_seed: String, x: int, z: int) -> float:
	var fx := (float(x) + .5) / SCALE
	var fz := (float(z) + .5) / SCALE
	var ix := floori(fx)
	var iz := floori(fz)
	var tx := smoothstep(0.0, 1.0, fx - float(ix))
	var tz := smoothstep(0.0, 1.0, fz - float(iz))
	var top := lerpf(_corner(world_seed, ix, iz), _corner(world_seed, ix + 1, iz), tx)
	var bottom := lerpf(_corner(world_seed, ix, iz + 1), _corner(world_seed, ix + 1, iz + 1), tx)
	return lerpf(top, bottom, tz)


## True when chunk column (x, z) carries a +1 deck (the void's own columns are the void's business).
static func is_deck(world_seed: String, x: int, z: int) -> bool:
	if absi(x) <= SPAWN_CLEAR and absi(z) <= SPAWN_CLEAR:
		return false
	return value(world_seed, x, z) > THRESHOLD
