class_name NightWatchHud
extends CanvasLayer

## Night Watch's screen furniture: the shift clock, the power meter, Zellia's call box, the monitor (a live SubViewport feed of
## one camera room, the camera map, REC and the room's name), the pause card and the end card. All drawn in code so the scene
## stays a single node; styled with the Night Watch theme (theme_nightwatch.tres) when it loads.

signal camera_selected(room: String)
signal retry_pressed
signal next_pressed
signal menu_pressed
signal resume_pressed
signal subtitles_toggled(on: bool)
signal pause_requested
signal cameras_requested

const AMBER := Color(0.96, 0.72, 0.28)
const INK := Color(0.93, 0.89, 0.80)
const PANEL := Color(0.05, 0.04, 0.07, 0.88)

var clock_label: Label
var night_label: Label
var power_label: Label
var usage_label: Label
var hint_label: Label
var prompt_label: Label
var note_label: Label
var _note_left := 0.0
var call_panel: PanelContainer
var call_label: Label
var call_mute: Button
var pause_button: Button
var cameras_button: Button
var call_script: NightWatchCallScript

var monitor_root: Control
var feed_viewport: SubViewport
var feed_camera: Camera3D
var cam_label: Label
var rec_label: Label
var static_rect: ColorRect
var cam_buttons := {}
var _static_left := 0.0

var pause_root: Control
var end_root: Control
var end_title: Label
var end_body: Label
var end_next: Button
var _call_queue: Array = []
var _call_timer := 0.0
var _call_active := false
var _script_shown := false
var muted := false
var subtitles := true
var subtitles_button: Button
var shown_call := ""
var mode_text := ""   # "1. Classic · Night 1", set by the mode scene


func _ready() -> void:
	layer = 20
	var theme_path := "res://src/ui/theme_nightwatch.tres"
	var root := Control.new()
	root.name = "HudRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(theme_path) and load(theme_path) is Theme:
		root.theme = load(theme_path)
	add_child(root)
	_build_status(root)
	_build_call(root)
	_build_monitor(root)
	_build_pause(root)
	_build_end(root)


