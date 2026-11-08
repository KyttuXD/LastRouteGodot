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
##   godot4 --headless res://tests/scenes/validate.tscn -- pause layout camera_console

const SUITES := ["platform", "room", "player", "body", "pause", "maze", "admin", "layout",
	"run_report", "sync", "roster", "hunters", "sprites",
	"blocky", "custom_map", "streamed_world", "sliced_startup", "props", "player_effects", "audio", "saves",
	"story", "hunter_emotes", "player_model", "hallways", "hud_overlap", "coplanar", "hunter_nav", "hunter_real", "hunter_parity", "death_lines", "hub", "furniture", "props_rework", "prop_perf", "lods", "collision", "colliders", "app_name", "room_sizes", "room_variety", "button_contrast", "account_hub", "connectivity", "controls", "density", "humps", "account_session", "admin_layout", "waypoints", "hunter_fall", "material_look", "night_watch", "night_watch_menus", "night_watch_modes", "night_watch_calls", "secret_creature", "playtest", "hub_carousel", "silent_presses", "expressions", "hunter_facing", "nw_poses", "night_watch_offices", "night_watch_keys", "night_watch_lure", "night_watch_bedroom", "night_watch_story", "night_watch_mask", "night_watch_dayshift", "night_watch_mixed", "night_watch_descent", "night_watch_extra", "night_watch_maps", "foot_slip", "face_transitions", "xivvy_flight", "night_watch_cammap", "night_watch_ui", "scheme_styles", "night_watch_admin", "night_watch_admin_a", "rescue_axe", "idle_stability", "geometry_overlap", "minimap_radar", "map_perf", "debug_view", "city_menu_layout", "map_follow", "key_conflicts", "self_update", "update_gate", "admin_entry", "region_names", "hunter_scale", "scale_fit", "wall_themes", "ambience", "biomes", "void_powers", "hunter_ids", "hunter_addons", "door_focus", "pickup_reach", "light_sight", "hiding_props", "sewers", "falls_jump", "stream_perf", "ysolde", "ravelle_traps", "ceiling_fixtures", "rest_and_sleep", "light_switches", "door_clearance", "upper_levels", "hard_abilities", "hunter_director", "anti_idle", "gray_pursuit", "sewer_crawl", "hunter_clipping", "player_eye_height", "hunter_meshes", "scale_consistency", "camping", "prompt_glyphs", "flashlight_empty", "stamina_regen", "screen_facing", "prop_orientation", "night_watch_sounds", "player_skin", "held_scale", "skin_share", "skin_sources", "player_arms", "voice_chat", "grabs", "quality_tiers", "chat", "server_privacy", "admin_panel", "pause_menu", "pause_settings", "bedrooms", "anti_cheat", "carnival_booths", "carousel", "typing_guard", "data_props", "data_regions", "data_hunters", "hide_reacquire", "inferno_caverns", "hunter_peek", "seating", "interact_aim", "mods", "maze_culling", "glyra_music", "locker_inspect", "regions_hospital", "regions_lab", "regions_greenhouse", "regions_mall", "data_packs", "data_hotswap", "data_downloads", "chase_style", "stream_errors", "music", "mezzanine_view", "seals", "death_screen_layout", "regions", "level_links", "sewer_floods", "minimap_teammates", "player_list", "player_state_packet", "coop_lossy", "crash_watch", "host_alive", "item_stacks", "stim", "revive", "guest_hunters", "data_modkit", "nav_walkable", "reserved_rooms", "hunter_faces", "lens_cull", "host_hunter_windows", "level_walk", "level_ambience", "deck_patches", "void", "ghost", "dedicated_host", "data_rooms", "data_night_watch", "grabs_external", "ceiling_gaps", "npc_teammates", "admin_hunters", "vents", "maze_winding", "vents_view", "no_invisible", "host_handoff", "web_host", "hunter_level_roam", "data_loot", "data_themes", "spiral_entry", "data_skins", "shader_lights", "original_props", "beach_look", "user_guard", "skip_hub", "no_announcements", "decor_colliders", "verrine_ducts", "hunter_decor_walk", "hunter_perf", "inferno_ramp", "melee_stun", "walk_match", "hunter_immunity", "screenshot", "waypoint_levels", "chase_cue"]
