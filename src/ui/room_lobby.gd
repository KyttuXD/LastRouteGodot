extends Control

## The staging screen: the room you are about to enter a route from.
##
## Built from Palette in code rather than as a scene, for the same reason the
## pause overlay is -- colours written into a .tscn are invisible to a palette
## change. Layout follows the web build's own staging screen: amber system
## line, the room code, the route seed in an inset block with a crimson rule,
## then the host's configuration and the seats.
##
## Offline this shows exactly what it shows online. That is deliberate: the
## screen is not a singleplayer menu wearing a room's clothes, it IS the room;
## ENet only changes who occupies it.

const ROW_HEIGHT := 13
const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
## Clear space left between the staging panel and the edge of the screen.
const MARGIN_Y := 10

var _notice := ""
var _modal: Control
var _dossier_name: Label
var _dossier_status: Label
var _dossier_behavior: Label
var _dossier_counter: Label
var _dossier_gimmick_heading: Label
var _dossier_gimmick: Label
var _dossier_stats: Label
var _default_focus: Control


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _modal != null:
		_close_modal()
		get_viewport().set_input_as_handled()


func _ready() -> void:
	MouseLock.release_all()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	RoomState.changed.connect(_rebuild)
	if not RoomState.status_message.is_empty():
		_notice = RoomState.status_message
	_rebuild()


func _rebuild() -> void:
	_modal = null
	_default_focus = null
	_clear_dossier_fields()
	for child in get_children():
		child.queue_free()

	var background := SIGNAL_BACKDROP_SCRIPT.new()
	background.name = "SignalBackdrop"
	background.pattern_strength = 0.7
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var panel := PanelContainer.new()
	panel.name = "StagingPanel"
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Palette.PANEL,
		Palette.PANEL_EDGE, 12))
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = -190
	panel.offset_right = 190
	# Bounded to the viewport with a real margin rather than sized by its
	# content. Staging grows -- more players, more config -- and a panel that
	# sizes itself pushes ENTER ROUTE off the bottom of the screen, which is
	# the one button that has to be reachable.
	panel.offset_top = MARGIN_Y
	panel.offset_bottom = -MARGIN_Y
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)

	# ...and scrolls if it still does not fit, so nothing is ever simply
	# unreachable on a short window.
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 5)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	header.add_child(_label(Palette.track("CO-OP STAGING SIGNAL"), Palette.AMBER, 7))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	header.add_child(_label("%d / %d SIGNALS" % [RoomState.roster().size(),
		RoomState.seats()], Palette.MUTED, 7))

	var title := HBoxContainer.new()
	title.name = "RoomTitle"
	title.add_theme_constant_override("separation", 6)
	column.add_child(title)
	var room_heading := _label("ROOM", Palette.INK, 18)
	room_heading.name = "RoomTitleLabel"
	Palette.style_title(room_heading)
	title.add_child(room_heading)
	var room_code := _label(RoomState.code, Palette.ACCENT, 18)
	room_code.name = "RoomCodeLabel"
	Palette.style_title(room_code, Palette.ACCENT)
	title.add_child(room_code)

	column.add_child(_seed_block())
	column.add_child(_config_block())
	column.add_child(_label(Palette.track("CONNECTED PLAYERS"), Palette.AMBER, 7))
	for row in RoomState.roster_rows():
		column.add_child(_player_row(row))
	var notice := _notice if not _notice.is_empty() else RoomState.status_message
	if not notice.is_empty():
		column.add_child(_label(notice, Palette.ALERT, 7))
	column.add_child(_label(_connection_summary(), Palette.MUTED, 7))
	column.add_child(_actions())
	if _default_focus != null:
		_default_focus.grab_focus.call_deferred()


func _connection_summary() -> String:
	if RoomState.connecting:
		return "JOINING THROUGH PRIMARY SERVER..."
	if RoomState.online and RoomState.is_host and not Backend.registered:
		return "REGISTERING ROOM %s WITH PRIMARY SERVER..." % RoomState.code
	if RoomState.online:
		return "ROOM %s // PRIMARY SERVER // %d CONNECTED" % [RoomState.code,
			RoomState.roster().size()]
	return "SOLO ROOM %s // PRIMARY SERVER UNAVAILABLE" % RoomState.code


