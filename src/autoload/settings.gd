extends Node

## Project-wide persisted settings (master volume, key bindings, display).
## Loads and applies user://settings.cfg once at startup regardless of which
## scene boots first — the menu and main_3d.tscn both read/write through this
## autoload instead of touching ConfigFile themselves.

## Emitted when the window mode changes, including from the F11 shortcut, so
## an open settings panel does not sit there showing the old state.
signal display_changed
signal visual_changed

const SETTINGS_PATH_DEFAULT := "user://settings.cfg"
## `--profile=NAME` gives each launched instance its own settings file (scripts/run_multi.sh).
var SETTINGS_PATH := RunProfile.path(SETTINGS_PATH_DEFAULT)
const DEFAULT_VOLUME_PERCENT := 100.0
const DEFAULT_SFX_VOLUME_PERCENT := 100.0
const DEFAULT_UI_VOLUME_PERCENT := 100.0
## Radians of turn per pixel of mouse travel. Both first-person controllers
## read this rather than each carrying a constant, so one slider moves the maze
## and the office together -- they were 0.0035 and 0.0022, which felt like two
## different games.
## 0.0030-0.0050 still read as sluggish in play; 0.0075 is the fresh-install
## baseline while preserving a broad accessibility range.
## The slider still spans 0.0005..0.0120, so this only moves where a fresh
## install starts.
const DEFAULT_MOUSE_SENSITIVITY := 0.0075
const MIN_MOUSE_SENSITIVITY := 0.0005
const MAX_MOUSE_SENSITIVITY := 0.0120
const MIN_VOLUME_DB := -80.0
## Fresh installs always receive a visible, persistent pixel-blur treatment.
const DEFAULT_PIXEL_EFFECT_PERCENT := 42.0
const DEFAULT_PLAYER_HUE_DEGREES := 0.0
const DEFAULT_VSYNC := true
const DEFAULT_FPS_LIMIT := 0
const DEFAULT_FIELD_OF_VIEW := 78.0
const MIN_FIELD_OF_VIEW := 60.0
const MAX_FIELD_OF_VIEW := 105.0
## Personal debug preferences are intentionally separate from room state.
## These values may survive a restart, but they are only ever applied after
## AdminMenu's Build.tools_enabled() gate has successfully attached a menu.
## World edits (hunters, relays, lights, rebuilt maps) remain session-only.
const ADMIN_PREFERENCE_DEFAULTS := {
	"no_target": false,
	"god_mode": false,
	"noclip": false,
	"map_reveal": false,
	"region_map": false,
	"show_collision": false,
	"hunter_reveal": false,
	"pixel_effect_enabled": true,
}

## The design size every 2D layout is authored against, and the project's
## stretch viewport. With stretch/aspect "expand" this is a MINIMUM, not a
## fixed frame: a window that is not 16:9 shows more of the scene rather than
## black bars, which is why every top-level Control is anchored to an edge.
const DISPLAY_BASE := Vector2i(480, 270)
## Largest share of the usable desktop a windowed session may open at. Below 1
## so the window does not start pinned under a taskbar or hanging off the
## bottom of a laptop screen.
const WINDOW_SCREEN_SHARE := 0.85

## Office Mode's controls live in their own action namespace (office_*),
## mirroring the original's deliberate split: rebinding a Last Route key can
## never collide with or silently clear an Office one, so the two sets can
## share physical keys freely. The office_camera_N bank is intentionally not
## rebindable — it's a fixed 1-8 hotbar, same as the original.
const REBINDABLE_ACTIONS: Array[String] = [
	"move_left", "move_right", "move_up", "move_down",
	"look_left", "look_right", "look_up", "look_down",
	"sprint", "crouch", "jump", "flashlight", "taser", "tool_use", "interact",
	"inventory", "drop_item", "chat", "toggle_map", "pause",
	"office_left_door", "office_right_door", "office_desk_light",
	"office_vent", "office_cameras", "office_radio", "office_breaker",
	"office_reboot", "office_emergency_flash", "office_rear_flash",
]

