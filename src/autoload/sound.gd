extends Node

## Procedural sound port of the original Web Audio SoundSystem. The source
## project ships no WAV/OGG assets: every cue is an oscillator, filtered noise
## or low thump. Rendering each named cue to a cached stereo AudioStreamWAV
## keeps that identity while giving Godot ordinary streams and audio buses.
## Ambient beds per region / room purpose (AmbienceTable) are looped renders of the same primitives, crossfaded by
## set_ambience() and ducked in chases; footsteps take the floor surface (SurfaceSounds).

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
var last_footstep_surface := ""
## Ambience: the bed now playing (AmbienceTable key) and its two crossfading players.
var ambience_key := ""
var ambience_duck := 0.0
const AMBIENCE_FADE := 1.6
const AMBIENCE_GAIN_DB := -6.0
var _ambience_players: Array[AudioStreamPlayer] = []
var _ambience_active := 0
var _ambience_cache := {}
## Content-pack replacements (docs/modding/content-types.md, "Sounds"): cue -> {"streams", "gain_db"} and ambience key ->
## {"stream", "gain_db"}, rebuilt whenever packs load or unload. Without packs both are empty and nothing changes.
var _cue_overrides := {}
var _ambience_overrides := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for index in PLAYER_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "Voice%d" % index
		player.bus = &"SFX"
		add_child(player)
		_players.append(player)
	for index in 2:
		var bed := AudioStreamPlayer.new()
		bed.name = "Ambience%d" % index
		bed.bus = &"SFX"
		bed.volume_db = -80.0
		add_child(bed)
		_ambience_players.append(bed)
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_wire_existing_buttons")
	ContentRegistry.watch(_on_content_packs_changed)


## True for a cue this class renders itself, as opposed to the fallback beep any unknown name gets (packs may only
## replace real cues).
func knows_cue(cue: String) -> bool:
	var unknown := ("nw_" if cue.begins_with("nw_") else "") + "__unknown_cue__"
	return var_to_str(_cue_components(cue, 0.0, 1.0)) != var_to_str(_cue_components(unknown, 0.0, 1.0))


func _on_content_packs_changed() -> void:
	_cue_overrides.clear()
	_ambience_overrides.clear()
	for def in ContentRegistry.pack_defs("sounds"):
		var streams := []
		for path in def["files"]:
			var stream := ContentRegistry.pack_audio(String(path))
			if stream != null:
				streams.append(stream)
		if not streams.is_empty():
			_cue_overrides[String(def["id"])] = {"streams": streams, "gain_db": float(def.get("gain_db", 0.0))}
	for def in ContentRegistry.pack_defs("ambience"):
		var bed := ContentRegistry.pack_audio(String(def["files"][0]), true)
		if bed != null:
			_ambience_overrides[String(def["id"])] = {"stream": bed, "gain_db": float(def.get("gain_db", 0.0))}
	# the bed playing now switches to (or back from) its replacement
	var key := ambience_key
	if not key.is_empty():
		ambience_key = ""
		set_ambience(key)


func _process(_delta: float) -> void:
	if not _ambience_jobs.is_empty():
		_poll_ambience_jobs()
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
	# a bed still rendering on the worker pool must finish before this autoload goes away (it runs our method)
	for key in _ambience_jobs.keys():
		WorkerThreadPool.wait_for_task_completion(int(_ambience_jobs[key]["task"]))
	_ambience_jobs.clear()


func collect() -> bool:
	return _play_named("collect")


