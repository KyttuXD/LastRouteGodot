class_name PauseMenu
extends CanvasLayer

## The pause overlay, shared by both 3D modes.
##
## ESC used to drop you straight to the main menu with no confirmation, which
## in a run with two lives left is a way to lose one by reaching for the wrong
## key. Now it stops the game and asks.
##
## Two ways in, because the modes want different things:
##
##   * Last Route taps ESC. It is a co-op mode, so pausing has to be quick.
##   * Office Mode HOLDS ESC for three seconds, with a meter while you do. It
##     is singleplayer by design, so nothing is waiting on you -- and the whole
##     mode is about not being able to step away, which a one-key escape hatch
##     would undercut.
##
## Built in code rather than as a .tscn on purpose: every colour comes from
## Palette, so restyling the game is one file rather than a hunt through scene
## files for hardcoded values.

signal resumed
signal abandoned

## How long ESC must be held in hold-to-pause mode.
const HOLD_SECONDS := 3.0

## Tap to pause, or hold. Office Mode sets this false.
@export var tap_to_pause := true
## What the abandon button says. "ROUTE" for the maze, "SHIFT" for the office.
@export var abandon_label := "ABANDON ROUTE"
## What leaving actually costs, spelled out on the confirmation. Co-op ends the
## run for the whole room, which is not something to discover afterwards.
@export var abandon_warning := "This ends the run for everyone in the room and returns to staging."

var _open := false
var _confirming := false
var _held := 0.0

var _scrim: ColorRect
var _panel: PanelContainer
var _confirm: PanelContainer
var _hold_box: PanelContainer
var _hold_fill: ColorRect
var _resume_button: Button
var _abandon_button: Button


func _ready() -> void:
	# The tree is paused while this is up, so it has to keep running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build()
	_set_open(false)


func is_open() -> bool:
	return _open


func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Palette.SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.PANEL_EDGE, 16))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(210, 0)
	_panel.offset_left = -105
	_panel.offset_right = 105
	_panel.offset_top = -56
	_panel.offset_bottom = 56
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Palette.GAP)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = Palette.track("SIGNAL SUSPENDED")
	Palette.style_label(eyebrow, Palette.AMBER, 7)
	column.add_child(eyebrow)

	var title := Label.new()
	title.text = "PAUSED"
	Palette.style_label(title, Palette.INK, 30)
	column.add_child(title)

	_resume_button = Button.new()
	_resume_button.text = "RETURN"
	_resume_button.focus_mode = Control.FOCUS_ALL
	_resume_button.custom_minimum_size = Vector2(74, 18)
	_resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Palette.style_button(_resume_button, true)
	_resume_button.pressed.connect(close)
	column.add_child(_resume_button)

	_abandon_button = Button.new()
	_abandon_button.text = abandon_label
	_abandon_button.focus_mode = Control.FOCUS_ALL
	_abandon_button.custom_minimum_size = Vector2(88, 14)
	_abandon_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_abandon_button.add_theme_font_size_override("font_size", 8)
	Palette.style_button(_abandon_button, false)
	_abandon_button.pressed.connect(_ask_abandon)
	column.add_child(_abandon_button)

	_build_confirm()
	_build_hold_prompt()


## Leaving is a two-step question, not a button. Abandoning is irreversible and
## in co-op it ends the run for everybody, so the second step says so rather
## than assuming the first click meant it.
func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.CRIMSON_DEEP, 14))
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.offset_left = -118
	_confirm.offset_right = 118
	_confirm.offset_top = -44
	_confirm.offset_bottom = 44
	add_child(_confirm)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	_confirm.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = Palette.track("SIGNAL SUSPENDED")
	Palette.style_label(eyebrow, Palette.AMBER, 7)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(eyebrow)

	var title := Label.new()
	title.text = "%s?" % abandon_label
	Palette.style_label(title, Palette.INK, 16)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)

	var body := Label.new()
	body.text = abandon_warning
	Palette.style_label(body, Palette.BODY, 8)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(208, 0)
	column.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	var yes := Button.new()
	yes.text = abandon_label
	yes.custom_minimum_size = Vector2(0, 14)
	yes.add_theme_font_size_override("font_size", 8)
	Palette.style_button(yes, false)
	yes.add_theme_stylebox_override("normal",
		Palette.button_box(Palette.PANEL, Palette.CRIMSON_DEEP))
	yes.pressed.connect(_on_abandon)
	row.add_child(yes)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(0, 14)
	cancel.add_theme_font_size_override("font_size", 8)
	Palette.style_button(cancel, false)
	cancel.pressed.connect(_cancel_abandon)
	row.add_child(cancel)

	_confirm.visible = false


func _ask_abandon() -> void:
	_confirming = true
	_panel.visible = false
	_confirm.visible = true


func _cancel_abandon() -> void:
	_confirming = false
	_confirm.visible = false
	_panel.visible = true
	_resume_button.grab_focus()


## The hold meter, shown only while ESC is actually down. Sitting above the
## bottom edge rather than in the middle, so it never covers what the player is
## watching while they decide whether to keep holding.
func _build_hold_prompt() -> void:
	_hold_box = PanelContainer.new()
	_hold_box.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.PANEL_EDGE, 6))
	_hold_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hold_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hold_box.offset_left = -66
	_hold_box.offset_right = 66
	_hold_box.offset_top = -46
	_hold_box.offset_bottom = -22
	_hold_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hold_box)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	_hold_box.add_child(stack)

	var caption := Label.new()
	caption.text = Palette.track("HOLD ESC TO PAUSE")
	Palette.style_label(caption, Palette.AMBER, 7)
	stack.add_child(caption)

	var track := ColorRect.new()
	track.color = Palette.INSET
	track.custom_minimum_size = Vector2(0, 3)
	stack.add_child(track)

	_hold_fill = ColorRect.new()
	_hold_fill.color = Palette.CRIMSON
	_hold_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_hold_fill.anchor_right = 0.0
	track.add_child(_hold_fill)

	_hold_box.visible = false


func open() -> void:
	if _open:
		return
	_set_open(true)
	_resume_button.grab_focus()


func close() -> void:
	if not _open:
		return
	_set_open(false)
	resumed.emit()


func _set_open(is_open: bool) -> void:
	_open = is_open
	_confirming = false
	_held = 0.0
	_scrim.visible = is_open
	_panel.visible = is_open
	_confirm.visible = false
	_hold_box.visible = false
	get_tree().paused = is_open
	# The cursor is a claim rather than a mode change, so the camera cannot
	# take it back on its next frame while the menu is still up.
	MouseLock.claim("pause", is_open)


func _on_abandon() -> void:
	_set_open(false)
	abandoned.emit()


## ESC is read here rather than in each mode's controller, so tap and hold
## behave identically wherever the menu is used.
func _process(delta: float) -> void:
	if _open:
		return
	if tap_to_pause:
		return
	if Input.is_action_pressed("pause"):
		_held += delta
		_hold_box.visible = true
		_hold_fill.anchor_right = clampf(_held / HOLD_SECONDS, 0.0, 1.0)
		if _held >= HOLD_SECONDS:
			open()
	elif _held > 0.0:
		_held = 0.0
		_hold_box.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _confirming:
		# ESC backs out of the question rather than out of the run.
		_cancel_abandon()
		get_viewport().set_input_as_handled()
	elif _open:
		close()
		get_viewport().set_input_as_handled()
	elif tap_to_pause:
		open()
		get_viewport().set_input_as_handled()
