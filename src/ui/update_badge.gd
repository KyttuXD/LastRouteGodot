class_name UpdateBadge
extends CanvasLayer

## The update status, top centre (styled like the old BETA bar): "UPDATE AVAILABLE // DOWNLOADING 42%" ->
## "UPDATE READY // RESTART TO APPLY". The download runs in the background while the player is in menus or playing; nothing
## interrupts a run. Clicking the badge opens a popup with RESTART NOW (phones: INSTALL) or LATER; otherwise the update is
## applied when the game quits. In a run the text goes into the HUD's status bar instead. Created by UpdateManager.

var _button: Button
var _popup: PanelContainer
var _popup_text: Label
var _restart: Button


func _ready() -> void:
	name = "UpdateBadge"
	layer = 110
	process_mode = Node.PROCESS_MODE_ALWAYS
	_button = Button.new()
	_button.name = "UpdateBadgeButton"
	_button.focus_mode = Control.FOCUS_NONE
	_button.add_theme_font_size_override("font_size", 7)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.ACCENT
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	for state in ["normal", "hover", "pressed", "focus"]:
		_button.add_theme_stylebox_override(state, box)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		_button.add_theme_color_override(color, Palette.ON_AMBER)
	_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_button.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_button.offset_top = 8
	_button.pressed.connect(open_popup)
	_button.visible = false
	add_child(_button)
	_build_popup()


func _process(_delta: float) -> void:
	var text := UpdateManager.badge_text()
	var bar := HudStatusBar.find(get_tree())
	if bar != null:
		bar.set_segment("update", text, "env")   # in a run: one line in the HUD's status bar
		_button.visible = false
	else:
		_button.visible = not text.is_empty()
		if _button.visible and _button.text != text:
			_button.text = text
			_button.reset_size()
	if _popup.visible:
		_refresh_popup()


func badge_visible_text() -> String:
	return _button.text if _button.visible else ""


func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.name = "UpdatePopup"
	_popup.add_theme_stylebox_override("panel", Palette.panel_box(Color(Palette.PANEL, .97), Palette.ACCENT_EDGE, 10))
	_popup.set_anchors_preset(Control.PRESET_CENTER)
	_popup.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_popup.grow_vertical = Control.GROW_DIRECTION_BOTH
	_popup.visible = false
	add_child(_popup)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	_popup.add_child(column)
	_popup_text = Label.new()
	_popup_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_popup_text.custom_minimum_size = Vector2(200, 0)
	_popup_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Palette.style_label(_popup_text, Palette.INK, 8)
	column.add_child(_popup_text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)
	_restart = Button.new()
	_restart.name = "RestartNowButton"
	Palette.style_button(_restart, true)
	_restart.pressed.connect(restart_now)
	row.add_child(_restart)
	var later := Button.new()
	later.name = "UpdateLaterButton"
	later.text = "LATER"
	Palette.style_button(later, false)
	later.pressed.connect(close_popup)
	row.add_child(later)


func open_popup() -> void:
	_popup.visible = true
	MouseLock.claim("update_popup", true)
	_refresh_popup()


func close_popup() -> void:
	_popup.visible = false
	MouseLock.claim("update_popup", false)


func popup_open() -> bool:
	return _popup.visible


func _refresh_popup() -> void:
	var ready := UpdateManager.ready_to_install or UpdateManager.staging_deferred
	var mobile := UpdateManager.is_mobile_package()
	_restart.text = "INSTALL" if mobile else "RESTART NOW"
	_restart.visible = ready and not UpdateManager.is_dev_build()
	if UpdateManager.is_dev_build():
		_popup_text.text = "A NEWER PUBLISHED BUILD EXISTS. THIS DEV BUILD IS NOT UPDATED AUTOMATICALLY."
	elif ready:
		_popup_text.text = "THE UPDATE IS READY. RESTART NOW, OR IT IS APPLIED THE NEXT TIME YOU QUIT."
	else:
		_popup_text.text = "%s\nIT KEEPS DOWNLOADING WHILE YOU PLAY." % UpdateManager.badge_text()
	_popup.reset_size()


## RESTART NOW: stage if the download waited for a run to end, then swap and relaunch (phones: open the installer).
func restart_now() -> void:
	if UpdateManager.staging_deferred:
		UpdateManager._force_stage_now = true
		await UpdateManager._prepare_verified_download()
	close_popup()
	UpdateManager.install_update(true)
