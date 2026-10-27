class_name GameHub
extends Control

## The shell above the games: boot lands here, each game is a card, and account / settings / admin / quit are shared
## entries that do not belong to any one game. Games come from GameRegistry; a locked game shows its card with the reason
## instead of a launch button.
## The games sit in an ARROW CAROUSEL: one focused card, centred and large, with big left/right arrows at both sides; the
## neighbours peek in smaller and dimmed when they fit whole (never clipped). Left/Right, A/D, the d-pad / shoulders, the
## mouse wheel and a swipe move the selection (wraps around); Enter / Space / PLAY launches the focused game. The card
## scales to fit any window and works for 1..12 games. The last game played is the default focus (Settings.hub_last_game).
## Account opens the shared app-level AccountPanel (one login for every game); settings open the Last Route menu's overlay
## (GameHub.pending_menu_action) until they move out of that scene.

const SIGNAL_BACKDROP_SCRIPT := preload("res://src/ui/signal_backdrop.gd")
const MENU_SCENE := "res://scenes/main_menu.tscn"

const CARD_W := 200.0
const CARD_MIN_H := 118.0
const NEIGHBOUR_SCALE := 0.5
const NEIGHBOUR_ALPHA := 0.45
const GAP := 6.0
const ARROW_W := 20.0
const SLIDE_SECONDS := 0.22
const SWIPE_UNITS := 24.0
const MAX_DOTS := 8

## What the next menu should open on arrival: "", "account" or "settings".
static var pending_menu_action := ""
## Tests: called with the game id instead of changing scene.
static var launch_override := Callable()

var _order: Array = []
var _cards := {}
var _launch_buttons := {}
var _index := 0
var _pos := 0.0
var _tween: Tween
var _stage: Control
var _left_arrow: Button
var _right_arrow: Button
var _dots: HBoxContainer
var _count_label: Label
var _card_h := CARD_MIN_H
var _peek := false
var _drag_start := Vector2.ZERO
var _dragging := false
var _toast: Label
var _signed_in: Label
var _quit_dialog: Control


func _ready() -> void:
	GameRegistry.active_game_id = GameRegistry.DEFAULT_ID
	MouseLock.release_all()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := SIGNAL_BACKDROP_SCRIPT.new()
	backdrop.name = "SignalBackdrop"
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var column := VBoxContainer.new()
	column.name = "HubColumn"
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.offset_left = GAP
	column.offset_right = -GAP
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	var brand := Label.new()
	brand.name = "HubTitle"
	Palette.style_title(brand, Palette.INK)
	brand.add_theme_font_size_override("font_size", 22)
	brand.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brand.text = "KYTTU'S LAB"
	column.add_child(brand)
	_signed_in = Label.new()
	_signed_in.name = "HubSignedIn"
	Palette.style_label(_signed_in, Palette.MUTED, 6)
	column.add_child(_signed_in)
	_refresh_signed_in()
	Backend.account_changed.connect(_on_account_changed)
	var kicker := Label.new()
	kicker.name = "HubKicker"
	Palette.style_label(kicker, Palette.AMBER, 6)
	kicker.text = Palette.track("CHOOSE A GAME")
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(kicker)

	# arrow | stage | arrow
	var row := HBoxContainer.new()
	row.name = "HubCarousel"
	row.add_theme_constant_override("separation", 4)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(row)
	_left_arrow = _arrow_button("LeftArrow", "<", -1)
	row.add_child(_left_arrow)
	_stage = Control.new()
	_stage.name = "HubStage"
	_stage.clip_contents = true
	_stage.focus_mode = Control.FOCUS_ALL
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.custom_minimum_size = Vector2(CARD_W * 0.5, CARD_MIN_H + 4.0)
	_stage.resized.connect(_layout)
	row.add_child(_stage)
	_right_arrow = _arrow_button("RightArrow", ">", 1)
	row.add_child(_right_arrow)
	for game in GameRegistry.all():
		var card := _build_card(game)
		_order.append(String(game["id"]))
		_stage.add_child(card)

	var indicator := HBoxContainer.new()
	indicator.name = "HubIndicator"
	indicator.alignment = BoxContainer.ALIGNMENT_CENTER
	indicator.add_theme_constant_override("separation", 6)
	column.add_child(indicator)
	_dots = HBoxContainer.new()
	_dots.name = "HubDots"
	_dots.add_theme_constant_override("separation", 3)
	_dots.alignment = BoxContainer.ALIGNMENT_CENTER
	indicator.add_child(_dots)
	_count_label = Label.new()
	_count_label.name = "HubCount"
	Palette.style_label(_count_label, Palette.MUTED, 6)
	indicator.add_child(_count_label)

	var footer := HBoxContainer.new()
	footer.name = "HubShared"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 6)
	column.add_child(footer)
	footer.add_child(_shared_button("AccountButton", "ACCOUNT", _on_account))
	footer.add_child(_shared_button("SettingsButton", "SETTINGS", _on_settings))
	var admin := _shared_button("AdminButton", "ADMIN", _on_admin)
	admin.disabled = not Backend.admin_owner_authorized()
	admin.tooltip_text = "Admin tools open inside a run"
	footer.add_child(admin)
	# Web builds have no desktop to quit to; the browser tab is the way out.
	if not OS.has_feature("web"):
		footer.add_child(_shared_button("QuitButton", "QUIT", _ask_quit))
	_toast = Label.new()
	_toast.name = "HubToast"
	Palette.style_label(_toast, Palette.MUTED, 6)
	_toast.custom_minimum_size = Vector2(0, 10)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_toast)
	_refresh_signed_in()

	_index = _initial_index()
	_pos = float(_index)
	_measure_cards.call_deferred()


