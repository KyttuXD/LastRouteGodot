extends RefCounted

## Hunter grabs (GrabStyles, HunterGrab, docs/HUNTER_GRABS.md): every hunter has a valid weighted pool in res://data/grabs, the
## pick is seeded and respects the room, and every style plays: the runner's body, eye and skinned hands, the hunter's hands on
## the right body point, the state other players draw it from, and a clean release.
##   godot --headless --path . res://scenes/validate.tscn -- grabs

const NECK_LIFTERS := ["kathy", "xivvy", "umbriel", "elise", "wynelle", "ravelle"]
## A hunter whose model has arms, for each style (the creature rig for its own).
const STYLE_HUNTER := {
	"neck_lift": "kathy", "shoulder_grab": "dovelle", "tackle": "haelith", "wrist_yank": "aki", "wrap": "briselle",
	"leg_grab": "ceryth", "upside_down": "xivvy", "shoulder_carry": "kathy", "collar_drag": "javelle", "wall_pin": "opalie",
	"pounce_pin": SecretCreatures.IDS[0],
}
const LIFTED := ["neck_lift", "shoulder_carry", "upside_down"]
const FLOORED := ["tackle", "leg_grab", "pounce_pin"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _expect_pools() -> void:
	_expect(GrabStyles.errors().is_empty(), "res://data/grabs has errors: %s" % ", ".join(GrabStyles.errors()))
	var every: Array = HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS + SecretCreatures.IDS
	for id in every:
		var pool := GrabStyles.pool_for(String(id))
		var file := "%s/%s.json" % [GrabStyles.ROOT, id]
		_expect(FileAccess.file_exists(file), "%s has no grab pool file" % id)
		_expect(not pool.is_empty(), "%s has an empty grab pool" % id)
		var creature := GrabStyles.is_creature(String(id))
		_expect(pool.size() <= 4 and (pool.size() >= 2 or creature), "%s has %d grab styles (want 2-4)" % [id, pool.size()])
		var main := GrabStyles.main_style(String(id))
		for style in pool:
			_expect(GrabStyles.STYLES.has(style), "%s uses unknown style %s" % [id, style])
			_expect(bool(GrabStyles.STYLES[style].get("creature", false)) == creature, "%s: %s does not fit its body" % [id, style])
			if style != main:
				_expect(float(pool[style]) < float(pool[main]), "%s: %s weighs as much as the main style %s" % [id, style, main])
		_expect(NECK_LIFTERS.has(id) == (main == GrabStyles.NECK_LIFT), "%s: main style is %s" % [id, main])
		if String(id).begins_with("void_"):
			_expect(not pool.has(GrabStyles.NECK_LIFT), "%s neck-lifts (KT: Void stay out of it)" % id)
	for file_name in DirAccess.get_files_at(GrabStyles.ROOT):
		_expect(every.has(String(file_name).get_basename()), "data/grabs/%s is not a hunter" % file_name)
	# strict like ContentRegistry: unknown keys, styles and bad weights are errors
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {"neck_lift": 1}, "extra": 1}, "t")["errors"].is_empty(),
		"an unknown key was accepted")
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {"noogie": 1}}, "t")["errors"].is_empty(),
		"an unknown style was accepted")
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {"wrap": 0}}, "t")["errors"].is_empty(),
		"a zero weight was accepted")
	_expect(not GrabStyles.parse_def({"schema": GrabStyles.SCHEMA, "id": "x", "pool": {}}, "t")["errors"].is_empty(),
		"an empty pool was accepted")


