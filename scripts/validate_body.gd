extends RefCounted

## Headless check on the shared player body.
##
## This suite exists because the previous mannequin passed every check the
## project had and was still visibly broken in game: limbs floating apart, one
## flat tan colour over the whole figure. Nothing was asking the only questions
## that matter about a body -- is it person-shaped, is it the right size, and
## does it have the clips the game plays on it -- because those had always been
## "look at it" questions.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- body

## The capsule in main_3d.tscn: radius 0.25, height 1.7, centred at y=0.85.
const HEIGHT := 1.7
const RADIUS := 0.25
const PLAYER_CLIPS := ["idle", "walk", "sprint", "chase", "crouch"]
const HUNTER_CLIPS := ["idle", "walk", "sprint", "chase", "crouch", "stun"]
const HUNTER_CLIP_LENGTHS := {
	"idle": 2.4,
	"walk": 1.0,
	"sprint": 2.0 / 3.0,
	"chase": 0.5,
	"crouch": 1.0,
	"stun": 1.2,
}

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	var body: Node3D = ModelSlot.instantiate("res://art/props-3d/characters/player.tscn")
	if body == null:
		_fail("the player body scene did not instantiate")
		return _failures
	host.get_tree().root.add_child(body)
	await host.get_tree().process_frame

	var parts := _parts(body)
	if parts.is_empty():
		_fail("the player body has no meshes -- players would be invisible")
		body.queue_free()
		return _failures

	_fits_the_capsule(parts)
	_is_one_figure(parts)
	_carries_its_clips(body, PLAYER_CLIPS)
	_wears_no_colliders(body)
	await _audit_clip_floors(host, body, "player")

	var whole: AABB = parts[0]["box"]
	for part in parts:
		whole = whole.merge(part["box"])
	print("  figure    %d parts, %.2f m tall, %.2f m across, feet at %.3f"
		% [parts.size(), whole.size.y, whole.size.x, whole.position.y])
	print("  player clips  %s" % ", ".join(PLAYER_CLIPS))
	body.queue_free()

	await _every_hunter_model(host)
	if _failures == 0:
		print("body OK")
	return _failures


