extends Node

## Does a hunter's FACE point where the brain says it is heading?  brain.facing (x, z) -> expected world direction (x, 0, z).
## Prints, per hunter and state, dot(face normal, heading): 1 = face first, -1 = runs back-first.
##   godot --path . res://tools/look/facing_check.tscn -- id1,id2   (windowed or --headless)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var ids: PackedStringArray = args[0].split(",") if args.size() > 0 and args[0] != "" else PackedStringArray(["kathy", "aki", "verrine", "eirys", "xivvy", "void_red"])
	var world := Node3D.new()
	add_child(world)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(80, .2, 80)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -.1
	floor_body.collision_layer = 1
	world.add_child(floor_body)
	var bad := 0
	for id in ids:
		for state in ["wander", "chase"]:
			var brain := HunterBrain.new(Vector2.ZERO, "FACING-CHECK", id, "standard")
			brain.activate_at(Vector2.ZERO)
			brain.state = HunterBrain.State.CHASE if state == "chase" else HunterBrain.State.WANDER
			brain.facing = Vector2(0, 1)   # heading +Z in the world
			var view := HunterView3D.new()
			view.brain = brain
			world.add_child(view)
			view.sync_from_brain()
			for i in 90:
				brain.facing = Vector2(0, 1)
				view.sync_from_brain()
				await get_tree().process_frame
			var face := view.find_child("Face", true, false) as MeshInstance3D
			if face == null:
				print("FACING %-10s %-6s no Face quad" % [id, state])
				view.queue_free()
				continue
			var arrays := face.mesh.surface_get_arrays(0)
			var n: Vector3 = (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
			var world_n := (face.global_transform.basis * n).normalized()
			var dot := world_n.dot(Vector3(0, 0, 1))
			var verdict := "ok" if dot > 0.7 else "BACK-FIRST"
			if dot <= 0.7:
				bad += 1
			print("FACING %-10s %-6s face_normal=(%.2f,%.2f,%.2f) dot_heading=%.2f %s" % [id, state, world_n.x, world_n.y, world_n.z, dot, verdict])
			view.queue_free()
			await get_tree().process_frame
	print("FACING SUMMARY back-first: %d" % bad)
	get_tree().quit(1 if bad > 0 else 0)