func _expect_picks() -> void:
	var open := {"ceiling": 4.0, "back": 3.0, "hunter_back": 3.0}
	_expect(GrabStyles.roll_for("SEED", 2, 1) == GrabStyles.roll_for("SEED", 2, 1), "the roll is not repeatable")
	_expect(GrabStyles.roll_for("SEED", 2, 1) != GrabStyles.roll_for("SEED", 2, 2), "two catches roll the same")
	for id in HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS:
		var seen := {}
		for i in 400:
			var roll := GrabStyles.roll_for("POOL-TEST", 1, i)
			var picked := GrabStyles.pick(String(id), roll, open)
			_expect(picked == GrabStyles.pick(String(id), roll, open), "%s: the same roll picked two styles" % id)
			seen[picked] = int(seen.get(picked, 0)) + 1
		var pool := GrabStyles.pool_for(String(id))
		for style in pool:
			if style == GrabStyles.WALL_PIN:
				continue   # needs a wall
			_expect(seen.has(style), "%s never picked %s in open space" % [id, style])
		var main := GrabStyles.main_style(String(id))
		if main != GrabStyles.WALL_PIN:
			for style in seen:
				_expect(int(seen[main]) >= int(seen[style]), "%s picked %s more often than its main style" % [id, style])
	# the room rules them out
	var low := {"ceiling": 2.1, "back": 3.0, "hunter_back": 3.0}
	for i in 200:
		var roll := GrabStyles.roll_for("LOW", 1, i)
		for id in NECK_LIFTERS:
			var picked := GrabStyles.pick(String(id), roll, low)
			_expect(not picked in [GrabStyles.NECK_LIFT, GrabStyles.UPSIDE_DOWN, GrabStyles.SHOULDER_CARRY],
				"%s lifts under a 2.1 m ceiling (%s)" % [id, picked])
		var walled := GrabStyles.pick("opalie", roll, {"ceiling": 4.0, "back": .9, "hunter_back": 3.0})
		_expect(walled in [GrabStyles.SHOULDER_GRAB, GrabStyles.WALL_PIN], "opalie picked %s by a wall" % walled)
		_expect(GrabStyles.pick("opalie", roll, open) != GrabStyles.WALL_PIN, "a wall pin with no wall")
		_expect(GrabStyles.pick("haelith", roll, {"ceiling": 4.0, "back": .9, "hunter_back": 3.0}) != GrabStyles.TACKLE,
			"a tackle into a wall")
	_expect(GrabStyles.pick("elise", .5, {"ceiling": 2.0, "back": .1, "hunter_back": 0.0}) == GrabStyles.FALLBACK,
		"no fitting style did not fall back to the shoulder grab")
	_expect(GrabStyles.pick(SecretCreatures.IDS[0], .5, {"ceiling": 2.0, "back": .1}) == GrabStyles.POUNCE_PIN,
		"a creature rig fell back to a humanoid grab")


func _hunter(parent: Node, id: String, at: Vector3, facing: Vector3) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(at.x, at.z), "GRAB-TEST", id, "standard")
	brain.activate_at(Vector2(at.x, at.z))
	var view := HunterView3D.new()
	view.brain = brain
	parent.add_child(view)
	view.global_position = at
	view.look_at(at + facing, Vector3.UP)
	return view


const ARENA := preload("res://scripts/grab_arena.gd")
## Camera rules (KT): clear of every hunter collider, model box and wall by at least the near plane plus a margin, and never
## inside the runner's own body; at that body's eyes; roll within 15 degrees (the upside-down hold: within 10 of upside down
## once it has turned over); no snapping; the FOV never changes; the hunter's face framed at the hold; the runner's own hands
## on screen and not huge where they hold something; every grip within 3 cm.
const CAMERA_CLEARANCE := .06
const MAX_TURN_RATE := 3.0
const MAX_MOVE_RATE := 6.0
const FACE_MIN := .45
const CONTACT := .03


## No part of the model's head group (head box, hair, hat, accessories, face) is drawn for `camera`.
static func _head_hidden(model: Node3D, camera: Camera3D) -> bool:
	var head := model.find_child("Head", true, false)
	if head == null:
		return true
	for node in [head] + head.find_children("*", "GeometryInstance3D", true, false):
		if node is VisualInstance3D and (node as VisualInstance3D).is_visible_in_tree() \
				and ((node as VisualInstance3D).layers & camera.cull_mask) != 0:
			return false
	return true


func _roll_of(basis: Basis) -> float:
	return asin(clampf(basis.x.normalized().y, -1.0, 1.0))


