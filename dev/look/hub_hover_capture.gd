extends Node

## The hub's buttons hovered and focused at 1280x720, so a label that disappears on a state is visible at a glance.
##   godot --path . res://dev/look/hub_hover_capture.tscn -- OUTDIR
func _ready() -> void:
	Build.capture_rig = true
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var pixels := Vector2i(1280, 720)
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://tests/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(holder)
	var hub: Control = (load("res://game/menus/game_hub.tscn") as PackedScene).instantiate()
	holder.add_child(hub)
	for _i in 6:
		await get_tree().process_frame
	var names := ["Launch_last_route", "Launch_night_watch", "AccountButton", "SettingsButton", "AdminButton", "QuitButton"]
	var sheet := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	DirAccess.make_dir_recursive_absolute(out)
	var shots := {}
	for state in ["hover", "focus"]:
		for button_name in names:
			var button := hub.find_child(button_name, true, false) as Button
			if button == null:
				continue
			if state == "hover":
				var at := button.get_global_rect().get_center()
				var motion := InputEventMouseMotion.new()
				motion.position = at
				motion.global_position = at
				holder.push_input(motion)
			else:
				button.grab_focus()
			for _i in 4:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var image := holder.get_texture().get_image()
			var scale := Vector2(pixels) / units
			var unit_rect := button.get_global_rect().grow(8.0)
			var rect := Rect2i(Vector2i((unit_rect.position * scale).round()), Vector2i((unit_rect.size * scale).round()))
			rect = rect.intersection(Rect2i(Vector2i.ZERO, pixels))
			shots["%s_%s" % [button_name, state]] = image.get_region(rect)
		var away := InputEventMouseMotion.new()
		away.position = Vector2(2, 2)
		holder.push_input(away)
		await get_tree().process_frame
	var y := 0
	for state in ["hover", "focus"]:
		var x := 0
		var row_height := 0
		for button_name in names:
			var key := "%s_%s" % [button_name, state]
			if not shots.has(key):
				continue
			var piece: Image = shots[key]
			piece.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(piece, Rect2i(Vector2i.ZERO, piece.get_size()), Vector2i(x, y))
			x += piece.get_width() + 6
			row_height = maxi(row_height, piece.get_height())
		y += row_height + 10
	sheet.save_png("%s/hub_hover_focus_1280x720.png" % out)
	get_tree().quit()
