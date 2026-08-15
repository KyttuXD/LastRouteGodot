extends Node

## Entry point for the headless check suites.
##
## They used to run as `--script` SceneTree scripts, which stopped working the
## moment game code referenced an autoload: in that mode Godot registers no
## singletons at all, so `MouseLock` and `GameState` fail to RESOLVE and every
## script that mentions them fails to compile. The suites then hung with no
## output, which is a worse failure than the one they exist to catch.
##
## Running them as a scene instead boots the project the way the game does --
## autoloads and all -- so a suite tests what ships.
##
##   godot4 --headless res://scenes/validate.tscn -- pause layout camera_console

const SUITES := ["room", "player", "pause", "maze", "admin", "layout", "camera_console"]


func _ready() -> void:
	_run()


func _run() -> void:
	# _ready runs while the tree is still building this node's parent, and a
	# suite's first act is to add a scene under root. One frame of daylight
	# turns "parent node is busy setting up children" into an ordinary add.
	await get_tree().process_frame

	var wanted := OS.get_cmdline_user_args()
	if wanted.is_empty():
		wanted = SUITES
	var failures := 0
	for name in wanted:
		var path := "res://scripts/validate_%s.gd" % name
		if not ResourceLoader.exists(path):
			print("  FAIL  no suite named %s" % name)
			failures += 1
			continue
		print("== %s" % name)
		var suite: RefCounted = (load(path) as GDScript).new()
		failures += await suite.run(self)
	if failures > 0:
		push_error("%d check(s) failed" % failures)
	else:
		print("all checks OK")
	get_tree().quit(1 if failures > 0 else 0)
