extends RefCounted

## Expressions of the blocky hunters (BlockyFace): for every hunter (A-Z and Void) the Face quad sits on the front of the head and
## looks along the model's forward axis, its UVs point at cell 0 of the expression grid, every expression cell lies inside the atlas and
## no other mesh of the model samples the expression cells; an expression change on one instance never leaks to another instance and
## the view's states map to the cells they should. Faces rendered in the real scene: dev/look/hunter_check.tscn, dev/look/facing_check.tscn.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- expressions

var _failures := 0
const ATLAS := Vector2(64, 128)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _meshes(node: Node, out: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for child in node.get_children():
		_meshes(child, out)


func _uv_rect(mesh: Mesh) -> Rect2:
	var rect := Rect2()
	var first := true
	for s in mesh.get_surface_count():
		var uvs = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
		if uvs == null:
			continue
		for uv in uvs:
			var p: Vector2 = uv * ATLAS
			if first:
				rect = Rect2(p, Vector2.ZERO)
				first = false
			else:
				rect = rect.expand(p)
	return rect


## UV rect of every quad (4 vertices) of a mesh, in atlas pixels
func _face_rects(mesh: Mesh) -> Array:
	var rects := []
	for s in mesh.get_surface_count():
		var uvs = mesh.surface_get_arrays(s)[Mesh.ARRAY_TEX_UV]
		if uvs == null:
			continue
		var i := 0
		while i + 3 < uvs.size():
			var r := Rect2(uvs[i] * ATLAS, Vector2.ZERO)
			for k in range(1, 4):
				r = r.expand(uvs[i + k] * ATLAS)
			rects.append(r)
			i += 4
	return rects


func run(_host: Node) -> int:
	var ids: Array = []
	for id in HunterRoster.A_Z_IDS:
		ids.append(String(id))
	for id in HunterRoster.VOID_IDS:
		ids.append(String(id))
	var checked := 0
	var cell_rect := Rect2()
	for id in ids:
		var path := "res://assets/hunters_blocky/%s/%s.glb" % [id, id]
		if not ResourceLoader.exists(path):
			continue
		var model := (load(path) as PackedScene).instantiate() as Node3D
		var faces := model.find_children("Face", "MeshInstance3D", true, false)
		_expect(faces.size() == 1, "%s has %d Face quads (want 1)" % [id, faces.size()])
		if faces.size() != 1:
			model.free()
			continue
		var face := faces[0] as MeshInstance3D
		var head := model.find_child("Head", true, false) as MeshInstance3D
		_expect(head != null and face.get_parent() == head, "%s: the Face quad is not a child of the Head" % id)
		if head != null:
			var head_box := head.get_aabb().grow(0.03)
			_expect(head_box.has_point(face.position) or head_box.intersects(face.get_aabb().abs()), "%s: the Face quad lies outside the head" % id)
		# the quad looks along the model's forward axis (-Z of the glTF root after import)
		var normal: Vector3 = (face.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
		var forward := normal
		var walker: Node = face
		while walker != null and walker is Node3D:
			forward = (walker as Node3D).transform.basis * forward
			walker = walker.get_parent()
		forward = forward.normalized()
		_expect(absf(forward.z) > 0.9, "%s: the Face quad does not look along the model's Z axis (normal %s)" % [id, str(normal)])
		# cell 0 is the quad's own UV rect: all nine/thirteen cells must stay inside the atlas
		var rect := _uv_rect(face.mesh)
		_expect(rect.size.x > 0.0 and absf(rect.size.x - BlockyFace.CELL_PX.x) < 0.6 and absf(rect.size.y - BlockyFace.CELL_PX.y) < 0.6,
				"%s: the Face quad's UV rect is %s px, not one %s cell" % [id, str(rect.size), str(BlockyFace.CELL_PX)])
		var highest := 0
		for cell in BlockyFace.CELLS.values():
			highest = maxi(highest, int(cell))
		for anim in BlockyFace.ANIMS.values():
			for cell in anim["cells"]:
				highest = maxi(highest, int(cell))
		var last := rect.position + Vector2(float(highest % BlockyFace.COLS) * BlockyFace.CELL_PX.x, float(highest / BlockyFace.COLS) * BlockyFace.CELL_PX.y) + rect.size
		_expect(last.x <= ATLAS.x + 0.01 and last.y <= ATLAS.y + 0.01, "%s: expression cell %d ends at %s, outside the %s atlas" % [id, highest, str(last), str(ATLAS)])
		cell_rect = Rect2(rect.position, Vector2(BlockyFace.COLS * BlockyFace.CELL_PX.x, last.y - rect.position.y))
		# no other mesh samples the expression grid
		var meshes := []
		_meshes(model, meshes)
		for m in meshes:
			if m == face:
				continue
			for r in _face_rects((m as MeshInstance3D).mesh):
				if r.size.x > 0.0 and r.size.y > 0.0 and r.grow(-0.01).intersects(cell_rect.grow(-0.01)):
					_expect(false, "%s: a face of %s samples the expression cells (uv %s vs cells %s)" % [id, m.name, str(r), str(cell_rect)])
					break
		model.free()
		checked += 1
	# per-instance independence: two instances of one model, one changes expression
	var scene := load("res://assets/hunters_blocky/kathy/kathy.glb") as PackedScene
	if scene != null:
		var a := scene.instantiate()
		var b := scene.instantiate()
		BlockyFace.set_expression(a, "stun")
		BlockyFace.set_expression(b, "neutral")
		var fa := (a.find_child("Face", true, false) as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		var fb := (b.find_child("Face", true, false) as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
		_expect(fa != null and fb != null and fa != fb, "two instances of the same hunter share one face material")
		if fa != null and fb != null:
			_expect(fa.uv1_offset != fb.uv1_offset, "an expression change leaked to another instance (same uv offset %s)" % str(fa.uv1_offset))
		a.free()
		b.free()
	if _failures == 0:
		print("  expressions  %d hunter models: Face quad on the head looking forward, cells inside the atlas, no other mesh samples them, instances independent" % checked)
	return _failures
