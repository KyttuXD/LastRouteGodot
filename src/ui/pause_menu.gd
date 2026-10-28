class_name PauseMenu
extends CanvasLayer

## The pause overlay, shared by both 3D modes.
##
## ESC used to drop you straight to the main menu with no confirmation, which
## in a live route is a way to lose it by reaching for the wrong
## key. Now it stops the game and asks.
##
## Two ways in, because the modes want different things:
##
##   * Last Route taps ESC. It is a co-op mode, so pausing has to be quick.
##   * Office Mode HOLDS ESC for three seconds, with a meter while you do. It
##     is singleplayer by design, so nothing is waiting on you -- and the whole
##     mode is about not being able to step away, which a one-key escape hatch
##     would undercut.
##   * A solo route window that loses OS focus opens the same overlay ESC does, when Settings.pause_on_focus_loss is
##     on (release builds by default). Never in a room, public route or with other players, never while a text field
##     or admin overlay has the keyboard; held keys are released either way.
##     Playtests kept dying to Gray Void while a terminal had the keyboard.
##     Focus coming back does not resume -- RETURN or ESC still has to. Title,
##     staging, Office hold-to-pause, and a locked-out escape struggle do not.
##
## Built in code rather than as a .tscn on purpose: every colour comes from
## Palette, so restyling the game is one file rather than a hunt through scene
## files for hardcoded values.

signal resumed
signal abandoned
signal opened

## How long ESC must be held in hold-to-pause mode.
const HOLD_SECONDS := 3.0

## Tap to pause, or hold. Office Mode sets this false.
@export var tap_to_pause := true
## Offline and Office Mode stop the SceneTree. In a live co-op room, opening a
## local menu must not freeze the host's hunter simulation for every guest.
## The mode freezes only that local controller instead.
@export var pauses_tree := true
## What the abandon button says. "ROUTE" for the maze, "SHIFT" for the office.
@export var abandon_label := "ABANDON ROUTE"
## What leaving actually costs, spelled out on the confirmation. Co-op ends the
## run for the whole room, which is not something to discover afterwards.
@export var abandon_warning := "This ends the run for everyone in the room and returns to staging."

var _open := false
var _confirming := false
var _held := 0.0
## Optional gameplay-owned close handler. It returns true when ESC closed a
## higher-priority overlay, preventing the same keypress from opening pause.
var dismiss_overlay: Callable
## Gameplay supplies persistence/statistics boundaries. Keeping storage out of
## this presentation class lets Office/legacy modes omit saves cleanly while
## Infinite Route exposes the complete local archive.
var save_slots_source: Callable
var save_new_request: Callable
var save_overwrite_request: Callable
var save_load_request: Callable
var save_rename_request: Callable
var save_delete_request: Callable
var statistics_source: Callable

var _scrim: ColorRect
var _panel: PanelContainer
var _confirm: PanelContainer
var _hold_box: PanelContainer
var _hold_fill: ColorRect
var _resume_button: Button
var _abandon_button: Button
var _pause_view: VBoxContainer
var _saves_view: VBoxContainer
var _statistics_view: VBoxContainer
var _save_list: VBoxContainer
var _save_name: LineEdit
var _save_status: Label
var _statistics_grid: GridContainer
var _share_code: Label
var _share_seed: Label
var _copy_button: Button
var _copy_status: Label
var _selected_save_id := ""
var _dossier_modal: ColorRect
var _dossier_name: Label
var _dossier_status: Label
var _dossier_behavior: Label
var _dossier_counter: Label
var _dossier_gimmick_heading: Label
var _dossier_gimmick: Label
var _dossier_stats: Label
## True after this menu has seen the window/application focused. Headless
## validate never has a real focused game window; reacting to a startup
## FOCUS_OUT there would open pause under every suite that instantiates a
## route. Only a focused -> unfocused transition calls open().
var _app_focused := false


func _ready() -> void:
	# The tree is paused while this is up, so it has to keep running.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 100
	_build()
	_set_open(false)
	_watch_window_focus()


func _exit_tree() -> void:
	_unwatch_window_focus()


func is_open() -> bool:
	return _open


