extends RefCounted

## Locker inspection (HunterInspect; KT: the trailer's "locker breath" shot for every hunter, "100% from different
## directions"). Every route hunter, with her real gimmick, against a locker set in a back wall in all 4 facings and
## approached from both sides along the hall: she must walk up, line up face-to-slats at her stand point (body clear of
## the locker and the walls), lean, linger, straighten and walk on without catching the hider. Any hunter that cannot
## do that every time must be in HunterInspect.EXCLUDED, and every excluded hunter must actually fail (so the list is
## exact). Two in a wardrobe (HideOccupancy): she inspects with both inside, from every facing, finds neither, and her
## check pulls the front one (slot 0, nearest the door) first. Also: the trigger rules, the hide check unchanged, difficulty tuning, Nyxie's easter egg, replication, pose.
##
##   godot --headless --path . res://scenes/validate.tscn -- locker_inspect

const STEP := 1.0 / 30.0
const LOCKER := Vector2i(10, 10)
const FACINGS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var _failures := 0


## A 20 x 20 room with a back wall through the locker's row, the locker cell itself solid (it is furniture).
class Hall:
	var safe_zones: Array = []
	var exit_cell := Vector2i(-1, -1)
	var rooms: Array = []
	var relays: Array = []
	var vents: Array = []
	var hiding_spots: Array = []
	var music_boxes: Array = []
	var batteries: Array = []
	var cols := 20
	var rows := 20
	var start := Vector2i(10, 15)
	var _solid := {}

	func _init(locker: Vector2i, door: Vector2i) -> void:
		var along := Vector2i(door.y, door.x)   # the wall runs across the door direction
		for k in range(-9, 10):
			_solid[locker - door + along * k] = true
		_solid[locker] = true
		for k in range(-9, 10):   # lockers in a row: the cells either side of it are cabinets too
			if absi(k) == 1:
				_solid[locker + along * k] = true

	func is_floor(x: float, y: float) -> bool:
		var cell := Vector2i(int(floor(x)), int(floor(y)))
		return cell.x >= 1 and cell.y >= 1 and cell.x < 20 and cell.y < 20 and not _solid.has(cell)

	func can_occupy(x: float, y: float, radius: float = .23, _blocked = null) -> bool:
		for offset in [Vector2.ZERO, Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, radius), Vector2(0, -radius),
				Vector2(radius, radius) * .7, Vector2(-radius, radius) * .7, Vector2(radius, -radius) * .7, Vector2(-radius, -radius) * .7]:
			if not is_floor(x + offset.x, y + offset.y):
				return false
		return true

	func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
		var steps := int(ceil(from.distance_to(to) / .1))
		for i in range(steps + 1):
			var point := from.lerp(to, float(i) / maxf(1.0, float(steps)))
			if not is_floor(point.x, point.y):
				return false
		return true

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		if not is_floor(to.x + .5, to.y + .5):
			return []
		var previous := {from: from}
		var queue: Array = [from]
		while not queue.is_empty():
			var cell: Vector2i = queue.pop_front()
			if cell == to:
				break
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = cell + d
				if is_floor(next.x + .5, next.y + .5) and not previous.has(next):
					previous[next] = cell
					queue.append(next)
		if not previous.has(to):
			return []
		var path: Array = [to]
		while path[0] != from:
			path.push_front(previous[path[0]])
		return path

	func floor_cells() -> Array:
		var cells: Array = []
		for x in range(1, 20):
			for y in range(1, 20):
				if is_floor(x + .5, y + .5):
					cells.append(Vector2i(x, y))
		return cells

	func nearest_open_position(x: float, y: float, _radius: float = 1.0, _blocked = null) -> Dictionary:
		return {"x": x, "y": y}

	func room_at(_x: float, _y: float) -> Dictionary:
		return {}

	func get_safe_zone_blocked_cells() -> Dictionary:
		return {}

	func uncollected(list: Array) -> Array:
		return list

	func hiding_exit_position(spot: Dictionary) -> Vector2:
		return Vector2(float(spot.get("x", 10)) + .5, float(spot.get("y", 10)) + .5)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _hider(at: Vector2, peer: int = 1, slot: int = 0) -> Dictionary:
	return {"peer_id": peer, "hide_slot": slot, "position": at, "hidden": true, "hiding_spot": LOCKER, "in_safe_zone": false, "noise": 0.0,
		"flashlight_on": true, "sprinting": false, "facing": Vector2(1, 0), "lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false, "in_vent": false}


## One trial: returns "" on success, else what went wrong. `pair`: two runners share the spot (a wardrobe), and the
## brain's target alternates between them frame by frame, as the host's nearest-target pick can.
func _trial(id: String, door: Vector2i, side: int, pair: bool = false) -> String:
	var field := Hall.new(LOCKER, door)
	var centre := Vector2(LOCKER) + Vector2(.5, .5)
	var along := Vector2(door.y, door.x) * float(side)
	var lane := centre + Vector2(door) * 2.0
	var brain := HunterBrain.new(lane - along * 5.0, "LOCKER-%s-%s-%d" % [id, door, side], id, "standard")
	if id == "nyxie":
		brain.gimmick = null   # her darkness rule keeps her inert or chasing; the easter egg is the brain's rule
	brain.activate_at(brain.position)
	brain.state = HunterBrain.State.WANDER
	brain.wander_target = lane + along * 5.0
	brain.has_wander_target = true
	brain.facing = along
	var started := false
	var clock := 0.0
	var linger_at := Vector2.INF
	var linger_facing := Vector2.ZERO
	var clear := true
	var phases: Array = []
	while clock < 30.0:
		clock += STEP
		if not started and HunterInspect.qualifies(brain, centre, false):
			if not brain.start_inspect(centre, Vector2(door), field):
				return "no stand clears her"
			started = true
		var hider := _hider(centre, 2, 1) if pair and int(clock / STEP) % 2 == 1 else _hider(centre)
		if brain.update(STEP, field, hider, 1, 0):
			return "caught a hider" if pair else "caught the hider"
		if started and brain.state != HunterBrain.State.INSPECT:
			break
		if brain.state == HunterBrain.State.INSPECT:
			if phases.is_empty() or phases[-1] != brain.inspect_phase:
				phases.append(brain.inspect_phase)
			if brain.inspect_phase == HunterBrain.Inspect.LINGER:
				linger_at = brain.position
				linger_facing = brain.facing
			if brain.inspect_phase != HunterBrain.Inspect.WALK and not field.can_occupy(brain.position.x, brain.position.y, brain.radius):
				clear = false
	if not started:
		return "never came within reach (state %d at %s)" % [brain.state, brain.position]
	if phases != [HunterBrain.Inspect.WALK, HunterBrain.Inspect.TURN, HunterBrain.Inspect.LEAN, HunterBrain.Inspect.LINGER, HunterBrain.Inspect.RISE]:
		return "phases %s (state %d)" % [phases, brain.state]
	if linger_at.distance_to(brain.inspect_stand) > .15:
		return "lingered %.2f m off her stand" % linger_at.distance_to(brain.inspect_stand)
	if linger_facing.dot(-Vector2(door)) < .97:
		return "not face-to-slats (%s)" % linger_facing
	if not clear:
		return "her body clipped the locker or a wall"
	if (linger_at - centre).dot(Vector2(door)) < HunterInspect.STAND_MIN - .01:
		return "stood too close to the locker"
	if brain.state != HunterBrain.State.WANDER:
		return "did not move on (state %d)" % brain.state
	return ""


func run(_host: Node) -> int:
	# trigger rules
	var field := Hall.new(LOCKER, Vector2i(1, 0))
	var centre := Vector2(LOCKER) + Vector2(.5, .5)
	var brain := HunterBrain.new(centre + Vector2(2, 1.5), "LOCKER-RULES", "dovelle", "standard")
	brain.activate_at(brain.position)
	brain.state = HunterBrain.State.WANDER
	_expect(HunterInspect.qualifies(brain, centre, false), "a wandering hunter passing a locker does not qualify")
	_expect(not HunterInspect.qualifies(brain, centre, true), "a hunter who saw the runner hide inspects instead of checking")
	brain.state = HunterBrain.State.CHASE
	_expect(not HunterInspect.qualifies(brain, centre, false), "a chasing hunter stops to inspect")
	_expect(HunterBrain.hide_check_triggers(HunterBrain.State.INVESTIGATE, true, centre, centre + Vector2(1, 0), centre),
		"the hide check no longer fires for a hunter who trailed the runner in")
	_expect(HunterInspect.slatted("") and HunterInspect.slatted("wardrobe") and not HunterInspect.slatted("bed"), "slatted rule")
	# tuning
	var standard := HunterInspect.difficulty("standard")
	var nightmare := HunterInspect.difficulty("nightmare")
	_expect(float(nightmare["linger"]) > float(standard["linger"]) and float(nightmare["cooldown"]) < float(standard["cooldown"])
		and HunterInspect.chance("dovelle", "nightmare") > HunterInspect.chance("dovelle", "standard"), "difficulty tuning is flat")
	_expect(HunterInspect.chance("nyxie", "standard") < HunterInspect.chance("dovelle", "standard")
		and float(HunterInspect.tuning("nyxie")["stand"]) < float(HunterInspect.tuning("dovelle")["stand"])
		and HunterInspect.linger("nyxie", "standard") > HunterInspect.linger("dovelle", "standard")
		and int(HunterInspect.tuning("nyxie")["breaths"]) > 1, "Nyxie's easter egg is not rarer, closer and longer")
	_expect(NightWatchPoses.has_pose("locker_lean"), "no locker_lean pose")

	# every hunter x 4 facings x 2 approach sides
	var ids: Array = HunterRoster.IMPLEMENTED_IDS + HunterRoster.VOID_IDS + ["nyxie"]
	var failing := {}
	var trials := 0
	var passed := 0
	for id in ids:
		for door in FACINGS:
			for side in [1, -1]:
				trials += 1
				var why := _trial(id, door, side)
				if why.is_empty():
					passed += 1
				elif not failing.has(id):
					failing[id] = "door %s side %d: %s" % [door, side, why]
	for id in failing:
		_expect(id in HunterInspect.EXCLUDED, "%s cannot inspect reliably (%s) and is not excluded" % [id, failing[id]])
	for id in HunterInspect.EXCLUDED:
		_expect(failing.has(id), "%s is excluded but passes every facing and side (drop it from EXCLUDED)" % id)
	print("  locker_inspect  %d of %d trials (%d hunters x 4 facings x 2 sides); excluded: %s" % [passed, trials, ids.size(),
		", ".join(HunterInspect.EXCLUDED)])
	for id in failing:
		print("    %s: %s" % [id, failing[id]])

	# two in a wardrobe: every facing and side, neither is found; the check takes the one nearest the door first
	for door in FACINGS:
		for side in [1, -1]:
			var why := _trial("dovelle", door, side, true)
			_expect(why.is_empty(), "with two in the wardrobe (door %s side %d): %s" % [door, side, why])
	var inside := [{"peer": 2, "slot": 1}, {"peer": 1, "slot": 0}]
	_expect(int(HideOccupancy.grab_order(inside)[0]["peer"]) == 1 and int(HideOccupancy.grab_order(inside)[1]["peer"]) == 2,
		"the check does not pull the front occupant first, then the back one")

	# replication
	var lean := Hall.new(LOCKER, Vector2i(1, 0))
	brain = HunterBrain.new(centre + Vector2(2, 0), "LOCKER-SYNC", "dovelle", "standard")
	brain.activate_at(brain.position)
	brain.start_inspect(centre, Vector2(1, 0), lean)
	for i in int(12.0 / STEP):
		brain.update(STEP, lean, _hider(centre), 1, 0)
		if brain.inspecting_close():
			break
	var world := StreamedWorldState.new()
	world.store_hunter("h1", brain, 0, Vector3i.ZERO)
	var guest := HunterBrain.new(Vector2.ZERO, "LOCKER-GUEST", "dovelle")
	world.restore_hunter(guest, world.hunter_state("h1"))
	_expect(guest.inspecting_close() and guest.inspect_stand == brain.inspect_stand and guest.inspect_face == brain.inspect_face,
		"the inspection does not replicate")
	if _failures == 0:
		print("  locker_inspect  ok")
	return _failures
