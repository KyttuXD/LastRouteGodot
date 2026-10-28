extends Node

## One hunter model in one clip at one moment, from the side and behind: for before/after captures of swaying parts.
##   godot --path . res://tools/look/clip_pose_shot.tscn -- OUT.png HUNTER CLIP FRACTION [YAW_DEGREES]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0]
	var id := args[1]
	var clip := args[2]
	var fraction := float(args[3])
	var yaw := float(args[4]) if args.size() > 4 else 35.0
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.09, 0.07, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.56, 0.62)
	env.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	viewport.add_child(sun)
	var model := ModelSlot.instantiate("res://assets/hunters_blocky/%s/%s.glb" % [id, id])
	viewport.add_child(model)
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	await get_tree().process_frame
	var name := clip if player.has_animation(clip) else clip + "-loop"
	player.play(name)
	player.seek(player.get_animation(name).length * fraction, true)
	var cam := Camera3D.new()
	cam.fov = 32.0
	viewport.add_child(cam)
	cam.current = true
	var centre := Vector3(0, 0.95, 0)
	cam.position = centre + Vector3(0, 0.15, 3.4).rotated(Vector3.UP, deg_to_rad(180.0 - yaw))
	cam.look_at(centre)
	for i in 6:
		await get_tree().process_frame
	viewport.get_texture().get_image().save_png(out)
	get_tree().quit()
