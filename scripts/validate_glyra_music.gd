extends RefCounted

## Glyra and the music boxes (KT 2026-10-28; GlyraGimmick, MusicBoxes). The streamed route places MUSIC_BOXES_PER_REGION
## boxes per 4x4 region (deterministic, on open floor); a box plays for its difficulty's wound time, winds down for the
## last 15 s, then stops; Glyra is calm (slow, near her box, no peeks, harmless, ignores a runner further than 4 m),
## restless while it winds down (normal speed, peeks, can catch) and hunting once it stops (1.3x, 1.5x on Nightmare,
## chases and catches); a rewind calms her within 3 s unless she is mid-chase in sight; her mood and box clock replicate;
## winding is a hold.
##
##   godot --headless --path . res://scenes/validate.tscn -- glyra_music

const STEP := 1.0 / 30.0
const BOX := Vector2(20.5, 20.5)

var _failures := 0


class Field:
	var safe_zones: Array = []
	var exit_cell := Vector2i(-1, -1)
	var rooms: Array = []
	var relays: Array = []
	var vents: Array = []
	var hiding_spots: Array = []
	var start := Vector2i(20, 20)
	var music_boxes: Array = [{"id": "TEST:music_box", "x": 20, "y": 20}]

	func is_floor(x: float, y: float) -> bool:
		return x >= 2.0 and y >= 2.0 and x < 40.0 and y < 40.0

	func can_occupy(x: float, y: float, radius: float = .23, _blocked = null) -> bool:
		return is_floor(x - radius, y - radius) and is_floor(x + radius, y + radius)

	func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
		return is_floor(from.x, from.y) and is_floor(to.x, to.y)

	func find_path(from: Vector2i, to: Vector2i) -> Array:
		var result := [from]
		var cursor := from
		while cursor != to:
			if cursor.x != to.x:
				cursor.x += 1 if to.x > cursor.x else -1
			else:
				cursor.y += 1 if to.y > cursor.y else -1
			result.append(cursor)
		return result

	func floor_cells() -> Array:
		return []

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


func _target(at: Vector2, hidden := false) -> Dictionary:
	return {"peer_id": 1, "position": at, "hidden": hidden, "in_safe_zone": false, "noise": 0.4, "flashlight_on": true,
		"sprinting": false, "facing": Vector2(0, 1), "lamp_charge": 100.0, "meters": null,
		"heater_unfrozen": false, "heater_powered": false}


func _glyra(mode: String, boxes: MusicBoxes, at: Vector2 = BOX + Vector2(1, 0)) -> HunterBrain:
	var brain := HunterBrain.new(at, "GLYRA-MUSIC-%s" % mode, "glyra", mode)
	(brain.gimmick as GlyraGimmick).boxes = boxes
	brain.activate_at(at)
	brain.state = HunterBrain.State.WANDER
	brain.peek_chance_override = -1.0
	return brain


func _run(brain: HunterBrain, field: Field, target: Dictionary, seconds: float, done := Callable()) -> bool:
	for i in int(seconds / STEP):
		if brain.update(STEP, field, target, 1, 0):
			return true
		if done.is_valid() and done.call():
			return true
	return false


func run(_host: Node) -> int:
	_placement()
	_clock()
	_moods()
	_hold_and_sync()
	if _failures == 0:
		print("  glyra_music  ok")
	return _failures


func _placement() -> void:
	var generator := StreamedRouteGenerator.new("GLYRA-MUSIC")
	var picked := 0
	var boxes := 0
	var ids := {}
	for z in 4:
		for x in 4:
			var coord := Vector3i(x, 0, z)
			if generator.music_box_chunk(coord):
				picked += 1
			var data := generator.chunk(coord)
			for box in data.get("music_boxes", []):
				boxes += 1
				ids[String(box["id"])] = true
				var cell: Vector2i = box["cell"]
				_expect(int(data["grid"][cell.y][cell.x]) == 0, "music box %s is not on open floor" % box["id"])
			var again := StreamedRouteGenerator.new("GLYRA-MUSIC").chunk(coord)
			_expect(str(again.get("music_boxes", [])) == str(data.get("music_boxes", [])),
				"music box placement is not deterministic at %s" % coord)
	_expect(picked == GameConfig.MUSIC_BOXES_PER_REGION, "a region picked %d box chunks, not %d" % [picked, GameConfig.MUSIC_BOXES_PER_REGION])
	_expect(boxes >= 1 and boxes <= GameConfig.MUSIC_BOXES_PER_REGION and ids.size() == boxes,
		"a region holds %d music boxes (%d ids)" % [boxes, ids.size()])


