class_name NightWatchMenu
extends Control

## Night Watch's menus, rebuilt from the 2D game's (games/night-watch/src/ui/menu.js, hub.js, custom.js): the TITLE (PLAY, CUSTOM NIGHT,
## ACCOUNT, SETTINGS, CREDITS, QUIT), the SHIFT BOARD (nine modes, shift tiles, START SHIFT), CUSTOM NIGHT, ACCOUNT, SETTINGS and CREDITS,
## over the office. Same order, labels, structure and palette as the 2D game; docs/NIGHT_WATCH_MENUS.md lays them side by side and
## tests/validate_night_watch_menus.gd checks the labels. The mode table is NightWatchModesData (copied from the 2D registry).
## QUIT goes back to the games hub, as the 2D QUIT goes back to the lab.

const INK := Color("e8e2d0")
const DIM := Color("9b947f")
const RED := Color("c4302b")
## the red for TEXT on the dark panels: RED is 3.5:1 there, this is 5:1
const RED_TEXT := Color("e0504a")
const AMBER := Color("e0b04a")
const BODY := Color("c9c3b0")   # secondary text straight on the scene (DIM is for text on a panel)
const PANEL := Color(0.024, 0.02, 0.016, 0.72)
const THEME_PATH := "res://game/night_watch/theme_nightwatch.tres"

signal screen_changed(screen: String)

var screen := "title"
var board_mode := 0
var board_level := 0
var title_index := 0
var toast_text := ""

var backdrop: SubViewportContainer
var layer_root: Control
var clock_label: Label
var toast_label: Label
var hint_label: Label
var title_buttons: Array[Button] = []
var mode_buttons: Array[Button] = []
var tile_buttons: Array[Button] = []
var start_button: Button
var custom_state := {"mode": "", "values": {}}
var username_edit: LineEdit
var password_edit: LineEdit
var account_status: Label
var volume_slider: HSlider
var calm_check: CheckBox
var scare_button: Button
var erase_button: Button
var _erase_armed := false
var _clock_t := 0.0
var _screen_root: Control


func _ready() -> void:
	if not GameRegistry.is_launchable("night_watch"):
		# locked for players (GameRegistry): a deep link, a saved scene path or any other route back to here returns to the landing scene (the hub, or the Last Route menu while the hub is skipped)
		GameRegistry.active_game_id = GameRegistry.DEFAULT_ID   # the hub set the Last Route scheme on arrival; the menu does not
		get_tree().change_scene_to_file.call_deferred(GameRegistry.landing_scene())
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	MouseLock.release_all()   # a menu always has the cursor, whatever held it before
	theme = NightWatchTheme.get_theme()
	GameRegistry.active_game_id = "night_watch"   # the shared screens that open from here (admin, account) wear Night Watch's colours
	_build_backdrop()
	layer_root = Control.new()
	layer_root.name = "Screens"
	layer_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(layer_root)
	clock_label = _label("12 AM", 9, INK)
	clock_label.name = "Clock"
	clock_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	clock_label.offset_left = -56
	clock_label.offset_right = -6
	clock_label.offset_top = 6
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(clock_label)
	toast_label = _label("", 7, AMBER)
	toast_label.name = "Toast"
	toast_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toast_label.offset_top = -25
	toast_label.offset_bottom = -15
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(toast_label)
	hint_label = _label("", 6, BODY)
	hint_label.name = "Hint"
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -13
	hint_label.offset_bottom = -3
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint_label)
	if Backend.has_signal("account_changed"):
		Backend.account_changed.connect(_on_account_changed)
	var first := String(NightWatchSession.mode_id)
	custom_state["mode"] = first
	var open_on := NightWatchSession.menu_screen
	NightWatchSession.menu_screen = "title"
	if open_on == "board":
		for i in NightWatchModesData.MODES.size():
			if String(NightWatchModesData.MODES[i]["id"]) == NightWatchSession.mode_id:
				board_mode = i
		board_level = clampi(NightWatchSession.night - 1, 0, 99)
	show_screen(open_on if ["title", "board"].has(open_on) else "title")


## clock text only needs ~2 Hz; skip the rest of the idle title frames.
var _clock_refresh_left := 0.0


func _process(delta: float) -> void:
	_clock_t += delta
	_clock_refresh_left -= delta
	if _clock_refresh_left > 0.0:
		return
	_clock_refresh_left = 0.5
	if screen == "title" or screen == "settings" or screen == "account" or screen == "credits" or screen == "custom":
		# The title clock drifts 12 AM to 6 AM, as the 2D title's does; the board shows the real time.
		var hour := int(floor(_clock_t / 12.0)) % 7
		clock_label.text = "12 AM" if hour == 0 else "%d AM" % hour
	else:
		clock_label.text = Time.get_time_string_from_system().substr(0, 5)


