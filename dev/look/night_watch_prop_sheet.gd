extends Node

## Inspect every Night Watch prop from all sides: each office prop and each camera-room prop group alone on a neutral background, lit evenly,
## shot from 8 angles (front, right, back, left, two three-quarter views, top, underneath) and joined into one contact sheet per prop.
##   godot --path . res://dev/look/night_watch_prop_sheet.tscn -- OUT_DIR [office|building|all]
## writes OUT_DIR/office_<Prop>.png and OUT_DIR/building_<room>_<Prop>.png (1920 x 540: 4 x 2 views of 480 x 270).

const VIEWS := [[0.0, 14.0], [90.0, 14.0], [180.0, 14.0], [270.0, 14.0], [45.0, 28.0], [225.0, 28.0], [20.0, 80.0], [20.0, -35.0]]


func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi.mesh == null:
			continue
		var a := mi.global_transform * mi.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box


func _sheet(node: Node3D, hide_list: Array, cam: Camera3D, path: String) -> void:
	for n in hide_list:
		(n as Node3D).visible = false
	node.visible = true
	var box := _aabb_of(node)
	var centre := box.get_center()
	var radius := maxf(0.4, box.size.length() * 0.5)
	var sheet := Image.create(1920, 540, false, Image.FORMAT_RGB8)
	var i := 0
	for v in VIEWS:
		var yaw := deg_to_rad(float(v[0]))
		var pitch := deg_to_rad(float(v[1]))
		var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
		cam.look_at_from_position(centre + dir * radius * 2.4, centre, Vector3.UP if absf(pitch) < 1.4 else Vector3.FORWARD)
		cam.far = 400.0
		for f in 3:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.convert(Image.FORMAT_RGB8)
		img.resize(480, 270, Image.INTERPOLATE_BILINEAR)
		sheet.blit_rect(img, Rect2i(0, 0, 480, 270), Vector2i((i % 4) * 480, (i / 4) * 270))
		i += 1
	sheet.save_png(path)
	for n in hide_list:
		(n as Node3D).visible = true


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var which := args[1] if args.size() > 1 else "all"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(960, 540)
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.57, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.85, 0.85, 0.9)
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(-0.9, 0.6, 0.0)
	sun.light_energy = 0.6
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 40.0
	root.add_child(cam)
	cam.make_current()
	var office := NightWatchOffice.new()
	root.add_child(office)
	var building := NightWatchBuilding.new()
	root.add_child(building)
	await get_tree().process_frame
	await get_tree().process_frame
	if which == "office" or which == "all":
		var others: Array = []
		for k in office.props:
			others.append(office.props[k])
		others.append(building)
		for k in office.props:
			var hide_list := others.filter(func(n): return n != office.props[k])
			await _sheet(office.props[k], hide_list, cam, "%s/office_%s.png" % [out, k])
	if which == "building" or which == "all":
		var all_groups: Array = []
		for k in building.props:
			all_groups.append(building.props[k])
		for k in building.props:
			var hide_list2: Array = all_groups.filter(func(n): return n != building.props[k])
			hide_list2.append(office)
			# the room shells stay hidden too: a prop is shown alone
			for rid in building.rooms:
				for c in (building.rooms[rid] as Node3D).get_children():
					if c != building.props[k] and not hide_list2.has(c):
						hide_list2.append(c)
			await _sheet(building.props[k], hide_list2, cam, "%s/building_%s.png" % [out, String(k).replace("/", "_")])
	get_tree().quit()
