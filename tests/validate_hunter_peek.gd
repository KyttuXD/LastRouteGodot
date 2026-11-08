extends RefCounted

## Corner peeking (HunterPeek, "make them peek from a corner, and either run/chase if they see something"). On an
## L corridor (east along row 5, turning south at x = 10): an investigating hunter stops behind the corner and leans out;
## her body stays behind the edge plane and out of sight of the hall while her head clears it; sight is taken from the
## head (a runner the body cannot see is spotted); a "burst" hunter then chases, an "ambush" hunter ducks back and
## chases when the runner comes round; an empty hall sends her back to searching; she never peeks mid-chase; the peek
## replicates through StreamedWorldState; harder modes react faster.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_peek

const STEP := 1.0 / 30.0
const EDGE_X := 10.0
const HALL := Vector2(10.5, 10.5)
const START := Vector2(3.5, 5.5)

var _failures := 0


class Corridor:
	var safe_zones: Array = []
	var exit_cell := Vector2i(-1, -1)
	var rooms: Array = []
	var relays: Array = []
	var vents: Array = []
	var hiding_spots: Array = []
	var start := Vector2i(3, 5)
	var _open := {}

	func _init() -> void:
		for x in range(2, 11):
			_open[Vector2i(x, 5)] = true
		for y in range(5, 16):
			_open[Vector2i(10, y)] = true

	func is_floor(x: float, y: float) -> bool:
		return _open.has(Vector2i(int(floor(x)), int(floor(y))))

	func can_occupy(x: float, y: float, radius: float = .23, _blocked = null) -> bool:
		for offset in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius)]:
			if not is_floor(x + offset.x, y + offset.y):
				return false
		return true

	func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
		var steps := int(ceil(from.distance_to(to) / .05))
		for i in range(steps + 1):
			var point := from.lerp(to, float(i) / maxf(1.0, float(steps)))
			if not is_floor(point.x, point.y):
				return false
		return true

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		if not _open.has(from) or not _open.has(to):
			return []
		var previous := {from: from}
		var queue: Array = [from]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			if cell == to:
				break
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = cell + d
				if _open.has(next) and not previous.has(next):
					previous[next] = cell
					queue.append(next)
		if not previous.has(to):
			return []
		var path: Array = [to]
		while path[0] != from:
			path.push_front(previous[path[0]])
		return path

	func floor_cells() -> Array:
		return _open.keys()

	func nearest_open_position(x: float, y: float, _radius: float = 1.0, _blocked = null) -> Dictionary:
		return {"x": x, "y": y}

	func room_at(_x: float, _y: float) -> Dictionary:
		return {}

	func get_safe_zone_blocked_cells() -> Dictionary:
		return {}

	func uncollected(list: Array) -> Array:
		return list


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _target(at: Vector2, hidden: bool) -> Dictionary:
	return {"peer_id": 1, "position": at, "hidden": hidden, "in_safe_zone": false, "noise": 0.0, "flashlight_on": true,
		"sprinting": false, "facing": Vector2(0, -1), "lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false}


func _brain(id: String, mode: String = "standard") -> HunterBrain:
	var brain := HunterBrain.new(START, "PEEK-%s-%s" % [id, mode], id, mode)
	brain.activate_at(Vector2(10.5, 14.5))   # investigating a noise down the hall: the route turns the corner
	brain.peek_chance_override = 1.0
	return brain


## Runs until `done` returns true or `seconds` pass; returns whether it finished.
func _run(brain: HunterBrain, field: Corridor, target: Dictionary, seconds: float, done: Callable) -> bool:
	for i in int(seconds / STEP):
		brain.update(STEP, field, target, 1, 0)
		if done.call():
			return true
	return false


func run(_host: Node) -> int:
	var field := Corridor.new()

	# 1. reaches the peek point, body behind the edge, head past it
	var brain := _brain("dovelle")
	var hidden_runner := _target(HALL, true)
	_expect(_run(brain, field, hidden_runner, 12.0, func() -> bool: return brain.state == HunterBrain.State.PEEK),
		"an investigating hunter never stopped to peek at the corner")
	_run(brain, field, hidden_runner, 3.0, func() -> bool: return brain.peeking_out())
	_expect(brain.peeking_out(), "the peek never leaned out")
	_expect(brain.position.x <= EDGE_X - GameConfig.HUNTER_RADIUS + .01,
		"her body (x %.2f) pokes past the corner edge at x %.1f" % [brain.position.x, EDGE_X])
	_expect(brain.peek_head.x > EDGE_X, "her head (x %.2f) does not clear the edge" % brain.peek_head.x)
	_expect(not field.has_line_of_sight(HALL, brain.position), "the hall can see her body round the corner")
	_expect(field.has_line_of_sight(HALL, brain.peek_head), "the hall cannot see her leaned-out head")
	_expect(brain.peek_dir == Vector2(0, 1), "she is not looking down the hall (%s)" % brain.peek_dir)

	# 2. an empty hall: she pulls back and carries on searching
	var withdrew := _run(brain, field, hidden_runner, 4.0, func() -> bool: return brain.state != HunterBrain.State.PEEK)
	_expect(withdrew and brain.state != HunterBrain.State.CHASE,
		"after an empty look she did not withdraw to searching (state %d)" % brain.state)
	_expect(brain.peek_cooldown > 0.0, "no cooldown after a peek")

	# 3. sight from the head spots a runner the body cannot see; a burst hunter chases
	brain = _brain("dovelle")
	var runner := _target(HALL, false)
	_run(brain, field, hidden_runner, 15.0, func() -> bool: return brain.peeking_out())
	_expect(not field.has_line_of_sight(brain.position, HALL), "test setup: her body already sees the hall")
	var react := float(HunterPeek.difficulty("standard")["react"])
	var chased := _run(brain, field, runner, react + .6,
		func() -> bool: return brain.state == HunterBrain.State.CHASE)
	_expect(chased, "a burst peeker saw the runner from her head and did not chase (state %d phase %d)"
		% [brain.state, brain.peek_phase])

	# 4. an ambusher ducks back, then chases when the runner comes round the corner
	brain = _brain("thessine")
	_run(brain, field, hidden_runner, 15.0, func() -> bool: return brain.peeking_out())
	_run(brain, field, runner, 1.0, func() -> bool: return brain.peek_phase == HunterBrain.Peek.AMBUSH)
	_expect(brain.state == HunterBrain.State.PEEK and brain.peek_phase == HunterBrain.Peek.AMBUSH and not brain.peeking_out(),
		"an ambusher who saw the runner did not duck back (state %d phase %d)" % [brain.state, brain.peek_phase])
	_expect(brain.sight_eye() == brain.position, "a ducked-back ambusher still looks from her head")
	var round_corner := _target(Vector2(10.5, 5.5), false)
	_expect(_run(brain, field, round_corner, 1.0, func() -> bool: return brain.state == HunterBrain.State.CHASE),
		"the ambusher did not chase a runner who came round the corner")
	brain = _brain("thessine")
	_run(brain, field, hidden_runner, 15.0, func() -> bool: return brain.peeking_out())
	_run(brain, field, runner, 1.0, func() -> bool: return brain.peek_phase == HunterBrain.Peek.AMBUSH)
	var waited := _run(brain, field, hidden_runner, float(HunterPeek.difficulty("standard")["ambush"]) + .5,
		func() -> bool: return brain.state != HunterBrain.State.PEEK)
	_expect(waited and brain.state == HunterBrain.State.INVESTIGATE and brain.last_known.distance_to(HALL) < .1,
		"an ambusher whose runner never came round did not go to where she saw them (state %d)" % brain.state)

	# 5. never mid-chase
	brain = _brain("dovelle")
	brain.state = HunterBrain.State.CHASE
	var chase_target := _target(Vector2(10.5, 14.5), false)
	var peeked := _run(brain, field, chase_target, 4.0, func() -> bool: return brain.state == HunterBrain.State.PEEK)
	_expect(not peeked, "a chasing hunter stopped to peek")

	# 6. replication: a guest brain restored from the host's state shows the same peek
	brain = _brain("dovelle")
	_run(brain, field, hidden_runner, 12.0, func() -> bool: return brain.peeking_out())
	var world := StreamedWorldState.new()
	world.store_hunter("h1", brain, 0, Vector3i.ZERO)
	var guest := HunterBrain.new(Vector2.ZERO, "PEEK-GUEST", "dovelle")
	world.restore_hunter(guest, world.hunter_state("h1"))
	_expect(guest.peeking_out() and guest.peek_head == brain.peek_head and guest.peek_side == brain.peek_side,
		"the peek does not replicate to guests")

	# 7. tuning: personalities and difficulty
	_expect(HunterPeek.chance("nyxie", "standard") > HunterPeek.chance("kathy", "standard") * 3.0,
		"Nyxie does not peek much more often than Kathy")
	_expect(HunterPeek.chance("opalie", "nightmare") == 0.0, "a stationary-rule hunter peeks")
	_expect(float(HunterPeek.difficulty("nightmare")["react"]) < float(HunterPeek.difficulty("hard")["react"])
		and float(HunterPeek.difficulty("hard")["react"]) < float(HunterPeek.difficulty("standard")["react"]),
		"harder modes do not react faster")
	_expect(HunterPeek.chance("dovelle", "nightmare") > HunterPeek.chance("dovelle", "standard"),
		"harder modes do not peek more")

	if _failures == 0:
		print("  hunter_peek  ok")
	return _failures