# --- shared drawing ------------------------------------------------------------------------------------------------------------

func _label(text: String, font_size := 8, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String, font_size := 7) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", font_size)
	return b


func _panel(parent: Control, panel_name: String, rect: Rect2) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = panel_name
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color(0.16, 0.15, 0.12)
	style.set_border_width_all(1)
	style.set_content_margin_all(5)
	p.add_theme_stylebox_override("panel", style)
	p.position = rect.position
	p.custom_minimum_size = rect.size
	p.size = rect.size
	parent.add_child(p)
	return p


func _flat(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0)
		sb.set_content_margin_all(2)
		if state == "focus":
			sb.bg_color = Color(0.88, 0.69, 0.29, 0.10)
		b.add_theme_stylebox_override(state, sb)


func _build_backdrop() -> void:
	backdrop = SubViewportContainer.new()
	backdrop.name = "Backdrop"
	backdrop.stretch = true
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var vp := SubViewport.new()
	vp.name = "OfficeView"
	vp.own_world_3d = true
	vp.size = Vector2i(960, 540)
	backdrop.add_child(vp)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.02, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.38, 0.40, 0.55)
	env_node.environment = env
	vp.add_child(env_node)
	var office := NightWatchOffice.new()
	office.name = "Office"
	vp.add_child(office)
	var cam := Camera3D.new()
	cam.name = "MenuCamera"
	cam.fov = 62.0
	vp.add_child(cam)
	cam.position = Vector3(0.0, 1.6, -0.25)
	cam.rotation = Vector3(-0.16, 0.0, 0.0)
	var dim := ColorRect.new()
	dim.name = "Tint"
	dim.color = Color(0.0, 0.03, 0.04, 0.6)   # dark enough that the light text on the scene reads (4.5:1)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)


func _clear_screen() -> void:
	for c in layer_root.get_children():
		c.queue_free()
		layer_root.remove_child(c)
	title_buttons.clear()
	mode_buttons.clear()
	tile_buttons.clear()
	start_button = null
	username_edit = null
	password_edit = null
	_screen_root = Control.new()
	_screen_root.name = "Screen_%s" % screen
	_screen_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer_root.add_child(_screen_root)


func show_screen(name_value: String) -> void:
	screen = name_value
	_erase_armed = false
	_clear_screen()
	match screen:
		"title":
			_build_title()
		"board":
			_build_board()
		"custom":
			_build_custom()
		"account":
			_build_account()
		"settings":
			_build_settings()
		"credits":
			_build_credits()
		_:
			_build_title()
	NightWatchSounds.wire_buttons(_screen_root)   # the 2D menu blips: move on hover / focus, pick on press, deny on a locked choice
	set_toast(toast_text if screen == "title" else "")
	screen_changed.emit(screen)


func set_toast(text: String) -> void:
	toast_text = text
	toast_label.text = text


func _header(title_text: String, extra := "", parent: Control = null) -> Control:
	var bar := HBoxContainer.new()
	bar.name = "Header"
	if parent == null:
		bar.position = Vector2(8, 6)
		bar.custom_minimum_size = Vector2(size.x - 70, 14)
	bar.add_theme_constant_override("separation", 10)
	(parent if parent != null else _screen_root).add_child(bar)
	var back := _button("← BACK  ESC", 6)
	back.name = "BackButton"
	back.pressed.connect(go_back)
	bar.add_child(back)
	var t := _label(title_text, 9, INK)
	t.name = "ScreenTitle"
	bar.add_child(t)
	if not extra.is_empty():
		var e := _label(extra, 7, AMBER)
		e.name = "HeaderExtra"
		bar.add_child(e)
	return bar


func go_back() -> void:
	match screen:
		"title":
			quit_to_games()
		_:
			show_screen("title" if screen != "custom" else "title")


func quit_to_games() -> void:
	get_tree().change_scene_to_file(GameRegistry.HUB_SCENE)


# --- title ---------------------------------------------------------------------------------------------------------------------

func _title_items() -> Array:
	var custom_ok := NightWatchSave.custom_unlocked("classic")
	var signed_in := bool(Backend.signed_in())
	var who := String(Backend.get("username")) if signed_in and Backend.get("username") != null else NightWatchSave.guest_name()
	return [
		{"label": "PLAY", "sub": "", "disabled": false, "action": "board"},
		{"label": "CUSTOM NIGHT", "sub": "" if custom_ok else "BEAT NIGHT 5 TO UNLOCK", "disabled": not custom_ok, "action": "custom"},
		{"label": "ACCOUNT", "sub": "GUEST" if not signed_in else who, "disabled": false, "action": "account"},
		{"label": "SETTINGS", "sub": "", "disabled": false, "action": "settings"},
		{"label": "CREDITS", "sub": "", "disabled": false, "action": "credits"},
		{"label": "QUIT", "sub": "", "disabled": false, "action": "quit"},
	]


