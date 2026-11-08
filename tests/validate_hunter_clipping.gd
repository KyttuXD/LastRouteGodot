extends RefCounted

## Every blocky hunter, every clip, sampled at SAMPLES timesteps (HunterClipAudit): swaying parts must not cut through the body,
## parts must not detach, feet must stay on the floor. Prints the worst findings; any finding fails the suite.
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_clipping
## HUNTER_ONLY=porcelle,aki narrows the run.

var _failures := 0


func run(host: Node) -> int:
	var only := OS.get_environment("HUNTER_ONLY")
	var ids: Array = []
	for id in HunterRoster.PROFILES:
		if only.is_empty() or only.split(",").has(String(id)):
			ids.append(String(id))
	var all: Array = []
	if OS.get_environment("CLIP_DEBUG") != "":
		_debug(host, OS.get_environment("CLIP_DEBUG"))
	for id in ids:
		var path := "res://assets/hunters_blocky/%s/%s.glb" % [id, id]
		if not ResourceLoader.exists(path):
			continue
		var model := ModelSlot.instantiate(path)
		if model == null:
			continue
		host.add_child(model)
		await host.get_tree().process_frame
		var found := HunterClipAudit.audit(model, id)
		all.append_array(found)
		model.queue_free()
	all.sort_custom(func(a, b): return float(a["depth"]) > float(b["depth"]))
	var shown := 0
	for f in all:
		if shown < 60:
			print("  %-10s %-14s %-12s %-28s %.1f cm @%.2f" % [f["hunter"], f["clip"], f["kind"], f["pair"],
				float(f["depth"]) * 100.0, float(f["t"])])
			shown += 1
	var by_hunter := {}
	for f in all:
		by_hunter[f["hunter"]] = int(by_hunter.get(f["hunter"], 0)) + 1
	var by_kind := {}
	for f in all:
		by_kind[f["kind"]] = int(by_kind.get(f["kind"], 0)) + 1
	print("  by kind %s" % by_kind)
	print("  clipping findings: %d across %d hunters %s" % [all.size(), by_hunter.size(), by_hunter])
	if not all.is_empty():
		print("  FAIL  %d hunter clip findings" % all.size())
		_failures = 1
	return _failures


func _debug(host: Node, id: String) -> void:
	var model := ModelSlot.instantiate("res://assets/hunters_blocky/%s/%s.glb" % [id, id])
	host.add_child(model)
	await host.get_tree().process_frame
	var player := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	print("  DBG anims %s" % [player.get_animation_list()])
	for clip in ["rest", "chase"]:
		if clip != "rest":
			player.play(clip)
			player.seek(player.get_animation("chase").length * 0.5625, true)
			print("  DBG len=%s" % player.get_animation("chase").length)
		print("  DBG player=%s root=%s anim=%s pos=%s speed=%s" % [player.get_path(), player.root_node, player.assigned_animation, player.current_animation_position, player.speed_scale])
		var an := player.get_animation("chase") if player.has_animation("chase") else null
		if an != null:
			print("  DBG tracks=%d first=%s" % [an.get_track_count(), an.track_get_path(0)])
		for n in ["Belly", "Pony-3"]:
			var node := model.find_child(n, true, false) as MeshInstance3D
			if node != null:
				print("  DBG %s %s xf=%s aabb=%s" % [clip, n, node.global_transform, node.mesh.get_aabb()])
		var pb := model.find_child("Pony-3", true, false) as MeshInstance3D
		var bb := model.find_child("Belly", true, false) as MeshInstance3D
		print("  DBG depth=%s" % HunterClipAudit._obb_depth(pb.global_transform, pb.mesh.get_aabb(), bb.global_transform, bb.mesh.get_aabb()))
