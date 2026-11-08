extends RefCounted

## Headless checks for the procedural SoundSystem port. A dummy audio driver
## cannot tell us what a cue sounds like, but it can prove every shipping cue
## renders valid stereo PCM, direction changes channel energy, and debounce gates
## repeated footsteps and UI buttons.

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


## Loading / sync screens silence the world and fade it back in on entry; UI sounds keep playing.
func _check_world_gate(host: Node) -> void:
	var world := AudioStreamPlayer3D.new()
	world.bus = &"Master"
	host.add_child(world)
	var sfx := AudioStreamPlayer.new()
	sfx.bus = &"SFX"
	host.add_child(sfx)
	var ui := AudioStreamPlayer.new()
	ui.bus = &"UI"
	host.add_child(ui)
	var screen := (load("res://game/boot/route_loading.tscn") as PackedScene).instantiate() as RouteLoadingScreen
	screen.auto_start = false   # shows the building screen without loading a route
	host.add_child(screen)
	await host.get_tree().process_frame
	_expect(WorldAudioGate.is_held(), "the loading screen does not silence the world")
	_expect(world.bus == &"WorldGateMaster" and sfx.bus == &"WorldGateSFX", "world players are not routed to the muted gate (%s, %s)" % [world.bus, sfx.bus])
	_expect(ui.bus == &"UI", "a UI sound was muted by the loading screen")
	_expect(WorldAudioGate.gate_db() <= -79.0, "the gate bus is not silent (%.1f dB)" % WorldAudioGate.gate_db())
	var late := AudioStreamPlayer2D.new()   # spawned while loading (a hunter, an ambience bed)
	host.add_child(late)
	_expect(late.bus == &"WorldGateMaster", "a sound added during loading escapes the gate")
	_expect(WorldAudioGate.route(&"SFX") == &"WorldGateSFX" and WorldAudioGate.route(&"UI") == &"UI", "one-shots are not routed through the gate")
	screen.show_sync_step(1, 5)   # the co-op sync gate on the same screen keeps it silent
	_expect(WorldAudioGate.is_held(), "the sync step released the gate")
	screen.dismiss()
	_expect(not WorldAudioGate.is_held(), "entering the world does not release the gate")
	await host.get_tree().create_timer(WorldAudioGate.FADE_SECONDS * 0.4).timeout
	var mid := WorldAudioGate.gate_db()
	_expect(mid > -79.0 and mid < -0.5, "the world should be fading in, not jumping (%.1f dB)" % mid)
	await host.get_tree().create_timer(WorldAudioGate.FADE_SECONDS).timeout
	_expect(absf(WorldAudioGate.gate_db()) < 0.1, "the world did not come back to full volume")
	_expect(world.bus == &"Master" and sfx.bus == &"SFX" and late.bus == &"Master", "players were not returned to their own buses")
	# the pre-route loading scene is freed into the route: that also lets the world back in
	screen.show_building_floor()
	_expect(WorldAudioGate.is_held(), "showing the screen again does not silence the world")
	screen.queue_free()
	await host.get_tree().process_frame
	_expect(not WorldAudioGate.is_held(), "freeing the loading screen left the world silent")
	await host.get_tree().create_timer(WorldAudioGate.FADE_SECONDS + 0.1).timeout
	for node in [world, sfx, ui, late]:
		node.queue_free()