func _clock() -> void:
	for mode in ["standard", "hard", "nightmare"]:
		var boxes := MusicBoxes.new()
		boxes.difficulty_id = mode
		var wound := float(GameConfig.MUSIC_BOX_WOUND_SECONDS[mode])
		_expect(is_equal_approx(boxes.seconds_left("a"), wound), "%s box does not start with %.0f s" % [mode, wound])
		_expect(boxes.mood("a") == MusicBoxes.Mood.PLAYING, "a fresh box is not playing")
		boxes.tick(wound - GameConfig.MUSIC_BOX_WINDDOWN_SECONDS + .1)
		_expect(boxes.mood("a") == MusicBoxes.Mood.WINDING_DOWN, "%s box does not wind down in its last 15 s" % mode)
		boxes.tick(GameConfig.MUSIC_BOX_WINDDOWN_SECONDS)
		_expect(boxes.mood("a") == MusicBoxes.Mood.STOPPED, "%s box does not stop" % mode)
		boxes.wind("a")
		_expect(boxes.mood("a") == MusicBoxes.Mood.PLAYING and is_equal_approx(boxes.seconds_left("a"), wound),
			"winding a %s box does not restart it" % mode)


func _moods() -> void:
	var field := Field.new()
	# calm: slow, near her box, no peeks, harmless, ignores a runner 8 m off in plain view
	var boxes := MusicBoxes.new()
	var brain := _glyra("standard", boxes)
	var glyra := brain.gimmick as GlyraGimmick
	var far := _target(BOX + Vector2(8, 0))
	_run(brain, field, far, 4.0)
	_expect(glyra.mood == MusicBoxes.Mood.PLAYING and glyra.humming(), "Glyra is not calm and humming while her box plays")
	_expect(brain.state != HunterBrain.State.CHASE, "calm Glyra chased a runner 8 m away")
	_expect(brain.position.distance_to(BOX) <= GameConfig.GLYRA_CALM_LEASH + 1.0, "calm Glyra wandered off from her box")
	_expect(is_equal_approx(glyra.speed_scale(brain), GameConfig.GLYRA_CALM_SPEED_SCALE), "calm Glyra is not slow")
	_expect(glyra.peek_chance(brain, .8) == 0.0 and glyra.immune_to_capture(), "calm Glyra peeks or can catch")
	var near := _target(brain.position + Vector2(2.5, 0))
	_expect(not _run(brain, field, near, 2.0), "calm Glyra caught a runner")
	# winding down: restless, peeks, normal speed, can catch
	boxes.set_seconds_left(glyra.box_id, 10.0)
	brain.update(STEP, field, far, 1, 0)
	_expect(glyra.mood == MusicBoxes.Mood.WINDING_DOWN and not glyra.humming(), "Glyra did not notice the tune winding down")
	_expect(glyra.peek_chance(brain, HunterPeek.chance("glyra", "standard")) >= .7 and not glyra.immune_to_capture()
		and is_equal_approx(glyra.speed_scale(brain), 1.0), "restless Glyra does not peek, catch and move at normal speed")
	# stopped: hunts fast, chases and catches
	for mode in ["standard", "nightmare"]:
		var clock := MusicBoxes.new()
		clock.difficulty_id = mode
		clock.set_seconds_left("TEST:music_box", 0.0)
		var hunter := _glyra(mode, clock)
		var hunted := hunter.gimmick as GlyraGimmick
		var runner := _target(BOX + Vector2(7, 0))
		var caught := _run(hunter, field, runner, 12.0)
		_expect(hunted.mood == MusicBoxes.Mood.STOPPED, "%s: Glyra did not hear her box stop" % mode)
		_expect(is_equal_approx(hunted.speed_scale(hunter), float(GameConfig.GLYRA_HUNT_SPEED_SCALE[mode])),
			"%s: Glyra is not hunting at %.1fx" % [mode, GameConfig.GLYRA_HUNT_SPEED_SCALE[mode]])
		_expect(caught, "%s: hunting Glyra never caught a runner 7 m away in plain view" % mode)
	# a rewind calms her within 3 s once she cannot see them
	var rewind := MusicBoxes.new()
	rewind.set_seconds_left("TEST:music_box", 0.0)
	brain = _glyra("standard", rewind, BOX + Vector2(-6, 0))
	glyra = brain.gimmick as GlyraGimmick
	_run(brain, field, _target(BOX + Vector2(-14, 0)), .5)
	rewind.wind("TEST:music_box")
	var gone := _target(BOX + Vector2(-14, 0), true)
	var calmed := _run(brain, field, gone, GameConfig.GLYRA_CALM_AFTER_WIND + .5,
		func() -> bool: return brain.state == HunterBrain.State.WANDER and glyra.mood == MusicBoxes.Mood.PLAYING)
	_expect(calmed, "a rewound box did not calm Glyra within %.0f s (state %d)" % [GameConfig.GLYRA_CALM_AFTER_WIND, brain.state])
	# ... but she finishes a chase she can see
	var seen := MusicBoxes.new()
	seen.set_seconds_left("TEST:music_box", 0.0)
	brain = _glyra("standard", seen, BOX + Vector2(-6, 0))
	glyra = brain.gimmick as GlyraGimmick
	var visible := _target(BOX + Vector2(-12, 0))
	_run(brain, field, visible, 1.0, func() -> bool: return brain.state == HunterBrain.State.CHASE)
	seen.wind("TEST:music_box")
	var spot := brain.position + Vector2(-5, 0)
	_run(brain, field, _target(spot), GameConfig.GLYRA_CALM_AFTER_WIND + .5)
	_expect(brain.position.distance_to(spot) < 2.0 and brain.state != HunterBrain.State.WANDER,
		"rewinding mid-chase made Glyra drop a runner she can see (state %d, %.1f m off)" % [brain.state, brain.position.distance_to(spot)])


