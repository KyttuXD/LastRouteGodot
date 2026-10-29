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
var url_edit: LineEdit
var name_edit: LineEdit
var peer_list: OptionButton
var copyable_check: CheckBox
var _copy_button: Button
var _arms_button: Button
var _busy := false
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
	camera.position = Vector3(0, 1.0, 2.9) * PlayerModels.SCALE   # framed for the runner's size, so the picture is the same
	camera.rotation_degrees = Vector3(-3, 0, 0)
	camera.fov = 38
	viewport.add_child(camera)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 30, 0)
	viewport.add_child(light)
	var model := ModelSlot.instantiate(PlayerModels.SCENE)
	if model != null:
		_preview_model = model
		model.scale = Vector3.ONE * PlayerModels.SCALE   # the 1.60 m runner, not the 1.78 m authored mannequin
		viewport.add_child(model)
		var idle := ModelSlot.find_animation_player(model)
		if idle != null and idle.has_animation("idle"):
			idle.play("idle")
		_show(PlayerSkin.active_texture())

	var column := VBoxContainer.new()
	column.position = Vector2(PREVIEW_SIZE.x + 10, 0)
	column.size = Vector2(240, 170)
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	column.add_child(grid)
	_pick_button = _button(grid, "PICK A PNG", _pick)
	_apply_button = _button(grid, "APPLY", _apply)
	_reset_button = _button(grid, "DEFAULT", _reset)
	_template_button = _button(grid, "TEMPLATE", _save_template)
	url_edit = _line(column, "https:// link to a 64x64 PNG skin", "FROM URL", _from_url)
	name_edit = _line(column, "Minecraft username", "FROM MC NAME", _from_minecraft)
	var copy_row := HBoxContainer.new()
	copy_row.add_theme_constant_override("separation", 2)
	column.add_child(copy_row)
	peer_list = OptionButton.new()
	peer_list.name = "CopyPeerList"
	peer_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	peer_list.add_theme_font_size_override("font_size", 7)
	peer_list.custom_minimum_size = Vector2(0, 16)
	copy_row.add_child(peer_list)
	_copy_button = _button(copy_row, "COPY SKIN", _copy_peer)
	copyable_check = CheckBox.new()
	copyable_check.text = "OTHERS MAY COPY"
	copyable_check.add_theme_font_size_override("font_size", 6)
	copyable_check.button_pressed = Settings.skin_copyable
	copyable_check.toggled.connect(Settings.set_skin_copyable)
	var options_row := HBoxContainer.new()
	options_row.add_theme_constant_override("separation", 4)
	column.add_child(options_row)
	options_row.add_child(copyable_check)
	_arms_button = _button(options_row, _arms_text(), _cycle_arms)
	status_label = Label.new()
	status_label.name = "SkinStatus"
	status_label.add_theme_font_size_override("font_size", 6)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(238, 26)
	column.add_child(status_label)
	visibility_changed.connect(_refresh_peers)
	_refresh()
	_refresh_peers()


func _line(parent: Node, hint: String, go_text: String, handler: Callable) -> LineEdit:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	parent.add_child(row)
	var edit := LineEdit.new()
	edit.placeholder_text = hint
	edit.max_length = PlayerSkin.MAX_URL_LENGTH
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.add_theme_font_size_override("font_size", 7)
	edit.custom_minimum_size = Vector2(0, 16)
	edit.text_submitted.connect(func(_t: String) -> void: handler.call())
	row.add_child(edit)
	_button(row, go_text, handler)
	return edit


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


func _show(texture: Texture2D, slim: bool = Settings.effective_slim()) -> void:
	if _preview_model != null:
		PlayerSkin.set_arms(_preview_model, slim)
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
		_show(ImageTexture.create_from_image(result["image"]), _slim_for(result))
		_say("Preview only. Press APPLY to wear it (%s arms)." % ("slim" if _slim_for(result) else "classic"))
	_refresh()
	return result