func run(host: Node) -> int:
	await _check_world_gate(host)
	_expect(AudioServer.get_bus_index("SFX") >= 0, "SFX audio bus is missing")
	_expect(AudioServer.get_bus_index("UI") >= 0, "UI audio bus is missing")

	var cues := ["collect", "recharge", "menu", "music_box", "alert", "chase_start", "taser",
		"door_open", "door_close", "door_breach", "interaction_fail", "tool_break", "axe_swing", "axe_chop", "hide_search", "light_switch", "sleep_settle", "sleep_yawn", "sleep_stir", "sleep_jolt", "hunter_snore",
		"nyxie_timer", "nyxie_empty", "hunter_footstep", "mimic",
		"mimic_rare", "heartbeat",
		"footstep_walk", "footstep_sprint", "footstep_crouch", "capture",
		"teammate_footstep_walk", "teammate_footstep_sprint",
		"teammate_footstep_crouch",
		"struggle", "escape", "office_camera", "office_warning",
		"office_crimson_door", "office_presence", "office_scrape",
		"office_static", "office_drain", "office_footsteps", "office_breath",
		"office_shift", "office_control", "office_jumpscare"]
	for cue in cues:
		var stream := Sound.render_cue(cue)
		_expect(stream != null, "%s did not render" % cue)
		if stream == null:
			continue
		_expect(stream.stereo, "%s is not stereo" % cue)
		_expect(stream.mix_rate == 44100, "%s rendered at %d Hz" % [cue, stream.mix_rate])
		_expect(stream.format == AudioStreamWAV.FORMAT_16_BITS,
			"%s is not 16-bit PCM" % cue)
		_expect(stream.data.size() > 100, "%s rendered an empty waveform" % cue)
	print("  waveforms  %d procedural stereo cues render to valid PCM" % cues.size())

	var left_pan := Sound.render_cue("office_presence", -0.9)
	var right_pan := Sound.render_cue("office_presence", 0.9)
	var left_energy := _channel_energy(left_pan.data, 0)
	var right_energy := _channel_energy(left_pan.data, 1)
	_expect(left_energy > right_energy * 2.0,
		"a left-panned cue is not meaningfully louder in the left channel")
	_expect(_channel_energy(right_pan.data, 1) > _channel_energy(right_pan.data, 0) * 2.0,
		"a right-panned cue is not meaningfully louder in the right channel")
	print("  direction  panning carries distinct left/right energy")

	_check_cue_identity()
	_check_prewarm_gate()
	_check_step_prewarm()
	_check_scaled_steps()
	Sound.reset_test_counters()
	_expect(Sound.footstep("walk"), "first footstep was swallowed")
	_expect(not Sound.footstep("walk"), "same-frame footsteps bypassed debounce")
	_expect(int(Sound.play_counts.get("footstep_walk", 0)) == 1,
		"footstep debounce recorded more than one cue")
	# 114: cadence follows real speed -- the base speeds keep the old gaps, faster feet step faster, a wall stops them
	for gait in ["walk", "sprint", "crouch"]:
		var base_speed := float({"walk": GameConfig.PLAYER_WALK_SPEED, "sprint": GameConfig.PLAYER_SPRINT_SPEED,
			"crouch": GameConfig.PLAYER_CROUCH_SPEED}[gait]) / GameConfig.TILE_SIZE
		var base_gap := Sound.footstep_gap(gait, base_speed)
		_expect(absf(base_gap - float(Sound.STEP_GAP_FALLBACK[gait])) < .01,
			"%s steps at base speed moved off the old cadence (%.3fs)" % [gait, base_gap])
		_expect(absf(Sound.footstep_gap(gait, base_speed * 1.5) - base_gap / 1.5) < .01,
			"%s steps do not speed up with the body (x1.5 speed)" % gait)
	Sound.reset_test_counters()
	_expect(not Sound.footstep("walk", "", .05), "a runner pressed into a wall still stepped")
	Sound._last_footstep_usec = Time.get_ticks_usec() - 200000
	_expect(not Sound.footstep("walk", "", 4.0), "a 4 m/s walk stepped after .2s (gap .335s)")
	_expect(Sound.footstep("walk", "", 8.0), "an 8 m/s walk did not step after .2s (gap .17s)")
	_expect(Sound.remote_player_footstep("walk", .5, .04),
		"nearby co-op footsteps did not use their distinct cue")
	_expect(Sound.last_cue == "teammate_footstep_walk",
		"co-op footsteps are indistinguishable from local/hunter footsteps")

	var button := Button.new()
	host.get_tree().root.add_child(button)
	await host.get_tree().process_frame
	Sound.reset_test_counters()
	button.pressed.emit()
	_expect(int(Sound.play_counts.get("menu", 0)) == 1,
		"a newly-added UI button did not play the menu cue")
	button.queue_free()
	await host.get_tree().process_frame

	# The authoritative Thessine event must resolve into the same rare cue on a
	# gameplay peer. This exercises the event-to-audio bridge, not only waveform
	# generation.
	var route: Node = load("res://game/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(route)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	Sound.reset_test_counters()
	route.call("_play_world_audio", {"what": "thessine_mimic", "rare": true,
		"choice": 0.0})
	_expect(int(Sound.play_counts.get("mimic_rare", 0)) == 1,
		"a synchronized Thessine mimic event played no rare false cue")
	var chased: HunterView3D = route.hunter_view
	var chase_cell: Vector2i = route.facility_view.generator.exit_cell
	route.player.global_position = route.facility_view.cell_to_world(chase_cell)
	chased.brain.position = Vector2(chase_cell) + Vector2(.5, .5)
	chased.brain.active = true
	chased.brain.state = HunterBrain.State.CHASE
	chased.brain.stun_timer = 0.0
	# This suite runs an offline route; peer 1 is the local runner contract.
	chased.target_peer_id = 1
	route._was_locally_pursued = false
	Sound.reset_test_counters()
	route._update_local_audio(.1)
	_expect(int(Sound.play_counts.get("chase_start", 0)) == 1,
		"a newly targeted runner heard no chase-start sting")
	_expect(int(Sound.play_counts.get("heartbeat", 0)) == 1,
		"an actively pursued runner heard no heartbeat ambience")
	route._update_local_audio(.1)
	_expect(int(Sound.play_counts.get("chase_start", 0)) == 1,
		"the chase-start sting repeated every frame")
	route._hunter_step_elapsed = 1.0   # one whole footfall due (114: the phase counts her footfalls)
	Sound.reset_test_counters()
	route._update_local_audio(.01)
	_expect(int(Sound.play_counts.get("hunter_footstep", 0)) == 1,
		"a moving non-special-cased route hunter produced no heavy footstep")
	# B4: a hunter left in CHASE far off (her sight of the runner is gone) must not sound the chase or pass as the danger of a
	# chase. A chase she can see still does, at any range, and one close by still does.
	_expect(chased.brain.has_method("pursuit_cue"), "the hunter brain has no pursuit cue (a chase far off would still sound)")
	var far_from_runner := Vector2(route.player.grid_position()) + Vector2(40.0, 0.0)
	chased.brain.position = far_from_runner
	chased.brain.direct_chase_visible = false
	route._was_locally_pursued = false
	Sound.reset_test_counters()
	route._update_local_audio(.1)
	_expect(int(Sound.play_counts.get("chase_start", 0)) == 0,
		"a hunter 40 cells off, out of sight after the chase, still sounded the chase-start sting")
	chased.brain.direct_chase_visible = true
	route._was_locally_pursued = false
	Sound.reset_test_counters()
	route._update_local_audio(.1)
	_expect(int(Sound.play_counts.get("chase_start", 0)) == 1,
		"a hunter 40 cells off that she can see heard no chase-start sting")
	chased.brain.direct_chase_visible = false
	chased.brain.position = Vector2(chase_cell) + Vector2(.5, .5)
	route._was_locally_pursued = false
	Sound.reset_test_counters()
	route._update_local_audio(.1)
	_expect(int(Sound.play_counts.get("chase_start", 0)) == 1,
		"a hunter close by after the chase heard no chase-start sting")
	route.queue_free()
	await host.get_tree().process_frame

	print("  wiring     UI, movement debounce, and Thessine sync are live")
	Sound.stop_all()
	await host.get_tree().process_frame

	if _failures == 0:
		print("audio OK")
	return _failures


## Golden byte hashes of rendered cues, captured with the global hash(stream.data) (PackedByteArray has no hash()) from the
## code as it was BEFORE render_cue was split into _cue_key + _render_cue_uncached. They pin the refactor: the same bytes,
## whichever path renders them. The float synthesis is the dev PC's x86 build: on another CPU architecture (arm64, the Air)
## these may legitimately need regenerating, and a mismatch there is not by itself a determinism bug.
const GOLDEN_CUES := [
	["step:walk:concrete:1", 0.05, 1.0, 3808229991],
	["step:sprint:metal:2", -0.05, 1.0, 553711646],
	["heartbeat", 0.0, 0.65, 456396346],
	["music_box_tune", 0.0, 1.0, 642208190],
	# captured before _render_components hoisted its per-sample dictionary lookups out of the inner loop
	["glyra_hum", 0.0, 1.0, 3426237372],
	["carnival_carousel_tune", 0.0, 1.0, 2758972945],
	["step:sprint:carpet:1", 0.05, 1.0, 3790847878],
	["step:sprint:water:1", 0.05, 1.0, 3697065950],
]
## sha256 of the 96 step hashes joined with "," (gait walk/sprint/crouch x SurfaceSounds.SURFACES x variant 0..3, pan -0.05 for
## variants 0 and 2, +0.05 for 1 and 3, intensity 1.0) and of the 20 heartbeat hashes (intensity 0.05..1.00, pan 0).
const STEP_GOLDEN := "84f0549c04e2939292b01e330a5325977c6a0c1085a45c5586e7c96af6993555"
const HEART_GOLDEN := "e7299c0b304aeabae8646a91e692e171df98907c445b9d178266fff4f1a0e82a"


## T1: render_cue's split into _cue_key + _render_cue_uncached changed no byte, and footstep()/heartbeat() still reach it
## under the keys the prewarm and the caches use.
func _check_cue_identity() -> void:
	var saved_overrides: Dictionary = Sound._cue_overrides
	var saved_muted := Sound.muted
	var saved_index: int = Sound._footstep_index
	Sound._cue_overrides = {}   # a loaded pack must not steer footstep()/heartbeat() away from render_cue
	Sound.muted = false
	for golden in GOLDEN_CUES:
		var cue := String(golden[0])
		var pan := float(golden[1])
		var intensity := float(golden[2])
		var want := int(golden[3])
		_expect(hash(Sound.render_cue(cue, pan, intensity).data) == want, "%s: render_cue bytes drifted from the golden" % cue)
		var key: String = Sound._cue_key(cue, pan, intensity)
		_expect(hash(Sound._render_cue_uncached(cue, pan, intensity).data) == want, "%s: _render_cue_uncached bytes drifted" % cue)
		var direct: AudioStreamWAV = Sound._render_components(Sound._cue_components(cue, snappedf(pan, 0.05), snappedf(intensity, 0.05)),
			abs(key.hash()))
		_expect(hash(direct.data) == want, "%s: _render_components(_cue_components(...)) bytes drifted" % cue)
	# aggregate identity over every step key and every heartbeat key (a regression in any gait or surface fails here)
	var step_hashes := []
	for gait in ["walk", "sprint", "crouch"]:
		for surface in SurfaceSounds.SURFACES:
			for variant in 4:
				var step_pan := -0.05 if variant % 2 == 0 else 0.05
				step_hashes.append(str(hash(Sound._render_cue_uncached("step:%s:%s:%d" % [gait, surface, variant], step_pan, 1.0).data)))
	_expect(step_hashes.size() == 96, "expected 96 step keys, got %d" % step_hashes.size())
	_expect(",".join(step_hashes).sha256_text() == STEP_GOLDEN, "the 96 step cues no longer render to the golden bytes")
	var heart_hashes := []
	for index in range(1, 21):
		heart_hashes.append(str(hash(Sound._render_cue_uncached("heartbeat", 0.0, index * 0.05).data)))
	_expect(",".join(heart_hashes).sha256_text() == HEART_GOLDEN, "the 20 heartbeat cues no longer render to the golden bytes")
	# key coverage: footstep() and heartbeat() render under the keys _cue_key builds (the cache entry is erased first, so
	# only a real render_cue call can put it back)
	for gait in ["walk", "sprint", "crouch"]:
		for surface in SurfaceSounds.SURFACES:
			for _repeat in 4:
				var next_index: int = Sound._footstep_index + 1
				var side := 1.0 if next_index % 2 else -1.0
				var step_key: String = Sound._cue_key("step:%s:%s:%d" % [gait, surface, next_index % 4], side * 0.045, 1.0)
				Sound._cache.erase(step_key)
				Sound._last_footstep_usec = -2000000
				_expect(Sound.footstep(gait, surface), "footstep(%s, %s) was swallowed" % [gait, surface])
				_expect(Sound._cache.has(step_key), "footstep(%s, %s) did not render under %s" % [gait, surface, step_key])
	for danger in [0.65, 1.0]:
		var beat_key: String = Sound._cue_key("heartbeat", 0.0, danger)
		Sound._cache.erase(beat_key)
		Sound._last_heartbeat_usec = -2000000
		_expect(Sound.heartbeat(danger), "heartbeat(%.2f) was swallowed" % danger)
		_expect(Sound._cache.has(beat_key), "heartbeat(%.2f) did not render under %s" % [danger, beat_key])
	# the key the prewarm uses is the key MusicBoxTune's render_cue("music_box_tune") lands under
	Sound._cache.erase(Sound._cue_key("music_box_tune", 0.0, 1.0))
	Sound.render_cue("music_box_tune")
	_expect(Sound._cache.has(Sound._cue_key("music_box_tune", 0.0, 1.0)), "render_cue(music_box_tune) is not cached under the prewarm's key")
	Sound._cue_overrides = saved_overrides
	Sound.muted = saved_muted
	Sound._footstep_index = saved_index
	print("  identity   render_cue split and render hoist are byte-identical (8 goldens, 96 step + 20 heartbeat aggregates), keys covered")


## T3: the prewarm is the music box tune only; its gate is pure and tested; an isolated Sound instance (not in the tree, so
## no _ready/_process/_exit_tree) is stepped by hand through arm -> blocked by bed jobs -> dispatch -> adopt -> gap.
func _check_prewarm_gate() -> void:
	# the pure gate: (now, next, ambience_jobs_empty, armed)
	_expect(not Sound._prewarm_may_dispatch(1000, 500, false, true), "the prewarm dispatched with bed jobs in flight")
	_expect(not Sound._prewarm_may_dispatch(400, 500, true, true), "the prewarm dispatched before its gap was over")
	_expect(not Sound._prewarm_may_dispatch(1000, 500, true, false), "the prewarm dispatched while not armed")
	_expect(Sound._prewarm_may_dispatch(500, 500, true, true), "the prewarm did not dispatch exactly at its time")
	_expect(Sound._prewarm_may_dispatch(900, 500, true, true), "the prewarm did not dispatch after its time")
	# the cue list
	var cues: Array = Sound._prewarm_cues()
	# 96 runner step keys + music box + 20 heartbeats + glyra_hum + the carousel tune; sprint steps come first
	_expect(cues.size() == 96 + 1 + 20 + 2, "the prewarm list has %d cues, expected 119" % cues.size())
	var seen := {}
	var step_keys := {}
	for index in cues.size():
		var spec: Array = cues[index]
		var cue_name := String(spec[0])
		var spec_key: String = Sound._cue_key(cue_name, float(spec[1]), float(spec[2]))
		_expect(not seen.has(spec_key), "%s is prewarmed twice" % spec_key)
		seen[spec_key] = true
		_expect(Sound.knows_cue(cue_name), "%s is not a known cue" % cue_name)
		if cue_name.begins_with("step:"):
			step_keys[spec_key] = true
			_expect(index < 32 or cue_name.begins_with("step:walk") or cue_name.begins_with("step:crouch"), "a step is out of order at %d" % index)
			_expect(not cue_name.begins_with("step:hunter"), "hunter steps are played scaled, not prewarmed: %s" % cue_name)
		if index < 32:
			_expect(cue_name.begins_with("step:sprint:"), "the first 32 prewarmed cues are not the sprint steps (index %d: %s)" % [index, cue_name])
	_expect(step_keys.size() == 96, "the prewarm does not cover the 96 step keys (%d)" % step_keys.size())
	for must in ["music_box_tune", "glyra_hum", "carnival_carousel_tune"]:
		_expect(seen.has(Sound._cue_key(must, 0.0, 1.0)), "%s (render_cue's default key) is not prewarmed" % must)
	for index in range(1, 21):
		_expect(seen.has(Sound._cue_key("heartbeat", 0.0, index * 0.05)), "heartbeat intensity %.2f is not prewarmed" % (index * 0.05))
	_expect(seen.has(Sound._cue_key("heartbeat", 0.0, 0.04)), "heartbeat(0.04) lands on a key the prewarm does not cover")
	_expect(Sound.knows_cue("music_box_tune"), "music_box_tune is not a known cue")
	_expect(not Sound._prewarm_allowed(), "the prewarm is allowed headless")
	_expect(Sound._prewarm_queue.is_empty(), "the real autoload queued a prewarm headless")
	# an isolated instance, stepped by hand
	var s: Node = (load("res://game/autoload/sound.gd") as GDScript).new()
	s._prewarm_queue = [["menu", 0.0, 1.0], ["collect", 0.0, 1.0]]
	s._prewarm_step()
	_expect(s._prewarm_job.is_empty() and s._prewarm_queue.size() == 2, "the prewarm dispatched before the boot fan-out armed it")
	s.prerender_ambience("")   # no key: starts no bed, but arms the latch
	_expect(s._prewarm_armed and s._ambience_jobs.is_empty(), "prerender_ambience did not arm the prewarm (or started a bed job)")
	s._ambience_jobs = {"dummy": {}}
	s._prewarm_step()
	_expect(s._prewarm_job.is_empty() and s._prewarm_queue.size() == 2, "the prewarm dispatched while a bed job was in flight")
	s._ambience_jobs = {}
	s._prewarm_step()
	_expect(not s._prewarm_job.is_empty() and s._prewarm_queue.size() == 1, "the prewarm did not dispatch once the beds drained")
	var menu_key: String = Sound._cue_key("menu", 0.0, 1.0)
	var before := Time.get_ticks_msec()
	var waited := 0
	while not s._prewarm_job.is_empty() and waited < 10000:
		OS.delay_msec(5)
		waited += 5
		before = Time.get_ticks_msec()
		s._prewarm_step()
	_expect(s._prewarm_job.is_empty(), "the prewarm job never landed")
	_expect(s._cache.has(menu_key), "the prewarmed cue was not inserted into the cache")
	if s._cache.has(menu_key):
		_expect(hash((s._cache[menu_key] as AudioStreamWAV).data) == hash(Sound._render_cue_uncached("menu", 0.0, 1.0).data),
			"a worker-rendered cue differs from the main-thread render")
	_expect(s._prewarm_next_msec >= before + Sound.PREWARM_GAP_MSEC, "the gap does not count from adoption")
	s._prewarm_step()
	_expect(s._prewarm_job.is_empty() and s._prewarm_queue.size() == 1, "job two started inside the gap")
	s._prewarm_next_msec = 0
	s._prewarm_step()
	_expect(not s._prewarm_job.is_empty() and s._prewarm_queue.is_empty(), "job two did not start once the gap was over")
	waited = 0
	while not s._prewarm_job.is_empty() and waited < 10000:
		OS.delay_msec(5)
		waited += 5
		s._prewarm_step()
	_expect(s._cache.has(Sound._cue_key("collect", 0.0, 1.0)), "the second prewarmed cue was not inserted")
	s._prewarm_step()
	_expect(not s._prewarm_armed, "the prewarm stayed armed with nothing left to do")
	# a cue a use site already rendered is skipped: no job
	var alert_key: String = Sound._cue_key("alert", 0.0, 1.0)
	var placeholder := AudioStreamWAV.new()
	s._cache[alert_key] = placeholder
	s._prewarm_queue = [["alert", 0.0, 1.0]]
	s._prewarm_armed = true
	s._prewarm_next_msec = 0
	s._prewarm_step()
	_expect(s._prewarm_job.is_empty() and s._prewarm_queue.is_empty() and s._cache[alert_key] == placeholder,
		"an already-cached cue started a prewarm job or was replaced")
	if not s._prewarm_job.is_empty():
		WorkerThreadPool.wait_for_task_completion(int(s._prewarm_job["task"]))
	s.free()
	print("  prewarm    119 cues (96 steps, sprint first; music box; 20 heartbeats; glyra; carousel); gate (armed, beds drained, 250 ms gap from adoption) and cached-skip hold")


## T4: the step keys render on a worker thread to the same bytes as on the main thread (so the prewarm may fill the cache
## the footstep path reads), a job batches the four variants of one step and no more than PREWARM_BATCH_MAX of anything,
## and a prewarmed step makes footstep() render nothing on the main thread.
func _check_step_prewarm() -> void:
	# worker render of every step key == the aggregate golden
	var out := []
	out.resize(96)
	var specs := []
	for gait in ["walk", "sprint", "crouch"]:
		specs.append_array(Sound._step_prewarm_specs(gait))
	var task := WorkerThreadPool.add_group_task(func(index: int) -> void:
		var spec: Array = specs[index]
		out[index] = hash(Sound._render_cue_uncached(String(spec[0]), float(spec[1]), float(spec[2])).data), 96, -1, true, "step prewarm test")
	WorkerThreadPool.wait_for_group_task_completion(task)
	var worker_hashes := []
	for value in out:
		worker_hashes.append(str(value))
	_expect(",".join(worker_hashes).sha256_text() == STEP_GOLDEN, "the 96 step cues rendered on worker threads differ from the golden bytes")
	# batching, by hand on an isolated instance
	var s: Node = (load("res://game/autoload/sound.gd") as GDScript).new()
	s._prewarm_queue = Sound._step_prewarm_specs("sprint").slice(16, 24) + [["heartbeat", 0.0, 0.5]]   # metal + stone variants 0..3 each
	s._prewarm_armed = true
	s._prewarm_step()
	_expect(not s._prewarm_job.is_empty() and (s._prewarm_job["keys"] as Array).size() == 4 and s._prewarm_queue.size() == 5,
		"a job did not take exactly the four variants of one step (queue left: %d)" % s._prewarm_queue.size())
	_wait_prewarm(s)
	for variant in 4:
		var step_pan := -0.05 if variant % 2 == 0 else 0.05
		var step_key: String = Sound._cue_key("step:sprint:%s:%d" % [SurfaceSounds.SURFACES[4], variant], step_pan, 1.0)
		_expect(s._cache.has(step_key), "batched step %s was not adopted" % step_key)
		if s._cache.has(step_key):
			_expect(hash((s._cache[step_key] as AudioStreamWAV).data) == hash(Sound._render_cue_uncached("step:sprint:%s:%d" % [SurfaceSounds.SURFACES[4], variant], step_pan, 1.0).data),
				"batched step %s differs from the main-thread render" % step_key)
	s._prewarm_next_msec = 0
	s._prewarm_step()
	_expect((s._prewarm_job["keys"] as Array).size() == 4 and s._prewarm_queue.size() == 1, "the second step group was not four keys")
	_wait_prewarm(s)
	s._prewarm_next_msec = 0
	s._prewarm_step()
	_expect((s._prewarm_job["keys"] as Array).size() == 1 and s._prewarm_queue.is_empty(), "a step group was batched with a heartbeat")
	_wait_prewarm(s)
	# a batch never exceeds PREWARM_BATCH_MAX, even for one group
	s._prewarm_queue = []
	for index in range(1, 11):
		s._prewarm_queue.append(["heartbeat", 0.0, index * 0.05])
	s._prewarm_armed = true
	s._prewarm_next_msec = 0
	s._prewarm_step()
	_expect((s._prewarm_job["keys"] as Array).size() == Sound.PREWARM_BATCH_MAX and s._prewarm_queue.size() == 10 - Sound.PREWARM_BATCH_MAX,
		"a batch of heartbeats was not capped at PREWARM_BATCH_MAX")
	_wait_prewarm(s)
	# a half-cached group renders only what is missing
	var present: String = Sound._cue_key("step:walk:wood:0", -0.05, 1.0)
	s._cache[present] = AudioStreamWAV.new()
	s._prewarm_queue = Sound._step_prewarm_specs("walk").slice(4, 8)
	s._prewarm_next_msec = 0
	s._prewarm_step()
	_expect((s._prewarm_job["keys"] as Array).size() == 3 and not (s._prewarm_job["keys"] as Array).has(present), "an already cached variant was rendered again")
	_wait_prewarm(s)
	s.free()
	# a prewarmed key is all footstep() touches: the cache does not grow and nothing is rendered
	var saved_overrides: Dictionary = Sound._cue_overrides
	var saved_index: int = Sound._footstep_index
	var saved_muted := Sound.muted
	Sound._cue_overrides = {}
	Sound.muted = false
	for surface in ["metal", "water"]:
		for variant in 4:
			var step_pan := -0.05 if variant % 2 == 0 else 0.05
			Sound.render_cue("step:sprint:%s:%d" % [surface, variant], step_pan, 1.0)   # what the prewarm adopts
	var cached_before: int = Sound._cache.size()
	for _repeat in 8:
		Sound._last_footstep_usec = -2000000
		Sound.footstep("sprint", "metal", 6.25)
		Sound._last_footstep_usec = -2000000
		Sound.footstep("sprint", "water", 6.25)
	_expect(Sound._cache.size() == cached_before, "footstep() rendered a step that the prewarm had cached (%d new keys)" % (Sound._cache.size() - cached_before))
	Sound._cue_overrides = saved_overrides
	Sound._footstep_index = saved_index
	Sound.muted = saved_muted
	print("  steps      96 step keys render the same on workers; prewarm jobs batch one step's 4 variants, capped at %d; no render on a cached step" % Sound.PREWARM_BATCH_MAX)


func _wait_prewarm(s: Node) -> void:
	var waited := 0
	while not s._prewarm_job.is_empty() and waited < 10000:
		OS.delay_msec(5)
		waited += 5
		s._prewarm_step()


## T5: hunter and teammate steps play one cached render scaled by volume_db: a whole approach (every distance and every
## pan) fills a handful of keys instead of one render per step, and the quiet end of it is the loud end's render turned down.
func _check_scaled_steps() -> void:
	var saved_overrides: Dictionary = Sound._cue_overrides
	var saved_muted := Sound.muted
	Sound._cue_overrides = {}
	Sound.muted = false
	var before: Dictionary = Sound._cache.duplicate()
	for step in 200:
		var distance := 9.0 * (1.0 - step / 200.0)
		var volume := .09 * (1.0 - distance / 9.0)
		var pan := clampf((step % 41 - 20) / 20.0, -1.0, 1.0)
		Sound.hunter_footstep(pan, volume)
		Sound.hunter_footstep(pan, volume, "metal")
		Sound.remote_player_footstep("sprint", pan, .045 * (1.0 - distance / 12.0))
		Sound.remote_player_footstep("walk", pan, .045 * (1.0 - distance / 12.0))
	var added := 0
	for key in Sound._cache:
		if not before.has(key):
			added += 1
			var parts := String(key).split("|")
			_expect(parts.size() == 3 and absf(float(parts[1]) / Sound.SCALED_PAN_STEP - roundf(float(parts[1]) / Sound.SCALED_PAN_STEP)) < 0.001 and float(parts[2]) == 1.0,
				"a scaled step cached a key that is not (pan on the %.2f grid, intensity 1): %s" % [Sound.SCALED_PAN_STEP, key])
	# 9 pans x (hunter_footstep + 4 metal variants + sprint + walk) at most; before this it was ~35 intensities x the pans per cue
	_expect(added <= 9 * 7, "a hunter approach rendered %d new cues (expected at most %d)" % [added, 9 * 7])
	_expect(Sound.last_cue.begins_with("teammate_footstep"), "scaled steps no longer record their cue (%s)" % Sound.last_cue)
	# loudness: the scaled path is the old per-intensity render turned down (generic hunter step: pure thumps, so exact)
	var loud := Sound.render_cue("hunter_footstep", 0.0, 1.0).data
	for gain in [0.1, 0.35, 0.8, 1.6]:
		var old := Sound._render_cue_uncached("hunter_footstep", 0.0, gain).data
		var worst := 0.0
		for offset in range(0, loud.size() - 1, 2):
			worst = maxf(worst, absf(float(loud.decode_s16(offset)) * gain - float(old.decode_s16(offset))))
		_expect(loud.size() == old.size() and worst <= 2.0, "hunter_footstep scaled by %.2f is %.1f LSB from the per-intensity render" % [gain, worst])
	# surface steps carry noise whose seed follows the key, so compare energy, not samples
	var metal_loud := _energy(Sound._render_cue_uncached("step:hunter:metal:1", 0.0, 1.0).data)
	var metal_old := _energy(Sound._render_cue_uncached("step:hunter:metal:1", 0.0, 0.5).data)
	_expect(metal_old > 0.0 and absf(metal_loud * 0.5 / metal_old - 1.0) < 0.2, "a surface hunter step at half volume is not half the energy (%.2f)" % (metal_loud * 0.5 / maxf(metal_old, 1.0)))
	Sound._cue_overrides = saved_overrides
	Sound.muted = saved_muted
	print("  scaled     hunter/teammate steps: %d cached cues for a 200-step approach over 41 pans; volume carries the loudness" % added)


func _energy(data: PackedByteArray) -> float:
	var energy := 0.0
	for offset in range(0, data.size() - 1, 2):
		energy += absf(float(data.decode_s16(offset)))
	return energy


func _channel_energy(data: PackedByteArray, channel: int) -> float:
	var energy := 0.0
	for offset in range(channel * 2, data.size() - 1, 4):
		energy += absf(float(data.decode_s16(offset)))
	return energy
