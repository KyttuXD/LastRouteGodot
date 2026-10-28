extends Node

## Held-tool captures (first person on the real player, third person on a remote body built by the real remote-hand code): one PNG per item, plus
## an axe swing sequence. Windowed, so run it on the mini:
##   mini-run.sh <dir> props-lane --scene res://tools/look/held_items.tscn -- /tmp/held_caps/after
## The same script runs on older checkouts for the "before" shots (it only uses calls that exist there).

const ITEMS := ["rescue_axe", "crowbar", "flashlight", "taser", "lockpick", "battery"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/held_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = (load("res://scenes/main_3d.tscn") as PackedScene).instantiate()
	add_child(scene)
	for _i in 20:
		await get_tree().process_frame
	var player: PlayerController3D = scene.player
	var capture_fill := OmniLight3D.new()    # capture-only fill light so the hands and items read in the dark spawn hall
	capture_fill.light_energy = 2.0
	capture_fill.omni_range = 3.0
	capture_fill.position = Vector3(.3, .2, -.2)
	player.active_camera().add_child(capture_fill)
	if player.has_method("set_first_person_hands"):
		player.set_first_person_hands(not (args.size() > 1 and args[1] == "nohands"))   # second arg "nohands": items only
	for item_id in ITEMS:
		if item_id != "flashlight":
			player.grant_inventory_item(item_id)
	var first_slot := {}
	for item_id in ITEMS:
		first_slot[item_id] = player.inventory_order.find(item_id)
	for item_id in ITEMS:
		player.select_inventory_slot(int(first_slot[item_id]))
		for _i in 12:
			await get_tree().process_frame
		_shot("%s/fp_%s.png" % [out, item_id])
	for item_id in ["rescue_axe", "crowbar"]:
		player.select_inventory_slot(int(first_slot[item_id]))
		for _i in 6:
			await get_tree().process_frame
		player._animate_tool_use(item_id)
		var swing: Dictionary = {}
		for step in 5:
			await get_tree().create_timer(.07).timeout
			_shot("%s/fp_swing_%s_%d.png" % [out, item_id, step])
		for _i in 20:
			await get_tree().process_frame

	# third person: a mannequin built like a remote peer, held item through the real remote-hand code, standing in front of the player's camera
	player.first_person_items.visible = false
	var camera_node := player.active_camera()
	var forward := -camera_node.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var stage := Node3D.new()
	stage.name = "TpStage"
	scene.add_child(stage)
	stage.global_position = Vector3(camera_node.global_position.x, player.global_position.y, camera_node.global_position.z) + forward * 2.6
	var remote := RemotePlayers.new()
	scene.add_child(remote)
	var yaw := atan2(-forward.x, -forward.z)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.2
	stage.add_child(sun)
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 2.2, 0)
	fill.omni_range = 7.0
	fill.light_energy = 2.0
	stage.add_child(fill)
	var id := 91
	for item_id in ITEMS:
		var body: Node3D = ModelSlot.instantiate(RemotePlayers.MODEL)
		stage.add_child(body)
		body.position = Vector3.ZERO
		remote._attach_remote_flashlight(id, body)
		remote._sync_remote_held_item(id, body, item_id)
		ModelSlot.play_if_available(ModelSlot.find_animation_player(body), "idle")
		for view in [["front", PI * .78], ["side", PI * .5]]:
			body.rotation.y = yaw + float(view[1])
			for _i in 6:
				await get_tree().process_frame
			_shot("%s/tp_%s_%s.png" % [out, item_id, view[0]])
		if item_id in ["rescue_axe", "crowbar"] and remote.has_method("play_remote_swing"):
			var anchor := remote._remote_hand_anchors.get(id) as Node3D
			body.rotation.y = yaw + PI * .5
			remote.play_remote_swing(id, anchor, item_id, false)
			for step in 5:
				await get_tree().create_timer(.09).timeout
				_shot("%s/tp_swing_%s_%d.png" % [out, item_id, step])
		body.queue_free()
		remote._remote_held_items.erase(id)
		remote._remote_held_item_ids.erase(id)
		remote._remote_hand_anchors.erase(id)
		await get_tree().process_frame
	print("held_items captures written to %s" % out)
	get_tree().quit()


func _shot(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	if image != null:
		image.save_png(path)
