class_name ModsPanel
extends ScrollContainer

## Settings -> MODS: the "Auto-download mods (at your own risk)" switch (off by default, with its warning), the installed packs
## (name, author, version, size, source) and a button that removes every downloaded pack. Scrolls so it fits small windows; every
## control is a plain Button/Label, so the XR settings panel and the laser work on it unchanged. Data comes from ModPackApi.

var auto_button: Button
var remove_button: Button
var status: Label
var _column: VBoxContainer
var _list: VBoxContainer
var _confirming_remove := false


func _ready() -> void:
	name = "ModsSection"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = VBoxContainer.new()
	_column.custom_minimum_size = Vector2(380, 0)
	_column.add_theme_constant_override("separation", 3)
	add_child(_column)
	_text("AUTO-DOWNLOAD MODS (AT YOUR OWN RISK)", Palette.AMBER)
	auto_button = Button.new()
	auto_button.name = "AutoDownloadButton"
	auto_button.custom_minimum_size = Vector2(0, 16)
	auto_button.add_theme_font_size_override("font_size", 7)
	auto_button.pressed.connect(func() -> void:
		Settings.set_auto_download_mods(not Settings.auto_download_mods)
		_refresh())
	_column.add_child(auto_button)
	var warning := _text(ModPackApi.AUTO_WARNING, Palette.ALERT)
	warning.name = "AutoDownloadWarning"
	_text("INSTALLED MODS", Palette.AMBER)
	_list = VBoxContainer.new()
	_list.name = "ModList"
	_list.add_theme_constant_override("separation", 2)
	_column.add_child(_list)
	remove_button = Button.new()
	remove_button.name = "RemoveDownloadedButton"
	remove_button.custom_minimum_size = Vector2(0, 16)
	remove_button.add_theme_font_size_override("font_size", 7)
	remove_button.pressed.connect(_on_remove_pressed)
	_column.add_child(remove_button)
	status = _text("", Palette.MUTED)
	status.name = "ModsStatus"
	visibility_changed.connect(func() -> void:
		if visible:
			_confirming_remove = false
			_refresh())
	_refresh()


func _text(text: String, tint: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(380, 0)
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", tint)
	_column.add_child(label)
	return label


func _refresh() -> void:
	Palette.style_state_toggle(auto_button, "AUTO-DOWNLOAD", Settings.auto_download_mods, true)
	for child in _list.get_children():
		child.free()
	var packs := ModPackApi.installed()
	if packs.is_empty():
		var empty := Label.new()
		empty.name = "NoModsLabel"
		empty.text = "NO MODS INSTALLED"
		empty.add_theme_font_size_override("font_size", 7)
		empty.add_theme_color_override("font_color", Palette.MUTED)
		_list.add_child(empty)
	for pack in packs:
		_list.add_child(_pack_row(pack))
	var count := ModPackApi.downloaded_count()
	remove_button.disabled = count == 0
	Palette.style_button(remove_button, false, true)
	if _confirming_remove:
		remove_button.text = "PRESS AGAIN TO REMOVE %d DOWNLOADED" % count
	else:
		remove_button.text = "REMOVE DOWNLOADED MODS (%d)" % count


func _pack_row(pack: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.name = "Mod_%s" % pack.get("pack_id", "")
	row.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET, Palette.PANEL_EDGE, 3))
	var box := VBoxContainer.new()
	row.add_child(box)
	var title := Label.new()
	title.name = "ModTitle"
	title.text = "%s  v%s" % [String(pack.get("name", pack.get("pack_id", "?"))).to_upper(), pack.get("version", "?")]
	title.add_theme_font_size_override("font_size", 7)
	title.add_theme_color_override("font_color", Palette.INK)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	box.add_child(title)
	var detail := Label.new()
	detail.name = "ModDetail"
	var source := String(ModPackApi.SOURCE_LABELS.get(String(pack.get("source", "")), String(pack.get("source", "?")).to_upper()))
	detail.text = "BY %s  //  %s  //  %s" % [String(pack.get("author", "UNKNOWN")).to_upper(),
		ModPackApi.format_size(int(pack.get("size", 0))), source]
	detail.add_theme_font_size_override("font_size", 6)
	detail.add_theme_color_override("font_color", Palette.MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.custom_minimum_size = Vector2(360, 0)
	box.add_child(detail)
	return row


func _on_remove_pressed() -> void:
	if not _confirming_remove:
		_confirming_remove = true
		_refresh()
		return
	_confirming_remove = false
	var removed := ModPackApi.remove_downloaded()
	_refresh()
	status.text = "REMOVED %d DOWNLOADED MOD%s" % [removed, "" if removed == 1 else "S"]
