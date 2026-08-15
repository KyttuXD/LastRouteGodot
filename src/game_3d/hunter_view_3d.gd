class_name HunterView3D
extends Node3D

## Thin 3D presentation wrapper around a HunterBrain: reads its grid-space
## `position`/`state` each frame and converts to world space (1 cell = 1
## meter, same convention as facility_view_3d.gd) plus a named animation.
## Which model to show comes from HunterRoster by `brain.hunter_id` — extend
## HunterRoster to add a hunter's model, nothing here needs to change.
##
## Umbriel is the one hunter whose *appearance* changes at runtime: her
## gimmick picks a `disguise_id` on a timer, which is presentation-only (on
## Standard she keeps all her own stats), so it's resolved here rather than in
## the brain.

var brain: HunterBrain

var _animation_player: AnimationPlayer
var _model: Node3D
var _shown_id := ""


func _ready() -> void:
	_apply_model(_desired_model_id())


func _desired_model_id() -> String:
	if brain == null:
		return HunterRoster.DEFAULT_ID
	if brain.gimmick is UmbrielGimmick:
		var disguise: String = brain.gimmick.disguise_id
		if not disguise.is_empty():
			return disguise
	return brain.hunter_id


func _apply_model(model_id: String) -> void:
	if model_id == _shown_id:
		return
	_shown_id = model_id
	if _model:
		_model.queue_free()
		_model = null
		_animation_player = null

	var identity := HunterRoster.get_identity(model_id)
	_model = ModelSlot.instantiate(identity["model_scene"])
	if _model:
		add_child(_model)
		_animation_player = ModelSlot.find_animation_player(_model)


func sync_from_brain() -> void:
	if brain == null:
		return
	position = Vector3(brain.position.x, 0.0, brain.position.y)
	_apply_model(_desired_model_id())
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
