extends Node

## The player body (PlayerModels.SCENE) as other players see it: front / side / back at a chosen clip, plus the hand
## anchor axes. PLAYER_CLIP=idle|walk|sprint|crouch|sit|lay|stun..., PLAYER_T=0.3.
##   godot --path . res://tools/look/player_check.tscn -- OUT.png

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/player.png"
	var clip := OS.get_environment("PLAYER_CLIP") if OS.get_environment("PLAYER_CLIP") != "" else "idle"
	var at_time := float(OS.get_environment("PLAYER_T")) if OS.get_environment("PLAYER_T") != "" else 0.3
	var world := Node3D.new()
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	world.add_child(sun)
	var room := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40, 20, 40)
	var dark := StandardMaterial3D.new()
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dark.albedo_color = Color(.12, .1, .14)
	dark.cull_mode = BaseMaterial3D.CULL_FRONT
	box.material = dark
	room.mesh = box
	room.position = Vector3(0, 8, 0)
	world.add_child(room)
	var x := 0.0
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		var body := ModelSlot.instantiate(PlayerModels.SCENE)
		world.add_child(body)
		body.position = Vector3(x, 0, 0)
		body.rotation_degrees.y = yaw
		var player := ModelSlot.find_animation_player(body)
		if player != null and player.has_animation(clip):
			player.play(clip)
			player.seek(at_time, true)
			player.pause()
		elif yaw == 0.0:
			print("MISSING clip ", clip)
		if yaw == 0.0:
			for anchor_name in ["R-Attachment", "R-HandProp", "L-Eye-Attachment"]:
				var a := body.find_child(anchor_name, true, false) as Node3D
				if a != null:
					print("ANCHOR ", anchor_name, " y=", a.global_position.y, " forward_axis(+Y)=", a.global_basis.y.snapped(Vector3(.01, .01, .01)), " -Z=", (-a.global_basis.z).snapped(Vector3(.01, .01, .01)))
		x += 1.2
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 38.0
	cam.position = Vector3(x * .5 - .6, 1.1, 6.0)
	cam.look_at(Vector3(x * .5 - .6, .9, 0))
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
