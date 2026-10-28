extends RefCounted

## Platform profiles (docs/XR_ANDROID.md): a desktop run keeps every reference budget (so desktop behaves exactly as
## before), the phone and Quest profiles shrink them, and the Android phone preset exists next to the Quest one.

var _failures := 0
var _made: Array = []


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	# This run is a desktop headless run: the live profile must be the desktop reference.
	var live := PlatformProfile
	_expect(not live.is_phone and not live.is_quest, "a desktop run reports a phone or Quest profile")
	# Desktops adapt to their tier (QualityTier); a desktop on ULTRA keeps the reference budgets exactly.
	var expected := QualityGovernor.degrade(QualityTier.budgets(live.tier, live.specs), live.notch)
	_expect(live.lamp_pool == int(expected["lamp_pool"]) and live.camera_far == float(expected["camera_far"])
		and live.default_pixel_effect_percent < 0.0, "the desktop profile does not match its tier: %s" % live.summary())
	if live.tier == QualityTier.Tier.ULTRA and live.notch == 0:
		_expect(live.lamp_pool == 8 and live.camera_far == 0.0 and live.prebuild_linked_levels,
			"an ULTRA desktop changed a reference budget: %s" % live.summary())
	# The other profiles, built from a fresh instance with the feature checks faked.
	var phone = _profile({"mobile": true})
	_expect(phone.is_phone and phone.lamp_pool < 8 and phone.camera_far > 0.0 and phone.default_pixel_effect_percent == 0.0,
		"the phone profile does not shrink the budgets: %s" % phone.summary())
	var low = _profile({"mobile": true, "lowmem": true})
	_expect(low.low_memory and not low.prebuild_linked_levels, "a low-memory phone still parks linked storeys")
	var quest = _profile({"xr": true, "quest": true})
	_expect(quest.is_quest and not quest.is_phone and quest.camera_far > 0.0 and quest.camera_far <= 80.0 and not quest.prebuild_linked_levels,
		"the Quest profile is wrong: %s" % quest.summary())
	# Export presets: the phone preset (flat, own package) beside the Quest preset (OpenXR).
	var presets := ConfigFile.new()
	_expect(presets.load("res://export_presets.cfg") == OK, "export_presets.cfg does not load")
	var found := {}
	for section in presets.get_sections():
		if not presets.has_section_key(section, "name"):
			continue
		var name := String(presets.get_value(section, "name"))
		var options := "%s.options" % section
		if name == "Android Phone Debug":
			found["phone"] = true
			_expect(String(presets.get_value(section, "platform")) == "Android", "the phone preset is not Android")
			_expect(int(presets.get_value(options, "xr_features/xr_mode", -1)) == 0, "the phone preset enables OpenXR")
			_expect(String(presets.get_value(options, "package/unique_name")) != "org.kyttuslab.lastroute", "the phone preset reuses the Quest package")
		elif name == "iPhone Debug":
			found["iphone"] = true
			_expect(String(presets.get_value(section, "platform")) == "iOS", "the iPhone preset is not iOS")
			_expect(String(presets.get_value(section, "custom_features")).contains("phone"), "the iPhone preset lost the phone feature")
			_expect(String(presets.get_value(options, "application/bundle_identifier")) == "org.kyttuslab.lastroute.phone",
				"the iPhone preset has the wrong bundle id")
		elif name == "Meta Quest OpenXR Debug":
			found["quest"] = true
			_expect(int(presets.get_value(options, "xr_features/xr_mode", -1)) == 1, "the Quest preset lost OpenXR")
	_expect(found.has("phone") and found.has("quest") and found.has("iphone"), "missing mobile presets: %s" % [found.keys()])
	_check_touch_controls(host)
	_check_quit()
	_check_player_release_presets()
	_check_self_update()
	_check_xr_comfort(host)
	await _check_xr_route_panel(host)
	if _failures == 0:
		print("  platform  desktop keeps the reference budgets; phone %s; quest %s" % [phone.summary(), quest.summary()])
	return _failures


## A profile computed as if the given features were present (the real autoload reads OS.has_feature at boot).
func _profile(features: Dictionary):
	var script := load("res://src/autoload/platform_profile.gd") as GDScript
	var profile: Node = script.new()
	profile.set("is_xr", bool(features.get("xr", false)))
	profile.set("is_quest", bool(features.get("quest", false)))
	profile.set("is_phone", bool(features.get("mobile", false)) and not bool(features.get("xr", false)))
	profile.set("low_memory", bool(features.get("lowmem", false)))
	profile.call("apply_budgets")
	_made.append(profile)
	return profile


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for profile in _made:
			if is_instance_valid(profile):
				profile.free()


