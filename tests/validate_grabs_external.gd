extends RefCounted

## Hunter grabs from the outside: every style the way another player sees it. The runner's own state packets are
## recorded on the runner's machine, then replayed into RemotePlayers at the send rate, the way a guest receives them, onto a
## guest copy of the hunter. For both machines, every frame, the suite checks:
## - Snaps: nothing jumps at the start, during the hold, at the end or on release, and both bodies settle back afterwards.
## - The guest copy against the runner's own body: the runner's orientation and hips match.
## - Room: the feet stay above the floor and no body part is inside a wall.
## - Contact: her hands are on the runner and the runner's held hands are on her (both within 3 cm).
## - Overlap: the two bodies' core boxes do not sink into each other.
## - Her body faces the runner and her head turns to them.
##   godot --headless --path . res://tests/scenes/validate.tscn -- grabs_external     (GRABS_QUICK=1: one hunter per style)

const ARENA := preload("res://tests/grab_arena.gd")
const GRABS := preload("res://tests/validate_grabs.gd")
## Hunters tried in every style their pool has, besides the grabs suite's own one per style.
const SAMPLES := ["aki", "kathy", "xivvy", "void_red", "white_wolf_spider"]
const BONES := FirstPersonBody.BONES
const CORE := ["Head", "Chest", "Belly", "Pelvis"]
const CONTACT := .03
## A body part moving faster than this has jumped (0.2 m in a 60 fps frame; the fastest grab moves about 4 m/s); the
## headless run's frames vary, so it is a speed, not a distance per frame.
const SNAP_SPEED := 12.0
## A whole body turning faster than this has snapped round (25 degrees in a 60 fps frame).
const SNAP_TURN_SPEED := deg_to_rad(1500.0)
## The guest copy against the runner's own body, at the hold.
const MATCH := .06
const MATCH_TURN := deg_to_rad(10.0)
## Her body to what she holds: a one-handed grip out at her side (the collar drag) is about 35 degrees off her front.
const FACING := deg_to_rad(40.0)
const LOOKING := deg_to_rad(15.0)
## After the grab ends, her model and the runner's copy are back in their own pose within this long.
const SETTLE := .7
const PEER := 7

var _failures := 0
var _frames := 0
var _cases := 0
var _debug := not OS.get_environment("GRAB_EXT_DEBUG").is_empty()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## The mesh boxes of one bone: the bone itself when it is a mesh, and the skin layers on it (not the bones below it).
static func _boxes(bone: Node) -> Array:
	var out := []
	for node in [bone] + bone.get_children():
		if node is MeshInstance3D and (node == bone or not String(node.name) in BONES) and (node as MeshInstance3D).mesh != null \
				and (node as MeshInstance3D).is_visible_in_tree():
			out.append(node)
	return out


static func _bone_points(root: Node3D) -> Dictionary:
	var out := {}
	for bone_name in BONES:
		var bone := root.find_child(bone_name, true, false) as Node3D
		if bone != null:
			var boxes := _boxes(bone)
			out[bone_name] = (boxes[0] as MeshInstance3D).global_transform * (boxes[0] as MeshInstance3D).mesh.get_aabb().get_center() \
				if not boxes.is_empty() else bone.global_position
	return out


## The lowest point of any of the body's boxes, and which part it is on.
static func _lowest(root: Node3D) -> Array:
	var low := INF
	var part := ""
	for bone_name in BONES:
		var bone := root.find_child(bone_name, true, false)
		if bone == null:
			continue
		for mesh in _boxes(bone):
			var box := (mesh as MeshInstance3D).mesh.get_aabb()
			for corner in 8:
				var y := ((mesh as MeshInstance3D).global_transform * box.get_endpoint(corner)).y
				if y < low:
					low = y
					part = bone_name if mesh == bone else "%s/%s" % [bone_name, (mesh as Node).name]
	return [low, part]


## How deep `point` is inside a core box of `root` (as a share of that box's half size, 0 = outside): > 0 means inside.
static func _inside_core(root: Node3D, point: Vector3) -> String:
	for bone_name in CORE:
		var bone := root.find_child(bone_name, true, false)
		if bone == null:
			continue
		for mesh in _boxes(bone):
			var box := (mesh as MeshInstance3D).mesh.get_aabb()
			var local := (mesh as MeshInstance3D).global_transform.affine_inverse() * point
			# the middle 70% of the box: touching or resting against it is fine, being through it is not
			var core := box.grow(-0.15 * minf(box.size.x, minf(box.size.y, box.size.z)))
			if core.has_point(local):
				return bone_name
	return ""


