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

const WANTED := ["idle", "walk", "chase", "sprint", "crouch", "sit", "lay"]

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

	# XR is an optional camera/input layer on the same body, not a second route
	# scene. In a headless/no-runtime test it must exist but fall back silently
	# to the ordinary first-person camera.
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	await _expect_xr(route)
	await _expect_small_hop(route, host)
	await _expect_hard_landing_stun(route, host)
	route.queue_free()
	await host.get_tree().process_frame

	if _failures == 0:
		print("  player    %.2f m tall, %d clips, %d meshes"
			% [bounds.size.y, WANTED.size(),
				model.find_children("*", "MeshInstance3D", true, false).size()])
		print("player OK")
	model.queue_free()
	await host.get_tree().process_frame
	return _failures


## XR hand interactions (XRHands, milestone 4): a flat run builds none of the XR helpers and still aims [E] from the head;
## the climb and swing maths hold; and a gripping hand's pull moves a real ladder climb by exactly that much.
func _expect_xr_hands(controller: PlayerController3D) -> void:
	if controller.xr_hands != null or controller.xr_comfort != null:
		_fail("a flat run built the XR comfort or hand helpers")
	if not controller.interaction_aim().is_equal_approx(controller.active_camera().global_transform):
		_fail("[E] no longer aims from the head on a flat run")
	if not is_equal_approx(XRHands.climb_pull(1.2, 1.0), 0.2) or not is_equal_approx(XRHands.climb_pull(1.0, 1.1), -0.1):
		_fail("pulling a gripping hand down does not climb up by the same distance")
	if not XRHands.is_swing(Vector3(0, 0, .05), 1.0 / 72.0) or XRHands.is_swing(Vector3(0, 0, .01), 1.0 / 72.0):
		_fail("the swing speed threshold is wrong (3.6 m/s must swing, 0.7 m/s must not)")
	var saved_position := controller.global_position
	var saved_rotation := controller.rotation
	var saved_layer := controller.collision_layer
	var saved_mask := controller.collision_mask
	var items_visible := controller.first_person_items.visible
	controller.begin_ladder_climb(saved_position, 3.0, 1.0, saved_rotation.y, saved_position + Vector3(0, 3, -1),
		saved_position + Vector3(0, 0, 1), 0, 0)
	if controller.is_climbing():
		controller.ladder_climb["phase"] = "climb"
		controller.xr_climb_pull(.4)
		controller._update_ladder_climb(1.0 / 60.0)
		var height := float(controller.ladder_climb.get("height", 0.0))
		if not is_equal_approx(height, 1.4):
			_fail("a 0.4 m hand pull moved the climb to %.2f m instead of 1.40 m" % height)
		controller.xr_climb_pull(-5.0)
		controller._update_ladder_climb(1.0 / 60.0)
		if String(controller.ladder_climb.get("phase", "")) != "climb" or float(controller.ladder_climb["height"]) > 0.001:
			_fail("pushing a hand far up does not stop the climb at the foot of the ladder")
	else:
		_fail("the test ladder climb did not start")
	controller.ladder_climb = {}
	controller._show_climb_hands(false)
	controller.global_position = saved_position
	controller.rotation = saved_rotation
	controller.collision_layer = saved_layer
	controller.collision_mask = saved_mask
	controller.first_person_items.visible = items_visible


## XR head follow (XRComfort.follow_head): a headset 0.6 m beside the body pulls the body after it in open space and
## always brings the view back over the body.
func _expect_xr_head_follow(controller: PlayerController3D) -> void:
	var comfort := XRComfort.new()
	comfort.player = controller
	comfort.origin = controller.xr_origin
	comfort.camera = controller.xr_camera
	var start := controller.global_position
	var origin_start := controller.xr_origin.position
	controller.xr_camera.position = Vector3(0.6, 1.4, 0)
	comfort.follow_head(false)
	var offset := controller.xr_camera.global_position - controller.global_position
	if Vector2(offset.x, offset.z).length() > 0.02 or not controller.global_position.is_equal_approx(start):
		_fail("the XR view is not pulled back over a body that must not move (offset %s)" % offset)
	controller.xr_origin.position = origin_start
	controller.global_position = start
	controller.xr_camera.position = Vector3.ZERO
	comfort.free()


