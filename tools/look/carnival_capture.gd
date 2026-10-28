extends Node

## Carnival booths: each booth's game board mid-game, seen from where the player stands.
##   godot --path . res://tools/look/carnival_capture.tscn -- OUT_DIR
## writes <booth>_playing.png and <booth>_won.png into OUT_DIR.

func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	var world := Node3D.new()
	add_child(world)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.03, 0.02, 0.05)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.5, 0.45, 0.6)
	env.environment.ambient_light_energy = 0.8
	world.add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.25, 0.2, 0.18)
	floor_mesh.material_override = floor_mat
	world.add_child(floor_mesh)
	var cam := Camera3D.new()
	world.add_child(cam)
	cam.position = Vector3(0, 1.6, 3.2)
	cam.look_at(Vector3(0, 1.3, 0))
	cam.current = true
	for type in CarnivalBooths.BOOTHS:
		var booth := CarnivalBooth3D.new()
		booth.manual = true
		booth.setup("0:0:0:%s:0:0" % type, String(type), Vector3(2.4, 2.4, 1.5))
		world.add_child(booth)
		# a stand-in "booth": a box the size of the prop
		var body := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(2.4, 2.4, 1.5)
		body.mesh = box
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.5, 0.2, 0.25)
		body.material_override = mat
		body.position = Vector3(0, 1.2, 0)
		booth.add_child(body)
		var fake := Node3D.new()
		world.add_child(fake)
		fake.position = Vector3(0, 0, 3.2)
		booth.begin_remote(2, 3, Vector3(0, 0, 3.2))
		for i in 60:
			if booth.game != null and booth.game is RingTossGame:
				var g := booth.game as RingTossGame
				g.fire() if g.rings_left > 0 and i % 20 == 5 else null
				g.set_aim(g.neck_position(0, g.angle + 0.4))
				g.step(1.0 / 30.0)
				booth._present(g.take_events())
			elif booth.game != null and booth.game is StrengthGame:
				var s := booth.game as StrengthGame
				s.puck = 0.55
			elif booth.game is ClawGame:
				var c := booth.game as ClawGame
				c.pos = Vector2(0.2, -0.1)
				if i == 30:
					c.phase = "down"
					c.phase_t = 0.5
			booth._idle_board(1.0 / 30.0)
			await get_tree().process_frame
		await _shot("%s/%s_playing.png" % [out, type])
		booth.end_game(true, 1)
		await _shot("%s/%s_won.png" % [out, type], 20)
		booth.queue_free()
		fake.queue_free()
		await get_tree().process_frame
	get_tree().quit()
