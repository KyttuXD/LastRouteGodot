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
	env.environment.ambient_light_energy = .7 if OS.get_environment("DARK") == "" else .08
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
	if OS.get_environment("DARK") != "":
		# the window is transparent, so the environment colour does not show: a dark room box instead
		var room := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(60, 30, 60)
		var dark := StandardMaterial3D.new()
		dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dark.albedo_color = Color(.02, .015, .03)
		dark.cull_mode = BaseMaterial3D.CULL_FRONT
		box.material = dark
		room.mesh = box
		room.position = Vector3(0, 10, 0)
		world.add_child(room)
	var x := 0.0
	var views: Array = []
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
		views.append([id, view])
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
	cam.environment = env.environment   # the camera's own environment so the backdrop colour applies
	cam.fov = 38.0
	var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else 7.5
	cam.position = Vector3(x * .5 - 1.0, 1.5, dist)
	cam.look_at(Vector3(x * .5 - 1.0, 1.0, 0))
	if OS.get_environment("CAM_YAW") != "":
		# orbit the row's centre: 0 front, 90 side, 180 back (hunters walk toward +Z, so they face the camera at 0)
		var centre := Vector3(x * .5 - 1.0, 1.0, 0)
		cam.position = centre + (cam.position - centre).rotated(Vector3.UP, deg_to_rad(float(OS.get_environment("CAM_YAW"))))
		cam.position.y = 1.5
		cam.look_at(centre)
	if OS.get_environment("CAM_SIDE") != "":
		# from the side and a little behind, so a beam is seen along its length (Kathy's beam capture)
		cam.position = Vector3(x * .5 - 1.0 + 6.5, 2.2, 6.0)
		cam.fov = 55.0
		cam.look_at(Vector3(x * .5 - 1.0, 1.0, 4.0))
	if OS.get_environment("LOD") != "":
		get_viewport().mesh_lod_threshold = float(OS.get_environment("LOD"))   # pixels of error allowed: tests generated LODs
	for i in 30:
		if OS.get_environment("FORCE_FACING") != "":
			for pair in views:
				(pair[1] as HunterView3D).brain.facing = Vector2(0, 1)   # heading +Z: the face should look at the camera
		await get_tree().process_frame
	if OS.get_environment("HIDE") != "":
		for pair in views:
			for nm in OS.get_environment("HIDE").split(","):
				var hn := (pair[1] as Node).find_child(nm, true, false) as Node3D
				if hn != null:
					hn.visible = false
		for i in 3:
			await get_tree().process_frame
	if OS.get_environment("POSE_DEBUG") != "":
		if OS.get_environment("POSE_TREE") != "":
			_dump(views[0][1] as Node, 0)
		for pair in views:
			var v: HunterView3D = pair[1]
			var h := v.find_child("Head", true, false) as Node3D
			var m := v._model as Node3D
			var fq := v.find_child("Face", true, false) as MeshInstance3D
			var fdot := 9.0
			if fq != null:
				var nn: Vector3 = (fq.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0]
				fdot = (fq.global_transform.basis * nn).normalized().dot(Vector3(0, 0, 1))
			var parts := ""
			for nm in ["Pelvis", "Belly", "Chest", "Head", "L-Arm", "L-Thigh"]:
				var pn := v.find_child(nm, true, false) as Node3D
				if pn != null:
					parts += " %s_fwdZ=%.2f" % [nm, pn.global_transform.basis.z.normalized().z]
			print("PARTS %s%s" % [pair[0], parts])
			print("FACE %s face_dot_plusZ=%.2f view_yaw_deg=%.0f brain_facing=%s state=%d" % [pair[0], fdot, rad_to_deg(v.rotation.y), v.brain.facing, v.brain.state])
			print("POSE %s clip=%s view_up=%.2f model_up=%.2f head_up=%.2f head_pitch_deg=%.0f model_rot=%s" % [pair[0], v._animation_player.current_animation if v._animation_player else "-", v.global_transform.basis.y.y, m.global_transform.basis.y.y if m else 9.0, h.global_transform.basis.y.y if h else 9.0, rad_to_deg(h.global_transform.basis.get_euler().x) if h else 0.0, m.rotation_degrees if m else Vector3.ZERO])
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()


func _dump(n: Node, depth: int) -> void:
	if n is Node3D:
		var g := (n as Node3D).global_transform
		print("TREE %s%s [%s] y=%.2f up=%.2f x=%.2f z=%.2f" % ["  ".repeat(depth), n.name, n.get_class(), g.origin.y, g.basis.y.normalized().y, g.origin.x, g.origin.z])
	for c in n.get_children():
		_dump(c, depth + 1)
