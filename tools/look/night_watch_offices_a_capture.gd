extends Node

## Lane A's three offices (broadcast booth, child's bedroom, control room), one image from the door and one from the desk (or the main station) each, 1280x720:
##   godot --path . res://tools/look/night_watch_offices_a_capture.tscn -- OUT_DIR
## writes <office id>_door.png and <office id>_desk.png.

const SHOTS := {
	"lure": {"door": [Vector3(0.0, 1.6, 1.7), Vector3(-3.0, 1.0, 0.0)], "desk": [Vector3(0.2, 1.6, 1.0), Vector3(0.0, 1.0, -2.0)]},
	"bedroom": {"door": [Vector3(0.0, 0.95, 1.9), Vector3(5.0, 1.0, -0.9)], "desk": [Vector3(0.0, 0.95, 1.9), Vector3(-0.9, 0.6, -1.0)]},
	"story": {"door": [Vector3(1.0, 1.6, 1.8), Vector3(0.0, 1.0, -2.5)], "desk": [Vector3(0.6, 1.6, 0.3), Vector3(-1.2, 0.9, 1.9)]},
}


func _shot(path: String, frames := 6) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	for mode in SHOTS:
		var office := NightWatchOfficeRegistry.make(mode)
		var holder := Node3D.new()
		add_child(holder)
		var env := WorldEnvironment.new()
		var e := Environment.new()
		e.background_mode = Environment.BG_COLOR
		e.background_color = Color(0.02, 0.02, 0.03)
		e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		e.ambient_light_color = office.spec.mood["ambient"]
		e.ambient_light_energy = 1.0
		env.environment = e
		holder.add_child(env)
		holder.add_child(office)
		if mode == "bedroom":
			office.call("set_light", "hall")
		if mode == "story":
			(office as Node3D).position = Vector3.ZERO
		var cam := Camera3D.new()
		cam.fov = 70.0
		holder.add_child(cam)
		cam.current = true
		for view in ["door", "desk"]:
			var pair: Array = SHOTS[mode][view]
			cam.transform = Transform3D(Basis.IDENTITY, pair[0]).looking_at(pair[1], Vector3.UP)
			if mode == "bedroom" and view == "desk":
				office.call("set_light", "bed")
			await _shot("%s/%s_%s.png" % [out, office.spec.id, view])
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
