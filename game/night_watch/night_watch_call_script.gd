class_name NightWatchCallScript
extends RefCounted

## Zellia's call as a state machine, ported line for line from the 2D game's createCall (its call box): she rings `at` seconds into the
## night ("Incoming call…" for 2.2 s with the ring), then each line is typed out word by word (one more word every 250 ms, a talk blip on
## every second word), a line stays up 1.8 s plus 0.38 s per word, and when the last line is done the box closes. Mute ends the call.
## Pure: the HUD feeds it the shift clock and draws `text` while `open`. Events returned from update(): "ring", "talk", "open", "close".

var open := false
var done := true
var text := ""
var line := -1
var muted := false
var _lines: Array = []
var _at_ms := 0.0
var _active := false
var _t := 0.0
var _dur := 0.0
var _words: PackedStringArray = []
var _shown := 0


func _init(lines: Array = [], at_seconds := 6.0) -> void:
	_lines = lines
	_at_ms = at_seconds * 1000.0
	done = lines.is_empty()


static func for_level(mode_id: String, level: int) -> NightWatchCallScript:
	var entry := NightWatchCallsData.for_level(mode_id, level)
	if entry.is_empty():
		return NightWatchCallScript.new([], 6.0)
	return NightWatchCallScript.new(entry["lines"], float(entry["at"]))


func update(elapsed_ms: float, dt_ms: float) -> Array:
	var events := []
	if done:
		return events
	if not _active:
		if elapsed_ms < _at_ms:
			return events
		_active = true
		_t = -float(NightWatchCallsData.INCOMING_MS)
		text = NightWatchCallsData.INCOMING_TEXT
		open = true
		events.append("open")
		events.append("ring")
	_t += dt_ms
	if _t < 0.0:
		return events
	if line == -1 or _t >= _dur:
		line += 1
		_t = 0.0
		_shown = 0
		if line >= _lines.size():
			done = true
			open = false
			events.append("close")
			return events
		_words = String(_lines[line]).split(" ")
		_dur = NightWatchCallsData.LINE_BASE_MS + _words.size() * NightWatchCallsData.LINE_WORD_MS
	var want := mini(_words.size(), int(floor(_t / float(NightWatchCallsData.WORD_MS))))
	if want != _shown:
		_shown = want
		text = " ".join(_words.slice(0, want))
		if want % 2 == 1:
			events.append("talk")
	return events


func mute() -> bool:
	if _active and not done:
		done = true
		open = false
		muted = true
		return true
	return false
