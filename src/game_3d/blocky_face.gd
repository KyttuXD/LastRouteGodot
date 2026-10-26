class_name BlockyFace
extends RefCounted

## Expression swap for the cube ("blocky") hunters in assets/hunters_blocky/.
##
## Each GLB has a "Face" quad laid over the head's front face. Its UVs point at
## cell 0 of a 3-column grid of 8x8 expression cells under the skin (atlas 64x128),
## so changing expression is a UV offset on the quad's own material.
## Still faces: neutral blink stun chase scream happy blank. Animated faces play from a
## Tween on the Face node: "derp" loops (the iris steps clockwise round each eye),
## "wink_left" / "wink_right" play once and return to neutral. Left/right are the
## character's own left (-X) and right (+X).

const CELLS := {"neutral": 0, "blink": 1, "stun": 2, "chase": 3, "scream": 4, "happy": 5,
	"blank": 10, "wink_right": 11, "wink_left": 12}
## name -> {cells, seconds each, loop}
const ANIMS := {
	"derp": {"cells": [6, 7, 8, 9], "times": [.16, .16, .16, .16], "loop": true},
	"wink_left": {"cells": [12, 0], "times": [.5, 0.0], "loop": false},
	"wink_right": {"cells": [11, 0], "times": [.5, 0.0], "loop": false},
}
const CELL_PX := Vector2(8, 8)
const ATLAS_PX := Vector2(64, 128)
const COLS := 3


## Shows `expression` (a CELLS/ANIMS key or a cell index) on a blocky hunter node.
## Returns false when the model has no Face quad.
static func set_expression(model: Node, expression: Variant) -> bool:
	var face := model.find_child("Face", true, false) as MeshInstance3D
	if face == null or face.mesh == null:
		return false
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
	if expression is String and ANIMS.has(expression) and face.is_inside_tree():
		var anim: Dictionary = ANIMS[expression]
		var tween := face.create_tween()
		if anim["loop"]:
			tween.set_loops()
		for i in anim["cells"].size():
			tween.tween_callback(BlockyFace._show_cell.bind(material, anim["cells"][i]))
			tween.tween_interval(maxf(anim["times"][i], 0.001))
		face.set_meta("blocky_tween", tween)
	else:
		var cell: int
		if expression is String:
			cell = CELLS.get(expression, ANIMS[expression]["cells"][0] if ANIMS.has(expression) else 0)
		else:
			cell = int(expression)
		_show_cell(material, cell)
	return true


static func _show_cell(material: StandardMaterial3D, cell: int) -> void:
	material.uv1_offset = Vector3(
		float(cell % COLS) * CELL_PX.x / ATLAS_PX.x,
		float(cell / COLS) * CELL_PX.y / ATLAS_PX.y, 0.0)
