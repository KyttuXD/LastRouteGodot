extends Node

## A hunter and a runner side by side at their in-game sizes, for before/after captures of the runner's scale.
##   godot --path . res://tools/look/scale_pair_shot.tscn -- OUT_PREFIX RUNNER_SCALE[,RUNNER_SCALE...] HUNTER_ID[,HUNTER_ID...]
## e.g. /tmp/pair 0.9,1.236 dovelle,void_black  ->  /tmp/pair_dovelle_0.9.png, /tmp/pair_dovelle_1.236.png ...
## Front view, a metre-grid backdrop and a 2 m ruler post so the heights read. Quits when done and after 60 s.

func _ready() -> void:
	get_tree().create_timer(60.0).timeout.connect(func() -> void:
		push_error("scale_pair_shot timed out")
		get_tree().quit(1))
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		push_error("usage: -- OUT_PREFIX RUNNER_SCALE[,..] HUNTER_ID[,..]")
		get_tree().quit(1)
		return
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 640)
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
	cam.fov = 30.0
	viewport.add_child(cam)
	cam.current = true
	# a 2 m ruler post with a mark every 0.5 m
	for k in 5:
		var mark := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.5, 0.02, 0.02)
		mark.mesh = box
		mark.position = Vector3(0.0, 0.5 * k + 0.01, -1.2)
		viewport.add_child(mark)
	for scale_text in args[1].split(","):
		for id in args[2].split(","):
			var hunter := ModelSlot.instantiate_hunter(HunterRoster.get_identity(id))
			var runner := ModelSlot.instantiate(PlayerModels.SCENE)
			if hunter == null or runner == null:
				push_error("no model for %s" % id)
				continue
			hunter.scale = Vector3.ONE * HunterRoster.scale_for(id)
			runner.scale = Vector3.ONE * float(scale_text)
			hunter.position = Vector3(-1.1, 0, 0)
			runner.position = Vector3(1.1, 0, 0)
			hunter.rotation.y = 0.0
			runner.rotation.y = 0.0
			viewport.add_child(hunter)
			viewport.add_child(runner)
			for model in [hunter, runner]:
				var player := ModelSlot.find_animation_player(model)
				if player != null and player.has_animation("idle"):
					player.play("idle")
					player.seek(0.0, true)
					player.pause()
			cam.position = Vector3(0, 1.7, 11.5)
			cam.look_at(Vector3(0, 1.6, 0))
			for i in 6:
				await get_tree().process_frame
			viewport.get_texture().get_image().save_png("%s_%s_%s.png" % [args[0], id, scale_text])
			hunter.queue_free()
			runner.queue_free()
			await get_tree().process_frame
	get_tree().quit(0)
