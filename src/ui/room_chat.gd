class_name RoomChat
extends CanvasLayer

## SPOKEN room chat (like R.E.P.O.): a typed line is said aloud by every client in range with the OS text-to-speech voice of
## its sender (DisplayServer.tts_speak), louder the closer they are (25 m on the same level, quieter through walls, silent
## beyond); TEAM lines also reach everyone as a quieter "radio". It shows as a speech bubble over the speaker and a short
## subtitle at the bottom (Settings.voice_subtitles); there is no on-screen log, only a small history in the pause menu.
## Speaking makes a noise for the hunters (louder for SHOUTED lines). Without TTS voices it falls back to subtitles + a blip.
##
## Room chat shared by the finite and Infinite scenes. Transport derives the sender name from RoomState; clients never get to
## claim another player's identity in the message packet.
##
## Bottom-left above the stamina bar: while closed only fresh lines show and fade FADE_AFTER seconds after the last one; open
## (chat key / CHAT touch button) it shows the scrollable history and the input with its channel toggle. Lines read
## "[TEAM] 12:04 CALLSIGN  text", the callsign in the sender's peer colour; NEARBY lines from further than NEARBY_RANGE on the
## same level are greyed, NEARBY lines from another level are not shown; system lines are amber. Quick chat (quick_chat
## action: ` key, D-pad up, Quest left X, QUICK touch button) opens a radial of presets that send a line plus a map ping.

signal open_changed(shown: bool)
## A quick-chat ping to show on the maps: map position (scene units, like player marks), depth, label, the sender's colour.
signal ping_posted(peer_id: int, at: Vector2, depth: int, label: String, colour: Color)

const MAX_VISIBLE_MESSAGES := 5
const HISTORY_MAX := 60
const MAX_WIDTH := 220.0
const MAX_HEIGHT_FRACTION := .25
const FADE_AFTER := 8.0
const FADE_SECONDS := 1.5
const SAFE_MARGIN := 8.0
## Bottom of the panel, measured from the window bottom: clear of the hotbar and stamina bar; its top stays below the
## interaction prompt under the crosshair (PROMPT_CLEARANCE from the window centre).
const BOTTOM_CLEARANCE := 58.0
const PROMPT_CLEARANCE := 34.0
const FONT_SIZE := 9
const NEARBY_RANGE := 25.0
const TEAM_RADIO_VOLUME := 0.35
const OCCLUDED_FACTOR := 0.5
const SUBTITLE_SECONDS := 4.0
const BUBBLE_SECONDS := 3.5
const HISTORY_SIZE := 12
## The pause menu's short history of what was said: {peer, name, text, channel, system}.
static var history: Array = []
const QUICK_ACTION := "quick_chat"
const PRESETS := ["OVER HERE!", "HUNTER!", "RELAY HERE", "NEED LIGHT", "HIDE!", "FOLLOW ME", "THANKS", "YES", "NO"]
const QUICK_RADIUS := 52.0

var remotes: RemotePlayers
## Scene hook: the hunter the player aims at, {"at": Vector2 map position, "depth": int} or {} (for "HUNTER!").
var hunter_aim_provider := Callable()
var channel := "team"
var _panel: PanelContainer
var _log: RichTextLabel
var _field: LineEdit
var _channel_button: Button
var _entries: Array = []
var _messages: Array[String] = []
var _open := false
var _fresh_left := 0.0
var _view_size := Vector2.ZERO
var _subtitle: Label
var _subtitle_left := 0.0
## What was last spoken (tests): {text, voice, volume, pitch, rate, blip}.
var last_spoken := {}
var _quick: Control
var _quick_buttons: Array[Button] = []
var _quick_open := false
var _quick_sticky := false
var _quick_held_ms := 0
var _quick_pick := -1
var _quick_mouse := Vector2.ZERO


static func attach(parent: Node, transport: RemotePlayers) -> RoomChat:
	var chat := RoomChat.new()
	chat.name = "RoomChat"
	chat.remotes = transport
	parent.add_child(chat)
	return chat


static func ensure_quick_action() -> void:
	if InputMap.has_action(QUICK_ACTION):
		return
	InputMap.add_action(QUICK_ACTION)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_QUOTELEFT
	InputMap.action_add_event(QUICK_ACTION, key)
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_DPAD_UP
	InputMap.action_add_event(QUICK_ACTION, pad)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 90
	ensure_quick_action()
	_build_ui()
	_build_quick()
	if remotes != null:
		remotes.chat_message.connect(_on_chat_message)


