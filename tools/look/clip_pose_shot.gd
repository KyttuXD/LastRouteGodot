extends Node

## Hunter models in clips at moments, from the side and behind: for before/after captures of swaying parts and hair. ONE process
## renders every shot, so nothing lingers.
##   godot --path . res://tools/look/clip_pose_shot.tscn -- OUT_PREFIX SPEC[,SPEC...]
## SPEC = hunter:clip:fraction[:yaw]   e.g.  /tmp/after porcelle:chase:0.5,aki:idle:0.25:60  ->  /tmp/after_porcelle_chase_0.5.png ...
## (one argument with commas, so a shell re-splitting the command line cannot break it). Quits on success, on any error and after 60 s.

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("clip_pose_shot timed out")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- OUT_PREFIX SPEC[,SPEC...]")
		get_tree().quit(1)
		return
	var prefix := args[0]
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
	var cam := Camera3D.new()
	cam.fov = 32.0
	viewport.add_child(cam)
	cam.current = true
	var status := 0
	for spec in args[1].split(","):
		var p := spec.split(":")
		if p.size() < 3:
			push_error("bad spec %s" % spec)
			status = 1
			continue
		var id := p[0]
		var clip := p[1]
		var fraction := float(p[2])
		var yaw := float(p[3]) if p.size() > 3 else 35.0
		var model := ModelSlot.instantiate("res://assets/hunters_blocky/%s/%s.glb" % [id, id])
		if model == null:
			push_error("no model %s" % id)
			status = 1
			continue
		viewport.add_child(model)
		var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
		await get_tree().process_frame
		var name := clip if player != null and player.has_animation(clip) else clip + "-loop"
		if player == null or not player.has_animation(name):
			push_error("no clip %s for %s" % [clip, id])
			status = 1
			model.queue_free()
			continue
		player.play(name)
		player.seek(player.get_animation(name).length * fraction, true)
		var centre := Vector3(0, 0.95, 0)
		cam.position = centre + Vector3(0, 0.15, 3.4).rotated(Vector3.UP, deg_to_rad(180.0 - yaw))
		cam.look_at(centre)
		for i in 6:
			await get_tree().process_frame
		viewport.get_texture().get_image().save_png("%s_%s_%s_%s.png" % [prefix, id, clip, p[2]])
		model.queue_free()
		await get_tree().process_frame
	get_tree().quit(status)
