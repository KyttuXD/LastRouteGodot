extends SceneTree

## Headless check that the Office Mode room models import correctly, in the
## same spirit as scripts/validate_facility.gd.
##
## The rooms are authored in Blockbench and exported straight to .glb (see
## art/props-3d/office/). Three things have to survive that trip or the Godot
## side breaks quietly:
##
##   1. Node names. The simulation drives parts BY NAME -- office_room's
##      LeftDoor/RightDoor/Vent/DeskLamp, and every camera room's CameraMount
##      whose transform is the security camera's viewpoint. A renamed or
##      flattened node means the room silently stops reacting.
##   2. Nearest-neighbour texture filtering. These are pixel-art atlases at
##      12 texels/metre; linear filtering blurs every texel and bleeds
##      neighbouring materials into each other.
##   3. Scale. 1 unit = 1 metre per art/props-3d/README.md, so a room has to
##      measure what it was authored to measure.
##
## Run with:
##   godot4 --headless --script scripts/validate_office_rooms.gd

const ROOMS := {
	"office_room": ["Floor", "Ceiling", "LeftDoor", "RightDoor", "Vent", "Desk", "Monitor", "DeskLamp"],
	"hall": ["Floor", "Walls", "CameraMount"],
	"storage": ["Floor", "Walls", "CameraMount"],
	"archive": ["Floor", "Walls", "CameraMount"],
	"vent": ["Floor", "Walls", "CameraMount"],
	"electrical": ["Floor", "Walls", "CameraMount"],
	"loading": ["Floor", "Walls", "CameraMount"],
	# OfficeConfig names these three layouts too; they had no standalone feed
	# model, so cam5/6/9/10/11 had nothing to draw.
	"passage": ["Floor", "Walls", "CameraMount"],
	"arcade": ["Floor", "Walls", "CameraMount"],
	"dining": ["Floor", "Walls", "CameraMount"],
}

## Authored size in metres (width, depth, height), for the scale check.
## office_room's depth: 7.0 (grown from 5 once already -- pinning the player
## behind the desk with too little room to move) + 0.35 (build_office_room.py's
## FRONT_EXTRA, pushing the front wall back a second time for the same reason,
## capped by the Electrical room sitting close behind it in the merged map).
const SIZES := {
	"office_room": Vector3(6.0, 7.35, 3.0),
	"hall": Vector3(3.0, 12.0, 3.0),
	"storage": Vector3(7.0, 6.0, 3.2),
	"archive": Vector3(6.0, 5.0, 3.0),
	"vent": Vector3(1.3, 9.0, 1.3),
	"electrical": Vector3(5.0, 4.0, 3.0),
	"loading": Vector3(9.0, 7.0, 4.5),
	"passage": Vector3(2.2, 9.0, 2.6),
	"arcade": Vector3(8.0, 6.0, 3.2),
	"dining": Vector3(9.0, 7.0, 3.2),
}


func _init() -> void:
	var failures := 0
	for room_name in ROOMS:
		failures += _check(room_name)
	if failures > 0:
		push_error("%d office room check(s) failed" % failures)
		quit(1)
	else:
		print("\nall %d rooms OK" % ROOMS.size())
		quit(0)


func _check(room_name: String) -> int:
	var path := "res://art/props-3d/office/%s.glb" % room_name
	var packed := load(path)
	if packed == null:
		printerr("%s: FAILED to load %s" % [room_name, path])
		return 1

	var root: Node3D = packed.instantiate()
	var failures := 0
	var found := {}
	_collect(root, found)

	# 1. required nodes present
	var missing: Array = []
	for wanted in ROOMS[room_name]:
		if not found.has(wanted):
			missing.append(wanted)
	if not missing.is_empty():
		printerr("%s: missing nodes %s" % [room_name, missing])
		failures += 1

	# 2. nearest filtering on every material
	var blurry: Array = []
	for node_name in found:
		var node = found[node_name]
		if node is MeshInstance3D:
			var mesh: Mesh = node.mesh
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i)
				if mat is BaseMaterial3D and mat.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST:
					blurry.append("%s(filter=%d)" % [node_name, mat.texture_filter])
	if not blurry.is_empty():
		printerr("%s: not nearest-filtered: %s" % [room_name, blurry])
		failures += 1

	# 3. authored scale, 1 unit == 1 metre
	var aabb := _world_aabb(root)
	var want: Vector3 = SIZES[room_name]
	# The shell adds wall thickness outside the nominal interior, so allow a
	# little slack rather than demanding an exact match.
	var got := Vector3(aabb.size.x, aabb.size.z, aabb.size.y)
	var slack := Vector3(0.5, 0.5, 0.7)
	if absf(got.x - want.x) > slack.x or absf(got.y - want.y) > slack.y \
			or absf(got.z - want.z) > slack.z:
		printerr("%s: size %.2f x %.2f x %.2f m, expected %.2f x %.2f x %.2f m"
			% [room_name, got.x, got.y, got.z, want.x, want.y, want.z])
		failures += 1

	var mount := "-"
	if found.has("CameraMount"):
		mount = str(found["CameraMount"].position)
	print("%-12s %2d nodes  %5.2f x %5.2f x %5.2f m  cam %s  %s"
		% [room_name, found.size(), got.x, got.y, got.z, mount,
		   "OK" if failures == 0 else "FAIL"])

	root.free()
	return failures


func _collect(node: Node, out: Dictionary) -> void:
	# First one wins. Godot names the node it generates from a "-colonly"
	# child after that node MINUS the suffix, so it shares its parent's name.
	# Overwriting would return that child -- sitting at local origin -- rather
	# than the mount whose transform is the whole point.
	if not out.has(node.name):
		out[node.name] = node
	for child in node.get_children():
		_collect(child, out)


## Accumulates the transform chain by hand rather than reading
## global_transform: a SceneTree script's _init() runs before the scene root
## exists, so nothing here is ever inside the tree.
func _world_aabb(node: Node, xform := Transform3D(), box := AABB(),
		has_any := [false]) -> AABB:
	var here := xform
	if node is Node3D:
		here = xform * node.transform
	if node is MeshInstance3D and node.mesh != null:
		var a: AABB = here * node.get_aabb()
		box = a if not has_any[0] else box.merge(a)
		has_any[0] = true
	for child in node.get_children():
		box = _world_aabb(child, here, box, has_any)
	return box
