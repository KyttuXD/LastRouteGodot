extends SceneTree

## Screenshot of the HUD with the phone touch controls on top (docs/XR_ANDROID.md), at phone window sizes.
##   godot --path . -s dev/look/touch_capture.gd -- OUT_DIR

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	await process_frame
	var hud: Node = (load("res://game/hud/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	TouchControls.attach(root, null)
	for size in [Vector2i(1688, 780), Vector2i(2400, 1080)]:
		DisplayServer.window_set_size(size)
		root.size = size
		for _i in 12:
			await process_frame
		root.get_texture().get_image().save_png("%s/touch_hud_%dx%d.png" % [out, size.x, size.y])
		print("saved touch_hud_%dx%d" % [size.x, size.y])
	quit()
