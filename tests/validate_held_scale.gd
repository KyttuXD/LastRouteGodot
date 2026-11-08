extends RefCounted

## Third-person held tools: every item's real size in the 1.60 m runner's hand, and where it sits.
##   godot --headless --path . res://tests/scenes/validate.tscn -- held_scale

var _failures := 0


func _bounds(root: Node3D) -> AABB:
	var out := AABB()
	var first := true
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh == null:
			continue
		var box: AABB = mesh_node.global_transform * mesh_node.mesh.get_aabb()
		out = box if first else out.merge(box)
		first = false
	return out


## Real-world length of each tool in the runner's hand (metres, in the old 1.60 m body; times PlayerModels.SCALE / 0.9 for the
## 1.9 m runner): flashlight ~0.2, taser ~0.17, lock-pick set ~0.15, a crowbar ~0.5 (shortened for the blocky body), the rescue axe
## ~0.6, a battery ~0.15, a stim ~0.2, the revive kit case ~0.27.
const LENGTH_RANGE := {
	"flashlight": Vector2(0.16, 0.30), "taser": Vector2(0.13, 0.25), "lockpick": Vector2(0.10, 0.20),
	"crowbar": Vector2(0.42, 0.64), "rescue_axe": Vector2(0.50, 0.74), "battery": Vector2(0.12, 0.26),
	"stim_pack": Vector2(0.14, 0.26), "revive_kit": Vector2(0.20, 0.34),
}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _check_items(remote: RemotePlayers, body: Node3D, label: String) -> void:
	var anchor := remote._remote_hand_anchors.get(91) as Node3D
	var body_box := _bounds(body)
	_expect(absf(body_box.size.y - 1.78 * PlayerModels.SCALE) < .03, "%s: the body is %.2f m, not %.2f" % [label, body_box.size.y, 1.78 * PlayerModels.SCALE])
	for item_id in RemotePlayers.REMOTE_HELD_MODELS:
		remote._sync_remote_held_item(91, body, item_id)
		var item := remote._remote_held_items.get(91) as Node3D
		_expect(item != null, "%s: %s did not appear in the hand" % [label, item_id])
		if item == null:
			continue
		var box := _bounds(item)
		var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
		var range_m: Vector2 = (LENGTH_RANGE[item_id] as Vector2) * (PlayerModels.SCALE / 0.9)
		_expect(longest >= range_m.x and longest <= range_m.y, "%s: %s is %.2f m long (want %.2f-%.2f for the %.2f m body)" % [label, item_id, longest, range_m.x, range_m.y, 1.78 * PlayerModels.SCALE])
		_expect(box.grow(.04).has_point(anchor.global_position), "%s: %s is not gripped (the hand is %.2f m from its bounds)" % [label, item_id, box.get_center().distance_to(anchor.global_position)])
		_expect(body_box.grow(.55).encloses(box), "%s: %s sticks %.2f m out of the body's reach" % [label, item_id, box.get_center().distance_to(body_box.get_center())])
		var share := longest / body_box.size.y
		_expect(share > .05 and share < .5, "%s: %s is %.0f%% of the body height" % [label, item_id, share * 100.0])
		remote._sync_remote_held_item(91, body, "")


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var remote := RemotePlayers.new()
	host.add_child(remote)
	var body: Node3D = ModelSlot.instantiate(RemotePlayers.MODEL)
	body.scale = Vector3.ONE * PlayerModels.SCALE
	host.add_child(body)
	remote._attach_remote_flashlight(91, body)
	await host.get_tree().process_frame
	var anchor := remote._remote_hand_anchors.get(91) as Node3D
	var rest_anchor := anchor.global_position
	_check_items(remote, body, "classic arms")
	PlayerSkin.set_arms(body, true)
	await host.get_tree().process_frame
	_expect(anchor.global_position.distance_to(rest_anchor) < .005, "the Alex arms moved the hand anchor")
	_check_items(remote, body, "slim arms")
	PlayerSkin.set_arms(body, false)
	# the poses: the held item stays at the hand and inside the body's reach in every clip (sitting, climbing, crawling, ...)
	var player := ModelSlot.find_animation_player(body)
	if player != null:
		for clip in player.get_animation_list():
			var length := maxf(player.get_animation(clip).length, .1)
			for k in 4:
				player.play(clip)
				player.seek(length * float(k) / 4.0, true)
				remote._sync_remote_held_item(91, body, "crowbar")
				var item := remote._remote_held_items.get(91) as Node3D
				var box := _bounds(item)
				_expect(box.grow(.04).has_point(anchor.global_position),
					"clip %s at %d/4: the crowbar left the hand" % [clip, k])
				_expect(_bounds(body).grow(.6).encloses(box), "clip %s at %d/4: the crowbar is far from the body" % [clip, k])
				remote._sync_remote_held_item(91, body, "")
	body.queue_free()
	remote.queue_free()
	if _failures == 0:
		print("held_scale: all checks OK")
	return _failures
