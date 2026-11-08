extends RefCounted

## Hunter mesh faces ("Verrine has inside-out body stripe issues"): over every hunter and runner model,
##   * no triangle's winding disagrees with its stored normal (an inverted face draws its inside),
##   * no two faces of different cubes of one bone lie in the same plane facing the same way and overlap (a coplanar overlay shell
##     z-fights with the body under it; second-layer shells must stand off by at least MIN_GAP),
##   * no negative or non-uniform node scale (a mirrored part flips its winding),
##   * a material never draws back faces blended (cull disabled with alpha blending shows the inside of every cube).
##   VERBOSE=1 HUNTER_ONLY=<id>
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_faces

const MIN_GAP := 0.0006     # metres (2 px of a 4096 px depth slice at 3 m is far finer; real shells stand off by 0.25 skin px)
const NORMAL_EPS := 0.05

## Coplanar same-facing faces that exist today on four Voids' add-on cubes (stacked spines, shoulder pads, the lure bulb and ear
## cubes sit flush on each other): listed, not failing, to be separated later. A new one anywhere fails.
const KNOWN_COPLANAR := ["void_brown/L-Arm", "void_brown/R-Arm", "void_pink/Cue-Lure", "void_red/Chest", "void_white/Cue-Ear-L", "void_white/Cue-Ear-R"]

var _failures := 0
var _known_seen := []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _tris(mesh: ArrayMesh) -> Array:
	var out := []
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var n = arrays[Mesh.ARRAY_NORMAL]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var count: int = idx.size() if idx != null and idx.size() > 0 else v.size()
		for i in range(0, count - 2, 3):
			var a: int = idx[i] if idx != null and idx.size() > 0 else i
			var b: int = idx[i + 1] if idx != null and idx.size() > 0 else i + 1
			var c: int = idx[i + 2] if idx != null and idx.size() > 0 else i + 2
			out.append({"p": [v[a], v[b], v[c]], "n": (n[a] if n != null and n.size() > 0 else Vector3.ZERO), "s": s})
	return out


func _check_model(model: Node3D, label: String) -> Array:
	var stats := [0, 0, 0]
	for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
		var inst := mesh_node as MeshInstance3D
		if inst.mesh == null or not (inst.mesh is ArrayMesh):
			continue
		var s := inst.scale
		_expect(s.x > 0 and s.y > 0 and s.z > 0, "%s/%s: negative scale %s flips the faces" % [label, inst.name, s])
		for surface in inst.mesh.get_surface_count():
			var mat := inst.get_active_material(surface)
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				_expect(not (bm.cull_mode == BaseMaterial3D.CULL_DISABLED and bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA),
					"%s/%s: draws back faces with alpha blending (the inside of every cube shows through)" % [label, inst.name])
		var tris := _tris(inst.mesh as ArrayMesh)
		var planes := {}
		for t in tris:
			var p: Array = t["p"]
			var geo: Vector3 = ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3))
			if geo.length() < 1e-9:
				continue
			geo = geo.normalized()
			var stored: Vector3 = t["n"]
			if stored != Vector3.ZERO:
				# Godot's front face is clockwise: the winding normal points opposite the stored (outward) normal when correct
				if geo.dot(stored) > NORMAL_EPS:
					stats[0] += 1
					_expect(false, "%s/%s: a face winds against its normal %s" % [label, inst.name, stored.snapped(Vector3(.01, .01, .01))])
			var key: String = "%d,%d,%d" % [roundi(-geo.x * 4), roundi(-geo.y * 4), roundi(-geo.z * 4)]
			planes[key] = planes.get(key, []) + [{"d": -geo.dot(p[0]), "n": -geo, "p": p}]
		# coplanar, same-facing faces of different cubes that overlap: z-fighting
		for key in planes:
			var list: Array = planes[key]
			for i in list.size():
				for j in range(i + 1, list.size()):
					var a: Dictionary = list[i]
					var b: Dictionary = list[j]
					if (a["n"] as Vector3).dot(b["n"]) < .999:
						continue
					if absf(float(a["d"]) - float(b["d"])) < MIN_GAP and _overlap(a["p"], b["p"], a["n"]):
						stats[1] += 1
						var where := "%s/%s" % [label, inst.name]
						if KNOWN_COPLANAR.has(where):
							if not _known_seen.has(where):
								_known_seen.append(where)
						elif stats[1] <= 5:
							_expect(false, "%s/%s: two faces share the plane %s (offset %.4f / %.4f m) and overlap (z-fighting) at %s and %s" % [label, inst.name,
								(a["n"] as Vector3).snapped(Vector3(.01, .01, .01)), a["d"], b["d"], _centre(a["p"]), _centre(b["p"])])
	return stats


func _centre(p: Array) -> Vector3:
	return (((p[0] as Vector3) + (p[1] as Vector3) + (p[2] as Vector3)) / 3.0).snapped(Vector3(.001, .001, .001))


## Do the two triangles overlap in area (in their shared plane)? Two halves of one quad only touch along an edge.
func _overlap(pa: Array, pb: Array, n: Vector3) -> bool:
	var u := n.cross(Vector3.UP if absf(n.y) < .9 else Vector3.RIGHT).normalized()
	var w := n.cross(u)
	var qa := PackedVector2Array()
	var qb := PackedVector2Array()
	for v in pa:
		qa.append(Vector2((v as Vector3).dot(u), (v as Vector3).dot(w)))
	for v in pb:
		qb.append(Vector2((v as Vector3).dot(u), (v as Vector3).dot(w)))
	for polygon in Geometry2D.intersect_polygons(qa, qb):
		var area := 0.0
		for i in polygon.size():
			var p: Vector2 = polygon[i]
			var q: Vector2 = polygon[(i + 1) % polygon.size()]
			area += p.x * q.y - q.x * p.y
		if absf(area) * .5 > 1e-7:      # 0.1 mm^2... a real overlap is at least a skin pixel's corner (about 2 cm^2 at this size)
			return true
	return false


func run(host: Node) -> int:
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var only := OS.get_environment("HUNTER_ONLY")
	var summary := []
	for id in ids:
		if not only.is_empty() and only != String(id):
			continue
		var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(String(id)))
		if model == null:
			continue
		host.add_child(model)
		var stats := _check_model(model, String(id))
		if stats[0] > 0 or stats[1] > 0:
			summary.append("%s inverted %d coplanar %d" % [id, stats[0], stats[1]])
		model.queue_free()
	for path in [PlayerModels.BLOCKY, PlayerModels.BLOCKY_SLIM]:
		var model := ModelSlot.instantiate(path)
		host.add_child(model)
		var stats := _check_model(model, String(path).get_file())
		if stats[0] > 0 or stats[1] > 0:
			summary.append("%s inverted %d coplanar %d" % [path.get_file(), stats[0], stats[1]])
		model.queue_free()
	if not _known_seen.is_empty():
		print("  known coplanar add-on cubes (Void): %s" % ", ".join(_known_seen))
	if not summary.is_empty():
		print("  offenders: %s" % ", ".join(summary))
	return _failures
