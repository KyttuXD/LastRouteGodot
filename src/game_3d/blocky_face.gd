class_name BlockyFace
extends RefCounted

## Expression swap for the cube ("blocky") hunters in assets/hunters_blocky/.
##
## Each GLB has a "Face" quad laid over the head's front face. Its UVs point at
## cell 0 of a 3-column grid of 8x8 expression cells under the skin (atlas 64x128),
## so changing expression is a UV offset on the quad's own material. "derp" is an
## animation: four cells (6-9) in which the iris steps clockwise round each eye.

const CELLS := {"neutral": 0, "blink": 1, "stun": 2, "chase": 3, "scream": 4, "happy": 5, "derp": 6}
const DERP_FRAMES := [6, 7, 8, 9]
const DERP_FPS := 6.0
const CELL_PX := Vector2(8, 8)
const ATLAS_PX := Vector2(64, 128)
const COLS := 3


## Shows `expression` (a CELLS key or a cell index) on a blocky hunter node.
## Returns false when the model has no Face quad.
static func set_expression(model: Node, expression: Variant) -> bool:
	var face := model.find_child("Face", true, false) as MeshInstance3D
	if face == null or face.mesh == null:
		return false
	var cell: int = CELLS.get(expression, 0) if expression is String else int(expression)
	var material := face.get_surface_override_material(0) as StandardMaterial3D
	if material == null:
		var source := face.get_active_material(0) as StandardMaterial3D
		if source == null:
			return false
		# Own copy: ModelSlot shares one material per source across every instance.
		material = source.duplicate() as StandardMaterial3D
		face.set_surface_override_material(0, material)
	if face.has_meta("blocky_tween"):
		var old := face.get_meta("blocky_tween") as Tween
		if old != null and old.is_valid():
			old.kill()
		face.remove_meta("blocky_tween")
	if cell == DERP_FRAMES[0] and face.is_inside_tree():
		var tween := face.create_tween().set_loops()
		for frame in DERP_FRAMES:
			tween.tween_callback(BlockyFace._show_cell.bind(material, frame))
			tween.tween_interval(1.0 / DERP_FPS)
		face.set_meta("blocky_tween", tween)
	else:
		_show_cell(material, cell)
	return true


static func _show_cell(material: StandardMaterial3D, cell: int) -> void:
	material.uv1_offset = Vector3(
		float(cell % COLS) * CELL_PX.x / ATLAS_PX.x,
		float(cell / COLS) * CELL_PX.y / ATLAS_PX.y, 0.0)