func _expect_xr(route: Node) -> void:
	var controller: PlayerController3D = route.player
	if controller.xr_origin == null or controller.xr_camera == null \
			or controller.xr_left == null or controller.xr_right == null:
		_fail("the route player is missing its OpenXR origin/camera/controllers")
		return
	# OpenXR names its controller trackers left_hand / right_hand (a /user/hand/... path never tracks).
	if controller.xr_left.tracker != &"left_hand" or controller.xr_right.tracker != &"right_hand" \
			or controller.xr_left.pose != &"default" or controller.xr_right.pose != &"default":
		_fail("the XR controllers listen to %s/%s %s/%s instead of left_hand/right_hand with the default pose" % [
			controller.xr_left.tracker, controller.xr_left.pose, controller.xr_right.tracker, controller.xr_right.pose])
	if controller.first_person_items == null or controller.flashlight_view == null \
			or controller.taser_view == null:
		_fail("the desktop first-person camera is missing its held equipment view")
	elif controller.first_person_items.get_parent() != controller.first_person_camera:
		_fail("first-person items are not camera-local")
	else:
		var item_meshes := controller.first_person_items.find_children(
			"*", "MeshInstance3D", true, false)
		if item_meshes.size() < 20:
			_fail("the authored equipment views contain only %d visible parts" % item_meshes.size())
		for item_id in PlayerController3D.INVENTORY_ITEMS:
			var view: Node3D = controller.flashlight_view if item_id == "flashlight" \
				else (controller.taser_view if item_id == "taser" \
				else controller.tool_views.get(item_id) as Node3D)
			if view == null or view.find_child("AuthoredToolModel", true, false) == null:
				_fail("%s has no authored first-person GLB" % item_id)
		controller._animate_taser_fire()
		if not controller.taser_view.visible:
			_fail("the taser fire animation never presents the first-person item")
	_expect_player_camera_and_crouch(controller)
	_expect_controller_bindings()
	_expect_keyboard_look(controller)
	_expect_xr_hands(controller)
	_expect_xr_head_follow(controller)
	# A headset without a tracked right / left hand aims [E] and the flashlight with the head.
	controller.xr_active = true
	var head_aim := controller.interaction_aim().is_equal_approx(controller.xr_camera.global_transform)
	var lamp_aim := controller.equipment_aim_direction().is_equal_approx(-controller.xr_camera.global_basis.z.normalized())
	controller.xr_active = false
	if not head_aim or not lamp_aim:
		_fail("without tracked hands the headset does not aim [E] (%s) and the flashlight (%s) from the head" % [head_aim, lamp_aim])
	if controller._flashlight_probe == null:
		_fail("the flashlight has no forward collision probe")
	else:
		if not controller._flashlight_probe.position.is_equal_approx(
				PlayerController3D.FLASHLIGHT_BEAM_LOCAL_POSITION):
			_fail("the flashlight ray does not begin at the held lens")
		if not is_equal_approx(controller._flashlight_probe.target_position.z,
				-PlayerController3D.FLASHLIGHT_MAX_RANGE):
			_fail("the flashlight ray does not cover the beam range")
	# Quality tiers: the flashlight casts shadows on every desktop tier but LOW (QualityTier); judge it per the live tier.
	if PlatformProfile.shadows and not controller.flashlight.shadow_enabled:
		_fail("the flashlight does not cast wall/prop shadows (tier %s keeps shadows)" % PlatformProfile.tier_readout())
	if not PlatformProfile.shadows and controller.flashlight.shadow_enabled:
		_fail("the flashlight casts shadows on tier %s, which drops them" % PlatformProfile.tier_readout())
	var beam_color := controller.flashlight.light_color
	var beam_color_error := maxf(absf(beam_color.r - 1.0), maxf(
		absf(beam_color.g - 1.0), absf(beam_color.b - 1.0)))
	if controller.flashlight.light_energy < 7.0 or beam_color_error > .02:
		_fail("the flashlight is not using the bright neutral-white profile")
	if not controller.flashlight.position.is_equal_approx(
			PlayerController3D.FLASHLIGHT_BEAM_LOCAL_POSITION):
		_fail("the flashlight is behind the held model instead of at its lens")
	for geometry in controller.first_person_items.find_children(
			"*", "GeometryInstance3D", true, false):
		if (geometry as GeometryInstance3D).cast_shadow != \
				GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
			_fail("held first-person item '%s' can block its own light" % geometry.name)
			break
	var world_environment := route.get_node_or_null("WorldEnvironment") as WorldEnvironment
	# The reference look (RefLook) replaces the old near-black flat ambient with a
	# dim plum ambient, fog and glow; the lamps and flashlight do the lighting.
	var environment := world_environment.environment if world_environment != null else null
	if environment == null or environment.ambient_light_energy > 2.5 \
			or environment.ambient_light_color.get_luminance() > .45 \
			or not environment.fog_enabled:
		_fail("the route environment is not using the dark reference-look profile")
	if not InputMap.has_action("taser") or not Settings.REBINDABLE_ACTIONS.has("taser"):
		_fail("taser is missing from the input map or Settings rebinding")
	if not InputMap.has_action("tool_use") or not Settings.REBINDABLE_ACTIONS.has("tool_use"):
		_fail("held-tool use is missing from the input map or Settings rebinding")
	if not InputMap.has_action("inventory") \
			or not Settings.REBINDABLE_ACTIONS.has("inventory"):
		_fail("the inventory menu is missing from the input map or Settings rebinding")
	var inventory_has_tab := false
	for event in InputMap.action_get_events("inventory"):
		if event is InputEventKey and (event.physical_keycode == KEY_TAB \
				or event.keycode == KEY_TAB):
			inventory_has_tab = true
	if not inventory_has_tab:
		_fail("Tab does not open the inventory menu")
	var initial_order := controller.inventory_order_snapshot()
	if not controller.owns_inventory_item("flashlight") \
			or controller.selected_inventory_item() != "flashlight" \
			or controller.flashlight_enabled \
			or initial_order != ["flashlight", "", "", "", ""]:
		_fail("the player does not start with an off flashlight and four blank slots")
	await _expect_flashlight_click_does_not_toggle(controller)
	controller._set_flashlight(true)
	if not controller.flashlight_enabled or not controller.flashlight.visible:
		_fail("the starting flashlight cannot turn its beam on while held")
	for item_id in PlayerController3D.INVENTORY_ITEMS:
		if item_id != "flashlight" and controller.owns_inventory_item(item_id):
			_fail("the route grants %s before the player finds its pickup" % item_id)
	var hud: HUD = route.hud
	if hud == null or hud._inventory_menu_slots.size() != 5 \
			or hud.inventory_is_open():
		_fail("the five-slot inventory menu was not built closed")
	else:
		hud.set_inventory_open(true)
		if not hud.inventory_is_open() or not controller.input_frozen:
			_fail("opening the inventory does not freeze player controls")
		hud.set_inventory_open(false)
	var battery_icon := HUD.ITEM_TEXTURES.get("battery") as Texture2D
	if battery_icon == null or battery_icon.get_size() != Vector2(96, 96) \
			or HUD.ITEM_TEXTURES.has("backpack_small") \
			or HUD.ITEM_TEXTURES.has("backpack_medium") \
			or HUD.ITEM_TEXTURES.has("backpack_large"):
		_fail("battery/backpack HUD icons still expose an atlas or storage upgrade as an item")
	var noclip_origin := controller.global_position
	var hover_position := noclip_origin + Vector3.UP * 2.0
	controller.global_position = hover_position
	controller.input_frozen = true
	controller.set_admin_noclip(true)
	controller._physics_process(.5)
	if not controller.global_position.is_equal_approx(hover_position) \
			or not controller.velocity.is_zero_approx():
		_fail("frozen noclip applied gravity instead of hovering in place")
	controller.input_frozen = false
	controller.global_position = noclip_origin
	controller.set_admin_noclip(false)
	var tool_use_has_left := false
	for event in (ProjectSettings.get_setting("input/tool_use", {}) as Dictionary).get("events", []):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			tool_use_has_left = true
	if not tool_use_has_left:
		_fail("left click does not use/attack with the selected item")
	var interact_has_right := false
	for event in (ProjectSettings.get_setting("input/interact", {}) as Dictionary).get("events", []):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
			interact_has_right = true
	if not interact_has_right:
		_fail("right click does not share the interact action with E")
	if not InputMap.has_action("drop_item") \
			or not Settings.REBINDABLE_ACTIONS.has("drop_item") \
			or not InputMap.has_action("chat") \
			or not Settings.REBINDABLE_ACTIONS.has("chat") \
			or Settings.action_binding_count("chat") < 2:
		_fail("drop/chat actions or their multiple default bindings are missing")
	var drop_uses_q := false
	for event in InputMap.action_get_events("drop_item"):
		if event is InputEventKey \
				and (event as InputEventKey).physical_keycode == KEY_Q:
			drop_uses_q = true
	if not drop_uses_q:
		_fail("Q is not the default drop-held-item key")
	if not Settings.get_action_key_label("chat").contains("/"):
		_fail("Settings does not display multiple bindings for one control")
	if RemotePlayers._sanitize_chat(" hello\nthere ").contains("\n") \
			or RemotePlayers._sanitize_chat("x".repeat(200)).length() \
			> RemotePlayers.MAX_CHAT_LENGTH:
		_fail("room chat does not sanitize line breaks/length")
	controller.taser_cooldown = 3.0
	if not controller.grant_inventory_item("taser") \
			or controller.selected_inventory_item() != "taser" \
			or controller.taser_cooldown != 0.0:
		_fail("granting the taser did not select and restock its inventory slot")
	if controller.flashlight_enabled or controller.flashlight.visible:
		_fail("putting the flashlight away leaves its world beam switched on")
	var shared_state: Dictionary = route._remotes._local_state()
	if String(shared_state.get("selected_item", "")) != "taser":
		_fail("co-op player state does not publish the selected inventory item")
	controller.grant_inventory_item("crowbar")
	if controller.item_durability("flashlight") != roundi(controller.lamp_charge) \
			or int(controller.inventory_durability_snapshot().get("flashlight", -1)) \
			!= roundi(controller.lamp_charge):
		_fail("flashlight charge is not exposed as hotbar durability")
	var selected_before_move := controller.selected_inventory_item()
	controller.move_inventory_slot(controller.selected_inventory_slot, 4)
	var moved_order := controller.inventory_order_snapshot()
	if moved_order[4] != selected_before_move or not String(moved_order[2]).is_empty() \
			or controller.selected_inventory_slot != 4 \
			or controller.selected_inventory_item() != selected_before_move:
		_fail("moving an item into a blank slot did not preserve item selection")
	controller.select_inventory_slot(2)
	if controller.selected_inventory_slot != 2 \
			or not controller.selected_inventory_item().is_empty():
		_fail("blank inventory slots cannot be selected as empty hands")
	controller.select_inventory_slot(4)
	var before := controller.item_durability("crowbar")
	if not controller.consume_item_durability("crowbar") \
			or controller.item_durability("crowbar") != before - 1:
		_fail("a committed crowbar swing did not consume durability")
	if PlayerController3D.FRIENDLY_FIRE_ENABLED:
		_fail("co-op friendly fire is enabled for hand tools")
	if not controller.equip_backpack("backpack_small") \
			or controller.inventory_capacity() != 10 \
			or not controller.equip_backpack("backpack_medium") \
			or controller.inventory_capacity() != 15 \
			or not controller.equip_backpack("backpack_large") \
			or controller.inventory_capacity() != 20 \
			or controller.equip_backpack("backpack_small"):
		_fail("small/medium/large backpacks do not upgrade inventory by 5/10/15")
	var backpack_order := controller.inventory_order_snapshot()
	var capacity_before_extra_pack := controller.inventory_capacity()
	if not controller.collect_backpack("backpack_small") \
			or controller.inventory_capacity() != capacity_before_extra_pack + 5 \
			or controller.inventory_order_snapshot().has("backpack_small") \
			or controller.inventory_order_snapshot().has("backpack_medium") \
			or controller.inventory_order_snapshot().has("backpack_large"):
		_fail("collected backpacks are not cumulative slot-free storage upgrades")
	for index in backpack_order.size():
		if not String(backpack_order[index]).is_empty() \
				and controller.inventory_order_snapshot()[index] != backpack_order[index]:
			_fail("collecting a backpack displaced a physical inventory item")
			break
	var original_crowbar_slot := controller.inventory_order.find("crowbar")
	var original_crowbar_durability := int(
		controller.inventory_slot_durability_snapshot()[original_crowbar_slot])
	if not controller.grant_inventory_item("crowbar", 7):
		_fail("a second copy of an owned inventory item was rejected")
	else:
		var duplicate_slot := controller.selected_inventory_slot
		var duplicate_order := controller.inventory_order_snapshot()
		if duplicate_order.count("crowbar") != 2 \
				or duplicate_slot == original_crowbar_slot \
				or controller.item_durability("crowbar") != 7:
			_fail("duplicate tools do not occupy independent inventory slots")
		controller.consume_item_durability("crowbar")
		var per_slot := controller.inventory_slot_durability_snapshot()
		if int(per_slot[duplicate_slot]) != 6 \
				or int(per_slot[original_crowbar_slot]) != original_crowbar_durability:
			_fail("using one duplicate changed the other copy's durability")
		for _use_index in 6:
			controller.consume_item_durability("crowbar")
		var after_break_order := controller.inventory_order_snapshot()
		var after_break_durability := controller.inventory_slot_durability_snapshot()
		if after_break_order.count("crowbar") != 1 \
				or not String(after_break_order[duplicate_slot]).is_empty() \
				or int(after_break_durability[duplicate_slot]) != 0:
			_fail("a zero-durability tool remained in the inventory after breaking")
	route._update_hud()
	if hud._inventory_menu_slots.size() != controller.inventory_capacity():
		_fail("inventory UI did not grow to the equipped backpack capacity")
	else:
		var drag_source := hud._inventory_menu_slots[4] as PanelContainer
		var source_icon := drag_source.get_node("Stack/Icon") as TextureRect
		hud._inventory_drag_from = 4
		hud._begin_inventory_drag(drag_source)
		if not hud._inventory_drag_ghost.visible \
				or hud._inventory_drag_icon.texture != source_icon.texture \
				or source_icon.self_modulate.a >= .5:
			_fail("inventory drag does not lift the selected item under the cursor")
		hud._finish_inventory_drag()
		if hud._inventory_drag_ghost.visible or source_icon.self_modulate != Color.WHITE:
			_fail("inventory drag visual does not clear after drop/cancel")
	var drop_result := {"requested": false}
	controller.item_drop_requested.connect(func(item_id: String, durability: int,
			slot: int) -> void:
		drop_result["requested"] = item_id == controller.selected_inventory_item() \
			and durability == controller.item_durability(item_id) \
			and slot == controller.selected_inventory_slot, CONNECT_ONE_SHOT)
	controller.request_drop_selected_item()
	if not bool(drop_result["requested"]):
		_fail("drop input did not publish the held item and remaining durability")
	var outside := controller.global_position
	var inside := outside + Vector3(2.0, 0.0, 1.0)
	controller.enter_hiding(Vector2i(2, 3), inside, outside)
	if not controller.hidden or not controller.global_position.is_equal_approx(inside):
		_fail("entering a locker did not move the player body inside it")
	controller.leave_hiding()
	if controller.hidden or not controller.global_position.is_equal_approx(outside):
		_fail("leaving a locker did not restore the outside position")
	var shared_identity: Dictionary = route._remotes._local_state()
	if String(shared_identity.get("display_name", "")).is_empty() \
			or not shared_identity.has("player_hue"):
		_fail("co-op state does not publish the player nametag/hue identity")


