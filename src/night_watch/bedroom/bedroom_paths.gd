class_name BedroomPaths
extends RefCounted

## Javelle's way through the house wing: a waypoint graph (a centre per room, a point in every doorway, three points down the hall), AStar3D, so she WALKS from the
## living room up the hall to the bedroom door and back, never appearing in the doorway. Same route format as NightWatchPaths, so NightWatchWalker walks it.

var astar := AStar3D.new()
var points := {}
var _ids := {}
var _keys := {}


func _init() -> void:
	_build()


func _add(key: String, pos: Vector3) -> void:
	var id := astar.get_available_point_id()
	astar.add_point(id, pos)
	_ids[key] = id
	_keys[id] = key
	points[key] = pos


func _link(a: String, b: String) -> void:
	astar.connect_points(int(_ids[a]), int(_ids[b]), true)


func _hall_node_for(x: float) -> String:
	var best := "near"
	var best_d := 1e9
	for k in BedroomMap.HALL_NODES:
		var d := absf(float(BedroomMap.HALL_NODES[k]) - x)
		if d < best_d:
			best_d = d
			best = k
	return "H:%s" % best


func _build() -> void:
	for id in BedroomMap.ROOMS:
		if id != "hall":
			_add("C:%s" % id, BedroomMap.center(id))
	for k in BedroomMap.HALL_NODES:
		_add("H:%s" % k, Vector3(float(BedroomMap.HALL_NODES[k]), 0.0, -0.9))
	_link("H:near", "H:mid")
	_link("H:mid", "H:far")
	for e in BedroomMap.EDGES:
		var d := BedroomMap.door_between(e[0], e[1])
		var p: Vector2 = d["point"]
		var key := "D:%s|%s" % [e[0], e[1]]
		_add(key, Vector3(p.x, 0.0, p.y))
		if e[0] == "hall" or e[1] == "hall":
			var room: String = e[1] if e[0] == "hall" else e[0]
			_link("C:%s" % room, key)
			_link(key, _hall_node_for(p.x))
		else:
			_link("C:%s" % e[0], key)
			_link(key, "C:%s" % e[1])


func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	for id in astar.get_id_path(int(_ids[from_key]), int(_ids[to_key])):
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": false, "key": key})
	return out


## The route from wherever she stands to a waypoint key ("C:living_room", "H:mid", "H:near").
func legs_from(pos: Vector3, to_key: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), to_key)