var master_volume_percent := DEFAULT_VOLUME_PERCENT
var sfx_volume_percent := DEFAULT_SFX_VOLUME_PERCENT
var ui_volume_percent := DEFAULT_UI_VOLUME_PERCENT
var mouse_sensitivity := DEFAULT_MOUSE_SENSITIVITY
var fullscreen := false
var vsync_enabled := DEFAULT_VSYNC
var fps_limit := DEFAULT_FPS_LIMIT
var field_of_view := DEFAULT_FIELD_OF_VIEW
var pixel_effect_percent := DEFAULT_PIXEL_EFFECT_PERCENT
## Accessibility: no fades or typing animation; the death moment shows its whole line at once.
var reduced_motion := false
## OpenXR comfort (XRComfort): the player's real standing height (world scale makes them a 1.60 m runner), smooth or snap
## turning, the movement vignette and seated mode. Ignored outside XR.
var xr_player_height := 1.70
## Phone movement control (TouchControls): "dpad" (fixed arrows, double tap to sprint) or "stick" (floating stick).
var touch_move := "dpad"
## Phone touch look (TouchControls.look_turn): speed (1.0 = 180 degrees per drag across the short side), vertical
## speed relative to horizontal, invert Y, smoothing "off" / "low" / "high", and flick acceleration.
var touch_look_speed := 1.0
var touch_look_vertical := 0.8
var touch_look_invert_y := false
var touch_look_smoothing := "off"
var touch_look_accel := false
var xr_smooth_turn := false
var xr_vignette := true
var xr_seated := false
## GRAPHICS: "AUTO" (PlatformProfile's detected tier with live adaptation) or a fixed LOW / MEDIUM / HIGH / ULTRA.
var graphics_quality := "AUTO"
const GRAPHICS_CHOICES := ["AUTO", "LOW", "MEDIUM", "HIGH", "ULTRA"]
## Death moment plays its whole line and closes after 2.5 s instead of typing it and waiting 7 s.
var short_death_scenes := false
## Open the pause menu when the window loses focus. Default ON only in release builds; always OFF in debug, BETA and
## TEST SERVER builds so two windows can be played side by side. focus_loss_pauses() also refuses with other players.
var pause_on_focus_loss := false
## Spoken chat (RoomChat): text-to-speech volume 0..100, voices on/off (off = subtitles only), subtitles, locally muted
## players (by callsign, upper case).
var voice_volume := 80.0
var voice_enabled := true
var voice_subtitles := true
var muted_players: Array = []
## Proximity voice chat (VoiceChat): on/off, "vad" (voice activated) or "ptt" (push to talk, the push_to_talk action), mic gain
## 0..2, activation sensitivity 0..1 (higher hears quieter speech), input device name, loudness of other players 0..1.5 and
## per-player volumes by callsign. Spoken chat (RoomChat) reads aloud "everyone" else, only "own" lines, or nobody ("off") at
## tts_rate 0.5..2 with an optional OS voice id ("" = a stable voice per player).
var voice_chat_on := false
var voice_mode := "vad"
var voice_mic_gain := 1.0
var voice_sensitivity := 0.5
var voice_input_device := "Default"
var voice_chat_volume := 1.0
var voice_player_volumes := {}
var tts_mode := "everyone"
## Settings -> MODS: fetch missing room mod packs without asking. Off by default; downloads are other players' content.
var auto_download_mods := false
var tts_rate := 1.0
var tts_voice_id := ""
## The game the hub focuses when it opens (the one launched last); "" until a game was launched.
var hub_last_game := ""
## 0 preserves the authored skin; 1..360 selects a lightweight texture tint.
var player_hue_degrees := DEFAULT_PLAYER_HUE_DEGREES
## The custom player skin (PlayerSkin): sha256 of its canonical PNG in user://skins, "" = the default mannequin skin.
var skin_hash := ""
## Whether other players may COPY your skin in co-op (SKIN tab). Honoured by their game; the skin itself is visible either way.
var skin_copyable := true
## In-world ads (flavour, TrollAds): "off" (default), "gentle" or "annoying". Troll mode overrides it for cheaters.
var ads_mode := "off"
## The arm style of the skin: skin_slim is what the skin's own pixels said when it was picked (Alex = transparent 4th arm column, or the
## Minecraft profile's model); skin_arms is the player's choice: "auto" follows the skin, "classic" (Steve) / "slim" (Alex) force it.
var skin_slim := false
var skin_arms := "auto"
## Waypoint HUD (docs/WAYPOINTS.md): guidance "off" (pin only), "arrow" (pin + screen-edge arrow), "path" (+ floor chevrons).
const WAYPOINT_GUIDANCE_MODES := ["off", "arrow", "path"]
var waypoint_guidance := "arrow"
var waypoint_show_distance := true
var waypoint_scale := 1.0
var waypoint_opacity := 0.9
var waypoint_arrival_chime := true
var _admin_preferences: Dictionary = ADMIN_PREFERENCE_DEFAULTS.duplicate()