func _build() -> void:
	_scrim = ColorRect.new()
	_scrim.color = Palette.SCRIM
	_scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scrim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_scrim)

	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.PANEL_EDGE, 16))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_panel.custom_minimum_size = Vector2(380, 236)
	_panel.offset_left = -190
	_panel.offset_right = 190
	_panel.offset_top = -118
	_panel.offset_bottom = 118
	add_child(_panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", Palette.GAP)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = Palette.track("SIGNAL SUSPENDED")
	Palette.style_label(eyebrow, Palette.AMBER, 7)
	column.add_child(eyebrow)

	var title := Label.new()
	title.name = "PauseTitle"
	title.text = "PAUSED"
	Palette.style_label(title, Palette.INK, 22)
	Palette.style_title(title)
	column.add_child(title)

	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 4)
	column.add_child(tabs)
	for entry in [["PAUSE", "pause"], ["SAVES", "saves"],
			["STATISTICS", "statistics"]]:
		var tab := Button.new()
		tab.text = String(entry[0])
		tab.focus_mode = Control.FOCUS_ALL
		tab.custom_minimum_size = Vector2(92, 18)
		tab.add_theme_font_size_override("font_size", 8)
		Palette.style_button(tab, String(entry[1]) == "pause")
		tab.pressed.connect(_set_section.bind(String(entry[1])))
		tabs.add_child(tab)

	_pause_view = VBoxContainer.new()
	_pause_view.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_view.add_theme_constant_override("separation", Palette.GAP)
	_pause_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_pause_view)

	_resume_button = Button.new()
	_resume_button.text = "RETURN"
	_resume_button.focus_mode = Control.FOCUS_ALL
	_resume_button.custom_minimum_size = Vector2(74, 18)
	_resume_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	Palette.style_button(_resume_button, true)
	_resume_button.pressed.connect(close)
	_pause_view.add_child(_resume_button)

	var dossier_button := Button.new()
	dossier_button.text = "HUNTER DOSSIER"
	dossier_button.focus_mode = Control.FOCUS_ALL
	dossier_button.custom_minimum_size = Vector2(112, 18)
	dossier_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dossier_button.add_theme_font_size_override("font_size", 8)
	Palette.style_button(dossier_button, false)
	dossier_button.pressed.connect(_open_dossier)
	_pause_view.add_child(dossier_button)

	_abandon_button = Button.new()
	_abandon_button.text = abandon_label
	_abandon_button.focus_mode = Control.FOCUS_ALL
	_abandon_button.custom_minimum_size = Vector2(88, 14)
	_abandon_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_abandon_button.add_theme_font_size_override("font_size", 8)
	Palette.style_button(_abandon_button, false)
	_abandon_button.pressed.connect(_ask_abandon)
	_pause_view.add_child(_abandon_button)

	_build_saves_view(column)
	_build_statistics_view(column)

	_build_confirm()
	_build_hold_prompt()
	_set_section("pause")


func _build_saves_view(parent: VBoxContainer) -> void:
	_saves_view = VBoxContainer.new()
	_saves_view.name = "PauseSaves"
	_saves_view.add_theme_constant_override("separation", 5)
	_saves_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_saves_view)

	var help := Label.new()
	help.text = "ROUTE ARCHIVES // HOST SAVES SHARED PROGRESS; LOAD WHILE SOLO"
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Palette.style_label(help, Palette.MUTED, 7)
	_saves_view.add_child(help)

	var create_row := HBoxContainer.new()
	create_row.name = "SaveCreateRow"
	create_row.add_theme_constant_override("separation", 4)
	_saves_view.add_child(create_row)

	_save_name = LineEdit.new()
	_save_name.name = "SaveNameInput"
	_save_name.placeholder_text = "SAVE NAME"
	_save_name.max_length = 40
	_save_name.custom_minimum_size = Vector2(0, 22)
	_save_name.text_direction = Control.TEXT_DIRECTION_LTR
	_save_name.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_save_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.style_line_edit(_save_name)
	create_row.add_child(_save_name)
	var save_new_button := _save_action_button("SAVE NEW", _save_new, true)
	save_new_button.name = "SaveNew"
	save_new_button.custom_minimum_size = Vector2(92, 22)
	create_row.add_child(save_new_button)

	var scroll := ScrollContainer.new()
	scroll.name = "SaveSlotScroll"
	scroll.custom_minimum_size = Vector2(0, 112)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_saves_view.add_child(scroll)
	_save_list = VBoxContainer.new()
	_save_list.name = "SaveSlotList"
	_save_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_save_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_save_list)

	_save_status = Label.new()
	_save_status.name = "SaveStatus"
	_save_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	Palette.style_label(_save_status, Palette.MUTED, 7)
	_saves_view.add_child(_save_status)


