extends Node3D

## Before/after size panels for the hunter-scale rescale (docs/PROP_SIZES.md): for each prop, the authored (person-sized)
## model on the left, the rescaled one on the right, a 1.60 m runner mannequin and a 2.67 m hunter between them for
## scale, on a 1 m grid floor. One PNG per prop; tools/props/prop_size_sheet.py tiles them. Windowed: run on the mini.
##   mini-run.sh <dir> props-lane --scene res://tools/look/prop_size_sheet.tscn -- /tmp/size_sheet type1,type2,...

const DEFAULT_TYPES := ["diningTable", "bedroomWardrobe", "normalKitchenFridge", "officeDesk", "vendingMachine",
	"arcadeCabinet", "houseToilet", "houseBathtub", "bathroomSink", "singleBedMansion", "diningChairMansion", "bedroomNightstand"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/size_sheet"
	var types: Array = Array(args[1].split(",")) if args.size() > 1 else DEFAULT_TYPES
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 640)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.16, .16, .18)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.75, .75, .8)
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 30, 0)
	add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 6)
	floor_mesh.mesh = plane
	var grid_mat := StandardMaterial3D.new()
	grid_mat.albedo_color = Color(.3, .3, .32)
	floor_mesh.material_override = grid_mat
	add_child(floor_mesh)
	for x in range(-6, 7):
		var line := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(.02, .01, 6)
		line.mesh = box
		line.position = Vector3(x, .005, 0)
		add_child(line)
	var runner := ModelSlot.instantiate(PlayerModels.SCENE)
	add_child(runner)
	runner.scale = Vector3.ONE * PlayerModels.SCALE
	runner.position = Vector3(-.5, 0, .8)
	runner.rotation.y = PI    # facing the camera
	var hunter := ModelSlot.instantiate_hunter(HunterRoster.get_identity("kathy"))
	add_child(hunter)
	hunter.scale = Vector3.ONE * HunterRoster.scale_for("kathy")
	hunter.position = Vector3(.5, 0, .8)
	hunter.rotation.y = PI
	var camera := Camera3D.new()
	camera.position = Vector3(0, 2.2, 8.6)
	camera.look_at(Vector3(0, 1.3, 0), Vector3.UP)
	camera.fov = 50
	add_child(camera)
	camera.current = true
	var label := Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 18)
	var canvas := CanvasLayer.new()
	canvas.add_child(label)
	add_child(canvas)
	for type_value in types:
		var type := String(type_value)
		var path := PropModelCatalog.model_path(type, type)
		var before := ModelSlot.instantiate_prop(path, "")      # no hint: the authored size
		var after := ModelSlot.instantiate_prop(path, type)     # the hunter-scale size
		if before == null or after == null:
			continue
		for pair in [[before, -3.2], [after, 3.2]]:
			var node: Node3D = pair[0]
			add_child(node)
			var bounds := ModelSlot.combined_local_bounds(node)
			node.position = Vector3(float(pair[1]), -bounds.position.y, 0)
			node.rotation.y = PI
		var b := ModelSlot.combined_local_bounds(before).size
		var a := ModelSlot.combined_local_bounds(after).size
		label.text = "%s: before %.2f m tall (left), after %.2f m (x%.2f, right). Runner 1.60 m, hunter 2.67 m" % [type, b.y, a.y, PropModelCatalog.hunter_scale(type)]
		for _i in 8:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		image.save_png("%s/%s.png" % [out, type])
		before.queue_free()
		after.queue_free()
		await get_tree().process_frame
	print("SIZESHEET done")
	get_tree().quit()