## Old suite names that still work, for branches and scripts written before a rename (biome -> region).
## Legacy names older trees still pass: the biome -> region rename split "biomes" into the four region shards.
const SUITE_ALIASES := {"biomes": ["regions_hospital", "regions_lab", "regions_greenhouse", "regions_mall"]}

## Whole-run watchdog (seconds; VALIDATE_TIMEOUT overrides). A suite that never returns -- or a runtime error that kills
## the run coroutine -- used to leave Godot idling until the machine's own watchdog; now the run reports and exits non-zero.
const DEFAULT_TIMEOUT := 1500.0

## Keeps the suites away from the real user:// (skin.png, settings.cfg, night_watch.cfg, route_saves ...): see tests/user_guard.gd.
const UserGuard := preload("res://tests/user_guard.gd")

var _current := ""
var _guard: RefCounted
var _heartbeat: Timer


func _ready() -> void:
	var limit := float(OS.get_environment("VALIDATE_TIMEOUT")) if not OS.get_environment("VALIDATE_TIMEOUT").is_empty() else DEFAULT_TIMEOUT
	var timer := get_tree().create_timer(limit, true, false, true)
	timer.timeout.connect(func() -> void:
		print("  FAIL  validation timed out after %.0f s (suite: %s)" % [limit, _current if not _current.is_empty() else "?"])
		push_error("validation timed out")
		_quit(2))
	_run()


func _run() -> void:
	# _ready runs while the tree is still building this node's parent, and a
	# suite's first act is to add a scene under root. One frame of daylight
	# turns "parent node is busy setting up children" into an ordinary add.
	await get_tree().process_frame

	var wanted := OS.get_cmdline_user_args()
	if wanted.is_empty():
		wanted = SUITES
	# A broken autoload (parse error) does not stop the run: every later call into it just returns a default, so whole
	# suites printed PASS in 0.00 s on a project that did not compile. Refuse to run on one.
	var broken := _broken_autoloads()
	if not broken.is_empty():
		for line in broken:
			print("  FAIL  %s" % line)
		print("  FAIL  the project does not load cleanly; no suite can be trusted, so none ran")
		push_error("broken autoloads: %s" % ", ".join(broken))
		_quit(1)
		return
	_guard_begin()
	var failures := 0
	for name in wanted:
		# a suite name, or a res:// path (the runner self-test points at a broken fixture this way)
		# "suite#i/n" runs shard i of n (suites that support it read VALIDATE_SHARD; see validate_hunter_real.gd)
		var base := String(name).get_slice("#", 0)
		OS.set_environment("VALIDATE_SHARD", String(name).get_slice("#", 1) if String(name).contains("#") else "")
		var path := base if base.begins_with("res://") else "res://tests/validate_%s.gd" % base
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
			_quit(1)
			return
		var suite: RefCounted = script.new()
		if suite == null or not suite.has_method("run"):
			print("  FAIL  suite %s (%s) has no run(host)" % [name, path])
			_quit(1)
			return
		var started := Time.get_ticks_msec()
		var suite_failures: int = await suite.run(self)
		var elapsed := (Time.get_ticks_msec() - started) / 1000.0
		# Most gameplay suites queue their temporary scenes for deletion. Starting
		# the next suite in the same frame leaves those worlds, group members and
		# input callbacks alive long enough to contaminate its physics assertions.
		# Flush both deletion and one physics boundary between suites so a combined
		# validation behaves exactly like running each selected suite by itself.
		await get_tree().process_frame
		await get_tree().physics_frame
		# What the suite did to the real user data (after its nodes were freed, which can write too): put back, say so, and under
		# VALIDATE_STRICT_USER=1 count it against the suite.
		suite_failures += _guard_after_suite(String(name))
		failures += suite_failures
		# One machine-readable line per suite: the parallel runner (tools/build/run_suites.py) reads
		# durations and verdicts from these instead of guessing from the free-form output.
		print("-- suite %s %s %.2fs" % [name, "FAIL" if suite_failures > 0 else "PASS", elapsed])
	if failures > 0:
		push_error("%d check(s) failed" % failures)
	else:
		print("all checks OK")
	_quit(1 if failures > 0 else 0)


