class_name XRRenderAudit
extends RefCounted

## Why a model would not show in a headset (docs/XR_ANDROID.md, "Models in VR"). Used by validate_platform for every
## hunter: an empty list means at least one visible, drawable surface and nothing that the Quest's mobile/XR path drops.


static func problems(model: Node) -> Array:
	var notes := []
	var drawable := 0
	var nodes := model.find_children("*", "GeometryInstance3D", true, false)
	if model is GeometryInstance3D:
		nodes.append(model)
	for node in nodes:
		var geometry := node as GeometryInstance3D
		if not geometry.is_visible_in_tree():
			continue
		if geometry.layers & 1 == 0:
			notes.append("%s not on layer 1" % geometry.name)
		if geometry.transparency >= 0.99:
			notes.append("%s fully transparent" % geometry.name)
		if geometry is SpriteBase3D:
			drawable += 1
			continue
		var instance := geometry as MeshInstance3D
		if instance == null:
			continue
		if instance.mesh == null or instance.mesh.get_surface_count() == 0:
			notes.append("%s has no mesh" % instance.name)
			continue
		var box := instance.get_aabb()
		if box.size.length() < 0.001 or box.size.length() > 100.0:
			notes.append("%s bounding box %s" % [instance.name, box.size])
		var surfaces_ok := true
		for surface in instance.mesh.get_surface_count():
			var material := instance.get_active_material(surface)
			var issue := material_problem(material)
			if not issue.is_empty():
				notes.append("%s surface %d %s" % [instance.name, surface, issue])
				surfaces_ok = false
		if surfaces_ok:
			drawable += 1
	if drawable == 0:
		notes.append("nothing drawable")
	return notes


## Empty when `material` draws on the Quest's Compatibility/XR path.
static func material_problem(material: Material) -> String:
	if material == null:
		return "has no material"
	if material is ShaderMaterial:
		var shader := (material as ShaderMaterial).shader
		if shader == null:
			return "has a shader material without a shader"
		var code := shader.code
		for unsupported in ["SCREEN_TEXTURE", "hint_screen_texture", "hint_depth_texture", "DEPTH_TEXTURE"]:
			if code.contains(unsupported):
				return "reads %s (not on the mobile XR path)" % unsupported
		return ""
	if material is BaseMaterial3D:
		var base := material as BaseMaterial3D
		if base.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED and base.albedo_color.a < 0.05:
			return "is fully transparent"
		if base.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR and base.alpha_scissor_threshold >= 0.99:
			return "alpha scissor discards everything"
	return ""
