class_name BotChat
extends RefCounted

## Playtest bots talk in the real room chat (RemotePlayers.send_chat_payload), so every client's TTS reads them aloud with that
## bot's own stable voice (RoomChat.voice_for(peer id)) and the chat's moderation, bubbles and subtitles all get exercised.
## Short, in-tone lines from a small table on things the bot noticed; a per-bot cooldown with jitter keeps a room of bots from
## being a wall of noise, well inside the chat's own limit (3 lines per 10 s, 80 characters).
##   mode "off": silent · "quiet" (default): rare lines on events and replies · "on": also idle banter, more often

const LINES := {
	"hunter": ["Hunter! Over here!", "Something's coming...", "I see one. Moving.", "Heads up, hunter close.", "Run, run, run!"],
	"caught": ["Got me... keep going!", "I'm down. Don't stop!", "Ugh. Caught.", "Avenge me!"],
	"relay": ["Relay's live!", "Got a relay.", "One more relay up.", "Relay done, moving on."],
	"level_down": ["Heading down.", "Going below. Wish me luck.", "Into the sewers."],
	"level_up": ["Going up.", "Climbing out.", "Back up top."],
	"light": ["Too dark here. Light on.", "Can't see a thing."],
	"banter": ["Anyone else hear that?", "This place gives me the creeps.", "Stay close, team.", "Quiet... too quiet.",
		"Who left the lights off?", "I'll check this way.", "Smells like old pipes down here.", "Keep your light handy."],
	"reply_hello": ["Hey!", "Hi there!", "Hello! Stay safe."],
	"reply_where": ["Somewhere near the relays.", "Follow the minimap dots.", "Over by the stairs, I think."],
	"reply_help": ["On my way!", "Hang on, coming!", "Hold tight."],
	"reply_bot": ["Beep boop. Just a tester.", "I'm a test bot, don't mind me.", "Just testing, carry on!"],
}
const KEYWORDS := {"reply_hello": ["hi", "hey", "hello", "yo", "sup"], "reply_where": ["where"],
	"reply_help": ["help", "save", "come"], "reply_bot": ["bot", "bots", "robot"]}
## events worth saying in quiet mode too (and the share of them sent on the TEAM radio)
const EVENTS := ["hunter", "caught", "relay", "level_down", "level_up"]
const TEAM_SHARE := .35
const MAX_LOG := 60

var mode := "quiet"
var rng := RandomNumberGenerator.new()
var said: Array = []
var _next_ok := 0.0          # seconds (clip time) before this bot may speak again
var _last_level := 999
var _threat_seen := false
var _was_over := false
var _relays := -1
var _dark := false
var _hooked := false
var _pending_reply := ""


func _init(p_mode: String, seed_value: int) -> void:
	mode = p_mode if p_mode in ["off", "quiet", "on"] else "quiet"
	rng.seed = seed_value
	_next_ok = rng.randf_range(8.0, 25.0)   # nobody speaks in the first seconds, and not all at once


func _cooldown() -> float:
	return rng.randf_range(20.0, 40.0) + rng.randf_range(0.0, 8.0) if mode == "on" else rng.randf_range(90.0, 180.0)


## Call every frame: notices events, answers chat, says at most one line when the cooldown allows.
func tick(scene: Node, obs: Dictionary, t: float, adapter: Object) -> void:
	if mode == "off" or scene == null:
		return
	var remotes: Object = scene.get("_remotes")
	if remotes == null:
		return
	if not _hooked and remotes.has_signal("chat_received"):
		_hooked = true
		remotes.connect("chat_received", _on_chat)
	var kind := ""
	var level := int(obs.get("world", {}).get("level", 0))
	if _last_level != 999 and level != _last_level:
		kind = "level_down" if level < _last_level else "level_up"
	_last_level = level
	var threat := false
	for h in obs.get("hunters", []):
		if String(h.get("state", "")) == "CHASE" and float(h.get("dist", 99.0)) < 15.0 and bool(h.get("los", false)):
			threat = true
	if threat and not _threat_seen:
		kind = "hunter"
	_threat_seen = threat
	var over := bool(obs.get("run", {}).get("over", false))
	if over and not _was_over:
		kind = "caught"
	_was_over = over
	var relays := int(obs.get("run", {}).get("relays", 0))
	if _relays >= 0 and relays > _relays:
		kind = "relay"
	_relays = relays
	var dark := bool(adapter.get("_dark")) if adapter != null and adapter.get("_dark") != null else false
	if dark and not _dark and kind.is_empty() and mode == "on":
		kind = "light"
	_dark = dark
	if not _pending_reply.is_empty():
		kind = _pending_reply
	_pending_reply = ""
	if kind.is_empty() and mode == "on" and t >= _next_ok + 30.0:
		kind = "banter"
	if kind.is_empty() or t < _next_ok or (mode == "quiet" and kind not in EVENTS and not kind.begins_with("reply")):
		return
	var pool: Array = LINES[kind]
	var text := String(pool[rng.randi_range(0, pool.size() - 1)]).substr(0, 80)
	var channel := "team" if kind in EVENTS and rng.randf() < TEAM_SHARE else "nearby"
	var sent := bool(remotes.call("send_chat_payload", {"text": text, "channel": channel}))
	if sent:
		var chat: Object = scene.get("_room_chat")
		if chat != null and chat.has_method("_make_speech_noise"):
			chat.call("_make_speech_noise", text)   # a spoken line is heard by the hunters, as for a player
	_next_ok = t + _cooldown()
	said.append({"t": snappedf(t, .1), "kind": kind, "text": text, "channel": channel, "sent": sent})
	if said.size() > MAX_LOG:
		said.pop_front()


## Another player's line: a keyword reply, by about one bot in the room (each answers with chance 1 / room size).
func _on_chat(peer_id: int, _display_name: String, message: String) -> void:
	if peer_id == (Engine.get_main_loop() as SceneTree).get_multiplayer().get_unique_id():
		return
	var words := message.to_lower()
	for key in KEYWORDS:
		for w in KEYWORDS[key]:
			if (" %s " % words).contains(" %s " % w) or words.begins_with(w + "!") or words.begins_with(w + "?"):
				if rng.randf() < 1.0 / float(maxi(RoomState.peers.size() - 1, 1)):
					_pending_reply = key
				return
