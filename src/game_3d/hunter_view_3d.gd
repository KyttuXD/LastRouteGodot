class_name HunterView3D
extends Node3D

## Thin 3D presentation wrapper around a HunterBrain: reads its grid-space
## `position`/`state` each frame and converts to world space (1 cell = 1
## meter, same convention as facility_view_3d.gd) plus a named animation.
## Visual and per-clip animation names come from art/props-3d/characters/ via
## ModelSlot, looked up through HunterRoster by brain.hunter_id — extend
## HunterRoster to add a new hunter's model, nothing here needs to change.

var brain: HunterBrain

var _animation_player: AnimationPlayer


func _ready() -> void:
	var identity := HunterRoster.get_identity(brain.hunter_id) if brain else HunterRoster.get_identity(HunterRoster.DEFAULT_ID)
	var model := ModelSlot.instantiate(identity["model_scene"])
	if model:
		add_child(model)
		_animation_player = ModelSlot.find_animation_player(model)


func sync_from_brain() -> void:
	if brain == null:
		return
	position = Vector3(brain.position.x, 0.0, brain.position.y)
	_update_animation()


## idle/walk/chase — see art/props-3d/README.md's animation convention.
## Investigate/search both read as "walk" (she's purposefully moving toward
## somewhere, just not at chase urgency yet); only an actual sighting-driven
## chase gets the more urgent clip.
func _update_animation() -> void:
	var clip_name := "idle"
	match brain.state:
		HunterBrain.State.CHASE:
			clip_name = "chase"
		HunterBrain.State.WANDER, HunterBrain.State.INVESTIGATE, HunterBrain.State.SEARCH:
			clip_name = "walk"
	ModelSlot.play_if_available(_animation_player, clip_name)
