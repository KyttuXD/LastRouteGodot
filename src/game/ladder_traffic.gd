class_name LadderTraffic
extends RefCounted

## Who is on which sewer ladder (LevelLink kind "ladder"), for hunters and
## runners alike. Pure data so the host can simulate it and tests can drive it.
## One climber per ladder at a time: a second climber waits at the foot or the
## top until the first is off. A climb is a timed crossing from one level to the
## other; `progress` 0..1 runs from the start level's floor to the far level's.
##
## Ladder rungs span the full storey between the sewer floor and the maze floor.

const RISE := 4.0                       # StreamedFacilityView3D.LEVEL_HEIGHT
const BASE_CLIMB_RATE := 1.6            # metres per second for a hunter of base speed 0.8
const RUNNER_CLIMB_SECONDS := 2.4
## How close (cells) a body must be to the ladder cell's centre to get on it.
const MOUNT_DISTANCE := 0.95

var _occupant := {}                     # link id -> climber id
var _climbs := {}                       # climber id -> {link, from_level, to_level, seconds, elapsed}


static func climb_seconds_for_speed(base_speed: float) -> float:
	return RISE / (BASE_CLIMB_RATE * clampf(base_speed / 0.8, 0.6, 1.4))


func is_free(link_id: String, climber_id: String = "") -> bool:
	var who := String(_occupant.get(link_id, ""))
	return who.is_empty() or who == climber_id


func is_climbing(climber_id: String) -> bool:
	return _climbs.has(climber_id)


func climb_of(climber_id: String) -> Dictionary:
	return _climbs.get(climber_id, {})


## Starts a crossing from `from_level` if the ladder is free. Returns false
## (and changes nothing) while someone else is on it.
func begin(climber_id: String, link: Dictionary, from_level: int, seconds: float) -> bool:
	var link_id := String(link["id"])
	if not is_free(link_id, climber_id) or _climbs.has(climber_id):
		return false
	_occupant[link_id] = climber_id
	_climbs[climber_id] = {"link": link, "from_level": from_level,
		"to_level": int(LevelLink.other_end(link, from_level)["level"]),
		"seconds": maxf(seconds, 0.1), "elapsed": 0.0}
	return true


## Advances a crossing. Returns {"progress", "height", "done", "to_level", "cell"}.
## `height` is metres above the lower level's floor. A finished climb frees the ladder.
func advance(climber_id: String, delta: float) -> Dictionary:
	var climb: Dictionary = _climbs.get(climber_id, {})
	if climb.is_empty():
		return {}
	climb["elapsed"] = float(climb["elapsed"]) + delta
	var progress := clampf(float(climb["elapsed"]) / float(climb["seconds"]), 0.0, 1.0)
	var going_up := int(climb["to_level"]) > int(climb["from_level"])
	var link: Dictionary = climb["link"]
	var result := {"progress": progress, "height": RISE * (progress if going_up else 1.0 - progress),
		"done": progress >= 1.0, "to_level": int(climb["to_level"]), "from_level": int(climb["from_level"]),
		"cell": LevelLink.cell_on(link, int(climb["to_level"])), "chunk": link["chunk"], "link_id": link["id"]}
	if progress >= 1.0:
		release(climber_id)
	return result


func release(climber_id: String) -> void:
	var climb: Dictionary = _climbs.get(climber_id, {})
	if not climb.is_empty():
		_occupant.erase(String(climb["link"]["id"]))
	_climbs.erase(climber_id)


func clear() -> void:
	_occupant.clear()
	_climbs.clear()


## The ladder on `level` nearest to the global cell `near`, searching the chunk
## holding it and its eight neighbours. Returns {} when there is none.
static func nearest_ladder(generator: StreamedRouteGenerator, level: int, near: Vector2) -> Dictionary:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cx := floori(near.x / size)
	var cz := floori(near.y / size)
	var best := {}
	var best_d := INF
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var coord := Vector3i(cx + dx, level, cz + dz)
			for link_value in generator.sewer().links_for(coord):
				var link: Dictionary = link_value
				var cell := LevelLink.cell_on(link, level)
				if cell.x < 0:
					continue
				var at := ladder_point(link, level)
				var d := at.distance_squared_to(near)
				if d < best_d:
					best_d = d
					best = link
	return best


## Centre of the ladder cell on `level`, in global grid units.
static func ladder_point(link: Dictionary, level: int) -> Vector2:
	var chunk: Vector3i = link["chunk"]
	var cell := LevelLink.cell_on(link, level)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	return Vector2(chunk.x * size + cell.x + .5, chunk.z * size + cell.y + .5)
