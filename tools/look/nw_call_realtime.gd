extends Node

## Zellia's call in REAL time (no manual clock), as the installed game runs it: prints what the call box shows each second and saves a screenshot.
##   godot --path . res://tools/look/nw_call_realtime.tscn -- OUT_DIR [mode] [night]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp"
	var mode := args[1] if args.size() > 1 else "classic"
	var night := int(args[2]) if args.size() > 2 else 1
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSession.start_mode(mode, night, {}, 5)
	var game := (load(NightWatchModeRegistry.scene_for(mode)) as PackedScene).instantiate()
	add_child(game)
	var hud = game.get("hud")
	for second in 16:
		await get_tree().create_timer(1.0).timeout
		print("t=%d visible=%s text='%s' name='%s' panel=%s hint=%s muted=%s subtitles=%s" % [second + 1, hud.call_panel.visible, hud.call_label.text, hud.call_panel.get_node("CallRow/CallName").text, hud.call_panel.get_global_rect(), hud.hint_label.visible, hud.muted, hud.subtitles])
		if hud.call_panel.visible and hud.call_label.text.length() > 20:
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/call_realtime_%s_%d.png" % [out, mode, night])
			break
	get_tree().quit()