## Every model in art/props-3d/characters/, not just the ones the roster
## currently draws from. All 26 hunters have models now while 13 have AI, so
## the ones nothing loads yet are exactly the ones a silent build failure would
## hide -- and they get wired in one at a time as the roster fills.
func _every_hunter_model(host: Node) -> void:
	var dir := DirAccess.open("res://art/props-3d/characters")
	if dir == null:
		_fail("no character model directory")
		return
	var checked := 0
	var clipless: Array[String] = []
	var shortest := INF
	var tallest := 0.0
	var lowest_floor := INF
	var highest_floor := -INF
	for file in dir.get_files():
		# The player has a deliberately separate animation contract above. Do
		# not let hunter-only clips (now, or later) leak into player validation.
		if not file.ends_with(".tscn") or file == "player.tscn" \
				or file.begins_with("character_scale") \
				or file.begins_with("admin_"):
			continue
		var path := "res://art/props-3d/characters/%s" % file
		var model: Node3D = ModelSlot.instantiate(path)
		if model == null:
			_fail("%s did not instantiate" % file)
			continue
		host.get_tree().root.add_child(model)
		await host.get_tree().process_frame
		checked += 1
		var parts := _parts(model)
		if parts.is_empty():
			_fail("%s has no meshes" % file)
		else:
			var rest_box := _whole(parts)
			shortest = minf(shortest, rest_box.size.y)
			tallest = maxf(tallest, rest_box.size.y)
			lowest_floor = minf(lowest_floor, rest_box.position.y)
			highest_floor = maxf(highest_floor, rest_box.position.y)
			_expect(rest_box.size.y > 1.4 and rest_box.size.y < 2.8,
				"%s is %.2f m tall at rest; expected a human-sized hunter" % [file, rest_box.size.y])
			_expect(absf(rest_box.position.y) < 0.08,
				"%s rests with its lowest point at y=%.2f instead of floor y=0"
					% [file, rest_box.position.y])
			_expect(rest_box.size.x < 2.5 and rest_box.size.z < 2.5,
				"%s has exploded rest bounds %s" % [file, rest_box])
			# The mannequin passed everything else this suite had and was still
			# visibly broken in game -- limbs standing apart with daylight
			# between them. That was never checked for anything but her; every
			# hunter model gets the same cohesion pass now, using Godot's own
			# global_transform (real parent-bone rotation and all, not an
			# approximation), which is the only thing that can actually tell.
			#
			# Reported, not failed: unlike the plain mannequin, a hunter can
			# legitimately have a part meant to stand apart from her body --
			# a halo hovering over a head, gills flared out from a cheek --
			# and telling those from a real disconnection needs a look this
			# suite cannot give it. What it CAN do honestly is name every gap
			# so a real one cannot hide among the intentional ones unnoticed.
			var floating: Array[String] = []
			for part in parts:
				var box: AABB = (part["box"] as AABB).grow(0.02)
				var touches := false
				for other in parts:
					if other["name"] == part["name"]:
						continue
					if box.intersects(other["box"]):
						touches = true
						break
				if not touches:
					floating.append(String(part["name"]))
			if not floating.is_empty():
				print("  %-16s stands apart from the rest: %s" % [file, ", ".join(floating)])
		var player := ModelSlot.find_animation_player(model)
		if player == null:
			clipless.append(file)
		else:
			if file == "xivvy.tscn":
				_expect(player.has_animation("flight"),
					"Xivvy has wings but no flight animation")
			if file == "loxelle.tscn":
				_expect(player.has_animation("charge"),
					"Loxelle has no locker charge animation")
			if file == "aki.tscn":
				await _audit_clip_floors(host, model, "hunter")
				_audit_hunter_walk_stability()
			for clip in HUNTER_CLIPS:
				if not player.has_animation(clip):
					_fail("%s has no '%s' clip" % [file, clip])
					continue
				var animation := player.get_animation(clip)
				_expect(animation.length >= 0.1,
					"%s '%s' is too short to animate" % [file, clip])
				_expect(absf(animation.length - HUNTER_CLIP_LENGTHS[clip]) < 0.02,
					"%s '%s' is %.3f s; expected %.3f s"
						% [file, clip, animation.length, HUNTER_CLIP_LENGTHS[clip]])
				_expect(animation.get_track_count() > 0,
					"%s '%s' contains no tracks" % [file, clip])
				_expect(animation.loop_mode != Animation.LOOP_NONE,
					"%s '%s' does not loop" % [file, clip])
				# One pose was not a locomotion audit: a broken knee can hide on the
				# other half of the cycle, and a loop can snap only at its seam. Sample
				# the whole clip, require each foot to make contact at least once, and
				# compare every mesh at the two sides of the loop boundary.
				player.play(clip)
				var foot_contacts := {}
				var loop_start := {}
				for sample_index in 8:
					player.seek(animation.length * float(sample_index) / 8.0, true)
					await host.get_tree().process_frame
					var posed := _parts(model)
					if posed.is_empty():
						_fail("%s vanished while playing '%s'" % [file, clip])
						break
					var posed_box := _whole(posed)
					_expect(_finite_box(posed_box),
						"%s '%s' produced non-finite bounds" % [file, clip])
					_expect(posed_box.size.x < 4.0 and posed_box.size.y < 4.0 \
							and posed_box.size.z < 4.0,
						"%s '%s' exploded to %s" % [file, clip, posed_box.size])
					_expect(posed_box.position.y > -0.15,
						"%s '%s' sinks %.3f m through the floor at %.0f%%"
							% [file, clip, -posed_box.position.y,
								100.0 * sample_index / 8.0])
					var foot_count := 0
					for part in posed:
						var part_name := String(part["name"])
						var box: AABB = part["box"]
						if sample_index == 0:
							loop_start[part_name] = box.get_center()
						if part_name.contains("Foot"):
							foot_count += 1
							foot_contacts[part_name] = minf(
								float(foot_contacts.get(part_name, INF)), box.position.y)
					_expect(foot_count >= 2,
						"%s '%s' has fewer than two visible feet" % [file, clip])
				for foot_name in foot_contacts:
					_expect(float(foot_contacts[foot_name]) < 0.2,
						"%s '%s' never plants %s (lowest point %.2f m)"
							% [file, clip, foot_name, foot_contacts[foot_name]])
				var seam_time := maxf(0.0, animation.length - 0.001)
				player.seek(seam_time, true)
				await host.get_tree().process_frame
				var loop_end := _parts(model)
				var worst_seam := 0.0
				for part in loop_end:
					var part_name := String(part["name"])
					if loop_start.has(part_name):
						worst_seam = maxf(worst_seam, (part["box"] as AABB).get_center() \
							.distance_to(loop_start[part_name]))
				_expect(worst_seam < 0.12,
					"%s '%s' jumps %.3f m at the loop seam"
						% [file, clip, worst_seam])
			player.stop()
		for node in _walk(model):
			if node is CollisionObject3D:
				_fail("%s carries its own collider '%s'" % [file, node.name])
		model.queue_free()
	_expect(clipless.is_empty(), "no AnimationPlayer on: %s" % ", ".join(clipless))
	print("  roster    %d character models, %.2f-%.2f m tall, rest floors %.3f-%.3f m"
		% [checked, shortest, tallest, lowest_floor, highest_floor])


