extends RefCounted

## Steve and Alex: the player mannequin matches the Minecraft player model, so standard 64x64 skins map 1:1. Both arm styles (classic
## 4 px, slim 3 px) have UVs exactly per the Minecraft layout (the slim arm never touches the unused 4th texture column), the overlay
## shells sit just outside the base cubes, swapping the style leaves the rig, bones and clips intact, and the hands (first person and
## XR) and co-op bodies follow it.
##
##   godot --headless --path . res://scenes/validate.tscn -- player_arms

var _failures := 0

## Base-layer arm boxes (origin x, y) and their width in skin pixels, per style; overlay boxes sit 16 px lower / at (48,48).
const ARM_ORIGINS := {"R": [Vector2i(40, 16), Vector2i(40, 32)], "L": [Vector2i(32, 48), Vector2i(48, 48)]}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _arm_uvs(root: Node, side: String) -> PackedVector2Array:
	var found := PackedVector2Array()
	for bone in ["Arm", "Forearm", "Hand"]:
		var mesh_node := root.find_child("%s-%s" % [side, bone], true, false) as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var uvs = mesh_node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
			if uvs is PackedVector2Array:
				found.append_array(uvs)
	return found


func _in_box(point: Vector2, origin: Vector2i, width: int) -> bool:
	return Rect2(origin.x, origin.y, 8 + 2 * width, 16).grow(.6).has_point(point)


func _bones(root: Node) -> Dictionary:
	var found := {}
	for node in root.find_children("*", "Node3D", true, false):
		found[root.get_path_to(node)] = (node as Node3D).transform
	return found