## The in-route XR panel end to end, headless: a fake route whose player is "in XR" gets its CanvasLayer moved into the
## panel's viewport; the panel shows only while a screen is open, in front of the head; and a laser click on the
## middle of the panel presses the button drawn there.
func _check_xr_route_panel(host: Node) -> void:
	var route := Node.new()
	route.name = "FakeXRRoute"
	host.add_child(route)
	var player := Node3D.new()
	player.set_script(_xr_player_script())
	route.add_child(player)
	var origin := XROrigin3D.new()
	player.add_child(origin)
	var camera := XRCamera3D.new()
	camera.position = Vector3(0, 1.6, 0)
	origin.add_child(camera)
	var left := XRController3D.new()
	var right := XRController3D.new()
	origin.add_child(left)
	origin.add_child(right)
	player.set("xr_origin", origin)
	player.set("xr_camera", camera)
	player.set("xr_left", left)
	player.set("xr_right", right)
	var layer := CanvasLayer.new()
	route.add_child(layer)
	var button := Button.new()
	button.position = Vector2(190, 110)
	button.size = Vector2(100, 50)
	layer.add_child(button)
	var clicks := [0]
	button.pressed.connect(func() -> void: clicks[0] += 1)
	var open := [false]
	var panel := XRRoutePanel.attach(route, player, func() -> bool: return open[0])
	panel._process(0.0)
	_expect(layer.custom_viewport == null, "the XR route panel moved the UI while the player was not in XR")
	player.set("xr_active", true)
	panel._process(0.0)
	_expect(layer.custom_viewport != null, "the XR route panel did not take the route's CanvasLayers once in XR")
	var quad := origin.get_node_or_null("RouteUIPanel") as MeshInstance3D
	_expect(quad != null and not quad.visible, "the XR route panel shows with no screen open")
	open[0] = true
	panel._process(0.0)
	_expect(quad != null and quad.visible and quad.global_position.z < -0.8 and absf(quad.global_position.x) < 0.01,
		"the XR route panel did not open in front of the head (%s)" % [quad.global_position if quad != null else "none"])
	# No tracked controller here, so the head points (XRGaze.pointer_hand): look straight at the panel's middle.
	camera.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, quad.global_position.y, 0))
	panel._process(0.0)
	panel.call("_click", true)
	await host.get_tree().process_frame
	panel.call("_click", false)
	await host.get_tree().process_frame
	_expect(clicks[0] == 1, "a laser click on the XR route panel did not press the button under it (%d)" % clicks[0])
	open[0] = false
	panel._process(0.0)
	_expect(not quad.visible, "the XR route panel stays up after the screen closed")
	route.queue_free()
	await host.get_tree().process_frame
	await _check_xr_keyboard(host)
	await _check_xr_panel_scroll(host)
	await _check_vr_pose_sync(host)
	await _check_no_touch_controllers(host)
	await _check_xr_origin_handover(host)
	_check_xr_canvas_fit()
	_check_death_audio_reset()
	_check_xr_scene_fades(host)


## The headset keyboard shows while a LineEdit has focus, types into it without taking focus, deletes, submits, and
## goes away with the focus.
## In XR Godot skips the window stretch, so the route panel re-anchors screens against 480 x 270 itself: a centred
## 380 x 236 box (the pause menu) and a full-rect screen must land where the stretch would put them.
func _check_xr_canvas_fit() -> void:
	var box := Control.new()
	box.set_anchors_preset(Control.PRESET_CENTER)
	box.offset_left = -190
	box.offset_right = 190
	box.offset_top = -118
	box.offset_bottom = 118
	XRRoutePanel.fit_to_canvas(box, Vector2(480, 270))
	_expect(Rect2(box.offset_left, box.offset_top, box.offset_right - box.offset_left, box.offset_bottom - box.offset_top) \
			== Rect2(50, 17, 380, 236) and box.anchor_left == 0.0 and box.anchor_right == 0.0,
		"the XR panel places a centred 380 x 236 box at %s" % [Rect2(box.offset_left, box.offset_top, box.offset_right - box.offset_left, box.offset_bottom - box.offset_top)])
	box.free()
	var full := Control.new()
	full.set_anchors_preset(Control.PRESET_FULL_RECT)
	XRRoutePanel.fit_to_canvas(full, Vector2(480, 270))
	_expect(full.offset_right == 480.0 and full.offset_bottom == 270.0 and full.offset_left == 0.0,
		"the XR panel does not fit a full-rect screen to 480 x 270")
	full.free()


## KT lost the sound in VR after dying: the run's audio effects (underwater muffle, chase duck) must clear on respawn,
## continue and the return to the hub. And a hand without a grip pose keeps the identity offset.
func _check_death_audio_reset() -> void:
	Sound.set_muffled(true)
	Sound.ambience_duck = 1.0
	Sound.reset_run_effects()
	var bus := AudioServer.get_bus_index("Master")
	var muffled := false
	for index in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) is AudioEffectLowPassFilter and AudioServer.is_bus_effect_enabled(bus, index):
			muffled = true
	_expect(not muffled and Sound.ambience_duck == 0.0, "Sound.reset_run_effects leaves the muffle or the chase duck on")
	_expect(XRHands.grip_offset(null) == Transform3D.IDENTITY, "an XR hand without a grip pose is not left on the controller")


## KT: leaving a route and switching menus flashed heavily in VR. Steps every headset transition (leave route, pause to
## hub, death to menu, menu to menu, entering a route) in a fake XR setup at the Quest's 72 Hz and fails on a frame with
## no XR camera (a bare frame) or a frame-to-frame brightness jump above XR_FADE_MAX_STEP.
const XR_FADE_FRAME := 1.0 / 72.0
const XR_FADE_MAX_STEP := 0.05
const XR_ROUTE_LUMA := 0.35
const XR_MENU_LUMA := 0.12