var _master_bus_index := -1
var _sfx_bus_index := -1
var _ui_bus_index := -1
var _default_bindings := {}


func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index("Master")
	_sfx_bus_index = AudioServer.get_bus_index("SFX")
	_ui_bus_index = AudioServer.get_bus_index("UI")
	_capture_default_bindings()
	_load()
	_apply_display()


## F11 anywhere. Handled by the autoload rather than per-scene so it works on
## the menu, in a run and in the office without three copies of it, and it is
## deliberately not in REBINDABLE_ACTIONS -- it is a window control, not a
## gameplay one.
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		set_fullscreen(not fullscreen)
		get_viewport().set_input_as_handled()


func set_fullscreen(on: bool) -> void:
	if fullscreen == on:
		return
	fullscreen = on
	_apply_display()
	_save()
	display_changed.emit()


func set_master_volume(percent: float) -> void:
	master_volume_percent = clampf(percent, 0.0, 100.0)
	_apply_volume()
	_save()


func set_sfx_volume(percent: float) -> void:
	sfx_volume_percent = clampf(percent, 0.0, 100.0)
	_apply_volume()
	_save()


func set_ui_volume(percent: float) -> void:
	ui_volume_percent = clampf(percent, 0.0, 100.0)
	_apply_volume()
	_save()


func set_vsync(enabled: bool) -> void:
	vsync_enabled = enabled
	_apply_display_performance()
	_save()
	display_changed.emit()


static func default_pause_on_focus_loss() -> bool:
	return not (OS.is_debug_build() or Build.is_beta() or OS.has_feature("test_server"))


func set_pause_on_focus_loss(enabled: bool) -> void:
	pause_on_focus_loss = enabled
	_save()


## True when losing window focus may open the pause menu: the setting is on and the run is purely solo (no room,
## public route or other players). Text focus and open overlays are checked by PauseMenu.
func focus_loss_pauses() -> bool:
	if not pause_on_focus_loss:
		return false
	return not (RoomState.online or RoomState.public_route or RoomState.peers.size() > 1)


func set_graphics_quality(choice: String) -> void:
	graphics_quality = choice if GRAPHICS_CHOICES.has(choice) else "AUTO"
	PlatformProfile.set_graphics_quality(graphics_quality)
	_save()


func set_touch_look(speed: float, vertical: float, invert_y: bool, smoothing: String, accel: bool) -> void:
	touch_look_speed = clampf(speed, 0.25, 3.0)
	touch_look_vertical = clampf(vertical, 0.3, 1.5)
	touch_look_invert_y = invert_y
	touch_look_smoothing = smoothing if ["off", "low", "high"].has(smoothing) else "off"
	touch_look_accel = accel
	_save()


func set_touch_move(mode: String) -> void:
	touch_move = "stick" if mode == "stick" else "dpad"
	_save()


func set_xr_comfort(height: float, smooth_turn: bool, vignette: bool, seated: bool) -> void:
	xr_player_height = clampf(height, 1.0, 2.3)
	xr_smooth_turn = smooth_turn
	xr_vignette = vignette
	xr_seated = seated
	_save()


func set_voice(volume: float, enabled: bool, subtitles: bool) -> void:
	voice_volume = clampf(volume, 0.0, 100.0)
	voice_enabled = enabled
	voice_subtitles = subtitles
	_save()


func set_voice_chat(on: bool, mode: String, gain: float, sensitivity: float, device: String, volume: float) -> void:
	voice_chat_on = on
	voice_mode = mode if mode in ["vad", "ptt"] else "vad"
	voice_mic_gain = clampf(gain, 0.0, 2.0)
	voice_sensitivity = clampf(sensitivity, 0.0, 1.0)
	voice_input_device = device if not device.is_empty() else "Default"
	voice_chat_volume = clampf(volume, 0.0, 1.5)
	_save()


func set_auto_download_mods(on: bool) -> void:
	auto_download_mods = on
	_save()


func set_tts(mode: String, rate: float, voice_id: String) -> void:
	tts_mode = mode if mode in ["off", "own", "everyone"] else "everyone"
	tts_rate = clampf(rate, 0.5, 2.0)
	tts_voice_id = voice_id
	_save()