## Every source ends the same way: a validated image becomes the preview, and APPLY stores it, wears it and uploads it.
func _preview(result: Dictionary) -> Dictionary:
	if not bool(result["ok"]):
		_pending = {}
		_say("Not applied: %s." % String(result["reason"]))
	else:
		_pending = result
		_show(ImageTexture.create_from_image(result["image"]), _slim_for(result))
		_say("Preview only. Press APPLY to wear it (%s arms)." % ("slim" if _slim_for(result) else "classic"))
	_refresh()
	return result


func _from_url() -> Dictionary:
	if _busy:
		return {}
	_busy = true
	_say("Downloading...")
	var result: Dictionary = await Backend.skin_sync.skin_from_url(url_edit.text)
	_busy = false
	return _preview(result)


func _from_minecraft() -> Dictionary:
	if _busy:
		return {}
	_busy = true
	_say("Looking up %s..." % name_edit.text.strip_edges())
	var result: Dictionary = await Backend.skin_sync.skin_from_minecraft(name_edit.text)
	_busy = false
	return _preview(result)


func _refresh_peers() -> void:
	if peer_list == null:
		return
	peer_list.clear()
	for peer in PlayerSkin.copyable_peers():
		peer_list.add_item(String(peer["name"]))
		peer_list.set_item_metadata(peer_list.item_count - 1, String(peer["hash"]))
	if peer_list.item_count == 0:
		peer_list.add_item("(no one to copy)")
		peer_list.disabled = true
	else:
		peer_list.disabled = false
	_copy_button.disabled = peer_list.disabled


## COPY SKIN: the chosen peer's skin (from the in-memory cache) goes to the preview, then APPLY like any other source.
func _copy_peer() -> Dictionary:
	if peer_list.disabled or peer_list.selected < 0:
		return {}
	var hash := String(peer_list.get_item_metadata(peer_list.selected))
	var texture := PlayerSkin.peer_texture(hash)
	var result := PlayerSkin.validate(texture.get_image().save_png_to_buffer()) if texture != null else {"ok": false, "reason": "that skin is not loaded"}
	if bool(result["ok"]):
		for peer in PlayerSkin.copyable_peers():
			if String(peer["hash"]) == hash:
				result["slim"] = bool(peer["slim"])   # the style comes from the owner's state; the pixels were normalised
	return _preview(result)


## The arm style a picked skin would be worn with: the player's override, else what the skin itself says.
func _slim_for(result: Dictionary) -> bool:
	match Settings.skin_arms:
		"slim":
			return true
		"classic":
			return false
	return bool(result.get("slim", false))


func _cycle_arms() -> void:
	var modes := ["auto", "classic", "slim"]
	Settings.set_skin_arms(modes[(modes.find(Settings.skin_arms) + 1) % modes.size()])
	_arms_button.text = _arms_text()
	_show(PlayerSkin.default_texture() if _pending.is_empty() and Settings.skin_hash.is_empty() else (ImageTexture.create_from_image(_pending["image"]) if not _pending.is_empty() else PlayerSkin.active_texture()),
		_slim_for(_pending) if not _pending.is_empty() else Settings.effective_slim())


func _arms_text() -> String:
	return "ARMS: %s" % Settings.skin_arms.to_upper()


func _apply() -> void:
	if _pending.is_empty():
		return
	var result := PlayerSkin.apply_result(_pending)
	if bool(result["ok"]):
		_pending = {}
		Settings.set_skin_pending_upload(true)   # cleared when the account holds it; a sign-in before that uploads it, not replaces it
		Backend.skin_sync.sync_own()
		_say("Skin applied." if Backend.signed_in() else "Skin applied (only you see it; sign in to share it).")
	else:
		_say("Not applied: %s." % String(result["reason"]))
	_refresh()


func _reset() -> void:
	_pending = {}
	PlayerSkin.reset_active()
	Backend.skin_sync.clear_own()
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
