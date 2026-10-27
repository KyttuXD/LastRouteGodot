class_name NightWatchPaths
extends RefCounted

## Pathfinding for the hunters: a waypoint graph over the building and the office hall, searched with AStar3D, so a hunter WALKS from room to
## room (through the carved doorways and across the lane the feed cameras look over) instead of being placed in the next room.
## Each room has three waypoints (C centre, S its open south mouth, L the lane point just outside it); same-row lane points are linked,
## doorways link neighbouring centres, and the north doorways link a room's lane to the room below. The two office doors have an outer
## waypoint (DO) a few metres down the hall; the leg from the last hall to DO is a `jump` (the hall and the office are far apart and the
## hunter is out of sight in the dark between them): the walker steps across it and walks the rest.
## `route()` returns [{"p": Vector3, "jump": bool}] from one waypoint to another; `legs_for()` builds the route between two sim rooms.

var astar := AStar3D.new()
var _ids := {}          # waypoint key -> astar id
var _keys := {}         # astar id -> key
var points := {}        # key -> Vector3 (world)
var _jumps := {}        # "a|b" -> true for a jump edge
var building: NightWatchBuilding
var office: NightWatchOffice

const SOUTH_MOUTH := 2.6
const LANE := 4.0
const DOOR_OUTER := 3.4   # how far beyond the first stand point the office door waypoint sits


func _init(b: NightWatchBuilding, o: NightWatchOffice) -> void:
	building = b
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
	for id in building.rooms:
		var c := (building.rooms[id] as Node3D).global_position
		_add("C:%s" % id, c)
		_add("S:%s" % id, c + Vector3(0, 0, SOUTH_MOUTH))
		_add("L:%s" % id, c + Vector3(0, 0, LANE))
		_link("C:%s" % id, "S:%s" % id)
		_link("S:%s" % id, "L:%s" % id)
	# neighbours in a row: the lane runs along the open south sides; a doorway in the shared wall links the centres
	var rows := {}
	for id in building.rooms:
		var g: Vector2i = NightWatchData.ROOMS[id]["grid"]
		rows[Vector2i(g.x, g.y)] = id
	for g in rows:
		var right := Vector2i(g.x + 1, g.y)
		if rows.has(right):
			_link("L:%s" % rows[g], "L:%s" % rows[right])
			if building.has_doorway("E", String(rows[g])) and building.has_doorway("W", String(rows[right])):
				_link("C:%s" % rows[g], "C:%s" % rows[right])
		var below := Vector2i(g.x, g.y + 1)
		if rows.has(below) and building.has_doorway("N", String(rows[below])):
			_link("L:%s" % rows[g], "C:%s" % rows[below])
	# the office doors hang off the halls: DO (down the hall) is one jump from the hall's lane point
	for door in ["doorL", "doorR"]:
		var hall := "westhall" if door == "doorL" else "easthall"
		var stand := office.global_position + office.door_stand(door, 0, 0.0)
		var outer := stand + Vector3(-1.0 if door == "doorL" else 1.0, 0.0, 0.0) * DOOR_OUTER
		_add("DO:%s" % door, outer)
		_add("D:%s" % door, stand)
		_link("L:%s" % hall, "DO:%s" % door, true)
		_link("DO:%s" % door, "D:%s" % door)


## The waypoint a sim room hangs from.
func key_for(room: String) -> String:
	return "D:%s" % room if room.begins_with("door") else "C:%s" % room


## The walk between two waypoints: [{"p": Vector3, "jump": bool}] (the first entry is the start itself).
func route(from_key: String, to_key: String) -> Array:
	var out := []
	if not _ids.has(from_key) or not _ids.has(to_key):
		return out
	var ids := astar.get_id_path(int(_ids[from_key]), int(_ids[to_key]))
	var last := ""
	for id in ids:
		var key := String(_keys[id])
		out.append({"p": points[key], "jump": _jumps.has("%s|%s" % [last, key]), "key": key})
		last = key
	return out


## The route a hunter takes when the sim moves her from one room to another.
func legs_for(from_room: String, to_room: String) -> Array:
	return route(key_for(from_room), key_for(to_room))


## Length of a route's walked legs (jumps do not count).
static func walked_length(legs: Array) -> float:
	var total := 0.0
	for i in range(1, legs.size()):
		if not bool(legs[i]["jump"]):
			total += (legs[i]["p"] as Vector3).distance_to(legs[i - 1]["p"])
	return total


## The route from wherever a hunter is standing now (not from a room's centre) to a sim room: starts at the waypoint nearest to her.
func legs_from(pos: Vector3, to_room: String) -> Array:
	var start := int(astar.get_closest_point(pos))
	if start < 0:
		return []
	return route(String(_keys[start]), key_for(to_room))