## Loudness multiplier 0..1.5 for one player's voice chat (1 unless set).
func player_voice_volume(callsign: String) -> float:
	return clampf(float(voice_player_volumes.get(callsign.strip_edges().to_upper(), 1.0)), 0.0, 1.5)


func set_player_voice_volume(callsign: String, volume: float) -> void:
	var key := callsign.strip_edges().to_upper()
	if is_equal_approx(volume, 1.0):
		voice_player_volumes.erase(key)
	else:
		voice_player_volumes[key] = clampf(volume, 0.0, 1.5)
	_save()


func is_player_muted(callsign: String) -> bool:
	return muted_players.has(callsign.strip_edges().to_upper())


func set_player_muted(callsign: String, muted: bool) -> void:
	var key := callsign.strip_edges().to_upper()
	if muted and not muted_players.has(key):
		muted_players.append(key)
	elif not muted:
		muted_players.erase(key)
	_save()


func set_reduced_motion(enabled: bool) -> void:
	reduced_motion = enabled
	_save()


func set_hub_last_game(id: String) -> void:
	if hub_last_game != id:
		hub_last_game = id
		_save()


func set_short_death_scenes(enabled: bool) -> void:
	short_death_scenes = enabled
	_save()


func set_fps_limit(limit: float) -> void:
	fps_limit = 0 if limit < 15.0 else clampi(roundi(limit), 30, 240)
	_apply_display_performance()
	_save()
	display_changed.emit()


func set_field_of_view(value: float) -> void:
	field_of_view = clampf(value, MIN_FIELD_OF_VIEW, MAX_FIELD_OF_VIEW)
	_save()
	visual_changed.emit()


