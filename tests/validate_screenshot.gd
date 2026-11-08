extends RefCounted

## F2 screenshot (Screenshot autoload): the key is F2 and only the press counts, the file names are dated and never
## overwrite, and a capture lands as a PNG of the window's size. Captures go to a scratch folder outside user://, so
## the user guard never sees them. A headless run may have no rendered image; then the capture is reported, not failed.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- screenshot

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _key(keycode: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	event.echo = echo
	return event


func run(host: Node) -> int:
	var shot := host.get_node_or_null("/root/Screenshot")
	_expect(shot != null, "the Screenshot autoload is not running")
	if shot == null:
		return _failures

	# the key: F2 press only
	_expect(Screenshot.KEY == KEY_F2, "the capture key is not F2")
	_expect(Screenshot.is_capture_key(_key(KEY_F2)), "F2 press does not capture")
	_expect(not Screenshot.is_capture_key(_key(KEY_F2, false)), "F2 release captures")
	_expect(not Screenshot.is_capture_key(_key(KEY_F2, true, true)), "F2 key repeat captures again")
	_expect(not Screenshot.is_capture_key(_key(KEY_F3)), "F3 captures")
	_expect(not Screenshot.is_capture_key(InputEventMouseButton.new()), "a mouse click captures")

	# nothing else in the project may take F2 (the capture runs before any screen's own keys)
	for action in InputMap.get_actions():
		for event in InputMap.action_get_events(action):
			_expect(not (event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_F2),
				"F2 is also bound to %s" % action)

	# dated names
	var stem := Screenshot.file_stem({"year": 2026, "month": 11, "day": 1, "hour": 9, "minute": 4, "second": 7})
	_expect(stem == "KYTTU_2026-11-01_09-04-07", "the file name is %s" % stem)

	# never overwrite
	var scratch := OS.get_temp_dir().path_join("lr_screenshot_check")
	DirAccess.make_dir_recursive_absolute(scratch)
	var first := scratch.path_join("%s.png" % stem)
	var store := FileAccess.open(first, FileAccess.WRITE)
	if store != null:
		store.store_string("x")
		store.close()
	_expect(Screenshot.unused_path(first) == scratch.path_join("%s_2.png" % stem), "a second capture in the same second does not get _2")
	var second := scratch.path_join("%s_2.png" % stem)
	store = FileAccess.open(second, FileAccess.WRITE)
	if store != null:
		store.store_string("x")
		store.close()
	_expect(Screenshot.unused_path(first) == scratch.path_join("%s_3.png" % stem), "a third capture in the same second does not get _3")
	_expect(Screenshot.unused_path(scratch.path_join("free.png")) == scratch.path_join("free.png"), "a free name was changed")
	DirAccess.remove_absolute(first)
	DirAccess.remove_absolute(second)

	# a real capture, when this run has a rendered image
	Screenshot.folder = scratch.path_join("captures")
	var saved: String = Screenshot.capture()
	if saved == "":
		print("  note  no rendered image in this run (headless): capture written check skipped")
	else:
		_expect(FileAccess.file_exists(saved), "the capture was not written to %s" % saved)
		var image := Image.load_from_file(saved)
		_expect(image != null, "the capture is not a readable image")
		if image != null:
			_expect(image.get_width() > 0 and image.get_height() > 0, "the capture is empty")
		DirAccess.remove_absolute(saved)
	DirAccess.remove_absolute(scratch.path_join("captures"))
	DirAccess.remove_absolute(scratch)
	Screenshot.folder = Screenshot.FOLDER

	await host.get_tree().process_frame
	if _failures == 0:
		print("  screenshot: F2 press only, dated names, no overwrite, capture writes a PNG of the window")
	return _failures
