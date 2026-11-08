class_name NightWatchDescentPanel
extends Control

## The service panel's screen (drawn over the panel plate on the car's back wall): the fuse boxes and their buttons, the four signal pads,
## the pipe grid, or the door hold. A port of the panels in the 2D game. It only draws what the rules hold (refresh) and reports
## presses as signals; the shift scene hands them to NightWatchDescentLogic. Sizes are in the project's 480 x 270 canvas.

signal wire_pressed(button: int)
signal pad_pressed(pad: int)
signal pipe_pressed(r: int, c: int)
signal hold_changed(down: bool)

const AMBER := Color(0.96, 0.72, 0.28)
const INK := Color(0.93, 0.89, 0.80)
const PANEL := Color(0.05, 0.04, 0.07, 0.92)
const WIRE_COLOURS := [Color("e0b040"), Color("50b0e0"), Color("e06060"), Color("70d090"), Color("c080e0"), Color("e09050")]
const PAD_COLOURS := [Color("e06060"), Color("e0b040"), Color("50b0e0"), Color("70d090")]
const SIZE := Vector2(172.0, 150.0)

var title_label: Label
var sub_label: Label
var body: Control
var hold_button: Button
var hold_bar: ColorRect
var hold_fill: ColorRect
var buttons: Array = []     # the wire buttons / signal pads / pipe tiles of the current panel, for the scene and the validator
var shown := ""
var message := ""


func _init() -> void:
	name = "ServicePanel"
	custom_minimum_size = SIZE
	size = SIZE
	mouse_filter = Control.MOUSE_FILTER_PASS


func _ready() -> void:
	var back := ColorRect.new()
	back.name = "Back"
	back.color = PANEL
	back.size = SIZE
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	title_label = _label("", 7, AMBER)
	title_label.position = Vector2(4, 2)
	title_label.size = Vector2(SIZE.x - 8, 10)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_label)
	body = Control.new()
	body.name = "Body"
	body.position = Vector2(4, 14)
	body.size = Vector2(SIZE.x - 8, SIZE.y - 36)
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)
	sub_label = _label("", 7, INK)
	sub_label.position = Vector2(4, SIZE.y - 18)
	sub_label.size = Vector2(SIZE.x - 8, 10)
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub_label)


func _label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _clear() -> void:
	for c in body.get_children():
		c.queue_free()
		body.remove_child(c)
	buttons.clear()
	hold_button = null
	hold_bar = null
	hold_fill = null


## Show what the rules hold now. Rebuilds the controls only when the picture changes.
func refresh(game: NightWatchDescentLogic) -> void:
	var z := game.puzzle
	var sig := ""
	if game.over != "":
		sig = "over"
	elif game.ride > 0.0:
		sig = "ride%d" % game.stage_idx
	elif game.kind() == "memory":
		sig = "m|%s|%d|%d|%s|%s" % [z["phase"], z["lit"], z["step"], str(z["seq"]), str(z["hues"])]
	elif game.kind() == "hold":
		sig = "hold"
	else:
		sig = JSON.stringify(z)
	if sig != shown:
		shown = sig
		_rebuild(game)
	if hold_fill != null:
		hold_fill.size.x = hold_bar.size.x * clampf(game.held / NightWatchDescentLogic.HOLD_MS, 0.0, 1.0)


func _rebuild(game: NightWatchDescentLogic) -> void:
	_clear()
	var z := game.puzzle
	if game.over != "" or z.is_empty():
		title_label.text = ""
		sub_label.text = ""
		return
	if game.ride > 0.0:
		title_label.text = ""
		var l := _label("DESCENDING\nFLOOR %d" % (game.stage_idx + 1), 9, AMBER)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.size = body.size
		body.add_child(l)
		sub_label.text = ""
		return
	title_label.text = NightWatchDescentLogic.stage_title(game.kind())
	match game.kind():
		"wires":
			_wires(z)
		"memory":
			_memory(z)
		"pipes":
			_pipes(z)
		"hold":
			_hold()


func _wires(z: Dictionary) -> void:
	var boxes := int(z["boxes"])
	var nbtn := int(z["buttons"])
	var rows := body.size.y / (boxes + 1)
	var brows := body.size.y / (nbtn + 1)
	var lit: Array = z["lit"]
	var target: int = int(lit[int(z["step"])])
	var wire: Array = z["wire"]
	var colors: Array = z.get("colors", [])
	var lines := Control.new()
	lines.name = "Wires"
	lines.size = body.size
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lines.draw.connect(func():
		for i in boxes:
			var col: Color = WIRE_COLOURS[int(colors[i]) if i < colors.size() else i % 6]
			lines.draw_line(Vector2(26.0, (i + 1) * rows), Vector2(body.size.x - 26.0, (int(wire[i]) + 1) * brows), col, 1.5))
	body.add_child(lines)
	for i in boxes:
		var col: Color = WIRE_COLOURS[int(colors[i]) if i < colors.size() else i % 6]
		var done := lit.find(i) >= 0 and lit.find(i) < int(z["step"])
		var box := ColorRect.new()
		box.name = "Box%d" % i
		box.size = Vector2(16, 10)
		box.position = Vector2(6, (i + 1) * rows - 5)
		box.color = Color(1, 1, 1) if i == target else (col.darkened(0.55) if done else col.darkened(0.25))
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(box)
	for b in nbtn:
		var btn := Button.new()
		btn.name = "Wire%d" % b
		btn.text = str(b + 1)
		btn.size = Vector2(18, 12)
		btn.position = Vector2(body.size.x - 24.0, (b + 1) * brows - 6)
		btn.add_theme_font_size_override("font_size", 7)
		btn.pressed.connect(func(): wire_pressed.emit(b))
		body.add_child(btn)
		buttons.append(btn)
	sub_label.text = "%d / %d" % [int(z["step"]), lit.size()]


