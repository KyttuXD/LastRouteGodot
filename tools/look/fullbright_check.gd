extends Node

## Rendered check of FULLBRIGHT (needs a real renderer: run on the Mac mini with --scene). A dark room (a lit-nothing box in a
## black environment) renders near black; fullbright renders its surfaces bright; off renders identical to before.
##   godot --path . res://tools/look/fullbright_check.tscn -- [OUTDIR]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else ""
	var holder := Node3D.new()   # the window's own viewport renders it (a SubViewport rendered 3D black here)
	add_child(holder)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color.BLACK
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.BLACK
	holder.add_child(env)
	var box := MeshInstance3D.new()
	box.mesh = BoxMesh.new()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.75, 0.7)
	box.material_override = material
	holder.add_child(box)
	var camera := Camera3D.new()
	camera.position = Vector3(1.6, 1.2, 2.2)
	holder.add_child(camera)
	camera.current = true
	camera.look_at(Vector3.ZERO)
	DebugView.tool_override = true
	var dark := await _brightness(holder, out, "dark")
	DebugView.set_mode(DebugView.Mode.FULLBRIGHT, get_viewport())
	var bright := await _brightness(holder, out, "fullbright")
	DebugView.set_mode(DebugView.Mode.OFF, get_viewport())
	var again := await _brightness(holder, out, "off")
	var ok := dark < 0.05 and bright > 0.25 and absf(again - dark) < 0.005
	print("fullbright_check: dark %.3f fullbright %.3f off %.3f -> %s" % [dark, bright, again, "OK" if ok else "FAIL"])
	get_tree().quit(0 if ok else 1)


func _brightness(_holder: Node, out: String, label: String) -> float:
	for _i in 4:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if not out.is_empty():
		DirAccess.make_dir_recursive_absolute(out)
		image.save_png("%s/fullbright_%s.png" % [out, label])
	var total := 0.0
	var size := image.get_size()
	var centre := Rect2i(size.x * 3 / 8, size.y / 3, size.x / 4, size.y / 3)
	for y in range(centre.position.y, centre.end.y):
		for x in range(centre.position.x, centre.end.x):
			total += image.get_pixel(x, y).get_luminance()
	return total / float(centre.size.x * centre.size.y)