func _expect_flashlight_click_does_not_toggle(controller: PlayerController3D) -> void:
	# Drive the real input path used by a 3D-view focus click (tool_use / left
	# mouse) versus the dedicated flashlight bind (F). A click must not flip
	# the beam or request a floor drop. Pause the node's own physics so only
	# the presses below count, then wait a frame so just_pressed cannot leak
	# from F into the following click.
	if controller.selected_inventory_item() != "flashlight" \
			or controller.flashlight_enabled:
		_fail("flashlight click guard needs the starter lamp selected and off")
		return
	var flashlight_has_left := false
	for event in InputMap.action_get_events("flashlight"):
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			flashlight_has_left = true
	if flashlight_has_left:
		_fail("the dedicated flashlight bind includes left click")
	var drop_count := [0]
	var drop_watch := func(_item_id: String, _durability: int, _slot: int) -> void:
		drop_count[0] += 1
	controller.item_drop_requested.connect(drop_watch)
	controller.set_physics_process(false)
	await _simulate_held_action(controller, "tool_use")
	if controller.flashlight_enabled or not controller.owns_inventory_item("flashlight") \
			or controller.selected_inventory_item() != "flashlight" \
			or drop_count[0] != 0:
		_fail("left click toggled or dropped the flashlight")
	await _simulate_held_action(controller, "flashlight")
	if not controller.flashlight_enabled:
		_fail("the dedicated flashlight bind did not toggle the lamp on")
	await _simulate_held_action(controller, "tool_use")
	if not controller.flashlight_enabled or drop_count[0] != 0 \
			or not controller.owns_inventory_item("flashlight"):
		_fail("left click toggled or dropped the flashlight while it was on")
	await _simulate_held_action(controller, "flashlight")
	if controller.flashlight_enabled:
		_fail("the dedicated flashlight bind did not toggle the lamp off")
	controller.item_drop_requested.disconnect(drop_watch)
	controller._set_flashlight(false)
	controller.set_physics_process(true)


