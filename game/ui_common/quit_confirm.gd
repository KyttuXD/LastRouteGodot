extends RefCounted

## The "QUIT TO DESKTOP?" question, shared by the hub and (while the hub is skipped) the Last Route menu.
## Load it with `const QuitConfirm := preload("res://game/ui_common/quit_confirm.gd")` and call `QuitConfirm.open(host, on_close)`.
## YES sits on the left, NO (the default, focused, safe answer) on the right; Esc, NO or a click outside the box close it
## through `on_close` (the owner frees the dialog and returns the focus). Esc never quits. YES goes through
## PlatformProfile.quit_app, the only way out of the app (it saves, closes a hosted room and applies a staged update).
## Node names (QuitDialog, QuitBox, QuitChoices, QuitYesButton, QuitNoButton) are looked up by the tests.

## Draw order above every carousel card (card.z_index tops out at 10).
const Z := 50


## Builds the dialog under `host` and returns it. `on_close` is called with no arguments when the question is dismissed.
static func open(host: Control, on_close: Callable) -> Control:
	var dialog := Control.new()
	dialog.name = "QuitDialog"
	dialog.z_index = Z
	dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			on_close.call())
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dialog.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "QuitBox"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Palette.PANEL, Palette.ACCENT_EDGE, 10))
	dialog.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var question := Label.new()
	question.text = "QUIT GAME?" if OS.has_feature("mobile") else "QUIT TO DESKTOP?"
	Palette.style_label(question, Palette.INK, 8)
	box.add_child(question)
	var row := HBoxContainer.new()
	row.name = "QuitChoices"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var yes := _button("QuitYesButton", "YES", func() -> void: PlatformProfile.quit_app())
	var no := _button("QuitNoButton", "NO", on_close)
	row.add_child(yes)
	row.add_child(no)
	# left/right keeps the visual order: YES | NO
	yes.focus_neighbor_right = yes.get_path_to(no)
	no.focus_neighbor_left = no.get_path_to(yes)
	yes.focus_neighbor_left = yes.get_path_to(yes)
	no.focus_neighbor_right = no.get_path_to(no)
	host.add_child(dialog)
	if no.is_inside_tree():
		no.grab_focus()   # a scene change can take it out of the tree first
	return dialog


static func _button(button_name: String, label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	Palette.style_button(button, false, true)
	button.pressed.connect(handler)
	return button
