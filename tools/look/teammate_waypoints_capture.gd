extends Node

## HUD teammate waypoints over a plain 3D backdrop -> captures/teammate_waypoints.png
##   godot --path . res://tools/look/teammate_waypoints_capture.tscn

func _ready() -> void:
	var root := get_tree().root
	root.size = Vector2i(960, 540)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.07, 0.1)
	add_child(env)
	var camera := Camera3D.new()
	add_child(camera)
	camera.global_position = Vector3(0, 1.7, 0)
	camera.current = true
	var hud := (load("res://scenes/hud.tscn") as PackedScene).instantiate() as HUD
	add_child(hud)
	await get_tree().process_frame
	var marks := [
		{"at": Vector2(3, -14), "level": 0, "name": "Ana", "colour": Color("63d9f1"), "age_ms": 100},
		{"at": Vector2(-6, -30), "level": 0, "name": "Bo", "colour": Color("f1a363"), "age_ms": 5000},
		{"at": Vector2(5, -9), "level": 1, "name": "Cy", "colour": Color("a3f163"), "other_floor": true, "age_ms": 100},
		{"at": Vector2(0, 14), "level": 0, "name": "Di", "colour": Color("f163d9"), "age_ms": 100},
		{"at": Vector2(500, -20), "level": 0, "name": "Ed", "colour": Color("f1e663"), "age_ms": 100},
		{"at": Vector2(-12, -6), "level": 0, "name": "Fay", "colour": Color("63d9f1"), "spectating": true, "age_ms": 100},
		{"at": Vector2(9, 3), "level": 0, "name": "Gus", "colour": Color("f16363"), "caught": true, "age_ms": 100},
	]
	hud.update_teammate_waypoints(camera, Vector3(0, 1.7, 0), marks)
	for _i in 8:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	root.get_texture().get_image().save_png("res://captures/teammate_waypoints.png")
	get_tree().quit()
