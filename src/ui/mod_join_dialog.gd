class_name ModJoinDialog
extends Control

## Joining a private room whose host runs mod packs. begin(host_packs) compares the host's list with the installed packs and shows
## one of: nothing (identical, join_allowed fires), the CONFIRM list (each missing pack's name, author, size, hash + the own-risk
## warning; DOWNLOAD & JOIN / CANCEL, "don't ask again" turns on auto-download), the DOWNLOAD progress bar, an ERROR, or PACKS DIFFER
## (public/ranked room with a modded host). With Settings.auto_download_mods on, confirm is skipped and the
## own-risk notice shows once per session. The guest never joins with a partial pack set: join_allowed only fires when every pack is in.

signal join_allowed
signal cancelled

enum Stage { HIDDEN, CONFIRM, DOWNLOADING, ERROR, DIFFER }

static var _notice_shown := false

var stage := Stage.HIDDEN
var title: Label
var body: Label
var list_box: VBoxContainer
var progress: ProgressBar
var progress_label: Label
var ask_again: CheckButton
var confirm_button: Button
var cancel_button: Button
var _panel: PanelContainer
var _scroll: ScrollContainer
var _pending: Array = []


func _ready() -> void:
	name = "ModJoinDialog"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Built on first use, in the palette of the game that is open then, and not at all for the many joins with no mods.
func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = Palette.SCRIM
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	_panel = PanelContainer.new()
	_panel.name = "ModJoinPanel"
	_panel.custom_minimum_size = Vector2(300, 0)
	_panel.add_theme_stylebox_override("panel", Palette.panel_box(Palette.PANEL, Palette.PANEL_EDGE, 8))
	centre.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	_panel.add_child(column)
	title = _label(column, "", Palette.AMBER, 8)
	title.name = "ModJoinTitle"
	body = _label(column, "", Palette.BODY, 7)
	body.name = "ModJoinBody"
	_scroll = ScrollContainer.new()
	_scroll.name = "ModJoinScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.custom_minimum_size = Vector2(284, 60)
	column.add_child(_scroll)
	list_box = VBoxContainer.new()
	list_box.name = "ModJoinList"
	list_box.add_theme_constant_override("separation", 2)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(list_box)
	progress = ProgressBar.new()
	progress.name = "ModJoinProgress"
	progress.custom_minimum_size = Vector2(0, 8)
	progress.show_percentage = false
	column.add_child(progress)
	progress_label = _label(column, "", Palette.MUTED, 6)
	progress_label.name = "ModJoinProgressLabel"
	ask_again = CheckButton.new()
	ask_again.name = "ModJoinAskAgain"
	ask_again.text = "DON'T ASK AGAIN (TURNS ON AUTO-DOWNLOAD)"
	ask_again.add_theme_font_size_override("font_size", 6)
	column.add_child(ask_again)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	column.add_child(buttons)
	confirm_button = _button(buttons, "DOWNLOAD & JOIN", true)
	confirm_button.name = "ModJoinConfirm"
	confirm_button.pressed.connect(_on_confirm)
	cancel_button = _button(buttons, "CANCEL", false)
	cancel_button.name = "ModJoinCancel"
	cancel_button.pressed.connect(_on_cancel)