## The game the hub opens on: the one played last, else the default.
func _initial_index() -> int:
	var wanted := Settings.hub_last_game if Settings.hub_last_game != "" else GameRegistry.DEFAULT_ID
	var found := _order.find(wanted)
	if found < 0:
		found = _order.find(GameRegistry.DEFAULT_ID)
	return maxi(found, 0)


func _measure_cards() -> void:
	if not is_inside_tree():
		return
	# a card's height depends on its wrapped tagline / lock note, so give every card its real width, let the labels re-wrap
	# for a few frames, then read the minimum height at that width
	var previous := -1.0
	for _attempt in 5:
		for id in _cards:
			var card := _cards[id] as Control
			card.visible = true   # hidden cards are never laid out, so their wrapped labels would measure wrong
			card.size = Vector2(CARD_W, CARD_MIN_H)
		await get_tree().process_frame
		if not is_inside_tree():
			return
		var tallest := CARD_MIN_H
		for id in _cards:
			tallest = maxf(tallest, (_cards[id] as Control).get_combined_minimum_size().y)
		_card_h = tallest
		if is_equal_approx(tallest, previous):
			break
		previous = tallest
	_stage.custom_minimum_size = Vector2(CARD_W * 0.5, _card_h + 4.0)
	_layout()
	_update_indicator()
	_focus_current()


func _arrow_button(button_name: String, glyph: String, direction: int) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = glyph
	button.focus_mode = Control.FOCUS_ALL
	button.custom_minimum_size = Vector2(ARROW_W, 40.0)
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Palette.style_button(button, false, true)
	button.pressed.connect(step.bind(direction))
	return button


## Game ids in carousel order and the focused one (for tests and the capture tool).
func game_ids() -> Array:
	return _order


func focused_index() -> int:
	return _index


func focused_id() -> String:
	return String(_order[_index]) if not _order.is_empty() else ""


func card_for(id: String) -> Control:
	return _cards.get(id) as Control


func stage_rect() -> Rect2:
	return _stage.get_global_rect()


func peeking() -> bool:
	return _peek


## Move the selection by `direction` games (wraps around).
func step(direction: int) -> void:
	select(_index + direction)


func select(index: int) -> void:
	var count := _order.size()
	if count == 0:
		return
	index = posmod(index, count)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var delta := _wrapped(float(index) - _pos, count)
	var target := _pos + delta
	_index = index
	_update_indicator()
	if Settings.reduced_motion or not is_inside_tree() or absf(delta) < 0.001:
		_pos = float(index)
		_layout()
		_focus_current()
		return
	_tween = create_tween()
	_tween.set_trans(Tween.TRANS_CUBIC)
	_tween.set_ease(Tween.EASE_OUT)
	_tween.tween_method(_set_pos, _pos, target, SLIDE_SECONDS)
	_tween.finished.connect(func() -> void:
		_pos = float(_index)
		_layout()
		_focus_current())


