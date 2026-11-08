extends Node

## The Descent screenshots at 1280x720 (docs/night_watch_modes/):
##   godot --path . res://dev/look/night_watch_descent_capture.tscn -- OUT_DIR
## writes 1280x720_descent_wires.png (descent 3, fuse boxes, Elise down the sill), _descent_pipes.png and _descent_door.png (Elise at the glass).

func _shot(path: String, frames := 10) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _shift(level: int, seed_number: int) -> NightWatchDescentGame:
	NightWatchSession.start_mode("descent", level, {}, seed_number)
	var shift := (load("res://game/night_watch/descent/night_watch_descent.tscn") as PackedScene).instantiate() as NightWatchDescentGame
	shift.manual_clock = true
	add_child(shift)
	return shift


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	NightWatchSave.path = "user://night_watch_descent_capture.cfg"
	NightWatchSave.reset()
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	var shift := _shift(4, 12)
	await get_tree().process_frame
	shift.sim.stages = ["wires", "memory", "pipes", "hold"]
	shift.sim.puzzle = shift.sim._build("wires")
	shift.advance_ms(NightWatchDescentLogic.RIDE_MS + 10.0)
	shift.sim.threat = 55.0
	shift.advance_ms(10.0)
	await _shot("%s/1280x720_descent_wires.png" % out)
	shift.sim.threat = 91.0
	shift.sim.stage_idx = 2
	shift.sim.puzzle = shift.sim._build("pipes")
	shift.advance_ms(10.0)
	await _shot("%s/1280x720_descent_pipes.png" % out)
	shift.queue_free()
	await get_tree().process_frame
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
