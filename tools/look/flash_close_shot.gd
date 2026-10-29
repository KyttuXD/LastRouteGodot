extends Node

## Hunters lit by the player's flashlight at close range (the same SpotLight3D settings as scenes/main_3d.tscn: shadows on,
## bias 0.3 / normal bias 1.0, reverse-cull shadow faces), for hunting inside-out stripes and shadow acne on the body layers.
##   godot --path . res://tools/look/flash_close_shot.tscn -- OUT_PREFIX DISTANCE HUNTER_ID[,HUNTER_ID...] [ENERGY [REVERSE_CULL(0/1) [BIAS [NORMAL_BIAS]]]]
## Writes OUT_PREFIX_<id>_front.png and _side.png. Quits when done and after 60 s.

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("flash_close_shot timed out")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- OUT_PREFIX DISTANCE HUNTER_ID[,..] [ENERGY]")
		get_tree().quit(1)
		return
	var distance := float(args[1])
	var viewport := SubViewport.new()
	viewport.size = Vector2i(700, 700)
	viewport.own_world_3d = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.22, 0.3)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	viewport.add_child(world_env)
	var cam := Camera3D.new()
	cam.fov = 50.0
	viewport.add_child(cam)
	cam.current = true
	var spot := SpotLight3D.new()
	spot.light_energy = float(args[3]) if args.size() > 3 else 7.5
	spot.shadow_enabled = true
	spot.shadow_bias = 0.3
	spot.shadow_normal_bias = 1.0
	spot.shadow_reverse_cull_face = args.size() <= 4 or args[4] == "1"
	if args.size() > 5:
		spot.shadow_bias = float(args[5])
	if args.size() > 6:
		spot.shadow_normal_bias = float(args[6])
	spot.spot_range = 16.0
	spot.spot_angle = 30.0
	spot.spot_angle_attenuation = 1.4
	viewport.add_child(spot)
	for id in args[2].split(","):
		var model := ModelSlot.instantiate_hunter(HunterRoster.get_identity(id))
		if model == null:
			continue
		model.scale = Vector3.ONE * HunterRoster.scale_for(id)
		viewport.add_child(model)
		var player := ModelSlot.find_animation_player(model)
		if player != null and player.has_animation("idle"):
			player.play("idle")
			player.seek(0.0, true)
			player.pause()
		for view in ["front", "side"]:
			var yaw := 0.0 if view == "front" else 90.0
			var base := Vector3(0, 1.35, 0)
			var dir := Vector3(0, 0, 1).rotated(Vector3.UP, deg_to_rad(yaw))
			cam.global_position = base + dir * distance + Vector3(0, 0.1, 0)
			cam.look_at(base)
			spot.global_position = cam.global_position + Vector3(0.08, -0.05, 0)
			spot.look_at(base)
			model.rotation.y = 0.0
			for i in 6:
				await get_tree().process_frame
			viewport.get_texture().get_image().save_png("%s_%s_%s.png" % [args[0], id, view])
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit(0)
