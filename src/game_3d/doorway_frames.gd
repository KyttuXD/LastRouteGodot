class_name DoorwayFrames
extends RefCounted

## Every door frame a hunter walks through (room doors, boarded doorways, prison cell doorways), so the hunter view can
## tell when she is in one and how big the opening is (docs/DOORWAY_CLEARANCE.md). Frames register themselves when
## they enter the tree and drop out when they leave; a frame's local z = 0 plane is the wall, x runs across the opening.
##
## Door frames are also RAISED here: since the hunters are 1.5x (2.67 m, up to 3.2 m with hair), the authored 2.375 m
## openings were lower than their heads. The visuals are stretched up toward TARGET_OPENING, never past FRAME_TOP_CAP
## (just under the lowest room ceiling); what is still tight is handled by DoorwayPose (a duck and a shoulder turn).

## Opening the raise aims for, and the highest a raised frame may reach (RefLook.ROOM_RANGE starts at 3.2 m).
const TARGET_OPENING := 2.95
const FRAME_TOP_CAP := 3.15
## Underside of the wall built over a room door (its soffit): just under the raised frames' tops, so frame and header
## overlap and nothing shows between them.
const HEADER_Y := 3.1
## Clearance the hunters keep: over the head (else they duck), and at each side (else they turn their shoulders).
const HEADROOM := .10
const SIDE_ROOM := .08
## A frame counts for a hunter this far either side of its wall plane, and this far past its posts.
const REACH := 3.1
const LATERAL_SLACK := .6
## A doorway without a lintel.
const NO_HEADER := 99.0

static var _by_cell := {}


## Vertical stretch for a frame whose opening is `opening` high and whose model top is `top` (both before the stretch).
## `cap`: the highest the frame may reach (FRAME_TOP_CAP, or a lower ceiling).
static func raise_scale(opening: float, top: float, cap: float = FRAME_TOP_CAP) -> float:
	if opening <= 0.0 or top <= 0.0:
		return 1.0
	return clampf(minf(TARGET_OPENING / opening, cap / top), 1.0, 2.0)


## `node`'s local z = 0 plane is the frame; width/height are the clear opening, depth the frame's thickness (metres).
## With `visual`, the frame only counts while that node is shown (a boarded doorway's frame goes with its boards).
static func register(node: Node3D, width: float, height: float, depth: float, visual: Node3D = null) -> void:
	if not node.is_inside_tree():
		if not node.tree_entered.is_connected(register):
			node.tree_entered.connect(register.bind(node, width, height, depth, visual), CONNECT_ONE_SHOT)
		return
	var entry := {"node": node, "width": width, "height": height, "depth": depth, "visual": visual}
	var cell := _cell(node.global_position)
	unregister(node)
	node.set_meta("doorway_cell", cell)
	(_by_cell.get_or_add(cell, []) as Array).append(entry)
	if not node.tree_exiting.is_connected(unregister):
		node.tree_exiting.connect(unregister.bind(node))


static func unregister(node: Node3D) -> void:
	if not node.has_meta("doorway_cell"):
		return
	var cell: Vector2i = node.get_meta("doorway_cell")
	var list: Array = _by_cell.get(cell, [])
	for index in range(list.size() - 1, -1, -1):
		if list[index]["node"] == node:
			list.remove_at(index)
	if list.is_empty():
		_by_cell.erase(cell)
	node.remove_meta("doorway_cell")


static func count() -> int:
	var total := 0
	for list in _by_cell.values():
		total += (list as Array).size()
	return total


## The frame nearest `at` (world) that she is passing: {"along" (signed distance to the wall plane), "lateral", "width",
## "height", "depth", "basis" (the frame's world basis)}, or {} when none is within REACH.
static func nearest(at: Vector3) -> Dictionary:
	var best := {}
	var best_along := INF
	var centre := _cell(at)
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			for entry_value in _by_cell.get(centre + Vector2i(dx, dz), []):
				var entry: Dictionary = entry_value
				var node: Node3D = entry["node"]
				if not is_instance_valid(node) or not node.is_inside_tree():
					continue
				var visual = entry["visual"]
				if visual != null and (not is_instance_valid(visual) or not (visual as Node3D).is_visible_in_tree()):
					continue
				var frame := node.global_transform.orthonormalized()
				var local := frame.affine_inverse() * at
				if absf(local.y) > 1.5 or absf(local.z) > REACH \
						or absf(local.x) > float(entry["width"]) * .5 + LATERAL_SLACK:
					continue
				if absf(local.z) < best_along:
					best_along = absf(local.z)
					best = {"along": local.z, "lateral": local.x, "width": entry["width"],
						"height": entry["height"], "depth": entry["depth"], "basis": frame.basis}
	return best


## The clear opening (width, height) of a frame model, in `root`'s space: the posts' inner faces at mid height and the
## underside of the header over the middle (INF where there is none). One-piece frames are read from their vertices,
## frames built of boxes (corner vertices only) from each piece's bounds. `names`: mesh name prefixes.
static func opening(root: Node3D, names: Array) -> Vector2:
	var half := INF
	var header := INF
	for mesh_value in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_value as MeshInstance3D
		var wanted := false
		for prefix in names:
			wanted = wanted or String(mesh.name).begins_with(String(prefix))
		if not wanted or not mesh.visible or mesh.mesh == null:
			continue
		var xf := Transform3D.IDENTITY
		var walk: Node3D = mesh
		while walk != null and walk != root:
			xf = walk.transform * xf
			walk = walk.get_parent_node_3d()
		var box := xf * mesh.get_aabb()
		if box.position.y < .4 and box.end.y > 1.9:
			if box.position.x > 0.0:
				half = minf(half, box.position.x)
			elif box.end.x < 0.0:
				half = minf(half, -box.end.x)
		if box.position.x < 0.0 and box.end.x > 0.0 and box.position.y > 1.2:
			header = minf(header, box.position.y)
		for surface in mesh.mesh.get_surface_count():
			for vertex in (mesh.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX] as PackedVector3Array):
				var at := xf * vertex
				if at.y > .4 and at.y < 1.9 and absf(at.x) > .2:
					half = minf(half, absf(at.x))
				if absf(at.x) < .3 and at.y > 1.2:
					header = minf(header, at.y)
	return Vector2(half * 2.0, header)


static func _cell(at: Vector3) -> Vector2i:
	return Vector2i(floori(at.x), floori(at.z))