func _process(delta: float) -> void:
	_fresh_left = maxf(0.0, _fresh_left - delta)
	_subtitle_left = maxf(0.0, _subtitle_left - delta)
	_subtitle.visible = _subtitle_left > 0.0
	_subtitle.modulate.a = clampf(_subtitle_left / 0.6, 0.0, 1.0)
	if _subtitle.visible:
		var view := get_viewport().get_visible_rect().size
		_subtitle.custom_minimum_size.x = minf(320.0, view.x - 2.0 * SAFE_MARGIN)
		_subtitle.reset_size()
		_subtitle.position = Vector2((view.x - _subtitle.size.x) * .5, view.y - BOTTOM_CLEARANCE - _subtitle.size.y - 2.0)
	_refresh_panel()
	_update_quick()


## Screen rect the panel occupies (zero-size while collapsed).
func subtitle_rect() -> Rect2:
	return Rect2(_subtitle.position, _subtitle.size) if _subtitle.visible else Rect2()


func panel_rect() -> Rect2:
	return Rect2(_panel.position, _panel.size) if _panel.visible else Rect2()


func _refresh_panel() -> void:
	var has_messages := not _messages.is_empty()
	var show_log := false   # spoken chat: no on-screen log (the pause menu keeps a short history)
	_log.visible = show_log
	(_field.get_parent() as Control).visible = _open
	_panel.visible = _open or show_log
	_panel.modulate.a = 1.0 if _open else clampf(_fresh_left / FADE_SECONDS, 0.0, 1.0)
	if not _panel.visible:
		return
	var view := get_viewport().get_visible_rect().size
	var width := minf(MAX_WIDTH, view.x * .45)
	var inner := width - _panel_margin().x
	_log.custom_minimum_size.x = inner
	var bottom := view.y - BOTTOM_CLEARANCE
	# phones: the on-screen keyboard never covers the input
	var keyboard_px := DisplayServer.virtual_keyboard_get_height() if _open else 0
	if keyboard_px > 0:
		var scale := get_viewport().get_final_transform().get_scale().y
		bottom = minf(bottom, view.y - float(keyboard_px) / maxf(scale, .01) - 4.0)
	var input_h: float = (_field.get_parent() as Control).get_combined_minimum_size().y + 4.0 if _open else 0.0
	var max_h := minf(view.y * MAX_HEIGHT_FRACTION, bottom - (view.y * 0.5 + PROMPT_CLEARANCE))
	if _open:
		max_h = maxf(max_h, view.y * MAX_HEIGHT_FRACTION)   # the open history may rise past the prompt line
	var log_h := minf(_log.get_content_height() if show_log else 0.0,
		maxf(0.0, max_h - _panel_margin().y - input_h))
	_log.custom_minimum_size.y = log_h
	var column_min := (_panel.get_child(0) as Control).get_combined_minimum_size()
	var height := maxf(_panel.get_combined_minimum_size().y, column_min.y + _panel_margin().y)
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.offset_left = SAFE_MARGIN
	_panel.offset_right = SAFE_MARGIN + width
	_panel.offset_bottom = bottom
	_panel.offset_top = bottom - height
	_panel.size = Vector2(width, height)
	_view_size = view


func _panel_margin() -> Vector2:
	var box := _panel.get_theme_stylebox("panel")
	return box.get_minimum_size() if box != null else Vector2.ZERO


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		if event.is_action_pressed("chat"):
			open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if _open:
		return
	if event.is_action_pressed(QUICK_ACTION) and not (event is InputEventKey and (event as InputEventKey).echo):
		if _quick_open and _quick_sticky:
			close_quick()
		else:
			open_quick()
		get_viewport().set_input_as_handled()
	elif event.is_action_released(QUICK_ACTION) and _quick_open and not _quick_sticky:
		# a held press: release sends the picked preset; a quick tap keeps the radial open for a click / tap
		if _quick_pick >= 0:
			send_preset(_quick_pick)
			close_quick()
		elif Time.get_ticks_msec() - _quick_held_ms < 250:
			_quick_sticky = true
			MouseLock.claim("quick_chat", true)
		else:
			close_quick()
		get_viewport().set_input_as_handled()
	elif _quick_open and event is InputEventMouseMotion:
		_quick_mouse += (event as InputEventMouseMotion).relative
	elif _quick_open and event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close_quick()
		get_viewport().set_input_as_handled()