func _hold_and_sync() -> void:
	var player := PlayerController3D.new()
	var box := RouteInteractable3D.new()
	box.kind = RouteInteractable3D.Kind.MUSIC_BOX
	box.music_box_id = "TEST:music_box"
	box.prompt_text = "HOLD INTERACT // WIND MUSIC BOX"
	_expect(is_equal_approx(player._hold_seconds(box), GameConfig.MUSIC_BOX_WIND_HOLD), "winding a music box is not a hold")
	_expect(box.get_prompt().begins_with("HOLD INTERACT // "), "the music box prompt does not say to hold")
	var wound: Array = []
	player.music_box_resolver = func(id: String) -> String:
		wound.append(id)
		return "wound"
	box.activate(player)
	_expect(wound == ["TEST:music_box"], "a finished hold did not wind that box (got %s)" % [wound])
	player.free()
	box.free()
	# host -> guest: mood and the box clock
	var host_boxes := MusicBoxes.new()
	host_boxes.set_seconds_left("TEST:music_box", 9.0)
	var host := _glyra("standard", host_boxes)
	host.update(STEP, Field.new(), _target(BOX + Vector2(9, 0)), 1, 0)
	var guest_boxes := MusicBoxes.new()
	var guest := GlyraGimmick.new()
	guest.boxes = guest_boxes
	guest.apply_network_state((host.gimmick as GlyraGimmick).network_state())
	_expect(guest.mood == MusicBoxes.Mood.WINDING_DOWN and absf(guest_boxes.seconds_left("TEST:music_box") - 9.0) < .2,
		"Glyra's mood and box clock do not replicate")
	_expect(not HunterPeek.NEVER.has("glyra"), "Glyra is still on the never-peek list")
