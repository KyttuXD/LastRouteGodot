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
	var screen := (load("res://scenes/route_loading.tscn") as PackedScene).instantiate() as RouteLoadingScreen
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

	Sound.reset_test_counters()
	_expect(Sound.footstep("walk"), "first footstep was swallowed")
	_expect(not Sound.footstep("walk"), "same-frame footsteps bypassed debounce")
	_expect(int(Sound.play_counts.get("footstep_walk", 0)) == 1,
		"footstep debounce recorded more than one cue")
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
	var route: Node = load("res://scenes/main_3d.tscn").instantiate()
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
	route._hunter_step_elapsed = .30
	Sound.reset_test_counters()
	route._update_local_audio(.01)
	_expect(int(Sound.play_counts.get("hunter_footstep", 0)) == 1,
		"a moving non-special-cased route hunter produced no heavy footstep")
	route.queue_free()
	await host.get_tree().process_frame

	print("  wiring     UI, movement debounce, and Thessine sync are live")
	Sound.stop_all()
	await host.get_tree().process_frame

	if _failures == 0:
		print("audio OK")
	return _failures


func _channel_energy(data: PackedByteArray, channel: int) -> float:
	var energy := 0.0
	for offset in range(channel * 2, data.size() - 1, 4):
		energy += absf(float(data.decode_s16(offset)))
	return energy