func open() -> void:
	close_quick()
	_open = true
	MouseLock.claim("room_chat", true)
	_field.clear()
	_field.call_deferred("grab_focus")
	DisplayServer.virtual_keyboard_show("", Rect2(), DisplayServer.KEYBOARD_TYPE_DEFAULT, RemotePlayers.MAX_CHAT_LENGTH)
	open_changed.emit(true)


func close() -> void:
	if not _open:
		return
	_open = false
	_fresh_left = FADE_AFTER
	MouseLock.claim("room_chat", false)
	_field.release_focus()
	DisplayServer.virtual_keyboard_hide()
	open_changed.emit(false)


func is_open() -> bool:
	return _open


func set_channel(value: String) -> void:
	channel = value if RemotePlayers.CHAT_CHANNELS.has(value) else "team"
	if _channel_button != null:
		_channel_button.text = channel.to_upper()


func toggle_channel() -> void:
	set_channel("nearby" if channel == "team" else "team")


func _submit(text: String) -> void:
	var message := text.strip_edges()
	if message.is_empty():
		close()
		return
	if remotes != null:
		if remotes.send_chat_payload({"text": message, "channel": channel}):
			_make_speech_noise(message)
		else:
			add_system("NOT SENT // SLOW DOWN OR NO REPEATS")
	close()


## The speaker is heard by the hunters: a noise burst sized by length, louder when shouted.
func _make_speech_noise(text: String) -> void:
	var player := remotes.local_player if remotes != null else null
	if player != null and player.has_method("emit_noise_burst"):
		var noise := noise_for(text)
		player.call("emit_noise_burst", noise.x, noise.y)


## (level 0..1, seconds) of the noise a spoken line makes: longer lines last longer, ALL CAPS or "!" is a shout.
static func noise_for(text: String) -> Vector2:
	var length := mini(text.length(), RemotePlayers.MAX_CHAT_LENGTH)
	var level := 0.25 + 0.35 * float(length) / float(RemotePlayers.MAX_CHAT_LENGTH)
	var letters := text.to_lower() != text.to_upper()
	if text.contains("!") or (letters and text == text.to_upper() and text.length() > 3):
		level *= 1.6
	return Vector2(clampf(level, 0.0, 1.0), 0.8 + float(length) / 40.0)


## Local system line (owner/admin notices arrive through RemotePlayers.send_system as system payloads).
func add_system(text: String) -> void:
	_add_entry({"peer": 0, "name": "", "text": text.to_upper(), "channel": "team", "system": true, "faint": false})


## Backwards-compatible text entry point (tests and older callers): a TEAM line from `display_name`.
func _on_chat_received(peer_id: int, display_name: String, message: String) -> void:
	_on_chat_message(peer_id, display_name, {"text": message, "channel": "team"})


func _on_chat_message(peer_id: int, display_name: String, payload: Dictionary) -> void:
	if Settings.is_player_muted(display_name):
		return   # muted players are neither spoken nor shown
	var own := peer_id == _local_id()
	var system := bool(payload.get("system", false))
	var volume := 1.0 if system else speech_volume(payload, _local_world(), GameState.depth, own,
		_occluded(payload.get("world", Vector3.ZERO)))
	if volume <= 0.0:
		return   # out of range: silent and not shown
	var text := String(payload.get("text", ""))
	var nearby := String(payload.get("channel", "team")) == "nearby"
	_add_entry({"peer": peer_id, "name": display_name, "text": text, "channel": "nearby" if nearby else "team",
		"system": system, "faint": volume < .35})
	if Settings.voice_subtitles:
		show_subtitle(peer_id, display_name, text, system)
	if not system:
		_show_bubble(peer_id, text)
		if speaks_line(Settings.tts_mode, own):
			_speak(text, peer_id, volume, own)
	if bool(payload.get("ping", false)):
		var target = payload.get("target")
		ping_posted.emit(peer_id, target if target is Vector2 else payload.get("at", Vector2.ZERO), int(payload.get("depth", 0)),
			String(payload.get("preset", text)), RemotePlayers.peer_colour(peer_id))


