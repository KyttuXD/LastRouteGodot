extends Node

## Screenshots the game hub at 1280x720, 1920x1080 and 3440x1440 ultrawide (real expand-stretch rule per viewport).
##   godot --path . res://tools/look/hub_capture.tscn -- OUTDIR
func _ready() -> void:
	Build.capture_rig = true
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	var sizes := {"1280x720": Vector2i(1280, 720), "1920x1080": Vector2i(1920, 1080), "ultrawide3440x1440": Vector2i(3440, 1440)}
	for key in sizes:
		var pixels: Vector2i = sizes[key]
		var holder := SubViewport.new()
		holder.size = pixels
		var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
		holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
		holder.size_2d_override_stretch = true
		holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(holder)
		var hub: Control = (load("res://scenes/game_hub.tscn") as PackedScene).instantiate()
		holder.add_child(hub)
		for _i in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		holder.get_texture().get_image().save_png("%s/hub_%s.png" % [out, key])
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
