extends Node

## Ladder climb in true first person: the runner's own player model climbing a ladder with the sewer ladder's layout (rungs
## every .3 m from .28 m up, .4 m in front of the climbing line), seen from its eyes, hands on the rungs, classic and slim
## arms: going up, going down, and the top dismount, plus one third-person view of the same climb. Windowed:
##   Godot --path . res://tools/look/climb_hands.tscn -- /tmp/climb_caps

func _shot(out: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


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
	player.input_frozen = true
	var foot := player.global_position
	var yaw := player.rotation.y
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var ladder := Node3D.new()
	scene.add_child(ladder)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.6, .55, .45)
	for i in 14:
		var rung := MeshInstance3D.new()
		rung.name = "Rung%02d" % i
		var bar := BoxMesh.new()
		bar.size = Vector3(.6, .04, .04)
		bar.material = material
		rung.mesh = bar
		ladder.add_child(rung)
		rung.global_position = foot + forward * .4 + Vector3.UP * (.28 + i * .3)
		rung.look_at(rung.global_position + forward, Vector3.UP)
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var post := BoxMesh.new()
		post.size = Vector3(.05, 4.4, .05)
		post.material = material
		rail.mesh = post
		ladder.add_child(rail)
		rail.global_position = foot + forward * .4 + forward.cross(Vector3.UP) * (.3 * side) + Vector3.UP * 2.2
	var light := OmniLight3D.new()
	light.light_energy = 3.0
	light.omni_range = 5.0
	scene.add_child(light)
	light.global_position = foot - forward * .6 + Vector3.UP * 2.2
	var side_camera := Camera3D.new()
	scene.add_child(side_camera)
	for style in ["classic", "slim"]:
		Settings.skin_arms = style
		player._apply_visual_settings()
		player.global_position = foot
		player.rotation.y = yaw
		player._pitch = -.15
		player._apply_look_rotation()
		player.active_camera().current = true
		player.ladder_climb = {}
		player.begin_ladder_climb(foot, 3.0, 0.4, yaw, foot + Vector3.UP * 3.0 + forward * .6, foot - forward * .6, 0, 0)
		player.ladder_climb["phase"] = "climb"
		for step in 3:
			player.ladder_climb["height"] = .9 + float(step) * .14   # going up
			player._update_ladder_climb(1.0 / 60.0)
			for _i in 4:
				await get_tree().process_frame
			await _shot(out, "climb_%s_up_%d" % [style, step])
		player.ladder_climb["height"] = 1.05
		player._update_ladder_climb(1.0 / 60.0)
		for _i in 4:
			await get_tree().process_frame
		await _shot(out, "climb_%s_down" % style)
		if style == "classic":
			# the same climb from beside the ladder, as another player sees the model
			side_camera.global_position = foot + forward.cross(Vector3.UP) * 1.8 - forward * .4 + Vector3.UP * 2.0
			side_camera.look_at(player.global_position + Vector3.UP * 1.0, Vector3.UP)
			side_camera.current = true
			for _i in 3:
				await get_tree().process_frame
			await _shot(out, "climb_third_person")
			player.active_camera().current = true
		player.ladder_climb["height"] = 3.0
		player._update_ladder_climb(1.0 / 60.0)
		player._ladder_dismount("top")
		for i in 40:
			player._update_ladder_climb(1.0 / 60.0)
			await get_tree().process_frame
			if i == 12:
				await _shot(out, "climb_%s_top_dismount" % style)
			if player.ladder_climb.is_empty():
				break
		player.ladder_climb = {}
		player._show_climb_hands(false)
	Settings.skin_arms = "auto"
	get_tree().quit()
