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
##   * Hold mode (tap_to_pause = false) HOLDS ESC for three seconds, with a
##     meter while you do, for screens where a one-key escape hatch would
##     undercut the moment (main_3d sets it on game over). The Office Mode
##     shift that introduced it was removed; the hold mode stays.
##   * A solo route window that loses OS focus opens the same overlay ESC does, when Settings.pause_on_focus_loss is
##     on (release builds by default). Never in a room, public route or with other players, never while a text field
##     or admin overlay has the keyboard; held keys are released either way.
##     Playtests kept dying to Gray Void while a terminal had the keyboard.
##     Focus coming back does not resume -- RETURN or ESC still has to. Title,
##     staging, hold-to-pause, and a locked-out escape struggle do not.
##
## Built in code rather than as a .tscn on purpose: every colour comes from
## Palette, so restyling the game is one file rather than a hunt through scene
## files for hardcoded values.

signal resumed
signal abandoned
signal opened

## How long ESC must be held in hold-to-pause mode.
const HOLD_SECONDS := 3.0
const SETTINGS_SCENE := "res://game/menus/settings_overlay.tscn"

## Tap to pause, or hold. main_3d sets this false on game over.
@export var tap_to_pause := true
## Offline play stops the SceneTree. In a live co-op room, opening a
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
## this presentation class lets Office/legacy modes omit saves cleanly. Last Route has one automatic save per run;
## save_status_source returns its line ("RUN SAVED AT LEVEL -2, 14:05"), shown under RETURN.
var save_status_source: Callable
var statistics_source: Callable

var _scrim: ColorRect
var _panel: PanelContainer
var _confirm: PanelContainer
var _hold_box: PanelContainer
var _hold_fill: ColorRect
var _resume_button: Button
var _abandon_button: Button
var _settings_button: Button
## The shared SettingsPanel, instanced on the first SETTINGS press and kept for the rest of the run (in_run: no SKIN or MODS tab).
var _settings_overlay: SettingsPanel
var _pause_view: VBoxContainer
## PAUSE / STATISTICS tab buttons: only the open page's tab is lit.
var _tabs := {}
var section := "pause"
var _statistics_scroll: ScrollContainer
var _statistics_view: VBoxContainer
## PLAYERS page: the active room's player list. players_source returns RoomPlayerList rows, players_admin says whether the viewer may
## pulse players (the host still re-checks). The page refreshes twice a second while it is the open one.
var players_source: Callable
var players_admin: Callable
var player_list: PlayerListPanel
var _players_view: VBoxContainer
var _players_elapsed := 0.0
signal pulse_requested(peer_id: int)
var _save_status: Label
var _statistics_grid: GridContainer
var _share_code: Label
var _share_seed: Label
var _copy_button: Button
var _copy_status: Label
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
	for entry in [["PAUSE", "pause"], ["STATISTICS", "statistics"], ["PLAYERS", "players"]]:
		var tab := Button.new()
		tab.text = String(entry[0])
		tab.focus_mode = Control.FOCUS_ALL
		tab.custom_minimum_size = Vector2(80, 18)
		tab.add_theme_font_size_override("font_size", 8)
		tab.name = "PauseTab_%s" % String(entry[1])
		Palette.style_button(tab, String(entry[1]) == "pause")
		tab.pressed.connect(_set_section.bind(String(entry[1])))
		tabs.add_child(tab)
		_tabs[String(entry[1])] = tab

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

	_save_status = Label.new()
	_save_status.name = "PauseSaveStatus"
	_save_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	Palette.style_label(_save_status, Palette.MUTED, 7)
	_pause_view.add_child(_save_status)

	var dossier_button := Button.new()
	dossier_button.text = "HUNTER DOSSIER"
	dossier_button.focus_mode = Control.FOCUS_ALL
	dossier_button.custom_minimum_size = Vector2(112, 18)
	dossier_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	dossier_button.add_theme_font_size_override("font_size", 8)
	Palette.style_button(dossier_button, false)
	dossier_button.pressed.connect(_open_dossier)
	_pause_view.add_child(dossier_button)

	# Same size and style as the dossier button, directly under it: the overlay itself is built on the first press.
	_settings_button = Button.new()
	_settings_button.name = "PauseSettingsButton"
	_settings_button.text = "SETTINGS"
	_settings_button.focus_mode = Control.FOCUS_ALL
	_settings_button.custom_minimum_size = Vector2(112, 18)
	_settings_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_settings_button.add_theme_font_size_override("font_size", 8)
	Palette.style_button(_settings_button, false)
	_settings_button.pressed.connect(_open_settings)
	_pause_view.add_child(_settings_button)

	_abandon_button = Button.new()
	_abandon_button.text = abandon_label
	_abandon_button.focus_mode = Control.FOCUS_ALL
	_abandon_button.custom_minimum_size = Vector2(88, 14)
	_abandon_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_abandon_button.add_theme_font_size_override("font_size", 8)
	Palette.style_button(_abandon_button, false)
	_abandon_button.pressed.connect(_ask_abandon)
	_pause_view.add_child(_abandon_button)

	_build_statistics_view(column)
	_build_players_view(column)

	_build_confirm()
	_build_hold_prompt()
	_set_section("pause")


