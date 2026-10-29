class_name BotChat
extends RefCounted

## Playtest bots talk in the real room chat (RemotePlayers.send_chat_payload), so every client's TTS reads them aloud with that
## bot's own stable voice (RoomChat.voice_for(peer id)) and the chat's moderation, bubbles and subtitles all get exercised.
## Short, in-tone lines from a small table on things the bot noticed; a per-bot cooldown with jitter keeps a room of bots from
## being a wall of noise, well inside the chat's own limit (3 lines per 10 s, 80 characters).
##   mode "off": silent · "quiet" (default): rare lines on events and replies · "on": also idle banter, more often
## Bots also talk to each other (KT 2026-10-28): a hunter callout carries where it was (the chat's "target"), and the other bots
## keep away from there; "I'll take the east relay" leaves that relay to the speaker; "I'm down" gets a "coming" from a bot with a
## Revive Kit (which then goes to revive, LastRouteBot._revive_goal). Replies never get replies, so bots cannot chain.

const LINES := {
	"hunter": ["Hunter near the {where}! Steer clear.", "Hunter {dir} of me, by the {where}.", "Heads up, hunter at the {where}.",
		"One's hunting near the {where}. Avoid it."],
	"caught": ["I'm down! Need a revive!", "Got me... anyone have a kit?", "Down by the {where}. Revive me?"],
	"claim": ["I'll take the {dir} relay.", "Got the relay to the {dir}.", "Heading for the {dir} relay."],
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
	"reply_ack": ["Got it, staying away.", "Thanks, going round.", "Copy. Avoiding it."],
	"reply_claim": ["Okay, I'll look elsewhere.", "Fine, it's yours."],
	"reply_coming": ["I've got a kit, coming!", "Hold on, bringing a kit.", "On my way with a kit."],
}
const KEYWORDS := {"reply_hello": ["hi", "hey", "hello", "yo", "sup"], "reply_where": ["where"],
	"reply_help": ["help", "save", "come"], "reply_bot": ["bot", "bots", "robot"]}
## events worth saying in quiet mode too (and the share of them sent on the TEAM radio)
const EVENTS := ["hunter", "caught", "relay", "level_down", "level_up", "claim"]
## what other bots read from a line (its preset) and the line kind it carries
const PRESETS := {"hunter": "bot_hunter", "caught": "bot_help", "claim": "bot_relay"}
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
var _adapter: Object
var _claimed_key := ""
var _target = null               # Vector2 for the line being said (hunter / relay / own spot)
var heard := 0                   # bot lines acted on


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
	_adapter = adapter
	if not _hooked and remotes.has_signal("chat_message"):
		_hooked = true
		remotes.connect("chat_message", _on_message)
	var kind := ""
	var level := int(obs.get("world", {}).get("level", 0))
	if _last_level != 999 and level != _last_level:
		kind = "level_down" if level < _last_level else "level_up"
	_last_level = level
	var threat := false
	var seen_at = null
	for h in obs.get("hunters", []):
		if String(h.get("state", "")) == "CHASE" and float(h.get("dist", 99.0)) < 15.0 and bool(h.get("los", false)):
			threat = true
			seen_at = Vector2(float(h["pos"][0]), float(h["pos"][1]))
	_target = null
	if threat and not _threat_seen:
		kind = "hunter"
		_target = seen_at
	_threat_seen = threat
	var over := bool(obs.get("run", {}).get("over", false))
	if over and not _was_over:
		kind = "caught"
		_target = _here(obs)
	_was_over = over
	var relays := int(obs.get("run", {}).get("relays", 0))
	if _relays >= 0 and relays > _relays:
		kind = "relay"
	_relays = relays
	# a relay this bot is heading for, said once: the others leave it alone
	var mine: Dictionary = adapter.call("current_relay") if adapter != null and adapter.has_method("current_relay") else {}
	if kind.is_empty() and not mine.is_empty() and String(mine.get("key", "")) != _claimed_key:
		_claimed_key = String(mine.get("key", ""))
		kind = "claim"
		_target = Vector2(float(mine["cell"].x) + .5, float(mine["cell"].y) + .5)
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
	var text := _fill(String(pool[rng.randi_range(0, pool.size() - 1)]), obs).substr(0, 80)
	# callouts and claims go to the whole team: the other bots act on them wherever they are
	var channel := "team" if PRESETS.has(kind) or (kind in EVENTS and rng.randf() < TEAM_SHARE) else "nearby"
	var payload := {"text": text, "channel": channel, "preset": PRESETS.get(kind, "bot_reply" if kind.begins_with("reply") else "bot")}
	if _target is Vector2:
		payload["target"] = _target
	var sent := bool(remotes.call("send_chat_payload", payload))
	if sent:
		var chat: Object = scene.get("_room_chat")
		if chat != null and chat.has_method("_make_speech_noise"):
			chat.call("_make_speech_noise", text)   # a spoken line is heard by the hunters, as for a player
	_next_ok = t + _cooldown()
	said.append({"t": snappedf(t, .1), "kind": kind, "text": text, "channel": channel, "sent": sent})
	if said.size() > MAX_LOG:
		said.pop_front()