## 0..1 loudness of a line at the listener: NEARBY falls off over NEARBY_RANGE on the same level (OCCLUDED_FACTOR through
## walls), nothing from another level or beyond range; TEAM is at least the quiet TEAM_RADIO_VOLUME for everyone.
static func speech_volume(payload: Dictionary, listener_world: Vector3, listener_depth: int, own: bool, occluded: bool) -> float:
	if own:
		return 1.0
	var proximity := 0.0
	if int(payload.get("depth", listener_depth)) == listener_depth:
		var speaker: Vector3 = payload.get("world", listener_world)
		var flat := Vector2(speaker.x - listener_world.x, speaker.z - listener_world.z).length()
		proximity = clampf(1.0 - flat / NEARBY_RANGE, 0.0, 1.0) * (OCCLUDED_FACTOR if occluded else 1.0)
	if String(payload.get("channel", "team")) == "team":
		return maxf(proximity, TEAM_RADIO_VOLUME)
	return proximity


## Kept for older callers: "clear", "faint" or "hidden" from the speech volume.
static func hear(payload: Dictionary, listener_world: Vector3, listener_depth: int, own: bool) -> String:
	if own or bool(payload.get("system", false)):
		return "clear"
	var volume := speech_volume(payload, listener_world, listener_depth, own, false)
	return "hidden" if volume <= 0.0 else ("faint" if volume < .35 else "clear")


## A wall between the listener's camera and the speaker's head (same physics the footsteps' world uses).
func _occluded(speaker_world) -> bool:
	if not speaker_world is Vector3 or remotes == null or remotes.local_player == null:
		return false
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var space := camera.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, (speaker_world as Vector3) + Vector3(0, 1.4, 0))
	query.collide_with_areas = false
	if remotes.local_player is CollisionObject3D:
		query.exclude = [(remotes.local_player as CollisionObject3D).get_rid()]
	return not space.intersect_ray(query).is_empty()


## A stable voice per peer: one of the OS voices (English first) plus a pitch and rate offset.
static func voice_for(peer_id: int, voices: Array) -> Dictionary:
	var english := voices.filter(func(v: Dictionary) -> bool: return String(v.get("language", "")).begins_with("en"))
	var pool: Array = english if not english.is_empty() else voices
	var id := String((pool[posmod(peer_id * 31 + 7, pool.size())] as Dictionary).get("id", "")) if not pool.is_empty() else ""
	return {"id": id, "pitch": 0.85 + 0.08 * float(posmod(peer_id * 13, 5)), "rate": 0.95 + 0.05 * float(posmod(peer_id * 7, 3))}


## Whether a line is read aloud: never when TTS is "off", only the player's own lines for "own", other players' for "everyone".
static func speaks_line(mode: String, own: bool) -> bool:
	match mode:
		"off":
			return false
		"own":
			return own
	return not own


func _speak(text: String, peer_id: int, volume: float, own: bool = false) -> void:
	if not Settings.voice_enabled:
		last_spoken = {"text": text, "volume": 0, "blip": false, "voice": ""}
		return   # subtitles only
	var voices: Array = DisplayServer.tts_get_voices() if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) else []
	var voice := voice_for(peer_id, voices)
	voice["rate"] = clampf(float(voice["rate"]) * Settings.tts_rate, 0.5, 2.0)
	if not Settings.tts_voice_id.is_empty() and voices.any(func(v: Dictionary) -> bool: return String(v.get("id", "")) == Settings.tts_voice_id):
		voice["id"] = Settings.tts_voice_id
	var loudness := int(round(clampf(volume, 0.0, 1.0) * Settings.voice_volume))
	if String(voice["id"]).is_empty():
		Sound.menu_blip()   # no TTS voice on this device: subtitle + a soft blip
		last_spoken = {"text": text, "volume": loudness, "blip": true, "voice": ""}
		return
	DisplayServer.tts_speak(text, String(voice["id"]), loudness, float(voice["pitch"]), float(voice["rate"]))
	last_spoken = {"text": text, "volume": loudness, "blip": false, "voice": voice["id"], "pitch": voice["pitch"], "rate": voice["rate"]}


func show_subtitle(peer_id: int, display_name: String, text: String, system: bool = false) -> void:
	_subtitle.text = ("// %s" % text) if system else "%s: %s" % [display_name.to_upper(), text]
	_subtitle.add_theme_color_override("font_color", Palette.AMBER if system else RemotePlayers.peer_colour(peer_id).lightened(.3))
	_subtitle_left = SUBTITLE_SECONDS
	_subtitle.visible = true


