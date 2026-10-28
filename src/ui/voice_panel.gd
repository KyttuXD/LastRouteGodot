class_name VoicePanel
extends ScrollContainer

## Settings -> VOICE: proximity voice chat (on/off, voice activation or push to talk, input device, gain, sensitivity with a live
## level meter, how loud other players are), spoken chat (TTS off / own lines / everyone, rate, OS voice) and one mute + volume row
## per player in the room. Settings only; the microphone itself is VoiceChat's, open only inside an online room.

var meter: ProgressBar
var status: Label
var _column: VBoxContainer
var _mode_button: Button
var _on_button: Button
var _tts_button: Button
var _players_box: VBoxContainer
var _devices: OptionButton
var _voices: OptionButton


func _ready() -> void:
	name = "VoiceSection"
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_column = VBoxContainer.new()
	_column.custom_minimum_size = Vector2(380, 0)
	_column.add_theme_constant_override("separation", 3)
	add_child(_column)
	_heading("VOICE CHAT (NEARBY PLAYERS HEAR YOU, 25 M)")
	var top := _row()
	_on_button = _button(top, "", func() -> void:
		Settings.set_voice_chat(not Settings.voice_chat_on, Settings.voice_mode, Settings.voice_mic_gain,
			Settings.voice_sensitivity, Settings.voice_input_device, Settings.voice_chat_volume)
		_refresh())
	_on_button.name = "VoiceChatOnButton"
	_mode_button = _button(top, "", func() -> void:
		Settings.set_voice_chat(Settings.voice_chat_on, "ptt" if Settings.voice_mode == "vad" else "vad", Settings.voice_mic_gain,
			Settings.voice_sensitivity, Settings.voice_input_device, Settings.voice_chat_volume)
		_refresh())
	_mode_button.name = "VoiceModeButton"
	var device_row := _row()
	_label(device_row, "MIC")
	_devices = OptionButton.new()
	_devices.name = "VoiceDeviceList"
	_devices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_devices.add_theme_font_size_override("font_size", 7)
	device_row.add_child(_devices)
	_devices.item_selected.connect(func(index: int) -> void:
		var device := _devices.get_item_text(index)
		AudioServer.input_device = device
		Settings.set_voice_chat(Settings.voice_chat_on, Settings.voice_mode, Settings.voice_mic_gain,
			Settings.voice_sensitivity, device, Settings.voice_chat_volume))
	_slider("VoiceGainSlider", "MIC GAIN", 0.0, 2.0, 0.05, Settings.voice_mic_gain, func(v: float) -> void:
		Settings.set_voice_chat(Settings.voice_chat_on, Settings.voice_mode, v, Settings.voice_sensitivity,
			Settings.voice_input_device, Settings.voice_chat_volume))
	_slider("VoiceSensitivitySlider", "SENSITIVITY", 0.0, 1.0, 0.05, Settings.voice_sensitivity, func(v: float) -> void:
		Settings.set_voice_chat(Settings.voice_chat_on, Settings.voice_mode, Settings.voice_mic_gain, v,
			Settings.voice_input_device, Settings.voice_chat_volume))
	var meter_row := _row()
	_label(meter_row, "LEVEL")
	meter = ProgressBar.new()
	meter.name = "VoiceLevelMeter"
	meter.min_value = 0.0
	meter.max_value = 1.0
	meter.show_percentage = false
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.custom_minimum_size = Vector2(0, 8)
	meter_row.add_child(meter)
	_slider("VoiceVolumeOthersSlider", "THEIR VOLUME", 0.0, 1.5, 0.05, Settings.voice_chat_volume, func(v: float) -> void:
		Settings.set_voice_chat(Settings.voice_chat_on, Settings.voice_mode, Settings.voice_mic_gain,
			Settings.voice_sensitivity, Settings.voice_input_device, v))
	status = Label.new()
	status.name = "VoiceStatus"
	status.add_theme_font_size_override("font_size", 6)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_column.add_child(status)
	_heading("SPOKEN CHAT (TEXT TO SPEECH)")
	var tts_row := _row()
	_tts_button = _button(tts_row, "", func() -> void:
		var next: String = {"everyone": "off", "off": "own", "own": "everyone"}[Settings.tts_mode]
		Settings.set_tts(next, Settings.tts_rate, Settings.tts_voice_id)
		_refresh())
	_tts_button.name = "TtsModeButton"
	_voices = OptionButton.new()
	_voices.name = "TtsVoiceList"
	_voices.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voices.add_theme_font_size_override("font_size", 7)
	tts_row.add_child(_voices)
	_voices.item_selected.connect(func(index: int) -> void:
		Settings.set_tts(Settings.tts_mode, Settings.tts_rate, String(_voices.get_item_metadata(index))))
	_slider("TtsRateSlider", "SPEECH RATE", 0.5, 2.0, 0.1, Settings.tts_rate, func(v: float) -> void:
		Settings.set_tts(Settings.tts_mode, v, Settings.tts_voice_id))
	_heading("PLAYERS")
	_players_box = VBoxContainer.new()
	_players_box.name = "VoicePlayers"
	_players_box.add_theme_constant_override("separation", 2)
	_column.add_child(_players_box)
	visibility_changed.connect(func() -> void:
		if is_visible_in_tree():
			_refresh_devices()
			_refresh_voices()
			_refresh_players())
	_refresh()
	_refresh_devices()
	_refresh_voices()
	_refresh_players()


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	var voice := _voice()
	meter.value = clampf(voice.mic_level * 6.0, 0.0, 1.0) if voice != null and voice.mic_open else 0.0
	var text := "JOIN A ROOM TO USE VOICE CHAT. THE MICROPHONE IS ONLY OPEN INSIDE A ROOM; NOTHING IS RECORDED OR STORED."
	if voice != null:
		if voice.force_muted:
			text = "THE HOST HAS MUTED YOUR VOICE."
		elif not Settings.voice_chat_on:
			text = "VOICE CHAT IS OFF: YOUR MICROPHONE IS CLOSED."
		elif voice.mic_open:
			text = "MICROPHONE OPEN. %s" % ("HOLD [V] (HEADSET: BOTH STICKS) TO TALK." if Settings.voice_mode == "ptt" else "SPEAK AND THE LEVEL RISES PAST THE BAR TO TRANSMIT.")
	status.text = text


