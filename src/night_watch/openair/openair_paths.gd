class_name NightWatchOpenAirPaths
extends RefCounted

## The waypoint graph Open Air's hunters walk, built the way NightWatchPaths builds the building's: named points (world positions) joined
## by edges, searched with AStar3D. The rules move a hunter a step at a time (a distance 3..0 on a side); the walker takes the visible
## time to get there, along the legs this returns ([{"p": Vector3, "jump": false, "key": String}], the format NightWatchWalker follows).
##
##   rooftop    L3..L0 and R3..R0: the catwalk up to the stair door (L) and the hatch (R); L3 and R3 are joined round the back of the
##              building, so a hunter sent back to the other door walks round to it.
##   campfire   V3..V0 (Verrine, the left trees to the edge of the light), Q3..Q0 (Quenelle, the right) and Y2..Y0 (Ysolde: the
##              trees, out of them, the log pile).
##   bus stop   one road: W0 (far down it) to W4 (at the shelter).

var astar := AStar3D.new()
var points := {}        # key -> Vector3
var _ids := {}
var _keys := {}


func add(key: String, pos: Vector3) -> void:
	var id := _ids.size()
	_ids[key] = id
	_keys[id] = key
	points[key] = pos
	astar.add_point(id, pos)


func link(a: String, b: String) -> void:
	astar.connect_points(int(_ids[a]), int(_ids[b]), true)


## A chain of points a-b-c-... each joined to the next.
func chain(keys: Array) -> void:
	for i in range(keys.size() - 1):
		link(String(keys[i]), String(keys[i + 1]))


func has_key(key: String) -> bool:
	return _ids.has(key)


func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	for id in astar.get_id_path(int(_ids[from_key]), int(_ids[to_key])):
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": false, "key": key})
	return out


## The route from wherever a hunter is standing now to a key: starts at the waypoint nearest to her.
func legs_from(pos: Vector3, to_key: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), to_key)


## Whether `to_key` can be walked to from `from_key`.
func reachable(from_key: String, to_key: String) -> bool:
	return not route(from_key, to_key).is_empty()