## {where}: this storey's region; {dir}: the compass direction from the speaker to the line's target.
func _fill(text: String, obs: Dictionary) -> String:
	var region := String(obs.get("world", {}).get("region", "")).replace("_", " ").strip_edges()
	text = text.replace("{where}", region if not region.is_empty() else "stairs")
	var dir := "north"
	if _target is Vector2:
		var d: Vector2 = (_target as Vector2) - _here(obs)
		if d.length() > 1.0:
			dir = ["east", "south", "west", "north"][posmod(roundi(atan2(d.y, d.x) / (PI / 2.0)), 4)]   # -z is north
	return text.replace("{dir}", dir)


func _here(obs: Dictionary) -> Vector2:
	var pos: Array = obs.get("player", {}).get("pos", [0, 0, 0])
	return Vector2(float(pos[0]), float(pos[2]))


## A line from anyone else in the room. Bot lines (their preset) are acted on: a hunter callout is avoided, a relay claim is left
## to its speaker, a call for a revive gets a "coming" from a bot carrying a kit. People's lines get keyword replies.
## A reply goes out from about one bot in the room (chance 1 / room size), and replies are never answered.
func _on_message(peer_id: int, _display_name: String, payload: Dictionary) -> void:
	if peer_id == (Engine.get_main_loop() as SceneTree).get_multiplayer().get_unique_id():
		return
	var preset := String(payload.get("preset", ""))
	var target = payload.get("target")
	var one_of_us := rng.randf() < 1.0 / float(maxi(RoomState.peers.size() - 1, 1))
	match preset:
		"bot_hunter":
			if target is Vector2 and _adapter != null and _adapter.has_method("avoid"):
				_adapter.call("avoid", target)
				heard += 1
			if one_of_us:
				_pending_reply = "reply_ack"
		"bot_relay":
			if target is Vector2 and _adapter != null and _adapter.has_method("relay_claimed"):
				_adapter.call("relay_claimed", Vector2i(floori((target as Vector2).x), floori((target as Vector2).y)))
				heard += 1
			if one_of_us and rng.randf() < .3:
				_pending_reply = "reply_claim"
		"bot_help":
			heard += 1
			var scene := (Engine.get_main_loop() as SceneTree).current_scene
			var player: Object = scene.get("player") if scene != null else null
			if player != null and player.has_method("item_count") and int(player.call("item_count", "revive_kit")) > 0:
				_pending_reply = "reply_coming"   # the brain goes to revive on its own (downed marker)
		"bot_reply":
			pass
		_:
			_on_chat(peer_id, _display_name, String(payload.get("text", "")))


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