## The runner's own first-person body: how many hand corners are on screen, and the taller hand as a share of the screen.
func _hand_share(player: PlayerController3D) -> Vector2:
	var camera := player.first_person_camera
	var size := player.get_viewport().get_visible_rect().size
	var seen := 0
	var tallest := 0.0
	for hand_name in ["L-Hand", "R-Hand"]:
		var hand := player.first_person_body().model.find_child(hand_name, true, false) as Node3D
		if hand == null:
			continue
		var top := 1e9
		var bottom := -1e9
		for node in [hand] + hand.find_children("*", "MeshInstance3D", true, false):
			if not node is MeshInstance3D:
				continue
			var mesh_node := node as MeshInstance3D
			var box := mesh_node.mesh.get_aabb()
			for corner in 8:
				var point := mesh_node.global_transform * box.get_endpoint(corner)
				if camera.is_position_behind(point):
					continue
				var screen := camera.unproject_position(point)
				if Rect2(Vector2.ZERO, size).has_point(screen):
					seen += 1
				top = minf(top, clampf(screen.y, 0.0, size.y))
				bottom = maxf(bottom, clampf(screen.y, 0.0, size.y))
		if bottom > top:
			tallest = maxf(tallest, (bottom - top) / size.y)
	return Vector2(seen, tallest)


## Her face: between her eyes (her head when the rig has no eyes).
func _face_point(view: Node3D) -> Vector3:
	var head := view.find_child("Head", true, false) as Node3D
	var left := head.find_child("L-Eye-Attachment", true, false) as Node3D if head else null
	var right := head.find_child("R-Eye-Attachment", true, false) as Node3D if head else null
	if left != null and right != null:
		return (left.global_position + right.global_position) * .5
	return head.global_position if head != null else view.global_position + Vector3.UP * 2.0


## Angle between where her face points and `target` (the runner's camera), in 3D.
func _facing_angle(view: Node3D, target: Vector3) -> float:
	var head := view.find_child("Head", true, false) as Node3D
	if head == null:
		return 0.0
	var id := String(view.call("shown_id")) if view.has_method("shown_id") else ""
	var facing := HunterGrab.face_forward(head, GrabStyles.look_for(id), Vector3.FORWARD)
	return facing.angle_to(target - head.global_position)