func _build_players_view(parent: VBoxContainer) -> void:
	_players_view = VBoxContainer.new()
	_players_view.name = "PausePlayers"
	_players_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_players_view)
	player_list = PlayerListPanel.new()
	player_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	player_list.pulse_requested.connect(func(id: int) -> void: pulse_requested.emit(id))
	_players_view.add_child(player_list)


func _refresh_players() -> void:
	if player_list == null:
		return
	player_list.admin_enabled = players_admin.is_valid() and bool(players_admin.call())
	player_list.set_rows(players_source.call() if players_source.is_valid() else [])


## The whole STATISTICS page scrolls (wheel, touch drag, focus): nothing clips at small windows, phones or the XR panel.
func _build_statistics_view(parent: VBoxContainer) -> void:
	_statistics_view = VBoxContainer.new()
	_statistics_view.name = "PauseStatistics"
	_statistics_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(_statistics_view)
	var scroll := ScrollContainer.new()
	scroll.name = "PauseStatisticsScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_ALWAYS
	scroll.follow_focus = true
	_style_scrollbar(scroll.get_v_scroll_bar())
	_statistics_view.add_child(scroll)
	_statistics_scroll = scroll
	var page := VBoxContainer.new()
	page.name = "PauseStatisticsPage"
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 6)
	scroll.add_child(page)
	var heading := Label.new()
	heading.text = Palette.track("CURRENT RUN")
	Palette.style_label(heading, Palette.AMBER, 8)
	page.add_child(heading)
	page.add_child(_build_share_block())
	var grid_parent := page
	_statistics_grid = GridContainer.new()
	_statistics_grid.name = "PauseStatisticsGrid"
	_statistics_grid.columns = 2
	_statistics_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_statistics_grid.add_theme_constant_override("h_separation", 18)
	_statistics_grid.add_theme_constant_override("v_separation", 5)
	grid_parent.add_child(_statistics_grid)


