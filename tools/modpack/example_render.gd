extends Node

## Windowed render of pack models for the example docs: Aki beside her frostbite variant, and the library's ladder.
##   godot --path . --position 10000,10000 res://tools/modpack/example_render.tscn -- <out dir>
## Needs a GPU (a window); the layout sheets (example_layout.gd) work headless.

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	# pack models load through ContentRegistry, so the packs are installed under user:// and loaded like a room would
	var dirs := []
	for pack in ["frostbite_aki", "library_rooms"]:
		var target := "user://example_render/%s" % pack
		_copy("res://examples/mods/%s" % pack, target)
		dirs.append(target)
	var report := ContentRegistry.load_packs(dirs)
	if not report["ok"]:
		printerr("packs refused: ", report["errors"])
	var base := "user://example_render"
	_shot(out.path_join("render_frostbite.png"), [["res://assets/hunters_blocky/aki/aki.glb", -.7, true],
		[base + "/frostbite_aki/assets/frostbite_aki.glb", .7, true]], 1.5, 4.2)
	for _i in 4:
		await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out.path_join("render_frostbite.png"))
	for child in get_tree().root.get_children():
		if child is Node3D:
			child.queue_free()
	await get_tree().process_frame
	_shot("", [[base + "/library_rooms/assets/rolling_ladder.glb", 0.0, false]], 1.2, 6.0)
	for _i in 4:
		await get_tree().process_frame
	get_tree().root.get_texture().get_image().save_png(out.path_join("render_ladder.png"))
	get_tree().quit()


func _shot(_path: String, models: Array, height: float, distance: float) -> void:
	var root := Node3D.new()
	get_tree().root.add_child.call_deferred(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.14, .14, .2)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.55, .55, .6)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = .9
	root.add_child(sun)
	for entry in models:
		var path := String(entry[0])
		var model := ModelSlot.instantiate(path)
		if model == null:
			printerr("could not load ", entry[0])
			continue
		model.position = Vector3(entry[1], 0, 0)
		model.rotation.y = PI if entry[2] else 0.5
		root.add_child(model)
		var player := ModelSlot.find_animation_player(model)
		if player != null and player.has_animation("idle"):
			player.play("idle")
			player.advance(0.4)
	var cam := Camera3D.new()
	cam.position = Vector3(0, height, distance)
	cam.rotation_degrees = Vector3(-4, 0, 0)
	cam.fov = 38
	root.add_child(cam)
	cam.current = true


func _copy(from: String, to: String) -> void:
	DirAccess.make_dir_recursive_absolute(to)
	for name in DirAccess.get_files_at(from):
		var file := FileAccess.open(to.path_join(name), FileAccess.WRITE)
		file.store_buffer(FileAccess.get_file_as_bytes(from.path_join(name)))
		file.close()
	for name in DirAccess.get_directories_at(from):
		_copy(from.path_join(name), to.path_join(name))