func _build_title() -> void:
	var wrap := CenterContainer.new()
	wrap.name = "TitleWrap"
	wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	wrap.offset_top = 14
	wrap.offset_bottom = -18
	_screen_root.add_child(wrap)
	var box := VBoxContainer.new()
	box.name = "TitleBox"
	box.custom_minimum_size = Vector2(180, 236)
	box.add_theme_constant_override("separation", 1)
	wrap.add_child(box)
	var logo := HBoxContainer.new()
	logo.name = "Logo"
	logo.alignment = BoxContainer.ALIGNMENT_CENTER
	logo.add_theme_constant_override("separation", 6)
	box.add_child(logo)
	var night := _label("NIGHT", 22, INK)
	night.name = "LogoNight"
	logo.add_child(night)
	var watch := _label("WATCH", 22, RED_TEXT)
	watch.name = "LogoWatch"
	logo.add_child(watch)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 18)
	box.add_child(spacer)
	var items := _title_items()
	for i in items.size():
		var item: Dictionary = items[i]
		var b := _button(String(item["label"]), 8)
		b.name = "Title_%s" % String(item["action"])
		b.set_meta("action", item["action"])
		b.set_meta("label", item["label"])
		b.disabled = bool(item["disabled"])
		_flat(b)
		b.add_theme_color_override("font_color", INK)
		b.add_theme_color_override("font_disabled_color", DIM)
		b.pressed.connect(title_activate.bind(i))
		b.focus_entered.connect(func(): _title_select(i))
		box.add_child(b)
		title_buttons.append(b)
		if not String(item["sub"]).is_empty():
			var sub := _label(String(item["sub"]), 5, BODY)
			sub.name = "Sub_%s" % String(item["action"])
			sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(sub)
	hint_label.text = "↑ ↓ select · Enter confirm"
	_title_select(clampi(title_index, 0, title_buttons.size() - 1))
	title_buttons[title_index].grab_focus()


func _title_select(i: int) -> void:
	title_index = i
	for k in title_buttons.size():
		var b := title_buttons[k]
		var base := String(b.get_meta("label"))
		b.text = (">> " + base) if k == i else base
		

func title_activate(i: int) -> void:
	var b := title_buttons[i]
	var action := String(b.get_meta("action"))
	if b.disabled:
		set_toast("Custom Night is locked. Beat Night 5.")
		return
	match action:
		"board", "custom", "account", "settings", "credits":
			show_screen(action)
		"quit":
			quit_to_games()


# --- shift board ---------------------------------------------------------------------------------------------------------------

func mode_data(i: int) -> Dictionary:
	return NightWatchModesData.MODES[clampi(i, 0, NightWatchModesData.MODES.size() - 1)]


func _scored(m: Dictionary) -> int:
	return int(m["scored"])


func _cleared_count(m: Dictionary) -> int:
	var n := 0
	for lv in NightWatchSave.cleared_levels(String(m["id"])):
		if int(lv) <= _scored(m):
			n += 1
	return n