func _build_statistics_view(parent: VBoxContainer) -> void:
	_statistics_view = VBoxContainer.new()
	_statistics_view.name = "PauseStatistics"
	_statistics_view.add_theme_constant_override("separation", 6)
	_statistics_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_statistics_view)
	var heading := Label.new()
	heading.text = Palette.track("CURRENT RUN")
	Palette.style_label(heading, Palette.AMBER, 8)
	_statistics_view.add_child(heading)
	_statistics_view.add_child(_build_share_block())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_statistics_view.add_child(scroll)
	_statistics_grid = GridContainer.new()
	_statistics_grid.name = "PauseStatisticsGrid"
	_statistics_grid.columns = 2
	_statistics_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_statistics_grid.add_theme_constant_override("h_separation", 18)
	_statistics_grid.add_theme_constant_override("v_separation", 5)
	scroll.add_child(_statistics_grid)


func _build_share_block() -> Control:
	var box := PanelContainer.new()
	box.name = "PauseShare"
	box.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.INSET, Palette.ACCENT_DEEP, 6))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 2)
	box.add_child(stack)
	var eyebrow := Label.new()
	eyebrow.text = Palette.track("ROUTE SIGNAL")
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Palette.style_label(eyebrow, Palette.AMBER, 6)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stack.add_child(eyebrow)
	_share_code = Label.new()
	_share_code.name = "PauseShareCode"
	_share_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Palette.style_label(_share_code, Palette.ACCENT, 9)
	_share_code.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stack.add_child(_share_code)
	_share_seed = Label.new()
	_share_seed.name = "PauseShareSeed"
	_share_seed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_share_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Palette.style_label(_share_seed, Palette.INK, 8)
	_share_seed.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	stack.add_child(_share_seed)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	stack.add_child(row)
	_copy_button = Button.new()
	_copy_button.name = "PauseCopyRoute"
	_copy_button.text = "COPY ROUTE"
	_copy_button.focus_mode = Control.FOCUS_ALL
	_copy_button.custom_minimum_size = Vector2(88, 16)
	_copy_button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(_copy_button, true)
	_copy_button.pressed.connect(copy_route_share)
	row.add_child(_copy_button)
	_copy_status = Label.new()
	_copy_status.name = "PauseCopyStatus"
	_copy_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_copy_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	Palette.style_label(_copy_status, Palette.MUTED, 7)
	_copy_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	row.add_child(_copy_status)
	return box


## What a host would actually paste: the joinable room code and the live
## route seed, as one string. Missing halves are omitted rather than faked.
static func route_share_text(code: String, seed: String) -> String:
	var room := code.strip_edges()
	var route := seed.strip_edges()
	if not room.is_empty() and not route.is_empty():
		return "ROOM %s // SEED %s" % [room, route]
	if not route.is_empty():
		return route
	if not room.is_empty():
		return "ROOM %s" % room
	return ""


func copy_route_share() -> String:
	var text := route_share_text(RoomState.code, RoomState.seed_text)
	if text.is_empty():
		_set_copy_status("NO ROUTE SIGNAL TO COPY", false)
		return ""
	DisplayServer.clipboard_set(text)
	_set_copy_status("COPIED TO CLIPBOARD", true)
	return text


func _set_copy_status(message: String, ok: bool) -> void:
	if _copy_status == null:
		return
	_copy_status.text = message
	_copy_status.add_theme_color_override("font_color",
		Palette.STABLE if ok else Palette.ALERT)


func _refresh_share() -> void:
	var room := RoomState.code.strip_edges()
	var route := RoomState.seed_text.strip_edges()
	if _share_code != null:
		_share_code.text = ("ROOM %s" % room) if not room.is_empty() \
			else "ROOM UNASSIGNED"
	if _share_seed != null:
		_share_seed.text = route if not route.is_empty() \
			else "ROUTE SIGNAL UNASSIGNED"
	if _copy_button != null:
		_copy_button.disabled = route_share_text(room, route).is_empty()


func _save_action_button(caption: String, action: Callable,
		primary: bool = false) -> Button:
	var button := Button.new()
	button.text = caption
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.add_theme_font_size_override("font_size", 7)
	Palette.style_button(button, primary)
	button.pressed.connect(action)
	return button


func _set_section(section: String) -> void:
	if _pause_view == null:
		return
	_pause_view.visible = section == "pause"
	_saves_view.visible = section == "saves"
	_statistics_view.visible = section == "statistics"
	if section == "saves":
		_refresh_saves()
		_save_name.grab_focus()
	elif section == "statistics":
		_refresh_share()
		_refresh_statistics()


