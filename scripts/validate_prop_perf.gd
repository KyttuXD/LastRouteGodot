extends RefCounted

## Props performance guard (DONE16), measured without a GPU: builds the streamed route twice (optimisations off, then on) and counts
## what the renderer and the physics server would have to carry: distinct prop materials, distinct collision box shapes, props with a
## visibility range, instance counts. The shared blocky material, shared boxes and the visibility ranges must cut those numbers; the
## limits below are the ratchet. Windowed frame times and draw calls come from tools/look/prop_perf.tscn on the mini.
##
##   godot --headless --path . res://scenes/validate.tscn -- prop_perf

const MAX_PROP_MATERIALS := 110         # shared blocky materials per style profile and grade, plus the non-blocky models
const MAX_BOX_SHAPES := 240             # one BoxShape3D per distinct blocker size (every box on the route, solid props and room parts)
const MIN_RANGED_SHARE := 0.25          # at least a quarter of the prop meshes carry a visibility range (small and medium props)

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _count(facility: Node) -> Dictionary:
	var state := {"props": 0, "meshes": 0, "ranged": 0, "bodies": 0}
	var materials := {}
	var shapes := {}
	_walk(facility, state, materials, shapes)
	return {"props": state["props"], "meshes": state["meshes"], "ranged": state["ranged"], "materials": materials.size(),
		"shapes": shapes.size(), "bodies": state["bodies"]}


func _walk(node: Node, state: Dictionary, materials: Dictionary, shapes: Dictionary, in_prop: bool = false) -> void:
	var here_prop := in_prop or node.has_meta("streamed_prop_type")
	if node.has_meta("streamed_prop_type"):
		state["props"] += 1
	if here_prop and node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		state["meshes"] += 1
		if mesh_node.visibility_range_end > 0.0:
			state["ranged"] += 1
		if mesh_node.mesh != null:
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_surface_override_material(surface)
				if material == null:
					material = mesh_node.mesh.surface_get_material(surface)
				if material != null:
					materials[material.get_rid()] = true
	if node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
		state["bodies"] += 1
		shapes[(node as CollisionShape3D).shape.get_rid()] = true
	for child in node.get_children():
		_walk(child, state, materials, shapes, here_prop)


func _build(host: Node, optimised: bool) -> Dictionary:
	ModelSlot.share_blocky_materials = optimised
	StreamedFacilityView3D.limit_prop_visibility = optimised
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "PROP-PERF"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 200:
		await host.get_tree().physics_frame
	var counted := _count(route.get_node("World/StreamedFacility"))
	route.queue_free()
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	return counted


func run(host: Node) -> int:
	var before := await _build(host, false)
	var after := await _build(host, true)
	ModelSlot.share_blocky_materials = true
	StreamedFacilityView3D.limit_prop_visibility = true
	metrics = {"before": before, "after": after}
	_expect(int(after["props"]) > 50, "only %d props were built, the scan is not looking at a real route" % int(after["props"]))
	_expect(int(after["materials"]) <= MAX_PROP_MATERIALS,
		"%d distinct prop materials (limit %d; %d without sharing)" % [after["materials"], MAX_PROP_MATERIALS, before["materials"]])
	_expect(int(after["materials"]) < int(before["materials"]),
		"sharing did not reduce the prop materials (%d -> %d)" % [before["materials"], after["materials"]])
	_expect(int(after["shapes"]) <= MAX_BOX_SHAPES, "%d distinct collision boxes (limit %d)" % [after["shapes"], MAX_BOX_SHAPES])
	_expect(int(after["shapes"]) * 2 <= int(after["bodies"]),
		"collision boxes are barely shared: %d distinct shapes for %d boxes" % [after["shapes"], after["bodies"]])
	_expect(float(after["ranged"]) >= MIN_RANGED_SHARE * float(after["meshes"]),
		"only %d of %d prop meshes have a visibility range" % [after["ranged"], after["meshes"]])
	_expect(int(before["ranged"]) == 0, "the baseline build already had visibility ranges")
	if _failures == 0:
		print("  prop_perf  %d props / %d meshes: materials %d -> %d, %d collision boxes on %d shared shapes, %d meshes with a visibility range" % [
			after["props"], after["meshes"], before["materials"], after["materials"], after["bodies"], after["shapes"], after["ranged"]])
	return _failures
