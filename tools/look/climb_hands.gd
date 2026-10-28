extends Node

## Ladder-climb first person capture: the real player starts a climb and the skinned hands (classic and slim arms) are shot at
## a few points of the reach cycle. Windowed:
##   Godot --path . --scene res://tools/look/climb_hands.tscn -- /tmp/climb_caps

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/climb_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	add_child(scene)
	for _i in 20:
		await get_tree().process_frame
	var player: PlayerController3D = scene.player
	var fill := OmniLight3D.new()
	fill.light_energy = 2.0
	fill.omni_range = 3.0
	fill.position = Vector3(.3, .2, -.2)
	player.active_camera().add_child(fill)
	for style in ["classic", "slim"]:
		Settings.skin_arms = style
		player._apply_visual_settings()
		player.ladder_climb = {}
		player.begin_ladder_climb(player.global_position, 3.0, 1.0, player.rotation.y, player.global_position + Vector3(0, 3, -1),
			player.global_position + Vector3(0, 0, 1), 0, 0)
		player.ladder_climb["phase"] = "climb"
		for step in 3:
			player._animate_climb_hands(float(step) * .17, true)
			for _i in 6:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/climb_%s_%d.png" % [out, style, step])
		player.ladder_climb = {}
		player._show_climb_hands(false)
	Settings.skin_arms = "auto"
	get_tree().quit()