## The feminine walk still has deliberate hip motion, but the old curves
## stacked a 4.5-degree pelvis roll with counter-roll through Belly/Chest and
## a large lateral translation. That made the entire hunter visibly wobble.
func _audit_hunter_walk_stability() -> void:
	var source := FileAccess.get_file_as_string(
		"res://art/props-3d/characters/aki.bbmodel")
	var model = JSON.parse_string(source)
	if not model is Dictionary:
		_fail("Aki's editable hunter source is not valid JSON")
		return
	var walk_animation: Dictionary = {}
	for candidate in model.get("animations", []):
		if String(candidate.get("name", "")).to_lower() == "walk":
			walk_animation = candidate
			break
	if walk_animation.is_empty():
		_fail("Aki's editable source has no walk animation")
		return
	var maximum_pelvis_roll := 0.0
	var maximum_pelvis_shift := 0.0
	var maximum_chest_roll := 0.0
	for animator_value in walk_animation.get("animators", {}).values():
		var animator: Dictionary = animator_value
		var bone := String(animator.get("name", ""))
		if bone not in ["Pelvis", "Chest"]:
			continue
		for keyframe_value in animator.get("keyframes", []):
			var keyframe: Dictionary = keyframe_value
			var points: Array = keyframe.get("data_points", [])
			if points.is_empty():
				continue
			var point: Dictionary = points[0]
			if bone == "Pelvis" and String(keyframe.get("channel", "")) == "rotation":
				maximum_pelvis_roll = maxf(maximum_pelvis_roll, absf(float(point.get("z", 0.0))))
			elif bone == "Pelvis" and String(keyframe.get("channel", "")) == "position":
				maximum_pelvis_shift = maxf(maximum_pelvis_shift, absf(float(point.get("x", 0.0))))
			elif bone == "Chest" and String(keyframe.get("channel", "")) == "rotation":
				maximum_chest_roll = maxf(maximum_chest_roll, absf(float(point.get("z", 0.0))))
	_expect(maximum_pelvis_roll <= 1.5 and maximum_pelvis_shift <= .4 \
			and maximum_chest_roll <= .7,
		"hunter walk still wobbles (pelvis roll %.2f, shift %.2f, chest roll %.2f)"
			% [maximum_pelvis_roll, maximum_pelvis_shift, maximum_chest_roll])


