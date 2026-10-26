extends Node

## Row of props, old models on the back row, blocky rebuilds in front.
##   godot --path . res://tools/look/prop_lineup.tscn -- OUTFILE.png

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/lineup.png"
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.1, .08, .1)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.8, .75, .8)
	env.environment.ambient_light_energy = .7
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment.adjustment_enabled = false
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 30, 0)
	world.add_child(sun)
	var types := ["woodenChair", "woodenTable", "singleBed", "bedroomNightstand", "loungeCouch", "officeDesk",
		"retroComputerDesktop", "filingCabinet", "arcadeCabinet", "tableLamp", "supplyCrates", "normalBookcase", "vendingMachine"]
	if OS.get_environment("LINE_TYPES") != "":
		types = Array(OS.get_environment("LINE_TYPES").split(","))
	var x := 0.0
	for type in types:
		for row in 2:
			var path := String(PropModelCatalog.MODEL_PATHS[type][0]) if row == 0 \
				else String(BlockyPropModels.MODELS.get(type, [PropModelCatalog.MODEL_PATHS[type][0]])[0])
			var node: Node3D = ModelSlot.instantiate_prop(path, type)
			world.add_child(node)
			node.position = Vector3(x, 0, -row * 2.2)
			node.rotation.y = PI
		x += 1.9 if type not in ["singleBed", "officeDesk"] else 2.9
		if OS.get_environment("LINE_TYPES") != "":
			x += float(PropModelCatalog.MODEL_PATHS.has(type)) * 0.0
	if OS.get_environment("LINE_PATHS") != "":
		# one row of arbitrary scenes/models (e.g. the interactables), 2 m apart
		for child in world.get_children():
			if child is Node3D and not (child is DirectionalLight3D) and not (child is Camera3D):
				child.queue_free()
		x = 0.0
		for path in OS.get_environment("LINE_PATHS").split(","):
			var packed := load(path) as PackedScene
			if packed == null:
				continue
			var inst := packed.instantiate() as Node3D
			world.add_child(inst)
			inst.position = Vector3(x, 0, 0)
			x += 1.4
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.fov = 30.0
	cam.position = Vector3(x * .5, 3.4, 16.0)
	cam.look_at(Vector3(x * .5, .8, -1.0))
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