func _seed_block() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel",
		Palette.panel_box(Palette.INSET, Palette.ACCENT_DEEP, 6))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 1)
	box.add_child(stack)
	stack.add_child(_label(Palette.track("ROUTE SEED"), Palette.AMBER, 6))
	stack.add_child(_label(RoomState.seed_text, Palette.INK, 9))
	stack.add_child(_label(
		"Players enter from separate nearby access points. The route is shared.",
		Palette.MUTED, 6))
	return box


func _config_block() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET,
		Palette.PANEL_EDGE, 6))
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 3)
	box.add_child(stack)

	var head := HBoxContainer.new()
	stack.add_child(head)
	head.add_child(_label(Palette.track("ROUTE SETUP"), Palette.AMBER, 7))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	head.add_child(_label("HOST CONTROLS" if RoomState.is_host else "HOST DECIDES",
		Palette.MUTED, 6))

	var groups := HBoxContainer.new()
	groups.add_theme_constant_override("separation", 5)
	stack.add_child(groups)
	# The route is now the game rather than a selectable experimental mode, so
	# MODE and MAP SCALE were redundant controls. Difficulty remains the one
	# meaningful room choice; the freed above-fold space exposes local archives.
	groups.add_child(_config_group("DIFFICULTY", RoomState.DIFFICULTY_LABELS,
		RoomState.difficulty,
		func(value: int) -> void: RoomState.set_difficulty(value),
		func(value: int) -> bool:
			return RoomState.is_host and RoomState.difficulty_available(value)))
	groups.add_child(_archive_group())

	stack.add_child(_label("SAVE DURING A ROUTE // LOAD FROM STAGING", Palette.MUTED, 6))
	return box


func _archive_group() -> Control:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 2)
	group.add_child(_label("ROUTE ARCHIVES", Palette.MUTED, 6))
	var slots := RunSaves.list_slots()
	var status := "NO LOCAL SAVES" if slots.is_empty() else "%d LOCAL SAVE%s" % [
		slots.size(), "" if slots.size() == 1 else "S"]
	if RoomState.online and not RoomState.is_host:
		status = "HOST CONTROLS SAVES"
	elif RoomState.online and RoomState.roster().size() > 1:
		status = "LOAD REQUIRES EMPTY ROOM"
	group.add_child(_label(status, Palette.BODY, 7))
	var button := Button.new()
	button.name = "LobbyLoadSaveButton"
	button.text = "LOAD SAVE" if slots.is_empty() else "LOAD SAVE (%d)" % slots.size()
	button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	button.focus_mode = Control.FOCUS_ALL
	Palette.style_button(button, false)
	button.disabled = not _archive_load_allowed() or slots.is_empty()
	button.pressed.connect(_on_saves_pressed)
	group.add_child(button)
	return group


func _archive_load_allowed() -> bool:
	return not RoomState.connecting \
		and (not RoomState.online or (RoomState.is_host and RoomState.roster().size() <= 1))


func _on_saves_pressed() -> void:
	_close_modal()
	var content := _modal_content("ROUTE ARCHIVE // LOCAL", "LOAD SAVED ROUTE",
		Vector2(390, 242))
	var note := _label(
		"LOADING REBUILDS THIS ROOM FROM THE SAVE. ONLINE LOAD REQUIRES THE HOST TO BE ALONE.",
		Palette.MUTED, 7)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "LobbySaveList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var status := _label("", Palette.ALERT, 7)
	status.name = "LobbySaveStatus"
	content.add_child(status)
	var slots := RunSaves.list_slots()
	if slots.is_empty():
		list.add_child(_label("NO LOCAL SAVES", Palette.MUTED, 8))
		return
	for value in slots:
		var slot: Dictionary = value
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		list.add_child(row)
		var details := _label("%s\nLEVEL %+d // %s // %s" % [
			String(slot.get("name", "ROUTE")), int(slot.get("level", 0)),
			String(slot.get("difficulty", "STANDARD")),
			_format_save_duration(float(slot.get("elapsed_seconds", 0.0)))],
			Palette.BODY, 7)
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		var load_button := Button.new()
		load_button.text = "LOAD"
		load_button.focus_mode = Control.FOCUS_ALL
		Palette.style_button(load_button, false)
		load_button.pressed.connect(_load_saved_route.bind(
			String(slot.get("slot_id", ""))))
		row.add_child(load_button)