func _set_pos(value: float) -> void:
	_pos = value
	_layout()


## Shortest circular distance from the focused slot, in (-n/2, n/2].
static func _wrapped(offset: float, count: int) -> float:
	if count <= 1:
		return 0.0
	var half := count * 0.5
	var d := fposmod(offset + half, float(count)) - half
	if is_equal_approx(d, -half) and count % 2 == 0:
		d = half
	return d


func _layout() -> void:
	if _stage == null or _cards.is_empty() or not is_inside_tree():
		return
	var count := _order.size()
	var stage_size := _stage.size
	if stage_size.x <= 0.0 or stage_size.y <= 0.0:
		return
	var base := Vector2(CARD_W, _card_h)
	# the focused card is scaled down to fit a small stage; never up
	var fit := clampf(minf((stage_size.x - 2.0) / base.x, (stage_size.y - 2.0) / base.y), 0.35, 1.0)
	var focused_w := base.x * fit
	var neighbour_w := focused_w * NEIGHBOUR_SCALE
	_peek = count > 1 and stage_size.x >= focused_w + 2.0 * (neighbour_w + GAP) - 0.5
	var step_x := (focused_w + neighbour_w) * 0.5 + GAP if _peek else stage_size.x
	for i in count:
		var id := String(_order[i])
		var card := _cards[id] as Control
		var d := _wrapped(float(i) - _pos, count)
		var ad := absf(d)
		var near := minf(ad, 1.0)
		var x := signf(d) * (step_x * near + stage_size.x * maxf(ad - 1.0, 0.0))
		var s := lerpf(1.0, NEIGHBOUR_SCALE, near) * fit
		card.size = base
		card.pivot_offset = base * 0.5
		card.scale = Vector2(s, s)
		card.position = Vector2(stage_size.x * 0.5 + x, stage_size.y * 0.5) - base * 0.5
		card.modulate.a = lerpf(1.0, NEIGHBOUR_ALPHA, near)
		card.z_index = int((1.0 - near) * 10.0)
		card.visible = ad < 2.0
		var focused := i == _index and ad < 0.5
		var button := _launch_buttons[id] as Button
		button.focus_mode = Control.FOCUS_ALL if focused and not button.disabled else Control.FOCUS_NONE
		button.mouse_filter = Control.MOUSE_FILTER_STOP if focused else Control.MOUSE_FILTER_IGNORE
		_style_play_button(button)
	_link_focus()
	_left_arrow.visible = count > 1
	_right_arrow.visible = count > 1


func _update_indicator() -> void:
	if _dots == null:
		return
	for child in _dots.get_children():
		child.queue_free()
	var count := _order.size()
	if count > 1 and count <= MAX_DOTS:
		var accent := _accent(focused_id())
		for i in count:
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(4, 4)
			dot.color = accent if i == _index else Palette.DIM
			_dots.add_child(dot)
	_count_label.text = "%d / %d" % [_index + 1, count] if count > 1 else ""


## A game's accent colour: the border of its theme's card frame (purple Last Route, amber City, red Night Watch).
func _accent(id: String) -> Color:
	var game := GameRegistry.get_game(id)
	if game.is_empty():
		return Palette.ACCENT
	if game.has("accent"):
		return Color(String(game["accent"]))
	var theme := load(String(game["theme"])) as Theme
	if theme != null:
		var frame := theme.get_stylebox("panel", "GameCard") as StyleBoxFlat
		if frame != null:
			return frame.border_color
	return Palette.ACCENT


## PLAY is built from the NORMAL state only, so no theme (a game theme that forgets pressed/focus/disabled boxes, a hover box
## that goes dark) can leave it unreadable: hover lightens the fill, pressed darkens it, hover+focus is the hover box, focus
## is a 2 px outline with no fill; the label colour of every state is whichever of dark/light ink contrasts better with that
## state's own fill (>= 4.5:1 for any fill that allows it). Disabled/LOCKED keeps the theme's muted look at >= 3:1.
const INK_DARK := Color(0.102, 0.059, 0.078)
const INK_LIGHT := Color(0.949, 0.929, 0.882)


static func _luma(color: Color) -> float:
	var channels := []
	for value in [color.r, color.g, color.b]:
		channels.append(value / 12.92 if value <= 0.03928 else pow((value + 0.055) / 1.055, 2.4))
	return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]


