extends SceneTree
## Top-down occupancy (vertices rasterised to 0.12 m cells) of a prop's first variant: godot -s tools/look/dump_occupancy.gd with TYPES=a,b
func _verts(n: Node, t: Transform3D, out: Array) -> void:
	var here := t
	if n is Node3D: here = t * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mesh: Mesh = (n as MeshInstance3D).mesh
		for s in mesh.get_surface_count():
			var arr := mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var idx = arr[Mesh.ARRAY_INDEX]
			var tris: Array = []
			if idx != null and idx.size() > 0:
				for i in range(0, idx.size() - 2, 3): tris.append([v[idx[i]], v[idx[i+1]], v[idx[i+2]]])
			else:
				for i in range(0, v.size() - 2, 3): tris.append([v[i], v[i+1], v[i+2]])
			for tri in tris:
				for p in [tri[0], tri[1], tri[2], (tri[0]+tri[1]+tri[2])/3.0, (tri[0]+tri[1])/2.0, (tri[1]+tri[2])/2.0, (tri[0]+tri[2])/2.0]:
					out.append(here * p)
	for c in n.get_children(): _verts(c, here, out)
func _init() -> void:
	for type in OS.get_environment("TYPES").split(","):
		var v := ModelSlot.instantiate_prop(String(ColliderAudit.variant_paths(type)[0]), type)
		var pts: Array = []
		_verts(v, Transform3D.IDENTITY, pts)
		var b := ModelSlot.combined_local_bounds(v)
		var step := 0.12
		var cols := int(ceil(b.size.x / step)); var rows := int(ceil(b.size.z / step))
		var grid := {}
		for p in pts:
			if p.y < 0.05: continue
			grid[Vector2i(int((p.x - b.position.x) / step), int((p.z - b.position.z) / step))] = true
		print(type, " origin x=%.2f z=%.2f cell %.2f (rows = z, cols = x)" % [b.position.x, b.position.z, step])
		for r in rows:
			var line := ""
			for c in cols: line += "#" if grid.has(Vector2i(c, r)) else "."
			print(line)
	quit()
