extends RefCounted

## The player body: PlayerModels points at the blocky wooden mannequin on the hunters' rig, the skin is a mapped nearest-
## filtered 64x64 atlas, every clip the controller asks for exists, the anchors the camera and held items use exist, and
## the older faceted/legacy bodies still load as fallbacks.
##
##   godot --headless --path . res://scenes/validate.tscn -- player_model

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _textures(node: Node, found: Array) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var mesh_node := node as MeshInstance3D
		for surface in mesh_node.mesh.get_surface_count():
			var material := mesh_node.get_active_material(surface) as StandardMaterial3D
			if material != null and material.albedo_texture != null:
				found.append({"texture": material.albedo_texture, "filter": material.texture_filter})
	for child in node.get_children():
		_textures(child, found)


func run(host: Node) -> int:
	_expect(PlayerModels.USE_BLOCKY and PlayerModels.SCENE == PlayerModels.BLOCKY, "the player should wear the blocky mannequin")
	for path in [PlayerModels.BLOCKY, PlayerModels.WOODEN, PlayerModels.LEGACY]:
		_expect(load(path) is PackedScene, "%s does not load (fallback body broken)" % path)
	var body := (load(PlayerModels.SCENE) as PackedScene).instantiate()
	host.add_child(body)
	await host.get_tree().process_frame
	var player := ModelSlot.find_animation_player(body)
	_expect(player != null, "the player body has no AnimationPlayer")
	if player != null:
		for clip in ["idle", "walk", "sprint", "chase", "crouch", "sit", "lay", "stun", "jump", "fall", "climb", "tpose"]:
			_expect(player.has_animation(clip), "player rig lacks clip %s" % clip)
	for anchor in ["L-Eye-Attachment", "R-Eye-Attachment", "R-HandProp"]:
		_expect(body.find_child(anchor, true, false) != null, "player rig lacks %s" % anchor)
	var textures := []
	_textures(body, textures)
	_expect(not textures.is_empty(), "the player body has no skin texture mapped")
	for entry in textures:
		var texture: Texture2D = entry["texture"]
		_expect(texture.get_width() == 64 and texture.get_height() == 64,
			"player skin must be a 64x64 atlas, got %dx%d" % [texture.get_width(), texture.get_height()])
		_expect(int(entry["filter"]) in [BaseMaterial3D.TEXTURE_FILTER_NEAREST, BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS,
			BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS_ANISOTROPIC], "player skin must be nearest-filtered")
	body.queue_free()
	# the controller's camera still aligns to the model's eyes
	var controller := PlayerController3D.new()
	_expect(PlayerController3D.BODY_MODEL_SCENE == PlayerModels.SCENE, "the controller does not use PlayerModels.SCENE")
	controller.free()
	if _failures == 0:
		print("  player    blocky mannequin: 64x64 nearest skin, 12 clips, eye + hand anchors, fallbacks load")
	return _failures
