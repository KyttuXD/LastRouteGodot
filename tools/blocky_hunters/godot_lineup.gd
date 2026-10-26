extends SceneTree

## Windowed lineup screenshot of the cube hunters (idle, walk and a few expressions), one run, all models.
##   godot4 --path . --script tools/blocky_hunters/godot_lineup.gd -- OUT_PNG [tall]
## Hunters stand in a row facing the camera; the second row plays "walk".

func _initialize() -> void:
	var out := "/tmp/blocky_lineup.png"
	var suffix := ""
	for a in OS.get_cmdline_user_args():
		if a == "tall":
			suffix = "_tall"
		else:
			out = a
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.16, .16, .24)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.45, .45, .5)
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, 25, 0)
	sun.light_energy = .8
	root.add_child(sun)
	var names := ["xivvy", "aki", "kathy"]
	for i in names.size():
		for row in 2:
			var path := "res://assets/hunters_blocky/%s%s/%s%s.glb" % [names[i], suffix, names[i], suffix]
			var model := ModelSlot.instantiate(path)
			if model == null:
				continue
			model.position = Vector3((i - 1) * 1.3, 0, -row * 1.8)
			model.rotation.y = PI          # models face -Z; turn them toward the camera
			root.add_child(model)
			var player := ModelSlot.find_animation_player(model)
			if player != null:
				player.play("idle" if row == 0 else "walk")
				player.advance(0.12 if row == 1 else 0.5)
			if row == 0:
				BlockyFace.set_expression(model, ["neutral", "happy", "chase"][i])
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, 4.6)
	cam.rotation_degrees = Vector3(-6, 0, 0)
	cam.fov = 38
	root.add_child(cam)
	cam.current = true
	await process_frame
	await process_frame
	await process_frame
	get_root().get_texture().get_image().save_png(out)
	print("saved ", out)
	quit()
