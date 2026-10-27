extends Node

## The Facility screenshots at 1280x720:
##   godot --path . res://tools/look/night_watch_story_capture.tscn -- OUT_DIR
## writes 1280x720_story_gallery.png (the gallery lamps, Opalie two steps off, the task list) and 1280x720_story_control.png (Control with the lift open on Quenelle).

func _shot(path: String, frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(path)


func _ready() -> void:
	var out := OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	await get_tree().process_frame
	NightWatchSave.path = "user://night_watch_capture.cfg"
	NightWatchSave.reset()
	NightWatchSession.start_mode("story", 4, {}, 4242)
	var game := (load("res://scenes/night_watch_story.tscn") as PackedScene).instantiate() as StoryGame
	game.manual_clock = true
	add_child(game)
	await get_tree().process_frame
	game.sim.levels = {"opalie": 12, "porcelle": 0, "quenelle": 12}
	game.sim.task_idx = 3
	game.sim.puzzle = game.sim._make_puzzle(game.sim.tasks[3])
	game.sim.room = "gallery"
	game.sim.opalie["dist"] = 2
	game.sim.noise = 40.0
	game.player.global_position = game.world.arrival("gallery", "L") + Vector3(-1.2, 0.0, 0.8)
	game.face_player(0.0, -0.05)
	game._sync_visuals()
	game.advance_ms(20.0)
	game.face_player(0.0, -0.05)
	await _shot(out + "/1280x720_story_gallery.png", 10)
	game.sim.room = "control"
	game.sim.task_idx = 0
	game.sim.puzzle = game.sim._make_puzzle(game.sim.tasks[0])
	game.sim.quenelle["state"] = "open"
	game.player.global_position = Vector3(0.0, 0.0, 0.8)
	game.face_player(0.0, 0.0)
	game._sync_visuals()
	game.advance_ms(20.0)
	await _shot(out + "/1280x720_story_control.png", 10)
	NightWatchSave.reset()
	NightWatchSave.path = NightWatchSave.DEFAULT_PATH
	get_tree().quit()
