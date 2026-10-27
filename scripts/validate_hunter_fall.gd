extends RefCounted

## Hunters never fall through the map (docs/HUNTER_PATHING.md): a hunter's height is the level floor, not physics, so far hunters
## and hunters whose chunk collider was freed under them stay on the floor. Places all 38 hunters 60 chunks from anywhere that has
## floor collision, runs 60 simulated seconds of walking, then repeats with a floor collider that is removed mid-run.
##
##   godot --headless --path . res://scenes/validate.tscn -- hunter_fall

const FAR := 60.0 * StreamedRouteGenerator.CHUNK_SIZE
const STEP := 1.0 / 60.0
const SECONDS := 60.0
const SPEED := 3.5
const MIN_Y := -0.2

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var tree := host.get_tree()
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var views := []
	var start := Vector2(FAR + .5, FAR + .5)
	for index in ids.size():
		var origin := start + Vector2(index * 3.0, 0)
		var brain := HunterBrain.new(origin, "FALL-%s" % ids[index], String(ids[index]), "standard")
		brain.activate_at(origin)
		brain.state = HunterBrain.State.WANDER
		var view := HunterView3D.new()
		view.brain = brain
		host.add_child(view)
		views.append({"view": view, "origin": origin, "min_y": INF})
	await tree.process_frame
	for entry in views:
		(entry["view"] as HunterView3D).sync_from_brain()
	# 1. no floor collision anywhere: 60 s of walking
	var steps := int(SECONDS / STEP)
	for step in steps:
		for entry in views:
			var view := entry["view"] as HunterView3D
			view.brain.position += Vector2(0, 1) * SPEED * STEP
			view.sync_from_brain()
			view._physics_process(STEP)
			entry["min_y"] = minf(float(entry["min_y"]), view.position.y)
		if step % 600 == 599:
			await tree.process_frame
	var progress_ok := 0
	for index in views.size():
		var entry: Dictionary = views[index]
		var view := entry["view"] as HunterView3D
		_expect(float(entry["min_y"]) >= MIN_Y, "%s fell to y=%.2f with no floor collision" % [ids[index], float(entry["min_y"])])
		_expect(view.brain.fall_recoveries == 0, "%s needed %d fall recoveries" % [ids[index], view.brain.fall_recoveries])
		var travelled := Vector2(view.position.x, view.position.z).distance_to(entry["origin"])
		if travelled >= SPEED * SECONDS * .8:
			progress_ok += 1
	_expect(progress_ok == views.size(), "only %d of %d hunters made progress along their route" % [progress_ok, views.size()])
	# 2. a chunk collider freed under a hunter
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(40, 1, 40)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position = Vector3(-5000, -.5, -5000)
	host.add_child(floor_body)
	var origin2 := Vector2(-5000, -5000)
	var brain2 := HunterBrain.new(origin2, "FALL-FREE", "aki", "standard")
	brain2.activate_at(origin2)
	brain2.state = HunterBrain.State.WANDER
	var view2 := HunterView3D.new()
	view2.brain = brain2
	host.add_child(view2)
	await tree.process_frame
	view2.sync_from_brain()
	var low := INF
	for step in 600:
		if step == 120:
			floor_body.queue_free()
			await tree.process_frame
		brain2.position += Vector2(1, 0) * 2.0 * STEP
		view2.sync_from_brain()
		view2._physics_process(STEP)
		low = minf(low, view2.position.y)
	_expect(low >= MIN_Y, "a hunter fell to y=%.2f when her chunk collider was freed" % low)
	# 3. a view that was already pushed under the floor is put back and counted
	view2.position.y = -3.0
	view2.sync_from_brain()
	view2._physics_process(STEP)
	_expect(view2.brain.fall_recoveries == 1 and view2.position.y > -3.0, "a hunter below the floor was not recovered and counted")
	for entry in views:
		(entry["view"] as HunterView3D).queue_free()
	view2.queue_free()
	await tree.process_frame
	if _failures == 0:
		print("  hunter_fall  %d hunters walked %d s each 60 chunks from any floor collision, and one lost her collider mid-walk: none fell below y=%.1f" % [ids.size(), int(SECONDS), MIN_Y])
	return _failures