func _label(text: String, size := 18, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _build_status(root: Control) -> void:
	var box := VBoxContainer.new()
	box.name = "Status"
	box.position = Vector2(8, 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)
	# the 2D shift HUD: power and usage top left with the mode and night under them, the clock top right with a Pause button
	clock_label = _label("12 AM", 12, INK)
	clock_label.name = "ClockLabel"
	clock_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock_label.offset_left = -62
	clock_label.offset_right = -8
	clock_label.offset_top = 6
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(clock_label)
	pause_button = Button.new()
	pause_button.name = "PauseButton"
	pause_button.text = "Ⅱ Pause"
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.add_theme_font_size_override("font_size", 6)
	pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_button.offset_left = -44
	pause_button.offset_right = -8
	pause_button.offset_top = 22
	pause_button.pressed.connect(func(): pause_requested.emit())
	root.add_child(pause_button)
	power_label = _label("Power left: 100%", 9)
	power_label.name = "PowerLabel"
	usage_label = _label("Usage: ▮", 9)
	usage_label.name = "UsageLabel"
	night_label = _label("1. Classic · Night 1", 7, Color(0.54, 0.52, 0.45))
	night_label.name = "NightLabel"
	for l in [power_label, usage_label, night_label]:
		box.add_child(l)
	cameras_button = Button.new()
	cameras_button.name = "CamerasButton"
	cameras_button.text = "▲ CAMERAS  U"
	cameras_button.focus_mode = Control.FOCUS_NONE
	cameras_button.add_theme_font_size_override("font_size", 6)
	cameras_button.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	cameras_button.offset_left = -45
	cameras_button.offset_right = 45
	cameras_button.offset_top = -17
	cameras_button.offset_bottom = -5
	cameras_button.pressed.connect(func(): cameras_requested.emit())
	root.add_child(cameras_button)
	hint_label = _label("WASD move · E use (hold on LIGHT) · Z / X doors · G / H lights · U cameras · Y lamp · R mute · P pause", 6, Color(0.54, 0.52, 0.45))
	hint_label.name = "HintLabel"
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint_label.position = Vector2(8, -22)
	hint_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(hint_label)
	# the shared crosshair (it follows MouseLock) and the shared interaction prompt (the route HUD's InteractionLabel, same style)
	var reticle := Crosshair.new()
	reticle.name = "Crosshair"
	reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	reticle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(reticle)
	prompt_label = Label.new()
	prompt_label.name = "PromptLabel"
	prompt_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	prompt_label.offset_left = -150
	prompt_label.offset_top = -98
	prompt_label.offset_right = 150
	prompt_label.offset_bottom = -79
	prompt_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	prompt_label.add_theme_color_override("font_color", Color(0.949, 0.929, 0.882, 1))
	prompt_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	prompt_label.add_theme_constant_override("shadow_offset_x", 1)
	prompt_label.add_theme_constant_override("shadow_offset_y", 1)
	prompt_label.add_theme_font_size_override("font_size", 10)
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(prompt_label)
	note_label = _label("", 8, Color(0.85, 0.82, 0.75))
	note_label.name = "NoteLabel"
	note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note_label.set_anchors_preset(Control.PRESET_CENTER)
	note_label.custom_minimum_size = Vector2(300, 0)
	note_label.position = Vector2(-150, 30)
	root.add_child(note_label)


## Zellia's call box, as the 2D .ncall: centred, 60% of the width, bottom at 10% of the height, black 78% fill, a grey-brown border, the
## amber letter-spaced name, the typed text growing to fill, and the Mute button at the right (the 2D key is N; here the shared radio key R).
func _build_call(root: Control) -> void:
	call_panel = PanelContainer.new()
	call_panel.name = "CallPanel"
	call_panel.visible = false
	call_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.78)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	style.border_color = Color("5a5446")
	style.set_border_width_all(1)
	call_panel.add_theme_stylebox_override("panel", style)
	call_panel.anchor_left = 0.2
	call_panel.anchor_right = 0.8
	call_panel.anchor_top = 0.9      # the bottom edge at 10% of the height, at any resolution
	call_panel.anchor_bottom = 0.9
	call_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var row := HBoxContainer.new()
	row.name = "CallRow"
	row.add_theme_constant_override("separation", 6)
	call_panel.add_child(row)
	var who := _label("Z E L L I A", 6, AMBER)
	who.name = "CallName"
	row.add_child(who)
	call_label = _label("", 7)
	call_label.name = "CallText"
	call_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	call_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(call_label)
	call_mute = Button.new()
	call_mute.name = "CallMute"
	call_mute.text = "Mute  R"
	call_mute.focus_mode = Control.FOCUS_NONE
	call_mute.add_theme_font_size_override("font_size", 6)
	call_mute.pressed.connect(toggle_mute)
	row.add_child(call_mute)
	root.add_child(call_panel)


