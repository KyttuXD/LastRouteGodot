extends RefCounted

## Normal-play lens culling (HunterView3D._update_lens_cull): with the camera 0.1-0.4 m from a hunter nothing is culled, with the near
## plane inside a cube that cube is drawn on the culled layer for that frame, and everything is put back when the camera moves off.
## Checked on Verrine and two more pale hunters (Aki, Javelle).
##   godot --headless --path . res://scenes/validate.tscn -- lens_cull

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var tree := host.get_tree()
	var camera := Camera3D.new()
	camera.near = PlayerController3D.FIRST_PERSON_NEAR
	host.add_child(camera)
	camera.current = true
	for id in ["verrine", "aki", "javelle"]:
		var origin := Vector2(5.5, 5.5)
		var brain := HunterBrain.new(origin, "LENS-%s" % id, id, "standard")
		brain.activate_at(origin)
		var view := HunterView3D.new()
		view.brain = brain
		host.add_child(view)
		view.global_position = Vector3.ZERO
		await tree.process_frame
		view.sync_from_brain()
		var model: Node3D = view._model
		var player := ModelSlot.find_animation_player(model)
		if player != null and player.has_animation("idle"):
			player.play("idle")
			player.seek(0.0, true)
			player.pause()
		# a chest box: the point in the middle of her chest, then off her front by 0.1 .. 0.4 m
		var chest := model.find_child("Chest", true, false) as MeshInstance3D
		var centre := chest.global_transform * chest.mesh.get_aabb().get_center()
		camera.global_position = centre
		view._update_lens_cull()
		_expect(view._lens_culled.has(chest), "%s: the camera inside her chest does not cull it" % id)
		_expect(chest.layers == HunterView3D.LENS_LAYER, "%s: the chest is not on the culled layer" % id)
		_expect(camera.cull_mask & HunterView3D.LENS_LAYER == 0, "%s: the camera still draws the culled layer" % id)
		for distance in [0.1, 0.2, 0.3, 0.4]:
			var front := chest.global_transform.basis.z.normalized()
			var half := chest.mesh.get_aabb().size.z * .5 * chest.global_transform.basis.get_scale().z
			camera.global_position = centre + front * (half + distance)
			view._update_lens_cull()
			_expect(not view._lens_culled.has(chest), "%s: the chest is culled with the camera %.1f m off its face" % [id, distance])
			_expect(chest.layers & HunterView3D.LENS_LAYER == 0, "%s: the chest stayed on the culled layer after the camera left" % id)
		camera.global_position = Vector3(0, 1.3, 6.0)
		view._update_lens_cull()
		_expect(view._lens_culled.is_empty(), "%s: something is culled with the camera 6 m away" % id)
		view.queue_free()
	return _failures