func _expect_style(route: Node, player: PlayerController3D, grab: HunterGrab, style: String, place: Dictionary, where: String) -> void:
	var id := String(STYLE_HUNTER[style])
	var label := "%s/%s" % [where, style]
	var stand: Vector3 = place["stand"]
	var facing: Vector3 = place["facing"]
	player.global_position = stand
	player.velocity = Vector3.ZERO
	player._yaw = atan2(-facing.x, -facing.z)
	player._pitch = 0.0
	player._apply_look_rotation()
	var view := _hunter(route, id, stand + facing * .8, -facing)
	await route.get_tree().process_frame
	await route.get_tree().process_frame
	var model := view.get("_model") as Node3D
	var rest := model.transform if model != null else Transform3D.IDENTITY
	# a style the room rules out is never picked there (the pick is checked above); everything else must play cleanly here
	var space := player.get_world_3d().direct_space_state
	var room := HunterGrab.probe_room(space, stand, stand + facing * .8, -facing, [player.get_rid(), view.get_rid()],
		player.collision_mask)
	if not GrabStyles.fits(style, room):
		view.queue_free()
		await route.get_tree().process_frame
		return
	var fov := player.first_person_camera.fov
	grab.play(player, view, id, .5, style)
	var previous := player.first_person_camera.global_transform
	var worst := ""
	var t_end := GrabStyles.duration(style) + .7
	var waited := 0.0
	var flipped := false
	var max_gap := 0.0
	var away_seen := false
	var pushes_seen := 0
	var eye_frames := 0
	var drift_frames := 0
	while waited < t_end:
		await route.get_tree().process_frame
		var delta := maxf(route.get_process_delta_time(), .001)
		waited += delta
		var camera := player.first_person_camera.global_transform
		var blocked := HunterGrab.camera_blocked(space, camera.origin, [player.get_rid()], player.collision_mask, [view],
			CAMERA_CLEARANCE)
		# a part of her at the lens may only be there if it is not drawn for this camera (culled for the frame)
		if blocked.begins_with("hunter mesh"):
			var part := blocked.trim_prefix("hunter mesh (").trim_suffix(")")
			var hidden_from_camera := false
			for mesh in grab.culled:
				hidden_from_camera = hidden_from_camera or (mesh as Node).name == part
			if hidden_from_camera:
				blocked = ""
		if not blocked.is_empty() and worst.is_empty():
			worst = "the camera is inside a %s at %.2f s" % [blocked, waited]
		var own := player.first_person_body()
		if own.model != null and own.visible and not _head_hidden(own.model, player.first_person_camera) and worst.is_empty():
			worst = "the runner's own head is visible to the first-person camera at %.2f s" % waited
		if waited > HunterGrab.CATCH_EASE + .05 and own.model != null:
			var inside_self := HunterGrab.camera_blocked(space, camera.origin, [player.get_rid()], 0, [own.model], .02)
			if not inside_self.is_empty():
				var part := inside_self.trim_prefix("hunter mesh (").trim_suffix(")")
				for mesh in grab.culled:
					if (mesh as Node).name == part and own.model.is_ancestor_of(mesh):
						inside_self = ""
			if not inside_self.is_empty() and worst.is_empty():
				worst = "the camera is inside the runner's own %s at %.2f s" % [inside_self.trim_prefix("hunter mesh "), waited]
			# at the body's own eyes, unless her arm or body is right there (then it is nudged clear, as the rules ask)
			var eye_clear := HunterGrab.camera_blocked(space, own.eye(), [player.get_rid()], player.collision_mask, [view],
				HunterGrab.CLEARANCE + .03, true).is_empty()
			if eye_clear and grab.pushes == pushes_seen:
				eye_frames += 1
				if camera.origin.distance_to(own.eye()) >= .03:   # at the head's front face plus at most 2 cm (and rounding)
					drift_frames += 1
		var roll := _roll_of(camera.basis)
		var upright := camera.basis.y.y > 0.0
		if style == GrabStyles.UPSIDE_DOWN and waited > t_end - .15:
			flipped = true
			_expect(not upright and absf(roll) <= HunterGrab.FLIP_SWAY + .03, "%s: upside down the view sways %.0f deg" % [label, rad_to_deg(roll)])
		elif style == GrabStyles.UPSIDE_DOWN:
			_expect(upright or absf(roll) <= 1.6, "%s: the view spins" % label)
		else:
			_expect(upright and absf(roll) <= HunterGrab.MAX_ROLL + .02, "%s: the view rolls %.0f deg at %.2f s" % [label, rad_to_deg(roll), waited])
		var turn := previous.basis.orthonormalized().get_rotation_quaternion().angle_to(camera.basis.orthonormalized().get_rotation_quaternion())
		_expect(turn / delta <= MAX_TURN_RATE or grab.pushes > pushes_seen, "%s: the view snaps %.0f deg in one frame at %.2f s" % [label, rad_to_deg(turn), waited])
		var pushed := grab.pushes > pushes_seen   # she moved into the camera: the push may be quick, never skipped
		pushes_seen = grab.pushes
		# she moved into the camera: it is pushed clear at once, but still never jumps
		# a push out of her arm may be one quick step (at most 20 cm), never a jump across the room
		_expect((pushed and previous.origin.distance_to(camera.origin) <= HunterGrab.MAX_PUSH + .05) or previous.origin.distance_to(camera.origin) / delta <= MAX_MOVE_RATE, "%s: the camera jumps %.2f m in one frame at %.2f s s" % [label, previous.origin.distance_to(camera.origin), waited])
		# the view may only widen, at most 10 degrees and eased, and only in the hold
		var widened := player.first_person_camera.fov - fov
		_expect(widened > -.01 and widened <= HunterGrab.fov_widen + .01, "%s: the FOV moved %.1f deg" % [label, widened])
		_expect(widened < .01 or waited > GrabStyles.REACH_SECONDS + GrabStyles.ACT_SECONDS * .5, "%s: the view widened before the hold" % label)
		# never behind the runner's eye plane (KT: in front of the head, not over the shoulder)
		if own.model != null and waited > HunterGrab.CATCH_EASE + .05:
			var front := -own.global_basis.z
			var ahead := Vector3(front.x, 0.0, front.z).normalized()   # the plane through the eyes, square to where the body faces
			_expect((camera.origin - own.eye()).dot(ahead) > -.03, "%s: the camera is %.2f m behind the runner's eyes at %.2f s" % [label,
				-(camera.origin - own.eye()).dot(ahead), waited])
		previous = camera
		if waited > GrabStyles.REACH_SECONDS + GrabStyles.ACT_SECONDS and not (grab.current["arms"] as Array).is_empty():
			max_gap = maxf(max_gap, grab.contact_gap)
		if float(GrabStyles.look_for(id)["delay"]) > 0.0 and waited > GrabStyles.REACH_SECONDS and waited < GrabStyles.REACH_SECONDS + GrabStyles.ACT_SECONDS:
			away_seen = away_seen or _facing_angle(view, camera.origin) > deg_to_rad(40.0)
	_expect(worst.is_empty(), "%s: %s" % [label, worst])
	_expect(drift_frames == 0, "%s: the camera left the head's front face on %d of %d clear frames" % [label, drift_frames, eye_frames])
	if style == GrabStyles.UPSIDE_DOWN:
		_expect(flipped, "%s: the view never turned over" % label)
	_expect(max_gap < CONTACT, "%s: a grip is %.1f cm off its contact during the hold" % [label, max_gap * 100.0])
	# the hold: her face framed, not a close-up; her head turned to the camera as far as the neck goes; the hands on screen
	var camera := player.first_person_camera.global_transform
	var head := view.find_child("Head", true, false) as Node3D
	# carried over her shoulder the runner looks down her back: her face is not theirs to see
	if head != null and style != GrabStyles.SHOULDER_CARRY:
		# crushed in a hug against a body half again your size, her face is right there: framed (and the view widened), not inside
		var face_min := .3 if style == GrabStyles.WRAP else FACE_MIN
		_expect(camera.origin.distance_to(head.global_position) >= face_min, "%s: the camera is %.2f m from her face" % [label, camera.origin.distance_to(head.global_position)])
		var screen := player.first_person_camera.unproject_position(head.global_position)
		var size := player.get_viewport().get_visible_rect().size
		_expect(not player.first_person_camera.is_position_behind(head.global_position) and Rect2(size * .1, size * .8).has_point(screen),
			"%s: her face is not framed (%s)" % [label, screen])
		var angle := _facing_angle(view, camera.origin)
		_expect(angle < deg_to_rad(10.0), "%s: she looks %.0f deg away from the runner at the hold" % [label, rad_to_deg(angle)])
		# and the runner's view is centred on her face
		var face := _face_point(view)
		var off := (-camera.basis.z).angle_to(face - camera.origin)
		_expect(off < deg_to_rad(10.0), "%s: her face is %.0f deg off the centre of the view at the hold" % [label, rad_to_deg(off)])
	if float(GrabStyles.look_for(id)["delay"]) > 0.0:
		_expect(away_seen, "%s: shy %s never looked away" % [label, id])
	# the runner's own body: the same model and scale as the third-person player (KT: not doll-sized), skinned, no head
	var own := player.first_person_body()
	_expect(own.visible and own.model != null, "%s: no first-person body" % label)
	var normal_scale := player._body_model.global_basis.get_scale().y
	_expect(absf(own.model.global_basis.get_scale().y / normal_scale - 1.0) < .02, "%s: the first-person body is %.2fx the player model" % [label,
		own.model.global_basis.get_scale().y / normal_scale])
	var head_node := own.model.find_child("Head", true, false)
	for mesh in head_node.find_children("*", "MeshInstance3D", true, false):
		_expect(not (mesh as MeshInstance3D).visible, "%s: the head mesh is drawn in first person" % label)
	var textured := false
	for mesh in own.model.find_children("*", "MeshInstance3D", true, false):
		var material := (mesh as MeshInstance3D).get_active_material(0)
		textured = textured or (material is StandardMaterial3D and (material as StandardMaterial3D).albedo_texture != null)
	_expect(textured, "%s: the first-person body is not skinned" % label)
	# the runner's own hands, when in view, never fill it (looking up at her face they are often below the view: the body is
	# there to look down at, not to be held up in front of the lens)
	var hands := _hand_share(player)
	_expect(hands.x == 0 or hands.y <= .5, "%s: a hand fills %.0f%% of the screen height" % [label, hands.y * 100.0])
	if String(grab.current["hands"]) == "held":
		for entry in HunterGrab.runner_hand_targets(own.model, view, grab.current, grab._along, waited):
			var gap := HunterGrab.grip_point(HunterGrab.arm_chain(own.model, String(entry[0]))).distance_to(entry[1])
			_expect(gap < CONTACT, "%s: the runner's own hand is %.1f cm from where she holds it" % [label, gap * 100.0])
	_expect(player.grab_active and player.current_clip() == String(grab.current["clip"]), "%s: not held / wrong clip" % label)
	var state: Array = player.grab_state
	_expect(state.size() == 7 and String(state[0]) == style, "%s: the state other players get is %s" % [label, state])
	var pose := grab.current
	var lift := float(state[2]) if state.size() == 7 else 0.0
	if style in LIFTED:
		_expect(lift > .2, "%s: the runner's feet are only %.2f m off the floor" % [label, lift])
	if style in FLOORED:
		_expect(player.first_person_camera.global_position.y - stand.y < 1.4, "%s: the eye is not down low" % label)
	if style == "leg_grab":
		_expect(float(pose["face"]) < 0.0, "%s: the body faces the hunter" % label)
	# other players: the runner's own state carries it; their copy of the body is taken the same way, clear of the walls
	var remote := RemotePlayers.new()
	remote.local_player = player
	route.add_child(remote)
	var sent := RemotePlayers._grab_packet(remote._local_state())
	_expect(sent.size() == 7 and String(sent[0]) == style, "%s: the runner's state does not carry the grab" % label)
	if sent.size() == 7:
		var body := ModelSlot.instantiate(PlayerModels.SCENE)
		route.add_child(body)
		body.scale = Vector3.ONE * PlayerModels.SCALE
		body.global_position = player.global_position + Vector3.UP * float(sent[2])
		body.rotation = Vector3(float(sent[3]), GrabStyles.body_yaw(grab._along, float(pose["face"])), 0.0)   # as RemotePlayers does
		await route.get_tree().process_frame
		_expect(absf(body.global_basis.get_scale().y / player._body_model.global_basis.get_scale().y - 1.0) < .02,
			"%s: a guest's copy of the runner is not the player's size" % label)
		HunterGrab.pose_nearest_hunter(remote, body, sent)
		var basis := body.global_basis.orthonormalized()
		for entry in HunterGrab.contacts(body.global_position, basis, pose["arms"]):
			var gap := HunterGrab.grip_point(HunterGrab.arm_chain(view, String(entry[0]))).distance_to(entry[1])
			_expect(gap < CONTACT, "%s: a guest sees her %s grip %.1f cm off the body" % [label, entry[0], gap * 100.0])
		for entry in pose.get("runner_arms", []):
			var gap := HunterGrab.grip_point(HunterGrab.arm_chain(body, String(entry[0]))).distance_to(
				body.global_position + basis * (GrabStyles.BODY_POINTS[String(entry[1])] as Vector3))
			_expect(gap < CONTACT, "%s: a guest sees the runner's hand %.1f cm off where she holds it" % [label, gap * 100.0])
		for bone in ["Head", "Chest", "Pelvis"]:
			var node := body.find_child(bone, true, false) as Node3D
			if node != null:
				var inside := HunterGrab.camera_blocked(space, node.global_position + Vector3.UP * .05, [player.get_rid()],
					player.collision_mask, [], .06)
				_expect(inside.is_empty() or inside.begins_with("hunter"), "%s: a guest sees the runner's %s inside a %s" % [label, bone, inside])
		body.queue_free()
	remote.queue_free()
	grab.release()
	_expect(not player.grab_active and player.grab_state.is_empty() and not player.first_person_body().visible, "%s: release left the runner held" % label)
	_expect(is_equal_approx(player.first_person_camera.fov, fov), "%s: release left the view widened" % label)
	_expect(absf(player.first_person_pivot.rotation.z) < .001, "%s: the view stays rolled after release" % label)
	if model != null:
		_expect(model.transform.is_equal_approx(rest), "%s: the hunter's model was not put back" % label)
	view.queue_free()
	await route.get_tree().process_frame