## The Shift Board, laid out with containers so nothing can overlap or run off the screen at any size: a column (header, body, START row) in a margin; the body is the mode list and the
## detail pane (a scrolling text area beside the portrait, the shift cards below it); START SHIFT has its own row under the pane; the key hint sits under everything.
func _build_board() -> void:
	var margin := MarginContainer.new()
	margin.name = "BoardMargin"
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 16)   # the key hint line lives in the bottom strip
	_screen_root.add_child(margin)
	var column := VBoxContainer.new()
	column.name = "BoardColumn"
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	_header("SHIFT BOARD", "", column)
	var body := HBoxContainer.new()
	body.name = "BoardBody"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	column.add_child(body)
	var list := VBoxContainer.new()
	list.name = "ModeList"
	list.custom_minimum_size = Vector2(120, 0)
	list.add_theme_constant_override("separation", 1)
	body.add_child(list)
	for i in NightWatchModesData.MODES.size():
		var m: Dictionary = NightWatchModesData.MODES[i]
		var row := Button.new()
		row.name = "Mode_%s" % String(m["id"])
		row.text = "%d.  %s" % [int(m["num"]), String(m["title"])]
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.custom_minimum_size = Vector2(120, 15)
		row.add_theme_font_size_override("font_size", 6)
		row.set_meta("mode", i)
		var stat := _label("%d/%d" % [_cleared_count(m), _scored(m)], 5, DIM)
		stat.name = "Stat"
		stat.anchor_left = 1.0
		stat.anchor_right = 1.0
		stat.anchor_top = 0.0
		stat.anchor_bottom = 1.0
		stat.offset_left = -30
		stat.offset_right = -5
		stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(stat)
		row.pressed.connect(select_mode.bind(i))
		list.add_child(row)
		mode_buttons.append(row)
	var right := VBoxContainer.new()
	right.name = "BoardRight"
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 4)
	body.add_child(right)
	var detail := PanelContainer.new()
	detail.name = "Detail"
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var dstyle := StyleBoxFlat.new()
	dstyle.bg_color = PANEL
	dstyle.border_color = Color(0.16, 0.15, 0.12)
	dstyle.set_border_width_all(1)
	dstyle.set_content_margin_all(5)
	detail.add_theme_stylebox_override("panel", dstyle)
	right.add_child(detail)
	var col := VBoxContainer.new()
	col.name = "DetailBox"
	col.add_theme_constant_override("separation", 4)
	detail.add_child(col)
	var m: Dictionary = mode_data(board_mode)
	var top := HBoxContainer.new()
	top.name = "DetailTop"
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.add_theme_constant_override("separation", 8)
	col.add_child(top)
	var shot := _portrait(String((m["art"] as Array)[0]) if not (m["art"] as Array).is_empty() else "")
	shot.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	top.add_child(shot)
	# the mode's text scrolls inside its own area: a long blurb or hint never runs into the cards
	var scroll := ScrollContainer.new()
	scroll.name = "InfoScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(60, 30)
	top.add_child(scroll)
	var info := VBoxContainer.new()
	info.name = "Info"
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	scroll.add_child(info)
	var t := _label(String(m["label"]), 11, INK)
	t.name = "ModeTitle"
	info.add_child(t)
	var tag := _label(String(m["tag"]), 6, AMBER)
	tag.name = "ModeTag"
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(tag)
	var blurb := _label(String(m["blurb"]), 6, INK)
	blurb.name = "ModeBlurb"
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(blurb)
	if not String(m["hint"]).is_empty():
		var hint := _label(String(m["hint"]), 6, DIM)
		hint.name = "ModeHint"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_child(hint)
	var stat_line := _label(_stat_line(m), 5, DIM)
	stat_line.name = "ModeStat"
	stat_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stat_line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_child(stat_line)
	var levels: Array = m["levels"]
	var grid := GridContainer.new()
	grid.name = "Tiles"
	grid.columns = 4 if levels.size() > 6 else 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 3)
	col.add_child(grid)
	for i in levels.size():
		var open := NightWatchSave.level_open(String(m["id"]), i + 1, bool(m["open"]))
		var tile := Button.new()
		tile.name = "Tile_%d" % (i + 1)
		tile.custom_minimum_size = Vector2(40, 24)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_font_size_override("font_size", 6)
		tile.text = ("%02d  %s" % [i + 1, String(levels[i])]) if open else ("%02d  LOCKED\n?????" % (i + 1))
		tile.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tile.clip_text = true
		tile.disabled = not open
		tile.set_meta("level", i)
		if open and NightWatchSave.cleared_levels(String(m["id"])).has(i + 1) and i < _scored(m):
			tile.text += "\n✔ CLEARED"
		tile.pressed.connect(select_level.bind(i, true))
		grid.add_child(tile)
		tile_buttons.append(tile)
	# START SHIFT has its own row below the pane
	var start_row := HBoxContainer.new()
	start_row.name = "StartRow"
	start_row.alignment = BoxContainer.ALIGNMENT_CENTER
	right.add_child(start_row)
	start_button = _button("▶ START SHIFT  ENTER", 8)
	start_button.name = "StartButton"
	start_button.custom_minimum_size = Vector2(148, 16)
	start_button.add_theme_color_override("font_color", INK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.45, 0.1, 0.09)
	sb.border_color = RED
	sb.set_border_width_all(1)
	sb.set_content_margin_all(3)
	start_button.add_theme_stylebox_override("normal", sb)
	start_button.pressed.connect(start_selected)
	start_row.add_child(start_button)
	hint_label.text = "↑ ↓ mode · ← → shift · Enter start · Esc back"
	_mark_board()
	mode_buttons[board_mode].grab_focus()


func _stat_line(m: Dictionary) -> String:
	if not NightWatchModeRegistry.playable(String(m["id"])):
		return "NOT BUILT YET"
	var s := "%d / %d SHIFTS CLEARED" % [_cleared_count(m), _scored(m)]
	if not (m["presets"] as Array).is_empty():
		s += " · ★ %d/%d STARS" % [NightWatchSave.stars(String(m["id"])).size(), (m["presets"] as Array).size()]
		var best := NightWatchSave.best_score(String(m["id"]))
		if best > 0:
			s += " · BEST %d" % best
	return s