func _simulate_held_action(controller: PlayerController3D, action: StringName) -> void:
	Input.action_release(action)
	await controller.get_tree().process_frame
	Input.action_press(action)
	controller._physics_process(1.0 / 60.0)
	Input.action_release(action)
	await controller.get_tree().process_frame


func _expect_player_camera_and_crouch(controller: PlayerController3D) -> void:
	var eye_heights: Array[float] = []
	for eye_name in ["L-Eye-Attachment", "R-Eye-Attachment"]:
		var eye := controller._body_model.find_child(eye_name, true, false) as Node3D
		if eye != null:
			eye_heights.append(controller.body_visual.to_local(eye.global_position).y)
	if eye_heights.size() != 2:
		_fail("the player model is missing authored left/right eye attachments")
	else:
		var eye_height := (eye_heights[0] + eye_heights[1]) * .5
		if absf(controller._standing_camera_height - eye_height) > .005 \
				or absf(controller.first_person_pivot.position.y - eye_height) > .005:
			_fail("the first-person camera does not match the player model's eyes")

	var capsule := controller.player_collision.shape as CapsuleShape3D
	if capsule == null:
		_fail("the player controller is missing its capsule hitbox")
		return
	controller._update_crouch_hitbox(true)
	controller._update_camera_pose(1.0, false, false, true)
	if not controller._crouched_physical \
			or not is_equal_approx(capsule.height,
				PlayerController3D.CROUCH_COLLISION_HEIGHT) \
			or not is_equal_approx(controller.player_collision.position.y,
				PlayerController3D.CROUCH_COLLISION_CENTER_Y):
		_fail("crouching does not lower the player's physical hitbox")
	if controller.first_person_pivot.position.y >= controller._standing_camera_height * .8:
		_fail("crouching does not lower the first-person point of view")
	if controller.first_person_pivot.position.y >= capsule.height:
		_fail("the crouched camera rises above its shortened physical hitbox")
	controller.admin_noclip = true
	controller._update_crouch_hitbox(false)
	controller.admin_noclip = false
	controller._update_camera_pose(1.0, false, false, false)
	if controller._crouched_physical \
			or not is_equal_approx(capsule.height,
				PlayerController3D.STANDING_COLLISION_HEIGHT) \
			or not is_equal_approx(controller.player_collision.position.y,
				PlayerController3D.STANDING_COLLISION_CENTER_Y):
		_fail("standing does not restore the player's full hitbox")
	controller._bob_phase = 0.0
	controller._update_camera_pose(.1, true, false, false)
	if is_zero_approx(controller.first_person_pivot.position.x) \
			and is_equal_approx(controller.first_person_pivot.position.y,
				controller._standing_camera_height):
		_fail("grounded movement does not apply player camera bob")
	controller._update_camera_pose(1.0, false, false, false)
	print("  camera    eye-aligned POV; crouch lowers camera and %.2fm hitbox; bob active"
		% PlayerController3D.CROUCH_COLLISION_HEIGHT)


