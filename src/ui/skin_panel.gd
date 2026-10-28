class_name SkinPanel
extends Control

## Settings -> SKIN: pick a 64x64 PNG skin, see it on a rotating mannequin, apply it, reset to the default, or save the template to
## paint over. Everything goes through PlayerSkin (validation, cache, the active hash in Settings); this is only the UI.
## File picking: the platform's native dialog (desktop, Android and iOS document pickers) when the display server has one,
## else Godot's own FileDialog (Quest and anything else).

const PREVIEW_SIZE := Vector2i(150, 150)
const SPIN_DEGREES_PER_SECOND := 28.0
const TEMPLATE_NAME := "lastroute_skin_template.png"

var status_label: Label
var _preview_model: Node3D
var _spin := 0.0
var _pending: Dictionary = {}    # a picked, validated skin not applied yet
var _fallback_dialog: FileDialog
var _pick_button: Button
var _apply_button: Button
var _reset_button: Button
var _template_button: Button


func _ready() -> void:
	name = "SkinSection"
	var container := SubViewportContainer.new()
	container.name = "SkinPreview"
	container.stretch = true
	container.position = Vector2.ZERO
	container.size = Vector2(PREVIEW_SIZE)
	add_child(container)
	var viewport := SubViewport.new()
	viewport.size = PREVIEW_SIZE
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(viewport)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.0, 2.9)
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 38
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	viewport.add_child(light)
	var model := ModelSlot.instantiate(PlayerModels.SCENE)
	if model != null:
		_preview_model = model
		viewport.add_child(model)
		var idle := ModelSlot.find_animation_player(model)
		if idle != null and idle.has_animation("idle"):
			idle.play("idle")
		_show(PlayerSkin.active_texture())

	var column := VBoxContainer.new()
	column.position = Vector2(PREVIEW_SIZE.x + 12, 0)
	column.size = Vector2(size.x - PREVIEW_SIZE.x - 12 if size.x > PREVIEW_SIZE.x + 12 else 230, PREVIEW_SIZE.y)
	column.add_theme_constant_override("separation", 3)
	add_child(column)
	_pick_button = _button(column, "PICK A PNG SKIN", _pick)
	_apply_button = _button(column, "APPLY", _apply)
	_reset_button = _button(column, "RESET TO DEFAULT", _reset)
	_template_button = _button(column, "SAVE TEMPLATE", _save_template)
	status_label = Label.new()
	status_label.name = "SkinStatus"
	status_label.add_theme_font_size_override("font_size", 6)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(228, 40)
	column.add_child(status_label)
	_refresh()


func _button(parent: Node, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 7)
	button.custom_minimum_size = Vector2(0, 16)
	button.focus_mode = Control.FOCUS_ALL
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _process(delta: float) -> void:
	if _preview_model != null and is_visible_in_tree():
		_spin = fmod(_spin + SPIN_DEGREES_PER_SECOND * delta, 360.0)
		_preview_model.rotation_degrees.y = _spin


func _show(texture: Texture2D) -> void:
	if _preview_model != null:
		PlayerSkin.apply(_preview_model, texture)


func _refresh() -> void:
	_apply_button.disabled = _pending.is_empty()
	_reset_button.disabled = Settings.skin_hash.is_empty() and _pending.is_empty()
	if status_label != null and status_label.text.is_empty():
		status_label.text = "Your skin: %s" % ("custom" if not Settings.skin_hash.is_empty() else "default")


func _say(text: String) -> void:
	status_label.text = text


# --------------------------------------------------------------------------------------------------- actions

func _pick() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Choose a skin", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE,
			PackedStringArray(["*.png"]), _on_native_picked)
		return
	_fallback(FileDialog.FILE_MODE_OPEN_FILE, _on_fallback_picked)


func _on_native_picked(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok and not paths.is_empty():
		pick_path(paths[0])


func _on_fallback_picked(path: String) -> void:
	pick_path(path)


## Loads, validates and previews a file (the UI's pick, also what the validator drives).
func pick_path(path: String) -> Dictionary:
	var result := PlayerSkin.validate(PlayerSkin.read_file(path))
	if not bool(result["ok"]):
		_pending = {}
		_say("Not applied: %s." % String(result["reason"]))
	else:
		_pending = result
		_show(ImageTexture.create_from_image(result["image"]))
		_say("Preview only. Press APPLY to wear it.")
	_refresh()
	return result


func _apply() -> void:
	if _pending.is_empty():
		return
	var result := PlayerSkin.import_bytes(_pending["png"])
	if bool(result["ok"]):
		_pending = {}
		_say("Skin applied.")
	else:
		_say("Not applied: %s." % String(result["reason"]))
	_refresh()


func _reset() -> void:
	_pending = {}
	PlayerSkin.reset_active()
	_show(PlayerSkin.default_texture())
	_say("Back to the default skin.")
	_refresh()


func _save_template() -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Save the skin template", "", TEMPLATE_NAME, false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
			PackedStringArray(["*.png"]), func(ok: bool, paths: PackedStringArray, _f: int) -> void:
				if ok and not paths.is_empty():
					write_template(paths[0]))
		return
	var downloads := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	write_template("%s/%s" % [downloads if not downloads.is_empty() else "user://", TEMPLATE_NAME])


func write_template(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_say("The template could not be saved to %s." % path)
		return false
	file.store_buffer(PlayerSkin.template_png())
	file.close()
	_say("Template saved: %s" % path)
	return true


func _fallback(mode: int, handler: Callable) -> void:
	if _fallback_dialog == null:
		_fallback_dialog = FileDialog.new()
		_fallback_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_fallback_dialog.filters = PackedStringArray(["*.png ; PNG skin"])
		_fallback_dialog.use_native_dialog = false
		add_child(_fallback_dialog)
	for connection in _fallback_dialog.file_selected.get_connections():
		_fallback_dialog.file_selected.disconnect(connection["callable"])
	_fallback_dialog.file_mode = mode
	_fallback_dialog.file_selected.connect(handler)
	_fallback_dialog.popup_centered(Vector2i(360, 220))
