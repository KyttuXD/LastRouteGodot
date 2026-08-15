extends RefCounted

## Headless check on the shared player mannequin.
##
## The player was a teal capsule for the whole port, so nothing downstream had
## ever been exercised against a real body. Three things have to hold or the
## swap is silently worse than the capsule: the model has to load, it has to
## carry the five clips ModelSlot asks for BY NAME -- has_animation is
## case-sensitive and a miss just returns, leaving a figure frozen mid-run --
## and it has to be roughly a person's height, since the capsule it replaces
## set the collision the world was built around.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- player

const WANTED := ["idle", "walk", "chase", "sprint", "crouch"]

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	var model: Node3D = ModelSlot.instantiate(
		"res://art/props-3d/characters/player.tscn")
	if model == null:
		_fail("the player model would not load")
		return _failures
	host.get_tree().root.add_child(model)
	await host.get_tree().process_frame

	var player := ModelSlot.find_animation_player(model)
	if player == null:
		_fail("the player model carries no AnimationPlayer")
	else:
		for clip in WANTED:
			if not player.has_animation(clip):
				_fail("the player model has no '%s' clip" % clip)

	# Its own bounds, against the 1.7 m capsule it replaces.
	var bounds := AABB()
	var first := true
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		var box := mesh.global_transform * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	# A character model must carry NO collision. The exporter emits a -colonly
	# body per mesh by default, which is right for a building and wrong for a
	# body: 21 static colliders parented to the player and moving with him
	# fight the world's own and shove him through the floor.
	var colliders := model.find_children("*", "StaticBody3D", true, false)
	if not colliders.is_empty():
		_fail("the player model carries %d colliders of its own" % colliders.size())

	if first:
		_fail("the player model has no meshes")
	elif bounds.size.y < 1.4 or bounds.size.y > 2.2:
		_fail("the player stands %.2f m, which is not a person" % bounds.size.y)

	if _failures == 0:
		print("  player    %.2f m tall, %d clips, %d meshes"
			% [bounds.size.y, WANTED.size(),
				model.find_children("*", "MeshInstance3D", true, false).size()])
		print("player OK")
	model.queue_free()
	await host.get_tree().process_frame
	return _failures