## A speech bubble over the speaker's head (remote players' bodies) in their colour, for a few seconds.
func _show_bubble(peer_id: int, text: String) -> void:
	var body: Node3D = remotes._bodies.get(peer_id) if remotes != null else null
	if body == null or not is_instance_valid(body):
		return
	var bubble := body.get_node_or_null("SpeechBubble") as Label3D
	if bubble == null:
		bubble = Label3D.new()
		bubble.name = "SpeechBubble"
		bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		bubble.no_depth_test = true
		bubble.font_size = 22
		bubble.outline_size = 6
		bubble.width = 360.0
		bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		bubble.position = Vector3(0, RemotePlayers.NAME_TAG_HEIGHT + 0.32, 0)
		body.add_child(bubble)
	bubble.text = text
	bubble.modulate = Color(RemotePlayers.peer_colour(peer_id).lightened(.25), 1.0)
	bubble.visible = true
	var token := Time.get_ticks_msec()
	bubble.set_meta("shown_at", token)
	get_tree().create_timer(BUBBLE_SECONDS + text.length() * 0.04).timeout.connect(func() -> void:
		if is_instance_valid(bubble) and int(bubble.get_meta("shown_at", 0)) == token:
			bubble.visible = false)


func _local_world() -> Vector3:
	return remotes.local_player.global_position if remotes != null and remotes.local_player != null else Vector3.ZERO


func _local_id() -> int:
	return multiplayer.get_unique_id() if RoomState.online else 1


func _add_entry(entry: Dictionary) -> void:
	entry["time"] = Time.get_time_string_from_system().substr(0, 5)
	_entries.append(entry)
	history.append(entry)
	while history.size() > HISTORY_SIZE:
		history.pop_front()
	while _entries.size() > HISTORY_MAX:
		_entries.pop_front()
	_fresh_left = FADE_AFTER
	_render()


func _render() -> void:
	var lines: Array[String] = []
	for entry_value in _entries:
		lines.append(format_entry(entry_value))
	_messages = lines
	var shown := _messages if _open else _messages.slice(maxi(0, _messages.size() - MAX_VISIBLE_MESSAGES))
	_log.text = "\n".join(shown)


## One rendered line (BBCode): "[TEAM] 12:04 CALLSIGN  text"; NEARBY faint lines greyed; system lines amber.
static func format_entry(entry: Dictionary) -> String:
	var time := "[color=#%s]%s[/color] " % [Palette.MUTED.to_html(false), String(entry.get("time", ""))]
	var text := String(entry.get("text", "")).replace("[", "(")
	if bool(entry.get("system", false)):
		return "%s[color=#%s]// %s[/color]" % [time, Palette.AMBER.to_html(false), text]
	var tag := "[NEAR]" if String(entry.get("channel", "team")) == "nearby" else "[TEAM]"
	var colour := RemotePlayers.peer_colour(int(entry.get("peer", 1)))
	var body := "[color=#%s]%s[/color] %s[color=#%s]%s[/color]  %s" % [Palette.MUTED.to_html(false), tag, time,
		colour.to_html(false), String(entry.get("name", "?")).to_upper(), text]
	if bool(entry.get("faint", false)):
		return "[color=#%s]%s[/color]" % [Palette.DIM.to_html(false), body.replace(colour.to_html(false), Palette.DIM.to_html(false))]
	return body


