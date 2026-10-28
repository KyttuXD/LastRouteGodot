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
		elif name == "Meta Quest OpenXR Debug":
			found["quest"] = true
			_expect(int(presets.get_value(options, "xr_features/xr_mode", -1)) == 1, "the Quest preset lost OpenXR")
	_expect(found.has("phone") and found.has("quest"), "missing Android presets: %s" % [found.keys()])
	_check_touch_controls(host)
	_check_xr_comfort(host)
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


## Touch controls build headless, every button drives a real Input action, the stick maps to move/sprint, and every
## target is at least MIN_TARGET pixels at a small phone's size. Not attached on desktop runs.
func _check_touch_controls(host: Node) -> void:
	var controls := TouchControls.attach(host, null)
	_expect(controls.button_names().size() >= 10, "only %d touch buttons" % controls.button_names().size())
	for name in controls.button_names():
		var action := controls.action_for(String(name))
		_expect(InputMap.has_action(action), "touch button %s drives a missing action %s" % [name, action])
	controls.call("_set_move", Vector2(0, -0.6))
	_expect(Input.is_action_pressed("move_up") and is_equal_approx(Input.get_action_strength("move_up"), 0.6) and not Input.is_action_pressed("sprint"),
		"the touch stick does not map to move_up at 0.6")
	controls.call("_set_move", Vector2(0, -1.4))
	_expect(Input.is_action_pressed("sprint"), "pushing past the ring does not sprint")
	controls.call("_set_move", Vector2.ZERO)
	_expect(not Input.is_action_pressed("move_up") and not Input.is_action_pressed("sprint"), "releasing the stick leaves movement pressed")
	for name in controls.button_names():
		var button: Button = controls.get_node("TouchRoot/%s" % name)
		_expect(button.size.x >= TouchControls.MIN_TARGET - .5 and button.size.y >= TouchControls.MIN_TARGET - .5,
			"touch target %s is %s" % [name, button.size])
	controls.queue_free()
