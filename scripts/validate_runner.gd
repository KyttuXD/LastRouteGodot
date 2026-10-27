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

const SUITES := ["room", "player", "body", "pause", "maze", "admin", "layout",
	"run_report", "sync", "roster", "hunters", "sprites",
	"blocky", "custom_map", "streamed_world", "props", "player_effects", "audio", "saves",
	"story", "hunter_emotes", "player_model", "hallways", "hud_overlap", "coplanar", "hunter_nav", "hunter_real", "hunter_parity", "death_lines", "hub", "furniture", "props_rework", "prop_perf", "lods", "collision", "colliders", "app_name", "room_sizes", "button_contrast", "account_hub", "connectivity", "controls", "density", "humps", "account_session", "admin_layout", "waypoints", "hunter_fall", "material_look", "night_watch", "night_watch_menus", "night_watch_modes", "night_watch_calls", "secret_creature", "playtest", "hub_carousel", "silent_presses", "expressions", "hunter_facing", "nw_poses", "night_watch_offices", "night_watch_keys", "night_watch_lure", "night_watch_bedroom", "night_watch_story", "night_watch_mask", "night_watch_dayshift", "night_watch_mixed", "night_watch_descent", "night_watch_extra", "night_watch_maps", "foot_slip", "face_transitions", "xivvy_flight", "night_watch_cammap", "night_watch_ui", "scheme_styles", "night_watch_admin", "night_watch_admin_a", "rescue_axe", "idle_stability", "geometry_overlap", "minimap_radar", "debug_view", "hunter_scale", "scale_fit", "wall_themes", "city", "biomes", "hiding_props"]


## Whole-run watchdog (seconds; VALIDATE_TIMEOUT overrides). A suite that never returns -- or a runtime error that kills
## the run coroutine -- used to leave Godot idling until the machine's own watchdog; now the run reports and exits non-zero.
const DEFAULT_TIMEOUT := 1500.0

var _current := ""


func _ready() -> void:
	var limit := float(OS.get_environment("VALIDATE_TIMEOUT")) if not OS.get_environment("VALIDATE_TIMEOUT").is_empty() else DEFAULT_TIMEOUT
	var timer := get_tree().create_timer(limit, true, false, true)
	timer.timeout.connect(func() -> void:
		print("  FAIL  validation timed out after %.0f s (suite: %s)" % [limit, _current if not _current.is_empty() else "?"])
		push_error("validation timed out")
		get_tree().quit(2))
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
		# a suite name, or a res:// path (the runner self-test points at a broken fixture this way)
		var path := String(name) if String(name).begins_with("res://") else "res://scripts/validate_%s.gd" % name
		_current = String(name)
		if not ResourceLoader.exists(path):
			print("  FAIL  no suite named %s" % name)
			failures += 1
			continue
		print("== %s" % name)
		# A suite that fails to PARSE loads as null, and awaiting a call on null
		# never returns -- so a typo in a check script used to look exactly like
		# a hanging game, with the parse error scrolled off above it. Say what
		# happened and keep going.
		# A script with a parse error still LOADS (non-null) but cannot be instantiated; calling new() on it raised a script
		# error that ended this coroutine, and the run hung. Check first, report, and stop with a non-zero exit.
		var script := load(path) as GDScript
		if script == null or not script.can_instantiate():
			print("  FAIL  suite %s (%s) did not compile -- see the parse error above" % [name, path])
			push_error("suite %s did not compile" % name)
			get_tree().quit(1)
			return
		var suite: RefCounted = script.new()
		if suite == null or not suite.has_method("run"):
			print("  FAIL  suite %s (%s) has no run(host)" % [name, path])
			get_tree().quit(1)
			return
		failures += await suite.run(self)
		# Most gameplay suites queue their temporary scenes for deletion. Starting
		# the next suite in the same frame leaves those worlds, group members and
		# input callbacks alive long enough to contaminate its physics assertions.
		# Flush both deletion and one physics boundary between suites so a combined
		# validation behaves exactly like running each selected suite by itself.
		await get_tree().process_frame
		await get_tree().physics_frame
	if failures > 0:
		push_error("%d check(s) failed" % failures)
	else:
		print("all checks OK")
	get_tree().quit(1 if failures > 0 else 0)
