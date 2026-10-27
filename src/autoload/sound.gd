extends Node

## Procedural sound port of the original Web Audio SoundSystem. The source
## project ships no WAV/OGG assets: every cue is an oscillator, filtered noise
## or low thump. Rendering each named cue to a cached stereo AudioStreamWAV
## keeps that identity while giving Godot ordinary streams and audio buses.
## Continuous ambience remains deliberately absent, matching the source.

const SAMPLE_RATE := 44100
const PLAYER_POOL_SIZE := 16
const OFFICE_QUEUE_MAX_LOOKAHEAD_USEC := 180000

var muted := false
var last_cue := ""
var play_counts := {}

var _players: Array[AudioStreamPlayer] = []
var _next_player := 0
var _cache := {}
var _pending: Array = []
var _office_queue_until_usec := 0
var _last_heartbeat_usec := -2000000
var _last_footstep_usec := -2000000
var _last_struggle_usec := -2000000
var _last_menu_usec := -2000000
var _footstep_index := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in PLAYER_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % index
		player.bus = &"SFX"
		add_child(player)
		_players.append(player)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_wire_existing_buttons")


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	for index in range(_pending.size() - 1, -1, -1):
		var item: Dictionary = _pending[index]
		if now < int(item["at"]):
			continue
		_play_stream(item["stream"], StringName(item["bus"]))
		_pending.remove_at(index)


func set_muted(value: bool) -> void:
	muted = value


func toggle() -> bool:
	muted = not muted
	return muted


func stop_all() -> void:
	_pending.clear()
	_office_queue_until_usec = 0
	for player in _players:
		player.stop()
		player.stream = null


func _exit_tree() -> void:
	stop_all()


func collect() -> bool:
	return _play_named("collect")


func recharge(amount: float = 10.0) -> bool:
	return _play_named("recharge", 0.0, clampf(amount / 10.0, 0.0, 4.0))


func menu_blip() -> bool:
	var now := Time.get_ticks_usec()
	if now - _last_menu_usec < 45000:
		return false
	_last_menu_usec = now
	return _play_named("menu", 0.0, 1.0, &"UI")


func music_box() -> bool:
	return _play_named("music_box")


func alert() -> bool:
	return _play_named("alert")


func chase_start() -> bool:
	return _play_named("chase_start")


func taser() -> bool:
	return _play_named("taser")


func door(open: bool) -> bool:
	return _play_named("door_open" if open else "door_close")


func door_breach() -> bool:
	return _play_named("door_breach")


func interaction_fail() -> bool:
	return _play_named("interaction_fail")


func tool_break() -> bool:
	return _play_named("tool_break")


func nyxie_timer_wake() -> bool:
	return _play_named("nyxie_timer")


func nyxie_empty_wake() -> bool:
	return _play_named("nyxie_empty")


func hunter_footstep(pan: float = 0.0, volume: float = 0.05) -> bool:
	return _play_named("hunter_footstep", pan, clampf(volume / 0.05, 0.1, 2.0))


## A hunter's laugh/hum/dance (HunterEmoteCatalog noise > 0): a small, quiet cue scaled by distance.
func hunter_laugh(pan: float = 0.0, volume: float = 0.05) -> bool:
	return _play_named("hunter_laugh", pan, clampf(volume / 0.05, 0.1, 2.0))