func set_mouse_sensitivity(value: float) -> void:
	mouse_sensitivity = clampf(value, MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	_save()


func set_waypoint_guidance(mode: String) -> void:
	waypoint_guidance = mode if WAYPOINT_GUIDANCE_MODES.has(mode) else "arrow"
	_save()
	visual_changed.emit()


func set_waypoint_show_distance(on: bool) -> void:
	waypoint_show_distance = on
	_save()
	visual_changed.emit()


func set_waypoint_scale(value: float) -> void:
	waypoint_scale = clampf(value, .6, 1.6)
	_save()
	visual_changed.emit()


func set_waypoint_opacity(value: float) -> void:
	waypoint_opacity = clampf(value, .3, 1.0)
	_save()
	visual_changed.emit()


func set_waypoint_arrival_chime(on: bool) -> void:
	waypoint_arrival_chime = on
	_save()


func set_pixel_effect_percent(value: float) -> void:
	pixel_effect_percent = clampf(value, 0.0, 100.0)
	_save()
	visual_changed.emit()


func effective_slim() -> bool:
	return skin_arms == "slim" or (skin_arms == "auto" and skin_slim)


func set_skin_slim(value: bool) -> void:
	skin_slim = value
	_save()
	visual_changed.emit()


func set_skin_arms(mode: String) -> void:
	skin_arms = mode if ["auto", "classic", "slim"].has(mode) else "auto"
	_save()
	visual_changed.emit()


func set_ads_mode(value: String) -> void:
	ads_mode = value if value in TrollAds.MODES else "off"
	_save()


func set_skin_copyable(value: bool) -> void:
	skin_copyable = value
	_save()


func set_skin_hash(hash: String) -> void:
	skin_hash = hash if PlayerSkin.valid_hash(hash) else ""
	_save()
	visual_changed.emit()


func set_player_hue_degrees(value: float) -> void:
	player_hue_degrees = clampf(value, 0.0, 360.0)
	_save()
	visual_changed.emit()


func admin_preference(key: String) -> bool:
	if not ADMIN_PREFERENCE_DEFAULTS.has(key):
		return false
	return bool(_admin_preferences.get(key, ADMIN_PREFERENCE_DEFAULTS[key]))


func set_admin_preference(key: String, enabled: bool) -> void:
	if not ADMIN_PREFERENCE_DEFAULTS.has(key):
		push_warning("Settings: ignored unknown admin preference '%s'" % key)
		return
	if admin_preference(key) == enabled:
		return
	_admin_preferences[key] = enabled
	_save()


func admin_preferences_snapshot() -> Dictionary:
	return _admin_preferences.duplicate()


func set_admin_preferences(values: Dictionary) -> void:
	for key_value in ADMIN_PREFERENCE_DEFAULTS:
		var key := String(key_value)
		_admin_preferences[key] = bool(values.get(key,
			ADMIN_PREFERENCE_DEFAULTS[key]))
	_save()


func rebind_action(action: String, event: InputEvent) -> void:
	set_action_binding(action, event, false)


## Actions that are live at the same time share no key: the route's gameplay actions, and separately Office mode's (Office
## mode runs on its own scene, so its keys may repeat route keys). The taser used to sit on Q with Drop.
static func binding_group(action: String) -> Array[String]:
	var office := action.begins_with("office_")
	var out: Array[String] = []
	for candidate in REBINDABLE_ACTIONS:
		if candidate.begins_with("office_") == office:
			out.append(candidate)
	return out


func set_action_binding(action: String, event: InputEvent, append: bool) -> void:
	if not InputMap.has_action(action):
		return
	if not (event is InputEventKey or event is InputEventMouseButton):
		return
	# a key moves: whatever else in the same group had it lets go, so a rebind can never create a double binding
	for other in binding_group(action):
		if other == action or not InputMap.has_action(other):
			continue
		for existing in InputMap.action_get_events(other):
			if _event_signature(existing) == _event_signature(event):
				InputMap.action_erase_event(other, existing)
	if not append:
		_erase_keyboard_mouse_bindings(action)
	else:
		for existing in InputMap.action_get_events(action):
			if _event_signature(existing) == _event_signature(event):
				return
	InputMap.action_add_event(action, event)
	_save()


func reset_action_bindings(action: String) -> void:
	if not InputMap.has_action(action) or not _default_bindings.has(action):
		return
	_erase_keyboard_mouse_bindings(action)
	for event in _default_bindings[action]:
		InputMap.action_add_event(action, (event as InputEvent).duplicate())
	_save()


## Keyboard/mouse customization is intentionally independent from the fixed
## controller layout. Erasing every event here used to silently remove a
## joypad's movement/action binding as soon as a player changed one key.
func _erase_keyboard_mouse_bindings(action: String) -> void:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey or event is InputEventMouseButton:
			InputMap.action_erase_event(action, event)


func get_action_key_label(action: String) -> String:
	var labels := []
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			labels.append(event.as_text_physical_keycode().to_upper())
		elif event is InputEventMouseButton:
			labels.append(_mouse_button_label((event as InputEventMouseButton).button_index))
	return " / ".join(labels) if not labels.is_empty() else "?"


func action_binding_count(action: String) -> int:
	return InputMap.action_get_events(action).size() if InputMap.has_action(action) else 0


func _capture_default_bindings() -> void:
	for action in REBINDABLE_ACTIONS:
		if InputMap.has_action(action):
			var events := []
			for event in InputMap.action_get_events(action):
				if event is InputEventKey or event is InputEventMouseButton:
					events.append(event.duplicate())
			_default_bindings[action] = events


static func _mouse_button_label(button: MouseButton) -> String:
	match button:
		MOUSE_BUTTON_LEFT: return "MOUSE 1"
		MOUSE_BUTTON_RIGHT: return "MOUSE 2"
		MOUSE_BUTTON_MIDDLE: return "MOUSE 3"
		MOUSE_BUTTON_WHEEL_UP: return "WHEEL UP"
		MOUSE_BUTTON_WHEEL_DOWN: return "WHEEL DOWN"
		_: return "MOUSE %d" % int(button)


static func _event_signature(event: InputEvent) -> String:
	if event is InputEventKey:
		return "K:%d" % int((event as InputEventKey).physical_keycode)
	if event is InputEventMouseButton:
		return "M:%d" % int((event as InputEventMouseButton).button_index)
	return ""


## Fit the window to the machine the game is actually running on.
##
## The project file can only name one window size, and a size that suits a
## 1080p desktop is unusable on a 4K one and does not fit a small laptop at
## all. Sizing at startup instead means the same build opens sensibly
## everywhere -- and in whole multiples of the design size, so the pixel art
## lands on an exact grid rather than between texels.
func _apply_display() -> void:
	var window := get_window()
	if window == null:
		return
	_apply_display_performance()
	window.min_size = DISPLAY_BASE
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	var scale := maxi(1, mini(
		floori(usable.size.x * WINDOW_SCREEN_SHARE / DISPLAY_BASE.x),
		floori(usable.size.y * WINDOW_SCREEN_SHARE / DISPLAY_BASE.y)))
	window.size = DISPLAY_BASE * scale
	window.position = usable.position + (usable.size - window.size) / 2


func _apply_display_performance() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED \
		if vsync_enabled else DisplayServer.VSYNC_DISABLED)
	# no limit set: phones and the Quest still cap at the rate they can hold (PlatformProfile.default_fps_cap)
	Engine.max_fps = fps_limit if fps_limit > 0 else PlatformProfile.default_fps_cap()


