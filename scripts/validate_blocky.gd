extends RefCounted

## Headless check for the cube ("blocky") hunter models in assets/hunters_blocky/.
##
## Every model must load, share the hunter rig (same bone names), carry the clips the
## game asks for, expose a "Head" node and eye locators (HunterView3D), stand on y = 0
## at about 1.78 m, and have an expression quad that BlockyFace can swap.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- blocky

const HUNTERS := ["kathy", "aki", "xivvy", "kathy_tall", "aki_tall", "xivvy_tall"]
const BONES := ["Pelvis", "Belly", "Chest", "Head", "L-Arm", "L-Forearm", "L-Hand", "R-Arm", "R-Forearm",
	"R-Hand", "L-Thigh", "L-Calf", "L-Foot", "R-Thigh", "R-Calf", "R-Foot"]
const CLIPS := ["idle", "walk", "chase", "sprint", "crouch", "stun", "charge", "flight", "jumpscare"]

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	for id in HUNTERS:
		var path := "res://assets/hunters_blocky/%s/%s.glb" % [id, id]
		if not ResourceLoader.exists(path):
			_fail("%s: %s is not imported" % [id, path])
			continue
		var node := ModelSlot.instantiate(path)
		if node == null:
			_fail("%s did not instantiate" % id)
			continue
		host.add_child(node)
		for bone in BONES:
			if node.find_child(bone, true, false) == null:
				_fail("%s is missing bone %s" % [id, bone])
		if id.begins_with("xivvy"):
			for wing in ["L-Wing", "R-Wing", "L-HindWing", "R-HindWing"]:
				if node.find_child(wing, true, false) == null:
					_fail("%s is missing wing bone %s" % [id, wing])
		var player := ModelSlot.find_animation_player(node)
		if player == null:
			_fail("%s has no AnimationPlayer" % id)
		else:
			for clip in CLIPS:
				if not player.has_animation(clip):
					_fail("%s is missing clip %s" % [id, clip])
				elif player.get_animation(clip).loop_mode == Animation.LOOP_NONE:
					_fail("%s clip %s does not loop" % [id, clip])
		if node.find_child("Head", true, false) == null:
			_fail("%s has no Head node" % id)
		for eye in ["L-Eye-Attachment", "R-Eye-Attachment"]:
			if node.find_child(eye, true, false) == null:
				_fail("%s has no %s" % [id, eye])
		var bounds := _bounds(node)
		if absf(bounds.position.y) > .03:
			_fail("%s feet are not on the floor (min y %.3f)" % [id, bounds.position.y])
		if absf(bounds.size.y - 1.78) > .08:
			_fail("%s is %.2f m tall, wanted 1.78" % [id, bounds.size.y])
		if not BlockyFace.set_expression(node, "blink"):
			_fail("%s has no swappable Face quad" % id)
		for anim in ["derp", "wink_left", "wink_right", "blank", "stun"]:
			if not BlockyFace.set_expression(node, anim):
				_fail("%s cannot show the %s expression" % [id, anim])
		# second skin layer (hat, jacket, sleeves, pants) must be present, not just the base boxes
		var head_mesh := node.find_child("Head", true, false) as MeshInstance3D
		if head_mesh == null or head_mesh.mesh == null \
				or (head_mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() < 48:
			_fail("%s has no hat layer on the Head mesh" % id)
		var vertices := 0
		for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh_node as MeshInstance3D
			vertices += (mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if vertices < 280 * 2:
			_fail("%s has only %d vertices, the overlay layers are missing" % [id, vertices])
		node.queue_free()
	print("  %d blocky hunters checked" % HUNTERS.size())
	return _failures


func _bounds(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
		var m := mesh_node as MeshInstance3D
		var local := node.global_transform.affine_inverse() * m.global_transform
		var b := local * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
