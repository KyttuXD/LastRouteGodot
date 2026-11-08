class_name ClimbableLadder3D
extends Node3D

## Authored service ladder plus a deliberately simple climb volume. Movement
## stays on PlayerController3D so the same body, gravity and co-op position
## replication continue to own the player.

const MODEL_PATH := "res://assets/interactables/service_ladder.glb"

var climb_height := 1.2
var climb_width := .72
var climb_depth := .72


func _ready() -> void:
	add_to_group("climbable_ladder")
	var model := ModelSlot.instantiate_prop(MODEL_PATH)
	if model:
		model.name = "AuthoredLadderModel"
		model.scale.y = climb_height / 1.44
		add_child(model)
	else:
		push_error("LADDER MODEL MISSING // %s" % MODEL_PATH)


func can_climb(world_position: Vector3) -> bool:
	var local := to_local(world_position)
	return absf(local.x) <= climb_width * .5 \
		and absf(local.z) <= climb_depth * .5 \
		and local.y >= -.12 and local.y <= climb_height + .2


func guide_world_position(world_y: float) -> Vector3:
	var local_y := clampf(to_local(Vector3(0, world_y, 0)).y, 0.0, climb_height)
	return to_global(Vector3(0, local_y, 0))
