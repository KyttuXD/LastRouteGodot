extends RefCounted

## Z-fighting inside the blocky prop models (the `coplanar` suite only compares different meshes in the route; a bed is one mesh made of
## boxes): every axis-aligned quad of every model in assets/props/blocky is compared with the others of the same model, and two
## same-facing quads on one plane (within 2 mm) that overlap by 5 cm2 or more fail. The builder (tools/props/build_blocky_props.py,
## resolve_coplanar) sets the earlier box's face back 6 mm behind the later one. Floor contact undersides and tilted boxes are exempt.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- prop_coplanar

const DIR := "res://assets/props/blocky"
const PLANE_TOL := 0.002
const MIN_OVERLAP := 0.0005
const KNOWN := 0
## Reported cases (gothic bedroom): these must exist and be clean by name, whatever happens to the ratchet.
const BEDROOM_SET := ["gothicWardrobe_0", "gothicDoubleBed_0", "gothicDoubleBed_1", "gothicNightstand_0", "gothicDresser_0",
	"gothicHighbackChair_0", "gothicBedsideCandelabra", "bedroomWardrobe_0", "singleBed_0", "doubleBed_0", "bunkBed_0"]

var _failures := 0
var offenders := []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## Axis-aligned triangles of a mesh (the importer reorders indices, so quads are not recovered): axis, outward side, plane, 2D points.
static func triangles_of(mesh: Mesh, to_root: Transform3D) -> Array:
	var result := []
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices = arrays[Mesh.ARRAY_INDEX]
		var order: Array = []
		if indices != null and (indices as PackedInt32Array).size() > 0:
			for index in indices:
				order.append(index)
		else:
			for k in vertices.size():
				order.append(k)
		var k := 0
		while k + 2 < order.size():
			var p0 := to_root * vertices[int(order[k])]
			var p1 := to_root * vertices[int(order[k + 1])]
			var p2 := to_root * vertices[int(order[k + 2])]
			k += 3
			for axis in 3:
				if absf(p0[axis] - p1[axis]) < 0.0005 and absf(p0[axis] - p2[axis]) < 0.0005:
					var normal := (p1 - p0).cross(p2 - p0)
					if absf(normal[axis]) < 1e-9:
						continue
					# Godot front faces are clockwise: the cross product points inward
					var side := -1 if normal[axis] > 0.0 else 1
					var flat := []
					for point in [p0, p1, p2]:
						var pair := []
						for m in 3:
							if m != axis:
								pair.append(point[m])
						flat.append(Vector2(pair[0], pair[1]))
					result.append({"axis": axis, "side": side, "plane": p0[axis], "points": flat})
	return result


static func _clip(subject: Array, a: Vector2, b: Vector2) -> Array:
	var out := []
	for index in subject.size():
		var current: Vector2 = subject[index]
		var previous: Vector2 = subject[(index + subject.size() - 1) % subject.size()]
		var in_current := (b - a).cross(current - a) >= -1e-9
		var in_previous := (b - a).cross(previous - a) >= -1e-9
		if in_current != in_previous:
			var d1 := (b - a).cross(previous - a)
			var d2 := (b - a).cross(current - a)
			out.append(previous + (current - previous) * (d1 / (d1 - d2)))
		if in_current:
			out.append(current)
	return out


static func _area(points: Array) -> float:
	var total := 0.0
	for index in points.size():
		total += (points[index] as Vector2).cross(points[(index + 1) % points.size()])
	return absf(total) * .5


static func overlap_area(first: Array, second: Array) -> float:
	var a: Array = first.duplicate()
	var b: Array = second.duplicate()
	if (a[1] - a[0] as Vector2).cross(a[2] - a[0]) < 0.0:
		a.reverse()
	if (b[1] - b[0] as Vector2).cross(b[2] - b[0]) < 0.0:
		b.reverse()
	var clipped := a
	for index in 3:
		if clipped.size() < 3:
			return 0.0
		clipped = _clip(clipped, b[index], b[(index + 1) % 3])
	return _area(clipped) if clipped.size() >= 3 else 0.0


func scan_model(path: String) -> Array:
	var packed := load(path) as PackedScene
	if packed == null:
		return []
	var root := packed.instantiate() as Node3D
	var tris := []
	var floor_y := INF
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh_node := node as MeshInstance3D
			var transform := Transform3D.IDENTITY
			var current: Node = mesh_node
			while current != null and current != root:
				if current is Node3D:
					transform = (current as Node3D).transform * transform
				current = current.get_parent()
			tris.append_array(triangles_of(mesh_node.mesh, transform))
			floor_y = minf(floor_y, (transform * mesh_node.get_aabb().position).y)
	root.free()
	var found := []
	for a in tris.size():
		var ta: Dictionary = tris[a]
		if int(ta["axis"]) == 1 and int(ta["side"]) < 0 and float(ta["plane"]) <= floor_y + 0.001:
			continue
		for b in range(a + 1, tris.size()):
			var tb: Dictionary = tris[b]
			if ta["axis"] != tb["axis"] or ta["side"] != tb["side"] \
					or absf(float(ta["plane"]) - float(tb["plane"])) > PLANE_TOL:
				continue
			var overlap := overlap_area(ta["points"], tb["points"])
			if overlap >= MIN_OVERLAP:
				found.append("axis %d side %d plane %.3f (%.3f m2)" % [ta["axis"], ta["side"], ta["plane"], overlap])
	return found


func run(_host: Node) -> int:
	var models := 0
	var dir := DirAccess.open(DIR)
	var names := []
	for file in dir.get_files():
		if file.ends_with(".glb"):
			names.append(file)
	names.sort()
	for file in names:
		var found := scan_model("%s/%s" % [DIR, file])
		models += 1
		if not found.is_empty():
			offenders.append("%s: %d (%s)" % [file, found.size(), found[0]])
	for model_name in BEDROOM_SET:
		var path := "%s/%s.glb" % [DIR, model_name]
		_expect(ResourceLoader.exists(path), "bedroom set model %s is missing" % model_name)
		if ResourceLoader.exists(path):
			var found := scan_model(path)
			_expect(found.is_empty(), "%s z-fights: %s" % [model_name, found.slice(0, 3)])
	_expect(offenders.size() <= KNOWN, "%d of %d blocky models still have coplanar same-facing faces (allowed %d), e.g. %s" % [
		offenders.size(), models, KNOWN, offenders.slice(0, 6)])
	for line in offenders:
		print("    ", line)
	if _failures == 0:
		print("  prop_coplanar  %d blocky models scanned, no overlapping coplanar faces" % models)
	return _failures
