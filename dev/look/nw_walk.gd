extends Node

## Debug: Masked Hours from several floor positions and headings, looking down a little, 960x540 PNGs.
##   godot --path . res://dev/look/nw_walk.tscn -- OUT_DIR
func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(960, 540)
	NightWatchSession.start_mode("mask", 2, {}, 5)
	var game := (load(NightWatchModeRegistry.scene_for("mask")) as PackedScene).instantiate()
	game.set("manual_clock", true)
	add_child(game)
	if game.has_method("start_shift"):
		game.call("start_shift", [])
	for i in 10:
		await get_tree().process_frame
	game.call("advance_ms", 300.0)
	var spots := [Vector3(-2.2, 0, 0.6), Vector3(2.2, 0, 0.6), Vector3(-1.5, 0, 2.5), Vector3(1.5, 0, 2.5)]
	var n := 0
	for spot in spots:
		for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
			game.player.global_position = (game.office as Node3D).global_position + spot
			game.call("face_player", yaw, -0.45)
			for i in 6:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png("%s/w%02d.png" % [out, n])
			n += 1
	get_tree().quit()
