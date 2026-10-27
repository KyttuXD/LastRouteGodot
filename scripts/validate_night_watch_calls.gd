extends RefCounted

## Zellia's call: the 3D table equals the 2D game's (every mode, level, ring time and line, compared with the golden file extracted from the 2D
## source by tools/nightwatch/extract_2d_calls.mjs), the 2D timings are the 3D ones, the call script plays exactly as the 2D createCall does (rings at `at`,
## "Incoming call…" for 2.2 s, a word every 250 ms, talk blips on odd word counts, each line stays 1.8 s + 0.38 s per word, the box closes after the last line, Mute
## ends it), and the call box sits where the 2D box does (centred, 60% wide, its bottom at 10% of the height) without covering the HUD, at both test resolutions.

const GOLDEN := "res://scripts/data/night_watch_2d_calls.json"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var golden = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	_expect(golden is Dictionary, "the golden 2D call file is missing or not JSON")
	if not (golden is Dictionary):
		return _failures
	var timing: Dictionary = golden["timing"]
	_expect(int(timing["ring"]) == NightWatchCallsData.INCOMING_MS and int(timing["word"]) == NightWatchCallsData.WORD_MS \
		and int(timing["base"]) == NightWatchCallsData.LINE_BASE_MS and int(timing["perWord"]) == NightWatchCallsData.LINE_WORD_MS, "the call timings differ from callbox.js")
	var calls: Dictionary = golden["calls"]
	var lines_total := 0
	for mode in calls:
		var table: Dictionary = NightWatchCallsData.CALLS.get(mode, {})
		_expect(table.size() == (calls[mode] as Dictionary).size(), "%s has %d call levels, the 2D game has %d" % [mode, table.size(), (calls[mode] as Dictionary).size()])
		for level in calls[mode]:
			var want: Dictionary = calls[mode][level]
			var have: Dictionary = NightWatchCallsData.for_level(mode, int(level))
			_expect(not have.is_empty(), "%s level %s has no call" % [mode, level])
			if have.is_empty():
				continue
			_expect(float(have["at"]) == float(want["at"]), "%s level %s rings at %s, not %s" % [mode, level, have["at"], want["at"]])
			_expect(have["lines"] == want["lines"], "%s level %s: the lines differ from the 2D game's" % [mode, level])
			lines_total += (want["lines"] as Array).size()
	_expect(NightWatchCallsData.CALLS.size() == calls.size(), "the 3D table has modes the 2D game does not")
	_expect(NightWatchCallsData.for_level("mixed", 1).is_empty(), "Mixed Shift must have no call")
	_expect(NightWatchCallScript.for_level("classic", 7).done == false and NightWatchCallScript.for_level("mixed", 1).done, "the quiet-night script is not done at once")
	# the script plays as createCall: step it at 50 ms and check the moments
	var s := NightWatchCallScript.for_level("classic", 2)
	var lines: Array = NightWatchCallsData.for_level("classic", 2)["lines"]
	var at_ms := 5000.0
	var t := 0.0
	var rang_at := -1.0
	var talks := 0
	var closed_at := -1.0
	var first_text_at := -1.0
	while t < 60000.0 and closed_at < 0.0:
		for e in s.update(t, 50.0):
			if e == "ring":
				rang_at = t
			elif e == "talk":
				talks += 1
			elif e == "close":
				closed_at = t
		if s.open and s.text == NightWatchCallsData.INCOMING_TEXT and first_text_at < 0.0:
			first_text_at = t
		t += 50.0
	var expect_close := at_ms + NightWatchCallsData.INCOMING_MS
	var expect_talks := 0
	for l in lines:
		var words := String(l).split(" ").size()
		expect_close += NightWatchCallsData.LINE_BASE_MS + words * NightWatchCallsData.LINE_WORD_MS
		expect_talks += (words + 1) / 2
	_expect(absf(rang_at - at_ms) <= 50.0, "the call rang at %.0f ms, not %.0f" % [rang_at, at_ms])
	_expect(first_text_at >= 0.0 and first_text_at <= at_ms + 50.0, "'Incoming call…' did not come up with the ring")
	_expect(absf(closed_at - expect_close) <= 100.0, "the call closed at %.0f ms, the 2D timing gives %.0f" % [closed_at, expect_close])
	_expect(talks == expect_talks, "%d talk blips, the 2D rule gives %d" % [talks, expect_talks])
	# a line types out word by word: after 750 ms of a line, three words show
	var s2 := NightWatchCallScript.new(["one two three four five"], 0.0)
	s2.update(0.0, 0.0)
	s2.update(0.0, float(NightWatchCallsData.INCOMING_MS))
	s2.update(0.0, 750.0)
	_expect(s2.text == "one two three", "750 ms into a line should show 3 words, shows '%s'" % s2.text)
	# Mute ends the call and it does not come back
	var s3 := NightWatchCallScript.new(["a b c"], 0.0)
	s3.update(0.0, 10.0)
	_expect(s3.open and s3.mute() and not s3.open and s3.done, "Mute did not end the call")
	_expect(s3.update(9000.0, 100.0).is_empty() and not s3.open, "the call came back after Mute")
	# the box: where the 2D box sits, at both test resolutions, clear of the HUD
	for size in [Vector2i(480, 270), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		var vp := SubViewport.new()
		vp.size = size
		vp.disable_3d = true
		host.add_child(vp)
		var hud := NightWatchHud.new()
		vp.add_child(hud)
		await host.get_tree().process_frame
		var longest := ""
		for mode in NightWatchCallsData.CALLS:
			for lvl in NightWatchCallsData.CALLS[mode]:
				for l in NightWatchCallsData.CALLS[mode][lvl]["lines"]:
					if String(l).length() > longest.length():
						longest = String(l)
		hud.show_call(longest)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var panel := hud.call_panel
		var r := panel.get_global_rect()
		var screen := Rect2(Vector2.ZERO, Vector2(size))
		_expect(screen.encloses(r), "%s: the call box leaves the screen: %s" % [str(size), str(r)])
		_expect(absf((r.position.x + r.size.x * 0.5) / size.x - 0.5) < 0.01, "%s: the call box is not centred" % str(size))
		_expect(absf(r.size.x / size.x - 0.6) < 0.01, "%s: the call box is %.0f%% wide, the 2D box is 60%%" % [str(size), r.size.x / size.x * 100.0])
		_expect(absf(1.0 - (r.position.y + r.size.y) / size.y - 0.1) < 0.01, "%s: the call box bottom is not at 10%% of the height" % str(size))
		if size.x == 480:
			for n in [hud.night_label, hud.power_label, hud.usage_label, hud.clock_label, hud.pause_button]:
				_expect(not r.intersects((n as Control).get_global_rect()), "%s: the call box covers %s" % [str(size), n.name])
		_expect(not hud.hint_label.visible, "the key hint stays up under the call box")
		_expect(hud.call_panel.find_child("CallName", true, false) != null and (hud.call_panel.find_child("CallName", true, false) as Label).text.replace(" ", "") == "ZELLIA", "the call box has no ZELLIA header")
		_expect(hud.call_mute != null and hud.call_mute.text.begins_with("Mute"), "the call box has no Mute button")
		vp.queue_free()
		await host.get_tree().process_frame
	# a scene that only calls queue_call (never update_call) still gets its call, on real time
	var lone_vp := SubViewport.new()
	lone_vp.size = Vector2i(480, 270)
	lone_vp.disable_3d = true
	host.add_child(lone_vp)
	var lone := NightWatchHud.new()
	lone_vp.add_child(lone)
	await host.get_tree().process_frame
	lone.queue_call(["one two three four"])
	for i in 30:
		lone._process(0.1)
	_expect(lone.call_script.open and lone.call_label.text.length() > 0 and lone.call_panel.visible, "a scene that only queues a call never got it (the HUD must run it on real time)")
	for i in 120:
		lone._process(0.1)
	_expect(lone.call_script.done and not lone.call_panel.visible, "the lone call did not finish and close")
	lone_vp.queue_free()
	if _failures == 0:
		print("  night_watch_calls  %d lines in %d modes equal the 2D game's; timings, typing, Mute and the box position match" % [lines_total, calls.size()])
	return _failures
