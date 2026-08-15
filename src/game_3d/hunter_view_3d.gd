class_name HunterView3D
extends Node3D

## Thin 3D presentation wrapper around a HunterBrain: reads its grid-space
## `position` each frame and converts to world space (1 cell = 1 meter, same
## convention as facility_view_3d.gd). Visual is instanced from
## art/props-3d/characters/ via ModelSlot — currently only Dovelle exists,
## so that's the only model this maps yet; extend MODEL_SCENES per hunter id
## as the roster grows (see MIGRATION.md).

const MODEL_SCENES := {
	"dovelle": "res://art/props-3d/characters/dovelle.tscn",
}
const FALLBACK_MODEL_SCENE := "res://art/props-3d/characters/dovelle.tscn"

var brain: HunterBrain
var hunter_id := "dovelle"


func _ready() -> void:
	var scene_path: String = MODEL_SCENES.get(hunter_id, FALLBACK_MODEL_SCENE)
	var model := ModelSlot.instantiate(scene_path)
	if model:
		add_child(model)


func sync_from_brain() -> void:
	if brain == null:
		return
	position = Vector3(brain.position.x, 0.0, brain.position.y)
