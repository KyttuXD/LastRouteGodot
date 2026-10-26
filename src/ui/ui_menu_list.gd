class_name UiMenuList
extends VBoxContainer

## Night Watch style menu: centred uppercase letter-spaced entries, a red ">>"
## marker hanging left of the selected one, small grey sub-labels, and a
## "select / Enter confirm" hint underneath. Up/Down (and W/S) move the
## selection, Enter or Space confirms; the mouse selects on hover.
##
##   var list := UiMenuList.new()
##   list.add_item(&"play", "PLAY")
##   list.add_item(&"custom", "CUSTOM NIGHT", "BEAT NIGHT 5 TO UNLOCK", false)
##   list.chosen.connect(func(id): ...)

signal chosen(id: StringName)
signal selection_changed(id: StringName)

const HINT_TEXT := "UP / DOWN  select   //   ENTER  confirm"

var _items: Array[Dictionary] = []
var _selected := 0
var _hint: Label


func _init() -> void:
	add_theme_constant_override("separation", 2)
	alignment = BoxContainer.ALIGNMENT_CENTER


## Update a proxied entry (text, enabled, shown) -- the title screen mirrors its real buttons.
func sync_item(index: int, text: String, enabled: bool, shown: bool) -> void:
	var entry := _items[index]
	var button := entry["button"] as Button
	if button.text != text:
		button.text = text
	button.disabled = not enabled
	entry["enabled"] = enabled
	(button.get_parent().get_parent() as Control).visible = shown
	entry["shown"] = shown


func item_count() -> int:
	return _items.size()


func add_item(id: StringName, text: String, sub: String = "", enabled: bool = true) -> Button:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	var line := HBoxContainer.new()
	line.alignment = BoxContainer.ALIGNMENT_CENTER
	line.add_theme_constant_override("separation", 4)
	var marker := Label.new()
	marker.text = ">>"
	marker.add_theme_color_override("font_color", Palette.CRIMSON_EDGE)
	marker.modulate.a = 0.0
	marker.custom_minimum_size = Vector2(14, 0)
	line.add_child(marker)
	var button := Button.new()
	button.theme_type_variation = &"MenuItem"
	button.text = Palette.track(text, 0) if false else text
	button.disabled = not enabled
	button.focus_mode = Control.FOCUS_ALL
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	var index := _items.size()
	button.pressed.connect(func() -> void: chosen.emit(id))
	button.mouse_entered.connect(func() -> void: select_index(index))
	line.add_child(button)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(14, 0)
	line.add_child(spacer)
	row.add_child(line)
	if sub != "":
		var small := Label.new()
		small.text = sub
		small.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		small.add_theme_font_size_override("font_size", 6)
		small.add_theme_color_override("font_color", Palette.MUTED)
		row.add_child(small)
	add_child(row)
	_items.append({"id": id, "button": button, "marker": marker, "enabled": enabled, "shown": true})
	if _items.size() == 1:
		select_index(0)
	return button


## The grey keyboard hint under the list.
func add_hint(text: String = HINT_TEXT) -> Label:
	_hint = Label.new()
	_hint.text = text
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_font_size_override("font_size", 6)
	_hint.add_theme_color_override("font_color", Palette.MUTED)
	add_child(_hint)
	return _hint


func selected_id() -> StringName:
	return _items[_selected]["id"] if not _items.is_empty() else &""


func select_index(index: int) -> void:
	if _items.is_empty():
		return
	_selected = clampi(index, 0, _items.size() - 1)
	for i in _items.size():
		var on := i == _selected
		(_items[i]["marker"] as Label).modulate.a = 1.0 if on else 0.0
		var button := _items[i]["button"] as Button
		button.add_theme_color_override("font_color", Color.WHITE if on else Palette.INK)
	var target := _items[_selected]["button"] as Button
	if is_inside_tree() and not target.disabled:
		target.grab_focus()
	selection_changed.emit(selected_id())


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or _items.is_empty():
		return
	if event.is_action_pressed("ui_down") or event.is_action_pressed("ui_up"):
		var step := 1 if event.is_action_pressed("ui_down") else -1
		var index := _selected
		for _try in _items.size():
			index = posmod(index + step, _items.size())
			if bool(_items[index]["enabled"]) and bool(_items[index].get("shown", true)):
				select_index(index)
				break
		get_viewport().set_input_as_handled()