static func _in_wall(space: PhysicsDirectSpaceState3D, point: Vector3, exclude: Array, mask: int) -> bool:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = point
	query.exclude = exclude
	query.collision_mask = mask
	return not space.intersect_point(query, 1).is_empty()


## Where the hunter's model faces, flat: the view's facing turned by her model's pin (grab_rest is the model under the view).
static func _hunter_forward(view: Node3D) -> Vector3:
	var model := view.get("_model") as Node3D
	var rest: Transform3D = model.get_meta("grab_rest", model.transform)
	var basis := model.global_basis.orthonormalized() * rest.basis.orthonormalized().inverse()
	var forward := -basis.z
	return Vector3(forward.x, 0.0, forward.z).normalized()


func _hunter(parent: Node, id: String, at: Vector3, facing: Vector3) -> HunterView3D:
	var brain := HunterBrain.new(Vector2(at.x, at.z), "GRAB-EXT", id, "standard")
	brain.activate_at(Vector2(at.x, at.z))
	brain.state = HunterBrain.State.WANDER
	var view := HunterView3D.new()
	view.brain = brain
	parent.add_child(view)
	view.global_position = at
	view.look_at(at + facing, Vector3.UP)
	# nothing steps her brain here: start the clip a route would have her in, so her bones are driven as they are in play
	ModelSlot.play_if_available(view.get("_animation_player") as AnimationPlayer, "idle")
	return view


static func _rids(nodes: Array) -> Array:
	var out := []
	for node in nodes:
		if node is CollisionObject3D:
			out.append((node as CollisionObject3D).get_rid())
		for body in (node as Node).find_children("*", "CollisionObject3D", true, false):
			out.append((body as CollisionObject3D).get_rid())
	return out


## One body seen over time: every frame's part positions, checked for jumps, the floor and the walls.
class Track:
	var label := ""
	var last := {}
	var last_basis := Basis.IDENTITY
	var worst_jump := 0.0
	var worst_part := ""
	var worst_at := 0.0
	var worst_turn := 0.0
	var turn_at := 0.0
	var lowest := INF
	var low_at := 0.0
	var lowest_part := ""
	var walled := ""

	func _init(name: String) -> void:
		label = name

	func see(points: Dictionary, basis: Basis, at: float, low: float, wall: String, low_part: String, delta: float) -> void:
		var frame := maxf(delta, 1.0 / 60.0)   # never stricter than a 60 fps frame
		for part in points:
			if last.has(part):
				var speed := (points[part] as Vector3).distance_to(last[part]) / frame
				if speed > worst_jump:
					worst_jump = speed
					worst_part = part
					worst_at = at
		if not last.is_empty():
			var turn := last_basis.orthonormalized().get_rotation_quaternion().angle_to(basis.orthonormalized().get_rotation_quaternion()) / frame
			if turn > worst_turn:
				worst_turn = turn
				turn_at = at
		last = points
		last_basis = basis
		if low < lowest:
			lowest = low
			low_at = at
			lowest_part = low_part
		if walled.is_empty() and not wall.is_empty():
			walled = "%s at %.2f s" % [wall, at]


## One frame of `root` for `track`; returns its part positions.
func _see(track: Track, root: Node3D, at: float, floor_y: float, space: PhysicsDirectSpaceState3D, exclude: Array, mask: int,
		check_room: bool) -> Dictionary:
	var points := _bone_points(root)
	var wall := ""
	if check_room:
		for part in points:
			if _in_wall(space, points[part], exclude, mask):
				wall = part
				break
	var low := _lowest(root) if check_room else [INF, ""]
	track.see(points, root.global_basis, at, float(low[0]) - floor_y, wall, String(low[1]), root.get_process_delta_time())
	return points


func _expect_track(track: Track, label: String, floored: bool) -> void:
	_expect(track.worst_jump <= SNAP_SPEED, "%s: %s's %s jumps (%.1f m/s for a frame) at %.2f s" % [label, track.label,
		track.worst_part, track.worst_jump, track.worst_at])
	_expect(track.worst_turn <= SNAP_TURN_SPEED, "%s: %s snaps round (%.0f deg/s for a frame) at %.2f s" % [label, track.label,
		rad_to_deg(track.worst_turn), track.turn_at])
	# lying on the floor, a box may rest on it (rounded and leaned), never sink through
	_expect(track.lowest > (-.04 if floored else -.02), "%s: %s's %s is %.0f cm into the floor at %.2f s" % [label, track.label,
		track.lowest_part, -track.lowest * 100.0, track.low_at])
	_expect(track.walled.is_empty(), "%s: %s has a part inside a wall (%s)" % [label, track.label, track.walled])


