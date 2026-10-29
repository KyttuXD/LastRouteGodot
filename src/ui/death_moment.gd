class_name DeathMoment
extends CanvasLayer

## The short death cutscene: a dark subtitle box low on the screen, the catcher's name in spaced capitals and her line,
## typed one word every 250 ms (a caption shows whole, in italics). No jumpscare, no flashing. Ported from the 2D
## game's death-moment.js. Tap/click/any key finishes the typing, then dismisses; Esc dismisses at once. The first
## 400 ms of input are ignored so the key held at the moment of death cannot skip it. It closes itself 7 s after the
## line is fully shown (2.5 s in short mode). Reduced motion shows the whole line at once with no fade.

signal finished

const WORD_SECONDS := 0.25
const INPUT_GUARD_SECONDS := 0.4
const AUTO_DISMISS_SECONDS := 7.0
const SHORT_DISMISS_SECONDS := 2.5
const FADE_SECONDS := 0.25

var _root: Control
var _name_label: Label
var _line_label: Label
var _hint: Label
var _words: PackedStringArray = []
var _shown_words := 0
var _caption := false
var _open_msec := 0
var _typing := false
var _full_shown := false
var _timer := 0.0
var _auto_after := AUTO_DISMISS_SECONDS
var _closing := false
var _tween: Tween
## The text that is on screen right now, for validators and screen readers.
var shown_line := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 130
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


## True when a pick should play as a moment at all: only hunter/cause lines, never the end-card fallback copy.
static func plays(picked: Dictionary) -> bool:
	return String(picked.get("source", "")) in ["hunter", "cause"] \
		and not String(picked.get("text", "")).strip_edges().is_empty()


## Plays and returns once it has been dismissed. `hunter_name` is the speaker.
func play(hunter_name: String, picked: Dictionary, void_hunter: bool = false) -> void:
	if not plays(picked) or is_open():
		return
	_closing = false
	_caption = String(picked.get("style", "")) == "caption" or void_hunter
	var text := String(picked["text"])
	_name_label.text = Palette.track(hunter_name.to_upper())
	_words = text.split(" ", false)
	_shown_words = 0
	_full_shown = false
	_timer = 0.0
	_auto_after = SHORT_DISMISS_SECONDS if Settings.short_death_scenes else AUTO_DISMISS_SECONDS
	_open_msec = Time.get_ticks_msec()
	if _caption:
		_line_label.add_theme_font_override("font", _caption_font())
	else:
		_line_label.remove_theme_font_override("font")
	_root.visible = true
	MouseLock.claim("death_moment", true)
	var instant := _caption or Settings.reduced_motion or Settings.short_death_scenes
	if instant:
		_show_all()
	else:
		_typing = true
		_line_label.text = ""
		shown_line = ""
	if Settings.reduced_motion:
		_root.modulate.a = 1.0
	else:
		_root.modulate.a = 0.0
		_tween = create_tween()
		_tween.tween_property(_root, "modulate:a", 1.0, FADE_SECONDS)
	await finished


func dismiss() -> void:
	if _closing or not is_open():
		return
	_closing = true
	_typing = false
	if _tween != null:
		_tween.kill()
	_root.visible = false
	_line_label.text = ""
	_name_label.text = ""
	shown_line = ""
	MouseLock.claim("death_moment", false)
	finished.emit()


func _process(delta: float) -> void:
	if not is_open() or _closing:
		return
	_timer += delta
	if _typing:
		var due := mini(_words.size(), int(_timer / WORD_SECONDS) + 1)
		if due != _shown_words:
			_shown_words = due
			shown_line = " ".join(_words.slice(0, _shown_words))
			_line_label.text = shown_line
			if not _caption and _shown_words % 2 == 1:
				Sound.menu_blip()
		if _shown_words >= _words.size():
			_typing = false
			_full_shown = true
			_timer = 0.0
	elif _full_shown and _timer >= _auto_after:
		dismiss()


func _input(event: InputEvent) -> void:
	if not is_open() or _closing:
		return
	var pressed: bool = (event is InputEventKey and event.pressed and not event.echo) \
		or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventScreenTouch and event.pressed)
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if Time.get_ticks_msec() - _open_msec < INPUT_GUARD_SECONDS * 1000.0:
		return
	if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		dismiss()
	elif _typing:
		_show_all()
	else:
		dismiss()


func _show_all() -> void:
	_typing = false
	_full_shown = true
	_timer = 0.0
	_shown_words = _words.size()
	shown_line = " ".join(_words)
	_line_label.text = shown_line


func _caption_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Courier New", "monospace"])
	font.font_italic = true
	return font


func _build() -> void:
	_root = Control.new()
	_root.name = "DeathMomentRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.name = "Shade"
	shade.color = Color(0.02, 0.01, 0.03, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shade)
	var box := PanelContainer.new()
	box.name = "SubtitleBox"
	box.anchor_left = 0.5
	box.anchor_right = 0.5
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -170
	box.offset_right = 170
	box.offset_top = -86
	box.offset_bottom = -22
	box.add_theme_stylebox_override("panel", Palette.panel_box(Color(0.04, 0.02, 0.06, 0.94), Palette.PANEL_EDGE, 9))
	_root.add_child(box)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	box.add_child(column)
	_name_label = Label.new()
	_name_label.name = "DeathMomentName"
	_name_label.add_theme_color_override("font_color", Palette.AMBER)
	_name_label.add_theme_font_size_override("font_size", 6)
	column.add_child(_name_label)
	_line_label = Label.new()
	_line_label.name = "DeathMomentLine"
	_line_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_line_label.custom_minimum_size = Vector2(320, 0)
	_line_label.add_theme_color_override("font_color", Palette.INK)
	_line_label.add_theme_font_size_override("font_size", 9)
	column.add_child(_line_label)
	_hint = Label.new()
	_hint.name = "DeathMomentHint"
	_hint.text = "CLICK OR PRESS A KEY"
	_hint.add_theme_color_override("font_color", Palette.DIM)
	_hint.add_theme_font_size_override("font_size", 5)
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(_hint)