func _check_xr_scene_fades(host: Node) -> void:
	var tree := host.get_tree()
	var panel := XRMenuPanel.new()
	host.add_child(panel)
	var menu_view := panel.get_node("XRMenuView") as SubViewport
	var menu_fade := panel.get("_fade") as XRFade
	_expect(menu_fade != null and menu_fade.alpha == 0.0, "the XR menu panel has no comfort fade")
	var worst := 0.0
	var bare := 0
	for transition in ["leave route", "pause to hub", "death to menu", "menu to menu", "enter route"]:
		var frames: Array[float] = []
		var route := _fake_xr_route(host, 0.0)
		if transition in ["menu to menu", "enter route"]:
			route.free()
			route = null
			menu_view.use_xr = true
			(panel.get("_origin") as XROrigin3D).current = true
			panel.set("_awaiting_scene", false)
			menu_fade.alpha = 0.0
			menu_fade.fade_to(0.0)
		else:
			menu_view.use_xr = false
		_record_luma(tree, frames, route)
		# fade out on whatever the headset sees (XRFade.change_scene's to_black)
		var leaving := XRFade.active(tree)
		_expect(leaving != null, "%s: no active XR fade before the switch" % transition)
		if leaving == null:
			continue
		leaving.fade_to(1.0)
		for _i in 60:
			leaving.advance(XR_FADE_FRAME)
			_record_luma(tree, frames, route)
			if leaving.is_settled():
				break
		panel.take_view_dark()
		if route != null:
			route.free()   # the scene change frees the route and its camera
			route = null
		for _i in 6:   # the new scene loading
			panel._process(XR_FADE_FRAME)
			menu_fade.advance(XR_FADE_FRAME)
			_record_luma(tree, frames, route)
		panel._on_scene_changed()
		if transition == "enter route":
			route = _fake_xr_route(host, 1.0)   # the route's player enters XR black
			menu_view.use_xr = false
			_record_luma(tree, frames, route)
			(route.get_meta("fade") as XRFade).fade_to(0.0)   # reveal_xr_view after the spawn settles
		for _i in 90:
			if transition != "enter route":
				panel._process(XR_FADE_FRAME)
				menu_fade.advance(XR_FADE_FRAME)
			else:
				(route.get_meta("fade") as XRFade).advance(XR_FADE_FRAME)
			_record_luma(tree, frames, route)
		var end_fade := XRFade.active(tree)
		_expect(end_fade != null and end_fade.alpha == 0.0, "%s: the headset does not fade back in" % transition)
		for i in range(1, frames.size()):
			if frames[i] < 0.0:
				bare += 1
			elif frames[i - 1] >= 0.0:
				worst = maxf(worst, absf(frames[i] - frames[i - 1]))
		_expect(bare == 0, "%s: %d frame(s) with no XR camera (a bare frame in the headset)" % [transition, bare])
		_expect(worst <= XR_FADE_MAX_STEP, "%s: brightness jumps by %.3f in one frame (max %.2f)" % [transition, worst, XR_FADE_MAX_STEP])
		if route != null:
			route.free()
	menu_view.use_xr = false
	panel.free()
	tree.root.use_xr = false


## A route's XR view: its own XR viewport with a current XRCamera3D carrying an XRFade at `start`.
func _fake_xr_route(host: Node, start: float) -> SubViewport:
	var view := SubViewport.new()
	view.use_xr = true
	view.disable_3d = false
	host.add_child(view)
	var origin := XROrigin3D.new()
	view.add_child(origin)
	var camera := XRCamera3D.new()
	origin.add_child(camera)
	camera.current = true
	view.set_meta("fade", XRFade.attach(camera, start))
	return view


## What the eye sees this frame: the active fade over its scene's brightness, or -1 for a frame with no XR camera.
func _record_luma(tree: SceneTree, frames: Array[float], route: Node) -> void:
	var fade := XRFade.active(tree)
	if fade == null:
		frames.append(-1.0)
		return
	var scene_luma := XR_ROUTE_LUMA if route != null and route.is_ancestor_of(fade) else XR_MENU_LUMA
	frames.append((1.0 - fade.alpha) * scene_luma)


func _check_xr_keyboard(host: Node) -> void:
	var layer := CanvasLayer.new()
	host.add_child(layer)
	var field := LineEdit.new()
	field.position = Vector2(100, 40)
	field.size = Vector2(200, 20)
	layer.add_child(field)
	var keyboard := XRKeyboard.new()
	host.add_child(keyboard)
	var submitted := [""]
	field.text_submitted.connect(func(text: String) -> void: submitted[0] = text)
	keyboard._process(0.0)
	_expect(not keyboard.is_open(), "the XR keyboard shows with no text field focused")
	field.grab_focus()
	keyboard._process(0.0)
	_expect(keyboard.is_open(), "the XR keyboard does not open for a focused text field")
	keyboard.type_text("A")
	keyboard.type_text("7")
	keyboard.backspace()
	keyboard.type_text("B")
	keyboard.submit()
	_expect(field.text == "AB" and submitted[0] == "AB" and field.has_focus(),
		"the XR keyboard typed '%s' / submitted '%s' (focus kept: %s)" % [field.text, submitted[0], field.has_focus()])
	field.release_focus()
	keyboard._process(0.0)
	_expect(not keyboard.is_open(), "the XR keyboard stays open after the field lost focus")
	keyboard.queue_free()
	layer.queue_free()
	await host.get_tree().process_frame


## XR panel scrolling (XRPanelScroll): a stick held on either controller scrolls the list in use (here the focused one)
## down and back up, faster with time; a trigger press that stays inside the dead zone is a click, one that moves
## drags the list like a finger.
func _check_xr_panel_scroll(host: Node) -> void:
	var layer := CanvasLayer.new()
	host.add_child(layer)
	var list := ScrollContainer.new()
	list.position = Vector2(40, 40)
	list.size = Vector2(200, 120)
	layer.add_child(list)
	var column := VBoxContainer.new()
	column.custom_minimum_size = Vector2(180, 900)
	list.add_child(column)
	var row := Button.new()
	row.text = "ROW"
	column.add_child(row)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	row.grab_focus()
	var root := host.get_tree().root
	_expect(XRPanelScroll.target_in(root) == list, "the XR panel scroll does not find the list in use")
	var scroll := XRPanelScroll.new()
	scroll.stick(root, [Vector2.ZERO, Vector2(0, -1)], 0.25)   # right stick down
	var first := list.scroll_vertical
	scroll.stick(root, [Vector2.ZERO, Vector2(0, -1)], 0.25)
	var second := list.scroll_vertical - first
	_expect(first > 0 and second > first, "stick down did not scroll the list faster over time (%d then %d)" % [first, second])
	var before := list.scroll_vertical
	scroll.stick(root, [Vector2(0, 1), Vector2.ZERO], 0.25)   # left stick up
	_expect(list.scroll_vertical < before, "the left stick does not scroll back up")
	scroll.stick(root, [Vector2.ZERO, Vector2.ZERO], 0.1)
	scroll.press(root, Vector2(120, 100))
	_expect(not scroll.move(root, Vector2(121, 102)) and not scroll.release(), "a still trigger press is not a click")
	list.scroll_vertical = 100
	scroll.press(root, Vector2(120, 100))
	var dragged := scroll.move(root, Vector2(120, 60))
	var after_drag := list.scroll_vertical
	_expect(dragged and scroll.release() and absi(after_drag - 140) <= 1,
		"dragging up 40 units did not scroll the list down 40 (now %d)" % after_drag)
	layer.queue_free()
	await host.get_tree().process_frame