## Rest-pose alignment can pass while an animated foot still cuts through the
## slab. Sample the actual player and one representative hunter across every
## gameplay clip; all hunters share the same locomotion curves and dimensions.
func _audit_clip_floors(host: Node, model: Node3D, label: String) -> void:
	var player := ModelSlot.find_animation_player(model)
	if player == null:
		_fail("%s has no AnimationPlayer for floor audit" % label)
		return
	var readings: Array[String] = []
	var clips := HUNTER_CLIPS if label == "hunter" else PLAYER_CLIPS
	for clip in clips:
		if not player.has_animation(clip):
			continue
		var animation := player.get_animation(clip)
		var lowest := INF
		player.play(clip)
		for sample_index in 16:
			player.seek(animation.length * float(sample_index) / 16.0, true)
			await host.get_tree().process_frame
			var posed := _parts(model)
			if posed.is_empty():
				continue
			lowest = minf(lowest, _whole(posed).position.y)
		readings.append("%s %.3f" % [clip, lowest])
		_expect(lowest >= -0.01,
			"%s '%s' clips %.3f m through floor y=0" % [label, clip, -lowest])
	player.stop()
	print("  %-9s animated floor minima: %s" % [label, ", ".join(readings)])


func _parts(body: Node3D) -> Array:
	var out := []
	for node in _walk(body):
		var mesh := node as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			out.append({"name": mesh.name, "box": mesh.global_transform * mesh.get_aabb()})
	return out


func _whole(parts: Array) -> AABB:
	var box: AABB = parts[0]["box"]
	for part in parts:
		box = box.merge(part["box"])
	return box


func _finite_box(box: AABB) -> bool:
	return is_finite(box.position.x) and is_finite(box.position.y) and is_finite(box.position.z) \
		and is_finite(box.size.x) and is_finite(box.size.y) and is_finite(box.size.z)


func _walk(node: Node) -> Array:
	var out := [node]
	for child in node.get_children():
		out += _walk(child)
	return out


## A body that does not match its own collider walks through walls its capsule
## stops at, or floats above the floor it stands on.
func _fits_the_capsule(parts: Array) -> void:
	var whole: AABB = parts[0]["box"]
	for part in parts:
		whole = whole.merge(part["box"])
	_expect(absf(whole.position.y) < 0.05,
		"the body's feet sit at y=%.3f instead of on the floor" % whole.position.y)
	_expect(absf(whole.size.y - HEIGHT) < 0.08,
		"the body is %.2f m tall; its capsule is %.2f m" % [whole.size.y, HEIGHT])
	# Arms out to the side are wider than the capsule and that is fine; a body
	# twice its own collider is not.
	_expect(whole.size.x < RADIUS * 4.0,
		"the body is %.2f m across, far wider than its %.2f m collider"
			% [whole.size.x, RADIUS * 2.0])


## Every part touches another part. The old mannequin's head, arms and legs
## hung in the air with daylight between them, which no flag anywhere recorded.
func _is_one_figure(parts: Array) -> void:
	for part in parts:
		var box: AABB = (part["box"] as AABB).grow(0.02)
		var touches := false
		for other in parts:
			if other["name"] == part["name"]:
				continue
			if box.intersects(other["box"]):
				touches = true
				break
		if not touches:
			_fail("'%s' floats free of the rest of the body" % part["name"])


## ModelSlot asks for these by name, and AnimationPlayer.has_animation is
## case-sensitive, so a renamed clip is a silently frozen player.
func _carries_its_clips(body: Node3D, required_clips: Array) -> void:
	var player := ModelSlot.find_animation_player(body)
	if player == null:
		_fail("the body has no AnimationPlayer, so remote players never move")
		return
	for clip in required_clips:
		if not player.has_animation(clip):
			_fail("the body has no '%s' clip" % clip)
			continue
		var animation := player.get_animation(clip)
		_expect(animation.loop_mode != Animation.LOOP_NONE,
			"'%s' does not loop, so it plays once and the body freezes" % clip)


## A character's only collider is the CharacterBody3D's own shape. Exported
## "-colonly" meshes gave the first mannequin twenty-one static bodies of its
## own and dropped the player through the floor.
func _wears_no_colliders(body: Node3D) -> void:
	for node in _walk(body):
		if node is CollisionObject3D:
			_fail("the body carries its own collider '%s'" % node.name)
