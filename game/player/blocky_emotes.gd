class_name BlockyEmotes
extends RefCounted

## Per-hunter emotes for the cube ("blocky") hunters in assets/hunters_blocky/.
##
## Each model carries one-shot clips named `emote_<name>`; assets/hunters_blocky/emotes.json lists which ones a hunter
## has (a few shared by everyone, a few personal), with a label and the face to show while it plays.

const TABLE_PATH := "res://assets/hunters_blocky/emotes.json"
static var _table := {}


static func _load() -> void:
	if not _table.is_empty():
		return
	var file := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if parsed is Dictionary:
			_table = parsed


## The emotes of a hunter id: Array of {clip, label, face, shared}. Empty when unknown.
static func emotes_for(hunter_id: String) -> Array:
	_load()
	return _table.get(hunter_id, [])


## Plays `clip` (e.g. "emote_hug") on a blocky hunter and shows its face; afterwards the face goes back to neutral and
## the hunter returns to "idle". Returns false when the model has no such clip.
static func play(model: Node, clip: String, hunter_id: String = "") -> bool:
	var player := ModelSlot.find_animation_player(model)
	if player == null or not player.has_animation(clip):
		return false
	var face := "neutral"
	for entry in emotes_for(hunter_id):
		if entry.get("clip", "") == clip:
			face = String(entry.get("face", "neutral"))
	BlockyFace.set_expression(model, face)
	player.play(clip)
	player.animation_finished.connect(func(_name: StringName) -> void:
		BlockyFace.set_expression(model, "neutral")
		if player.has_animation("idle"):
			player.play("idle"), CONNECT_ONE_SHOT)
	return true
