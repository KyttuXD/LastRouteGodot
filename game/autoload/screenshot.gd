extends Node

## F2 saves a PNG of the game window as it is on screen, from any screen: title, hub, menus, pause and gameplay.
## Files go to user://screenshots/ as KYTTU_<date>_<time>.png (a second press in the same second gets _2, _3 ...).
## A short line under the bottom-left corner names the file once it is saved, so the capture never includes it.

const KEY := KEY_F2
const FOLDER := "user://screenshots"
const SHOW_SECONDS := 1.8

## Where captures are written. The validator points this at a scratch folder outside user://, so a test never leaves
## files in the real saves folder (see tests/user_guard.gd).
var folder := FOLDER

var _label: Label
var _tween: Tween


func _ready() -> void:
	# Menus pause the tree and the key must still work there.
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_label = Label.new()
	_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_label.offset_left = 16.0
	_label.offset_bottom = -16.0
	_label.offset_top = -16.0 - 32.0
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.visible = false
	layer.add_child(_label)


func _input(event: InputEvent) -> void:
	if not is_capture_key(event):
		return
	get_viewport().set_input_as_handled()
	_show(capture())


## True for the press of the capture key only (not a release, not key repeat).
static func is_capture_key(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var key := event as InputEventKey
	return key.pressed and not key.echo and (key.keycode == KEY or key.physical_keycode == KEY)


## Name for a capture taken at `now` (a Time.get_datetime_dict_from_system() style dictionary).
static func file_stem(now: Dictionary) -> String:
	return "KYTTU_%04d-%02d-%02d_%02d-%02d-%02d" % [now.year, now.month, now.day, now.hour, now.minute, now.second]


## `path` itself, or the first "<stem>_2", "<stem>_3" ... that does not exist yet.
static func unused_path(path: String) -> String:
	if not FileAccess.file_exists(path):
		return path
	var stem := path.get_basename()
	var ext := path.get_extension()
	var n := 2
	while FileAccess.file_exists("%s_%d.%s" % [stem, n, ext]):
		n += 1
	return "%s_%d.%s" % [stem, n, ext]


## Saves what the window shows right now. Returns the file path, or "" when nothing could be written (no rendered
## image, for example a run without a renderer).
func capture() -> String:
	var image := get_viewport().get_texture().get_image()
	if image == null:
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var path := unused_path(folder.path_join(file_stem(Time.get_datetime_dict_from_system()) + ".png"))
	if image.save_png(path) != OK:
		return ""
	print("screenshot: %s" % ProjectSettings.globalize_path(path))
	return path


func _show(path: String) -> void:
	_label.text = ("SCREENSHOT  " + path.get_file()) if path != "" else "SCREENSHOT FAILED: nothing was written"
	_label.modulate.a = 1.0
	_label.visible = true
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_tween.tween_interval(SHOW_SECONDS)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.4)
	_tween.tween_callback(_label.hide)