## House-style scrollbar: a slim inset track with an accent grabber.
static func _style_scrollbar(bar: VScrollBar) -> void:
	var track := Palette.panel_box(Palette.INSET, Palette.PANEL_EDGE, 0)
	track.content_margin_left = 3
	track.content_margin_right = 3
	bar.add_theme_stylebox_override("scroll", track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		bar.add_theme_stylebox_override(state, Palette.panel_box(Palette.ACCENT if state == "grabber" else Palette.ACCENT_EDGE, Palette.ACCENT_EDGE, 0))




## Scrolls the statistics page so its last row is visible (keyboard/controller "end", tests).
func scroll_statistics_to_end() -> void:
	if _statistics_scroll != null:
		_statistics_scroll.scroll_vertical = int(_statistics_scroll.get_v_scroll_bar().max_value)


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


func _set_section(next: String) -> void:
	if _pause_view == null:
		return
	section = next
	for id in _tabs:
		Palette.style_button(_tabs[id] as Button, id == section)
	_pause_view.visible = section == "pause"
	_statistics_view.visible = section == "statistics"
	_players_view.visible = section == "players"
	if section == "players":
		_refresh_players()
	if section == "statistics":
		_refresh_share()
		_refresh_statistics()


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
	roster.fixed_icon_size = Vector2i(48, 48)
	roster.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST   # 2D pixel-art portraits
	roster.icon_mode = ItemList.ICON_MODE_LEFT
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
				else "???"
			var index := roster.add_item(label, HunterDossier.portrait(hunter_id))
			roster.set_item_metadata(index, hunter_id)
			if not discovered:
				roster.set_item_icon_modulate(index, HunterDossier.SILHOUETTE)
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
		_dossier_name.text = "??? (LOCKED)"
		_dossier_status.text = "ACCOUNT DISCOVERY REQUIRED" \
			if Backend.signed_in() else "SIGN IN TO RETAIN DISCOVERIES"
		_dossier_behavior.text = HunterDossier.redacted(hunter_id, String(entry["behavior"]))
		var locked_chart := entry.has("gimmick_behavior")
		_dossier_gimmick_heading.visible = locked_chart
		_dossier_gimmick.visible = locked_chart
		_dossier_gimmick.text = HunterDossier.redacted(hunter_id,
			String(entry.get("gimmick_behavior", ""))) if locked_chart else ""
		_dossier_counter.text = ""
		_dossier_stats.text = "PATROL %.2f  //  CHASE %.2f  //  SIGHT %.1f  //  HEARING %.2f" % [
			float(profile["speed"]), float(profile["chase"]), float(profile["sight"]),
			float(profile["hearing"])]
		return
	_dossier_name.text = String(profile["name"]).to_upper()
	var category := String(profile.get("category", "az"))
	var special := HunterRoster.SPECIAL_IDS.has(hunter_id)
	_dossier_status.text = "VOID INCURSION // EXTRA HUNTER" if category == "void" \
		else "SECRET // FOUND IN THE CITY" if category == "secret" \
		else "RULE-SUMMONED // A-Z SPECIAL" if special \
		else "A-Z ROUTE DRAW // %s" % String(profile["tier"]).to_upper()
	_dossier_behavior.text = String(entry["behavior"])
	var has_chart := entry.has("gimmick_behavior")
	_dossier_gimmick_heading.visible = has_chart
	_dossier_gimmick.visible = has_chart
	_dossier_gimmick.text = String(entry.get("gimmick_behavior", "")) if has_chart else ""
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


func settings_is_open() -> bool:
	return _settings_overlay != null and _settings_overlay.visible


## SETTINGS: the shared SettingsPanel above the pause menu. It lives under this CanvasLayer, so it keeps running while the
## tree is paused and, in XR, follows the layer onto the route panel. The pause page is hidden behind it (like the abandon
## question) so keyboard and controller focus cannot wander onto the buttons underneath.
func _open_settings() -> void:
	if not _open or _confirming:
		return
	if _settings_overlay == null:
		var scene := load(SETTINGS_SCENE) as PackedScene
		_settings_overlay = scene.instantiate() as SettingsPanel
		_settings_overlay.name = "PauseSettings"
		_settings_overlay.in_run = true
		_settings_overlay.closed.connect(_on_settings_closed)
		add_child(_settings_overlay)
	_close_dossier()
	_panel.visible = false
	_settings_overlay.open()


func _close_settings() -> void:
	if settings_is_open():
		_settings_overlay.close()


## BACK, ESC and B all end up here: back to the pause page, with the SETTINGS button focused. Closing the whole menu (RETURN,
## abandon) hides the overlay too, but must not bring the pause page back.
func _on_settings_closed() -> void:
	if not _open:
		return
	_panel.visible = true
	_settings_button.grab_focus()


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


func _refresh_save_status() -> void:
	var line = save_status_source.call() if save_status_source.is_valid() else ""
	_save_status.text = String(line) if line is String else ""
	_save_status.visible = not _save_status.text.is_empty()


func open() -> void:
	if _open:
		return
	_set_open(true)
	_refresh_voice_history()
	_set_copy_status("", true)
	_refresh_share()
	_refresh_save_status()
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
	_close_settings()
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
		if section == "players":
			_players_elapsed += delta
			if _players_elapsed >= 0.5:
				_players_elapsed = 0.0
				_refresh_players()
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
	if settings_is_open():
		# ESC, the pause key and B back out of SETTINGS only: the pause menu stays up and the run stays paused. (A rebind in
		# progress takes ESC first, in SettingsPanel._input.)
		if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
			_close_settings()
			get_viewport().set_input_as_handled()
		return
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
