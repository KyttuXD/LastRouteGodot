class_name CoplanarScan
extends RefCounted

## Finds z-fighting: same-facing, axis-aligned faces of DIFFERENT mesh instances that lie in the same plane (within
## `tolerance`) and overlap. Walks every MeshInstance3D and MultiMesh instance below `root`, keeps only axis-aligned
## triangles (floors, walls, ceilings, box props, doors, rugs...), buckets them by plane, and reports overlapping pairs.
## Used by scripts/validate_coplanar.gd and tools/look/coplanar_scan.gd.

const TOLERANCE := 0.002          # 2 mm: closer than this fights at any sane near plane
const MIN_OVERLAP := 0.0004       # 2 x 2 cm
const AXIS_EPSILON := 0.0005
const ADDITIVE_DECOR := ["Ref_pool", "Ref_streak", "Ref_halo", "Ref_petal"]

var tolerance := TOLERANCE
var min_overlap := MIN_OVERLAP
## Skip pairs between parts of the same prop (its own boxes overlapping): only placement against OTHER things matters.
var ignore_siblings := false
var triangles_seen := 0
var faces: Array[Dictionary] = []
var _buckets := {}


## Returns an Array of {a, b, axis, plane, overlap, at} sorted by overlap (largest first).
func scan(root: Node) -> Array[Dictionary]:
	faces.clear()
	_buckets.clear()
	triangles_seen = 0
	_collect(root)
	return _pairs()


func _collect(node: Node) -> void:
	if node.name == "LockerSeal":
		return   # a hidden two-sided box inside the locker panels, by design
	if node is MultiMeshInstance3D and String(node.name) in ADDITIVE_DECOR:
		return   # additive light pools/halos/streaks/petals draw without depth writes: they cannot z-fight
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.multimesh != null and mmi.multimesh.mesh != null and mmi.is_visible_in_tree():
			var shown := mmi.multimesh.visible_instance_count
			for i in (mmi.multimesh.instance_count if shown < 0 else mini(shown, mmi.multimesh.instance_count)):
				_add_mesh(mmi.multimesh.mesh, mmi.global_transform * mmi.multimesh.get_instance_transform(i),
					"%s#%d" % [mmi.get_path(), i], mmi)
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.is_visible_in_tree():
			_add_mesh(mi.mesh, mi.global_transform, str(mi.get_path()), mi)
	for child in node.get_children():
		_collect(child)


func _add_mesh(mesh: Mesh, transform: Transform3D, owner_id: String, node: Node) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var count: int = (indices as PackedInt32Array).size() if indices != null else vertices.size()
		var i := 0
		while i + 2 < count:
			var ia: int = indices[i] if indices != null else i
			var ib: int = indices[i + 1] if indices != null else i + 1
			var ic: int = indices[i + 2] if indices != null else i + 2
			_add_triangle(transform * vertices[ia], transform * vertices[ib], transform * vertices[ic], owner_id, node)
			i += 3


func _add_triangle(a: Vector3, b: Vector3, c: Vector3, owner_id: String, node: Node) -> void:
	triangles_seen += 1
	var normal := (b - a).cross(c - a)
	var length := normal.length()
	if length < 1e-9:
		return
	normal /= length
	var axis := -1
	for k in 3:
		if absf(normal[k]) > 1.0 - AXIS_EPSILON:
			axis = k
	if axis < 0:
		return
	if absf(a[axis] - b[axis]) > AXIS_EPSILON or absf(a[axis] - c[axis]) > AXIS_EPSILON:
		return
	# a face looking down from the floor plane (or up from a ceiling plane) is buried in the slab: never seen
	if axis == 1 and normal.y < 0.0 and absf(a.y - roundf(a.y / 4.0) * 4.0) < .004:
		return
	var u := (axis + 1) % 3
	var v := (axis + 2) % 3
	var face := {
		"axis": axis, "sign": 1 if normal[axis] > 0.0 else -1, "plane": (a[axis] + b[axis] + c[axis]) / 3.0,
		"u0": minf(a[u], minf(b[u], c[u])), "u1": maxf(a[u], maxf(b[u], c[u])),
		"v0": minf(a[v], minf(b[v], c[v])), "v1": maxf(a[v], maxf(b[v], c[v])),
		"owner": owner_id, "node": node,
	}
	faces.append(face)
	var key := Vector3i(axis, int(face["sign"]), int(round(float(face["plane"]) / tolerance)))
	if not _buckets.has(key):
		_buckets[key] = []
	(_buckets[key] as Array).append(faces.size() - 1)


func _pairs() -> Array[Dictionary]:
	var found := {}
	for key_value in _buckets:
		var key: Vector3i = key_value
		var here: Array = _buckets[key]
		var lists: Array = [here]
		var next_key := Vector3i(key.x, key.y, key.z + 1)
		if _buckets.has(next_key):
			lists.append(_buckets[next_key])
		for list_index in lists.size():
			var other: Array = lists[list_index]
			for i in here.size():
				var fa: Dictionary = faces[here[i]]
				var start := i + 1 if list_index == 0 else 0
				for j in range(start, other.size()):
					var fb: Dictionary = faces[other[j]]
					if String(fa["owner"]) == String(fb["owner"]) or absf(float(fa["plane"]) - float(fb["plane"])) > tolerance:
						continue
					# parts of one prop (same parent node) overlapping each other are modelling detail, not placement
					if ignore_siblings and (fa["node"] as Node).get_parent() == (fb["node"] as Node).get_parent() \
							and not String(fa["owner"]).contains("#"):
						continue
					var du := minf(float(fa["u1"]), float(fb["u1"])) - maxf(float(fa["u0"]), float(fb["u0"]))
					var dv := minf(float(fa["v1"]), float(fb["v1"])) - maxf(float(fa["v0"]), float(fb["v0"]))
					if du <= 0.0 or dv <= 0.0 or du * dv < min_overlap:
						continue
					var owners := [String(fa["owner"]), String(fb["owner"])]
					owners.sort()
					var pair_key := "%s|%s|%d" % [owners[0], owners[1], int(key.x)]
					var axis := int(fa["axis"])
					var at := Vector3.ZERO
					at[axis] = float(fa["plane"])
					at[(axis + 1) % 3] = (maxf(float(fa["u0"]), float(fb["u0"])) + minf(float(fa["u1"]), float(fb["u1"]))) * .5
					at[(axis + 2) % 3] = (maxf(float(fa["v0"]), float(fb["v0"])) + minf(float(fa["v1"]), float(fb["v1"]))) * .5
					if not found.has(pair_key) or float(found[pair_key]["overlap"]) < du * dv:
						found[pair_key] = {"a": owners[0], "b": owners[1], "axis": axis, "plane": float(fa["plane"]),
							"overlap": du * dv, "at": at}
	var result: Array[Dictionary] = []
	for value in found.values():
		result.append(value)
	result.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return float(x["overlap"]) > float(y["overlap"]))
	return result


## "surface" for the chunk's merged floor/wall mesh, "decor" for MultiMesh dressing, otherwise the prop node name.
static func kind_of(owner_id: String) -> String:
	var parts := owner_id.split("/")
	if owner_id.contains("#"):
		return "decor:" + parts[parts.size() - 1].split("#")[0]
	for part in parts:
		if part.begins_with("Ref") and part.contains("Surface"):
			return "surface"
	return parts[parts.size() - 1] if parts.size() > 0 else owner_id