func _portrait(hunter_id: String) -> Control:
	var frame := PanelContainer.new()
	frame.name = "Portrait"
	frame.custom_minimum_size = Vector2(96, 54)
	var svc := SubViewportContainer.new()
	svc.stretch = true
	svc.custom_minimum_size = Vector2(96, 54)
	frame.add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.size = Vector2i(192, 108)
	svc.add_child(vp)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.9)
	env_node.environment = env
	vp.add_child(env_node)
	var identity := HunterRoster.get_identity(hunter_id) if not hunter_id.is_empty() else {}
	var model: Node3D = NightWatchHunterScale.instantiate(identity) if not identity.is_empty() else null
	if model != null:
		vp.add_child(model)
		var cam := Camera3D.new()
		cam.fov = 28.0
		vp.add_child(cam)
		cam.look_at_from_position(Vector3(0, 2.2, -4.2), Vector3(0, 1.8, 0), Vector3.UP)   # a 1.5x hunter is about 2.6 m tall: further back and higher to frame the whole body
	var rec := _label("● REC", 5, RED_TEXT)
	rec.name = "Rec"
	rec.position = Vector2(4, 3)
	frame.add_child(rec)
	return frame


## Selected = amber text and an amber frame; hover = a lighter background only (never the selected look); keyboard focus keeps the theme's ring.
func _mark_board() -> void:
	for i in mode_buttons.size():
		_style_choice(mode_buttons[i], i == board_mode)
	for t in tile_buttons:
		_style_choice(t, int(t.get_meta("level")) == board_level)


func _style_choice(b: Button, selected: bool) -> void:
	var base := StyleBoxFlat.new()
	base.bg_color = Color(0.024, 0.02, 0.016, 0.8)
	base.border_color = AMBER if selected else Color(0.16, 0.15, 0.12)
	base.set_border_width_all(2 if selected else 1)
	base.set_content_margin_all(4)
	var hover := base.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.13, 0.12, 0.10, 0.95)
	if not selected:
		hover.border_color = Color(0.42, 0.40, 0.33)
	b.add_theme_stylebox_override("normal", base)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_color_override("font_color", AMBER if selected else INK)
	b.add_theme_color_override("font_hover_color", AMBER if selected else INK)


func select_mode(i: int) -> void:
	if i == board_mode and screen == "board" and not tile_buttons.is_empty():
		return
	board_mode = clampi(i, 0, NightWatchModesData.MODES.size() - 1)
	board_level = 0
	_rebuild_board()


func _rebuild_board() -> void:
	var keep := board_mode
	show_screen("board")
	board_mode = keep
	mode_buttons[board_mode].grab_focus()


func select_level(i: int, start := false) -> void:
	var m := mode_data(board_mode)
	if not NightWatchSave.level_open(String(m["id"]), i + 1, bool(m["open"])):
		return
	board_level = i
	_mark_board()
	if start:
		start_selected()


func start_selected() -> void:
	var m := mode_data(board_mode)
	var id := String(m["id"])
	if not NightWatchModeRegistry.playable(id):
		set_toast("%s is not built yet. See docs/NIGHT_WATCH_MODES.md." % String(m["label"]))
		toast_label.text = toast_text
		return
	if not NightWatchSave.level_open(id, board_level + 1, bool(m["open"])):
		set_toast("That shift is locked.")
		return
	var path := NightWatchModeRegistry.prepare(id, board_level + 1)
	if not path.is_empty():
		get_tree().change_scene_to_file(path)


# --- custom night --------------------------------------------------------------------------------------------------------------

func custom_modes() -> Array:
	var out := []
	for m in NightWatchModesData.MODES:
		if not (m["presets"] as Array).is_empty():
			out.append(m)
	return out


func custom_open_modes() -> Array:
	var out := []
	for m in custom_modes():
		if NightWatchSave.custom_unlocked(String(m["id"])):
			out.append(m)
	return out


func custom_current() -> Dictionary:
	var open := custom_open_modes()
	for m in open:
		if String(m["id"]) == String(custom_state["mode"]):
			return m
	return open[0] if not open.is_empty() else {}


func custom_values(m: Dictionary) -> Dictionary:
	var saved := NightWatchSave.custom_values(String(m["id"]))
	var out := {}
	for h in m["custom"]:
		var id := String(h["id"])
		var first: Dictionary = (m["presets"] as Array)[0]["ai"]
		out[id] = clampi(int(saved.get(id, first.get(id, 0))), 0, NightWatchModesData.MAX_AI)
	return out


