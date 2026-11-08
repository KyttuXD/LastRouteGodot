extends Node

## The merry-go-round running, from where a player stands to the side and from above the lever.
##   godot --path . res://dev/look/carousel_capture.tscn -- OUT_DIR
func _shot(path: String, frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.02, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.55, 0.5, 0.6)
	env.environment.ambient_light_energy = 0.9
	world.add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(14, 14)
	floor_mesh.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.2, 0.18)
	floor_mesh.material_override = mat
	world.add_child(floor_mesh)
	var state := {"on": true, "angle": 0.6}
	var ride := CarouselRide3D.new()
	ride.manual = true
	ride.state_resolver = func() -> Dictionary: return state
	ride.setup("capture")
	world.add_child(ride)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.position = Vector3(0.0, 1.6, 7.0)
	cam.look_at(Vector3(0, 1.4, 0))
	for i in 20:
		state["angle"] = 0.6 + float(i) * 0.05
		ride._t += 0.1
		ride._refresh()
		await get_tree().process_frame
	await _shot(out + "/carousel_side.png")
	cam.position = Vector3(3.2, 1.7, 3.0)
	cam.look_at(Vector3(0, 1.3, 0))
	await _shot(out + "/carousel_near.png")
	get_tree().quit()