func _broken_autoloads() -> PackedStringArray:
	var problems := PackedStringArray()
	for property in ProjectSettings.get_property_list():
		var key := String(property.get("name", ""))
		if not key.begins_with("autoload/"):
			continue
		var autoload_name := key.trim_prefix("autoload/")
		var path := String(ProjectSettings.get_setting(key)).trim_prefix("*")
		if path.ends_with(".gd"):
			var script := load(path) as GDScript
			if script == null or not script.can_instantiate():
				problems.append("autoload %s (%s) did not compile" % [autoload_name, path])
				continue
		if get_tree().root.get_node_or_null(NodePath(autoload_name)) == null:
			problems.append("autoload %s (%s) is missing from the tree" % [autoload_name, path])
	return problems


# ------------------------------------------------------------------------------------------------ real user data guard

func _guard_begin() -> void:
	if UserGuard.disabled_by_environment():
		print("  guard: off (VALIDATE_USER_GUARD=0): suites may change the real user:// data")
		return
	if UserGuard.scratch_user_dir():
		print("  guard: not needed, user:// is already a throw-away folder (%s)" % OS.get_user_data_dir())
		return
	var guard = UserGuard.new("user://")
	if not guard.begin():
		return
	for line in guard.recovered:
		print("  GUARD  %s" % line)
	guard.redirect_to_scratch()
	_guard = guard
	# a long suite can block the main thread, so a fresh beat is also written after every suite; this covers the quiet stretches
	_heartbeat = Timer.new()
	_heartbeat.wait_time = 15.0
	_heartbeat.process_mode = Node.PROCESS_MODE_ALWAYS
	_heartbeat.timeout.connect(guard.heartbeat)
	add_child(_heartbeat)
	_heartbeat.start()
	if guard.shared:
		print("  guard: another validator run is using user:// right now; its files are not compared, but the skin, settings, account, saves and Night Watch save go to scratch copies")
	else:
		print("  guard: user:// is protected (skin, settings, account, saves and Night Watch go to scratch copies; every file is checked after each suite)")
	print("  guard: the run is signed out of the account%s, so no suite can upload a skin or save to it" % (" (a verified login was dropped)" if guard.was_signed_in else ""))


## Checks user:// after one suite, puts back whatever it changed, and returns 1 when that must fail the suite (strict mode).
func _guard_after_suite(suite_name: String) -> int:
	if _guard == null:
		return 0
	var lines: PackedStringArray = _guard.check()
	for line in lines:
		print("  LEAK  %s: %s" % [suite_name, line])
	_guard.reset_scratch()
	_guard.heartbeat()
	if _guard.strict and not lines.is_empty():
		print("  FAIL  suite %s changed the real user data (VALIDATE_STRICT_USER=1)" % suite_name)
		return 1
	return 0


## Every way out of the run goes through here, so the real files are restored whichever way it ends.
func _guard_finish() -> void:
	if _guard == null:
		return
	var guard := _guard
	_guard = null
	if _heartbeat != null:
		_heartbeat.stop()
	guard.undo_redirect()
	for line in guard.finish():
		print("  LEAK  (end of run): %s" % line)


func _quit(code: int) -> void:
	_guard_finish()
	get_tree().quit(code)


func _exit_tree() -> void:
	_guard_finish()   # a suite that quit the tree itself, or an engine shutdown