func _refresh_saves() -> void:
	if _save_list == null:
		return
	for child in _save_list.get_children():
		child.queue_free()
	var slots: Array = save_slots_source.call() if save_slots_source.is_valid() else []
	if slots.is_empty():
		var empty := Label.new()
		empty.text = "NO LOCAL SAVES"
		Palette.style_label(empty, Palette.MUTED, 8)
		_save_list.add_child(empty)
		_selected_save_id = ""
		return
	var selected_found := false
	for value in slots:
		var slot: Dictionary = value
		var slot_id := String(slot.get("slot_id", ""))
		var selected := slot_id == _selected_save_id
		var entry := VBoxContainer.new()
		entry.name = "SaveEntry_%s" % slot_id
		entry.add_theme_constant_override("separation", 2)
		entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_save_list.add_child(entry)
		var row := Button.new()
		row.name = "SaveSlot_%s" % slot_id
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.text = "%s  //  LEVEL %+d  //  %s  //  %s" % [
			String(slot.get("name", "ROUTE")), int(slot.get("level", 0)),
			String(slot.get("difficulty", "STANDARD")),
			_format_duration(float(slot.get("elapsed_seconds", 0.0)))]
		row.tooltip_text = "SAVED %s" % _format_save_time(int(slot.get("saved_at", 0)))
		row.add_theme_font_size_override("font_size", 7)
		Palette.style_button(row, selected)
		row.pressed.connect(_select_save.bind(slot_id,
			String(slot.get("name", "ROUTE"))))
		entry.add_child(row)
		if selected:
			var actions := HBoxContainer.new()
			actions.name = "SaveSlotActions_%s" % slot_id
			actions.add_theme_constant_override("separation", 3)
			entry.add_child(actions)
			for action_entry in [
					["LOAD", _save_load, true],
					["OVERWRITE", _save_overwrite, false],
					["RENAME", _save_rename, false],
					["DELETE", _save_delete, false]]:
				var action_button := _save_action_button(String(action_entry[0]),
					action_entry[1] as Callable, bool(action_entry[2]))
				action_button.name = "SaveSlot%s_%s" % [
					String(action_entry[0]).capitalize().replace(" ", ""), slot_id]
				actions.add_child(action_button)
		selected_found = selected_found or selected
	if not selected_found:
		_selected_save_id = ""


func _select_save(slot_id: String, display_name: String) -> void:
	_selected_save_id = slot_id
	_save_name.text = display_name
	_save_name.caret_column = _save_name.text.length()
	_refresh_saves()


func _save_new() -> void:
	_save_call(save_new_request, [_save_name.text])


func _save_overwrite() -> void:
	_save_call(save_overwrite_request, [_selected_save_id], true)


func _save_load() -> void:
	if _selected_save_id.is_empty():
		_set_save_status("SELECT A SAVE SLOT", false)
		return
	if not save_load_request.is_valid():
		_set_save_status("SAVES ARE UNAVAILABLE IN THIS MODE", false)
		return
	var result = save_load_request.call(_selected_save_id)
	if result is Dictionary:
		_set_save_status(String(result.get("message", "SAVE LOAD FAILED")),
			bool(result.get("ok", false)))


func _save_rename() -> void:
	_save_call(save_rename_request, [_selected_save_id, _save_name.text], true)


func _save_delete() -> void:
	_save_call(save_delete_request, [_selected_save_id], true)


func _save_call(action: Callable, arguments: Array,
		requires_selection: bool = false) -> void:
	if requires_selection and _selected_save_id.is_empty():
		_set_save_status("SELECT A SAVE SLOT", false)
		return
	if not action.is_valid():
		_set_save_status("SAVES ARE UNAVAILABLE IN THIS MODE", false)
		return
	var result = action.callv(arguments)
	if not result is Dictionary:
		_set_save_status("SAVE OPERATION FAILED", false)
		return
	var ok := bool(result.get("ok", false))
	_set_save_status(String(result.get("message", "ROUTE SAVED" if ok else
		"SAVE OPERATION FAILED")), ok)
	if ok:
		_selected_save_id = String(result.get("slot_id", _selected_save_id))
		_refresh_saves()


func _set_save_status(message: String, ok: bool) -> void:
	_save_status.text = message
	_save_status.add_theme_color_override("font_color",
		Palette.STABLE if ok else Palette.ALERT)


