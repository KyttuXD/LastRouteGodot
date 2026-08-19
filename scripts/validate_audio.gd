extends RefCounted

## Headless checks for the procedural SoundSystem port. A dummy audio driver
## cannot tell us what a cue sounds like, but it can prove every shipping cue
## renders valid stereo PCM, direction changes channel energy, debounce gates
## repeated footsteps, UI buttons are wired, and Office emits named events.

var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


func run(host: Node) -> int:
	_expect(AudioServer.get_bus_index("SFX") >= 0, "SFX audio bus is missing")
	_expect(AudioServer.get_bus_index("UI") >= 0, "UI audio bus is missing")

	var cues := ["collect", "recharge", "menu", "music_box", "alert", "chase_start", "taser",
		"door_open", "door_close", "door_breach", "interaction_fail", "tool_break",
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

	var simulation := OfficeSimulation.new("audio-check", {
		"default_ai": 0, "jumpscares": true,
	})
	var office_events: Array = []
	simulation.audio_cue.connect(func(cue: String, pan: float, intensity: float) -> void:
		office_events.append({"cue": cue, "pan": pan, "intensity": intensity}))
	simulation.toggle_control("cameras")
	_expect(not office_events.is_empty() and office_events[-1]["cue"] == "camera",
		"raising the Office monitor emitted no camera cue")
	office_events.clear()
	simulation.threats["crimson"]["progress"] = 0.99
	simulation.threats["crimson"]["timer"] = 0.0
	simulation._update_crimson(0.1)
	_expect(office_events.any(func(event: Dictionary) -> bool:
		return event["cue"] == "crimson_door" and absf(float(event["pan"])) > .8),
		"Crimson's door deadline emitted no directional cue")
	print("  wiring     UI, movement debounce, Thessine sync, and Office hooks are live")
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
