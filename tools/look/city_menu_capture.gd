extends Node

## Screenshots the City menu at KT's window sizes (SubViewport with the real expand-stretch rule).
##   godot --path . res://tools/look/city_menu_capture.tscn -- OUTDIR PREFIX
const SIZES := {"1280x720": Vector2i(1280, 720), "1445x860": Vector2i(1445, 860), "1920x1080": Vector2i(1920, 1080),
	"2560x1440": Vector2i(2560, 1440), "phone844x390": Vector2i(844, 390)}


func _ready() -> void:
	Build.capture_rig = true
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var prefix := args[1] if args.size() > 1 else "city_menu"
	DirAccess.make_dir_recursive_absolute(out)
	for key in SIZES:
		var pixels: Vector2i = SIZES[key]
		var holder := SubViewport.new()
		holder.size = pixels
		var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
		holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
		holder.size_2d_override_stretch = true
		holder.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(holder)
		var menu := (load("res://scenes/city_menu.tscn") as PackedScene).instantiate()
		holder.add_child(menu)
		for _i in 10:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		holder.get_texture().get_image().save_png("%s/%s_%s.png" % [out, prefix, key])
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