func _build_monitor(root: Control) -> void:
	monitor_root = Control.new()
	monitor_root.name = "Monitor"
	monitor_root.visible = false
	monitor_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(monitor_root)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.03, 0.03, 0.96)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	monitor_root.add_child(back)
	var ratio := AspectRatioContainer.new()
	ratio.ratio = 16.0 / 9.0
	ratio.set_anchors_preset(Control.PRESET_FULL_RECT)
	ratio.offset_left = 22
	ratio.offset_right = -22
	ratio.offset_top = 12
	ratio.offset_bottom = -12
	monitor_root.add_child(ratio)
	var container := SubViewportContainer.new()
	container.name = "FeedContainer"
	container.stretch = true
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	ratio.add_child(container)
	feed_viewport = SubViewport.new()
	feed_viewport.name = "Feed"
	feed_viewport.size = Vector2i(480, 270)
	feed_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	feed_viewport.msaa_3d = Viewport.MSAA_DISABLED
	container.add_child(feed_viewport)
	feed_camera = Camera3D.new()
	feed_camera.name = "FeedCamera"
	feed_camera.fov = 62.0
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.03, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.95, 0.9, 0.8)
	env.ambient_light_energy = 1.15
	feed_camera.environment = env
	feed_viewport.add_child(feed_camera)
	# feed furniture: room name, REC, static on a switch
	cam_label = _label("CAM 1  SHOW STAGE", 11, Color(0.8, 1.0, 0.85))
	cam_label.name = "CamLabel"
	cam_label.position = Vector2(30, 18)
	monitor_root.add_child(cam_label)
	rec_label = _label("● REC", 10, Color(1.0, 0.3, 0.3))
	rec_label.name = "RecLabel"
	rec_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	rec_label.position = Vector2(-80, 18)
	monitor_root.add_child(rec_label)
	static_rect = ColorRect.new()
	static_rect.name = "Static"
	static_rect.color = Color(0.75, 0.78, 0.76, 0.0)
	static_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	static_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	static_rect.offset_left = 22
	static_rect.offset_right = -22
	static_rect.offset_top = 12
	static_rect.offset_bottom = -12
	monitor_root.add_child(static_rect)
	# the camera map, bottom right
	var map := Control.new()
	map.name = "CamMap"
	map.custom_minimum_size = Vector2(120, 92)
	map.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	map.position = Vector2(-146, -112)
	monitor_root.add_child(map)
	var frame := ColorRect.new()
	frame.color = Color(0.04, 0.08, 0.06, 0.8)
	frame.size = Vector2(120, 92)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(frame)
	for room in NightWatchData.cam_rooms():
		var info: Dictionary = NightWatchData.ROOMS[room]
		var b := Button.new()
		b.name = "Cam_%s" % room
		b.text = "CAM %d" % int(info["cam"])
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(30, 13)
		b.add_theme_font_size_override("font_size", 6)
		var p: Vector2 = info["map"]
		b.position = Vector2(p.x / 100.0 * 120.0 - 15.0, p.y / 100.0 * 92.0 - 6.0)
		b.pressed.connect(func(): camera_selected.emit(room))
		map.add_child(b)
		cam_buttons[room] = b
	var you := _label("YOU", 7, AMBER)
	you.position = Vector2(52, 82)
	map.add_child(you)


func _build_pause(root: Control) -> void:
	pause_root = _card(root, "Pause", "PAUSED", "")
	pause_root.process_mode = Node.PROCESS_MODE_ALWAYS
	var box := pause_root.find_child("CardButtons", true, false) as HBoxContainer
	var resume := Button.new()
	resume.name = "ResumeButton"
	resume.text = "RESUME  ESC"
	resume.pressed.connect(func(): resume_pressed.emit())
	box.add_child(resume)
	var back := Button.new()
	back.name = "PauseMenuButton"
	back.text = "QUIT TO HUB  BACKSPACE"
	back.pressed.connect(func(): menu_pressed.emit())
	box.add_child(back)
	pause_root.visible = false


func _build_end(root: Control) -> void:
	end_root = _card(root, "End", "", "")
	end_title = end_root.find_child("CardTitle", true, false) as Label
	end_body = end_root.find_child("CardBody", true, false) as Label
	var box := end_root.find_child("CardButtons", true, false) as HBoxContainer
	end_next = Button.new()
	end_next.name = "NextButton"
	end_next.text = "NEXT NIGHT  ENTER"
	end_next.pressed.connect(func(): next_pressed.emit())
	box.add_child(end_next)
	var retry := Button.new()
	retry.name = "RetryButton"
	retry.text = "RETRY  ENTER"
	retry.pressed.connect(func(): retry_pressed.emit())
	box.add_child(retry)
	var back := Button.new()
	back.name = "EndMenuButton"
	back.text = "MENU  ESC"
	back.pressed.connect(func(): menu_pressed.emit())
	box.add_child(back)
	end_root.visible = false


func _card(root: Control, card_name: String, title: String, body: String) -> Control:
	var wrap := Control.new()
	wrap.name = card_name + "Card"
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.add_child(dim)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.set_content_margin_all(10)
	style.border_color = AMBER
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(280, 0)
	panel.position = Vector2(-140, -60)
	wrap.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	panel.add_child(v)
	var t := _label(title, 22, AMBER)
	t.name = "CardTitle"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var b := _label(body, 8)
	b.name = "CardBody"
	b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(b)
	var buttons := HBoxContainer.new()
	buttons.name = "CardButtons"
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 6)
	v.add_child(buttons)
	root.add_child(wrap)
	return wrap