func _open_dossier() -> void:
	_close_dossier()
	var content := _dossier_modal_content("ARCHIVED HUNTER SIGNALS",
		"HUNTER DOSSIER", Vector2(420, 232))
	var split := HBoxContainer.new()
	split.name = "PauseDossierSplit"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	content.add_child(split)

	var roster := ItemList.new()
	roster.name = "PauseDossierRoster"
	roster.custom_minimum_size = Vector2(108, 0)
	roster.size_flags_vertical = Control.SIZE_EXPAND_FILL
	roster.allow_reselect = true
	roster.add_theme_font_size_override("font_size", 7)
	roster.add_theme_color_override("font_color", Palette.BODY)
	roster.add_theme_color_override("font_selected_color", Palette.ON_AMBER)
	roster.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET,
		Palette.PANEL_EDGE, 3))
	roster.add_theme_stylebox_override("selected", Palette.button_box(
		Palette.AMBER_FILL, Palette.AMBER, 3, 1))
	roster.add_theme_stylebox_override("selected_focus", Palette.button_box(
		Palette.AMBER_FILL, Palette.AMBER, 3, 1))
	split.add_child(roster)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 4)
	split.add_child(details)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 5)
	details.add_child(identity)
	_dossier_name = _overlay_label("", Palette.INK, 16)
	_dossier_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.style_title(_dossier_name)
	identity.add_child(_dossier_name)
	_dossier_status = _overlay_label("", Palette.AMBER, 6)
	_dossier_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.add_child(_dossier_status)

	_dossier_behavior = _dossier_copy("PauseDossierBehavior")
	details.add_child(_dossier_behavior)
	_dossier_gimmick_heading = _overlay_label(Palette.track("VOID GIMMICK CHART"),
		Palette.AMBER, 6)
	_dossier_gimmick_heading.visible = false
	details.add_child(_dossier_gimmick_heading)
	_dossier_gimmick = _dossier_copy("PauseDossierGimmick")
	_dossier_gimmick.visible = false
	details.add_child(_dossier_gimmick)
	_dossier_counter = _dossier_copy("PauseDossierCounter")
	_dossier_counter.visible = false
	details.add_child(_dossier_counter)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)
	_dossier_stats = _overlay_label("", Palette.MUTED, 6)
	_dossier_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_dossier_stats)

	var ids: Array = []
	for category in ["az", "void"] + SecretCreatures.dossier_categories():
		var header := roster.add_item("-- %s --" % HunterDossier.category_title(category))
		roster.set_item_disabled(header, true)
		for hunter_id in HunterDossier.category_ids(category):
			ids.append(hunter_id)
			var discovered := Backend.hunter_discovered(hunter_id)
			var profile: Dictionary = HunterDossier.profile(hunter_id)
			var label := String(profile["name"]).to_upper() if discovered \
				else "???? // UNDISCOVERED"
			var index := roster.add_item(label)
			roster.set_item_metadata(index, hunter_id)
	roster.item_selected.connect(func(index: int) -> void:
		_show_dossier_entry(String(roster.get_item_metadata(index))))
	if not ids.is_empty():
		roster.select(1)
		_show_dossier_entry(String(ids[0]))
		roster.grab_focus.call_deferred()


func _dossier_copy(node_name: String) -> Label:
	var label := _overlay_label("", Palette.BODY, 7)
	label.name = node_name
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label


func _show_dossier_entry(hunter_id: String) -> void:
	var profile: Dictionary = HunterDossier.profile(hunter_id)
	var entry: Dictionary = HunterDossier.entry(hunter_id)
	if profile.is_empty() or entry.is_empty() or _dossier_name == null:
		return
	if not Backend.hunter_discovered(hunter_id):
		_dossier_name.text = "UNDISCOVERED SIGNAL"
		_dossier_status.text = "ACCOUNT DISCOVERY REQUIRED" if Backend.signed_in() \
			else "SIGN IN TO RETAIN DISCOVERIES"
		_dossier_behavior.text = "ENCOUNTER THIS HUNTER IN THE ROUTE TO REVEAL HER DOSSIER. SPAWN ROLLS AND ROOM SNAPSHOTS DO NOT COUNT."
		_dossier_gimmick_heading.visible = false
		_dossier_gimmick.visible = false
		_dossier_gimmick.text = ""
		_dossier_counter.text = ""
		_dossier_stats.text = "IDENTITY // ABILITY // TUNING HIDDEN"
		return
	_dossier_name.text = String(profile["name"]).to_upper()
	var category := String(profile.get("category", "az"))
	var special := HunterRoster.SPECIAL_IDS.has(hunter_id)
	_dossier_status.text = "VOID INCURSION // EXTRA HUNTER" if category == "void" \
		else "SECRET // FOUND IN THE CITY" if category == "secret" \
		else "RULE-SUMMONED // A-Z SPECIAL" if special \
		else "A-Z ROUTE DRAW // %s" % String(profile["tier"]).to_upper()
	_dossier_behavior.text = "%s // %s" % [String(entry["ability"]),
		String(entry["behavior"])]
	var has_chart := entry.has("gimmick_behavior")
	_dossier_gimmick_heading.visible = has_chart
	_dossier_gimmick.visible = has_chart
	_dossier_gimmick.text = "%s // %s" % [
		String(entry.get("gimmick_title", "UNASSIGNED")),
		String(entry.get("gimmick_behavior", "")),
	] if has_chart else ""
	_dossier_counter.text = ""
	_dossier_stats.text = "PATROL %.2f  //  CHASE %.2f  //  SIGHT %.1f  //  HEARING %.2f" % [
		float(profile["speed"]), float(profile["chase"]), float(profile["sight"]),
		float(profile["hearing"])]


