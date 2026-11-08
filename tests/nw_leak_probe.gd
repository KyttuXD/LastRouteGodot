class_name NwLeakProbe
extends RefCounted

## What an earlier suite left behind in the shared process, printed at the start of the suites that build offices (the Night Watch suites fail in the single-process gate and pass alone).
static func report(host: Node, tag: String) -> void:
	var tree := host.get_tree()
	var extra := []
	for child in tree.root.get_children():
		extra.append("%s(%s)" % [child.name, child.get_class()])
	print("  LEAKPROBE %s: paused=%s time_scale=%s physics_tps=%d root=[%s] bodies3d_in_root_world=%d orphan_nodes=%d" % [tag, tree.paused, Engine.time_scale, Engine.physics_ticks_per_second, ", ".join(extra),
		PhysicsServer3D.get_process_info(PhysicsServer3D.INFO_ACTIVE_OBJECTS), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))])


## Where the Night Watch suites keep their save when they are not pointing it at a file of their own. The validator runner
## (tests/user_guard.gd) sets `home` to a private scratch file; with no runner it is a throw-away file in user://. It is never
## the player's real user://night_watch.cfg: that file is progress, stars, key overrides and subtitle/calm/scare choices.
static var home := ""


static func scratch_path() -> String:
	return home if not home.is_empty() else "user://nw_validate.cfg"


## Every Night Watch suite starts from a fresh save (progress, stars, custom values and key overrides all live in the one NightWatchSave file), so the single-process gate and any suite order behave like a suite run alone.
static func fresh() -> void:
	# reset() deletes the file at the CURRENT path: never let that be the real save
	if NightWatchSave.path == NightWatchSave.DEFAULT_PATH:
		NightWatchSave.path = scratch_path()
	NightWatchSave.reset()
	# and from an empty scene: a mode scene an earlier suite queued for freeing (or forgot) is still in the shared tree, standing on the next suite's spawn
	# (the descent suite found "/root/Validate/NightWatchMixed/Player" in the way of its lift landing)
	var root := (Engine.get_main_loop() as SceneTree).root
	var host := root.get_node_or_null("Validate")
	if host == null:
		return
	for child in host.get_children():
		if child is Node3D:   # a mode scene (the suites' own helpers are never 3D nodes)
			host.remove_child(child)
			child.free()