func update_status(hour: int, power: float, usage: int, night: int) -> void:
	clock_label.text = NightWatchData.hour_label(hour)
	if mode_text.is_empty():
		night_label.text = "1. Classic · Night %d" % night
	else:
		night_label.text = mode_text
	power_label.text = "Power left: %d%%" % int(ceil(power))
	usage_label.text = "Usage: " + "▮".repeat(clampi(usage + 1, 1, 7))


func set_prompt(text: String) -> void:
	prompt_label.text = text


func show_note(text: String, seconds := 2.5) -> void:
	note_label.text = text
	_note_left = seconds


## An office without a camera monitor (Bedtime, The Descent, Open Air) hides the CAMERAS button: call with `office.spec.has_monitor`.
func set_monitor_available(on: bool) -> void:
	if cameras_button != null:
		cameras_button.visible = on


func show_monitor(on: bool) -> void:
	prompt_label.visible = not on
	monitor_root.visible = on
	feed_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED


func set_cam(room: String, mount: Transform3D) -> void:
	var info: Dictionary = NightWatchData.ROOMS.get(room, {})
	cam_label.text = "CAM %d  %s" % [int(info.get("cam", 0)), String(info.get("label", ""))]
	feed_camera.transform = mount
	for r in cam_buttons:
		(cam_buttons[r] as Button).modulate = Color(1.0, 0.85, 0.4) if r == room else Color(1, 1, 1)


func flash_static() -> void:
	if "reduced_motion" in Settings and bool(Settings.reduced_motion):
		return
	_static_left = 0.14


func show_call(text: String) -> void:
	shown_call = text
	call_label.text = text
	call_panel.visible = not text.is_empty() and not muted and subtitles
	hint_label.visible = not call_panel.visible   # the key line yields to the call box, which sits where it does


func set_subtitles(on: bool) -> void:
	subtitles = on
	if subtitles_button != null:
		subtitles_button.text = "SUBTITLES: ON" if on else "SUBTITLES: OFF"
	call_panel.visible = not shown_call.is_empty() and not muted and subtitles


## Zellia's script for this shift (NightWatchCallScript); the game feeds it the shift clock through update_call().
func set_call_script(script: NightWatchCallScript) -> void:
	call_script = script
	_call_active = false
	show_call("")


func update_call(elapsed_ms: float, dt_ms: float) -> void:
	if call_script == null:
		return
	for e in call_script.update(elapsed_ms, dt_ms):
		match String(e):
			"ring":
				NightWatchSounds.call_ring()
			"talk":
				NightWatchSounds.call_line()
	if call_script.open:
		show_call(call_script.text)
		_script_shown = true
	elif _script_shown:
		_script_shown = false
		show_call("")


## A call given as plain lines (the old interface): wraps them in a script that rings at once.
func queue_call(lines: Array) -> void:
	set_call_script(NightWatchCallScript.new(lines, 0.0))


func _process(delta: float) -> void:
	if _note_left > 0.0:
		_note_left -= delta
		if _note_left <= 0.0:
			note_label.text = ""
	if _static_left > 0.0:
		_static_left -= delta
		static_rect.color = Color(0.7 + randf() * 0.2, 0.74 + randf() * 0.2, 0.72, clampf(_static_left / 0.14, 0.0, 1.0) * 0.9)
	elif static_rect.color.a > 0.0:
		static_rect.color.a = 0.0
	rec_label.visible = monitor_root.visible and int(Time.get_ticks_msec() / 600) % 2 == 0


## Mute ends the call (2D `call.mute()`): the box closes and she does not ring again this shift.
func toggle_mute() -> void:
	if call_script != null and call_script.mute():
		muted = true
		show_call("")
		return
	muted = true
	call_panel.visible = false


func show_pause(on: bool) -> void:
	pause_root.visible = on


func show_end(title: String, body: String, can_next: bool) -> void:
	end_title.text = title
	end_body.text = body
	end_next.visible = can_next
	end_root.visible = true