func _dossier_modal_content(kicker: String, title: String, minimum: Vector2) -> VBoxContainer:
	_dossier_modal = ColorRect.new()
	_dossier_modal.name = "PauseDossierModal"
	_dossier_modal.color = Palette.SCRIM
	_dossier_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_dossier_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dossier_modal.z_index = 120
	add_child(_dossier_modal)
	var panel := PanelContainer.new()
	panel.name = "PauseDossierPanel"
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Color("0c080e"),
		Palette.PANEL_EDGE, 12))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.custom_minimum_size = minimum
	panel.offset_left = -minimum.x * 0.5
	panel.offset_top = -minimum.y * 0.5
	panel.offset_right = minimum.x * 0.5
	panel.offset_bottom = minimum.y * 0.5
	_dossier_modal.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var top := HBoxContainer.new()
	content.add_child(top)
	top.add_child(_overlay_label(Palette.track(kicker), Palette.AMBER, 6))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close_button := Button.new()
	close_button.add_theme_font_size_override("font_size", 7)
	Palette.style_escape_close(close_button)
	close_button.pressed.connect(_close_dossier)
	top.add_child(close_button)
	var heading := _overlay_label(title, Palette.INK, 15)
	Palette.style_title(heading)
	content.add_child(heading)
	return content


func _close_dossier() -> void:
	if _dossier_modal != null and is_instance_valid(_dossier_modal):
		_dossier_modal.queue_free()
	_dossier_modal = null
	_dossier_name = null
	_dossier_status = null
	_dossier_behavior = null
	_dossier_counter = null
	_dossier_gimmick_heading = null
	_dossier_gimmick = null
	_dossier_stats = null


func _overlay_label(text: String, tint: Color, font_size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", font_size)
	return label


func _refresh_statistics() -> void:
	if _statistics_grid == null:
		return
	for child in _statistics_grid.get_children():
		child.queue_free()
	var statistics: Dictionary = statistics_source.call() \
		if statistics_source.is_valid() else {}
	if statistics.is_empty():
		_add_statistic("STATUS", "NO RUN STATISTICS AVAILABLE")
		return
	for caption in statistics:
		_add_statistic(String(caption), String(statistics[caption]))


func _add_statistic(caption: String, value: String) -> void:
	var key := Label.new()
	key.text = caption.to_upper()
	Palette.style_label(key, Palette.MUTED, 8)
	_statistics_grid.add_child(key)
	var readout := Label.new()
	readout.text = value
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	readout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.style_label(readout, Palette.INK, 8)
	_statistics_grid.add_child(readout)


func _format_duration(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func _format_save_time(unix_time: int) -> String:
	if unix_time <= 0:
		return "UNKNOWN"
	var date := Time.get_datetime_dict_from_unix_time(unix_time)
	return "%04d-%02d-%02d %02d:%02d" % [int(date.get("year", 0)),
		int(date.get("month", 0)), int(date.get("day", 0)),
		int(date.get("hour", 0)), int(date.get("minute", 0))]


## Leaving is a two-step question, not a button. Abandoning is irreversible and
## in co-op it ends the run for everybody, so the second step says so rather
## than assuming the first click meant it.
func _build_confirm() -> void:
	_confirm = PanelContainer.new()
	_confirm.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.ACCENT_DEEP, 14))
	_confirm.set_anchors_preset(Control.PRESET_CENTER)
	_confirm.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_confirm.grow_vertical = Control.GROW_DIRECTION_BOTH
	_confirm.offset_left = -118
	_confirm.offset_right = 118
	_confirm.offset_top = -44
	_confirm.offset_bottom = 44
	add_child(_confirm)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	_confirm.add_child(column)

	var eyebrow := Label.new()
	eyebrow.text = Palette.track("SIGNAL SUSPENDED")
	Palette.style_label(eyebrow, Palette.AMBER, 7)
	eyebrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(eyebrow)

	var title := Label.new()
	title.name = "PauseConfirmTitle"
	title.text = "%s?" % abandon_label
	Palette.style_label(title, Palette.INK, 16)
	Palette.style_title(title)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	column.add_child(title)

	var body := Label.new()
	body.text = abandon_warning
	Palette.style_label(body, Palette.BODY, 8)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(208, 0)
	column.add_child(body)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	column.add_child(row)

	var yes := Button.new()
	yes.text = abandon_label
	yes.custom_minimum_size = Vector2(0, 14)
	yes.add_theme_font_size_override("font_size", 8)
	Palette.style_button(yes, false)
	yes.add_theme_stylebox_override("normal",
		Palette.button_box(Palette.PANEL, Palette.ACCENT_DEEP))
	yes.pressed.connect(_on_abandon)
	row.add_child(yes)

	var cancel := Button.new()
	cancel.text = "CANCEL"
	cancel.custom_minimum_size = Vector2(0, 14)
	cancel.add_theme_font_size_override("font_size", 8)
	Palette.style_button(cancel, false)
	cancel.pressed.connect(_cancel_abandon)
	row.add_child(cancel)

	_confirm.visible = false


