extends RefCounted

## Held tools and the rescue axe: pose bounds in first person (every FOV and aspect, also pushed back by a wall) and third person, the grip
## placement, the axe's swing (two boards a chop, a quarter of its life, loud, replicated), the free whoosh without a target, and a guest seeing
## the swing. Run with:
##
##   godot --headless --path . res://scenes/validate.tscn -- rescue_axe

const ITEMS := ["flashlight", "taser", "lockpick", "crowbar", "rescue_axe", "battery"]
const ASPECTS := [16.0 / 9.0, 16.0 / 10.0, 4.0 / 3.0, 21.0 / 9.0]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _corners(item_id: String) -> Array[Vector3]:
	var root := ModelSlot.instantiate_prop(String(PlayerController3D.ITEM_MODEL_PATHS[item_id]))
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	if root != null:
		var stack: Array[Node] = [root]
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
				var mesh_node := node as MeshInstance3D
				var local := _local_to(root, mesh_node)
				var box := local * mesh_node.get_aabb()
				low = low.min(box.position)
				high = high.max(box.end)
		root.free()
	var result: Array[Vector3] = []
	if low.x == INF:
		return result
	for x in [low.x, high.x]:
		for y in [low.y, high.y]:
			for z in [low.z, high.z]:
				result.append(Vector3(x, y, z))
	return result


static func _local_to(root: Node3D, node: Node3D) -> Transform3D:
	var transform := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		if current is Node3D:
			transform = (current as Node3D).transform * transform
		current = current.get_parent()
	return transform


func _check_first_person() -> void:
	var fovs := [Settings.MIN_FIELD_OF_VIEW, Settings.DEFAULT_FIELD_OF_VIEW, 90.0, Settings.MAX_FIELD_OF_VIEW]
	for item_id in ITEMS:
		var corners := _corners(item_id)
		_expect(corners.size() == 8, "%s: no model bounds" % item_id)
		if corners.size() != 8:
			continue
		var pose := HeldItemPoses.first_person_transform(item_id)
		var hand := HeldItemPoses.first_person_hand(item_id)
		var top := corners[0]
		for corner in corners:
			if corner.y > top.y:
				top = corner
		var nearest := INF
		var front := 0.0
		for corner in corners:
			var depth := -(hand + pose * corner).z
			nearest = minf(nearest, depth)
			front = maxf(front, depth)
		_expect(nearest >= .12, "%s: a corner is %.3f m from the camera plane (near clipping)" % [item_id, nearest])
		_expect(front <= float(HeldItemPoses.REACH[item_id]) + .001,
			"%s reaches %.2f m ahead of the camera, more than its REACH %.2f" % [item_id, front, HeldItemPoses.REACH[item_id]])
		for fov in fovs:
			for aspect in ASPECTS:
				var half := tan(deg_to_rad(float(fov)) * .5)
				for label in ["tip", "grip"]:
					var point := hand + pose * (top if label == "tip" else (HeldItemPoses.GRIP[item_id] as Vector3))
					var ndc := Vector2(point.x / (-point.z * half * float(aspect)), point.y / (-point.z * half))
					_expect(absf(ndc.x) <= 1.0 and absf(ndc.y) <= 1.0,
						"%s %s is off screen at fov %.0f aspect %.2f (ndc %.2f,%.2f)" % [item_id, label, fov, aspect, ndc.x, ndc.y])
		# a wall close in front: the hand slides back until the whole model is on this side of it
		for wall in [.35, .5, .7, 1.0]:
			var push := PlayerController3D.viewmodel_push_for(wall, float(HeldItemPoses.REACH[item_id]))
			var offset := hand + PlayerController3D.viewmodel_offset(push)
			var deepest := 0.0
			for corner in corners:
				deepest = maxf(deepest, -(offset + pose * corner).z)
			_expect(deepest <= wall - .02, "%s clips a wall %.2f m ahead by %.2f m even after the push-back" % [item_id, wall, deepest - wall + .02])