## The room's VoiceChat node, if a room is running.
func _voice() -> VoiceChat:
	for node in get_tree().get_nodes_in_group("voice_chat"):
		return node as VoiceChat
	return null


func _refresh() -> void:
	_on_button.text = "VOICE CHAT: %s" % ("ON" if Settings.voice_chat_on else "OFF")
	_mode_button.text = "VOICE ACTIVATED" if Settings.voice_mode == "vad" else "PUSH TO TALK"
	_tts_button.text = "TTS: %s" % {"everyone": "EVERYONE", "own": "OWN LINES", "off": "OFF"}[Settings.tts_mode]


func _refresh_devices() -> void:
	_devices.clear()
	var current := AudioServer.input_device
	var list := AudioServer.get_input_device_list()
	for i in list.size():
		_devices.add_item(list[i])
		if list[i] == (Settings.voice_input_device if Settings.voice_input_device in list else current):
			_devices.select(i)


func _refresh_voices() -> void:
	_voices.clear()
	_voices.add_item("AUTO (PER PLAYER)")
	_voices.set_item_metadata(0, "")
	var voices: Array = DisplayServer.tts_get_voices() if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH) else []
	for voice in voices:
		var index := _voices.item_count
		_voices.add_item(String(voice.get("name", voice.get("id", "VOICE"))).substr(0, 24))
		_voices.set_item_metadata(index, String(voice.get("id", "")))
		if String(voice.get("id", "")) == Settings.tts_voice_id:
			_voices.select(index)


## One row per other player in the room: MUTE and a volume slider (shared with the pause menu's MUTE buttons).
func _refresh_players() -> void:
	for child in _players_box.get_children():
		child.queue_free()
	var me := RoomState.local_display_name().to_upper()
	var names := []
	for id in RoomState.peers:
		var callsign := String(RoomState.peers[id]).to_upper()
		if callsign != me and not callsign.is_empty() and not names.has(callsign):
			names.append(callsign)
	if names.is_empty():
		var none := Label.new()
		none.text = "NO OTHER PLAYERS IN THE ROOM"
		none.add_theme_font_size_override("font_size", 6)
		_players_box.add_child(none)
		return
	for callsign in names:
		var row := HBoxContainer.new()
		row.name = "VoicePlayer_%s" % callsign
		row.add_theme_constant_override("separation", 4)
		_players_box.add_child(row)
		var mute := CheckBox.new()
		mute.text = "MUTE %s" % callsign
		mute.add_theme_font_size_override("font_size", 7)
		mute.custom_minimum_size = Vector2(150, 0)
		mute.button_pressed = Settings.is_player_muted(callsign)
		mute.toggled.connect(func(on: bool) -> void: Settings.set_player_muted(callsign, on))
		row.add_child(mute)
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.5
		slider.step = 0.05
		slider.value = Settings.player_voice_volume(callsign)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(v: float) -> void: Settings.set_player_voice_volume(callsign, v))
		row.add_child(slider)


func _heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 7)
	label.add_theme_color_override("font_color", Palette.AMBER)
	_column.add_child(label)


func _row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	_column.add_child(row)
	return row


func _label(parent: Node, text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(70, 0)
	label.add_theme_font_size_override("font_size", 7)
	parent.add_child(label)
	return label


func _button(parent: Node, text: String, handler: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 7)
	button.custom_minimum_size = Vector2(0, 16)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(handler)
	parent.add_child(button)
	return button


func _slider(slider_name: String, caption: String, low: float, high: float, step: float, value: float, changed: Callable) -> void:
	var row := _row()
	_label(row, caption)
	var slider := HSlider.new()
	slider.name = slider_name
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(30, 0)
	readout.text = "%.2f" % value
	readout.add_theme_font_size_override("font_size", 7)
	row.add_child(readout)
	slider.value_changed.connect(func(v: float) -> void:
		readout.text = "%.2f" % v
		changed.call(v))
