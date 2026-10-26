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
		# Sprites are the optional fallback (HunterRoster.USE_SPRITES): the cutout assets and the
		# billboard builder must keep working even while the game shows the blocky models.
		var front := "%s%s-front.png" % [HunterRoster.SPRITE_DIR, id]
		var back := "%s%s-back.png" % [HunterRoster.SPRITE_DIR, id]
		if not ResourceLoader.exists(front) or not ResourceLoader.exists(back):
			_fail("%s has no sprite files" % id)
			continue
		var node: Node3D = SpriteBillboard.create(front, back)
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
	# What the game actually shows: the blocky 3D model for every A-Z and Void hunter (no billboard),
	# unless USE_SPRITES is switched on.
	var shown := []
	shown.append_array(HunterRoster.A_Z_IDS)
	shown.append_array(HunterRoster.VOID_IDS)
	for id in shown:
		var identity := HunterRoster.get_identity(id)
		var presented := ModelSlot.instantiate_hunter(identity)
		if presented == null:
			_fail("%s produced no presentation" % id)
			continue
		if HunterRoster.USE_SPRITES and HunterRoster.A_Z_IDS.has(id):
			if not presented is SpriteBillboard:
				_fail("%s should be a billboard while USE_SPRITES is on" % id)
		else:
			if presented is SpriteBillboard:
				_fail("%s should show its 3D model" % id)
			if HunterRoster.USE_BLOCKY and not String(identity["model_scene"]).begins_with(HunterRoster.BLOCKY_DIR):
				_fail("%s does not use its blocky model: %s" % [id, identity["model_scene"]])
		presented.queue_free()
	print("  %d A-Z hunters checked" % HunterRoster.A_Z_IDS.size())
	return _failures
