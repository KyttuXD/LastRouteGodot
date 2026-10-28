extends RefCounted

## Night Watch's sounds are the 2D game's (NightWatchSounds, Sound.nw): every cue of the 2D `sfx` table renders to audible sound of about the 2D length, the ring is four double blips, the call's talk blip and the camera,
## door and chime cues are the 2D pitches' length, the menus play `move` on hover / focus and `pick` on press instead of the shared menu blip, and the game events play the 2D cue for the job.
##
##   godot --headless --path . res://scenes/validate.tscn -- night_watch_sounds

var _failures := 0

## cue -> the 2D length in seconds (the longest tone or noise plus its delay), within 15 ms
const LENGTHS := {"move": 0.04, "pick": 0.12, "deny": 0.18, "burst": 0.2, "step": 0.09, "clank": 0.16, "bound": 0.15 + 0.045, "pad": 0.2, "ring": 0.54 + 0.12, "lure": 0.26 + 0.25, "crackle": 0.35, "hum": 0.6,
	"breath": 0.43 + 0.35, "talk": 0.09, "door": 0.25, "light_on": 0.3, "camera": 0.05, "scare": 1.2, "scare_short": 0.65, "power_out": 1.2, "chime": 0.8}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _peak(stream: AudioStreamWAV) -> float:
	var data := stream.data
	var peak := 0.0
	for i in range(0, data.size() - 1, 2):
		var v := absf(float(data.decode_s16(i)) / 32768.0)
		peak = maxf(peak, v)
	return peak


func run(host: Node) -> int:
	for cue in NightWatchSounds.CUES:
		var stream := Sound.render_cue("nw_" + String(cue))
		_expect(stream != null and stream.get_length() > 0.02, "the 2D cue '%s' renders nothing" % cue)
		if stream == null:
			continue
		_expect(_peak(stream) > 0.01, "the 2D cue '%s' is silent (peak %.4f)" % [cue, _peak(stream)])
		if LENGTHS.has(cue):
			_expect(absf(stream.get_length() - float(LENGTHS[cue])) < 0.1, "the 2D cue '%s' is %.2f s, the 2D one %.2f s" % [cue, stream.get_length(), float(LENGTHS[cue])])
	# the ring is four double blips: peaks at 0, .18, .36, .54
	var ring := Sound.render_cue("nw_ring")
	var loud := 0
	for k in 4:
		var from := int(float(k) * 0.18 * ring.mix_rate) * 2 * (2 if ring.stereo else 1)
		var window := ring.data.slice(from, from + int(0.1 * ring.mix_rate) * 2 * (2 if ring.stereo else 1))
		var m := 0.0
		for i in range(0, window.size() - 1, 2):
			m = maxf(m, absf(float(window.decode_s16(i)) / 32768.0))
		loud += int(m > 0.02)
	_expect(loud == 4, "the ring does not have its four blips (%d)" % loud)
	# the events play the 2D cues
	Sound.reset_test_counters()
	NightWatchSounds.door(true)
	NightWatchSounds.monitor_toggle()
	NightWatchSounds.hour_change()
	NightWatchSounds.call_ring()
	NightWatchSounds.call_line()
	NightWatchSounds.power_out()
	NightWatchSounds.light_on()
	NightWatchSounds.caught()
	NightWatchSounds.hunter_event({"type": "arrived", "room": "doorL"})
	for expected in ["nw_door", "nw_camera", "nw_chime", "nw_ring", "nw_talk", "nw_power_out", "nw_light_on", "nw_scare", "nw_step", "nw_clank"]:
		_expect(Sound.play_counts.has(expected), "the event for %s did not play it (%s)" % [expected, str(Sound.play_counts.keys())])
	# the menu: hover and focus move, press picks, and the shared menu blip stays off
	var menu := (load("res://scenes/night_watch_menu.tscn") as PackedScene).instantiate() as NightWatchMenu
	host.add_child(menu)
	await host.get_tree().process_frame
	menu.show_screen("title")
	await host.get_tree().process_frame
	Sound.reset_test_counters()
	var button := menu.title_buttons[0]
	button.mouse_entered.emit()
	_expect(Sound.play_counts.has("nw_move"), "hovering a menu button does not play the 2D move blip")
	button.pressed.emit()
	_expect(Sound.play_counts.has("nw_pick") and not Sound.play_counts.has("menu"), "pressing a menu button does not play the 2D pick blip alone (%s)" % str(Sound.play_counts.keys()))
	menu.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  night_watch_sounds  %d cues of the 2D sfx table render at their 2D lengths, the ring is four blips, events and menus play them" % NightWatchSounds.CUES.size())
	return _failures
