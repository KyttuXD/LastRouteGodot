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
	var material := own_material(face)
	if material == null:
		return false
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


## The Face quad's PRIVATE material. ModelSlot.share_blocky_materials hands every mesh of a hunter (body, legs, the
## Face quad ...) the SAME shared override material, so an override being present does not mean it is the face's own:
## writing uv1_offset to it shifted the UVs of the whole body on every expression change (garbled legs and torso
## whenever a hunter chased, searched or was stunned). The copy is remembered in meta, and re-made when something
## (a fade, a material restore) put another material on the quad.
static func own_material(face: MeshInstance3D) -> StandardMaterial3D:
	var mine := face.get_meta("blocky_face_material") as StandardMaterial3D if face.has_meta("blocky_face_material") else null
	var current := face.get_surface_override_material(0) as StandardMaterial3D
	if mine != null and current == mine:
		return mine
	var source := current if current != null else face.get_active_material(0) as StandardMaterial3D
	if source == null:
		return null
	var copy := source.duplicate() as StandardMaterial3D
	copy.uv1_offset = Vector3.ZERO
	face.set_surface_override_material(0, copy)
	face.set_meta("blocky_face_material", copy)
	return copy


## True while the Face quad still wears its own material (a view re-applies the expression when it does not).
static func owns_material(face: MeshInstance3D) -> bool:
	return face != null and face.has_meta("blocky_face_material") \
		and face.get_surface_override_material(0) == face.get_meta("blocky_face_material")


static func _show_cell(material: StandardMaterial3D, cell: int) -> void:
	material.uv1_offset = Vector3(
		float(cell % COLS) * CELL_PX.x / ATLAS_PX.x,
		float(cell / COLS) * CELL_PX.y / ATLAS_PX.y, 0.0)