## VR bodies in co-op (VRPoseSync): a synthetic VR peer's head and hand poses survive the 43-byte packet within a
## couple of millimetres, drive a real mannequin (each arm points at its hand, the head pitches with the head), turn
## the body once the head is turned far, leave a flat peer's body untouched, and stay small per peer.
func _check_vr_pose_sync(host: Node) -> void:
	var head := Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-30.0)), Vector3(0.02, 1.36, -0.05))
	var left := Transform3D(Basis(Vector3.UP, 0.4), Vector3(-0.25, 1.1, -0.45))
	var right := Transform3D(Basis(Vector3.FORWARD, 0.3), Vector3(0.3, 0.75, -0.2))
	var packet := VRPoseSync.encode(head, left, right, VRPoseSync.FLAG_LEFT | VRPoseSync.FLAG_RIGHT)
	_expect(packet.size() == VRPoseSync.PACKET_BYTES and packet.size() * 20 <= 1000,
		"a VR pose packet is %d bytes (%d bytes/s per peer)" % [packet.size(), packet.size() * 20])
	var pose := VRPoseSync.decode(packet)
	_expect(not pose.is_empty(), "a VR pose packet does not decode")
	if pose.is_empty():
		return
	for pair in [[head, "head"], [left, "left"], [right, "right"]]:
		var sent: Transform3D = pair[0]
		var got: Transform3D = pose[pair[1]]
		_expect(sent.origin.distance_to(got.origin) < 0.002
			and absf(sent.basis.get_rotation_quaternion().dot(got.basis.get_rotation_quaternion())) > 0.9999,
			"the VR %s pose does not survive the packet (%s vs %s)" % [pair[1], sent, got])
	_expect(VRPoseSync.decode(PackedByteArray([1, 2, 3])).is_empty() and VRPoseSync.decode(null).is_empty(),
		"a malformed VR packet decodes")
	var turned := VRPoseSync.decode(VRPoseSync.encode(Transform3D(Basis(Vector3.UP, deg_to_rad(90.0)), head.origin),
		left, right, 0))
	_expect(is_equal_approx(rad_to_deg(VRPoseSync.body_follow(turned)), 40.0) and is_zero_approx(VRPoseSync.body_follow(pose)),
		"the body does not follow a head turned 90 degrees by 40 (got %.1f)" % rad_to_deg(VRPoseSync.body_follow(turned)))
	var body := ModelSlot.instantiate(PlayerModels.SCENE)
	var flat := ModelSlot.instantiate(PlayerModels.SCENE)
	_expect(body != null and flat != null, "the runner mannequin did not load")
	if body == null or flat == null:
		return
	for model in [body, flat]:
		model.scale = Vector3.ONE * PlayerModels.SCALE
		model.rotation.y = 0.7
		host.add_child(model)
	await host.get_tree().process_frame
	var flat_arm := (flat.find_child("L-Arm", true, false) as Node3D).global_transform
	VRPoseSync.apply(flat, {})
	_expect(flat_arm.is_equal_approx((flat.find_child("L-Arm", true, false) as Node3D).global_transform),
		"a flat peer's body moved without VR data")
	VRPoseSync.apply(body, pose)
	var yaw := Basis(Vector3.UP, body.global_rotation.y)
	for side in [["L", left], ["R", right]]:
		var arm := body.find_child("%s-Arm" % side[0], true, false) as Node3D
		var hand := body.find_child("%s-Hand" % side[0], true, false) as Node3D
		var target := body.global_position + yaw * (side[1] as Transform3D).origin
		var angle := rad_to_deg((hand.global_position - arm.global_position).angle_to(target - arm.global_position))
		_expect(angle < 4.0, "the remote %s arm points %.1f degrees away from the VR hand" % [side[0], angle])
	var head_node := body.find_child("Head", true, false) as Node3D
	var flat_head := flat.find_child("Head", true, false) as Node3D
	var pitch := rad_to_deg(head_node.global_basis.z.normalized().angle_to(flat_head.global_basis.z.normalized()))
	_expect(absf(pitch - 30.0) < 3.0, "the remote head turned %.1f degrees for a 30 degree head pitch" % pitch)
	body.queue_free()
	flat.queue_free()
	await host.get_tree().process_frame


## Playing without Touch controllers: with no tracked hand the head points (pointer_hand null), dwell clicks a button
## once after XRGaze.DWELL_SECONDS and moving away resets it, and a gamepad's right stick / look keys turn the player.
func _check_no_touch_controllers(host: Node) -> void:
	var left := XRController3D.new()
	var right := XRController3D.new()
	_expect(XRGaze.pointer_hand(left, right) == null, "an untracked controller still points at the panels")
	left.free()
	right.free()
	var layer := CanvasLayer.new()
	host.add_child(layer)
	var button := Button.new()
	button.position = Vector2(100, 60)
	button.size = Vector2(80, 30)
	layer.add_child(button)
	var clicks := [0]
	button.pressed.connect(func() -> void: clicks[0] += 1)
	await host.get_tree().process_frame
	var root := host.get_tree().root
	var centre := Vector2(140, 75)
	var motion := InputEventMouseMotion.new()
	motion.position = root.get_final_transform() * centre
	motion.global_position = motion.position
	Input.parse_input_event(motion)
	await host.get_tree().process_frame
	var gaze := XRGaze.new()
	var fired := 0
	for i in 15:   # 1.5 s of steady gaze in 0.1 s steps
		if gaze.update(root, centre, 0.1):
			fired += 1
	_expect(fired == 1, "a steady gaze on a button clicked %d times (once expected)" % fired)
	_expect(not gaze.update(root, centre + Vector2(30, 0), 0.1) and gaze.progress < 0.1, "moving the gaze does not restart the dwell")
	layer.queue_free()
	Input.action_press("look_right")
	var turn := XRComfort.turn_input(0.2)
	Input.action_release("look_right")
	_expect(is_equal_approx(turn, 1.0) and is_equal_approx(XRComfort.turn_input(-0.7), -0.7),
		"a gamepad / keyboard look does not turn a headset player (%s)" % turn)
	await host.get_tree().process_frame


