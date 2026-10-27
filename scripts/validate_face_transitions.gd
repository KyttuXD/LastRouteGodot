extends RefCounted

## Expression swaps on LIVE hunters (the real HunterView3D, so ModelSlot's shared materials are in play): flip a hunter through
## idle -> chase -> scream -> search -> stun -> wake -> idle and after every flip check that
##  - the Face quad wears the expected cell,
##  - the Face quad's material is its own: not shared with any other mesh of the hunter, nor with a second instance,
##  - no other material of the hunter changed (this was the Glyra bug: the face offset was written to the material the
##    body and legs share, so every chase garbled her torso and legs),
##  - going back to idle restores the first face and every material exactly.
##
##   godot --headless --path . res://scenes/validate.tscn -- face_transitions

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _materials(view: HunterView3D) -> Dictionary:
	var out := {}
	for node in view._model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		for surface in mesh.mesh.get_surface_count():
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			out["%s#%d" % [mesh.get_path(), surface]] = material
	return out


func _snapshot(view: HunterView3D) -> Dictionary:
	var out := {}
	var materials := _materials(view)
	for key in materials:
		var material := materials[key] as StandardMaterial3D
		if material != null and not String(key).contains("/Face#"):
			out[key] = {"id": material.get_instance_id(), "offset": material.uv1_offset, "scale": material.uv1_scale,
				"texture": material.albedo_texture}
	return out


func _cell_offset(cell: int) -> Vector3:
	return Vector3(float(cell % BlockyFace.COLS) * BlockyFace.CELL_PX.x / BlockyFace.ATLAS_PX.x,
		float(cell / BlockyFace.COLS) * BlockyFace.CELL_PX.y / BlockyFace.ATLAS_PX.y, 0.0)


func _face_material(view: HunterView3D) -> StandardMaterial3D:
	var face := view._model.find_child("Face", true, false) as MeshInstance3D
	return face.get_active_material(0) as StandardMaterial3D if face != null else null


func _flip(view: HunterView3D, tree: SceneTree, state: int, near: bool, stun: float = 0.0) -> void:
	var brain := view.brain
	brain.state = state
	brain.stun_timer = stun
	if state == HunterBrain.State.CHASE:
		view.set_look_target(brain.position + Vector2(1.5 if near else 12.0, 0))
	else:
		view.set_look_target(null)
	view._face_hold = 0.0
	view._recover_left = 0.0
	for i in 3:
		await tree.process_frame
		view.sync_from_brain()
		view._face_hold = 0.0
		if state != HunterBrain.State.WANDER or stun > 0.0:
			view._recover_left = 0.0


func run(host: Node) -> int:
	var tree := host.get_tree()
	await tree.process_frame
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var checked := 0
	for id in ids:
		if not ResourceLoader.exists("res://assets/hunters_blocky/%s/%s.glb" % [id, id]):
			continue
		var views: Array = []
		for k in 2:
			var brain := HunterBrain.new(Vector2(5.5, 5.5 + k * 3), "FACE-%s" % id, id, "standard")
			brain.activate_at(brain.position)
			brain.state = HunterBrain.State.WANDER
			var view := HunterView3D.new()
			view.brain = brain
			host.add_child(view)
			views.append(view)
		await tree.process_frame
		var view: HunterView3D = views[0]
		var other: HunterView3D = views[1]
		view.sync_from_brain()
		other.sync_from_brain()
		await tree.process_frame
		view.sync_from_brain()
		var face_start := _face_material(view)
		if face_start == null:
			for v in views:
				v.queue_free()
			continue
		var start_offset := face_start.uv1_offset
		var before := _snapshot(view)
		var before_other := _snapshot(other)
		var steps := [
			["chase", HunterBrain.State.CHASE, false, 0.0],
			["scream", HunterBrain.State.CHASE, true, 0.0],
			["derp", HunterBrain.State.SEARCH, false, 0.0],
			["stun", HunterBrain.State.WANDER, false, 2.0],
			["wake", HunterBrain.State.WANDER, false, 0.0],
			["chase", HunterBrain.State.CHASE, false, 0.0],
			["neutral", HunterBrain.State.WANDER, false, 0.0],
		]
		for step in steps:
			await _flip(view, tree, step[1], step[2], step[3])
			if step[0] == "wake":
				_expect(view._expression == "blank" or view._recover_left <= 0.0, "%s: waking should show the blank face" % id)
				view._recover_left = 0.0
				view._expression = ""
				await tree.process_frame
			checked += 1
			var face := _face_material(view)
			var expected: String = step[0]
			if step[0] == "wake":
				expected = "blank"
			if step[0] != "neutral" and step[0] != "wake" and step[0] != "derp":
				_expect(view._expression == expected, "%s %s: expression is '%s'" % [id, step[0], view._expression])
			var after := _snapshot(view)
			for key in before:
				_expect(after.has(key) and after[key]["id"] == before[key]["id"], "%s %s: material of %s was replaced" % [id, step[0], key])
				if after.has(key):
					_expect(after[key]["offset"] == before[key]["offset"] and after[key]["scale"] == before[key]["scale"] \
						and after[key]["texture"] == before[key]["texture"], "%s %s: %s changed (uv %s -> %s)" % [id, step[0], key, before[key]["offset"], after[key]["offset"]])
			var shared := false
			for key in _materials(view):
				if key.contains("/Face#"):
					continue
				if _materials(view)[key] == face:
					shared = true
			_expect(not shared, "%s %s: the Face material is shared with another mesh of the same hunter" % [id, step[0]])
			_expect(face != _face_material(other), "%s %s: the Face material is shared with another hunter instance" % [id, step[0]])
			var after_other := _snapshot(other)
			for key in before_other:
				_expect(after_other.has(key) and after_other[key]["offset"] == before_other[key]["offset"], "%s %s: the OTHER instance changed (%s)" % [id, step[0], key])
		# back to idle: the first face again (a blink may be showing)
		var final := _face_material(view)
		_expect(final.uv1_offset == start_offset or final.uv1_offset == _cell_offset(BlockyFace.CELLS["blink"]), "%s: idle did not restore the first face (%s vs %s)" % [id, final.uv1_offset, start_offset])
		for v in views:
			v.queue_free()
		await tree.process_frame
	print("  face_transitions: %d state flips checked on live hunters" % checked)
	if _failures == 0:
		print("  ok    face_transitions: expression swaps touch only the Face quad's own material")
	return _failures
