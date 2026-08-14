class_name HunterView3D
extends Node3D

## Thin 3D presentation wrapper around a HunterBrain: reads its grid-space
## `position` each frame and converts to world space (1 cell = 1 meter, same
## convention as facility_view_3d.gd). Placeholder capsule mesh, distinct
## color from the player, until real 3D art exists (see art/props-3d/).

const BODY_COLOR := Color(0.85, 0.18, 0.22)

var brain: HunterBrain

var _mesh_instance: MeshInstance3D


func _ready() -> void:
	var capsule := CapsuleMesh.new()
	capsule.radius = GameConfig.HUNTER_RADIUS
	capsule.height = 1.8
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = capsule
	_mesh_instance.position = Vector3(0, 0.9, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = BODY_COLOR
	material.emission_enabled = true
	material.emission = BODY_COLOR
	material.emission_energy_multiplier = 0.25
	_mesh_instance.material_override = material
	add_child(_mesh_instance)


func sync_from_brain() -> void:
	if brain == null:
		return
	position = Vector3(brain.position.x, 0.0, brain.position.y)