static func _ratio(a: Color, b: Color) -> float:
	var la := _luma(a)
	var lb := _luma(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


static func readable_ink(fill: Color) -> Color:
	return INK_DARK if _ratio(INK_DARK, fill) >= _ratio(INK_LIGHT, fill) else INK_LIGHT


## The first candidate fill an ink reads on at 4.5:1 (mid-tone fills fit neither ink), else the state's own fill.
static func _readable_variant(fallback: Color, candidates: Array) -> Color:
	for candidate in candidates:
		if _ratio(readable_ink(candidate), candidate) >= 4.5:
			return candidate
	return fallback


func _style_play_button(button: Button) -> void:
	if button.has_meta("play_styled") or not button.is_inside_tree():
		return
	button.set_meta("play_styled", true)
	var normal := button.get_theme_stylebox("normal") as StyleBoxFlat
	if normal == null:
		return
	var fill := normal.bg_color
	var pressed_fill := _readable_variant(fill, [fill.darkened(0.1), fill.darkened(0.2), fill.lightened(0.1)])
	var states := {
		"normal": fill,
		"hover": _readable_variant(fill, [fill.lightened(0.12), fill.darkened(0.12), fill.lightened(0.2), fill.darkened(0.2)]),
		"pressed": pressed_fill, "hover_pressed": pressed_fill,
	}
	var label_names := {"normal": "font_color", "hover": "font_hover_color", "pressed": "font_pressed_color",
		"hover_pressed": "font_hover_pressed_color"}
	for state in states:
		var box := normal.duplicate() as StyleBoxFlat
		box.bg_color = states[state]
		button.add_theme_stylebox_override(state, box)
		button.add_theme_color_override(label_names[state], readable_ink(states[state]))
	# focus stays on top of whichever state box is showing; its outline uses the normal label colour
	var outline := StyleBoxFlat.new()
	outline.bg_color = Color(0, 0, 0, 0)
	outline.draw_center = false
	outline.set_border_width_all(2)
	outline.border_color = readable_ink(fill)
	outline.set_corner_radius_all(2)
	button.add_theme_stylebox_override("focus", outline)
	button.add_theme_color_override("font_focus_color", readable_ink(fill))
	# locked: muted fill with an ink that still reads
	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Palette.INSET
	button.add_theme_stylebox_override("disabled", disabled)
	button.add_theme_color_override("font_disabled_color", readable_ink(disabled.bg_color))


## Up/Down move between the focused card's PLAY button and the shared row (Account / Settings / Admin / Quit);
## Left/Right on PLAY are the carousel's (handled in _input), so PLAY keeps them.
func _link_focus() -> void:
	var play := _launch_buttons.get(focused_id()) as Button
	var target: Control = play if play != null and play.focus_mode == Control.FOCUS_ALL else _stage
	var row: Array[Control] = []
	for button_name in ["AccountButton", "SettingsButton", "AdminButton", "QuitButton"]:
		var shared := find_child(button_name, true, false) as Control
		if shared != null and shared.visible:
			row.append(shared)
	for shared in row:
		shared.focus_neighbor_top = shared.get_path_to(target)
	if not row.is_empty():
		target.focus_neighbor_bottom = target.get_path_to(row[0])
		target.focus_neighbor_left = target.get_path_to(target)
		target.focus_neighbor_right = target.get_path_to(target)
		target.focus_neighbor_top = target.get_path_to(target)


func _focus_current() -> void:
	if not is_inside_tree() or _quit_dialog != null:
		return
	var focus_owner := get_viewport().gui_get_focus_owner()
	# keep the focus where the player put it unless it was on a card or the stage
	if focus_owner != null and focus_owner != _stage and not _stage.is_ancestor_of(focus_owner):
		return
	var button := _launch_buttons.get(focused_id()) as Button
	if button != null and is_instance_valid(button) and not button.disabled and button.focus_mode == Control.FOCUS_ALL:
		if button.is_inside_tree():
			button.grab_focus()   # a scene change can take it out of the tree first
	else:
		if _stage.is_inside_tree():
			_stage.grab_focus()   # a scene change can take it out of the tree first


## The header shows who is signed in (and ADMIN) so every menu and the hub agree; Backend is the one source.
func _refresh_signed_in() -> void:
	if _signed_in == null:
		return
	_signed_in.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if Backend.signed_in():
		_signed_in.text = "SIGNED IN // %s%s" % [Backend.account_username, "  [ADMIN]" if Backend.account_admin else ""]
		_signed_in.add_theme_color_override("font_color", Palette.STABLE)
	else:
		_signed_in.text = "NOT SIGNED IN"
		_signed_in.add_theme_color_override("font_color", Palette.MUTED)
	var admin_button := find_child("AdminButton", true, false) as Button
	if admin_button != null:
		admin_button.disabled = not Backend.admin_owner_authorized()
	var account_button := find_child("AccountButton", true, false) as Button
	if account_button != null:
		account_button.text = Backend.account_username if Backend.signed_in() else "ACCOUNT"


func _on_account_changed(_signed_in_now: bool, _username: String, _admin: bool, _message: String) -> void:
	if is_inside_tree():
		_refresh_signed_in()


func _exit_tree() -> void:
	if Backend.account_changed.is_connected(_on_account_changed):
		Backend.account_changed.disconnect(_on_account_changed)
	if _tween != null and _tween.is_valid():
		_tween.kill()


func _build_card(game: Dictionary) -> PanelContainer:
	var id := String(game["id"])
	var locked := bool(game["locked"])
	var card := PanelContainer.new()
	card.name = "Card_%s" % id
	card.custom_minimum_size = Vector2(CARD_W, CARD_MIN_H)
	card.theme = load(String(game["theme"])) as Theme
	card.theme_type_variation = &"LockedGameCard" if locked else &"GameCard"
	card.gui_input.connect(_on_card_input.bind(id))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	card.add_child(box)
	var kicker := Label.new()
	kicker.theme_type_variation = &"KickerLabel"
	kicker.text = String(game["kicker"])
	box.add_child(kicker)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_override("font", Palette.title_font())
	title.text = String(game["title"])
	title.add_theme_color_override("font_color", Palette.INK if not locked else Palette.DIM)
	box.add_child(title)
	var tagline := Label.new()
	tagline.name = "Tagline"
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tagline.custom_minimum_size = Vector2(CARD_W - 20.0, 0)
	tagline.text = String(game["tagline"])
	box.add_child(tagline)
	if bool(game.get("in_progress", false)):
		var progress := Label.new()
		progress.name = "InProgress"
		progress.theme_type_variation = &"KickerLabel"
		progress.text = "IN PROGRESS"
		box.add_child(progress)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(spacer)
	if locked:
		var note := Label.new()
		note.name = "LockedNote"
		note.theme_type_variation = &"MutedLabel"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.custom_minimum_size = Vector2(CARD_W - 20.0, 0)
		note.text = "LOCKED // %s" % String(game["locked_note"])
		box.add_child(note)
	var button := Button.new()
	button.name = "Launch_%s" % id
	button.theme_type_variation = &"PrimaryButton"
	button.text = "LOCKED" if locked else "PLAY"
	button.disabled = locked
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(_launch.bind(id))
	box.add_child(button)
	_cards[id] = card
	_launch_buttons[id] = button
	return card


## Clicking a neighbouring card brings it to the front.
func _on_card_input(event: InputEvent, id: String) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var index := _order.find(id)
		if index >= 0 and index != _index:
			select(index)
			accept_event()


func _shared_button(button_name: String, label: String, handler: Callable) -> Button:
	var button := Button.new()
	button.name = button_name
	button.text = label
	button.focus_mode = Control.FOCUS_ALL
	Palette.style_button(button, false, true)
	button.pressed.connect(handler)
	return button


## "QUIT TO DESKTOP?" The only place that leaves the app. YES sits on the left, NO (the default, focused, safe answer) on
## the right; Esc, NO or a click outside the box closes the question. Esc never quits.
func _ask_quit() -> void:
	if _quit_dialog != null and is_instance_valid(_quit_dialog):
		return
	_quit_dialog = Control.new()
	_quit_dialog.name = "QuitDialog"
	_quit_dialog.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quit_dialog.mouse_filter = Control.MOUSE_FILTER_STOP
	_quit_dialog.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_close_quit_dialog())
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quit_dialog.add_child(dim)
	var panel := PanelContainer.new()
	panel.name = "QuitBox"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_theme_stylebox_override("panel", Palette.panel_box(Palette.PANEL, Palette.ACCENT_EDGE, 10))
	_quit_dialog.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)
	var question := Label.new()
	question.text = "QUIT TO DESKTOP?"
	Palette.style_label(question, Palette.INK, 8)
	box.add_child(question)
	var row := HBoxContainer.new()
	row.name = "QuitChoices"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	box.add_child(row)
	var yes := _shared_button("QuitYesButton", "YES", func() -> void: get_tree().quit())
	var no := _shared_button("QuitNoButton", "NO", _close_quit_dialog)
	row.add_child(yes)
	row.add_child(no)
	# left/right keeps the visual order: YES | NO
	yes.focus_neighbor_right = yes.get_path_to(no)
	no.focus_neighbor_left = no.get_path_to(yes)
	yes.focus_neighbor_left = yes.get_path_to(yes)
	no.focus_neighbor_right = no.get_path_to(no)
	add_child(_quit_dialog)
	if no.is_inside_tree():
		no.grab_focus()   # a scene change can take it out of the tree first