func _expect_controller_bindings() -> void:
	var wanted_buttons := {
		"jump": JOY_BUTTON_A,
		"crouch": JOY_BUTTON_B,
		"interact": JOY_BUTTON_X,
		"inventory": JOY_BUTTON_Y,
		"pause": JOY_BUTTON_START,
		"sprint": JOY_BUTTON_LEFT_STICK,
		"flashlight": JOY_BUTTON_RIGHT_SHOULDER,
		"taser": JOY_BUTTON_LEFT_SHOULDER,
	}
	for action in wanted_buttons:
		var found := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton \
					and event.button_index == int(wanted_buttons[action]):
				found = true
				break
		if not found:
			_fail("controller action '%s' is missing its default gamepad button" % action)
	for action in ["move_left", "move_right", "move_up", "move_down",
			"look_left", "look_right", "look_up", "look_down", "tool_use"]:
		var has_axis := false
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadMotion:
				has_axis = true
				break
		if not has_axis:
			_fail("controller action '%s' has no analog-axis binding" % action)

	# Loading or rebinding keyboard controls must never erase the fixed gamepad
	# layer. Exercise the same helper Settings uses without touching a real save.
	var action := &"__validate_controller_binding_preservation"
	InputMap.add_action(action)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_K
	InputMap.action_add_event(action, key)
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	InputMap.action_add_event(action, button)
	Settings._erase_keyboard_mouse_bindings(action)
	if InputMap.action_get_events(action).size() != 1 \
			or not InputMap.action_get_events(action)[0] is InputEventJoypadButton:
		_fail("keyboard rebinding erased the controller binding")
	InputMap.erase_action(action)
	print("  gamepad   twin-stick look/move, face controls, shoulders, trigger and D-pad")