func _load_saved_route(slot_id: String) -> void:
	if not _archive_load_allowed():
		var denied := _modal.find_child("LobbySaveStatus", true, false) as Label \
			if _modal != null else null
		if denied != null:
			denied.text = "LOAD REQUIRES THE HOST TO BE ALONE"
		return
	var result := RunSaves.queue_load(slot_id)
	if not bool(result.get("ok", false)):
		var status := _modal.find_child("LobbySaveStatus", true, false) as Label \
			if _modal != null else null
		if status != null:
			status.text = String(result.get("message", "SAVE LOAD FAILED"))
		return
	var payload: Dictionary = result.get("payload", {})
	RoomState.mode = RoomState.Mode.DEFAULT
	RoomState.map_scale = RoomState.Scale.INFINITE
	RoomState.seed_text = String(payload.get("seed_text", RoomState.seed_text))
	RoomState.difficulty = clampi(int(payload.get("difficulty",
		RoomState.Difficulty.STANDARD)), RoomState.Difficulty.RELAXED,
		RoomState.Difficulty.HARD)
	RoomState.status_message = "SAVE READY // %s" % String(result.get("name", "ROUTE"))
	_close_modal()
	RoomState.enter(get_tree())


func _format_save_duration(seconds: float) -> String:
	var total := maxi(0, floori(seconds))
	return "%02d:%02d:%02d" % [total / 3600, (total / 60) % 60, total % 60]


func _config_group(title: String, labels: Dictionary, selected: int,
		on_pick: Callable, is_allowed: Callable) -> Control:
	var group := VBoxContainer.new()
	group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_theme_constant_override("separation", 2)
	group.add_child(_label(title, Palette.MUTED, 6))
	group.add_child(_toggles(labels, selected, on_pick, is_allowed))
	return group


## A row of mutually exclusive buttons, amber-filled when selected -- the web
## build's quick button groups.
func _toggles(labels: Dictionary, selected: int, on_pick: Callable,
		is_allowed: Callable) -> Control:
	var row := HFlowContainer.new()
	row.add_theme_constant_override("separation", 3)
	for value in labels:
		var button := Button.new()
		button.text = String(labels[value])
		button.add_theme_font_size_override("font_size", 7)
		button.custom_minimum_size = Vector2(0, ROW_HEIGHT)
		button.focus_mode = Control.FOCUS_ALL
		var allowed: bool = is_allowed.call(value)
		Palette.style_button(button, false)
		if value == selected:
			button.add_theme_stylebox_override("normal",
				Palette.button_box(Palette.AMBER_FILL, Palette.AMBER))
			button.add_theme_color_override("font_color", Palette.ON_AMBER)
		button.disabled = not allowed
		if allowed:
			button.pressed.connect(func() -> void: on_pick.call(value))
		row.add_child(button)
	return row


## One seat. Every part of this used to be hardcoded, so a guest's window
## showed itself as the host.
func _player_row(entry: Dictionary) -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", Palette.panel_box(Palette.INSET,
		Palette.PANEL_EDGE, 4))
	var row := HBoxContainer.new()
	box.add_child(row)
	var you: bool = entry["you"]
	var label: String = String(entry["name"])
	if you:
		label += "  //  YOU"
	row.add_child(_label(label, Palette.INK if you else Palette.BODY, 7))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	var role: String = "HOST" if entry["host"] else "GUEST"
	row.add_child(_label("%s // STAGING" % role,
		Palette.AMBER if entry["host"] else Palette.MUTED, 6))
	return box


func _actions() -> Control:
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	stack.add_child(row)

	var enter := Button.new()
	enter.name = "EnterRouteButton"
	enter.text = "CONNECTING..." if RoomState.connecting else (
		"WAITING FOR HOST" if RoomState.online and not RoomState.is_host
		else "WAITING FOR PRIMARY SERVER" if RoomState.online and not Backend.registered
		else RoomState.start_label())
	enter.add_theme_font_size_override("font_size", 10)
	enter.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(enter, true)
	enter.disabled = RoomState.connecting or (RoomState.online and not RoomState.is_host) \
		or (RoomState.online and RoomState.is_host and not Backend.registered) \
		or not RoomState.mode_available(RoomState.mode)
	if not enter.disabled:
		enter.pressed.connect(func() -> void: RoomState.enter(get_tree()))
	row.add_child(enter)

	var reroll := Button.new()
	reroll.text = "REROLL ROUTE"
	reroll.add_theme_font_size_override("font_size", 7)
	reroll.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(reroll, false)
	reroll.disabled = RoomState.connecting or (RoomState.online and not RoomState.is_host)
	if not reroll.disabled:
		reroll.pressed.connect(func() -> void: RoomState.reroll_seed())
	row.add_child(reroll)

	var dossier := Button.new()
	dossier.name = "DossierButton"
	dossier.text = "HUNTER DOSSIER"
	dossier.add_theme_font_size_override("font_size", 7)
	dossier.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(dossier, false)
	dossier.pressed.connect(_on_dossier_pressed)
	row.add_child(dossier)
	_default_focus = enter if not enter.disabled else dossier

	var leave := Button.new()
	leave.name = "BackToMenuButton"
	leave.text = "BACK TO GAMES"
	leave.add_theme_font_size_override("font_size", 7)
	leave.custom_minimum_size = Vector2(0, 18)
	Palette.style_button(leave, false)
	leave.pressed.connect(func() -> void:
		var menu_scene := RoomState.menu_scene_path()
		RoomState.leave_network()
		get_tree().change_scene_to_file(menu_scene))
	row.add_child(leave)

	return stack