## Every hunter, in her main grab, in the open room: at the hold her face points at the runner's camera within 15 degrees
## (Aki after her look-away delay). Catches a rig whose face axis or neck would leave her staring past the runner.
func _expect_every_hunter_looks(route: Node, player: PlayerController3D, grab: HunterGrab, place: Dictionary) -> void:
	var stand: Vector3 = place["stand"]
	var facing: Vector3 = place["facing"]
	for id in HunterRoster.A_Z_IDS + HunterRoster.VOID_IDS + SecretCreatures.IDS:
		var style := GrabStyles.main_style(String(id))
		player.global_position = stand
		player._yaw = atan2(-facing.x, -facing.z)
		player._apply_look_rotation()
		var view := _hunter(route, String(id), stand + facing * .8, -facing)
		await route.get_tree().process_frame
		if view.find_child("Head", true, false) == null:
			view.queue_free()
			continue
		grab.play(player, view, String(id), .5, style)
		var waited := 0.0
		while waited < GrabStyles.duration(style) + .6:
			await route.get_tree().process_frame
			waited += route.get_process_delta_time()
		var angle := _facing_angle(view, player.first_person_camera.global_position)
		_expect(angle < deg_to_rad(10.0), "%s (%s): she looks %.0f deg away from the runner at the hold" % [id, style, rad_to_deg(angle)])
		if style != GrabStyles.SHOULDER_CARRY:
			var cam := player.first_person_camera.global_transform
			var off := (-cam.basis.z).angle_to(_face_point(view) - cam.origin)
			_expect(off < deg_to_rad(10.0), "%s (%s): her face is %.0f deg off the centre of the view" % [id, style, rad_to_deg(off)])
		grab.release()
		view.queue_free()
		await route.get_tree().process_frame


func run(host: Node) -> int:
	_expect_pools()
	_expect_picks()
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	var player := route.get("player") as PlayerController3D
	var grab := route.get("grab") as HunterGrab
	_expect(grab != null, "the route has no HunterGrab")
	if player != null and grab != null:
		player.input_frozen = true
		player.look_frozen = true
		var home := player.global_position
		for kind in ["open", "hallway"]:
			var place := ARENA.build(route, kind)
			for style in GrabStyles.STYLES:
				await _expect_style(route, player, grab, String(style), place, kind)
			if kind == "open" and OS.get_environment("GRABS_QUICK").is_empty():   # GRABS_QUICK=1 skips the 40-hunter sweep
				await _expect_every_hunter_looks(route, player, grab, place)
			(place["root"] as Node).queue_free()
			await host.get_tree().process_frame
		player.global_position = home
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  grabs     %d styles, %d pools, seeded room-aware pick, skinned hands, guest view" % [GrabStyles.STYLES.size(),
			HunterRoster.A_Z_IDS.size() + HunterRoster.VOID_IDS.size() + SecretCreatures.IDS.size()])
		print("grabs: all checks OK")
	return _failures