func _action_has_physical_key(action: String, keycode: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			if key.physical_keycode == keycode or key.keycode == keycode:
				return true
	return false


func _expect_keyboard_look(controller: PlayerController3D) -> void:
	var wanted_keys := {
		"look_left": [KEY_J, KEY_LEFT],
		"look_right": [KEY_L, KEY_RIGHT],
		"look_up": [KEY_I, KEY_UP],
		"look_down": [KEY_K, KEY_DOWN],
	}
	for action in wanted_keys:
		if not InputMap.has_action(action) \
				or not Settings.REBINDABLE_ACTIONS.has(action):
			_fail("keyboard look action '%s' is missing from the input map or Settings rebinding" % action)
			continue
		for keycode in wanted_keys[action]:
			if not _action_has_physical_key(action, keycode):
				_fail("look action '%s' is missing its default key" % action)
	if not _action_has_physical_key("move_left", KEY_A) \
			or not _action_has_physical_key("move_right", KEY_D) \
			or not _action_has_physical_key("move_up", KEY_W) \
			or not _action_has_physical_key("move_down", KEY_S):
		_fail("WASD walk bindings were removed while adding keyboard look")
	if _action_has_physical_key("move_left", KEY_J) \
			or _action_has_physical_key("move_right", KEY_L) \
			or _action_has_physical_key("move_up", KEY_I) \
			or _action_has_physical_key("move_down", KEY_K):
		_fail("keyboard look stole WASD walk")
	if not InputMap.has_action("ui_left") \
			or not _action_has_physical_key("ui_left", KEY_LEFT) \
			or not _action_has_physical_key("ui_right", KEY_RIGHT) \
			or not _action_has_physical_key("ui_up", KEY_UP) \
			or not _action_has_physical_key("ui_down", KEY_DOWN):
		_fail("arrow keys no longer navigate menus through ui_left/ui_right")

	controller.input_frozen = false
	controller.look_frozen = false
	controller.xr_active = false
	controller._yaw = 0.0
	controller._pitch = 0.0
	controller._apply_look_rotation()
	for action in ["look_left", "look_right", "look_up", "look_down",
			"move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(action)

	var start_yaw := controller._yaw
	Input.action_press("look_right")
	if not controller.is_look_input_active():
		_fail("held look keys do not count as look activity")
	controller._physics_process(.25)
	Input.action_release("look_right")
	if controller._yaw >= start_yaw - 0.01:
		_fail("holding look_right did not yaw first-person look")
	if absf(controller.velocity.x) > .01 or absf(controller.velocity.z) > .01:
		_fail("keyboard look translated the player instead of only turning")

	var start_pitch := controller._pitch
	Input.action_press("look_up")
	controller._physics_process(.25)
	Input.action_release("look_up")
	if controller._pitch <= start_pitch + 0.01:
		_fail("holding look_up did not pitch first-person look")

	var facing_before_walk := controller.facing
	Input.action_press("move_up")
	controller._physics_process(.1)
	Input.action_release("move_up")
	var walk_speed := Vector2(controller.velocity.x, controller.velocity.z).length()
	if walk_speed <= .01:
		_fail("WASD walk did not move after keyboard look was added")
	if facing_before_walk.dot(controller.facing) < .98:
		_fail("WASD walk rotated look instead of walking")

	MouseLock.release_all()
	MouseLock.set_gameplay_capture(false)
	var uncaptured_yaw := controller._yaw
	var stray := InputEventMouseMotion.new()
	stray.relative = Vector2(80, 0)
	controller._unhandled_input(stray)
	if not is_equal_approx(controller._yaw, uncaptured_yaw):
		_fail("uncaptured mouse motion still aimed the camera")
	Input.action_press("look_left")
	controller._physics_process(.25)
	Input.action_release("look_left")
	# look_left is negative stick X, which increases yaw.
	if controller._yaw <= uncaptured_yaw + 0.01:
		_fail("keyboard look cannot turn when mouse capture is off")

	MouseLock.set_gameplay_capture(true)
	var captured_yaw := controller._yaw
	var captured := InputEventMouseMotion.new()
	captured.relative = Vector2(40, 0)
	controller._unhandled_input(captured)
	if controller._yaw >= captured_yaw:
		_fail("captured mouse look no longer yaws the camera")

	controller.input_frozen = true
	var frozen_yaw := controller._yaw
	Input.action_press("look_right")
	controller._physics_process(.25)
	Input.action_release("look_right")
	if not is_equal_approx(controller._yaw, frozen_yaw):
		_fail("keyboard look still turns while pause/menu input is frozen")
	if controller.is_look_input_active():
		_fail("frozen look input still counts as AFK activity")
	controller.input_frozen = false
	Input.action_release("look_left")
	Input.action_release("look_right")
	Input.action_release("look_up")
	Input.action_release("look_down")
	print("  look      IJKL/arrows turn; WASD still walks; capture-off stays playable")


func _expect_hard_landing_stun(route: Node, host: Node) -> void:
	var controller: PlayerController3D = route.player
	controller.stun_timer = 0.0
	controller.input_frozen = false
	controller.velocity = Vector3.ZERO
	# A normal room-height drop is no longer punished.
	controller.global_position.y += 2.0
	var landed := false
	for _frame in 180:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame
		if controller.is_on_floor():
			landed = true
			break
	if not landed:
		_fail("the safe fall check never landed")
		return
	if controller.stun_timer > 0.0:
		_fail("a 2 m room-height drop incorrectly stunned the player")
	controller.velocity = Vector3.ZERO
	controller.global_position.y += 5.0
	landed = false
	for _frame in 240:
		await host.get_tree().physics_frame
		await host.get_tree().process_frame
		if controller.is_on_floor():
			landed = true
			break
	if not landed:
		_fail("the hard fall check never landed")
		return
	if controller.stun_timer <= 0.0:
		_fail("a full-level hard landing did not stun the player")
	elif controller.stun_timer > GameConfig.PLAYER_FALL_STUN_MAX_SECONDS:
		_fail("fall stun exceeded its configured maximum")
	else:
		print("  fall      2m safe; full-level landing applies %.2fs stun"
			% controller.stun_timer)
	controller.stun_timer = 0.0
	if controller.xr_active:
		_fail("OpenXR activated without an XR export/runtime request")
	if not controller.first_person_camera.current:
		_fail("desktop fallback lost its first-person camera")
	print("  openxr    tracked rig present; no-runtime desktop fallback stays active")


func _expect_small_hop(route: Node, host: Node) -> void:
	var controller: PlayerController3D = route.player
	if not InputMap.has_action("jump") or not Settings.REBINDABLE_ACTIONS.has("jump"):
		_fail("jump is missing from the input map or Settings rebinding")
		return
	var jump_uses_space := false
	var default_jump: Dictionary = ProjectSettings.get_setting("input/jump", {})
	for event in default_jump.get("events", []):
		if event is InputEventKey and event.physical_keycode == KEY_SPACE:
			jump_uses_space = true
	var default_interact: Dictionary = ProjectSettings.get_setting("input/interact", {})
	for event in default_interact.get("events", []):
		if event is InputEventKey and event.physical_keycode == KEY_SPACE:
			_fail("Space still activates interact as well as jump")
	if not jump_uses_space:
		_fail("the default jump binding is not Space")

	Input.action_release("jump")
	for _frame in 45:
		await host.get_tree().physics_frame
		if controller.is_on_floor():
			break
	if not controller.is_on_floor():
		_fail("the route player never settled onto the floor before the hop check")
		return
	var floor_y := controller.global_position.y
	# physics_frame wakes this coroutine inside the physics tick. Injecting an
	# action there is too late for `just_pressed` bookkeeping on some headless
	# backends, so stage synthetic input during the intervening process frame,
	# matching when a real keyboard event reaches the game.
	await host.get_tree().process_frame
	controller.request_jump()
	await host.get_tree().physics_frame
	await host.get_tree().process_frame
	if controller.velocity.y <= 0.0:
		_fail("pressing jump on the floor did not start an upward hop " \
			+ "(floor=%s frozen=%s crouch=%s)" % [
				controller.is_on_floor(), controller.input_frozen,
				Input.is_action_pressed("crouch")])
		return
	var maximum_y := controller.global_position.y

	# A second press while rising must not reset the impulse. This is the
	# grounded-only rule that keeps a small hop from becoming flight.
	var rising_velocity := controller.velocity.y
	await host.get_tree().process_frame
	controller.request_jump()
	await host.get_tree().physics_frame
	await host.get_tree().process_frame
	if controller.velocity.y >= rising_velocity:
		_fail("a second midair jump reset or increased vertical velocity")

	# Freezing input in the air (pause/capture/stun) still applies gravity.
	controller.input_frozen = true
	var before_frozen_gravity := controller.velocity.y
	await host.get_tree().physics_frame
	await host.get_tree().process_frame
	if controller.velocity.y >= before_frozen_gravity:
		_fail("input freeze suspended the player instead of applying gravity")
	controller.input_frozen = false

	var landed := false
	for _frame in 120:
		await host.get_tree().physics_frame
		maximum_y = maxf(maximum_y, controller.global_position.y)
		if controller.is_on_floor():
			landed = true
			break
	var height := maximum_y - floor_y
	if height < 0.24 or height > 0.50:
		_fail("the hop rose %.3f m; expected a restrained 0.24-0.50 m arc" % height)
	if not landed or absf(controller.global_position.y - floor_y) > 0.03:
		_fail("the hop did not return cleanly to its starting floor")

	# Network state already carries a Vector3; guard the vertical component so
	# a future bandwidth cleanup cannot silently flatten jumping peers.
	var state: Dictionary = route._remotes._local_state()
	var published = state.get("at")
	if not published is Vector3 or not is_equal_approx(published.y,
			controller.global_position.y):
		_fail("remote player state dropped the hop's vertical coordinate")
	print("  hop       %.2f m apex, grounded-only, gravity survives input freeze" % height)
