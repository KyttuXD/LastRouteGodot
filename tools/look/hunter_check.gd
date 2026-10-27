extends Node

## The hunters as the game presents them (HunterView3D from a HunterBrain): a row of ids, lit like a
## corridor, camera in front. HUNTERS=kathy,aki,... HUNTER_STATE=idle|walk|chase|search|stun|scream.
##   godot --path . res://tools/look/hunter_check.tscn -- OUT.png

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/hunters.png"
	var ids := (OS.get_environment("HUNTERS") if OS.get_environment("HUNTERS") != "" else "kathy,aki,xivvy,loxelle,void_red,void_white").split(",")
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.05, .04, .06)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.55, .5, .55)
	env.environment.ambient_light_energy = .7
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	sun.light_energy = .8
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := BoxMesh.new()
	plane.size = Vector3(40, .1, 8)
	floor_mesh.mesh = plane
	floor_mesh.position = Vector3(ids.size(), -.05, 0)
	world.add_child(floor_mesh)
	# HunterView3D is a CharacterBody3D with gravity: without a collider the hunters fall through this floor
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = plane.size
	floor_shape.shape = floor_box
	floor_body.collision_layer = 1
	floor_body.add_child(floor_shape)
	floor_mesh.add_child(floor_body)
	var x := 0.0
	var state := OS.get_environment("HUNTER_STATE")
	for id in ids:
		var at := Vector2(x, 0)
		var brain := HunterBrain.new(at, "HUNTER-CHECK", id, "standard")
		brain.activate_at(at)
		if state == "chase":
			brain.state = HunterBrain.State.CHASE
		elif state == "walk":
			brain.state = HunterBrain.State.WANDER
		elif state == "search":
			brain.state = HunterBrain.State.SEARCH
		elif state == "stun":
			brain.apply_stun(30.0)
		elif state == "scream":
			brain.state = HunterBrain.State.CHASE
		var view := HunterView3D.new()
		view.brain = brain
		world.add_child(view)
		if state == "scream":
			view.set_look_target(at + Vector2(0, 1.5))
		view.sync_from_brain()
		print("HUNTER %s scythe=%s clip=%s" % [id, view._carries_scythe, view._animation_player.current_animation if view._animation_player else "-"])
		if OS.get_environment("HEAD_DEBUG") != "":
			var head := view.find_child("Head", true, false)
			var le := view.find_child("L-Eye-Attachment", true, false) as Node3D
			var re := view.find_child("R-Eye-Attachment", true, false) as Node3D
			print("HEAD %s class=%s aabb=%s L=%s R=%s" % [id, head.get_class(), (head as MeshInstance3D).get_aabb() if head is MeshInstance3D else "-", le.position, re.position])
		x += 2.2
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 38.0
	cam.position = Vector3(x * .5 - 1.0, 1.5, 7.5)
	cam.look_at(Vector3(x * .5 - 1.0, 1.0, 0))
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
