extends Node

## A ghosted hunter (stealth fade, HunterView3D.MIN_VISIBLE_ALPHA) in front of a bright striped wall, so the fade's own
## sorting shows: inner faces / far-side faces bleeding through read as "inside out" (Verrine in the sewer).
## HUNTER=verrine CAM_DIST=2.5 FADE=0.72 CAM_Y=1.3
##   godot --path . res://dev/look/ghost_fade_shot.tscn -- OUT.png

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/ghost_fade.png"
	var id := OS.get_environment("HUNTER") if OS.get_environment("HUNTER") != "" else "verrine"
	var fade := float(OS.get_environment("FADE")) if OS.get_environment("FADE") != "" else 1.0 - HunterView3D.MIN_VISIBLE_ALPHA
	var world := Node3D.new()
	add_child(world)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(.05, .04, .06)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(.6, .55, .6)
	env.ambient_light_energy = .8
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -25, 0)
	world.add_child(sun)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, .1, 20)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -.05
	world.add_child(floor_body)
	# striped backdrop wall behind her
	for i in 12:
		var bar := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(.25, 4, .05)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(.9, .2, .2) if i % 2 == 0 else Color(.15, .6, .9)
		bm.material = m
		bar.mesh = bm
		bar.position = Vector3(-1.5 + i * .25, 2, -1.5)
		world.add_child(bar)
	var brain := HunterBrain.new(Vector2.ZERO, "GHOST-SHOT", id, "standard")
	brain.activate_at(Vector2.ZERO)
	var view := HunterView3D.new()
	view.brain = brain
	world.add_child(view)
	view.sync_from_brain()
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.environment = env
	cam.fov = 60.0
	var dist := float(OS.get_environment("CAM_DIST")) if OS.get_environment("CAM_DIST") != "" else 2.5
	var cy := float(OS.get_environment("CAM_Y")) if OS.get_environment("CAM_Y") != "" else 1.2
	var yaw := deg_to_rad(float(OS.get_environment("CAM_YAW"))) if OS.get_environment("CAM_YAW") != "" else 0.0
	cam.position = Vector3(sin(yaw) * dist, cy, cos(yaw) * dist)
	cam.look_at(Vector3(0, cy * .8, 0))
	for i in 30:
		brain.facing = Vector2(0, 1)
		await get_tree().process_frame
		ModelSlot.set_character_fade(view._model, fade)
	await get_tree().process_frame
	var faded := 0
	var total := 0
	for g in view._model.find_children("*", "GeometryInstance3D", true, false):
		total += 1
		if (g as GeometryInstance3D).transparency > .01:
			faded += 1
	print("GHOST %s fade=%.2f faded_meshes=%d/%d" % [id, fade, faded, total])
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