func _memory(z: Dictionary) -> void:
	var hues: Array = z.get("hues", [0, 1, 2, 3])
	var show := String(z["phase"]) == "show"
	for i in 4:
		var pad := Button.new()
		pad.name = "Pad%d" % i
		pad.text = str(i + 1)
		pad.size = Vector2(40, 34)
		pad.position = Vector2(body.size.x * 0.5 - 44.0 + (i % 2) * 48.0, 6.0 + (i / 2) * 42.0)
		pad.disabled = show
		pad.add_theme_font_size_override("font_size", 9)
		var col: Color = PAD_COLOURS[int(hues[i])]
		var lit_now := int(z["lit"]) == i
		for state in ["normal", "hover", "pressed", "disabled", "focus"]:
			var sb := StyleBoxFlat.new()
			sb.bg_color = col if lit_now else col.darkened(0.55)
			sb.set_border_width_all(1)
			sb.border_color = Color(1, 1, 1) if lit_now else col.darkened(0.2)
			pad.add_theme_stylebox_override(state, sb)
		pad.add_theme_color_override("font_disabled_color", INK)
		pad.pressed.connect(func(): pad_pressed.emit(i))
		body.add_child(pad)
		buttons.append(pad)
	sub_label.text = "WATCH" if show else "REPEAT · %d / %d" % [int(z["step"]), (z["seq"] as Array).size()]


func _pipes(z: Dictionary) -> void:
	var n := int(z["n"])
	var flow := NightWatchDescentLogic.pipes_flow(z)
	var wet := {}
	for cell in flow["cells"]:
		wet["%d,%d" % [cell[0], cell[1]]] = true
	var tile := floorf(minf((body.size.x - 44.0) / n, (body.size.y - 4.0) / n))
	var ox := (body.size.x - tile * n) * 0.5
	for r in n:
		for c in n:
			var t: Dictionary = z["tiles"][r][c]
			var open: Array = NightWatchDescentLogic.pipe_openings(t)
			var is_wet := wet.has("%d,%d" % [r, c])
			var btn := Button.new()
			btn.name = "Pipe%d_%d" % [r, c]
			btn.size = Vector2(tile - 1.0, tile - 1.0)
			btn.position = Vector2(ox + c * tile, 2.0 + r * tile)
			btn.focus_mode = Control.FOCUS_NONE
			btn.draw.connect(func():
				var mid := btn.size * 0.5
				var col := Color("7fe0ff") if is_wet else Color("9aa0b0")
				for d in open:
					var end := mid + Vector2([0, 1, 0, -1][d], [-1, 0, 1, 0][d]) * mid.x
					btn.draw_line(mid, end, col, 3.0)
				btn.draw_circle(mid, 2.5, col))
			btn.pressed.connect(func(): pipe_pressed.emit(r, c))
			body.add_child(btn)
			buttons.append(btn)
	var tag_in := _label("IN ▶", 6, AMBER)
	tag_in.position = Vector2(0, 2.0 + tile * 0.5 - 5.0)
	body.add_child(tag_in)
	var tag_out := _label("▶ OUT", 6, Color("7fe0ff") if flow["done"] else AMBER)
	tag_out.position = Vector2(body.size.x - 24.0, 2.0 + tile * (n - 0.5) - 5.0)
	body.add_child(tag_out)
	sub_label.text = "TURN THE PIECES · CONNECT IN TO OUT"


func _hold() -> void:
	var info := _label("SHE IS TRYING TO GET ON\nhold the door shut", 8, INK)
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.size = Vector2(body.size.x, 24)
	info.position = Vector2(0, 8)
	body.add_child(info)
	hold_bar = ColorRect.new()
	hold_bar.name = "HoldBar"
	hold_bar.color = Color(0.2, 0.2, 0.25)
	hold_bar.size = Vector2(body.size.x - 20.0, 6)
	hold_bar.position = Vector2(10, 42)
	body.add_child(hold_bar)
	hold_fill = ColorRect.new()
	hold_fill.color = AMBER
	hold_fill.size = Vector2(0, 6)
	hold_bar.add_child(hold_fill)
	hold_button = Button.new()
	hold_button.name = "HoldButton"
	hold_button.text = "HOLD THE DOOR  SPACE"
	hold_button.size = Vector2(body.size.x - 20.0, 16)
	hold_button.position = Vector2(10, 58)
	hold_button.add_theme_font_size_override("font_size", 7)
	hold_button.button_down.connect(func(): hold_changed.emit(true))
	hold_button.button_up.connect(func(): hold_changed.emit(false))
	body.add_child(hold_button)
	buttons.append(hold_button)
	sub_label.text = ""
