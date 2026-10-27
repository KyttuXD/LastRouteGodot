extends SceneTree

## Prints the UV rectangle (in atlas pixels, atlas 64x128) of every cube face of the named meshes of one hunter:
##   godot --headless --path . --script res://tools/look/uv_faces_dump.gd -- kathy Head L-Foot R-Foot
func _initialize() -> void:
	var a := OS.get_cmdline_user_args()
	var id := a[0]
	var names: Array = a.slice(1)
	var model := (load("res://assets/hunters_blocky/%s/%s.glb" % [id, id]) as PackedScene).instantiate()
	for n in names:
		var m := model.find_child(n, true, false) as MeshInstance3D
		if m == null:
			print("%s: not found" % n)
			continue
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var i := 0
			while i + 3 < uvs.size():
				var minv := Vector2(1e9, 1e9)
				var maxv := Vector2(-1e9, -1e9)
				for k in 4:
					minv = minv.min(uvs[i + k] * Vector2(64, 128))
					maxv = maxv.max(uvs[i + k] * Vector2(64, 128))
				print("%s s%d face%d normal=(%.0f,%.0f,%.0f) uv_px x %.1f..%.1f  y %.1f..%.1f" % [n, s, i / 4, norms[i].x, norms[i].y, norms[i].z, minv.x, maxv.x, minv.y, maxv.y])
				i += 4
	quit()