func _build_custom() -> void:
	var m := custom_current()
	if m.is_empty():
		_header("CUSTOM NIGHT")
		var note := _label("CLEAR NIGHT 5 OF A MODE TO OPEN ITS CUSTOM NIGHT.", 7, BODY)
		note.position = Vector2(12, 34)
		_screen_root.add_child(note)
		hint_label.text = "Esc back"
		return
	custom_state["mode"] = String(m["id"])
	var stars_done := NightWatchSave.stars(String(m["id"])).size()
	_header("CUSTOM NIGHT", "%d/%d ★" % [stars_done, (m["presets"] as Array).size()])
	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.position = Vector2(8, 26)
	tabs.add_theme_constant_override("separation", 3)
	_screen_root.add_child(tabs)
	for cm in custom_modes():
		var open := NightWatchSave.custom_unlocked(String(cm["id"]))
		var tb := _button(String(cm["label"]) + ("" if open else " 🔒"), 5)
		tb.name = "Tab_%s" % String(cm["id"])
		tb.disabled = not open
		if String(cm["id"]) == String(m["id"]):
			tb.add_theme_color_override("font_color", AMBER)
		tb.pressed.connect(func():
			custom_state["mode"] = String(cm["id"])
			show_screen("custom"))
		tabs.add_child(tb)
	var vals := custom_values(m)
	var sliders := VBoxContainer.new()
	sliders.name = "Sliders"
	sliders.position = Vector2(8, 42)
	sliders.add_theme_constant_override("separation", 1)
	_screen_root.add_child(sliders)
	for h in m["custom"]:
		var id := String(h["id"])
		var row := HBoxContainer.new()
		row.name = "Row_%s" % id
		row.add_theme_constant_override("separation", 6)
		sliders.add_child(row)
		var name_label := _label(String(h["label"]), 7, INK)
		name_label.custom_minimum_size = Vector2(70, 0)
		row.add_child(name_label)
		var s := HSlider.new()
		s.name = "Slider_%s" % id
		s.min_value = 0
		s.max_value = NightWatchModesData.MAX_AI
		s.step = 1
		s.value = int(vals[id])
		s.custom_minimum_size = Vector2(150, 10)
		row.add_child(s)
		var v := _label(str(int(vals[id])), 7, INK)
		v.name = "Value_%s" % id
		v.custom_minimum_size = Vector2(14, 0)
		row.add_child(v)
		s.value_changed.connect(func(x: float):
			vals[id] = int(x)
			v.text = str(int(x))
			NightWatchSave.set_custom_values(String(m["id"]), vals)
			_update_custom_score(m, vals))
	var presets := HBoxContainer.new()
	presets.name = "Presets"
	presets.position = Vector2(8, 42 + (m["custom"] as Array).size() * 12 + 8)
	presets.add_theme_constant_override("separation", 3)
	_screen_root.add_child(presets)
	for p in m["presets"]:
		var star := "★" if NightWatchSave.stars(String(m["id"])).has(String(p["id"])) else "☆"
		var pb := _button("%s %s" % [star, String(p["name"])], 6)
		pb.name = "Preset_%s" % String(p["id"])
		pb.pressed.connect(func():
			NightWatchSave.set_custom_values(String(m["id"]), p["ai"])
			show_screen("custom"))
		presets.add_child(pb)
	for quick in [["All 0", 0], ["All 10", 10], ["All 20", 20], ["Random", -1]]:
		var qb := _button(String(quick[0]), 6)
		qb.name = "Quick_%s" % String(quick[0]).replace(" ", "")
		qb.pressed.connect(func():
			var v2 := {}
			for h in m["custom"]:
				v2[String(h["id"])] = int(quick[1]) if int(quick[1]) >= 0 else randi_range(0, NightWatchModesData.MAX_AI)
			NightWatchSave.set_custom_values(String(m["id"]), v2)
			show_screen("custom"))
		presets.add_child(qb)
	var score := _label("", 7, INK)
	score.name = "Score"
	score.position = Vector2(8, 42 + (m["custom"] as Array).size() * 12 + 28)   # the preset row is 16 px high on the Mac and 17 on Windows (font metrics)
	_screen_root.add_child(score)
	_update_custom_score(m, vals)
	var go := _button("▶ START NIGHT", 8)
	go.name = "StartButton"
	go.position = Vector2(190, 224)
	go.pressed.connect(func(): custom_start(m, vals))
	_screen_root.add_child(go)
	hint_label.text = "Esc back"


func custom_score(vals: Dictionary) -> int:
	var total := 0
	for k in vals:
		total += clampi(int(vals[k]), 0, NightWatchModesData.MAX_AI)
	return total * NightWatchModesData.POINTS_PER_LEVEL


func _update_custom_score(m: Dictionary, vals: Dictionary) -> void:
	var score_label := _screen_root.find_child("Score", true, false) as Label
	if score_label == null:
		return
	var max_score: int = (m["custom"] as Array).size() * NightWatchModesData.MAX_AI * NightWatchModesData.POINTS_PER_LEVEL
	var s := custom_score(vals)
	score_label.text = "SCORE %d OF %d · %s · BEST %d" % [s, max_score, NightWatchModesData.rating_of(s, max_score).to_upper(), NightWatchSave.best_score(String(m["id"]))]


