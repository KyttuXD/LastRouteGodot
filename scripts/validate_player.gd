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
	_expect_xr(route)
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


func _expect_xr(route: Node) -> void:
	var controller: PlayerController3D = route.player
	if controller.xr_origin == null or controller.xr_camera == null \
			or controller.xr_left == null or controller.xr_right == null:
		_fail("the route player is missing its OpenXR origin/camera/controllers")
		return
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
	if controller._flashlight_probe == null:
		_fail("the flashlight has no forward collision probe")
	else:
		if not controller._flashlight_probe.position.is_equal_approx(
				PlayerController3D.FLASHLIGHT_BEAM_LOCAL_POSITION):
			_fail("the flashlight ray does not begin at the held lens")
		if not is_equal_approx(controller._flashlight_probe.target_position.z,
				-PlayerController3D.FLASHLIGHT_MAX_RANGE):
			_fail("the flashlight ray does not cover the beam range")
	if not controller.flashlight.shadow_enabled:
		_fail("the flashlight does not cast wall/prop shadows")
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
	if world_environment == null or world_environment.environment == null \
			or world_environment.environment.ambient_light_energy > .30:
		_fail("the route environment is not using the darker flashlight-first profile")
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
	_expect_flashlight_click_does_not_toggle(controller)
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
	# the beam or request a floor drop.
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
	Input.action_press("tool_use")
	controller._physics_process(1.0 / 60.0)
	Input.action_release("tool_use")
	if controller.flashlight_enabled or not controller.owns_inventory_item("flashlight") \
			or controller.selected_inventory_item() != "flashlight" \
			or drop_count[0] != 0:
		_fail("left click toggled or dropped the flashlight")
	Input.action_press("flashlight")
	controller._physics_process(1.0 / 60.0)
	Input.action_release("flashlight")
	if not controller.flashlight_enabled:
		_fail("the dedicated flashlight bind did not toggle the lamp on")
	Input.action_press("tool_use")
	controller._physics_process(1.0 / 60.0)
	Input.action_release("tool_use")
	if not controller.flashlight_enabled or drop_count[0] != 0 \
			or not controller.owns_inventory_item("flashlight"):
		_fail("left click toggled or dropped the flashlight while it was on")
	Input.action_press("flashlight")
	controller._physics_process(1.0 / 60.0)
	Input.action_release("flashlight")
	if controller.flashlight_enabled:
		_fail("the dedicated flashlight bind did not toggle the lamp off")
	controller.item_drop_requested.disconnect(drop_watch)
	controller._set_flashlight(false)


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