func _expect_case(route: Node, player: PlayerController3D, grab: HunterGrab, style: String, id: String, place: Dictionary,
		where: String) -> void:
	var label := "%s/%s/%s" % [where, style, id]
	var stand: Vector3 = place["stand"]
	var facing: Vector3 = place["facing"]
	var tree := route.get_tree()
	var space := player.get_world_3d().direct_space_state
	var mask := player.collision_mask
	# caught from behind: running away from her, facing away
	player.global_position = stand
	player.velocity = Vector3.ZERO
	player._yaw = atan2(facing.x, facing.z)
	player._pitch = 0.0
	player._apply_look_rotation()
	var view := _hunter(route, id, stand + facing * .8, -facing)
	var sender := RemotePlayers.new()
	sender.local_player = player
	route.add_child(sender)
	for _i in 30:   # settled in: a hunter just spawned is still rising into her pose
		await tree.process_frame
	var room := HunterGrab.probe_room(space, stand, stand + facing * .8, -facing, [player.get_rid(), view.get_rid()], mask)
	if not GrabStyles.fits(style, room):
		view.queue_free()
		sender.queue_free()
		await tree.process_frame
		return
	_cases += 1
	if OS.get_environment("GRAB_EXT_DEBUG") == "rig":
		_dump(view.get("_model"), 0)
		for b in ["Belly", "Pelvis", "Chest", "R-Arm"]:
			var a := view.find_child(b, true, false)
			var m := (view.get("_model") as Node).find_child(b, true, false)
			print("FIND ", b, " view:", a.get_path() if a else "none", " model:", m.get_path() if m else "none")
	var floored := style in GRABS.FLOORED
	var walls_only := _rids([player, view])
	var model := view.get("_model") as Node3D
	var rest := model.transform
	# 1. on the runner's own machine: every frame's packet, her model and the runner's body
	var recorded := []
	var clock := 0.0
	var her := Track.new("her model (runner's machine)")
	var own := Track.new("the runner")
	var waited := -.4
	while waited < 0.0:   # her last steps before the catch: the grab starts from the pose she was in
		await tree.process_frame
		var delta := tree.root.get_process_delta_time()
		waited += delta
		clock += delta
		recorded.append([clock, sender._local_state().duplicate(true)])
		_see(her, model, waited, stand.y, space, walls_only, mask, true)
	grab.play(player, view, id, .5, style)
	waited = 0.0
	var held_runner := {}
	var held_hunter := {}
	var held_basis := Basis.IDENTITY
	var end := GrabStyles.duration(style) + .4
	while waited < end:
		await tree.process_frame
		var delta := tree.root.get_process_delta_time()
		waited += delta
		clock += delta
		_frames += 1
		recorded.append([clock, sender._local_state().duplicate(true)])
		_see(her, model, waited, stand.y, space, walls_only, mask, true)
		if _debug:
			var arm_side := OS.get_environment("GRAB_EXT_SIDE") if OS.has_environment("GRAB_EXT_SIDE") else "R"
			var ra := model.find_child(arm_side + "-Arm", true, false) as Node3D
			var rf := model.find_child(arm_side + "-Forearm", true, false) as Node3D
			var rh := model.find_child(arm_side + "-Hand", true, false) as Node3D
			print("ARM %.3f reach %.3f gap %.3f arm %s fore %s hand %s sc %s fsc %s hsc %s" % [waited, HunterGrab.reach_of(HunterGrab.arm_chain(view, "R")), grab.contact_gap, ra.global_position, rf.global_position, rh.global_position, ra.scale, rf.scale, rh.scale])
			print("HOST %.3f model %s low %s head %s rfoot %s anim %s pos %.2f belly %s pelvis %s" % [waited, model.global_position, _lowest(model),
				(model.find_child("Head", true, false) as Node3D).global_position, (model.find_child("R-Foot", true, false) as Node3D).global_position,
				(view.get("_animation_player") as AnimationPlayer).current_animation, (view.get("_animation_player") as AnimationPlayer).current_animation_position,
				(model.find_child("Belly", true, false) as Node3D).rotation_degrees, (model.find_child("Pelvis", true, false) as Node3D).position])
		var body := player.first_person_body().model
		# the first frame is the first-person model coming on (nobody sees it switch): from the next one on it is watched
		if waited > .05:
			held_runner = _see(own, body, waited, stand.y, space, walls_only, mask, true)
			held_basis = body.global_basis.orthonormalized()
		held_hunter = _bone_points(model)
	grab.release()
	var released := clock
	var settle := Track.new("her model after release (runner's machine)")
	waited = 0.0
	while waited < SETTLE + .2:
		await tree.process_frame
		var delta := tree.root.get_process_delta_time()
		waited += delta
		clock += delta
		recorded.append([clock, sender._local_state().duplicate(true)])
		_see(settle, model, waited, stand.y, space, walls_only, mask, false)
		if _debug:
			print("REL %.3f model %s head %s ease %.3f belly %s pelvis %s chest %s" % [waited, model.position, (model.find_child("Head", true, false) as Node3D).global_position, float(view.get("_grab_ease")),
				(model.find_child("Belly", true, false) as Node3D).rotation_degrees, (model.find_child("Pelvis", true, false) as Node3D).position, (model.find_child("Chest", true, false) as Node3D).rotation_degrees])
	_expect_track(her, label, false)
	_expect_track(own, label, floored)
	_expect_track(settle, label, false)
	_expect(model.transform.is_equal_approx(rest), "%s: her model is not back in place %.1f s after release" % [label, SETTLE + .2])
	view.queue_free()
	sender.queue_free()
	player.global_position = stand + Vector3.UP * 30.0   # out of the way: from here on only the guest's copies are drawn
	await tree.process_frame
	# 2. on a guest's machine: the same packets at the send rate, into RemotePlayers, onto her own copy of the hunter
	var guest_view := _hunter(route, id, stand + facing * .8, -facing)
	var remote := RemotePlayers.new()
	route.add_child(remote)
	for _i in 30:
		await tree.process_frame
	var guest_model := guest_view.get("_model") as Node3D
	var guest_rest := guest_model.transform
	var exclude := _rids([player, guest_view])
	var copy_track := Track.new("the guest's copy of the runner")
	var her_track := Track.new("her model (guest)")
	var after_track := Track.new("her model after the grab (guest)")
	var next := 0
	var since := 1.0
	var guest_clock := 0.0
	var sent := []
	var worst_grip := 0.0
	var worst_hand := 0.0
	var overlap := ""
	var facing_off := 0.0
	var looking_off := 0.0
	var copy: Node3D = null
	var copy_thighs := {}
	var last_runner := {}
	var last_hunter := {}
	var last_basis := Basis.IDENTITY
	var grab_ended_at := INF
	while guest_clock < clock + .2:
		await tree.process_frame
		var delta := tree.root.get_process_delta_time()
		guest_clock += delta
		since += delta
		if since >= 1.0 / RemotePlayers.SEND_HZ:
			since = 0.0
			while next < recorded.size() and float(recorded[next][0]) <= guest_clock:
				next += 1
			if next > 0:
				var state: Dictionary = (recorded[next - 1][1] as Dictionary).duplicate(true)
				remote.receive_state(PEER, state)
				sent = RemotePlayers._grab_packet(state)
				if sent.is_empty() and grab_ended_at == INF and float(recorded[next - 1][0]) >= released:
					grab_ended_at = guest_clock
		copy = remote._bodies.get(PEER)
		if copy == null:
			continue
		if not copy.has_meta("ext_seen"):
			copy.set_meta("ext_seen", guest_clock)
		if guest_clock - float(copy.get_meta("ext_seen")) < .25:
			continue   # just made: its clip has not started yet
		if copy_thighs.is_empty():
			for thigh in ["L-Thigh", "R-Thigh"]:
				var node := copy.find_child(thigh, true, false) as Node3D
				if node != null:
					copy_thighs[thigh] = node
		var t := float(sent[1]) if not sent.is_empty() else -1.0
		# the runner's copy is followed until the grab ends: a runner is let go when they respawn somewhere else or start
		# spectating (and are no longer drawn), so how the copy stands back up is never seen
		var points := _bone_points(copy) if grab_ended_at < INF else _see(copy_track, copy, guest_clock, stand.y, space, exclude,
			mask, true)
		var hunter := _see(after_track if grab_ended_at < INF else her_track, guest_model, guest_clock,
			stand.y, space, exclude, mask, grab_ended_at == INF)
		if _debug:
			var hd := guest_view.find_child("Head", true, false) as Node3D
			print("COPY %.3f pos %s rot %s" % [guest_clock, copy.global_position, copy.rotation_degrees])
			print("GUEST %.3f t %.2f model %s rot %s head %s hq %s lh %s ease %.2f clip %s" % [guest_clock, t, guest_model.global_position,
				guest_model.global_rotation_degrees, hunter.get("Head", Vector3.ZERO), hd.quaternion, hunter.get("L-Hand", Vector3.ZERO),
				float(guest_view.get("_grab_ease")), (guest_view.get("_animation_player") as AnimationPlayer).current_animation])
			print("   belly %s pelvis %s chest %s sent %s" % [(guest_view.find_child("Belly", true, false) as Node3D).rotation_degrees,
				(guest_view.find_child("Pelvis", true, false) as Node3D).position, (guest_view.find_child("Chest", true, false) as Node3D).rotation_degrees, sent])
		if sent.is_empty() or t < GrabStyles.REACH_SECONDS + GrabStyles.ACT_SECONDS + .15:
			continue
		var pose := GrabStyles.pose(style, t, {})
		var basis := copy.global_basis.orthonormalized()
		for entry in HunterGrab.contacts(copy.global_position, basis, pose["arms"]):
			var g := HunterGrab.grip_point(HunterGrab.arm_chain(guest_view, String(entry[0]))).distance_to(entry[1])
			worst_grip = maxf(worst_grip, g)
			if _debug:
				var ch := HunterGrab.arm_chain(guest_view, String(entry[0]))
				print("GRIP %.3f t %.2f shown %s gap %.3f reach %.3f span %.3f fsc %s" % [guest_clock, t, copy.get_meta("grab_shown", []), g, HunterGrab.reach_of(ch),
					(ch["arm"] as Node3D).global_position.distance_to(entry[1]), (ch["arm"] as Node3D).scale])
		if String(pose.get("hands", "")) == "held":
			for entry in HunterGrab.runner_hand_targets(copy, guest_view, pose, Vector3.FORWARD, t):
				worst_hand = maxf(worst_hand, HunterGrab.grip_point(HunterGrab.arm_chain(copy, String(entry[0]))).distance_to(entry[1]))
		if overlap.is_empty():
			for part in CORE:
				if points.has(part):
					var into := _inside_core(guest_model, points[part])
					if not into.is_empty():
						overlap = "the runner's %s is inside her %s at %.2f s" % [part, into, t]
						break
			for part in CORE:
				if overlap.is_empty() and hunter.has(part):
					var into := _inside_core(copy, hunter[part])
					if not into.is_empty():
						overlap = "her %s is inside the runner's %s at %.2f s" % [part, into, t]
		if t >= GrabStyles.duration(style) - .01:
			last_runner = points
			last_hunter = hunter
			last_basis = basis
			# her body square to the runner, at their chest (not when the runner is over her shoulder, nor right on top of her)
			var held: Vector3 = points.get("Chest", copy.global_position)
			var to_runner := held - (hunter.get("Pelvis", guest_model.global_position) as Vector3)   # from her model, where it is
			to_runner.y = 0.0
			if style != GrabStyles.SHOULDER_CARRY and to_runner.length() > .35:
				facing_off = maxf(facing_off, _hunter_forward(guest_view).angle_to(to_runner.normalized()))
			var head := guest_view.find_child("Head", true, false) as Node3D
			if head != null and style != GrabStyles.SHOULDER_CARRY and not bool(pose.get("her_look_ahead", false)) \
					and points.has("Head"):
				var look := HunterGrab.face_forward(head, GrabStyles.look_for(id), Vector3.FORWARD)
				looking_off = maxf(looking_off, look.angle_to((points["Head"] as Vector3) - head.global_position))
	_expect(copy != null, "%s: the guest never drew the runner" % label)
	_expect_track(copy_track, label, floored)
	_expect_track(her_track, label, false)
	_expect_track(after_track, label, false)
	_expect(worst_grip < CONTACT, "%s: a guest sees her grip %.1f cm off the runner" % [label, worst_grip * 100.0])
	_expect(worst_hand < CONTACT, "%s: a guest sees the runner's hand %.1f cm off where she holds it" % [label, worst_hand * 100.0])
	_expect(overlap.is_empty(), "%s: a guest sees %s" % [label, overlap])
	_expect(facing_off < FACING, "%s: a guest sees her body %.0f deg off the runner" % [label, rad_to_deg(facing_off)])
	_expect(looking_off < LOOKING, "%s: a guest sees her look %.0f deg past the runner's face" % [label, rad_to_deg(looking_off)])
	_expect(not last_runner.is_empty(), "%s: the guest never drew the hold" % label)
	if not last_runner.is_empty():
		# the guest's hold is the runner's own: same hips, head and turn, same hands on them
		for part in ["Pelvis", "Chest", "Head"]:
			if held_runner.has(part) and last_runner.has(part):
				var gap := (last_runner[part] as Vector3).distance_to(held_runner[part])
				_expect(gap < MATCH, "%s: the guest's runner %s is %.0f cm from the runner's own" % [label, part, gap * 100.0])
		for part in ["Pelvis", "Head", "L-Hand", "R-Hand"]:
			if held_hunter.has(part) and last_hunter.has(part):
				var gap := (last_hunter[part] as Vector3).distance_to(held_hunter[part])
				_expect(gap < MATCH, "%s: the guest's hunter %s is %.0f cm from the runner's machine's" % [label, part, gap * 100.0])
		var turned := last_basis.get_rotation_quaternion().angle_to(held_basis.get_rotation_quaternion())
		_expect(turned < MATCH_TURN, "%s: the guest's runner is turned %.0f deg from the runner's own" % [label, rad_to_deg(turned)])
	# and once the grab is over, both are back as they were
	_expect(guest_model.transform.is_equal_approx(guest_rest), "%s: a guest's hunter model is still off her body after the grab" % label)
	if copy != null:
		_expect(absf(copy.rotation.x) < .02, "%s: a guest's copy of the runner stays tipped %.0f deg" % [label, rad_to_deg(copy.rotation.x)])
		for thigh in copy_thighs:
			_expect(not (copy_thighs[thigh] as Node).has_meta("carry_rest"), "%s: a guest's copy keeps its legs folded" % label)
	guest_view.queue_free()
	remote.queue_free()
	await tree.process_frame


