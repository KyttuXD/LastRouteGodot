class_name HunterAddonTicker
extends Node

## Drives a rig's secondary motion by itself, so add-ons also move in Night Watch, the menus and previews (anything that instances a hunter
## model without a HunterView3D). The mode comes from the model's AnimationPlayer (idle / walk / chase / sprint / emote / pose), the speed from how fast
## the model moves. Runs after the clips (priority 60).

var rig: HunterAddons.Rig
var _player: AnimationPlayer
var _last := Vector3.INF
var _speed := 0.0


func _ready() -> void:
	process_priority = 60
	_player = ModelSlot.find_animation_player(rig.model)


func _process(delta: float) -> void:
	if rig == null or rig.external_tick or delta <= 0.0:
		return
	var model := rig.model
	if model == null or not model.is_inside_tree():
		return
	var at := model.global_position
	if _last != Vector3.INF:
		_speed = lerpf(_speed, at.distance_to(_last) / delta, .3)
	_last = at
	rig.tick(delta, mode_of(_player), _speed)


static func mode_of(player: AnimationPlayer) -> String:
	if player == null:
		return "idle"
	var clip := String(player.assigned_animation)
	if clip.begins_with("nw/") or clip.begins_with("addon/"):
		return "pose"
	if clip.begins_with("emote"):
		return "emote"
	if clip.begins_with("scythe_"):
		clip = clip.trim_prefix("scythe_")
	return clip if not clip.is_empty() else "idle"