func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.name = "ChatPanel"
	_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel",
		Palette.panel_box(Color(Palette.PANEL, .88), Palette.PANEL_EDGE, 5))
	add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	_panel.add_child(column)
	_log = RichTextLabel.new()
	_log.name = "ChatLog"
	_log.bbcode_enabled = true
	_log.fit_content = false
	_log.scroll_active = true
	_log.scroll_following = true
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.mouse_filter = Control.MOUSE_FILTER_PASS
	_log.add_theme_font_size_override("normal_font_size", FONT_SIZE)
	column.add_child(_log)
	_log.get_v_scroll_bar().modulate.a = 0.0
	var row := HBoxContainer.new()
	row.name = "ChatInputRow"
	row.add_theme_constant_override("separation", 3)
	column.add_child(row)
	_channel_button = Button.new()
	_channel_button.name = "ChatChannelButton"
	_channel_button.focus_mode = Control.FOCUS_NONE
	_channel_button.add_theme_font_size_override("font_size", 7)
	_channel_button.tooltip_text = "TEAM: everyone // NEARBY: players close by on this level (TAB)"
	Palette.style_button(_channel_button, false, true)
	_channel_button.pressed.connect(toggle_channel)
	row.add_child(_channel_button)
	_field = LineEdit.new()
	_field.name = "ChatInput"
	_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_field.placeholder_text = "SAY SOMETHING // ENTER SPEAKS // TAB CHANNEL"
	_field.max_length = RemotePlayers.MAX_CHAT_LENGTH
	_field.add_theme_font_size_override("font_size", FONT_SIZE)
	_field.text_submitted.connect(_submit)
	_field.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_TAB:
			toggle_channel()
			_field.accept_event())
	row.add_child(_field)
	set_channel(channel)
	_panel.visible = false
	_subtitle = Label.new()
	_subtitle.name = "ChatSubtitle"
	_subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle.add_theme_font_size_override("font_size", FONT_SIZE)
	_subtitle.add_theme_color_override("font_outline_color", Color(0, 0, 0, .9))
	_subtitle.add_theme_constant_override("outline_size", 3)
	var subtitle_box := StyleBoxFlat.new()
	subtitle_box.bg_color = Color(0, 0, 0, .55)
	subtitle_box.set_content_margin_all(3)
	_subtitle.add_theme_stylebox_override("normal", subtitle_box)
	_subtitle.visible = false
	add_child(_subtitle)


# -- quick chat ---------------------------------------------------------------

func _build_quick() -> void:
	_quick = Control.new()
	_quick.name = "QuickChat"
	_quick.set_anchors_preset(Control.PRESET_FULL_RECT)
	_quick.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quick.visible = false
	add_child(_quick)
	for index in PRESETS.size():
		var button := Button.new()
		button.name = "Quick_%d" % index
		button.text = PRESETS[index]
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_font_size_override("font_size", 7)
		Palette.style_button(button, false, true)
		button.pressed.connect(func() -> void:
			send_preset(index)
			close_quick())
		_quick.add_child(button)
		_quick_buttons.append(button)


func quick_is_open() -> bool:
	return _quick_open


func open_quick() -> void:
	if _open:
		return
	_quick_open = true
	_quick_sticky = false
	_quick_pick = -1
	_quick_mouse = Vector2.ZERO
	_quick_held_ms = Time.get_ticks_msec()
	_quick.visible = true


func close_quick() -> void:
	if not _quick_open:
		return
	_quick_open = false
	_quick_sticky = false
	_quick.visible = false
	MouseLock.claim("quick_chat", false)


## Radial layout around the screen centre; the stick / WASD / mouse direction highlights a preset.
func _update_quick() -> void:
	if not _quick_open:
		return
	var view := get_viewport().get_visible_rect().size
	var centre := view * .5
	for index in _quick_buttons.size():
		var angle := -PI * .5 + TAU * float(index) / float(_quick_buttons.size())
		var button := _quick_buttons[index]
		button.reset_size()
		button.position = centre + Vector2(cos(angle), sin(angle)) * QUICK_RADIUS - button.size * .5
	var direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if direction.length() < .5 and _quick_mouse.length() > 18.0:
		direction = _quick_mouse.normalized()
	if direction.length() >= .5:
		_quick_pick = pick_for_direction(direction, _quick_buttons.size())
	for index in _quick_buttons.size():
		Palette.set_state_toggle(_quick_buttons[index], index == _quick_pick)


## The preset a stick/mouse direction points at (index 0 straight up, clockwise).
static func pick_for_direction(direction: Vector2, count: int) -> int:
	var angle := fposmod(atan2(direction.y, direction.x) + PI * .5, TAU)
	return roundi(angle / (TAU / float(count))) % count


## Sends preset `index` as a line on the current channel with a map ping at the player (HUNTER! pings the aimed hunter).
func send_preset(index: int) -> bool:
	if index < 0 or index >= PRESETS.size() or remotes == null:
		return false
	var payload := {"text": PRESETS[index], "preset": PRESETS[index], "channel": channel, "ping": true}
	if PRESETS[index] == "HUNTER!" and hunter_aim_provider.is_valid():
		var hunter: Dictionary = hunter_aim_provider.call()
		if not hunter.is_empty():
			payload["target"] = hunter.get("at", Vector2.ZERO)   # everyone's ping lands on the hunter, not on me
	if not remotes.send_chat_payload(payload):
		add_system("NOT SENT // PINGS ARE RATE LIMITED")
		return false
	_make_speech_noise(PRESETS[index])
	return true