func _check_third_person() -> void:
	for item_id in ITEMS:
		var scale_amount := float(RemotePlayers.REMOTE_HELD_SCALES.get(item_id, .32))
		var transform := HeldItemPoses.third_person_transform(item_id, scale_amount)
		var grip_at := transform * (HeldItemPoses.GRIP[item_id] as Vector3)
		_expect(grip_at.length() < .001, "%s: the grip is not at the hand (off by %.3f)" % [item_id, grip_at.length()])
		var head := (transform.basis * Vector3.UP).normalized()
		if bool((HeldItemPoses.THIRD_PERSON.get(item_id, {}) as Dictionary).get("upright", false)):
			_expect(head.z >= .45 and head.y >= .5,
				"%s: the head should point up and tipped forward in the hand (got %s)" % [item_id, head])
		else:
			_expect(head.y >= .8, "%s: a small hand item should point forward (got %s)" % [item_id, head])
		var corners := _corners(item_id)
		for corner in corners:
			var world := transform * corner
			_expect(world.length() <= .62, "%s: a vertex is %.2f m from the hand" % [item_id, world.length()])
			_expect(world.z >= -.16, "%s: pokes %.2f m below the hand" % [item_id, -world.z])
	_expect(is_equal_approx(float(RemotePlayers.REMOTE_HELD_SCALES["rescue_axe"]), .29), "the remote axe scale is not .29")


func _in_front(player: PlayerController3D) -> Vector3:
	var forward := -player.active_camera().global_basis.z
	forward.y = 0.0
	return player.global_position + forward.normalized() * 1.0


func _await_swing(host: Node, item_id: String) -> void:
	var swing: Dictionary = HeldItemPoses.SWINGS.get(item_id, {})
	var total := float(swing.get("windup", .1)) + float(swing.get("strike", .1)) + float(swing.get("recover", .2)) + .1
	await host.get_tree().create_timer(total).timeout


## KT: the tool is just "Axe", and rarer than the other world tools (it breaks the sewer's pipes).
func _check_axe_rarity() -> void:
	_expect(PlayerController3D.INVENTORY_LABELS["rescue_axe"] == "AXE", "the axe is labelled %s, not AXE" % PlayerController3D.INVENTORY_LABELS["rescue_axe"])
	var total := 0.0
	for type in StreamedRouteGenerator.PICKUP_TYPES:
		total += float(StreamedRouteGenerator.PICKUP_WEIGHTS[type])
	_expect(is_equal_approx(total, 1.0), "tool pickup weights sum to %.2f" % total)
	var counts := {}
	var rng := SeededRandom.new("AXE-RARITY")
	for _i in 4000:
		var tool := StreamedRouteGenerator.pick_tool(rng)
		counts[tool] = int(counts.get(tool, 0)) + 1
	var axe_share := float(counts.get("rescue_axe", 0)) / 4000.0
	_expect(axe_share > .06 and axe_share < .14, "the axe is %.0f %% of tool pickups (want about 10 %%)" % (axe_share * 100.0))
	for type in ["taser", "lockpick", "crowbar"]:
		_expect(int(counts.get(type, 0)) > int(counts.get("rescue_axe", 0)) * 2, "the %s is not clearly commoner than the axe: %s" % [type, counts])