func _close_quit_dialog() -> void:
	if _quit_dialog != null and is_instance_valid(_quit_dialog):
		_quit_dialog.queue_free()
	_quit_dialog = null
	var quit_button := find_child("QuitButton", true, false) as Button
	if quit_button != null:
		if quit_button.is_inside_tree():
			quit_button.grab_focus()   # a scene change can take it out of the tree first


## True while the focus is on the carousel (a card, the stage, an arrow) or nowhere: the shared buttons below keep their
## own left/right navigation.
func _carousel_has_input() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused == null or focused == _stage or focused == _left_arrow or focused == _right_arrow \
		or _stage.is_ancestor_of(focused)


func _input(event: InputEvent) -> void:
	if _quit_dialog != null and is_instance_valid(_quit_dialog):
		return
	if event is InputEventMouseButton:
		_mouse_input(event as InputEventMouseButton)
		return
	if not event.is_pressed():
		return
	var direction := 0
	if event.is_action_pressed("ui_left"):
		direction = -1
	elif event.is_action_pressed("ui_right"):
		direction = 1
	elif event is InputEventKey:
		match (event as InputEventKey).physical_keycode:
			KEY_A:
				direction = -1
			KEY_D:
				direction = 1
	elif event is InputEventJoypadButton:
		match (event as InputEventJoypadButton).button_index:
			JOY_BUTTON_LEFT_SHOULDER:
				direction = -1
			JOY_BUTTON_RIGHT_SHOULDER:
				direction = 1
	if direction != 0 and _carousel_has_input():
		step(direction)
		get_viewport().set_input_as_handled()
		return
	# Enter / Space with nothing focused launches the focused game (a focused PLAY button handles its own press)
	if event.is_action_pressed("ui_accept"):
		var focus_owner := get_viewport().gui_get_focus_owner()
		if focus_owner == null or focus_owner == _stage:
			launch_focused()
			get_viewport().set_input_as_handled()


