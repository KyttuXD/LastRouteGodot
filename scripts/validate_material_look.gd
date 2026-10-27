extends RefCounted

## Matte by default (docs/MATERIAL_LOOK.md): the shared surface tables, the City tile shader, decor and every material and
## light in a booted Last Route and City scene must stay inside MaterialLook's limits (roughness >= MIN_ROUGHNESS, metallic <=
## MAX_METALLIC, light specular <= MAX_LIGHT_SPECULAR), unless emissive (glow, not glint), transparent glass, or allow-listed.
##
##   godot --headless --path . res://scenes/validate.tscn -- material_look

var _failures := 0
var _checked := 0
var _lights := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _allowed(name: String) -> bool:
	var lower := name.to_lower()
	for word in MaterialLook.ALLOWED_GLOSS:
		if lower.contains(word):
			return true
	return false


func _check_standard(material: BaseMaterial3D, where: String, strict_specular: bool) -> void:
	_checked += 1
	if material.emission_enabled and material.emission_energy_multiplier > 0.5:
		return
	if material.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and material.albedo_color.a < 0.9:
		return   # glass
	if _allowed(material.resource_name) or _allowed(where):
		return
	_expect(material.roughness >= MaterialLook.MIN_ROUGHNESS,
		"%s: roughness %.2f is below %.2f" % [where, material.roughness, MaterialLook.MIN_ROUGHNESS])
	_expect(material.metallic <= MaterialLook.MAX_METALLIC,
		"%s: metallic %.2f is above %.2f" % [where, material.metallic, MaterialLook.MAX_METALLIC])
	if strict_specular:
		_expect(material.metallic_specular <= MaterialLook.MAX_SPECULAR,
			"%s: specular %.2f is above %.2f" % [where, material.metallic_specular, MaterialLook.MAX_SPECULAR])


func _check_shader(material: ShaderMaterial, where: String) -> void:
	_checked += 1
	for name in ["roughness_value"]:
		var value = material.get_shader_parameter(name)
		if value != null:
			_expect(float(value) >= MaterialLook.MIN_ROUGHNESS, "%s: %s %.2f is below %.2f" % [where, name, float(value), MaterialLook.MIN_ROUGHNESS])
	for name in ["specular_value", "specular_base", "specular_metal"]:
		var value = material.get_shader_parameter(name)
		if value != null:
			_expect(float(value) <= MaterialLook.MAX_SPECULAR, "%s: %s %.2f is above %.2f" % [where, name, float(value), MaterialLook.MAX_SPECULAR])
	var code := material.shader.code if material.shader != null else ""
	_expect(not code.contains("SPECULAR = 0.5") and not code.contains("METALLIC = 1"), "%s: shader hard-codes a glossy value" % where)


func run(host: Node) -> int:
	# shared surface tables
	for group in ["floor", "wall", "ceiling"]:
		var painters: Dictionary = {"floor": RefTextures.FLOOR_PAINTERS, "wall": RefTextures.WALL_PAINTERS, "ceiling": RefTextures.CEILING_PAINTERS}[group]
		for kind in painters:
			_check_standard(RefTextures.material(group, String(kind)), "RefTextures %s/%s" % [group, kind], true)
			var response := RefTextures.params(group, String(kind))
			_expect(response.r >= MaterialLook.MIN_ROUGHNESS and response.g <= MaterialLook.MAX_METALLIC,
				"RefTextures.params %s/%s roughness %.2f metallic %.2f" % [group, kind, response.r, response.g])
		_check_shader(RefTextures.array_material(group), "RefTextures array %s" % group)
	for material in CitySurface.materials():
		if material is ShaderMaterial:
			_check_shader(material, "CitySurface tiles")
		elif material is BaseMaterial3D:
			_check_standard(material, "CitySurface rim", true)
	for key in ["brass", "iron", "rust", "canvas", "amber", "stone", "leaf", "vault_glass", "leaf_light", "bark", "soil", "bloom", "bloom_pale", "night", "teal"]:
		var decor := RefDecor.material(key)
		if decor is BaseMaterial3D:
			_check_standard(decor, "RefDecor " + key, false)
	_expect(MaterialLook.LIGHT_SPECULAR <= MaterialLook.MAX_LIGHT_SPECULAR, "MaterialLook.LIGHT_SPECULAR is above its own limit")
	# live scenes
	await _scan_scene(host, RoomState.Mode.DEFAULT, "res://scenes/infinite_route_test.tscn", "Last Route")
	await _scan_scene(host, RoomState.Mode.CITY, RoomState.CITY_ROUTE_SCENE, "City")
	if _failures == 0:
		print("  material_look  %d materials and %d lights in the shared tables, decor, Last Route and the City stay matte (roughness >= %.2f, metallic <= %.2f, light specular <= %.2f)" % [
			_checked, _lights, MaterialLook.MIN_ROUGHNESS, MaterialLook.MAX_METALLIC, MaterialLook.MAX_LIGHT_SPECULAR])
	return _failures


func _scan_scene(host: Node, mode: int, path: String, label: String) -> void:
	RoomState.create_local(mode)
	RoomState.seed_text = "MATERIAL-LOOK"
	Backend.enable_offline_mode()
	var scene: Node = (load(path) as PackedScene).instantiate()
	host.add_child(scene)
	for _frame in 8:
		await host.get_tree().process_frame
	var seen := {}
	_scan_node(scene, label, seen)
	scene.queue_free()
	await host.get_tree().process_frame
	RoomState.create_local(RoomState.Mode.DEFAULT)


func _scan_node(node: Node, label: String, seen: Dictionary) -> void:
	if node is Light3D:
		_lights += 1
		_expect((node as Light3D).light_specular <= MaterialLook.MAX_LIGHT_SPECULAR,
			"%s: light %s has specular %.2f" % [label, node.get_path(), (node as Light3D).light_specular])
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh != null and not _allowed(String(mesh_node.name)):
			for surface in mesh_node.mesh.get_surface_count():
				var material := mesh_node.get_active_material(surface)
				if material == null or seen.has(material):
					continue
				seen[material] = true
				var where := "%s %s (%s)" % [label, node.name, material.resource_name]
				if material is ShaderMaterial:
					_check_shader(material, where)
				elif material is BaseMaterial3D:
					_check_standard(material, where, false)
	for child in node.get_children():
		_scan_node(child, label, seen)