func _ask_abandon() -> void:
	_confirming = true
	_panel.visible = false
	_confirm.visible = true
	# Focus the safe choice for keyboard/controller confirmation.
	var buttons := _confirm.find_children("*", "Button", true, false)
	if buttons.size() > 1:
		(buttons[1] as Button).grab_focus()


func _cancel_abandon() -> void:
	_confirming = false
	_confirm.visible = false
	_panel.visible = true
	_resume_button.grab_focus()


## The hold meter, shown only while ESC is actually down. Sitting above the
## bottom edge rather than in the middle, so it never covers what the player is
## watching while they decide whether to keep holding.
func _build_hold_prompt() -> void:
	_hold_box = PanelContainer.new()
	_hold_box.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.PANEL, Palette.PANEL_EDGE, 6))
	_hold_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hold_box.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_hold_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_hold_box.offset_left = -66
	_hold_box.offset_right = 66
	_hold_box.offset_top = -46
	_hold_box.offset_bottom = -22
	_hold_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hold_box)

	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	_hold_box.add_child(stack)

	var caption := Label.new()
	caption.text = Palette.track("HOLD ESC TO PAUSE")
	Palette.style_label(caption, Palette.AMBER, 7)
	stack.add_child(caption)

	var track := ColorRect.new()
	track.color = Palette.INSET
	track.custom_minimum_size = Vector2(0, 3)
	stack.add_child(track)

	_hold_fill = ColorRect.new()
	_hold_fill.color = Palette.ACCENT
	_hold_fill.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	_hold_fill.anchor_right = 0.0
	track.add_child(_hold_fill)

	_hold_box.visible = false


func open() -> void:
	if _open:
		return
	_set_open(true)
	_refresh_voice_history()
	_set_copy_status("", true)
	_refresh_share()
	_set_section("pause")
	_resume_button.grab_focus()
	opened.emit()


## Same overlay ESC opens once it decides to pause. Focus-loss calls this
## instead of synthesizing a keypress, so an open map/inventory is not eaten
## as a dismiss-only ESC. Focus returning must not call close().
func open_for_lost_focus() -> void:
	if _open:
		return
	if not tap_to_pause:
		return
	if not is_processing_unhandled_input():
		return
	open()


func _watch_window_focus() -> void:
	var window := get_window()
	if window == null:
		return
	if not window.focus_entered.is_connected(_on_window_focus_entered):
		window.focus_entered.connect(_on_window_focus_entered)
	if not window.focus_exited.is_connected(_on_window_focus_exited):
		window.focus_exited.connect(_on_window_focus_exited)
	_app_focused = window.has_focus()


func _unwatch_window_focus() -> void:
	var window := get_window()
	if window == null:
		return
	if window.focus_entered.is_connected(_on_window_focus_entered):
		window.focus_entered.disconnect(_on_window_focus_entered)
	if window.focus_exited.is_connected(_on_window_focus_exited):
		window.focus_exited.disconnect(_on_window_focus_exited)


func _on_window_focus_entered() -> void:
	_app_focused = true


func _on_window_focus_exited() -> void:
	_handle_focus_lost()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			_app_focused = true
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_handle_focus_lost()


