extends Node

## Every blocky model rendered in Godot (the real import, ModelSlot's materials) in a grid, one angle per PNG:
## ANGLE=front|side|back|top  IDS=a,b,c (default: all folders of assets/hunters_blocky)  LIT=1 flat bright light.
##   godot --path . res://tools/look/uv_sheet.tscn -- OUT.png

func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp/uv_sheet.png"
	var angle := OS.get_environment("ANGLE") if OS.get_environment("ANGLE") != "" else "front"
	var ids: Array = []
	if OS.get_environment("IDS") != "":
		ids = Array(OS.get_environment("IDS").split(","))
	else:
		var d := DirAccess.open("res://assets/hunters_blocky")
		for n in d.get_directories():
			ids.append(n)
		ids.sort()
	# CLIPS=1: one hunter (IDS=id), one cell per animation clip at T (0..1 of its length) instead of one per hunter
	var clip_mode := OS.get_environment("CLIPS") != ""
	var clip_t := float(OS.get_environment("T")) if OS.get_environment("T") != "" else .4
	var cells: Array = []
	if clip_mode:
		var probe := ModelSlot.instantiate("res://assets/hunters_blocky/%s/%s.glb" % [ids[0], ids[0]])
		var ap := ModelSlot.find_animation_player(probe)
		for c in ap.get_animation_list():
			if c != "RESET":
				cells.append([ids[0], c])
		probe.free()
	else:
		for id in ids:
			cells.append([id, "idle"])
	var yaw := {"front": 180.0, "side": 90.0, "back": 0.0, "top": 180.0}.get(angle, 180.0) as float
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.3, .33, .36)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 1.0
	world.add_child(env)
	var cols := 8
	var gap := 1.6
	var x := 0
	for cell in cells:
		var id: String = cell[0]
		var path := "res://assets/hunters_blocky/%s/%s.glb" % [id, id]
		var body := ModelSlot.instantiate(path)
		if body == null:
			print("MISSING ", id)
			continue
		world.add_child(body)
		body.position = Vector3((x % cols) * gap, -(x / cols) * 2.4, 0)
		# the glb faces -Z; the camera looks down -Z so rotate 180 for the front
		body.rotation_degrees.y = yaw
		var player := ModelSlot.find_animation_player(body)
		if player != null and player.has_animation(cell[1]):
			player.play(cell[1])
			player.seek(player.get_animation(cell[1]).length * (clip_t if clip_mode else 0.0), true)
			player.pause()
		var label := Label3D.new()
		label.text = cell[1] if clip_mode else id
		label.font_size = 36
		label.pixel_size = .004
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = body.position + Vector3(0, -.15, 0)
		world.add_child(label)
		x += 1
	var rows := (x + cols - 1) / cols
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	var w := cols * gap
	var h := rows * 2.4 + 0.8
	viewport.size = Vector2i(2400, int(2400.0 * h / w))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	cam.size = h
	cam.position = Vector3((cols - 1) * gap * .5, 1.2 - (rows - 1) * 1.2, 10)
	if angle == "top":
		cam.rotation_degrees = Vector3(-90, 0, 0)
		cam.position = Vector3((cols - 1) * gap * .5, 12, 0)
	for i in 20:
		await get_tree().process_frame
	viewport.get_texture().get_image().save_png(out)
	get_tree().quit()
