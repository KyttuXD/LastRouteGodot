extends Node

## Camera inside a hiding locker against a bright backdrop: any gap in the panels shows as bright.
##   godot --path . res://dev/look/locker_check.tscn -- OUT.png [nosleep]

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/locker.png"
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(1.0, 0.2, 0.9)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(1, 1, 1)
	env.environment.ambient_light_energy = 1.0
	world.add_child(env)
	var locker := RouteInteractable3D.new()
	locker.kind = RouteInteractable3D.Kind.HIDING_SPOT
	world.add_child(locker)
	if OS.get_environment("NOSEAL") != "":
		await get_tree().process_frame
		var seal := locker.find_child("LockerSeal", true, false)
		if seal != null:
			seal.queue_free()
	var yaws := [0.0, 25.0, -25.0, 180.0, 60.0, -60.0]
	var index := 0
	for yaw in yaws:
		var cam := Camera3D.new()
		world.add_child(cam)
		cam.current = true
		cam.fov = 75.0
		cam.near = .05
		cam.position = Vector3(0, 1.5, -.05)
		cam.rotation_degrees = Vector3(0, 180.0 + yaw, 0)
		for i in 6:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.replace(".png", "_%d.png" % index))
		cam.queue_free()
		index += 1
	get_tree().quit()