func _label(parent: Node, text: String, tint: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size = Vector2(284, 0)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", tint)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 16)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(button, primary, true)
	parent.add_child(button)
	return button


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()


## Entry point from the join handshake. private_room false (public/ranked) refuses any pack difference.
func begin(host_packs: Array, private_room: bool = true) -> void:
	var diff := ModPackApi.diff(host_packs, ModPackApi.installed())
	var to_get: Array = diff["missing"] + diff["different"]
	# A guest loads exactly the host's packs, so installed packs the host does not use change nothing and never refuse a join.
	if not private_room and not host_packs.is_empty():
		show_differ(host_packs, ModPackApi.installed())
		return
	if to_get.is_empty():
		join_allowed.emit()
		return
	_pending = to_get
	if Settings.auto_download_mods:
		_start_download()
	else:
		_show_confirm()


func _open(new_stage: Stage, heading: String, text: String) -> void:
	if _panel == null:
		_build()
	stage = new_stage
	title.text = heading
	body.text = text
	visible = true
	progress.visible = new_stage == Stage.DOWNLOADING
	progress_label.visible = new_stage == Stage.DOWNLOADING
	ask_again.visible = new_stage == Stage.CONFIRM
	confirm_button.visible = new_stage == Stage.CONFIRM
	_scroll.visible = new_stage in [Stage.CONFIRM, Stage.DIFFER]
	cancel_button.text = "CANCEL" if new_stage in [Stage.CONFIRM, Stage.DOWNLOADING] else "CLOSE"
	for child in list_box.get_children():
		child.free()
	cancel_button.grab_focus.call_deferred()


func _pack_line(pack: Dictionary, prefix: String = "") -> Label:
	var line := Label.new()
	line.text = "%s%s v%s  BY %s  //  %s  //  #%s" % [prefix, String(pack.get("name", pack.get("pack_id", "?"))).to_upper(),
		pack.get("version", "?"), String(pack.get("author", "UNKNOWN")).to_upper(),
		ModPackApi.format_size(int(pack.get("size", 0))), ModPackApi.short_hash(String(pack.get("sha256", "")))]
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.custom_minimum_size = Vector2(270, 0)
	line.add_theme_font_size_override("font_size", 6)
	line.add_theme_color_override("font_color", Palette.INK)
	list_box.add_child(line)
	return line


func _show_confirm() -> void:
	_open(Stage.CONFIRM, "THIS ROOM USES MODS", ModPackApi.OWN_RISK_WARNING)
	body.add_theme_color_override("font_color", Palette.ALERT)
	var total := 0
	for pack in _pending:
		_pack_line(pack)
		total += int(pack.get("size", 0))
	confirm_button.text = "DOWNLOAD & JOIN (%s)" % ModPackApi.format_size(total)
	ask_again.button_pressed = false


func _start_download() -> void:
	var notice := "" if _notice_shown else ModPackApi.OWN_RISK_WARNING
	_notice_shown = true
	_open(Stage.DOWNLOADING, "DOWNLOADING MODS", notice)
	body.add_theme_color_override("font_color", Palette.BODY)
	progress.value = 0
	progress_label.text = "STARTING..."
	ModPackApi.download(_pending, set_progress, _on_download_done)


func set_progress(done: int, total: int, pack_name: String) -> void:
	if stage != Stage.DOWNLOADING:
		return
	progress.max_value = maxi(total, 1)
	progress.value = clampi(done, 0, maxi(total, 1))
	progress_label.text = "%s  %s / %s" % [pack_name.to_upper(), ModPackApi.format_size(done), ModPackApi.format_size(total)]


func _on_download_done(ok: bool, reason: String) -> void:
	if stage != Stage.DOWNLOADING:
		return
	if ok:
		visible = false
		stage = Stage.HIDDEN
		join_allowed.emit()
	else:
		show_error(reason)


func show_error(reason: String) -> void:
	_open(Stage.ERROR, "COULD NOT JOIN: MODS", "%s\nYOU WERE NOT CONNECTED. NO PARTIAL MODS WERE KEPT." % \
		(reason if not reason.is_empty() else "THE DOWNLOAD FAILED"))
	body.add_theme_color_override("font_color", Palette.ALERT)


## The join was refused because the pack sets differ: list what the host runs and what this player has that the host does not.
func show_differ(host_packs: Array, local_packs: Array) -> void:
	var diff := ModPackApi.diff(host_packs, local_packs)
	_open(Stage.DIFFER, "PACKS DIFFER", "THIS ROOM'S MODS DO NOT MATCH YOURS, SO YOU CANNOT JOIN YET.")
	body.add_theme_color_override("font_color", Palette.ALERT)
	for pack in diff["missing"]:
		_pack_line(pack, "MISSING: ")
	for pack in diff["different"]:
		_pack_line(pack, "OTHER VERSION: ")
	if host_packs.is_empty():
		body.text += "\nTHE HOST RUNS NO MODS."


func _on_confirm() -> void:
	if stage != Stage.CONFIRM:
		return
	if ask_again.button_pressed:
		Settings.set_auto_download_mods(true)
	_start_download()


func _on_cancel() -> void:
	var was := stage
	visible = false
	stage = Stage.HIDDEN
	if was != Stage.HIDDEN:
		cancelled.emit()