## Night Watch's own cues, recreated from the 2D game's synthesized sfx table (games/night-watch/src/core/audio.js): the same pitches, lengths and volumes, panned the same way.
## move / pick / deny / burst (menus and the camera static), step / clank / bound / pad (the hunters), ring / talk / chime (Zellia's call and the music-box note), door, light_on, camera, scare, power_out, crackle / hum /
## breath (Kathy and the hall), tape / radio / rustle / zip (the campfire), clunk / glass_tap / hinge / latch / squeak (the death scenes), lure and Bedtime's bed_*. `intensity` is the 2D `vol` over its default.
func nw(cue_name: String, pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("nw_" + cue_name, pan, intensity, &"SFX")


## Carnival booth sounds (CarnivalBooth3D): "start" a bell ding, "throw" a ring whoosh, "ring_on" a clink, "ring_miss" a soft thud, "windup" a rising whine, "swing" the mallet, "thud" a puck that fell short,
## "bell" the strength tester's bell, "win" a little fanfare, "lose" a sad slide, "tick" a light click, "pop" / "clang" / "splash" / "motor" / "grip" for the other booths.
func carnival(kind: String, pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("carnival_" + kind, pan, intensity)


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


func axe_swing(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("axe_swing", pan, intensity)


func axe_chop(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("axe_chop", pan, intensity)


## A hunter checking a bed or wardrobe: wood creak and a rattle, the tell before it pulls the spot open.
func hide_search(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("hide_search", pan, intensity)


## Sleep (docs/REST_AND_SLEEP.md): settling into sleep, a yawn when drowsy, the muffled stir of something close, the
## jolt awake, and a sleeping hunter's snore.
## Room light switch click (docs/LIGHT_SWITCHES.md).
func light_switch(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("light_switch", pan, intensity)


func sleep_settle(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("sleep_settle", pan, intensity)


func sleep_yawn(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("sleep_yawn", pan, intensity)


func sleep_stir(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("sleep_stir", pan, intensity)


func sleep_jolt(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("sleep_jolt", pan, intensity)


func hunter_snore(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("hunter_snore", pan, intensity)


func nyxie_timer_wake() -> bool:
	return _play_named("nyxie_timer")


func nyxie_empty_wake() -> bool:
	return _play_named("nyxie_empty")


func hunter_footstep(pan: float = 0.0, volume: float = 0.05, surface := "") -> bool:
	if surface == "":
		return _play_named("hunter_footstep", pan, clampf(volume / 0.05, 0.1, 2.0))
	_footstep_index += 1
	return _play_named("step:hunter:%s:%d" % [surface, _footstep_index % 4], pan, clampf(volume / 0.05, 0.1, 2.0))


## A hunter's laugh/hum/dance (HunterEmoteCatalog noise > 0): a small, quiet cue scaled by distance.
func hunter_laugh(pan: float = 0.0, volume: float = 0.05) -> bool:
	return _play_named("hunter_laugh", pan, clampf(volume / 0.05, 0.1, 2.0))


## The secret creature's bark: a low double growl, loud enough to be a warning.
func spider_bark(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("spider_bark", pan, clampf(intensity, 0.1, 2.0))


## Xivvy's take-off / closing-in screech: a rising shriek.
func xivvy_screech(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("xivvy_screech", pan, clampf(intensity, 0.1, 2.0))


## Purple's radar going to static / dead.
func radar_static(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("radar_static", pan, clampf(intensity, 0.1, 2.0))


## Orange taking a system offline.
func system_offline(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("system_offline", pan, clampf(intensity, 0.1, 2.0))


## One E press of Gray's signal route (rises with each node).
func signal_node(progress: float = 0.0) -> bool:
	return _play_named("signal_node", 0.0, clampf(.7 + progress, 0.5, 1.8))


## One wing beat of Xivvy in flight.
func xivvy_wing(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("xivvy_wing", pan, clampf(intensity, 0.1, 2.0))


## The black variant's tell: a long low hiss.
func spider_hiss(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("spider_hiss", pan, clampf(intensity, 0.1, 2.0))


## The runner hitting the cistern after the waterfall jump: a heavy splash that carries (hunters hear it too, see the player's noise burst).
func splash_big(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("splash_big", pan, clampf(intensity, 0.1, 2.0))


## A drip off a soaked runner.
func water_drip(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("water_drip", pan, clampf(intensity, 0.1, 2.0))


var _muffle_effect: AudioEffectLowPassFilter = null


## Underwater: everything on the master bus goes dull (a low-pass) until released.
func set_muffled(on: bool) -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus < 0:
		return
	if _muffle_effect == null:
		if not on:
			return
		_muffle_effect = AudioEffectLowPassFilter.new()
		_muffle_effect.cutoff_hz = 650.0
		AudioServer.add_bus_effect(bus, _muffle_effect)
	for index in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, index) == _muffle_effect:
			AudioServer.set_bus_effect_enabled(bus, index, on)


## Hard legs on hot stone: a quick dry run of ticks (the Inferno's secret creatures, heard before they are seen).
func spider_skitter(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("spider_skitter", pan, clampf(intensity, 0.1, 2.0))


## Something cracking and settling in the dark of the Inferno's halls: a low ember crackle with a hollow knock (the secret creatures' lair ambience).
func inferno_crackle(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("inferno_crackle", pan, clampf(intensity, 0.1, 2.0))


## A deep rumble from the lava pits of the Inferno.
func pit_rumble(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("pit_rumble", pan, clampf(intensity, 0.1, 2.0))


## Back to normal hearing after a death, a continue or the return to the hub: a death mid-plunge never reached the
## swim's set_muffled(false), and a chase duck can stay down while nothing updates it (KT lost the sound in VR after
## dying). The player's own mute and volume settings are untouched.
func reset_run_effects() -> void:
	set_muffled(false)
	set_ambience_duck(0.0)
	_pending.clear()
	_office_queue_until_usec = 0


## A music-wing prop being played (MusicProps): "mic", "podium", "drums", "electric", "acoustic", "bass", "keys", "piano".
func music(kind: String, pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("music_" + kind, pan, clampf(intensity, 0.1, 2.0))


## A hand or boot on an iron ladder rung.
func ladder_rung(pan: float = 0.0, intensity: float = 1.0) -> bool:
	return _play_named("ladder_rung", pan, clampf(intensity, 0.1, 2.0))


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


func footstep(mode := "walk", surface := "") -> bool:
	var resolved := mode if mode in ["sprint", "crouch"] else "walk"
	var gaps := {"sprint": 205000, "walk": 335000, "crouch": 510000}
	var now := Time.get_ticks_usec()
	if now - _last_footstep_usec < int(gaps[resolved]):
		return false
	_last_footstep_usec = now
	_footstep_index += 1
	var side := 1.0 if _footstep_index % 2 else -1.0
	last_footstep_surface = surface
	if surface == "":
		return _play_named("footstep_%s" % resolved, side * 0.045)
	# slight random pitch per step: rendered variants are cached, four per surface and gait
	return _play_named("step:%s:%s:%d" % [resolved, surface, _footstep_index % 4], side * 0.045)


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


## Crossfades to the ambient bed `key` (AmbienceTable.key_for; "" fades out). Same key again does nothing.
func set_ambience(key: String) -> bool:
	if key == ambience_key:
		return false
	ambience_key = key
	var old := _ambience_players[_ambience_active]
	_ambience_active = 1 - _ambience_active
	var new_player := _ambience_players[_ambience_active]
	var fade := create_tween().set_parallel(true)
	fade.tween_property(old, "volume_db", -80.0, AMBIENCE_FADE)
	if key != "" and not muted:
		if _ambience_cache.has(key) or _ambience_overrides.has(key):
			_fade_in_ambience(new_player, key, fade)
		else:
			# A bed not heard yet is synthesized off the main thread (150-300 ms of GDScript sample maths that used to
			# freeze the frame on entering a new district, room or the sewer); it fades in once ready.
			_render_ambience_async(key)
	return true


func _fade_in_ambience(new_player: AudioStreamPlayer, key: String, fade: Tween) -> void:
	var replacement: Dictionary = _ambience_overrides.get(key, {})
	new_player.stream = replacement["stream"] if not replacement.is_empty() else render_ambience(key)
	new_player.volume_db = -80.0
	if DisplayServer.get_name() != "headless":
		new_player.play()
	fade.tween_property(new_player, "volume_db", _ambience_level_db() + float(replacement.get("gain_db", 0.0)),
		AMBIENCE_FADE)


var _ambience_jobs := {}   # key -> {"task": WorkerThreadPool id, "out": [stream]}


## Render a bed in the background ahead of need (PlatformProfile.prerender_ambience at boot).
func prerender_ambience(key: String) -> void:
	if key != "" and not _ambience_cache.has(key):
		_render_ambience_async(key)


func _render_ambience_async(key: String) -> void:
	if _ambience_jobs.has(key):
		return
	var out := []
	_ambience_jobs[key] = {"out": out, "task": WorkerThreadPool.add_task(func() -> void:
		out.append(_render_ambience_uncached(key)), false, "ambience bed")}


func _poll_ambience_jobs() -> void:
	for key in _ambience_jobs.keys():
		var job: Dictionary = _ambience_jobs[key]
		if not WorkerThreadPool.is_task_completed(int(job["task"])):
			continue
		WorkerThreadPool.wait_for_task_completion(int(job["task"]))
		_ambience_jobs.erase(key)
		var out: Array = job["out"]
		if out.is_empty():
			continue
		_ambience_cache[key] = out[0]
		if key == ambience_key and not muted:
			_fade_in_ambience(_ambience_players[_ambience_active], key, create_tween())


## 0 = full bed, 1 = ducked (a chase is on): eased toward by the caller each frame.
func set_ambience_duck(amount: float) -> void:
	ambience_duck = clampf(amount, 0.0, 1.0)
	var player := _ambience_players[_ambience_active]
	if ambience_key != "" and player.volume_db > -60.0:
		player.volume_db = _ambience_level_db()


func _ambience_level_db() -> float:
	return AMBIENCE_GAIN_DB - 14.0 * ambience_duck


## A looping render of a bed's layers (cached per key).
func render_ambience(key: String) -> AudioStreamWAV:
	if _ambience_cache.has(key):
		return _ambience_cache[key]
	var stream := _render_ambience_uncached(key)
	_ambience_cache[key] = stream
	return stream


## Pure: no shared state, safe on a worker thread.
func _render_ambience_uncached(key: String) -> AudioStreamWAV:
	return AmbienceSynth.render(key, AmbienceTable.layers(key))


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
	if _cue_overrides.has(cue):
		# a pack's recording: one of its variants, at the pack's gain scaled by this play's intensity (pan is not baked in)
		var replacement: Dictionary = _cue_overrides[cue]
		var streams: Array = replacement["streams"]
		_play_stream(streams[randi() % streams.size()], bus,
			float(replacement["gain_db"]) + linear_to_db(clampf(intensity, 0.05, 4.0)))
		_record(cue)
		return true
	_play_stream(render_cue(cue, pan, intensity), bus)
	_record(cue)
	return true


func _play_stream(stream: AudioStream, bus: StringName, volume_db: float = 0.0) -> void:
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
	chosen.bus = WorldAudioGate.route(bus)   # silent while a loading screen is up
	chosen.stream = stream
	chosen.volume_db = volume_db
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
	if button.has_meta(&"silent_ui"):
		return   # in-game touch controls (TouchControls): a blip on every jump or step would be a constant beeping
	var callback := Callable(self, "menu_blip")
	if not button.pressed.is_connected(callback):
		button.pressed.connect(callback)


## "step:<walk|sprint|crouch|hunter>:<surface>:<variant>": the floor's step (SurfaceSounds.PROFILES), gait scales level and
## length, the variant nudges pitch a little so a walk does not repeat one sample.
func _surface_step(cue: String, pan: float, intensity: float) -> Array:
	var parts := cue.split(":")
	var gait := parts[1]
	var profile: Dictionary = SurfaceSounds.PROFILES.get(parts[2], SurfaceSounds.PROFILES["concrete"])
	var pitch := 1.0 + (int(parts[3]) - 1.5) * .035
	var level: float = float({"walk": .05, "sprint": .095, "crouch": .017, "hunter": .045}.get(gait, .05)) * intensity
	var length: float = float({"walk": .07, "sprint": .085, "crouch": .055, "hunter": .08}.get(gait, .07))
	var c := [_noise(length, level * float(profile["noise"]), float(profile["noise_hz"]) * pitch, 0, pan, pitch),
		_thump(float(profile["thump_hz"]) * pitch, length, level * .8 * float(profile["thump"]), 0, pan)]
	if float(profile.get("click", 0.0)) > 0.0:
		c.append(_tone(2400.0 * pitch, .012, level * .35 * float(profile["click"]), 0, "square", pan))
	if float(profile.get("ring", 0.0)) > 0.0:
		c.append(_tone(620.0 * pitch, .14, level * .22, .005, "triangle", pan))
	if float(profile.get("splash", 0.0)) > 0.0:
		c.append(_noise(.16, level * .6, 1800.0 * pitch, .02, pan, 1.3))
	return c


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


## The 2D game's cues (audio.js `sfx`): blip(freq, dur, type, vol) is a tone with the 2D envelope, noise(dur, vol, cutoff) a low-passed noise burst; setTimeout delays become `delay`.
func _nw_components(name: String, pan: float, k: float) -> Array:
	var c: Array = []
	match name:
		"move": c = [_tone(520, .04, .08, 0, "square", pan)]
		"pick": c = [_tone(330, .08, .08, 0, "square", pan), _tone(660, .12, .08, 0, "square", pan)]
		"deny": c = [_tone(110, .18, .08, 0, "triangle", pan)]
		"burst": c = [_tone(110, .2, .05, 0, "sine", pan)]
		"step": c = [_tone(60, .09, .35 * k, 0, "sine", pan), _noise(.05, .35 * k * .45, 600, 0, pan, 1.0)]
		"clank": c = [_tone(310, .1, .08, 0, "triangle", pan), _tone(233, .16, .06, 0, "triangle", pan), _noise(.06, .08, 2500, 0, pan, 1.0)]
		"bound":
			for i in 3:
				c.append(_tone([700.0, 830.0, 990.0][i], .045, .075 * k, float(i) * .075, "triangle", pan))
		"pad": c = [_tone(92, .2, .12 * k, 0, "sine", pan), _tone(184, .12, .06 * k, 0, "sine", pan), _noise(.14, .12 * k * .6, 520, 0, pan, 1.0)]
		"ring":
			for i in 4:
				c.append(_tone(880, .12, .2, float(i) * .18, "sine", pan))
				c.append(_tone(1175, .12, .16, float(i) * .18, "sine", pan))
		"lure": c = [_tone(880, .12, .07, 0, "triangle", pan), _tone(660, .12, .07, .13, "triangle", pan), _tone(494, .25, .07, .26, "triangle", pan)]
		"crackle": c = [_noise(.18, .32, 5200, 0, pan, 1.0), _noise(.12, .22, 3800, .14, pan, 1.0), _tone(47, .35, .05, 0, "saw", pan)]
		"hum": c = [_tone(82, .6, .12, 0, "sine", pan), _tone(123, .45, .04, 0, "sine", pan)]
		"hum_muffled": c = [_tone(82, .7, .045, .0, "sine", pan), _tone(123, .5, .008, 0, "sine", pan)]
		"breath": c = [_noise(.4, .2 * k, 700, 0, pan, 1.0), _noise(.35, .2 * k * .8, 500, .43, pan, 1.0)]
		"talk": c = [_tone(470, .09, .26, 0, "triangle", pan), _tone(705, .06, .1, 0, "sine", pan)]
		"door": c = [_noise(.25, .5, 600, 0, pan, 1.0), _tone(70, .2, .15, 0, "square", pan)]
		"light_on": c = [_tone(180, .3, .03, 0, "triangle", pan)]
		"camera": c = [_tone(900, .05, .04, 0, "square", pan)]
		"scare": c = [_noise(1.2, .9, 6000, 0, pan, 1.0), _tone(140, 1.1, .3, 0, "saw", pan), _tone(97, 1.1, .2, 0, "square", pan)]
		"scare_short": c = [_noise(.65, .9, 6000, 0, pan, 1.0), _tone(140, .55, .3, 0, "saw", pan), _tone(97, .55, .2, 0, "square", pan)]
		"power_out": c = [_tone(200, 1.2, .15, 0, "saw", pan), _noise(.6, .3, 400, 0, pan, 1.0)]
		"chime": c = [_tone(523, .4, .15, 0, "sine", pan), _tone(784, .8, .15, 0, "sine", pan)]
		"tape": c = [_tone(210, .6, .135 * k, 0, "sine", pan), _tone(211, .6, .075 * k, 0, "triangle", pan), _noise(.5, .054 * k, 3200, 0, pan, 1.0)]
		"radio": c = [_tone(1050, .12, .042 * k, 0, "square", pan), _noise(.2, .105 * k, 2400, 0, pan, 1.0), _tone(640, .04, .036 * k, .17, "square", pan)]
		"rustle": c = [_noise(.18, .25 * k, 1400, 0, pan, 1.0), _noise(.22, .2 * k, 1100, .24, pan, 1.0)]
		"zip": c = [_noise(.3, .12, 4200, 0, pan, 1.0), _tone(1500, .05, .02, 0, "square", pan)]
		"clunk": c = [_tone(84, .16, .1, 0, "sine", pan), _noise(.08, .12, 320, 0, pan, 1.0)]
		"glass_tap": c = [_tone(2100, .04, .05, 0, "sine", pan)]
		"hinge": c = [_tone(150, .5, .06, 0, "sine", pan), _noise(.5, .08, 480, 0, pan, 1.0)]
		"latch": c = [_tone(1300, .02, .045, 0, "square", pan), _noise(.03, .06, 2600, 0, pan, 1.0)]
		"squeak": c = [_tone(2900, .12, .035, 0, "sine", pan)]
		"bed_breath": c = [_noise(.4, .2 * k * 7.0, 950, 0, pan, 1.0), _noise(.35, .2 * k * 5.6, 800, .43, pan, 1.0)]
		"bed_step": c = [_tone(60, .09, .16 * k, 0, "sine", pan), _tone(220, .09, .16 * k * 4.0, 0, "triangle", pan), _noise(.05, .16 * k * 18.0, 950, 0, pan, 1.0)]
		"bed_leave": c = [_noise(.25, 3.5 * .12, 950, 0, pan, 1.0), _tone(240, .2, .7 * .3, 0, "triangle", pan)]
		"bed_stir": c = [_tone(310, .1, .56, 0, "triangle", pan), _tone(233, .16, .42, 0, "triangle", pan), _noise(.06, .56, 1800, 0, pan, 1.0)]
		"bed_restless": c = [_noise(.4, .22 * 7.0, 950, 0, pan, 1.0), _noise(.35, .22 * 5.6, 800, .43, pan, 1.0), _tone(294, .4, .08, 0, "triangle", pan), _tone(311, .4, .08, 0, "triangle", pan)]
	return c


func _cue_components(cue: String, pan: float, intensity: float) -> Array:
	var c: Array = []
	if cue.begins_with("step:"):
		return _surface_step(cue, pan, intensity)
	if cue.begins_with("nw_"):
		return _nw_components(cue.substr(3), pan, intensity)
	match cue:
		"carnival_start": c = [_tone(1318, .22, .07, 0, "triangle", pan), _tone(1760, .3, .05, .08, "triangle", pan)]
		"carnival_throw": c = [_noise(.16, .05, 1500, 0, pan, .8), _tone(420, .12, .04, 0, "triangle", pan)]
		"carnival_ring_on": c = [_tone(1568, .12, .09, 0, "triangle", pan), _tone(2093, .2, .07, .06, "triangle", pan), _thump(300, .05, .05, 0, pan)]
		"carnival_ring_miss": c = [_thump(120, .12, .09, 0, pan), _noise(.09, .04, 500, 0, pan, .7)]
		"carnival_windup": c = [_tone(180, .35, .05, 0, "saw", pan), _tone(270, .3, .04, .2, "saw", pan)]
		"carnival_swing": c = [_noise(.18, .08, 900, 0, pan, .7), _thump(70, .22, .16, .1, pan)]
		"carnival_thud": c = [_thump(90, .25, .14, 0, pan), _noise(.1, .06, 400, 0, pan, .6)]
		"carnival_bell": c = [_tone(880, 1.6, .2 * minf(intensity, 1.5), 0, "sine", pan), _tone(1320, 1.3, .13, 0, "sine", pan), _tone(1760, 1.0, .1, 0, "triangle", pan), _thump(60, .3, .15, 0, pan)]
		"carnival_win": c = [_tone(523, .12, .08, 0, "square", pan), _tone(659, .12, .08, .1, "square", pan), _tone(784, .12, .08, .2, "square", pan), _tone(1046, .3, .09, .3, "triangle", pan)]
		"carnival_lose": c = [_tone(330, .18, .07, 0, "triangle", pan), _tone(262, .2, .07, .15, "triangle", pan), _tone(196, .4, .07, .3, "triangle", pan)]
		"carnival_shot": c = [_noise(.12, .22, 2200, 0, pan, 1.1), _thump(70, .18, .2, 0, pan), _tone(180, .08, .06, 0, "saw", pan)]
		"carnival_drop": c = [_tone(110, .5, .05, 0, "saw", pan), _tone(160, .4, .03, .1, "square", pan)]
		"carnival_hit": c = [_thump(110, .12, .16, 0, pan), _tone(520, .06, .07, 0, "square", pan)]
		"carnival_miss_swing": c = [_noise(.1, .05, 800, 0, pan, .8)]
		"carnival_miss": c = [_tone(220, .2, .05, 0, "triangle", pan), _tone(165, .3, .05, .15, "triangle", pan)]
		"carnival_hook": c = [_noise(.08, .04, 1600, 0, pan, 1.0), _tone(900, .05, .04, 0, "triangle", pan)]
		"carnival_carousel_tune":
			# a waltz on a music box that has been left out in the damp: every note a little off, one flat, the bass a beat late
			var melody := [523.3, 659.3, 784.0, 659.3, 880.0, 784.0, 659.3, 587.3, 523.3, 659.3, 784.0, 1046.5, 880.0, 784.0, 698.5, 659.3]
			for i in melody.size():
				var off := 1.0 + 0.018 * sin(float(i) * 2.3) - (0.04 if i == 11 else 0.0)
				c.append(_tone(float(melody[i]) * off, .42, .05, float(i) * .5, "triangle", pan))
				if i % 4 == 0:
					c.append(_tone(130.8 if i % 8 == 0 else 196.0, .9, .035, float(i) * .5 + 0.03, "square", pan))
		"carnival_lever": c = [_thump(80, .2, .2, 0, pan), _tone(220, .15, .08, 0, "square", pan), _noise(.12, .08, 700, .05, pan, .8)]
		"carnival_tick": c = [_tone(1400, .02, .03, 0, "square", pan)]
		"carnival_pop": c = [_thump(160, .08, .1, 0, pan), _tone(700, .05, .05, 0, "square", pan)]
		"carnival_clang": c = [_tone(1200, .3, .1, 0, "square", pan), _tone(1900, .25, .06, 0, "triangle", pan), _noise(.06, .08, 3000, 0, pan, 1.2)]
		"carnival_splash": c = [_noise(.3, .06, 900, 0, pan, .9), _tone(500, .08, .04, .02, "sine", pan)]
		"carnival_motor": c = [_tone(90, .3, .05, 0, "saw", pan), _tone(120, .3, .03, 0, "square", pan)]
		"carnival_grip": c = [_tone(240, .1, .06, 0, "square", pan), _thump(110, .12, .08, .05, pan)]
		"collect":
			c = [_tone(220, .12, .13, 0, "square"), _tone(330, .16, .10, .09, "square"), _tone(660, .22, .07, .19)]
		"recharge":
			var lift := minf(120.0, 30.0 * intensity)
			c = [_tone(180 + lift, .09, .10, 0, "square"), _tone(360 + lift, .14, .08, .08)]
		"menu": c = [_tone(620, .035, .026, 0, "square"), _tone(930, .055, .018, .022)]
		"music_box":
			var phrase := [1046.5, 1318.5, 1568.0, 1318.5, 1760.0, 1568.0]
			for index in phrase.size(): c.append(_tone(phrase[index], .22, .07, index * .2, "triangle"))
		"music_box_tune":
			# the music box's loop (MusicBoxTune): a phrase, four notes more, then four that turn around and come home
			var tune := [1046.5, 1318.5, 1568.0, 1318.5, 1760.0, 1568.0, 1318.5, 1174.7,
				1318.5, 1568.0, 1396.9, 1174.7, 1046.5, 1174.7, 1318.5, 1046.5]
			for index in tune.size(): c.append(_tone(tune[index], .34, .14, index * .27, "triangle"))
			c.append(_tone(0.0, .01, 0.0, tune.size() * .27 + .3))   # breath before the loop
		"glyra_hum":
			# Glyra humming along, low and soft (HunterView3D, only while her music plays)
			var hum := [261.6, 329.6, 392.0, 329.6, 440.0, 392.0, 329.6, 293.7]
			for index in hum.size(): c.append(_tone(hum[index], .5, .12, index * .45, "sine"))
			c.append(_tone(0.0, .01, 0.0, hum.size() * .45 + .6))
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
		"axe_swing": c = [_noise(.20, .05, 1250, 0, pan, .72),
			_noise(.11, .035, 2300, .07, pan, .95)]
		"axe_chop": c = [_thump(64, .24, .20, 0, pan),
			_noise(.14, .11, 760, 0, pan, .9),
			_tone(168, .09, .07, .02, "square", pan),
			_noise(.09, .06, 2100, .08, pan, 1.1)]
		"light_switch": c = [_tone(2600, .012, .1, 0, "square", pan), _thump(140, .04, .08, .01, pan)]
		"sleep_settle": c = [_noise(.5, .05, 400, 0, pan, .5), _tone(110, .4, .04, .1, "sine", pan)]
		"sleep_yawn": c = [_tone(220, .55, .07, 0, "triangle", pan), _tone(165, .5, .05, .35, "triangle", pan),
			_noise(.4, .04, 900, .2, pan, .6)]
		"sleep_stir": c = [_thump(55, .3, .12, 0, pan), _noise(.35, .05, 300, .05, pan, .5)]
		"sleep_jolt": c = [_thump(80, .18, .22, 0, pan), _tone(330, .12, .09, 0, "square", pan),
			_noise(.12, .1, 1600, .02, pan, 1.0)]
		"hunter_snore": c = [_noise(.7, .07, 260, 0, pan, .7), _tone(70, .6, .06, .05, "sawtooth", pan)]
		"hide_search": c = [_tone(92, .42, .09, 0, "sawtooth", pan),
			_noise(.3, .07, 520, .05, pan, .8),
			_thump(70, .16, .12, .18, pan),
			_thump(64, .16, .10, .46, pan)]
		"tool_break": c = [_noise(.16, .095, 1850, 0, pan, 1.22),
			_tone(310, .08, .065, .025, "square", pan),
			_tone(118, .18, .052, .09, "triangle", pan)]
		"nyxie_timer": c = [_tone(72, .5, .09), _tone(108, .4, .07, .18, "triangle"), _tone(144, .3, .05, .34, "triangle")]
		"nyxie_empty": c = [_tone(48, .7, .13, 0, "saw"), _tone(32, .9, .08, .1)]
		"hunter_laugh": c = [_tone(392, .07, .05 * intensity, 0, "triangle", pan), _tone(349, .07, .045 * intensity, .10, "triangle", pan), _tone(311, .09, .04 * intensity, .20, "triangle", pan)]
		"xivvy_screech": c = [_tone(1250, .12, .07 * intensity, 0, "saw", pan), _tone(1760, .16, .08 * intensity, .07, "saw", pan), _tone(2350, .22, .075 * intensity, .16, "square", pan), _noise(.34, .05 * intensity, 3400, .06, pan, 1.3)]
		"radar_static": c = [_noise(.55, .09 * intensity, 2600, 0, pan, 1.4), _noise(.35, .06 * intensity, 900, .12, pan, 1.1), _tone(980, .08, .03 * intensity, .4, "square", pan)]
		"system_offline": c = [_tone(260, .12, .06 * intensity, 0, "square", pan), _tone(180, .16, .06 * intensity, .1, "square", pan), _tone(110, .3, .07 * intensity, .22, "saw", pan)]
		"signal_node": c = [_tone(420.0 * intensity, .07, .07, 0, "square", pan), _tone(630.0 * intensity, .05, .04, .05, "triangle", pan)]
		"xivvy_wing": c = [_noise(.13, .05 * intensity, 520, 0, pan, .9), _thump(120, .09, .03 * intensity, .02, pan)]
		"spider_hiss": c = [_noise(.9, .16 * intensity, 520, 0, pan, .7), _tone(61, .8, .15 * intensity, .02, "saw", pan), _noise(.55, .09 * intensity, 900, .25, pan, 1.1)]
		"spider_bark": c = [_tone(74, .30, .20 * intensity, 0, "saw", pan), _tone(55, .36, .18 * intensity, .04, "square", pan), _noise(.22, .09 * intensity, 240, .02, pan, .8), _tone(96, .22, .15 * intensity, .46, "saw", pan), _noise(.18, .07 * intensity, 300, .46, pan, .9)]
		"splash_big": c = [_noise(.9, .22 * intensity, 700, 0, pan, .8), _noise(.5, .16 * intensity, 2200, .02, pan, 1.2), _thump(70, .35, .16 * intensity, 0, pan),
			_noise(.7, .08 * intensity, 1400, .25, pan, 1.0)]
		"music_mic": c = [_tone(2100, .5, .05 * intensity, 0, "sine", pan), _tone(2800, .45, .035 * intensity, .08, "sine", pan), _thump(90, .12, .1 * intensity, 0, pan)]
		"music_podium": c = [_thump(110, .1, .14 * intensity, 0, pan), _thump(110, .1, .12 * intensity, .28, pan), _noise(.06, .03 * intensity, 1800, 0, pan, 1.0)]
		"music_drums": c = [_thump(60, .3, .2 * intensity, 0, pan), _noise(.14, .12 * intensity, 1900, .22, pan, 1.0), _thump(60, .3, .18 * intensity, .44, pan),
			_noise(.12, .11 * intensity, 1900, .66, pan, 1.0), _noise(.9, .07 * intensity, 6200, .66, pan, 1.4)]
		"music_electric": c = [_tone(82.4, .9, .07 * intensity, 0, "saw", pan), _tone(123.5, .9, .06 * intensity, .01, "saw", pan), _tone(164.8, .9, .05 * intensity, .02, "square", pan)]
		"music_acoustic": c = [_tone(196, .8, .05 * intensity, 0, "triangle", pan), _tone(247, .75, .05 * intensity, .04, "triangle", pan), _tone(294, .7, .05 * intensity, .08, "triangle", pan),
			_tone(392, .65, .045 * intensity, .12, "triangle", pan)]
		"music_bass": c = [_tone(55, .7, .14 * intensity, 0, "saw", pan), _tone(110, .5, .04 * intensity, 0, "triangle", pan)]
		"music_keys": c = [_tone(261.6, .7, .05 * intensity, 0, "square", pan), _tone(329.6, .7, .045 * intensity, 0, "square", pan), _tone(392, .7, .045 * intensity, 0, "square", pan)]
		"music_piano": c = [_tone(220, 1.1, .07 * intensity, 0, "triangle", pan), _tone(277.2, 1.0, .06 * intensity, .02, "triangle", pan), _tone(329.6, .95, .06 * intensity, .04, "triangle", pan),
			_tone(440, .8, .03 * intensity, .04, "sine", pan)]
		"water_drip": c = [_tone(980, .05, .05 * intensity, 0, "triangle", pan), _tone(640, .09, .04 * intensity, .04, "triangle", pan), _noise(.05, .03 * intensity, 3000, 0, pan, 1.2)]
		"spider_skitter": c = [_noise(.04, .07 * intensity, 3100, 0, pan, 1.3), _noise(.04, .06 * intensity, 2700, .07, pan, 1.3), _noise(.04, .065 * intensity, 3300, .13, pan, 1.3),
			_noise(.04, .055 * intensity, 2500, .21, pan, 1.3), _noise(.04, .06 * intensity, 3000, .26, pan, 1.3), _thump(150, .05, .03 * intensity, .0, pan)]
		"inferno_crackle": c = [_noise(.5, .05 * intensity, 1500, 0, pan, 1.4), _noise(.06, .08 * intensity, 2600, .12, pan, 1.5), _noise(.05, .07 * intensity, 2200, .31, pan, 1.5),
			_thump(70, .22, .06 * intensity, .4, pan), _tone(46, .6, .05 * intensity, .38, "triangle", pan)]
		"pit_rumble": c = [_tone(38, 1.1, .07 * intensity, 0, "triangle", pan), _noise(.9, .035 * intensity, 380, .1, pan, 1.2), _thump(52, .35, .06 * intensity, .5, pan)]
		"ladder_rung": c = [_tone(540, .07, .05 * intensity, 0, "square", pan), _tone(820, .1, .03 * intensity, .01, "triangle", pan),
			_thump(120, .05, .03 * intensity, 0, pan)]
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


func _render_components(components: Array, seed_value: int, fixed_seconds: float = 0.0) -> AudioStreamWAV:
	var total := 0.05
	for component in components:
		total = maxf(total, float(component["delay"]) + float(component["duration"]) + .025)
	if fixed_seconds > 0.0:
		total = fixed_seconds
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
			if bool(component.get("flat", false)):
				# a steady layer of a loop: no decay, and a slow swell (waves, wind) that returns to its start
				envelope = 1.0
				var swell := float(component.get("swell", 0.0))
				if swell > 0.0:
					envelope = .55 + .45 * sin(TAU * t / swell)
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
