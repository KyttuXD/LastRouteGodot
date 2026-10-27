extends Node

## Screenshots the admin panel at KT's resolutions (each a SubViewport with the real expand-stretch rule).
##   godot --path . res://tools/look/admin_capture.tscn -- OUTDIR
## ADMIN_TABS=1,2,3 picks tab indices (default 0,2,3).

func _ready() -> void:
	Build.capture_rig = true
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(route)
	for _i in 12:
		await get_tree().process_frame
	var tabs := [0, 2, 3]
	if OS.get_environment("ADMIN_TABS") != "":
		tabs = []
		for part in OS.get_environment("ADMIN_TABS").split(","):
			tabs.append(int(part))
	var sizes := {"1280x720": Vector2i(1280, 720), "1366x768": Vector2i(1366, 768), "1920x1080": Vector2i(1920, 1080),
		"2560x1440": Vector2i(2560, 1440), "ultrawide3440x1440": Vector2i(3440, 1440), "phone390x844": Vector2i(390, 844)}
	for key in sizes:
		var pixels: Vector2i = sizes[key]
		var holder := SubViewport.new()
		holder.size = pixels
		var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
		holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
		holder.size_2d_override_stretch = true
		holder.transparent_bg = false
		holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(holder)
		var backdrop := ColorRect.new()
		backdrop.color = Color(.12, .1, .14)
		backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
		holder.add_child(backdrop)
		var menu := AdminMenu.attach(holder, func() -> String: return "ROOM TEST1  INFINITE // DEPTH 1  RELAYS 0/5", route._infinite_admin_actions(), route._admin_roster_fields())
		await get_tree().process_frame
		menu._set_open(true)
		for tab_index in tabs:
			menu._tabs.current_tab = clampi(tab_index, 0, menu._tabs.tab_count - 1)
			menu._show_page(menu._tabs.current_tab)
			for _i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			holder.get_texture().get_image().save_png("%s/admin_%s_tab%d.png" % [out, key, tab_index])
		menu._set_open(false)
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
