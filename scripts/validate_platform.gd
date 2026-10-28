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
	_expect(live.lamp_pool == 8 and live.camera_far == 0.0 and live.prebuild_linked_levels and live.default_pixel_effect_percent < 0.0,
		"the desktop profile changed a reference budget: %s" % live.summary())
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
	right.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, quad.global_position.y, -0.2))
	panel._process(0.0)
	panel.call("_click", true)
	await host.get_tree().process_frame
	panel.call("_click", false)
	await host.get_tree().process_frame
	_expect(clicks[0] == 1, "a laser click on the XR route panel did not press the button under it (%d)" % clicks[0])
	# The right stick scrolls: nothing inside the dead zone, one step past it, then a short wait between steps.
	var wait := XRMenuPanel.scroll_from_stick(0.2, Vector2(240, 135), 0.0, 0.016)
	var stepped := XRMenuPanel.scroll_from_stick(-0.9, Vector2(240, 135), 0.0, 0.016)
	var waiting := XRMenuPanel.scroll_from_stick(-0.9, Vector2(240, 135), stepped, 0.016)
	_expect(wait == 0.0 and is_equal_approx(stepped, XRMenuPanel.SCROLL_STEP_SECONDS) and waiting < stepped and waiting > 0.0,
		"the XR panel stick scroll steps wrongly (%s %s %s)" % [wait, stepped, waiting])
	open[0] = false
	panel._process(0.0)
	_expect(not quad.visible, "the XR route panel stays up after the screen closed")
	route.queue_free()
	await host.get_tree().process_frame


func _xr_player_script() -> GDScript:
	var script := GDScript.new()
	script.source_code = "extends Node3D\nvar xr_active := false\nvar xr_origin: Node\nvar xr_camera: Node\nvar xr_left: Node\nvar xr_right: Node\n"
	script.reload()
	return script


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
	controls.queue_free()
	fake_hud.queue_free()