func _mouse_input(event: InputEventMouseButton) -> void:
	var inside := _stage.get_global_rect().has_point(event.position)
	if event.pressed and inside and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		step(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_dragging = inside
		_drag_start = event.position
	elif _dragging:
		_dragging = false
		var swipe := event.position - _drag_start
		if absf(swipe.x) >= SWIPE_UNITS and absf(swipe.x) > absf(swipe.y) * 1.5:
			step(-1 if swipe.x > 0.0 else 1)
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	# Esc on the hub does nothing, except closing the quit question.
	if event.is_action_pressed("ui_cancel"):
		if _quit_dialog != null and is_instance_valid(_quit_dialog):
			_close_quit_dialog()
		get_viewport().set_input_as_handled()


func launch_focused() -> void:
	_launch(focused_id())


func _launch(id: String) -> void:
	if not GameRegistry.is_launchable(id):
		return
	Settings.set_hub_last_game(id)
	if launch_override.is_valid():
		launch_override.call(id)
		return
	GameRegistry.active_game_id = id
	get_tree().change_scene_to_file(String(GameRegistry.get_game(id)["scene"]))


func _on_account() -> void:
	AccountPanel.open(self)


func _on_settings() -> void:
	pending_menu_action = "settings"
	_launch(GameRegistry.DEFAULT_ID)


func _on_admin() -> void:
	_toast.text = "ADMIN TOOLS OPEN INSIDE A RUN"