func _on_dossier_pressed() -> void:
	_close_modal()
	var content := _modal_content("ARCHIVED HUNTER SIGNALS", "HUNTER DOSSIER",
		Vector2(420, 232))
	var split := HBoxContainer.new()
	split.name = "DossierSplit"
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 8)
	content.add_child(split)

	var roster := ItemList.new()
	roster.name = "DossierRoster"
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
	details.name = "DossierDetails"
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 4)
	split.add_child(details)

	var identity := HBoxContainer.new()
	identity.add_theme_constant_override("separation", 5)
	details.add_child(identity)
	_dossier_name = _label("", Palette.INK, 16)
	_dossier_name.name = "DossierName"
	_dossier_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Palette.style_title(_dossier_name)
	identity.add_child(_dossier_name)
	_dossier_status = _label("", Palette.AMBER, 6)
	_dossier_status.name = "DossierStatus"
	_dossier_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	identity.add_child(_dossier_status)

	_dossier_behavior = _dossier_copy("DossierBehavior")
	details.add_child(_dossier_behavior)
	_dossier_gimmick_heading = _label(Palette.track("VOID GIMMICK CHART"),
		Palette.AMBER, 6)
	_dossier_gimmick_heading.name = "DossierGimmickHeading"
	_dossier_gimmick_heading.visible = false
	details.add_child(_dossier_gimmick_heading)
	_dossier_gimmick = _dossier_copy("DossierGimmick")
	_dossier_gimmick.visible = false
	details.add_child(_dossier_gimmick)
	_dossier_counter = _dossier_copy("DossierCounter")
	_dossier_counter.visible = false
	details.add_child(_dossier_counter)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	details.add_child(spacer)
	_dossier_stats = _label("", Palette.MUTED, 6)
	_dossier_stats.name = "DossierStats"
	_dossier_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.add_child(_dossier_stats)

	var ids: Array = []
	for category in ["az", "void"] + SecretCreatures.dossier_categories():
		var header_text := HunterDossier.category_title(category)
		var header := roster.add_item("-- %s --" % header_text)
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
	var label := _label("", Palette.BODY, 7)
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


func _modal_content(kicker: String, title: String, minimum: Vector2) -> VBoxContainer:
	_modal = ColorRect.new()
	_modal.name = "DossierModal"
	_modal.color = Palette.SCRIM
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal.set_anchors_preset(Control.PRESET_FULL_RECT)
	_modal.z_index = 80
	add_child(_modal)
	var panel := PanelContainer.new()
	panel.name = "DossierPanel"
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
	_modal.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 5)
	panel.add_child(content)
	var top := HBoxContainer.new()
	content.add_child(top)
	top.add_child(_label(Palette.track(kicker), Palette.AMBER, 6))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close := Button.new()
	close.name = "DossierCloseButton"
	close.add_theme_font_size_override("font_size", 7)
	Palette.style_escape_close(close)
	close.pressed.connect(_close_modal)
	top.add_child(close)
	var heading := _label(title, Palette.INK, 15)
	Palette.style_title(heading)
	content.add_child(heading)
	return content


func _close_modal() -> void:
	if _modal != null and is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null
	_clear_dossier_fields()


func _clear_dossier_fields() -> void:
	_dossier_name = null
	_dossier_status = null
	_dossier_behavior = null
	_dossier_counter = null
	_dossier_gimmick_heading = null
	_dossier_gimmick = null
	_dossier_stats = null


func _label(text: String, tint: Color, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", tint)
	label.add_theme_font_size_override("font_size", size)
	return label