## Only one XROrigin3D drives the headset: the first in the tree becomes current (the menu panel's). The route's origin
## must take over when it enters XR (PlayerController3D._try_enter_xr) and the panel's must take back the view after.
func _check_xr_origin_handover(host: Node) -> void:
	var menu := XROrigin3D.new()
	var route := XROrigin3D.new()
	route.position = Vector3(22.5, 0, 21.5)
	host.add_child(menu)
	host.add_child(route)
	await host.get_tree().process_frame
	var first_current := menu.current and not route.current
	route.current = true
	var route_drives := route.current and not menu.current \
		and XRServer.world_origin.origin.is_equal_approx(route.global_position)
	menu.current = true
	var menu_back := menu.current and not route.current
	_expect(menu_back and route_drives, "the XR origin hand-over is wrong (route drives %s, menu back %s; first current %s)" % [
		route_drives, menu_back, first_current])
	menu.queue_free()
	route.queue_free()
	await host.get_tree().process_frame


func _xr_player_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar xr_active := false\nvar xr_origin: Node\nvar xr_camera: Node\nvar xr_left: Node\nvar xr_right: Node\n"
	script.reload()
	return script


## Phone / Quest self-update (UpdateManager): the platform picks the right channel, the manifest parser accepts only
## HTTPS or the backend's own files with a real sha256 (and normalises them), a newer commit installs only with a
## higher build number, and the sha256 the download is checked with matches a known digest.
func _check_self_update() -> void:
	var keys := {["android"]: "phone", ["android", "quest", "xr"]: "quest", ["ios"]: "ios", ["web"]: "web",
		["windows", "xr"]: "steamvr", ["windows"]: "windows", ["macos"]: "macos", []: "linux"}
	for features in keys:
		var tags: Array = features
		var key := UpdateManager.platform_key_for(func(name: String) -> bool: return tags.has(name))
		_expect(key == keys[features], "features %s pick the update channel %s, not %s" % [features, key, keys[features]])
	var sha := "a".repeat(64)
	var good := UpdateManager.parse_manifest(JSON.stringify({"update": {"version": "0.0.1.0", "revision": "ABCDEF1234",
		"build": 812, "url": "/api/updates/files/KyttusLab-Android-Debug.apk", "sha256": sha.to_upper()}}),
		"https://lab.test", false)
	_expect(not good.has("error") and good["url"] == "https://lab.test/api/updates/files/KyttusLab-Android-Debug.apk"
		and good["revision"] == "abcdef1234" and good["sha256"] == sha and int(good["build"]) == 812,
		"a valid phone manifest parsed as %s" % [good])
	var cases := {
		"not json": "INVALID UPDATE RESPONSE",
		JSON.stringify({"update": {"url": "http://evil.test/x.apk", "sha256": sha}}): "UNTRUSTED UPDATE RESPONSE",
		JSON.stringify({"update": {"url": "https://lab.test/x.apk", "sha256": "a".repeat(63)}}): "UNTRUSTED UPDATE RESPONSE",
		JSON.stringify({"update": {"url": "http://127.0.0.1/x.apk", "sha256": sha}}): "UNTRUSTED UPDATE RESPONSE",
	}
	for text in cases:
		var parsed := UpdateManager.parse_manifest(String(text), "https://lab.test", false)
		_expect(String(parsed.get("error", "")) == cases[text], "manifest %s parsed as %s" % [text, parsed])
	var newer := "b".repeat(40)
	var installed := "c".repeat(40)
	_expect(UpdateManager.mobile_update_needed(newer, installed, 813, 812), "a newer commit with a higher build does not update")
	_expect(not UpdateManager.mobile_update_needed(newer, installed, 812, 812), "an equal build number would install (Android refuses it)")
	_expect(not UpdateManager.mobile_update_needed(newer, installed, 700, 812), "an older build would install")
	_expect(not UpdateManager.mobile_update_needed(installed, installed, 900, 812), "the same commit would install again")
	_expect(not UpdateManager.mobile_update_needed("not-a-sha", installed, 900, 812), "an invalid revision would install")
	var path := "user://self_update_check.bin"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("abc")
	file.close()
	_expect(FileAccess.get_sha256(path) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
		"the download checksum does not match a known sha256")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Player Release presets (docs/XR_ANDROID.md, "Encrypted player builds"): one per shipped platform, encrypted (PCK and
## directory), feature "player", internal code excluded; every other preset is "internal". No shipped script or scene
## may reference an excluded file, or a player build would fail to load it.
## The macOS template zip a preset exports with (its custom template, else the installed official one) must hold
## macos_template.app/Contents/MacOS/<binary>. A template that is not on this machine is reported, not failed.
func _check_macos_template(preset_name: String, custom: String, binary: String) -> void:
	var path := custom
	if path.is_empty():
		var version := Engine.get_version_info()
		path = OS.get_data_dir().path_join("Godot/export_templates/%d.%d.%d.%s/macos.zip" % [version.major, version.minor,
			version.patch, version.status])
	if not FileAccess.file_exists(path):
		print("NOTE %s: template %s is not on this machine, %s not checked" % [preset_name, path, binary])
		return
	var zip := ZIPReader.new()
	_expect(zip.open(path) == OK, "%s: cannot open its template %s" % [preset_name, path])
	var found := zip.get_files().has("macos_template.app/Contents/MacOS/" + binary)
	zip.close()
	_expect(found, "%s: template %s has no %s, so the export would fail" % [preset_name, path, binary])


func _check_player_release_presets() -> void:
	var presets := ConfigFile.new()
	_expect(presets.load("res://export_presets.cfg") == OK, "export_presets.cfg does not load")
	var player := {}
	var excluded := PackedStringArray()
	for section in presets.get_sections():
		if section.ends_with(".options") or not presets.has_section_key(section, "name"):
			continue
		var name := String(presets.get_value(section, "name"))
		var features := String(presets.get_value(section, "custom_features", "")).split(",")
		if name.ends_with("Player Release"):
			player[name] = true
			_expect(features.has("player") and not features.has("internal"), "%s is not a player-only build" % name)
			_expect(bool(presets.get_value(section, "encrypt_pck", false)) and bool(presets.get_value(section, "encrypt_directory", false)),
				"%s does not encrypt its PCK" % name)
			excluded = String(presets.get_value(section, "exclude_filter", "")).split(",")
			_expect(excluded.size() >= 3, "%s excludes no internal code" % name)
			_expect(int(presets.get_value(section, "script_export_mode", -1)) == 2,
				"%s does not export GDScript as compressed binary tokens (script_export_mode 2)" % name)
		else:
			_expect(features.has("internal"), "%s is not marked internal" % name)
	# Godot's macOS templates (official and our encrypted ones) only ship *.universal binaries, so every macOS preset
	# exports universal and tools/macos/thin_app.sh thins the app to arm64 afterwards (KT: Apple Silicon only).
	# The template each preset uses must really contain the binary it asks for, or the export fails on the mini.
	for section in presets.get_sections():
		if section.ends_with(".options") or String(presets.get_value(section, "platform", "")) != "macOS":
			continue
		var mac_name := String(presets.get_value(section, "name"))
		var arch := String(presets.get_value(section + ".options", "binary_format/architecture", ""))
		_expect(arch == "universal", "%s builds %s (macOS presets export universal; the scripts thin to arm64)" % [mac_name, arch])
		for kind in ["debug", "release"]:
			_check_macos_template(mac_name, String(presets.get_value(section + ".options", "custom_template/" + kind, "")),
				"godot_macos_%s.%s" % [kind, arch])
	for wanted in ["macOS", "Windows", "Linux", "Android Phone", "Meta Quest", "iPhone"]:
		_expect(player.has("%s Player Release" % wanted), "missing the %s Player Release preset" % wanted)
	var offenders := []
	for path in _shipped_sources("res://src") + _shipped_sources("res://scenes"):
		if _excluded(path, excluded):
			continue
		var text := FileAccess.get_file_as_string(path)
		for pattern in excluded:
			var folder := pattern.strip_edges().trim_suffix("*")
			if folder.ends_with("/") and text.contains("res://" + folder) and path != "res://src/look/perf_log.gd":
				offenders.append("%s -> %s" % [path, folder])
	_expect(offenders.is_empty(), "shipped code references excluded files: %s" % [offenders])


func _shipped_sources(dir_path: String) -> Array:
	var found := []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found
	for file in dir.get_files():
		if file.ends_with(".gd") or file.ends_with(".tscn"):
			found.append(dir_path.path_join(file))
	for sub in dir.get_directories():
		found.append_array(_shipped_sources(dir_path.path_join(sub)))
	return found


func _excluded(path: String, patterns: PackedStringArray) -> bool:
	for pattern in patterns:
		if path.trim_prefix("res://").match(pattern.strip_edges()):
			return true
	return false


## QUIT: hidden on iOS and the web, offered elsewhere (this desktop run included), and the quit path saves before it
## leaves.
func _check_quit() -> void:
	_expect(PlatformProfile.can_quit(), "a desktop run lost its QUIT button")
	_expect(not PlatformProfile.quit_allowed(true, false) and not PlatformProfile.quit_allowed(false, true)
		and PlatformProfile.quit_allowed(false, false), "QUIT visibility per platform is wrong")
	var order: Array = []
	var on_saved := func() -> void: order.append("saved")
	PlatformProfile.saves_flushed.connect(on_saved)
	PlatformProfile.quit_app(func() -> void: order.append("quit"))
	PlatformProfile.saves_flushed.disconnect(on_saved)
	_expect(order == ["saved", "quit"], "quitting does not save first: %s" % [order])


## Touch look: a drag across the short side turns LOOK_DEGREES_PER_SHORT_SIDE at speed 1 on any screen (a 2400x1080
## phone and a 1688x780 one give the same angle for the same fraction of the screen); speed, vertical and invert apply;
## acceleration only boosts fast flicks; and the settings round-trip through the settings file.
func _check_touch_look() -> void:
	var full := deg_to_rad(TouchControls.LOOK_DEGREES_PER_SHORT_SIDE)
	for screen in [Vector2(2400, 1080), Vector2(1688, 780)]:
		var short_side: float = minf(screen.x, screen.y)
		var turn := TouchControls.look_turn(Vector2(short_side * .5, short_side * .25), short_side, 1.0, 1.0, false, false, 0.0)
		_expect(is_equal_approx(turn.x, full * .5) and is_equal_approx(turn.y, full * .25),
			"touch look on %s turns %s instead of %s" % [screen, turn, Vector2(full * .5, full * .25)])
	var tuned := TouchControls.look_turn(Vector2(100, 100), 270.0, 2.0, 0.5, true, false, 0.0)
	_expect(is_equal_approx(tuned.x, full * 200.0 / 270.0) and is_equal_approx(tuned.y, -full * 100.0 / 270.0),
		"touch look speed/vertical/invert are wrong: %s" % tuned)
	var slow := TouchControls.look_turn(Vector2(10, 0), 270.0, 1.0, 1.0, false, true, 100.0)
	var flick := TouchControls.look_turn(Vector2(10, 0), 270.0, 1.0, 1.0, false, true, 2000.0)
	_expect(is_equal_approx(slow.x, full * 10.0 / 270.0) and flick.x > slow.x * 1.5 and flick.x <= slow.x * 2.5 + 0.0001,
		"touch look acceleration is wrong (slow %s, flick %s)" % [slow.x, flick.x])
	var saved := [Settings.touch_look_speed, Settings.touch_look_vertical, Settings.touch_look_invert_y,
		Settings.touch_look_smoothing, Settings.touch_look_accel]
	Settings.set_touch_look(1.75, 0.6, true, "high", true)
	var config := ConfigFile.new()
	var loaded := config.load("user://settings.cfg") == OK
	_expect(loaded and is_equal_approx(float(config.get_value("touch", "look_speed", 0.0)), 1.75)
		and is_equal_approx(float(config.get_value("touch", "look_vertical", 0.0)), 0.6)
		and bool(config.get_value("touch", "look_invert_y", false)) and String(config.get_value("touch", "look_smoothing", "")) == "high"
		and bool(config.get_value("touch", "look_accel", false)), "the TOUCH LOOK settings do not save")
	Settings.set_touch_look(saved[0], saved[1], saved[2], saved[3], saved[4])


## XR comfort maths (XRComfort; only built once OpenXR starts, so checked here directly): the world scale makes any
## real height see from 1.60 m, snap turn steps once per push, smooth turn is proportional, and a desktop run built no
## comfort node.
func _check_xr_comfort(host: Node) -> void:
	_expect(is_equal_approx(XRComfort.world_scale_for(1.60), 1.0), "a 1.60 m player is rescaled")
	_expect(is_equal_approx(XRComfort.world_scale_for(1.80), 1.60 / 1.80), "a 1.80 m player is not scaled to 1.60 m")
	_expect(XRComfort.world_scale_for(0.2) <= 1.6 and XRComfort.world_scale_for(5.0) >= 0.6, "silly heights are not clamped")
	var comfort := XRComfort.new()
	var first := comfort.snap_turn(0.9)
	var held := comfort.snap_turn(0.95)
	comfort.snap_turn(0.0)
	var again := comfort.snap_turn(-0.9)
	_expect(is_equal_approx(first, deg_to_rad(-30.0)) and held == 0.0 and is_equal_approx(again, deg_to_rad(30.0)),
		"snap turn is not one latched 30 degree step per push (%s %s %s)" % [first, held, again])
	comfort.free()
	_expect(XRComfort.smooth_turn(0.1, 0.1) == 0.0 and XRComfort.smooth_turn(1.0, 0.5) < XRComfort.smooth_turn(0.5, 0.5),
		"smooth turn ignores the dead zone or is not proportional")
	_expect(host.get_tree().root.find_children("XRComfort", "", true, false).is_empty(), "a desktop run built the XR comfort node")
	# The in-route XR panel moves the route's CanvasLayers into its own viewport, but never TouchControls or a layer that
	# already renders elsewhere.
	var fake_route := Node.new()
	var hud_layer := CanvasLayer.new()
	var elsewhere := CanvasLayer.new()
	var touch := TouchControls.new()
	var target := SubViewport.new()
	var other := SubViewport.new()
	elsewhere.custom_viewport = other
	for node in [hud_layer, elsewhere, touch, target, other]:
		fake_route.add_child(node)
	var moved := XRRoutePanel.retarget_canvas_layers(fake_route, target)
	_expect(moved == 1 and hud_layer.custom_viewport == target and elsewhere.custom_viewport == other and touch.custom_viewport == null,
		"the XR route panel retargets the wrong CanvasLayers (moved %d)" % moved)
	fake_route.free()
	# The XR menu panel: a desktop run has none, and the laser maps onto the panel's UV (top-left 0,0) and misses off it.
	_expect(PlatformProfile.find_children("XRMenuPanel", "", true, false).is_empty(), "a desktop run built the XR menu panel")
	var panel := Transform3D(Basis.IDENTITY, Vector3(0, 1.5, -1.5))
	var centre := XRMenuPanel.panel_uv(Vector3(0, 1.5, 0), Vector3.FORWARD, panel, Vector2(1.6, 0.9))
	var corner := XRMenuPanel.panel_uv(Vector3(-0.79, 1.94, 0), Vector3.FORWARD, panel, Vector2(1.6, 0.9))
	var miss := XRMenuPanel.panel_uv(Vector3(0, 1.5, 0), Vector3.BACK, panel, Vector2(1.6, 0.9))
	_expect(centre.is_equal_approx(Vector2(0.5, 0.5)) and corner.distance_to(Vector2.ZERO) < 0.02 and miss.x < 0.0,
		"the XR menu laser maps wrongly onto the panel (%s %s %s)" % [centre, corner, miss])


## Touch controls build headless with the D-pad by default: every button drives a real Input action and never plays
## the menu blip; each arrow (and each diagonal) maps to the right move actions at full strength; a double tap held on
## an arrow sprints; the stick mode still maps to move_up and sprint; no movement zone overlaps the hotbar or its
## arrows; while the inventory is open it gets every touch; every target is at least MIN_TARGET canvas units.
func _check_touch_controls(host: Node) -> void:
	_expect(FileAccess.get_file_as_string("res://src/autoload/settings.gd").contains('var touch_move := "dpad"'),
		"touch movement does not default to the D-pad")
	var saved_mode := Settings.touch_move
	Settings.touch_move = "dpad"
	var fake_hud := Node.new()
	var fake_script := GDScript.new()
	fake_script.source_code = "extends Node\nvar open := false\nfunc inventory_is_open() -> bool:\n\treturn open\n"
	fake_script.reload()
	fake_hud.set_script(fake_script)
	host.add_child(fake_hud)
	var controls := TouchControls.attach(host, null, fake_hud)
	_expect(controls.button_names().size() >= 10, "only %d touch buttons" % controls.button_names().size())
	var blip := Callable(Sound, "menu_blip")
	for name in controls.button_names():
		var action := controls.action_for(String(name))
		_expect(InputMap.has_action(action), "touch button %s drives a missing action %s" % [name, action])
		var button: Button = controls.get_node("TouchRoot/%s" % name)
		_expect(not button.pressed.is_connected(blip), "touch button %s plays the menu blip (the in-game beeping)" % name)
		_expect(button.size.x >= TouchControls.MIN_TARGET - .5 and button.size.y >= TouchControls.MIN_TARGET - .5,
			"touch target %s is %s" % [name, button.size])
	# Arrows and diagonals from where a finger lands on the pad.
	var cell := TouchControls.PAD_CELL
	var cases := {Vector2(1.5, .5): Vector2(0, -1), Vector2(1.5, 2.5): Vector2(0, 1), Vector2(.5, 1.5): Vector2(-1, 0),
		Vector2(2.5, 1.5): Vector2(1, 0), Vector2(2.5, .5): Vector2(1, -1), Vector2(1.5, 1.5): Vector2.ZERO}
	for at in cases:
		var got := TouchControls.pad_direction(Vector2(at) * cell)
		_expect(got == cases[at], "the D-pad at cell %s gives %s instead of %s" % [at, got, cases[at]])
	var expected := {Vector2(0, -1): "move_up", Vector2(0, 1): "move_down", Vector2(-1, 0): "move_left", Vector2(1, 0): "move_right"}
	for direction in expected:
		controls.set_pad(direction, false)
		for action in ["move_up", "move_down", "move_left", "move_right"]:
			var want: bool = action == String(expected[direction])
			_expect(Input.is_action_pressed(action) == want and (not want or is_equal_approx(Input.get_action_strength(action), 1.0)),
				"the %s arrow sets %s wrongly" % [expected[direction], action])
		_expect(not Input.is_action_pressed("sprint"), "a single press on an arrow sprints")
	controls.set_pad(Vector2(1, -1), false)
	_expect(Input.is_action_pressed("move_up") and Input.is_action_pressed("move_right"), "a D-pad diagonal does not press both arrows")
	controls.set_pad(Vector2.ZERO, false)
	_expect(not Input.is_action_pressed("move_up") and not Input.is_action_pressed("move_right"), "letting go of the D-pad leaves movement pressed")
	# Double tap: tap up, let go, press up again at once -> sprint up until released.
	var pad: Control = controls.get_node("TouchRoot/DPad")
	var up := pad.position + Vector2(1.5, .5) * cell
	controls.call("_pad_press", 0, up)
	_expect(not Input.is_action_pressed("sprint"), "the first tap on an arrow sprints")
	controls.call("_pad_release", 0)
	controls.call("_pad_press", 1, up)
	_expect(Input.is_action_pressed("sprint") and Input.is_action_pressed("move_up"), "a double tap held on an arrow does not sprint")
	controls.call("_pad_release", 1)
	_expect(not Input.is_action_pressed("sprint") and not Input.is_action_pressed("move_up"), "releasing a double-tapped arrow keeps sprinting")
	# No movement zone over the hotbar or its arrows.
	var movement := controls.movement_rect()
	_expect(not movement.intersects(controls.hotbar_rect()), "the D-pad overlaps the hotbar")
	for name in ["TouchPrev", "TouchNext"]:
		var arrow_button: Button = controls.get_node("TouchRoot/%s" % name)
		_expect(not movement.intersects(arrow_button.get_global_rect()), "the D-pad overlaps the hotbar arrow %s" % name)
		_expect(not controls.hotbar_rect().intersects(arrow_button.get_global_rect()), "the hotbar arrow %s covers the hotbar" % name)
	# The inventory gets every touch while it is open.
	fake_hud.set("open", true)
	controls._process(0.0)
	_expect(not pad.visible, "the D-pad stays up over the open inventory")
	for name in controls.button_names():
		var shown: bool = (controls.get_node("TouchRoot/%s" % name) as Button).visible
		_expect(shown == TouchControls.INVENTORY_BUTTONS.has(name), "touch button %s is %s over the open inventory" % [name, "shown" if shown else "hidden"])
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = up
	controls._input(touch)
	_expect(not Input.is_action_pressed("move_up"), "a touch on the D-pad moves while the inventory is open")
	fake_hud.set("open", false)
	controls._process(0.0)
	_expect(pad.visible, "the D-pad does not come back when the inventory closes")
	# The stick mode still works.
	Settings.touch_move = "stick"
	controls._process(0.0)
	_expect(not pad.visible, "the D-pad shows in stick mode")
	controls.call("_set_move", Vector2(0, -0.6))
	_expect(Input.is_action_pressed("move_up") and is_equal_approx(Input.get_action_strength("move_up"), 0.6) and not Input.is_action_pressed("sprint"),
		"the touch stick does not map to move_up at 0.6")
	controls.call("_set_move", Vector2(0, -1.4))
	_expect(Input.is_action_pressed("sprint"), "pushing the stick past the ring does not sprint")
	controls.call("_set_move", Vector2.ZERO)
	_expect(not Input.is_action_pressed("move_up") and not Input.is_action_pressed("sprint"), "releasing the stick leaves movement pressed")
	Settings.touch_move = saved_mode
	_check_touch_look()
	controls.queue_free()
	fake_hud.queue_free()