## The secret creature's bark: a low double growl, loud enough to be a warning.
func spider_bark(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("spider_bark", pan, clampf(intensity, 0.1, 2.0))


## Xivvy's take-off / closing-in screech: a rising shriek.
func xivvy_screech(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("xivvy_screech", pan, clampf(intensity, 0.1, 2.0))


## One wing beat of Xivvy in flight.
func xivvy_wing(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("xivvy_wing", pan, clampf(intensity, 0.1, 2.0))


## The black variant's tell: a long low hiss.
func spider_hiss(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("spider_hiss", pan, clampf(intensity, 0.1, 2.0))


func remote_player_footstep(mode := "walk", pan: float = 0.0,
		volume: float = 0.04) -> bool:
	var resolved := mode if mode in ["sprint", "crouch"] else "walk"
	return _play_named("teammate_footstep_%s" % resolved, pan,
		clampf(volume / 0.04, 0.08, 1.5))


func mimic(rare := false) -> bool:
	return _play_named("mimic_rare" if rare else "mimic")


func heartbeat(intensity: float) -> bool:
	var danger := clampf(intensity, 0.0, 1.0)
	if danger < 0.04:
		return false
	var now := Time.get_ticks_usec()
	var gap_usec := int(maxf(0.32, 1.08 - danger * 0.73) * 1000000.0)
	if now - _last_heartbeat_usec < gap_usec:
		return false
	_last_heartbeat_usec = now
	return _play_named("heartbeat", 0.0, danger)


func footstep(mode := "walk") -> bool:
	var resolved := mode if mode in ["sprint", "crouch"] else "walk"
	var gaps := {"sprint": 205000, "walk": 335000, "crouch": 510000}
	var now := Time.get_ticks_usec()
	if now - _last_footstep_usec < int(gaps[resolved]):
		return false
	_last_footstep_usec = now
	_footstep_index += 1
	var side := 1.0 if _footstep_index % 2 else -1.0
	return _play_named("footstep_%s" % resolved, side * 0.045)


func capture() -> bool:
	return _play_named("capture")


func struggle(intensity: float = 0.5) -> bool:
	var effort := clampf(intensity, 0.0, 1.0)
	var now := Time.get_ticks_usec()
	var gap_usec := int((0.13 - effort * 0.045) * 1000000.0)
	if now - _last_struggle_usec < gap_usec:
		return false
	_last_struggle_usec = now
	return _play_named("struggle", -0.035 if _footstep_index % 2 else 0.035,
		effort)


func escape() -> bool:
	return _play_named("escape")


## Office cues are queued just like the source, but never more than 180 ms in
## front of real time. Under button spam that bound matters more than perfect
## serialization: feedback stays connected to the action that caused it.
func queue_office_cue(cue: String, pan: float = 0.0, intensity: float = 1.0) -> bool:
	if muted:
		return false
	var resolved := cue if cue in ["camera", "warning", "crimson_door",
		"presence", "scrape", "static", "drain", "footsteps", "breath",
		"shift", "control"] else "control"
	var stream := render_cue("office_%s" % resolved, pan, intensity)
	var now := Time.get_ticks_usec()
	var start := mini(now + OFFICE_QUEUE_MAX_LOOKAHEAD_USEC,
		maxi(now, _office_queue_until_usec))
	_pending.append({"at": start, "stream": stream, "bus": &"SFX"})
	_office_queue_until_usec = start + int(stream.get_length() * 1000000.0) + 25000
	_record("office_%s" % resolved)
	return true


func office_jumpscare(hunter_id := "void") -> bool:
	# A small id-derived pitch tint keeps each Void hit recognizably related but
	# avoids every signal ending on a byte-identical sting.
	var tint: int = absi(hunter_id.hash()) % 90
	return _play_named("office_jumpscare", 0.0, 1.0 + tint / 900.0)


## Public for the headless audio check and future waveform previews. Callers
## normally use the named methods above.
func render_cue(cue: String, pan: float = 0.0, intensity: float = 1.0) -> AudioStreamWAV:
	var clean_pan := snappedf(clampf(pan, -1.0, 1.0), 0.05)
	var clean_intensity := snappedf(clampf(intensity, 0.0, 4.0), 0.05)
	var key := "%s|%.2f|%.2f" % [cue, clean_pan, clean_intensity]
	if _cache.has(key):
		return _cache[key]
	var components := _cue_components(cue, clean_pan, clean_intensity)
	var stream := _render_components(components, abs(key.hash()))
	_cache[key] = stream
	return stream


func reset_test_counters() -> void:
	last_cue = ""
	play_counts.clear()
	_last_heartbeat_usec = -2000000
	_last_footstep_usec = -2000000
	_last_struggle_usec = -2000000
	_last_menu_usec = -2000000


func _play_named(cue: String, pan := 0.0, intensity := 1.0,
		bus: StringName = &"SFX") -> bool:
	if muted:
		return false
	_play_stream(render_cue(cue, pan, intensity), bus)
	_record(cue)
	return true


func _play_stream(stream: AudioStream, bus: StringName) -> void:
	# Dedicated/headless runs still render cues for validation, but have no
	# device to consume a playback. Asking the dummy driver to play leaves its
	# WAV playback object alive until shutdown and serves no game purpose.
	if DisplayServer.get_name() == "headless":
		return
	if _players.is_empty():
		return
	var chosen: AudioStreamPlayer
	for offset in _players.size():
		var candidate := _players[(_next_player + offset) % _players.size()]
		if not candidate.playing:
			chosen = candidate
			break
	if chosen == null:
		chosen = _players[_next_player]
		chosen.stop()
	_next_player = (_players.find(chosen) + 1) % _players.size()
	chosen.bus = bus
	chosen.stream = stream
	chosen.play()


func _record(cue: String) -> void:
	last_cue = cue
	play_counts[cue] = int(play_counts.get(cue, 0)) + 1


func _wire_existing_buttons() -> void:
	for node in get_tree().get_nodes_in_group(&"__sound_buttons"):
		_on_node_added(node)
	_wire_buttons_below(get_tree().root)


func _wire_buttons_below(node: Node) -> void:
	_on_node_added(node)
	for child in node.get_children():
		_wire_buttons_below(child)


func _on_node_added(node: Node) -> void:
	if not node is BaseButton:
		return
	var button := node as BaseButton
	var callback := Callable(self, "menu_blip")
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


func _tone(frequency: float, duration: float, volume: float, delay := 0.0,
		wave := "sine", pan := 0.0) -> Dictionary:
	return {"kind": "tone", "frequency": frequency, "duration": duration,
		"volume": volume, "delay": delay, "wave": wave, "pan": pan}


func _thump(frequency: float, duration: float, volume: float, delay := 0.0,
		pan := 0.0) -> Dictionary:
	return {"kind": "thump", "frequency": frequency, "duration": duration,
		"volume": volume, "delay": delay, "wave": "sine", "pan": pan}


func _noise(duration: float, volume: float, frequency: float, delay := 0.0,
		pan := 0.0, rate := 1.0) -> Dictionary:
	return {"kind": "noise", "frequency": frequency, "duration": duration,
		"volume": volume, "delay": delay, "pan": pan, "rate": rate}


func _cue_components(cue: String, pan: float, intensity: float) -> Array:
	var c: Array = []
	match cue:
		"collect":
			c = [_tone(220, .12, .13, 0, "square"), _tone(330, .16, .10, .09, "square"), _tone(660, .22, .07, .19)]
		"recharge":
			var lift := minf(120.0, 30.0 * intensity)
			c = [_tone(180 + lift, .09, .10, 0, "square"), _tone(360 + lift, .14, .08, .08)]
		"menu": c = [_tone(620, .035, .026, 0, "square"), _tone(930, .055, .018, .022)]
		"music_box":
			var phrase := [1046.5, 1318.5, 1568.0, 1318.5, 1760.0, 1568.0]
			for index in phrase.size(): c.append(_tone(phrase[index], .22, .07, index * .2, "triangle"))
		"alert": c = [_tone(150, .12, .12, 0, "saw"), _tone(96, .2, .10, .06, "square")]
		"chase_start": c = [_tone(92, .16, .16, 0, "saw"),
			_tone(138, .19, .13, .07, "square"),
			_tone(207, .24, .10, .15, "saw"),
			_noise(.24, .045, 860, .04, 0.0, 1.12),
			_thump(48, .30, .14, .19)]
		"taser": c = [_noise(.12, .16, 4200, 0, pan, 1.35),
			_tone(860, .07, .13, 0, "square", pan),
			_tone(430, .11, .10, .055, "saw", pan),
			_thump(76, .10, .06, .045, pan)]
		"door_open": c = [_noise(.24, .038, 310, 0, pan, .46),
			_tone(118, .18, .032, .03, "triangle", pan),
			_noise(.055, .055, 980, .19, pan, .82)]
		"door_close": c = [_noise(.15, .042, 360, 0, pan, .56),
			_thump(82, .12, .085, .11, pan),
			_tone(145, .08, .038, .12, "square", pan)]
		"door_breach": c = [_noise(.34, .18, 720, 0, pan, .88),
			_thump(54, .42, .23, .015, pan),
			_tone(96, .18, .13, .06, "saw", pan),
			_noise(.20, .10, 1900, .16, pan, 1.18)]
		"interaction_fail": c = [_tone(196, .075, .052, 0, "square", pan),
			_tone(132, .12, .045, .065, "square", pan)]
		"tool_break": c = [_noise(.16, .095, 1850, 0, pan, 1.22),
			_tone(310, .08, .065, .025, "square", pan),
			_tone(118, .18, .052, .09, "triangle", pan)]
		"nyxie_timer": c = [_tone(72, .5, .09), _tone(108, .4, .07, .18, "triangle"), _tone(144, .3, .05, .34, "triangle")]
		"nyxie_empty": c = [_tone(48, .7, .13, 0, "saw"), _tone(32, .9, .08, .1)]
		"hunter_laugh": c = [_tone(392, .07, .05 * intensity, 0, "triangle", pan), _tone(349, .07, .045 * intensity, .10, "triangle", pan), _tone(311, .09, .04 * intensity, .20, "triangle", pan)]
		"xivvy_screech": c = [_tone(1250, .12, .07 * intensity, 0, "saw", pan), _tone(1760, .16, .08 * intensity, .07, "saw", pan), _tone(2350, .22, .075 * intensity, .16, "square", pan), _noise(.34, .05 * intensity, 3400, .06, pan, 1.3)]
		"xivvy_wing": c = [_noise(.13, .05 * intensity, 520, 0, pan, .9), _thump(120, .09, .03 * intensity, .02, pan)]
		"spider_hiss": c = [_noise(.9, .16 * intensity, 520, 0, pan, .7), _tone(61, .8, .15 * intensity, .02, "saw", pan), _noise(.55, .09 * intensity, 900, .25, pan, 1.1)]
		"spider_bark": c = [_tone(74, .30, .20 * intensity, 0, "saw", pan), _tone(55, .36, .18 * intensity, .04, "square", pan), _noise(.22, .09 * intensity, 240, .02, pan, .8), _tone(96, .22, .15 * intensity, .46, "saw", pan), _noise(.18, .07 * intensity, 300, .46, pan, .9)]
		"hunter_footstep": c = [_thump(58, .10, .05 * intensity, 0, pan), _thump(41, .13, .035 * intensity, .05, pan)]
		"teammate_footstep_sprint": c = [_noise(.07, .066 * intensity, 610, 0, pan, 1.15), _thump(92, .065, .045 * intensity, 0, pan)]
		"teammate_footstep_crouch": c = [_noise(.045, .012 * intensity, 430, 0, pan, .92), _thump(68, .045, .009 * intensity, 0, pan)]
		"teammate_footstep_walk": c = [_noise(.06, .035 * intensity, 525, 0, pan, 1.03), _thump(82, .06, .028 * intensity, 0, pan)]
		"mimic": c = [_tone(132, .2, .24, 0, "saw"), _tone(82, .32, .21, .06, "square")]
		"mimic_rare": c = [_tone(1046.5, .28, .2, 0, "triangle"), _tone(1568, .34, .18, .1, "triangle")]
		"heartbeat":
			# Keep the double-pulse shape, but center it above sub-bass and add a
			# short midrange body. Laptop/TV speakers can now reproduce the cue,
			# and the higher gain survives footsteps without becoming a rumble.
			var pulse_volume := .11 + intensity * .14
			c = [_thump(96 + intensity * 20, .085, pulse_volume),
				_tone(182 + intensity * 28, .07, pulse_volume * .38,
					.012, "triangle"),
				_thump(82 + intensity * 14, .10, pulse_volume * .76, .12),
				_tone(154 + intensity * 22, .075, pulse_volume * .28,
					.135, "triangle")]
		"footstep_sprint": c = [_noise(.085, .105, 470, 0, pan, 1.08), _thump(69, .085, .085, 0, pan)]
		"footstep_crouch": c = [_noise(.055, .017, 285, 0, pan, .86), _thump(43, .055, .012, 0, pan)]
		"footstep_walk": c = [_noise(.07, .052, 385, 0, pan, .96), _thump(55, .07, .042, 0, pan)]
		"capture": c = [_tone(92, .26, .10, 0, "triangle"), _tone(61, .44, .085, .16), _tone(41, .62, .06, .36)]
		"struggle": c = [_noise(.045, .025 + intensity * .045,
			330 + intensity * 210, 0, pan, .92 + intensity * .16),
			_thump(72 + intensity * 22, .055, .025 + intensity * .045)]
		"escape": c = [_tone(174, .08, .08, 0, "triangle"), _tone(261, .10, .075, .07, "triangle"), _tone(392, .14, .055, .15)]
		"office_camera": c = [_noise(.065, .04, 1250, 0, pan, 1.18), _tone(690, .045, .045, .025, "square", pan), _tone(430, .11, .035, .075, "triangle", pan)]
		"office_warning": c = [_thump(68, .1, .09, 0, pan), _tone(118, .27, .075, .055, "saw", pan), _noise(.09, .04, 520, .13, pan)]
		"office_crimson_door":
			for index in 3:
				c.append(_thump(56 + index * 5, .065, .055 + index * .008, index * .16, pan))
				c.append(_tone([132, 158, 190][index], .12, .045 + index * .007, index * .16 + .018, "square", pan))
			c.append(_noise(.07, .026, 620, .37, pan, .9))
		"office_presence": c = [_noise(.11, .016, 330, 0, pan, .72), _tone(154, .16, .022, .035, "triangle", pan), _thump(58, .08, .024, .1, pan)]
		"office_scrape": c = [_noise(.18, .018, 240, 0, pan, .48), _noise(.055, .012, 1160, .15, pan, .66)]
		"office_static": c = [_noise(.16, .026, 1650, 0, pan, 1.45), _tone(410, .11, .018, .035, "square", pan)]
		"office_drain": c = [_tone(190, .22, .026, 0, "saw", pan), _tone(104, .18, .024, .1, "triangle", pan), _noise(.06, .013, 760, .19, pan, .7)]
		"office_footsteps": c = [_thump(92, .045, .022, 0, pan), _thump(78, .055, .02, .15, pan), _thump(84, .04, .017, .29, pan)]
		"office_breath": c = [_noise(.38, .014 * intensity, 210, 0, pan, .34), _tone(52, .4, .02 * intensity, .05, "sine", pan), _noise(.55, .017 * intensity, 150, .48, pan, .26), _tone(40, .58, .024 * intensity, .52, "sine", pan)]
		"office_shift": c = [_noise(.11, .035, 900, 0, 0, .84), _tone(210, .2, .045, .07, "triangle"), _tone(315, .22, .035, .2, "triangle")]
		"office_control": c = [_tone(265, .08, .045, 0, "square"), _noise(.045, .025, 720, .025, pan)]
		"office_jumpscare":
			var tint := (intensity - 1.0) * 900.0
			c = [_noise(.58, .24, 1320 + tint, 0, 0, .72),
				_thump(72, .34, .22, .015),
				_tone(740 + tint, .13, .15, .025, "saw"),
				_tone(360 + tint * .4, .46, .13, .09, "square"),
				_tone(56, .72, .1, .12)]
		_: c = [_tone(265, .08, .045, 0, "square")]
	return c


func _render_components(components: Array, seed_value: int) -> AudioStreamWAV:
	var total := 0.05
	for component in components:
		total = maxf(total, float(component["delay"]) + float(component["duration"]) + .025)
	var frame_count := maxi(1, ceili(total * SAMPLE_RATE))
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(frame_count)
	right.resize(frame_count)
	var noise_state := maxi(1, seed_value)
	for component in components:
		var start := int(float(component["delay"]) * SAMPLE_RATE)
		var count := maxi(1, int(float(component["duration"]) * SAMPLE_RATE))
		var frequency := maxf(20.0, float(component["frequency"]))
		var volume := float(component["volume"])
		var component_pan := clampf(float(component.get("pan", 0.0)), -1.0, 1.0)
		var left_gain := cos((component_pan + 1.0) * PI * .25)
		var right_gain := sin((component_pan + 1.0) * PI * .25)
		var filtered := 0.0
		for local_index in count:
			var frame := start + local_index
			if frame >= frame_count:
				break
			var t := float(local_index) / SAMPLE_RATE
			var progress := float(local_index) / maxf(1.0, count - 1.0)
			var attack := minf(1.0, t / .009)
			var envelope := attack * pow(1.0 - progress, 2.25)
			var sample := 0.0
			if component["kind"] == "noise":
				noise_state = int((noise_state * 1103515245 + 12345) & 0x7fffffff)
				var white := float(noise_state) / 1073741823.5 - 1.0
				var alpha := clampf(frequency * float(component.get("rate", 1.0)) / SAMPLE_RATE * 5.0, .015, .55)
				filtered += (white - filtered) * alpha
				sample = filtered
			else:
				var phase_frequency := frequency
				if component["kind"] == "thump":
					phase_frequency = lerpf(frequency * 1.15, frequency * .72, progress)
				var phase := TAU * phase_frequency * t
				match String(component.get("wave", "sine")):
					"square": sample = 1.0 if sin(phase) >= 0.0 else -1.0
					"triangle": sample = asin(sin(phase)) * 2.0 / PI
					"saw": sample = 2.0 * fmod(phase / TAU, 1.0) - 1.0
					_: sample = sin(phase)
			var value := sample * volume * envelope
			left[frame] += value * left_gain
			right[frame] += value * right_gain
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 4)
	for frame in frame_count:
		bytes.encode_s16(frame * 4, roundi(clampf(left[frame], -.98, .98) * 32767.0))
		bytes.encode_s16(frame * 4 + 2, roundi(clampf(right[frame], -.98, .98) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = true
	stream.data = bytes
	return stream
