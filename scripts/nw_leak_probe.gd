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
