class_name LurePaths
extends RefCounted

## Pathfinding for Xivvy in Dead Air: a waypoint graph over the station (a centre per room and a point in each doorway between rooms, from LureMap), AStar3D, so she
## WALKS from room to room through the doorways. Each crawlspace hangs off its office vent: the leg from the crawlspace to the vent's outer waypoint (DO) is a `jump`
## (the crawlspace and the booth are far apart and she is out of sight), then she walks down the duct to the vent opening (D). Same route format as NightWatchPaths,
## so NightWatchWalker walks it.

const DOOR_OUTER := 3.4

var astar := AStar3D.new()
var points := {}
var _ids := {}
var _keys := {}
var _jumps := {}
var world: LureWorld
var office: LureOffice


func _init(w: LureWorld, o: LureOffice) -> void:
	world = w
	office = o
	_build()


func _add(key: String, pos: Vector3) -> void:
	var id := astar.get_available_point_id()
	astar.add_point(id, pos)
	_ids[key] = id
	_keys[id] = key
	points[key] = pos


func _link(a: String, b: String, jump := false) -> void:
	astar.connect_points(int(_ids[a]), int(_ids[b]), true)
	if jump:
		_jumps["%s|%s" % [a, b]] = true
		_jumps["%s|%s" % [b, a]] = true


func _build() -> void:
	for map_id in LureMap.ROOMS:
		_add("C:%s" % map_id, LureMap.center(map_id))
	for e in LureMap.EDGES:
		var d := LureMap.door_between(e[0], e[1])
		var p: Vector2 = d["point"]
		var key := "D:%s|%s" % [e[0], e[1]]
		_add(key, LureMap.ORIGIN + Vector3(p.x, 0.0, p.y))
		_link("C:%s" % e[0], key)
		_link(key, "C:%s" % e[1])
	for door in ["doorL", "doorR"]:
		var crawl := "crawl_l" if door == "doorL" else "crawl_r"
		var stand := office.global_position + office.door_stand(door, 0, 0.0)
		var outer := stand + Vector3(-1.0 if door == "doorL" else 1.0, 0.0, 0.0) * DOOR_OUTER
		_add("DO:%s" % door, outer)
		_add("D:%s" % door, stand)
		_link("C:%s" % crawl, "DO:%s" % door, true)
		_link("DO:%s" % door, "D:%s" % door)


## The waypoint a sim room hangs from (the vent openings are the office vents).
func key_for(room: String) -> String:
	if room == "officeL":
		return "D:doorL"
	if room == "officeR":
		return "D:doorR"
	return "C:%s" % LureMap.sim_to_map(room)


func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	var last := ""
	for id in astar.get_id_path(int(_ids[from_key]), int(_ids[to_key])):
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": _jumps.has("%s|%s" % [last, key]), "key": key})
		last = key
	return out


func legs_for(from_room: String, to_room: String) -> Array:
	return route(key_for(from_room), key_for(to_room))


## The route from wherever she is standing now to a sim room.
func legs_from(pos: Vector3, to_room: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), key_for(to_room))
