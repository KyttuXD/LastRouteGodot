class_name XRKeyboard
extends CanvasLayer

## A keyboard for headsets (docs/XR_ANDROID.md). An immersive OpenXR app gets no system keyboard on the Quest, so a
## room code, a name or a chat line could not be typed. Whenever a LineEdit has focus this shows a key grid on the same
## canvas (so it appears on the XR menu or route panel and is clicked with the laser), clear of the field: at the
## bottom, or at the top when the field sits in the lower half. Keys type into the focused field and never take focus.
## Created only by XRMenuPanel, so desktop and phones never have it.

const ROWS := ["1234567890", "QWERTYUIOP", "ASDFGHJKL.", "ZXCVBNM?!-"]
const KEY := Vector2(30, 22)
const GAP := 3.0

var target: LineEdit
var _panel: PanelContainer
var _grid: VBoxContainer
var _lower := false
var _letter_buttons: Array[Button] = []


func _ready() -> void:
	layer = 120
	add_to_group(&"xr_keyboard")
	_panel = PanelContainer.new()
	_panel.name = "XRKeyboardPanel"
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.03, 0.07, 0.94)
	style.border_color = Color(0.6, 0.45, 0.75)
	style.set_border_width_all(1)
	style.set_content_margin_all(4)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	_grid = VBoxContainer.new()
	_grid.add_theme_constant_override("separation", int(GAP))
	_panel.add_child(_grid)
	for row in ROWS:
		var line := _row()
		for character in String(row):
			var key := _key(character, func() -> void: type_text(_cased(character)))
			line.add_child(key)
			if character.to_upper() != character.to_lower():
				_letter_buttons.append(key)
	var bottom := _row()
	bottom.add_child(_key("aA", toggle_case, 1.5))
	bottom.add_child(_key("SPACE", func() -> void: type_text(" "), 4.0))
	bottom.add_child(_key("DEL", backspace, 1.5))
	bottom.add_child(_key("ENTER", submit, 2.0))
	bottom.add_child(_key("DONE", close, 1.5))
	_panel.visible = false


func _row() -> HBoxContainer:
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", int(GAP))
	_grid.add_child(line)
	return line


func _key(label: String, action: Callable, width := 1.0) -> Button:
	var key := Button.new()
	key.text = label
	key.focus_mode = Control.FOCUS_NONE   # the field keeps focus, so the caret stays where the user is typing
	key.custom_minimum_size = Vector2(KEY.x * width + GAP * (width - 1.0), KEY.y)
	key.add_theme_font_size_override("font_size", 9)
	key.pressed.connect(action)
	return key


func _cased(character: String) -> String:
	return character.to_lower() if _lower else character


func _process(_delta: float) -> void:
	var focus := get_viewport().gui_get_focus_owner()
	var field := focus as LineEdit
	if field != null and field.editable and field.is_visible_in_tree():
		if field != target:
			target = field
			_place()
		_panel.visible = true
	elif _panel.visible and (target == null or not is_instance_valid(target) or not target.has_focus()):
		_panel.visible = false
		target = null


## Clear of the field: along the bottom, or along the top when the field is in the lower half.
func _place() -> void:
	var view := get_viewport().get_visible_rect().size
	_panel.reset_size()
	var size := _panel.get_combined_minimum_size()
	var field_rect := target.get_global_rect()
	var y := view.y - size.y - 4.0 if field_rect.get_center().y < view.y * 0.5 else 4.0
	_panel.position = Vector2((view.x - size.x) * 0.5, y)


func is_open() -> bool:
	return _panel.visible


func type_text(text: String) -> void:
	if target == null or not is_instance_valid(target):
		return
	if target.max_length > 0 and target.text.length() >= target.max_length:
		return
	target.insert_text_at_caret(text)
	target.text_changed.emit(target.text)


func backspace() -> void:
	if target == null or not is_instance_valid(target) or target.caret_column <= 0:
		return
	var caret := target.caret_column
	target.delete_text(caret - 1, caret)
	target.text_changed.emit(target.text)


func submit() -> void:
	if target != null and is_instance_valid(target):
		target.text_submitted.emit(target.text)


func toggle_case() -> void:
	_lower = not _lower
	for key in _letter_buttons:
		key.text = key.text.to_lower() if _lower else key.text.to_upper()


func close() -> void:
	if target != null and is_instance_valid(target):
		target.release_focus()
	_panel.visible = false
	target = null
