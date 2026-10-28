extends RefCounted

## The neck-lift catch (NeckLift, GrabStyles): every hunter has a grab style; the six approved lifters raise the runner by the neck
## with one hand (feet off the floor, the eye rises and tips back, the skinned hands come up to the hunter's wrist); other players see
## the lifted body through the runner's own state; release puts the runner back down.
##   godot --headless --path . res://scenes/validate.tscn -- neck_lift

const LIFTERS := ["kathy", "xivvy", "umbriel", "elise", "wynelle", "ravelle"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _hunter(host: Node, hunter_id: String, at: Vector3, facing: Vector3) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(at.x, at.z), "NECK-LIFT", hunter_id, "standard")
	brain.activate_at(Vector2(at.x, at.z))
	var view := HunterView3D.new()
	view.brain = brain
	host.add_child(view)
	view.global_position = at
	view.look_at(at + facing, Vector3.UP)
	return view


func _expect_styles() -> void:
	var every := HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS
	for id in every:
		var style := GrabStyles.style_for(String(id))
		_expect(style in [GrabStyles.NECK_LIFT, GrabStyles.CLASSIC], "%s has no grab style" % id)
		_expect(GrabStyles.lifts(String(id)) == LIFTERS.has(id), "%s: neck lift is %s, KT's list says %s" % [id, GrabStyles.lifts(String(id)), LIFTERS.has(id)])
	for id in GrabStyles.STYLES:
		_expect(every.has(id), "GrabStyles lists %s, which is not a hunter" % id)


func _expect_skinned(hands: Node3D) -> void:
	_expect(hands != null and hands.visible, "the lift hands are not shown")
	if hands == null:
		return
	var meshes := hands.find_children("*", "MeshInstance3D", true, false)
	_expect(not meshes.is_empty(), "the lift hands have no meshes")
	for node in meshes:
		var mesh_node := node as MeshInstance3D
		_expect(not mesh_node.mesh is BoxMesh, "a lift hand is a placeholder box")
		var material := mesh_node.get_active_material(0)
		if material is StandardMaterial3D:
			_expect((material as StandardMaterial3D).albedo_texture != null, "a lift hand is not textured with the skin")
	var left := hands.get_node("L").get_child(0) as Node3D
	var right := hands.get_node("R").get_child(0) as Node3D
	_expect(left.scale.x * right.scale.x < 0.0, "the left lift hand is not mirrored")


func run(host: Node) -> int:
	_expect_styles()
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	var player := route.get("player") as PlayerController3D
	var lift := route.get("neck_lift") as NeckLift
	_expect(lift != null, "the route has no NeckLift director")
	if player == null or lift == null:
		route.queue_free()
		return _failures
	player.input_frozen = true
	player.look_frozen = true
	var stand := player.global_position
	var eye_before := player.active_camera().global_position.y
	var facing := -player.global_basis.z
	facing.y = 0.0
	facing = facing.normalized()
	var reach_done := false
	for id in LIFTERS:
		player.global_position = stand
		var view := _hunter(route, String(id), stand + facing * .75, -facing)
		await host.get_tree().process_frame
		await lift.play(player, view)
		await host.get_tree().process_frame
		var raised := player.lift_height
		_expect(raised >= .3 and raised <= NeckLift.MAX_LIFT, "%s lifts the runner %.2f m (want feet off the floor, .30-%.2f)" % [id, raised, NeckLift.MAX_LIFT])
		var eye := player.active_camera().global_position.y
		_expect(eye - eye_before > .25, "%s: the eye only rose %.2f m" % [id, eye - eye_before])
		_expect(player.lift_pitch > .2, "%s: the view does not tip back while lifted" % id)
		_expect(player.current_clip() == "fall", "%s: the lifted body plays %s, not the dangling fall clip" % [id, player.current_clip()])
		var hand := view.find_child("R-Hand", true, false) as Node3D
		var neck := NeckLift.neck_of(player.global_position, raised, player._standing_camera_height)
		_expect(hand != null and hand.global_position.distance_to(neck) < .45, "%s: the hunter's hand is %.2f m from the runner's neck" % [id, hand.global_position.distance_to(neck) if hand else -1.0])
		var shoulder := view.find_child("R-Arm", true, false) as Node3D
		_expect(shoulder != null and shoulder.global_position.y > stand.y + 1.5, "%s: the shoulder is not above the runner (hunter scale)" % id)
		_expect(Vector2(player.global_position.x - stand.x, player.global_position.z - stand.z).length() < .6, "%s pulled the runner %.2f m" % [id, player.global_position.distance_to(stand)])
		_expect_skinned(player._lift_hands)
		if not reach_done:
			reach_done = true
			# the hands are on screen, around the wrist rather than off the edges
			var camera := player.active_camera()
			var size := player.get_viewport().get_visible_rect().size
			var seen := 0
			for node in player._lift_hands.find_children("*", "MeshInstance3D", true, false):
				var mesh_node := node as MeshInstance3D
				var point := mesh_node.global_transform * mesh_node.mesh.get_aabb().get_center()
				if camera.is_position_behind(point):
					continue
				var screen := camera.unproject_position(point)
				if Rect2(Vector2.ZERO, size).has_point(screen):
					seen += 1
			_expect(seen > 0, "the lift hands are off screen")
			# the runner's state tells everyone else how high they are
			var remote := RemotePlayers.new()
			remote.local_player = player
			route.add_child(remote)
			var state := remote._local_state()
			_expect(absf(float(state.get("lift", 0.0)) - raised) < .02, "the runner's state carries lift %.2f, not %.2f" % [float(state.get("lift", 0.0)), raised])
			_expect(String(state.get("clip", "")) == "fall", "the runner's state sends clip %s while lifted" % state.get("clip", ""))
			# a guest's copy of the lifted body: the nearest lifting hunter takes it by the neck
			var body := ModelSlot.instantiate(PlayerModels.SCENE)
			route.add_child(body)
			body.scale = Vector3.ONE * PlayerModels.SCALE
			body.global_position = player.global_position + Vector3.UP * raised
			NeckLift.pose_nearest_hunter(remote, body, true)
			var remote_neck := body.global_position + Vector3(0, NeckLift.BODY_NECK, 0)
			_expect(hand.global_position.distance_to(remote_neck) < .5, "a guest sees the hunter's hand %.2f m from the lifted body's neck" % hand.global_position.distance_to(remote_neck))
			body.queue_free()
			remote.queue_free()
		lift.release()
		_expect(player.lift_height == 0.0 and not player._lift_hands.visible, "%s: release did not put the runner down" % id)
		_expect(absf(player.first_person_pivot.rotation.z) < .001, "%s: the view stays rolled after release" % id)
		view.queue_free()
		await host.get_tree().process_frame
	# a classic hunter's catch is untouched
	_expect(not GrabStyles.lifts("dovelle") and not GrabStyles.lifts("void_red"), "a non-lifting hunter lifts")
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  neck_lift  %d lifters, every hunter has a grab style, skinned hands, guest view synced" % LIFTERS.size())
		print("neck_lift: all checks OK")
	return _failures
