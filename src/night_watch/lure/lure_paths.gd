class_name LurePaths
extends RefCounted

## Pathfinding for Xivvy in Dead Air: a waypoint graph over the hall (each room has C its centre, S its open south mouth and L the lane point
## just outside it), AStar3D, so she WALKS from room to room through the doorways. Same-row lane points are linked, a doorway in a shared
## wall links the two centres, and a north doorway links the lane above to the room below. Each vent hangs off its office door: the leg from
## the vent's lane point to the door's outer waypoint (DO) is a `jump` (the duct and the office are far apart and she is out of sight), then
## she walks down the hall to the vent opening (D). Same route format as NightWatchPaths, so NightWatchWalker walks it.

const SOUTH_MOUTH := 2.6
const LANE := 4.0
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
	var at := {}
	for id in world.rooms:
		var c := (world.rooms[id] as Node3D).global_position
		_add("C:%s" % id, c)
		_add("S:%s" % id, c + Vector3(0, 0, SOUTH_MOUTH))
		_add("L:%s" % id, c + Vector3(0, 0, LANE))
		_link("C:%s" % id, "S:%s" % id)
		_link("S:%s" % id, "L:%s" % id)
		at[LureData.INFO[id]["grid"]] = id
	for g in at:
		var right: Vector2i = g + Vector2i(1, 0)
		if at.has(right):
			_link("L:%s" % at[g], "L:%s" % at[right])
			if world.has_doorway("E", String(at[g])) and world.has_doorway("W", String(at[right])):
				_link("C:%s" % at[g], "C:%s" % at[right])
		var below: Vector2i = g + Vector2i(0, 1)
		if at.has(below) and world.has_doorway("N", String(at[below])):
			_link("L:%s" % at[g], "C:%s" % at[below])
	for door in ["doorL", "doorR"]:
		var vent := "ventl" if door == "doorL" else "ventr"
		var stand := office.global_position + office.door_stand(door, 0, 0.0)
		var outer := stand + Vector3(-1.0 if door == "doorL" else 1.0, 0.0, 0.0) * DOOR_OUTER
		_add("DO:%s" % door, outer)
		_add("D:%s" % door, stand)
		_link("L:%s" % vent, "DO:%s" % door, true)
		_link("DO:%s" % door, "D:%s" % door)


## The waypoint a sim room hangs from (the vent openings are the office doors).
func key_for(room: String) -> String:
	if room == "officeL":
		return "D:doorL"
	if room == "officeR":
		return "D:doorR"
	return "C:%s" % room


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