func _apply_volume() -> void:
	if _master_bus_index >= 0:
		AudioServer.set_bus_volume_db(_master_bus_index, _percent_to_db(master_volume_percent))
	if _sfx_bus_index >= 0:
		AudioServer.set_bus_volume_db(_sfx_bus_index, _percent_to_db(sfx_volume_percent))
	if _ui_bus_index >= 0:
		AudioServer.set_bus_volume_db(_ui_bus_index, _percent_to_db(ui_volume_percent))


func _percent_to_db(percent: float) -> float:
	return MIN_VOLUME_DB if percent <= 0.0 else linear_to_db(percent / 100.0)


func _load() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) != OK:
		# First run: a phone starts with the pixel post effect off (PlatformProfile; desktop keeps the default).
		if PlatformProfile.default_pixel_effect_percent >= 0.0:
			pixel_effect_percent = PlatformProfile.default_pixel_effect_percent
		_apply_volume()
		return

	master_volume_percent = clampf(float(config.get_value("audio",
		"master_volume_percent", DEFAULT_VOLUME_PERCENT)), 0.0, 100.0)
	sfx_volume_percent = clampf(float(config.get_value("audio",
		"sfx_volume_percent", DEFAULT_SFX_VOLUME_PERCENT)), 0.0, 100.0)
	ui_volume_percent = clampf(float(config.get_value("audio",
		"ui_volume_percent", DEFAULT_UI_VOLUME_PERCENT)), 0.0, 100.0)
	fullscreen = config.get_value("display", "fullscreen", false)
	vsync_enabled = bool(config.get_value("display", "vsync", DEFAULT_VSYNC))
	fps_limit = clampi(int(config.get_value("display", "fps_limit", DEFAULT_FPS_LIMIT)), 0, 240)
	field_of_view = clampf(float(config.get_value("display", "field_of_view",
		DEFAULT_FIELD_OF_VIEW)), MIN_FIELD_OF_VIEW, MAX_FIELD_OF_VIEW)
	pixel_effect_percent = clampf(config.get_value("display",
		"pixel_effect_percent", DEFAULT_PIXEL_EFFECT_PERCENT), 0.0, 100.0)
	player_hue_degrees = clampf(config.get_value("player",
		"hue_degrees", DEFAULT_PLAYER_HUE_DEGREES), 0.0, 360.0)
	skin_hash = String(config.get_value("player", "skin_hash", ""))
	skin_copyable = bool(config.get_value("player", "skin_copyable", true))
	ads_mode = String(config.get_value("gameplay", "ads_mode", "off"))
	if ads_mode not in TrollAds.MODES:
		ads_mode = "off"
	skin_slim = bool(config.get_value("player", "skin_slim", false))
	skin_arms = String(config.get_value("player", "skin_arms", "auto"))
	if not ["auto", "classic", "slim"].has(skin_arms):
		skin_arms = "auto"
	if not PlayerSkin.valid_hash(skin_hash):
		skin_hash = ""
	reduced_motion = bool(config.get_value("accessibility", "reduced_motion", false))
	xr_player_height = clampf(float(config.get_value("xr", "player_height", 1.70)), 1.0, 2.3)
	touch_move = "stick" if String(config.get_value("touch", "move", "dpad")) == "stick" else "dpad"
	touch_look_speed = clampf(float(config.get_value("touch", "look_speed", 1.0)), 0.25, 3.0)
	touch_look_vertical = clampf(float(config.get_value("touch", "look_vertical", 0.8)), 0.3, 1.5)
	touch_look_invert_y = bool(config.get_value("touch", "look_invert_y", false))
	var smoothing := String(config.get_value("touch", "look_smoothing", "off"))
	touch_look_smoothing = smoothing if ["off", "low", "high"].has(smoothing) else "off"
	touch_look_accel = bool(config.get_value("touch", "look_accel", false))
	xr_smooth_turn = bool(config.get_value("xr", "smooth_turn", false))
	xr_vignette = bool(config.get_value("xr", "vignette", true))
	xr_seated = bool(config.get_value("xr", "seated", false))
	graphics_quality = String(config.get_value("display", "graphics_quality", "AUTO"))
	if not GRAPHICS_CHOICES.has(graphics_quality):
		graphics_quality = "AUTO"
	if graphics_quality != "AUTO":
		PlatformProfile.set_graphics_quality(graphics_quality)
	var guidance := String(config.get_value("waypoint", "guidance", "arrow"))
	waypoint_guidance = guidance if WAYPOINT_GUIDANCE_MODES.has(guidance) else "arrow"
	waypoint_show_distance = bool(config.get_value("waypoint", "show_distance", true))
	waypoint_scale = clampf(float(config.get_value("waypoint", "scale", 1.0)), .6, 1.6)
	waypoint_opacity = clampf(float(config.get_value("waypoint", "opacity", .9)), .3, 1.0)
	waypoint_arrival_chime = bool(config.get_value("waypoint", "arrival_chime", true))
	short_death_scenes = bool(config.get_value("accessibility", "short_death_scenes", false))
	hub_last_game = String(config.get_value("hub", "last_game", ""))
	pause_on_focus_loss = bool(config.get_value("gameplay", "pause_on_focus_loss", default_pause_on_focus_loss()))
	voice_volume = clampf(float(config.get_value("voice", "volume", 80.0)), 0.0, 100.0)
	voice_enabled = bool(config.get_value("voice", "enabled", true))
	voice_subtitles = bool(config.get_value("voice", "subtitles", true))
	muted_players = Array(config.get_value("voice", "muted", []))
	voice_chat_on = bool(config.get_value("voice", "chat_on", false))
	voice_mode = String(config.get_value("voice", "mode", "vad"))
	if not voice_mode in ["vad", "ptt"]:
		voice_mode = "vad"
	voice_mic_gain = clampf(float(config.get_value("voice", "mic_gain", 1.0)), 0.0, 2.0)
	voice_sensitivity = clampf(float(config.get_value("voice", "sensitivity", 0.5)), 0.0, 1.0)
	voice_input_device = String(config.get_value("voice", "input_device", "Default"))
	voice_chat_volume = clampf(float(config.get_value("voice", "chat_volume", 1.0)), 0.0, 1.5)
	voice_player_volumes = Dictionary(config.get_value("voice", "player_volumes", {}))
	tts_mode = String(config.get_value("voice", "tts_mode", "everyone"))
	if not tts_mode in ["off", "own", "everyone"]:
		tts_mode = "everyone"
	tts_rate = clampf(float(config.get_value("voice", "tts_rate", 1.0)), 0.5, 2.0)
	tts_voice_id = String(config.get_value("voice", "tts_voice", ""))
	auto_download_mods = bool(config.get_value("mods", "auto_download", false))
	for key_value in ADMIN_PREFERENCE_DEFAULTS:
		var key := String(key_value)
		_admin_preferences[key] = bool(config.get_value("admin", key,
			ADMIN_PREFERENCE_DEFAULTS[key]))
	mouse_sensitivity = clampf(
		config.get_value("controls", "mouse_sensitivity", DEFAULT_MOUSE_SENSITIVITY),
		MIN_MOUSE_SENSITIVITY, MAX_MOUSE_SENSITIVITY)
	for action in REBINDABLE_ACTIONS:
		if not config.has_section_key("controls", action) or not InputMap.has_action(action):
			continue   # never saved (a new action keeps its default binding)
		var saved = config.get_value("controls", action)
		if saved == null:
			continue
		# Read the original one-integer format so existing player settings migrate
		# without silently resetting. New saves preserve every keyboard/mouse bind.
		var entries: Array = saved if saved is Array else [{"type": "key", "code": int(saved)}]
		_erase_keyboard_mouse_bindings(action)
		for entry_value in entries:
			if not entry_value is Dictionary:
				continue
			var entry: Dictionary = entry_value
			if String(entry.get("type", "")) == "mouse":
				var mouse := InputEventMouseButton.new()
				mouse.button_index = int(entry.get("button", 0)) as MouseButton
				if mouse.button_index > 0:
					InputMap.action_add_event(action, mouse)
			else:
				var key := InputEventKey.new()
				key.physical_keycode = int(entry.get("code", 0))
				if key.physical_keycode > 0:
					InputMap.action_add_event(action, key)
	_migrate_taser_off_q()
	_apply_volume()