func custom_start(m: Dictionary, vals: Dictionary) -> void:
	if custom_score(vals) == 0:
		set_toast("Set at least one hunter above 0.")
		toast_label.text = toast_text
		return
	var path := NightWatchModeRegistry.prepare(String(m["id"]), 1, vals)
	if path.is_empty():
		set_toast("%s is not built yet. See docs/NIGHT_WATCH_MODES.md." % String(m["label"]))
		toast_label.text = toast_text
		return
	get_tree().change_scene_to_file(path)


# --- account -------------------------------------------------------------------------------------------------------------------

func _build_account() -> void:
	_header("ACCOUNT")
	var panel := _panel(_screen_root, "AccountPanel", Rect2(8, 26, 464, 110))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	var signed_in := bool(Backend.signed_in())
	var intro := _label("", 6, BODY)
	intro.name = "Intro"
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.custom_minimum_size = Vector2(450, 0)
	intro.text = ("Signed in as %s." % String(Backend.get("username"))) if signed_in else "Playing as a guest (%s). Sign in or create an account and your guest progress carries over." % NightWatchSave.guest_name()
	col.add_child(intro)
	var u := HBoxContainer.new()
	col.add_child(u)
	var ul := _label("Username", 7, INK)
	ul.custom_minimum_size = Vector2(80, 0)
	u.add_child(ul)
	username_edit = LineEdit.new()
	username_edit.name = "Username"
	username_edit.placeholder_text = "3-24 CHARS: A-Z 0-9 _"
	username_edit.custom_minimum_size = Vector2(150, 12)
	username_edit.add_theme_font_size_override("font_size", 6)
	u.add_child(username_edit)
	var p := HBoxContainer.new()
	col.add_child(p)
	var pl := _label("Password", 7, INK)
	pl.custom_minimum_size = Vector2(80, 0)
	p.add_child(pl)
	password_edit = LineEdit.new()
	password_edit.name = "Password"
	password_edit.placeholder_text = "6+ characters"
	password_edit.secret = true
	password_edit.custom_minimum_size = Vector2(150, 12)
	password_edit.add_theme_font_size_override("font_size", 6)
	p.add_child(password_edit)
	var note := _label("Usernames are CAPS only and shared with Last Route and KT: Systems.", 6, BODY)
	note.name = "Note"
	col.add_child(note)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	var sign_in := _button("SIGN IN", 6)
	sign_in.name = "SignInButton"
	sign_in.pressed.connect(func(): _account_submit(false))
	row.add_child(sign_in)
	var create := _button("CREATE ACCOUNT", 6)
	create.name = "CreateButton"
	create.pressed.connect(func(): _account_submit(true))
	row.add_child(create)
	account_status = _label("", 6, AMBER)
	account_status.name = "AccountStatus"
	col.add_child(account_status)
	hint_label.text = "Esc back"


func _account_submit(create: bool) -> void:
	var name_value := username_edit.text.strip_edges().to_upper()
	if name_value.length() < 3 or password_edit.text.length() < 6:
		account_status.text = "Enter a username (3-24 characters) and a password (6+)."
		return
	account_status.text = "Working..."
	if create:
		Backend.account_register(name_value, password_edit.text)
	else:
		Backend.account_login(name_value, password_edit.text)


func _on_account_changed(signed_in: bool, username: String, _admin: bool, message: String) -> void:
	if screen == "account" and account_status != null:
		account_status.text = message if not message.is_empty() else ("Signed in as %s." % username if signed_in else "Signed out.")


# --- settings ------------------------------------------------------------------------------------------------------------------

