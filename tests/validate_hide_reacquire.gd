extends RefCounted

## "opalie saw me, i hid in a locker, and now shes walking away even if i go up close". Every hunter on a real
## facility: she sees the runner and chases, the runner hides and she gives up the chase, then the runner steps out and
## stands 2-3 m from her in plain view, torch on, walking noise. She must be chasing (or have caught them) within
## REACQUIRE_LIMIT seconds. Every hunter must commit to that first chase except NO_OPEN_CHASE, whose rules never chase a
## runner simply for being in view (so a guard or objective rule that swallows the chase, like Opalie's did, fails here).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hide_reacquire

const STEP := 1.0 / 30.0
const REACQUIRE_LIMIT := 2.0
const HIDE_SECONDS := 12.0
const DIRECTIONS := [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1),
	Vector2(.707, .707), Vector2(-.707, .707), Vector2(.707, -.707), Vector2(-.707, -.707)]

## Wynelle and Gray Void are dormant until their own trigger; Haelith and Ysolde go where the relays/batteries are;
## Verrine waits in the vents; Zellia is a merchant who never reacts.
const NO_OPEN_CHASE := ["wynelle", "haelith", "ysolde", "verrine", "zellia", "void_gray"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _target(position: Vector2, hidden: bool, noise: float) -> Dictionary:
	return {"peer_id": 1, "position": position, "hidden": hidden, "in_safe_zone": false, "noise": noise,
		"flashlight_on": true, "sprinting": false, "facing": Vector2(-1, 0), "lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false}


## A floor point 2-3 m from `from` in plain sight, or `from` itself when none fits.
func _visible_near(generator: FacilityGenerator, from: Vector2) -> Vector2:
	for distance in [3.0, 2.5, 2.0]:
		for direction in DIRECTIONS:
			var point: Vector2 = from + direction * distance
			if generator.is_floor(point.x, point.y) and generator.can_occupy(point.x, point.y) \
					and generator.has_line_of_sight(from, point):
				return point
	return from


func run(_host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "HIDE-REACQUIRE"
	var generator := FacilityGenerator.new("HIDE-REACQUIRE", RoomState.generator_options())
	var hider := Vector2.ZERO
	var start := Vector2.ZERO
	for cell in generator.floor_cells():
		var at := Vector2(cell.x + .5, cell.y + .5)
		var near := _visible_near(generator, at)
		if near != at:
			hider = at
			start = near
			break
	if hider == start:
		_expect(false, "no open floor pair for the scenario")
		return _failures
	var skipped: Array = []
	for id in HunterRoster.IMPLEMENTED_IDS + HunterRoster.VOID_IDS:
		var brain := HunterBrain.new(start, "REACQ-%s" % id, id, "standard")
		brain.activate_at(hider)
		var chased := false
		var caught := false
		for i in int(3.0 / STEP):
			caught = brain.update(STEP, generator, _target(hider, false, 0.6), 1, 0)
			if caught or brain.state == HunterBrain.State.CHASE:
				chased = not caught
				break
		if not chased:
			_expect(caught or id in NO_OPEN_CHASE, "%s never chased a runner 2-3 m away in plain view (state %d)" % [id, brain.state])
			skipped.append(id)
			continue
		var searched := false
		for i in int(HIDE_SECONDS / STEP):
			brain.update(STEP, generator, _target(hider, true, 0.0), 1, 0)
			searched = searched or brain.state != HunterBrain.State.CHASE
		_expect(searched, "%s kept chasing a hidden runner for %.0f s" % [id, HIDE_SECONDS])
		var clock := 0.0
		var found := false
		var walker := hider
		while clock < REACQUIRE_LIMIT and not found:
			clock += STEP
			walker = _visible_near(generator, brain.position)   # out of the locker and right up to her
			caught = brain.update(STEP, generator, _target(walker, false, 0.6), 1, 0)
			found = caught or brain.state == HunterBrain.State.CHASE
		_expect(found, "%s did not reacquire a runner in plain view %.1f m away within %.1f s of leaving a hide spot (state %d)"
			% [id, walker.distance_to(brain.position), REACQUIRE_LIMIT, brain.state])
	print("  no open-sight chase (by design): %s" % ", ".join(skipped))
	if _failures == 0:
		print("  hide_reacquire  ok")
	return _failures