func run(host: Node) -> int:
	_check_axe_rarity()
	_check_first_person()
	_check_third_person()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	for _i in 3:
		await host.get_tree().process_frame
	var player: PlayerController3D = scene.player
	player.global_position += Vector3(400, 0, 400)
	await host.get_tree().process_frame
	player.grant_inventory_item("rescue_axe")
	player.grant_inventory_item("crowbar")
	var camera := player.active_camera()

	# the axe and the crowbar are held in a hotbar slot with the viewmodel built from the pose table
	var axe_model := (player.tool_views["rescue_axe"] as Node3D).get_node_or_null("AuthoredToolModel") as Node3D
	_expect(axe_model != null and axe_model.transform.is_equal_approx(HeldItemPoses.first_person_transform("rescue_axe")),
		"the first-person axe is not placed from the pose table")

	# a swing with nothing to hit is a free whoosh
	player.select_inventory_slot(player.inventory_order.find("rescue_axe"))
	var durability := player.item_durability("rescue_axe")
	var seq := player.tool_swing_seq
	Sound.reset_test_counters()
	player._use_selected_tool()
	await _await_swing(host, "rescue_axe")
	_expect(player.item_durability("rescue_axe") == durability, "a swing at nothing spent durability")
	_expect(player.tool_swing_seq == seq + 1 and not player.tool_swing_hit, "a swing at nothing should count as one miss for peers")
	_expect(int(Sound.play_counts.get("interaction_fail", 0)) == 0, "a swing at nothing played the deny blip")
	player._physics_process(1.0 / 60.0)
	_expect(player.noise < PlayerController3D.AXE_NOISE, "a swing at nothing was loud")

	# chops: two boards a swing, a quarter of the axe, loud, one swing per counter bump
	var chops := 0
	for round_index in 4:
		var board := RouteInteractable3D.new()
		board.kind = RouteInteractable3D.Kind.BOARDED_PATH
		scene.add_child(board)
		board.global_position = _in_front(player)
		await host.get_tree().process_frame
		var pieces := board.board_pieces_remaining
		if round_index == 0:
			_expect(pieces >= 3, "the test barricade has only %d boards" % pieces)
		var before := player.item_durability("rescue_axe")
		var swings_before := player.tool_swing_seq
		player._swing_busy_until_msec = 0
		player._use_selected_tool()
		await _await_swing(host, "rescue_axe")
		if not player.owns_inventory_item("rescue_axe") and round_index < 3:
			_expect(false, "the axe broke after only %d chops" % (round_index + 1))
			break
		chops += 1
		_expect(board.board_pieces_remaining == maxi(0, pieces - 2), "chop %d broke %d boards, expected 2" % [
			round_index + 1, pieces - board.board_pieces_remaining])
		_expect(player.tool_swing_seq == swings_before + 1 and player.tool_swing_hit, "chop %d was not replicated as a hit" % (round_index + 1))
		if round_index == 0:
			_expect(before - player.item_durability("rescue_axe") == 6, "a chop should cost 6 durability, cost %d" % (
				before - player.item_durability("rescue_axe")))
			player._physics_process(1.0 / 60.0)
			_expect(player.noise >= PlayerController3D.AXE_NOISE, "a chop made no noise hunters can hear (%.1f)" % player.noise)
		board.queue_free()
	_expect(chops == 4 and not player.owns_inventory_item("rescue_axe"), "four chops should use the axe up (owned: %s)" % player.owns_inventory_item("rescue_axe"))

	# the crowbar keeps its one board per pry and one durability
	player.select_inventory_slot(player.inventory_order.find("crowbar"))
	var board2 := RouteInteractable3D.new()
	board2.kind = RouteInteractable3D.Kind.BOARDED_PATH
	scene.add_child(board2)
	board2.global_position = _in_front(player)
	await host.get_tree().process_frame
	var crow_before := player.item_durability("crowbar")
	var crow_pieces := board2.board_pieces_remaining
	player._swing_busy_until_msec = 0
	player._use_selected_tool()
	await _await_swing(host, "crowbar")
	_expect(board2.board_pieces_remaining == crow_pieces - 1 and crow_before - player.item_durability("crowbar") == 1,
		"the crowbar should pry one board for one durability")

	# a guest sees the swing: the counter travels with the movement state and drives one swing on the hand anchor per bump
	var remote := RemotePlayers.new()
	remote.local_player = player
	scene.add_child(remote)
	var state := remote._local_state()
	_expect(state.has("tool_swing_seq") and state.has("tool_swing_item") and state.has("tool_swing_hit"),
		"the movement state does not carry the tool swing")
	var body := Node3D.new()
	scene.add_child(body)
	var anchor := Node3D.new()
	body.add_child(anchor)
	remote._remote_hand_anchors[77] = anchor
	remote._sync_remote_swing(77, body, {"tool_swing_seq": 5, "tool_swing_item": "rescue_axe", "tool_swing_hit": true})
	_expect(not remote._remote_swing_tweens.has(77), "joining mid-game replayed an old swing")
	remote._sync_remote_swing(77, body, {"tool_swing_seq": 6, "tool_swing_item": "rescue_axe", "tool_swing_hit": true})
	_expect(remote._remote_swing_tweens.has(77), "a guest did not play the swing")
	var peak := 0.0
	for _i in 30:
		await host.get_tree().process_frame
		peak = maxf(peak, absf(anchor.rotation.x))
	_expect(peak > .4, "the third-person swing barely moved the hand (peak %.2f rad)" % peak)
	remote._sync_remote_swing(77, body, {"tool_swing_seq": 6, "tool_swing_item": "rescue_axe", "tool_swing_hit": true})
	scene.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  rescue_axe  held poses fit every FOV/aspect and sit on the grip; a chop breaks two boards for 6 durability, is loud and replicates; a miss is free")
	return _failures
