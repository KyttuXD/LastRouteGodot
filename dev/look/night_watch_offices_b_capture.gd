extends Node

## Captures of Masked Hours' front office and Salvage Run's cargo bay at 1280x720: from the entrance and from the desk (docs/night_watch_offices/).
##   godot --path . res://dev/look/night_watch_offices_b_capture.tscn -- OUT_DIR
## writes front_office_door.png, front_office_desk.png, cargo_bay_door.png, cargo_bay_desk.png.

func _shot(path: String, frames := 10) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSession.start_mode("mask", 1, {}, 4242)
	var mask := (load("res://game/night_watch/mask/night_watch_mask.tscn") as PackedScene).instantiate() as MaskGame
	mask.manual_clock = true
	add_child(mask)
	await get_tree().process_frame
	mask.office.set_lamp(true)
	mask.hud.visible = false
	mask.player.global_position = Vector3(2.6, 0.0, 0.9)
	mask.face_player(PI * 0.3, -0.08)
	await _shot(out + "/front_office_door.png")
	mask.player.global_position = Vector3(0.0, 0.0, 0.9)
	mask.face_player(0.0, -0.2)
	await _shot(out + "/front_office_desk.png")
	mask.queue_free()
	await get_tree().process_frame
	NightWatchSession.start_mode("dayshift", 3, {}, 4242)
	var cargo := (load("res://game/night_watch/dayshift/night_watch_dayshift.tscn") as PackedScene).instantiate() as DayshiftGame
	cargo.manual_clock = true
	add_child(cargo)
	await get_tree().process_frame
	cargo.start_shift([])
	cargo.hud.visible = false
	cargo.sim.s["items"] = [{"slot": 1, "kind": "parts", "value": 25, "need": 3500.0, "progress": 1200.0, "age": 0.0}, {"slot": 2, "kind": "prize", "value": 60, "need": 5500.0, "progress": 0.0, "age": 0.0}]
	cargo.sim.s["spawnAt"] = 1e12
	cargo.advance_ms(50.0)
	cargo.player.global_position = Vector3(2.6, 0.0, 0.9)
	cargo.face_player(PI * 0.3, -0.08)
	await _shot(out + "/cargo_bay_door.png")
	cargo.player.global_position = Vector3(0.0, 0.0, 0.9)
	cargo.face_player(0.0, -0.2)
	await _shot(out + "/cargo_bay_desk.png")
	get_tree().quit()
