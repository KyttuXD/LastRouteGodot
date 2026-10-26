extends Node

## Mannequin lineup: the wooden mannequin in its T-pose and idle, beside a hunter
## sprite for scale, front and three-quarter views.
##   godot --path . res://tools/look/mannequin_capture.tscn -- OUTDIR

func _ready() -> void:
	var out_dir := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.55, .55, .58)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.8, .8, .82)
	env.environment.ambient_light_energy = .6
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	world.add_child(sun)
	var tpose: Node3D = load(PlayerModels.WOODEN).instantiate()
	world.add_child(tpose)
	tpose.position = Vector3(-.9, 0, 0)
	var idle: Node3D = load(PlayerModels.WOODEN).instantiate()
	world.add_child(idle)
	idle.position = Vector3(.2, 0, 0)
	var legacy: Node3D = load(PlayerModels.LEGACY).instantiate()
	world.add_child(legacy)
	legacy.position = Vector3(1.0, 0, 0)
	var hunter: Node3D = ModelSlot.instantiate_hunter(HunterRoster.get_identity("aki"))
	world.add_child(hunter)
	hunter.position = Vector3(1.8, 0, 0)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	await get_tree().process_frame
	ModelSlot.play_if_available(ModelSlot.find_animation_player(tpose), "tpose")
	ModelSlot.play_if_available(ModelSlot.find_animation_player(idle), "walk")
	for view in [["front", Vector3(.45, 1.0, -4.6), Vector3(.45, .9, 0)], ["three_quarter", Vector3(3.0, 1.6, -3.6), Vector3(.45, .85, 0)]]:
		cam.position = view[1]
		cam.look_at(view[2])
		for i in 12:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s/mannequin_%s.png" % [out_dir, view[0]])
	get_tree().quit()
