class_name StoryPanel
extends Control

## The Facility's HUD parts, built into NightWatchHud's canvas (the HUD file itself is untouched): the task list on the left (done / current / to do),
## the noise meter with Opalie's hearing line, the beacon's charge, a hint for what is held, and the keypad for the terminal. Coordinates are in the
## 480 x 270 canvas the HUD uses.

signal digit_pressed(digit: String)
signal keypad_closed

const AMBER := Color(0.96, 0.72, 0.28)

var task_label: Label
var noise_bar: ProgressBar
var hear_line: ColorRect
var beacon_bar: ProgressBar
var status_label: Label
var keypad: PanelContainer
var keypad_display: Label
var lift_lamp: ColorRect
var keypad_open := false


func _ready() -> void:
	name = "StoryPanel"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_label = _label("", 7, Color(0.93, 0.89, 0.8))
	task_label.name = "TaskList"
	task_label.position = Vector2(8, 70)
	add_child(task_label)
	var noise_title := _label("NOISE", 6, AMBER)
	noise_title.position = Vector2(8, 186)
	add_child(noise_title)
	noise_bar = _bar(Vector2(8, 194), Color(0.9, 0.5, 0.2))
	noise_bar.name = "NoiseBar"
	hear_line = ColorRect.new()
	hear_line.name = "HearLine"
	hear_line.color = Color(1.0, 0.2, 0.2)
	hear_line.size = Vector2(1, 9)
	hear_line.position = Vector2(8, 192)
	hear_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hear_line)
	var beacon_title := _label("BEACON  F", 6, AMBER)
	beacon_title.position = Vector2(8, 206)
	add_child(beacon_title)
	beacon_bar = _bar(Vector2(8, 214), Color(1.0, 0.9, 0.5))
	beacon_bar.name = "BeaconBar"
	status_label = _label("", 7, Color(0.8, 0.9, 1.0))
	status_label.name = "StatusLine"
	status_label.position = Vector2(8, 226)
	add_child(status_label)
	lift_lamp = ColorRect.new()
	lift_lamp.name = "LiftLamp"
	lift_lamp.size = Vector2(10, 4)
	lift_lamp.position = Vector2(8, 60)
	lift_lamp.color = Color(0.2, 0.2, 0.2)
	lift_lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(lift_lamp)
	_build_keypad()


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _bar(pos: Vector2, color: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.position = pos
	b.size = Vector2(100, 7)
	b.show_percentage = false
	b.max_value = 100.0
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.05, 0.05, 0.07, 0.85)
	b.add_theme_stylebox_override("background", back)
	add_child(b)
	return b


func _build_keypad() -> void:
	keypad = PanelContainer.new()
	keypad.name = "Keypad"
	keypad.set_anchors_preset(Control.PRESET_CENTER)
	keypad.position = Vector2(-45, -60)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.04, 0.07, 0.94)
	style.border_color = AMBER
	style.set_border_width_all(1)
	style.set_content_margin_all(8)
	keypad.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	keypad.add_child(v)
	keypad_display = _label("", 12, Color(0.6, 1.0, 0.7))
	keypad_display.name = "KeypadDisplay"
	keypad_display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(keypad_display)
	var grid := GridContainer.new()
	grid.columns = 3
	v.add_child(grid)
	for d in ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", ""]:
		var b := Button.new()
		b.text = d
		b.custom_minimum_size = Vector2(22, 16)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 8)
		b.visible = d != ""
		if d == "":
			b.modulate.a = 0.0
			b.disabled = true
			b.visible = true
		else:
			b.pressed.connect(func(): digit_pressed.emit(d))
		grid.add_child(b)
	var hint := _label("KEY IT IN  /  E OR ESC LEAVES", 5, Color(0.7, 0.68, 0.62))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	keypad.visible = false
	add_child(keypad)


func show_keypad(on: bool) -> void:
	keypad_open = on
	keypad.visible = on


func refresh(sim: StoryLogic) -> void:
	var lines := []
	for i in sim.tasks.size():
		var t: Dictionary = sim.tasks[i]
		var mark := "x" if i < sim.task_idx else (">" if i == sim.task_idx else "-")
		lines.append("%s %s  (%s)" % [mark, t["label"], String(StoryData.ROOMS[t["room"]]["label"]).capitalize()])
	task_label.text = "\n".join(lines)
	noise_bar.value = sim.noise
	hear_line.position.x = 8.0 + float(sim.tune["hear"])
	beacon_bar.value = sim.charge
	var q := String(sim.quenelle["state"])
	lift_lamp.color = Color(1.0, 0.8, 0.2) if q == "bell" else (Color(1.0, 0.3, 0.2) if q == "open" else Color(0.2, 0.2, 0.2))
	var tag := "WALKING" if not sim.moving.is_empty() else (String(StoryData.ROOMS[sim.room]["label"]))
	if sim.hidden:
		tag = "HIDING"
	elif sim.light:
		tag = "BEACON ON"
	elif sim.working:
		tag = "HOLDING THE BUTTON"
	status_label.text = tag
	if keypad_open and sim.puzzle.get("kind", "") == "code":
		var shown := String(sim.puzzle["entered"])
		keypad_display.text = shown + "_".repeat(maxi(0, int(sim.puzzle["n"]) - shown.length()))