## Old defaults put the taser on Q together with Drop. A saved profile that still has Q on both gives Q back to Drop and
## the taser its new default (G) if it has no other key.
func _migrate_taser_off_q() -> void:
	if not InputMap.has_action("taser") or not InputMap.has_action("drop_item"):
		return
	var q_on_drop := false
	for event in InputMap.action_get_events("drop_item"):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == KEY_Q:
			q_on_drop = true
	if not q_on_drop:
		return
	var keys_left := 0
	for event in InputMap.action_get_events("taser"):
		if event is InputEventKey:
			if (event as InputEventKey).physical_keycode == KEY_Q:
				InputMap.action_erase_event("taser", event)
			else:
				keys_left += 1
	if keys_left == 0:
		var g := InputEventKey.new()
		g.physical_keycode = KEY_G
		InputMap.action_add_event("taser", g)


func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume_percent", master_volume_percent)
	config.set_value("audio", "sfx_volume_percent", sfx_volume_percent)
	config.set_value("audio", "ui_volume_percent", ui_volume_percent)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "vsync", vsync_enabled)
	config.set_value("display", "fps_limit", fps_limit)
	config.set_value("display", "field_of_view", field_of_view)
	config.set_value("display", "pixel_effect_percent", pixel_effect_percent)
	config.set_value("player", "hue_degrees", player_hue_degrees)
	config.set_value("player", "skin_hash", skin_hash)
	config.set_value("player", "skin_copyable", skin_copyable)
	config.set_value("gameplay", "ads_mode", ads_mode)
	config.set_value("player", "skin_slim", skin_slim)
	config.set_value("player", "skin_arms", skin_arms)
	config.set_value("accessibility", "reduced_motion", reduced_motion)
	config.set_value("xr", "player_height", xr_player_height)
	config.set_value("touch", "move", touch_move)
	config.set_value("touch", "look_speed", touch_look_speed)
	config.set_value("touch", "look_vertical", touch_look_vertical)
	config.set_value("touch", "look_invert_y", touch_look_invert_y)
	config.set_value("touch", "look_smoothing", touch_look_smoothing)
	config.set_value("touch", "look_accel", touch_look_accel)
	config.set_value("xr", "smooth_turn", xr_smooth_turn)
	config.set_value("xr", "vignette", xr_vignette)
	config.set_value("xr", "seated", xr_seated)
	config.set_value("display", "graphics_quality", graphics_quality)
	config.set_value("waypoint", "guidance", waypoint_guidance)
	config.set_value("waypoint", "show_distance", waypoint_show_distance)
	config.set_value("waypoint", "scale", waypoint_scale)
	config.set_value("waypoint", "opacity", waypoint_opacity)
	config.set_value("waypoint", "arrival_chime", waypoint_arrival_chime)
	config.set_value("accessibility", "short_death_scenes", short_death_scenes)
	config.set_value("hub", "last_game", hub_last_game)
	config.set_value("gameplay", "pause_on_focus_loss", pause_on_focus_loss)
	config.set_value("voice", "volume", voice_volume)
	config.set_value("voice", "enabled", voice_enabled)
	config.set_value("voice", "subtitles", voice_subtitles)
	config.set_value("voice", "muted", muted_players)
	config.set_value("voice", "chat_on", voice_chat_on)
	config.set_value("voice", "mode", voice_mode)
	config.set_value("voice", "mic_gain", voice_mic_gain)
	config.set_value("voice", "sensitivity", voice_sensitivity)
	config.set_value("voice", "input_device", voice_input_device)
	config.set_value("voice", "chat_volume", voice_chat_volume)
	config.set_value("voice", "player_volumes", voice_player_volumes)
	config.set_value("voice", "tts_mode", tts_mode)
	config.set_value("voice", "tts_rate", tts_rate)
	config.set_value("voice", "tts_voice", tts_voice_id)
	config.set_value("mods", "auto_download", auto_download_mods)
	for key_value in ADMIN_PREFERENCE_DEFAULTS:
		var key := String(key_value)
		config.set_value("admin", key, admin_preference(key))
	config.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	for action in REBINDABLE_ACTIONS:
		var entries := []
		for event in MouseLock.true_events(action):
			if event is InputEventKey:
				entries.append({"type": "key", "code": event.physical_keycode})
			elif event is InputEventMouseButton:
				entries.append({"type": "mouse", "button": event.button_index})
		config.set_value("controls", action, entries)
	config.save(SETTINGS_PATH)
