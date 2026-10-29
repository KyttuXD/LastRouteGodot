extends Node

## A chair, a table and a hunter-sized cube stack at 3 m and 10 m with a high mesh LOD threshold (what a low-res or
## scaled 3D viewport does). Run once with generate_lods on and once off to compare.
##   godot --path . res://tools/look/lod_check.tscn -- OUT.png
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/lod.png"
	var image := Image.create(960, 540, false, Image.FORMAT_RGB8)
	var slot := 0
	for distance in [3.0, 10.0]:
		var holder := SubViewport.new()
		holder.size = Vector2i(480, 270)
		holder.mesh_lod_threshold = 8.0
		holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(holder)
		var world := Node3D.new()
		holder.add_child(world)
		var env := WorldEnvironment.new()
		env.environment = Environment.new()
		env.environment.background_mode = Environment.BG_COLOR
		env.environment.background_color = Color(.12, .1, .13)
		env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.environment.ambient_light_color = Color(.8, .78, .8)
		world.add_child(env)
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = Vector3(-40, 30, 0)
		world.add_child(sun)
		var x := -1.0
		for type in ["woodenChair", "woodenTable", "bedroomNightstand"]:
			var path := String(BlockyPropModels.MODELS[type][0])
			var node := (load(path) as PackedScene).instantiate() as Node3D
			world.add_child(node)
			node.position = Vector3(x, 0, 0)
			x += 1.2
		var cam := Camera3D.new()
		cam.fov = 40
		world.add_child(cam)
		cam.position = Vector3(0.2, 0.9, distance)
		cam.look_at(Vector3(0.2, 0.4, 0))
		for _i in 5:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var shot := holder.get_texture().get_image()
		shot.convert(Image.FORMAT_RGB8)
		image.blit_rect(shot, Rect2i(0, 0, 480, 270), Vector2i(slot * 480, 0))
		slot += 1
		holder.queue_free()
	image.save_png(out)
	get_tree().quit()
