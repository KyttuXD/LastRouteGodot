extends Node

## Top-down captures of lane A's maps at 1280x720 (the Dead Air radio station and the Facility's complex), the floor plan drawn over the built rooms:
##   godot --path . res://tools/look/night_watch_maps_a_capture.tscn -- OUT_DIR
## writes 1280x720_map_lure.png, 1280x720_map_story.png and 1280x720_map_bedroom.png.

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	var jobs := [
		["lure", LureWorld.new(), Vector3(-8.0 + 0.0, 40.0, -40.0 + 10.0), 27.0],
		["story", StoryWorld.new(), Vector3(0.0, 40.0, -1.0), 36.0],
		["bedroom", [NightWatchOfficeRegistry.make("bedroom"), BedroomWing.new()], Vector3(7.0, 40.0, -3.5), 26.0],
	]
	for job in jobs:
		var holder := Node3D.new()
		add_child(holder)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.02, 0.02, 0.03)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = Color(0.9, 0.9, 1.0)
		e.ambient_light_energy = 1.1
		env.environment = e
		holder.add_child(env)
		var parts: Array = job[1] if job[1] is Array else [job[1]]
		for part in parts:
			holder.add_child(part)
		# no ceilings in a plan view
		await get_tree().process_frame
		for part in parts:
			for m in (part as Node).find_children("*Ceiling*", "MeshInstance3D", true, false):
				(m as Node3D).visible = false
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = job[3]
		holder.add_child(cam)
		cam.current = true
		cam.transform = Transform3D(Basis.IDENTITY, job[2]).looking_at(Vector3(job[2].x, 0.0, job[2].z), Vector3.FORWARD)
		for i in 8:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/1280x720_map_%s.png" % [out, job[0]])
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