func run(host: Node) -> int:
	await host.get_tree().process_frame
	var classic_scene := load(PlayerModels.BLOCKY) as PackedScene
	var slim_scene := load(PlayerModels.BLOCKY_SLIM) as PackedScene
	_expect(classic_scene != null and slim_scene != null, "a mannequin scene did not load")
	if classic_scene == null or slim_scene == null:
		return 1
	var classic := classic_scene.instantiate()
	var slim := slim_scene.instantiate()
	host.add_child(classic)
	host.add_child(slim)

	# ---- UVs per the Minecraft layout, both arm styles, including the separate left-arm regions
	for style in ["classic", "slim"]:
		var root: Node = classic if style == "classic" else slim
		var width := 4 if style == "classic" else 3
		for side in ["R", "L"]:
			var uvs := _arm_uvs(root, side)
			_expect(uvs.size() > 0, "%s %s arm has no UVs" % [style, side])
			var origins: Array = ARM_ORIGINS[side]
			var outside := 0
			var unused_column := 0
			for uv in uvs:
				var at := Vector2(uv.x * 64.0, uv.y * 64.0)
				if not (_in_box(at, origins[0], width) or _in_box(at, origins[1], width)):
					outside += 1
				# the slim box is 2 px narrower than the classic one: its last two texture columns are unused
				for origin in origins:
					var strip := Rect2(origin.x + 8 + 2 * width + .6, origin.y, 2.0 * (4 - width) - 1.2, 16)
					if width == 3 and strip.size.x > 0 and strip.has_point(at):
						unused_column += 1
			_expect(outside == 0, "%s %s arm: %d vertices outside its Minecraft UV box" % [style, side, outside])
			_expect(unused_column == 0, "%s %s arm touches the unused 4th texture column (%d)" % [style, side, unused_column])
	# the classic arm DOES reach the 14..16 px part of its box, the slim one stops 2 px short
	var classic_right_max := 0.0
	var slim_right_max := 0.0
	for uv in _arm_uvs(classic, "R"):
		if uv.y * 64.0 >= 16 and uv.y * 64.0 <= 32:
			classic_right_max = maxf(classic_right_max, uv.x * 64.0)
	for uv in _arm_uvs(slim, "R"):
		if uv.y * 64.0 >= 16 and uv.y * 64.0 <= 32:
			slim_right_max = maxf(slim_right_max, uv.x * 64.0)
	_expect(is_equal_approx(classic_right_max, 56.0) and is_equal_approx(slim_right_max, 54.0), "arm UV extents are wrong: classic %.1f (56), slim %.1f (54)" % [classic_right_max, slim_right_max])

	# ---- overlay shells: every part also carries its outer layer (hat, jacket, sleeves, pants), mapped to the second-layer regions
	var shells := {"Head": Rect2(32, 0, 32, 16), "Chest": Rect2(16, 32, 24, 16), "Belly": Rect2(16, 32, 24, 16), "R-Arm": Rect2(40, 32, 16, 16),
		"L-Arm": Rect2(48, 48, 16, 16), "R-Thigh": Rect2(0, 32, 16, 16), "L-Thigh": Rect2(0, 48, 16, 16)}
	var with_shell := 0
	for bone in shells:
		for root in [classic, slim]:
			var node := root.find_child(bone, true, false) as MeshInstance3D
			var in_shell := 0
			var in_base := 0
			for surface in node.mesh.get_surface_count():
				for uv in node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]:
					if (shells[bone] as Rect2).grow(.6).has_point(Vector2(uv.x * 64.0, uv.y * 64.0)):
						in_shell += 1
					else:
						in_base += 1
			if in_shell > 0 and in_base > 0:
				with_shell += 1
	_expect(with_shell == shells.size() * 2, "%d of %d parts carry both a base and an overlay shell" % [with_shell, shells.size() * 2])
	# the shell is inflated: the head mesh (base + hat) is wider than a bare 8 px head would be
	var head_bounds := (classic.find_child("Head", true, false) as MeshInstance3D).mesh.get_aabb()
	var chest_bounds := (classic.find_child("Chest", true, false) as MeshInstance3D).mesh.get_aabb()
	_expect(head_bounds.size.x / chest_bounds.size.x > 1.0 and head_bounds.size.x / chest_bounds.size.x < 1.12, "the head/body proportion is off (%.2f, expected about 9/8.5 with shells)" % (head_bounds.size.x / chest_bounds.size.x))

	# ---- width: slim arms are 3/4 of classic
	var classic_arm := (classic.find_child("R-Arm", true, false) as MeshInstance3D).mesh.get_aabb()
	var slim_arm := (slim.find_child("R-Arm", true, false) as MeshInstance3D).mesh.get_aabb()
	var ratio := slim_arm.size.x / classic_arm.size.x
	_expect(ratio > .68 and ratio < .86, "the slim arm is %.2f of the classic width, expected about 0.75-0.8" % ratio)

	# ---- the rig is identical: same bones, same rest transforms, same clips
	var classic_bones := _bones(classic)
	var slim_bones := _bones(slim)
	_expect(classic_bones.size() == slim_bones.size() and classic_bones.size() > 20, "the two mannequins have different node trees")
	var moved := 0
	for path in classic_bones:
		if slim_bones.has(path) and not (classic_bones[path] as Transform3D).is_equal_approx(slim_bones[path]):
			moved += 1
	_expect(moved == 0, "%d bones rest differently in the slim mannequin" % moved)
	var classic_player := ModelSlot.find_animation_player(classic)
	var slim_player := ModelSlot.find_animation_player(slim)
	_expect(classic_player != null and slim_player != null, "a mannequin has no animation player")
	if classic_player != null and slim_player != null:
		var classic_clips := Array(classic_player.get_animation_list())
		var slim_clips := Array(slim_player.get_animation_list())
		classic_clips.sort()
		slim_clips.sort()
		_expect(classic_clips == slim_clips and classic_clips.size() >= 12, "the clip sets differ: %s vs %s" % [str(classic_clips), str(slim_clips)])
		for clip in ["idle", "walk", "sprint", "crouch", "climb", "jump"]:
			_expect(classic_clips.has(clip), "the mannequin lost its %s clip" % clip)

	# ---- swapping the style on a live body keeps the rig and animations working
	var body := classic_scene.instantiate()
	host.add_child(body)
	var before := _bones(body)
	_expect(PlayerSkin.set_arms(body, true), "the arm swap failed")
	var after := _bones(body)
	var drift := 0
	for path in before:
		if not (before[path] as Transform3D).is_equal_approx(after[path]):
			drift += 1
	_expect(drift == 0, "swapping arms moved %d bones" % drift)
	_expect(is_equal_approx((body.find_child("R-Arm", true, false) as MeshInstance3D).mesh.get_aabb().size.x, slim_arm.size.x), "the body does not carry the slim arm")
	var player := ModelSlot.find_animation_player(body)
	player.play("walk")
	player.advance(.4)
	var arm_pose := (body.find_child("R-Arm", true, false) as Node3D).quaternion
	player.advance(.3)
	_expect(not arm_pose.is_equal_approx((body.find_child("R-Arm", true, false) as Node3D).quaternion), "the walk clip does not move a slim arm")
	for clip in ["climb", "crouch", "jump", "idle"]:
		player.play(clip)
		player.advance(.2)
	_expect(PlayerSkin.set_arms(body, false) and is_equal_approx((body.find_child("R-Arm", true, false) as MeshInstance3D).mesh.get_aabb().size.x, classic_arm.size.x), "swapping back to classic failed")
	# a skin lands on the swapped arms too
	var marker := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	marker.fill(Color(.2, .8, .3, 1.0))
	var texture := ImageTexture.create_from_image(marker)
	PlayerSkin.set_arms(body, true)
	PlayerSkin.apply(body, texture)
	var wearing := 0
	var other := 0
	for node in body.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				if material.albedo_texture == texture:
					wearing += 1
				else:
					other += 1
	_expect(wearing > 0 and other == 0, "the skin reached %d surfaces, %d stayed on the old texture after the swap" % [wearing, other])

	# ---- height: the 1.60 m player (the mannequin is authored at 1.78 m and scaled by PlayerModels.SCALE)
	var tall := classic.find_child("Head", true, false) as MeshInstance3D
	var head_top := (tall.global_transform * tall.mesh.get_aabb()).end.y
	_expect(absf(head_top * PlayerModels.SCALE - 1.78 * PlayerModels.SCALE) < .12, "the mannequin is not authored at about 1.78 m (head top %.2f)" % head_top)
	var slim_head := slim.find_child("Head", true, false) as MeshInstance3D
	_expect(absf((slim_head.global_transform * slim_head.mesh.get_aabb()).end.y - head_top) < .01, "the slim mannequin is a different height")

	# ---- hands: first person and XR follow the style, in both
	var classic_parts := PlayerController3D._mannequin_hand_parts(false)
	var slim_parts := PlayerController3D._mannequin_hand_parts(true)
	_expect(not classic_parts.is_empty() and not slim_parts.is_empty() and classic_parts[0][0] != slim_parts[0][0], "the first-person hand does not have a slim variant")
	var left := XRController3D.new()
	var right := XRController3D.new()
	var origin := XROrigin3D.new()
	host.add_child(origin)
	origin.add_child(left)
	origin.add_child(right)
	var hands := XRHands.new()
	host.add_child(hands)
	var saved_arms := Settings.skin_arms
	Settings.skin_arms = "slim"
	hands.setup(Node3D.new(), origin, left, right)
	_expect(bool(left.find_child("SkinnedHand", true, false).get_meta("slim", false)), "an XR hand is not slim under the slim setting")
	Settings.set_skin_arms("classic")
	hands._wear_skin()
	_expect(not bool(left.find_child("SkinnedHand", true, false).get_meta("slim", true)), "an XR hand did not return to classic")
	Settings.set_skin_arms(saved_arms)
	hands.queue_free()
	origin.queue_free()

	# ---- the setting: auto follows the skin, classic / slim override it; a bad value falls back
	Settings.skin_slim = true
	Settings.set_skin_arms("auto")
	_expect(Settings.effective_slim(), "auto did not follow a slim skin")
	Settings.set_skin_arms("classic")
	_expect(not Settings.effective_slim(), "classic did not override a slim skin")
	Settings.skin_slim = false
	Settings.set_skin_arms("slim")
	_expect(Settings.effective_slim(), "slim did not override a classic skin")
	Settings.set_skin_arms("bogus")
	_expect(Settings.skin_arms == "auto", "a bad arm style was kept")
	Settings.set_skin_arms(saved_arms)

	# ---- co-op: a peer's body takes the arms from the state
	var players := RemotePlayers.new()
	host.add_child(players)
	var peer_body := ModelSlot.instantiate(PlayerModels.SCENE)
	host.add_child(peer_body)
	players._bodies[2] = peer_body
	var skin_image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	skin_image.fill(Color(.3, .3, .9, 1.0))
	var validated := PlayerSkin.validate(skin_image.save_png_to_buffer())
	Backend.skin_sync.accept_download(String(validated["hash"]), true, validated["png"])
	players._apply_peer_skin(2, peer_body, String(validated["hash"]), true)
	_expect(is_equal_approx((peer_body.find_child("R-Arm", true, false) as MeshInstance3D).mesh.get_aabb().size.x, slim_arm.size.x), "a slim peer has classic arms")
	players._apply_peer_skin(2, peer_body, String(validated["hash"]), false)
	_expect(is_equal_approx((peer_body.find_child("R-Arm", true, false) as MeshInstance3D).mesh.get_aabb().size.x, classic_arm.size.x), "a classic peer has slim arms")
	players.queue_free()
	await host.get_tree().process_frame
	peer_body.queue_free()
	body.queue_free()
	classic.queue_free()
	slim.queue_free()
	PlayerSkin.clear_peer_cache()

	if _failures == 0:
		print("  ok    player_arms: Steve and Alex UVs per the Minecraft layout, overlay shells, same rig and clips, arm swap, hands, co-op")
	return _failures
