extends Node

## One owner for the mouse cursor.
##
## Three things want a say in whether the cursor is captured -- the first-person
## camera, the office seat and its tablet, and any menu on top -- and each used
## to set `Input.mouse_mode` directly. That is unarguable while only one of them
## is talking: open the pause menu from first person and the camera would take
## the cursor straight back on its next frame, leaving a menu you cannot click.
##
## So nothing sets the mode itself any more. Gameplay says whether it WANTS the
## cursor captured, anything that needs a pointer registers a claim by name, and
## the rule here is simply: any claim wins. Claims are keyed so a screen can
## drop its own without knowing who else is holding one.

## Whoever currently needs a visible cursor, by name. A Dictionary rather than
## a counter so a double release cannot leave the cursor stuck.
var _claims := {}
var _gameplay_capture := false


func _ready() -> void:
	# Menus pause the tree; the cursor still has to work.
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_physics_priority = -1000   # the typing guard lets go of held keys before any game script polls Input
	_apply()


## Gameplay's preference. False for a top-down view or a 2D screen, where the
## cursor is the pointer and there is nothing to capture it for.
func set_gameplay_capture(wants: bool) -> void:
	if _gameplay_capture == wants:
		return
	_gameplay_capture = wants
	_apply()


## Claim the cursor for `who` -- a pause menu, the office tablet, the seat.
## Idempotent, so it is safe to call every frame from a state check.
func claim(who: String, wants_cursor: bool) -> void:
	var held := _claims.has(who)
	if held == wants_cursor:
		return
	if wants_cursor:
		_claims[who] = true
	else:
		_claims.erase(who)
	_apply()


## Hand the cursor back unconditionally. Leaving a mode does not tidy up after
## itself -- change_scene_to_file just swaps the tree, so gameplay's capture
## preference outlived the gameplay and the pointer stayed locked to a window
## showing a menu. Whatever is about to run states its own needs.
func release_all() -> void:
	_claims.clear()
	_gameplay_capture = false
	_apply()


func cursor_visible() -> bool:
	return not _claims.is_empty() or not _gameplay_capture


## Whether the view is currently being aimed with the mouse, which is also the
## only time a crosshair means anything.
func is_captured() -> bool:
	return not cursor_visible()


func _apply() -> void:
	var wanted := Input.MOUSE_MODE_VISIBLE if cursor_visible() \
		else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != wanted:
		Input.mouse_mode = wanted
	# Web: the browser only grants pointer lock from a click, so the page re-requests it on mousedown while this is true.
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.lrWantCapture=%s" % ("true" if wanted == Input.MOUSE_MODE_CAPTURED else "false"), true)


## Alt-tabbing away releases the cursor; clicking back in should take it again
## rather than leaving the player looking at a free pointer over a captured
## game. Godot does not restore the mode itself.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN:
		_apply()


# -- typing guard --------------------------------------------------------------
## While a text field (chat, a name, a room code, admin fields) has the keyboard, NO gameplay action fires. Godot registers a
## key's action before any script sees the event (and counts a tap pressed-and-released in one frame as just_pressed), so the
## guard works at the source: while typing, the keyboard / mouse / gamepad-button events of every non-ui_ action are taken
## out of the InputMap, and put back the moment typing ends. Held actions are let go. ui_* actions (which the field itself
## uses) are untouched. One shared check instead of per-action patches. Settings saves the real bindings (true_events).

var _stripped := {}


## True while a LineEdit / TextEdit has keyboard focus in the main viewport.
func typing() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is LineEdit or focused is TextEdit


## The real bindings of `action`, even while the typing guard has them out of the InputMap.
func true_events(action: StringName) -> Array:
	return (_stripped[action] as Array).duplicate() if _stripped.has(action) else InputMap.action_get_events(action)


func _strip_bindings() -> void:
	for action in InputMap.get_actions():
		if String(action).begins_with("ui_") or _stripped.has(action):
			continue
		var events := InputMap.action_get_events(action)
		_stripped[action] = events
		for event in events:
			if event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton:
				InputMap.action_erase_event(action, event)
		if Input.is_action_pressed(action):
			Input.action_release(action)


func _restore_bindings() -> void:
	for action in _stripped:
		if not InputMap.has_action(action):
			continue
		var current := InputMap.action_get_events(action)
		for event in _stripped[action]:
			if not current.has(event):
				InputMap.action_add_event(action, event)
	_stripped.clear()


func _process(_delta: float) -> void:
	_sync_typing_guard()


func _physics_process(_delta: float) -> void:
	_sync_typing_guard()


func _input(_event: InputEvent) -> void:
	_sync_typing_guard()


func _sync_typing_guard() -> void:
	var now := typing()
	if now and _stripped.is_empty():
		_strip_bindings()
	elif not now and not _stripped.is_empty():
		_restore_bindings()