func _cases_for(style: String) -> Array:
	var ids := [String(GRABS.STYLE_HUNTER[style])]
	if OS.get_environment("GRABS_QUICK").is_empty():
		for id in SAMPLES:
			if GrabStyles.pool_for(id).has(style) and not ids.has(id):
				ids.append(id)
	return ids


## Run in real time, without --fixed-fps: RemoteMotion plays guests back on the wall clock, and a fixed-fps headless run
## races ahead of it (the replay then reads as jumps).
func run(host: Node) -> int:
	var route: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	var player := route.get("player") as PlayerController3D
	var grab := route.get("grab") as HunterGrab
	_expect(player != null and grab != null, "the route has no player or HunterGrab")
	if player != null and grab != null:
		player.input_frozen = true
		player.look_frozen = true
		var home := player.global_position
		for kind in ["open", "hallway"]:
			var place := ARENA.build(route, kind)
			for style in GrabStyles.STYLES:
				if not OS.get_environment("GRAB_EXT_ONLY").is_empty() and style != OS.get_environment("GRAB_EXT_ONLY"):
					continue
				for id in (_cases_for(String(style)) if kind == "open" else [String(GRABS.STYLE_HUNTER[style])]):
					await _expect_case(route, player, grab, String(style), String(id), place, kind)
			(place["root"] as Node).queue_free()
			await host.get_tree().process_frame
		player.global_position = home
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  grabs_external  %d cases, %d frames: guest replay matches, no snaps, clear of floor and walls" % [_cases, _frames])
		print("grabs_external: all checks OK")
	return _failures


func _dump(n: Node, d: int) -> void:
	if n is MeshInstance3D and n.get_parent().name == "Head":
		var box := (n as MeshInstance3D).mesh.get_aabb()
		print("HEADCHILD ", n.name, " aabb ", box, " low ", ((n as MeshInstance3D).global_transform * box.position).y)
	if n is Node3D and (String(n.name) in BONES or d < 3):
		print("RIG ", "  ".repeat(d), n.name, " ", (n as Node3D).position, " ", (n as Node3D).rotation_degrees, " ", n.get_class())
	for c in n.get_children():
		_dump(c, d + 1)