func _handle_focus_lost() -> void:
	# A playtest window on a test machine is never focused by a person: it must not pause itself (docs/PLAYTEST.md).
	if Playtest.enabled:
		return
	if not _app_focused:
		return
	_app_focused = false
	# Held keys never arrive as releases once the window is away: let go of them so nobody keeps walking.
	_release_held_actions()
	if _focus_loss_may_pause():
		open_for_lost_focus()


func _release_held_actions() -> void:
	for action in InputMap.get_actions():
		if Input.is_action_pressed(action):
			Input.action_release(action)


## Losing the window never pauses unless the setting is on and the run is solo, and never while a text field has
## the keyboard (chat, admin fields, any LineEdit/TextEdit) or an admin overlay is open.
func _focus_loss_may_pause() -> bool:
	if not Settings.focus_loss_pauses() or AdminMenu.overlay_open:
		return false
	var focused := get_viewport().gui_get_focus_owner() if get_viewport() != null else null
	return not (focused is LineEdit or focused is TextEdit)


func close() -> void:
	if not _open:
		return
	_set_open(false)
	resumed.emit()


func _set_open(is_open: bool) -> void:
	_open = is_open
	_confirming = false
	_held = 0.0
	_scrim.visible = is_open
	_panel.visible = is_open
	_confirm.visible = false
	_hold_box.visible = false
	_close_dossier()
	if pauses_tree:
		get_tree().paused = is_open
	# The cursor is a claim rather than a mode change, so the camera cannot
	# take it back on its next frame while the menu is still up.
	MouseLock.claim("pause", is_open)


func _on_abandon() -> void:
	_set_open(false)
	abandoned.emit()


## ESC is read here rather than in each mode's controller, so tap and hold
## behave identically wherever the menu is used.
func _process(delta: float) -> void:
	if _open:
		return
	if tap_to_pause:
		return
	if Input.is_action_pressed("pause"):
		_held += delta
		_hold_box.visible = true
		_hold_fill.anchor_right = clampf(_held / HOLD_SECONDS, 0.0, 1.0)
		if _held >= HOLD_SECONDS:
			open()
	elif _held > 0.0:
		_held = 0.0
		_hold_box.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("pause"):
		return
	if _confirming:
		# ESC backs out of the question rather than out of the run.
		_cancel_abandon()
		get_viewport().set_input_as_handled()
	elif _dossier_modal != null and is_instance_valid(_dossier_modal):
		_close_dossier()
		get_viewport().set_input_as_handled()
	elif _open:
		close()
		get_viewport().set_input_as_handled()
	elif dismiss_overlay.is_valid() and bool(dismiss_overlay.call()):
		get_viewport().set_input_as_handled()
	elif tap_to_pause:
		open()
		get_viewport().set_input_as_handled()



## The only chat log: the last lines said in the room (RoomChat.history), each speaker with a local MUTE toggle.
func _refresh_voice_history() -> void:
	if _pause_view == null:
		return
	var old := _pause_view.get_node_or_null("VoiceHistory")
	if old != null:
		old.free()
	if RoomChat.history.is_empty():
		return
	var box := VBoxContainer.new()
	box.name = "VoiceHistory"
	box.add_theme_constant_override("separation", 1)
	_pause_view.add_child(box)
	var heading := Label.new()
	heading.text = Palette.track("SAID RECENTLY")
	Palette.style_label(heading, Palette.AMBER, 6)
	box.add_child(heading)
	var speakers := {}
	for entry_value in RoomChat.history.slice(maxi(0, RoomChat.history.size() - 6)):
		var entry: Dictionary = entry_value
		var line := Label.new()
		line.text = ("// %s" % entry["text"]) if bool(entry.get("system", false)) else "%s: %s" % [String(entry["name"]).to_upper(), entry["text"]]
		Palette.style_label(line, Palette.BODY, 6)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(220, 0)
		box.add_child(line)
		if not bool(entry.get("system", false)) and int(entry.get("peer", 0)) != (multiplayer.get_unique_id() if RoomState.online else 1):
			speakers[String(entry["name"]).to_upper()] = true
	for callsign in speakers:
		var mute := Button.new()
		mute.name = "Mute_%s" % callsign
		mute.text = ("UNMUTE %s" if Settings.is_player_muted(callsign) else "MUTE %s") % callsign
		mute.add_theme_font_size_override("font_size", 6)
		Palette.style_button(mute, false, true)
		mute.pressed.connect(func() -> void:
			Settings.set_player_muted(callsign, not Settings.is_player_muted(callsign))
			mute.text = ("UNMUTE %s" if Settings.is_player_muted(callsign) else "MUTE %s") % callsign)
		box.add_child(mute)
