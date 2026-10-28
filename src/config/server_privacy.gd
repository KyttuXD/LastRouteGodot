class_name ServerPrivacy
extends RefCounted

## Players never see where the server is: no host name, IP address, port or URL in the HUD, menus, pause, staging or
## connection errors. scrub() replaces them with "THE SERVER"; a connection failure that named an address becomes the friendly
## "CAN'T REACH THE SERVER". Admins read the server and channel in the admin/debug readout only (debug_line()).

const FRIENDLY_UNREACHABLE := "CAN'T REACH THE SERVER"
const _FAILURE_WORDS := ["CONNECT", "UNREACH", "TIMEOUT", "TIMED OUT", "REFUSED", "RESOLVE", "UNAVAILABLE", "FAILED", "LOST"]

static var _patterns: Array = []


static func _compiled() -> Array:
	if _patterns.is_empty():
		for source in [
			"(?i)\\b(?:https?|wss?|enet)://[^\\s/]+(?:/\\S*)?",      # URLs
			"(?i)(?<!version )(?<![v\\d.])\\b(?:\\d{1,3}\\.){3}\\d{1,3}(?::\\d{1,5})?\\b",   # IPv4[:port] (not "VERSION 0.0.1.0")
			"(?i)\\[?[0-9a-f]{0,4}(?::[0-9a-f]{0,4}){2,7}\\]?(?::\\d{1,5})?",  # IPv6
			"(?i)\\b[a-z0-9-]+(?:\\.[a-z0-9-]+)*\\.(?:org|com|net|io|dev|app|local|lan|cloud)(?::\\d{1,5})?\\b",  # host names
			"(?i)\\blocalhost(?::\\d{1,5})?\\b",
			"(?<![\\w.]):\\d{2,5}\\b",                                 # a bare :port
		]:
			_patterns.append(RegEx.create_from_string(source))
	return _patterns


## True when `text` names a host, address, URL or port.
static func leaks(text: String) -> bool:
	for regex in _compiled():
		if (regex as RegEx).search(text) != null:
			return true
	return false


## `text` safe for players: addresses become THE SERVER; a failure that named one becomes CAN'T REACH THE SERVER.
static func scrub(text: String) -> String:
	if not leaks(text):
		return text
	var upper := text.to_upper()
	for word in _FAILURE_WORDS:
		if upper.contains(word):
			return FRIENDLY_UNREACHABLE
	var out := text
	for regex in _compiled():
		out = (regex as RegEx).sub(out, "THE SERVER", true)
	return out


## Admin/debug readout only: which server and update channel this client talks to.
static func debug_line() -> String:
	return "SERVER %s // CHANNEL %s" % [Backend.base_url.trim_prefix("http://").trim_prefix("https://"), Build.update_channel().to_upper()]
