extends RefCounted

## Headless check for the 2D billboard hunters (see SpriteBillboard).
##
## Every A-Z hunter must resolve to a sprite, the sprite must expose what
## HunterView3D and HunterJumpscare rely on (the usual clip names, a "Head"
## node, a feet-on-the-floor body), and Void hunters must keep their 3D model.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- sprites

const CLIPS := ["idle", "walk", "chase", "charge", "stun", "flight", "jumpscare"]

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	for id in HunterRoster.A_Z_IDS:
		var identity := HunterRoster.get_identity(id)
		if String(identity["sprite_front"]).is_empty() or String(identity["sprite_back"]).is_empty():
			_fail("%s has no sprite paths" % id)
			continue
		var node := ModelSlot.instantiate_hunter(identity)
		if not node is SpriteBillboard:
			_fail("%s did not produce a SpriteBillboard" % id)
			continue
		host.add_child(node)
		var player := ModelSlot.find_animation_player(node)
		if player == null:
			_fail("%s has no AnimationPlayer" % id)
		else:
			for clip in CLIPS:
				if not player.has_animation(clip):
					_fail("%s is missing clip %s" % [id, clip])
		if node.find_child("Head", true, false) == null:
			_fail("%s has no Head node (Kathy's beam hangs there)" % id)
		var body := node.find_child("Body", true, false) as Sprite3D
		if body == null or body.texture == null:
			_fail("%s has no body texture" % id)
		else:
			var height := body.texture.get_height() * body.pixel_size
			if absf(height - SpriteBillboard.BODY_HEIGHT) > .01:
				_fail("%s sprite is %.2f m tall, wanted %.2f" % [id, height, SpriteBillboard.BODY_HEIGHT])
			if body.position.y - height * .5 > .001 or body.position.y - height * .5 < -.001:
				_fail("%s feet are not on the floor" % id)
		node.queue_free()
	var void_node := ModelSlot.instantiate_hunter(HunterRoster.get_identity("void_black"))
	if void_node == null or void_node is SpriteBillboard:
		_fail("void_black should keep its 3D model")
	elif void_node != null:
		void_node.queue_free()
	print("  %d A-Z hunters checked" % HunterRoster.A_Z_IDS.size())
	return _failures
