extends RefCounted

## No two actions that are live at the same time share a key, mouse button or gamepad button in the default InputMap (the
## route's gameplay actions; Office mode's actions among themselves). The taser is off Q (Drop keeps Q); a rebind moves the key
## instead of doubling it; an old saved profile with Q on both is repaired.
##
##   godot --headless --path . res://scenes/validate.tscn -- key_conflicts

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _signature(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		return "key:%d" % (key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode)
	if event is InputEventMouseButton:
		return "mouse:%d" % (event as InputEventMouseButton).button_index
	if event is InputEventJoypadButton:
		return "pad:%d" % (event as InputEventJoypadButton).button_index
	return ""


func _check_group(actions: Array, label: String) -> void:
	var owner := {}
	for action in actions:
		if not InputMap.has_action(action):
			continue
		var events: Array = Settings._default_bindings.get(action, []).duplicate()
		for event in InputMap.action_get_events(action):
			if event is InputEventJoypadButton:
				events.append(event)
		for event in events:
			var signature := _signature(event)
			if signature.is_empty():
				continue
			if owner.has(signature) and owner[signature] != action:
				_expect(false, "%s: %s is bound to both %s and %s" % [label, signature, owner[signature], action])
			owner[signature] = action


func run(_host: Node) -> int:
	_check_group(Settings.binding_group("move_left"), "gameplay")
	_check_group(Settings.binding_group("office_left_door"), "office")
	var taser_keys := []
	for event in Settings._default_bindings.get("taser", []):
		if event is InputEventKey:
			taser_keys.append((event as InputEventKey).physical_keycode)
	_expect(not taser_keys.has(KEY_Q), "the taser still defaults to Q")
	_expect(taser_keys.has(KEY_G), "the taser has no dedicated key (expected G)")
	# a rebind moves the key
	var saved_taser := InputMap.action_get_events("taser")
	var saved_drop := InputMap.action_get_events("drop_item")
	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	Settings.set_action_binding("taser", q, true)
	var drop_has_q := false
	for event in InputMap.action_get_events("drop_item"):
		drop_has_q = drop_has_q or (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_Q)
	_expect(not drop_has_q, "rebinding the taser to Q left Q on Drop too")
	# the old-profile repair
	InputMap.action_erase_events("drop_item")
	InputMap.action_add_event("drop_item", q.duplicate())
	InputMap.action_erase_events("taser")
	InputMap.action_add_event("taser", q.duplicate())
	Settings._migrate_taser_off_q()
	var taser_after := []
	for event in InputMap.action_get_events("taser"):
		if event is InputEventKey:
			taser_after.append((event as InputEventKey).physical_keycode)
	_expect(not taser_after.has(KEY_Q) and taser_after.has(KEY_G), "an old profile with Q on both was not repaired: %s" % [taser_after])
	_expect(InputGlyphs.name_of("taser", InputGlyphs.KEYBOARD) == "G", "the taser hint shows %s" % InputGlyphs.name_of("taser", InputGlyphs.KEYBOARD))
	# restore without saving
	InputMap.action_erase_events("taser")
	for event in saved_taser:
		InputMap.action_add_event("taser", event)
	InputMap.action_erase_events("drop_item")
	for event in saved_drop:
		InputMap.action_add_event("drop_item", event)
	Settings._save()
	if _failures == 0:
		print("  keys      no shared keys among live actions; taser on G, Q stays Drop; rebinds move keys; old profiles repaired")
	return _failures
