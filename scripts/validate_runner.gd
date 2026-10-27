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
	"story", "hunter_emotes", "player_model", "hallways", "hud_overlap", "coplanar", "hunter_nav", "hunter_real", "hunter_parity", "death_lines", "hub", "furniture", "props_rework", "prop_perf", "lods", "collision", "colliders", "app_name", "room_sizes", "button_contrast", "account_hub", "connectivity", "controls", "density", "humps", "account_session", "admin_layout", "waypoints", "hunter_fall", "material_look", "night_watch", "night_watch_menus", "night_watch_modes", "night_watch_calls", "city", "city_nav", "secret_creature", "playtest", "hub_carousel", "silent_presses", "expressions", "hunter_facing", "nw_poses", "night_watch_offices", "night_watch_keys", "night_watch_lure", "night_watch_bedroom", "night_watch_story", "night_watch_mask", "night_watch_dayshift", "night_watch_mixed", "night_watch_descent", "night_watch_extra", "night_watch_maps", "foot_slip", "face_transitions", "xivvy_flight", "night_watch_cammap", "scheme_styles", "night_watch_admin", "night_watch_admin_a", "rescue_axe", "idle_stability", "geometry_overlap", "minimap_radar", "debug_view", "hunter_scale"]


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
		# A suite that fails to PARSE loads as null, and awaiting a call on null
		# never returns -- so a typo in a check script used to look exactly like
		# a hanging game, with the parse error scrolled off above it. Say what
		# happened and keep going.
		var script := load(path) as GDScript
		var suite: RefCounted = script.new() if script != null else null
		if suite == null:
			print("  FAIL  %s did not compile (see the parse error above)" % path)
			failures += 1
			continue
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