func _build_settings() -> void:
	_header("SETTINGS")
	var panel := _panel(_screen_root, "SettingsPanel", Rect2(8, 48, 464, 100))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 5)
	panel.add_child(col)
	var vol := HBoxContainer.new()
	col.add_child(vol)
	var vl := _label("Volume", 7, INK)
	vl.custom_minimum_size = Vector2(300, 0)
	vol.add_child(vl)
	volume_slider = HSlider.new()
	volume_slider.name = "VolumeSlider"
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value = Settings.master_volume_percent
	volume_slider.custom_minimum_size = Vector2(130, 10)
	volume_slider.value_changed.connect(func(v: float): Settings.set_master_volume(v))
	vol.add_child(volume_slider)
	var calm := HBoxContainer.new()
	col.add_child(calm)
	var cl := _label("Calm mode (no lamp flicker or glitching)", 7, INK)
	cl.custom_minimum_size = Vector2(300, 0)
	calm.add_child(cl)
	calm_check = CheckBox.new()
	calm_check.name = "CalmCheck"
	calm_check.button_pressed = NightWatchSave.calm()
	calm_check.toggled.connect(func(on: bool):
		NightWatchSave.set_calm(on)
		Settings.set_reduced_motion(on))
	calm.add_child(calm_check)
	var sc := HBoxContainer.new()
	col.add_child(sc)
	var sl := _label("Scare (Short: a quick one · Off: just the card)", 7, INK)
	sl.custom_minimum_size = Vector2(300, 0)
	sc.add_child(sl)
	scare_button = _button(NightWatchSave.scare().capitalize(), 6)
	scare_button.name = "ScareButton"
	scare_button.pressed.connect(cycle_scare)
	sc.add_child(scare_button)
	var er := HBoxContainer.new()
	col.add_child(er)
	var el := _label("Erase progress (your account)", 7, INK)
	el.custom_minimum_size = Vector2(300, 0)
	er.add_child(el)
	erase_button = _button("ERASE", 6)
	erase_button.name = "EraseButton"
	erase_button.pressed.connect(erase_pressed)
	er.add_child(erase_button)
	hint_label.text = "Esc back"


func cycle_scare() -> void:
	var list: Array = NightWatchSave.SCARE_SETTINGS
	var next := String(list[(list.find(NightWatchSave.scare()) + 1) % list.size()])
	NightWatchSave.set_scare(next)
	Settings.set_short_death_scenes(next == "short" or next == "off")
	scare_button.text = next.capitalize()


## The first press arms it ("SURE?"), the second erases Night Watch's progress (not the account).
func erase_pressed() -> void:
	if not _erase_armed:
		_erase_armed = true
		erase_button.text = "SURE?"
		return
	NightWatchSave.reset()
	_erase_armed = false
	erase_button.text = "ERASED"
	set_toast("")


# --- credits -------------------------------------------------------------------------------------------------------------------

const CREDITS := [
	["", "Night Watch is an unofficial fan project, made for fun and not affiliated with or endorsed by anyone below."],
	["INSPIRED BY", "The Five Nights at Freddy's series by Scott Cawthon, including its sequels, Sister Location, Pizzeria Simulator and the Help Wanted games, and the community that documented how they work."],
	["MADE BY", "Kyttu's Lab. Characters are from The Last Route. Office art, menus and code are original to this project."],
	["SOUND", "All sound is synthesized in the game for now."],
]


func _build_credits() -> void:
	_header("CREDITS")
	var panel := _panel(_screen_root, "CreditsPanel", Rect2(8, 26, 464, 170))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)
	for entry in CREDITS:
		if not String(entry[0]).is_empty():
			var h := _label(String(entry[0]), 7, AMBER)
			col.add_child(h)
		var body := _label(String(entry[1]), 6, INK)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(450, 0)
		col.add_child(body)
	hint_label.text = "Esc back"


# --- input ---------------------------------------------------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE:
		go_back()
		get_viewport().set_input_as_handled()
		return
	match screen:
		"title":
			if key == KEY_DOWN or key == KEY_UP:
				var step := 1 if key == KEY_DOWN else -1
				title_index = posmod(title_index + step, title_buttons.size())
				_title_select(title_index)
				title_buttons[title_index].grab_focus()
				get_viewport().set_input_as_handled()
		"board":
			if key == KEY_DOWN or key == KEY_UP:
				select_mode(posmod(board_mode + (1 if key == KEY_DOWN else -1), NightWatchModesData.MODES.size()))
				get_viewport().set_input_as_handled()
			elif key == KEY_LEFT or key == KEY_RIGHT:
				var count := tile_buttons.size()
				var i := board_level
				for _step in count:
					i = posmod(i + (1 if key == KEY_RIGHT else -1), count)
					if not tile_buttons[i].disabled:
						break
				select_level(i)
				get_viewport().set_input_as_handled()
			elif key == KEY_ENTER or key == KEY_KP_ENTER or key == KEY_SPACE:
				start_selected()
				get_viewport().set_input_as_handled()


## Every piece of text on the current screen, in reading order: what the parity validator compares with the 2D game's.
func visible_texts() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_texts(_screen_root, out)
	return out


func _collect_texts(node: Node, out: PackedStringArray) -> void:
	if node is Control and not (node as Control).visible:
		return
	if node is SubViewport or node is SubViewportContainer:
		return
	if node is Label and not (node as Label).text.is_empty():
		out.append((node as Label).text)
	elif node is Button and not (node as Button).text.is_empty():
		out.append((node as Button).text)
	elif node is LineEdit:
		out.append((node as LineEdit).placeholder_text)
	for c in node.get_children():
		_collect_texts(c, out)
