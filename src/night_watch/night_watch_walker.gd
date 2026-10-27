class_name NightWatchWalker
extends RefCounted

## One hunter's visible movement: it follows a route from NightWatchPaths at a walking pace (faster when the sim has her on a short
## window), faces where she is going, and when she has arrived follows `final` (the stand spot, which creeps closer at a door) and
## turns to face `look`. `moving` says whether the walk clip should play. Nothing here touches the sim: she is already in the new room
## as far as the rules go; the walker just takes the visible time to get there.

const WALK_SPEED := 2.3
const RUN_SPEED := 5.5
const ARRIVE_SECONDS := 2.0   # a route is walked within about this long, as fast as RUN_SPEED allows

var pos := Vector3.ZERO
var yaw := 0.0
var room := ""
var moving := false
var running := false
var final := Vector3.ZERO
var look := Vector3.ZERO
var _queue: Array = []
var _speed := WALK_SPEED


func place(p: Vector3, f: Vector3, l: Vector3, room_id: String) -> void:
	pos = p
	final = f
	look = l
	room = room_id
	_queue.clear()
	moving = false
	_face(l - p)


## The sim moved her to `to_room`: take `legs` (from NightWatchPaths) to it.
func go(legs: Array, to_room: String, f: Vector3) -> void:
	room = to_room
	final = f
	_queue.clear()
	if legs.is_empty():
		pos = f
		return
	# start from where she is now: skip the legs behind her, walk to the first waypoint that still lies ahead
	for i in legs.size():
		_queue.append(legs[i])
	var length := NightWatchPaths.walked_length(legs) + pos.distance_to(legs[0]["p"] if not bool(legs[0]["jump"]) else pos)
	_speed = clampf(length / ARRIVE_SECONDS, WALK_SPEED, RUN_SPEED)
	running = _speed > WALK_SPEED * 1.6


func is_walking() -> bool:
	return not _queue.is_empty()


## Advance by `delta` seconds; returns true while she is on the move.
func step(delta: float) -> bool:
	var budget := delta
	moving = false
	while budget > 0.0 and not _queue.is_empty():
		var leg: Dictionary = _queue[0]
		var target: Vector3 = leg["p"]
		if bool(leg["jump"]):
			pos = target
			_queue.pop_front()
			continue
		var d := target - pos
		d.y = 0.0
		var dist := d.length()
		var move := _speed * budget
		moving = true
		_face(d)
		if move >= dist:
			pos = Vector3(target.x, pos.y, target.z)
			budget -= dist / _speed
			_queue.pop_front()
		else:
			pos += d / dist * move
			budget = 0.0
	if _queue.is_empty():
		# arrived: shuffle to the stand spot (it moves at a door) and face what she looks at
		var to_final := final - pos
		to_final.y = 0.0
		if to_final.length() > 0.02:
			var move2 := minf(to_final.length(), WALK_SPEED * 0.5 * delta)
			pos += to_final.normalized() * move2
			moving = move2 > 0.001
		else:
			pos = final
		pos.y = final.y
		if not moving:
			_face(look - pos)
	return moving


func _face(d: Vector3) -> void:
	d.y = 0.0
	if d.length() > 0.01:
		yaw = atan2(d.x, d.z) + PI   # the blocky models' front is -Z
