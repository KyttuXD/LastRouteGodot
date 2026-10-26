class_name BlockyFace
extends RefCounted

## Expression swap for the cube ("blocky") hunters in assets/hunters_blocky/.
##
## Each GLB has a "Face" quad laid over the head's front face. Its UVs point at
## cell 0 of a 3x3 grid of 8x8 expression cells (7 used) under the skin (atlas 64x128),
## so changing expression is a UV offset on the quad's own material.

const CELLS := {"neutral": 0, "blink": 1, "stun": 2, "chase": 3, "scream": 4, "happy": 5, "derp": 6}
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
	material.uv1_offset = Vector3(
		float(cell % COLS) * CELL_PX.x / ATLAS_PX.x,
		float(cell / COLS) * CELL_PX.y / ATLAS_PX.y, 0.0)
	return true
