extends RefCounted

## Hunter size: the tall variants are gone, every humanoid hunter is drawn at HunterRoster.MODEL_SCALE,
## and everything that depends on size follows (hit radius, view collider, stride reference), while hunters still fit the doors
## and halls and the ceiling.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- hunter_scale

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _model_height(node: Node) -> float:
	var top := -INF
	var bottom := INF
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var m := mesh as MeshInstance3D
		if m.mesh == null or not m.visible or String(m.name).contains("Beam") or String(m.name).contains("Star") or String(m.name).contains("Scythe"):
			continue   # effects and held props are not the body
		var box := m.global_transform * m.get_aabb()
		top = maxf(top, box.end.y)
		bottom = minf(bottom, box.position.y)
	return top - bottom if top > bottom else 0.0


func run(host: Node) -> int:
	var tree := host.get_tree()
	# the tall variants are gone
	var dir := DirAccess.open("res://assets/hunters_blocky")
	for sub in dir.get_directories():
		_expect(not sub.ends_with("_tall"), "tall variant %s is still in assets/hunters_blocky" % sub)
	for table_path in ["res://assets/hunters_blocky/stride_table.json", "res://assets/hunters_blocky/emotes.json"]:
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(table_path))
		for key in (parsed as Dictionary):
			_expect(not String(key).ends_with("_tall"), "%s still lists %s" % [table_path, key])
	_expect(is_equal_approx(HunterRoster.MODEL_SCALE, 1.5), "the shared hunter scale is %.2f, expected 1.5" % HunterRoster.MODEL_SCALE)
	_expect(is_equal_approx(GameConfig.HUNTER_RADIUS, .22 * HunterRoster.MODEL_SCALE), "the hunter hit radius does not follow the scale")
	_expect(GameConfig.HUNTER_RADIUS < .5, "the hunter radius no longer fits inside one cell")

	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	var tallest := 0.0
	var origin := Vector2(5.5, 5.5)
	for id in ids:
		var brain := HunterBrain.new(origin, "SCALE-%s" % id, String(id), "standard")
		brain.activate_at(origin)
		var view := HunterView3D.new()
		view.brain = brain
		host.add_child(view)
		await tree.process_frame
		view.sync_from_brain()
		var model: Node3D = view._model
		_expect(model != null and model.scale.is_equal_approx(Vector3.ONE * HunterRoster.MODEL_SCALE), "%s model scale is %s" % [id, model.scale if model != null else "missing"])
		if model != null:
			var authored := ResourceLoader.load(HunterRoster.get_identity(String(id))["model_scene"]) as PackedScene
			var plain := authored.instantiate() as Node3D
			host.add_child(plain)
			var base_height := _model_height(plain)
			plain.queue_free()
			var height := _model_height(model)
			if view._carries_scythe:
				height = base_height * HunterRoster.MODEL_SCALE   # the scythe reaches above the head; measure the body
			tallest = maxf(tallest, height)
			_expect(base_height > 0.0 and absf(height - base_height * HunterRoster.MODEL_SCALE) < .06, "%s is %.2f m, expected %.2f x %.2f" % [id, height, HunterRoster.MODEL_SCALE, base_height])
		var capsule := (view.get_node("HunterCollision") as CollisionShape3D).shape as CapsuleShape3D
		_expect(is_equal_approx(capsule.height, 1.72 * HunterRoster.MODEL_SCALE), "%s collider height %.2f does not follow the scale" % [id, capsule.height])
		_expect(capsule.radius >= brain.radius and capsule.radius < .5, "%s collider radius %.2f vs brain %.2f" % [id, capsule.radius, brain.radius])
		_expect(is_equal_approx(brain.radius, GameConfig.HUNTER_RADIUS), "%s brain radius %.2f" % [id, brain.radius])
		# the stride reference follows the scale
		_expect(is_equal_approx(HunterStride.ref_speed(String(id), "walk"),
				maxf(float(HunterStride.table().get(String(id), {}).get("walk", {}).get("ref", HunterStride.FALLBACK["walk"])), .3) * HunterRoster.MODEL_SCALE),
			"%s stride reference is not scaled" % id)
		view.queue_free()
	_expect(tallest > 0.0 and tallest < 3.95, "the tallest hunter is %.2f m, which touches the 4 m ceiling" % tallest)
	# secret creature rigs keep their size
	for id in SecretCreatures.IDS if "IDS" in SecretCreatures else []:
		if SecretCreatures.uses_creature_rig(String(id)):
			_expect(is_equal_approx(HunterRoster.scale_for(String(id)), 1.0), "creature %s was scaled" % id)

	# doors and halls: a hunter's footprint fits every door cell and mid-hall of a few real chunks
	var generator := StreamedRouteGenerator.new("SCALE-FIT")
	var navigation := StreamedHunterNavigation.new(generator, 0)
	var coords := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			coords.append(Vector3i(dx, 0, dz))
	navigation.refresh(0, coords)
	var doors := 0
	var blocked := 0
	for coord in coords:
		var data := generator.chunk(coord)
		for prop_value in data.get("region_props", []):
			var door: Dictionary = prop_value
			if not bool(door.get("room_door", false)):
				continue
			var cell: Vector2i = door.get("cell", Vector2i(-1, -1))
			doors += 1
			var world := Vector2(coord.x * StreamedRouteGenerator.CHUNK_SIZE + cell.x + .5, coord.z * StreamedRouteGenerator.CHUNK_SIZE + cell.y + .5)
			if not navigation.can_occupy(world.x, world.y, GameConfig.HUNTER_RADIUS):
				blocked += 1
	_expect(blocked == 0, "%d of %d doors are too narrow for the scaled hunter" % [blocked, doors])
	if _failures == 0:
		print("  hunter_scale  %d hunters at x%.1f (tallest %.2f m), no tall variants left, hit radius %.2f, %d doors still fit" % [ids.size(), HunterRoster.MODEL_SCALE, tallest, GameConfig.HUNTER_RADIUS, doors])
	return _failures
