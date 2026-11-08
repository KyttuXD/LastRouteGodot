extends Node

const RELAY_TUNNEL_SCRIPT := preload("res://game/network/enet_relay_tunnel.gd")
const WS_PEER_SCRIPT := preload("res://game/network/ws_room_peer.gd")
const HOST_HANDOFF_SCRIPT := preload("res://game/network/host_handoff.gd")
## The persistent public route always uses the WebSocket relay, so web and native players share one route. (ENet/UDP
## cannot be used from a browser.)
const PUBLIC_ROUTE_USES_WS := true

## The room a session belongs to.
##
## Singleplayer is not a separate path here -- it is a room with one player in
## it, hosted locally, with no transport attached. That is the whole point of
## introducing this before there is any networking: every entry into the game
## already goes through a room, so adding multiplayer later means giving the
## room a transport rather than rewriting how runs start.
##
## Concretely, the things a run needs -- which mode, which seed, how big the
## map, how hard -- live on the room, not on whoever pressed the button. CREATE
## ROOM and JOIN ROOM fill the same fields; a joined room simply receives them
## from the host instead of `create_local`.
##
## Mirrors the web build's staging screen, including its vocabulary (route
## seed, signals, staging) and its offline rule: without a backend you get the
## modes that do not need anyone else.

signal changed
## A transport-level failure that takes a guest out of a room. The message is
## also kept in `status_message` so the staging scene can show it after the
## gameplay scene has been replaced.
signal connection_lost(reason: String)
## Deliberate host handoff: the handoff phase changed (HUD/staging read handoff_phase / status_message).
signal handoff_changed
## Successor only: a reconnecting runner proved its host-issued resume identity; its records move old -> new peer id.
## new_peer 0: the runner never came back within the rebind window and its peer-owned records are dropped.
signal handoff_peer_rebound(old_peer: int, new_peer: int)
## A guest's view of the host went quiet (or came back). `message` is the line to show (a web host whose
## browser tab is hidden stops its game loop, so the whole room freezes).
signal host_stall_changed(stalled: bool, message: String)

## KYTTU: The City used to be Mode 1; it was archived (branch archive/city-20261027).
enum Mode { DEFAULT }
## SPRAWLING and CAVERNOUS merged into one top tier, IMMENSE -- two "big"
## steps that only differed by how big, with nothing else changing between
## them, was a choice that cost more attention at the lobby than it earned.
## Not named LARGE: that name was already taken by the tier below it, and
## renaming an existing tier just to free the word felt like a bigger change
## than "merge the two biggest" asked for.
enum Scale { SMALL, STANDARD, LARGE, IMMENSE, INFINITE }
## Nightmare is a step above Hard with a larger active lineup:
## GameConfig.STREAMED_HUNTER_BASE, HunterDirector's Nightmare team and HunterDirector.separate.
enum Difficulty { RELAXED, STANDARD, HARD, NIGHTMARE }

## The web build calls a slot a "signal" and seats sixteen of them.
const MAX_PLAYERS := 16

## Room codes are read aloud and typed in, so the alphabet drops the glyphs
## that get confused doing either: I/1, O/0, and lowercase entirely.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5

const MODE_LABELS := {
	Mode.DEFAULT: "DEFAULT",
}
## Rooms carry the id of the game they belong to so a code for one game is never joined from another.
const GAME_LAST_ROUTE := "last_route"
const MAIN_MENU_SCENE := "res://game/menus/main_menu.tscn"
const SCALE_LABELS := {
	Scale.SMALL: "SMALL", Scale.STANDARD: "STANDARD", Scale.LARGE: "LARGE",
	Scale.IMMENSE: "IMMENSE", Scale.INFINITE: "INFINITE",
}
## Normal staging is Infinite-only. STANDARD remains a protocol/debug fallback
## while streamed equivalents for every specialist hunter are completed.
const SELECTABLE_SCALE_LABELS := {
	Scale.INFINITE: "INFINITE",
}
const DIFFICULTY_LABELS := {
	Difficulty.RELAXED: "RELAXED", Difficulty.STANDARD: "STANDARD",
	Difficulty.HARD: "HARD", Difficulty.NIGHTMARE: "NIGHTMARE",
}
## One line per difficulty for the staging menu (tooltip and the line under the buttons); hunter abilities follow the difficulty alone.
## Tone only: never name a hunter ability here, players discover them in-game.
const DIFFICULTY_BLURBS := {
	Difficulty.RELAXED: "Gentler hunters and longer clocks. A good first run.",
	Difficulty.STANDARD: "The route as meant: hunters work together, so keep moving.",
	Difficulty.HARD: "Sharper hunters who search harder. Expect surprises.",
	Difficulty.NIGHTMARE: "Hunters at their worst. Trust nothing, keep your lamp lit.",
}
const DIFFICULTY_IDS := {
	Difficulty.RELAXED: "relaxed", Difficulty.STANDARD: "standard",
	Difficulty.HARD: "hard", Difficulty.NIGHTMARE: "nightmare",
}

## (Old pools, no longer used for new guests: GuestNames' "R-4821" style replaced them.) Anonymous room guests used a two-word callsign. Keeping the words as
## named pools makes FIRST/LAST coverage explicit and gives enough variety for
## a full 16-player room without the roster looking repeated.
const GUEST_FIRST_NAMES := [
	"QUIET", "LOW", "DIM", "COLD", "LONG", "THIN", "FAINT", "LAST",
	"PALE", "STILL", "DARK", "SOFT", "LOST", "HOLLOW", "SILENT", "DUSK",
	"ASH", "IRON", "GLASS", "NARROW", "FAR", "LONE", "RED", "GREY",
	"BROKEN", "HIDDEN", "EMPTY", "FROZEN", "WILD", "SLOW", "DEEP", "FINAL",
]
const GUEST_LAST_NAMES := [
	"EYE", "STEP", "LAMP", "WIRE", "ROUTE", "DOOR", "SIGNAL", "WATCH",
	"HALL", "BELL", "KEY", "THREAD", "WINDOW", "STATIC", "ECHO", "SHADOW",
	"GATE", "ROOM", "LIGHT", "TOWER", "PATH", "ARCHIVE", "RELAY", "MARK",
	"LOCK", "VAULT", "FRAME", "STAIR", "VOICE", "TRACK", "FIELD", "LINE",
]

## Which scene each mode opens. The route includes office-region rooms; the
## separate Office Mode shift was removed, so every room opens Last Route.
const MODE_SCENES := {
	Mode.DEFAULT: "res://game/main_3d.tscn",
}
const ROUTE_LOADING_SCENE := "res://game/boot/route_loading.tscn"

var code := ""
## The full route seed, shown on the staging screen and the in-run HUD so two
## players can confirm they are on the same route.
var seed_text := ""
## True while this room is the shared PUBLIC route: no lobby, server-owned state.
var public_route := false
var mode: Mode = Mode.DEFAULT
## Daytime room flag (the archived City used it; kept because HunterBrain.day_mode and the room sync still carry it).
var daytime := false
## This room's code is one of the owner's reserved private rooms (backend reserved_rooms.mjs): it never expires, only
## invited players (or the room password) may host or join it, and the owner restarts / ends / kicks through commands
## the directory hands to whoever hosts it (_on_reserved_commands).
var reserved := false
var map_scale: Scale = Scale.INFINITE
var difficulty: Difficulty = Difficulty.STANDARD
## Host only: AI teammates the host simulates in co-op (NpcTeammates, 0 up to COUNT_LIMIT, 0 = unlimited); guests just see them as runners.
var npc_teammates := 0   # set from the staging screen by admins and devs only (room_lobby _npc_scroller)
## Display names, host first. One entry while offline.
var players: PackedStringArray = []
## True after an ENet room handshake (or immediately for its host).
var online := false
var is_host := true
## Account name of the signed-in creator of an online room the directory hosts ("" otherwise). Set from the server.
var room_owner := ""
## A client socket exists but ENet has not completed its handshake yet.
var connecting := false
## True between the host starting a mode and returning the room to staging.
## Kept on the autoload so a player joining after the start can be sent straight
## into the live scene and catch up from the host's world snapshot.
var session_active := false
## Player-facing transport/lifecycle feedback which survives scene changes.
## Shown in menus and staging, so never with a server address (ServerPrivacy.scrub).
var status_message := "":
	set(value):
		status_message = ServerPrivacy.scrub(value)

## Peer id -> callsign. The host is always peer 1. Kept as a dictionary rather
## than a list so a player leaving removes the right row without the others
## shuffling under it.
var peers := {}

const DEFAULT_PORT := 8421
## The persistent server-owned route (see PublicRoute).
const PUBLIC_CODE := "PUBLC"
const CONNECTION_TIMEOUT_MSEC := 15_000
const WORLD_AUTH_TIMEOUT_SECONDS := 3.0
const RECONNECT_GRACE_MSEC := 8_000
const RECONNECT_LOOKUP_INTERVAL_MSEC := 1_000
## Loopback by default: this exists to test with two windows on one machine
## before there is anything to connect to.
const DEFAULT_ADDRESS := "127.0.0.1"

var _peer: MultiplayerPeer
## Private rooms use the WebSocket relay too (so browser players can join them). Web builds always do; native builds
## opt in with `-- --ws-rooms` (tests) until a setting exists.
var prefer_ws_rooms := false
var _host_port := DEFAULT_PORT
var _connect_started_msec := 0
var _world_auth_mismatch_peer: MultiplayerPeer
var _relay: Node
var _relay_status := ""
var _directory_status := ""
var reconnect_active := false
var _reconnect_deadline_msec := 0
var _reconnect_next_lookup_msec := 0
var _reconnect_request_in_flight := false
var _reconnect_generation := 0
var _reconnect_room_received := false
## Host: last successful _register_peer msec per joining peer (rate-limit 1/5s).
var _register_peer_at := {}
## CREATE ROOM uses this only until its first successful directory listing.
## If the primary service cannot accept the room, the staging screen remains
## usable as solo instead of waiting forever behind an online-only button.
var _primary_create_fallback_enabled := false
var _scene_transitions_suppressed_for_tests := false
## The host's pack announcement while this guest is still confirming or downloading packs ({} when none): the guest
## stays in staging until RoomPacks.adopt() succeeds.
var _packs_waiting := {}


# --- web build: a hidden tab stops the page's game loop (docs/WEB_BUILD.md) ---------------------------------
## Browsers stop requestAnimationFrame for a hidden tab, so a room hosted from a browser froze for every guest the
## moment its host switched tabs. Co-op rooms are hosted from the desktop app; the web build can still JOIN any
## web-compatible room, play solo, and take the public route. Guests are told when the host goes quiet.
const WEB_HOST_REFUSED := "THE BROWSER VERSION CANNOT HOST CO-OP // A HIDDEN TAB WOULD FREEZE YOUR GUESTS. HOST FROM THE DESKTOP APP, OR JOIN A ROOM"
const HOST_STALL_NOTICE := "HOST NOT RESPONDING // THEIR GAME MAY BE PAUSED (HIDDEN BROWSER TAB?). WAITING FOR THEM"
const HOST_HIDDEN_NOTICE := "HOST SWITCHED AWAY FROM THEIR BROWSER TAB // THE ROOM IS PAUSED UNTIL THEY COME BACK"
const HOST_BACK_NOTICE := "HOST IS BACK"
## The host says it is alive this often (tiny unreliable RPC) ...
const HOST_BEAT_SECONDS := 1.0
## ... and a guest that heard nothing from it for this long (in its OWN running time) warns.
const HOST_STALL_SECONDS := 4.0
var host_stalled := false
## Validation only: behave as the web build on a native/headless run.
var simulate_web_for_tests := false
var _host_beat_elapsed := 0.0
var _host_silent_seconds := 0.0
var _web_visibility_callback = null   # JavaScriptObject; kept so the browser listener is not freed


func is_web_build() -> bool:
	return OS.has_feature("web") or simulate_web_for_tests


## Why this client may not host, or "" when it may. Only the public route is still allowed from a browser: it hands
## the route to someone else when its holder stops answering, and refusing it would leave web players with no route.
func web_host_refusal(_for_public_route: bool) -> String:
	# Online rooms are hosted by the backend now, so no client hosts one, browser or not.
	return ""


func _tick_host_presence(delta: float) -> void:
	if not online or multiplayer.multiplayer_peer == null:
		_host_beat_elapsed = 0.0
		_host_silent_seconds = 0.0
		if host_stalled:
			_set_host_stalled(false, "")
		return
	if is_host:
		_host_beat_elapsed += delta
		if _host_beat_elapsed >= HOST_BEAT_SECONDS:
			_host_beat_elapsed = 0.0
			NetPeers.send_all(multiplayer, _receive_host_beat)
		return
	if connecting or reconnect_active:
		_host_silent_seconds = 0.0
		return
	# Clamped: when this guest's OWN tab was hidden, one huge delta on return must not read as a silent host.
	_host_silent_seconds += minf(delta, 0.25)
	if not host_stalled and _host_silent_seconds >= HOST_STALL_SECONDS:
		_set_host_stalled(true, HOST_STALL_NOTICE)


func _heard_from_host() -> void:
	_host_silent_seconds = 0.0
	if host_stalled:
		_set_host_stalled(false, HOST_BACK_NOTICE)


func _set_host_stalled(stalled: bool, message: String) -> void:
	var was_notice := status_message in [HOST_STALL_NOTICE, HOST_HIDDEN_NOTICE]
	host_stalled = stalled
	if stalled:
		status_message = message
	elif was_notice:
		status_message = ""
	host_stall_changed.emit(stalled, message)
	changed.emit()


@rpc("authority", "call_remote", "unreliable")
func _receive_host_beat() -> void:
	if not is_host:
		_heard_from_host()


## Sent by a host whose browser tab just hid or came back (best effort: the page may not get to send it).
@rpc("authority", "call_remote", "reliable")
func _receive_host_hidden(hidden: bool) -> void:
	if is_host:
		return
	if hidden:
		_host_silent_seconds = HOST_STALL_SECONDS
		_set_host_stalled(true, HOST_HIDDEN_NOTICE)
	else:
		_heard_from_host()


func _hook_web_visibility() -> void:
	if not OS.has_feature("web") or not Engine.has_singleton("JavaScriptBridge"):
		return
	_web_visibility_callback = JavaScriptBridge.create_callback(_on_web_visibility_changed)
	var document = JavaScriptBridge.get_interface("document")
	if document != null:
		document.addEventListener("visibilitychange", _web_visibility_callback)


## Runs inside the browser's visibilitychange event, before the page stops ticking: a web host (public route) tells
## its guests straight away, then flushes the socket.
func _on_web_visibility_changed(_args: Array) -> void:
	var hidden := bool(JavaScriptBridge.eval("document.hidden", true))
	CrashWatch.crumb("web", "tab %s" % ("hidden" if hidden else "visible"))
	if online and is_host and _peer != null:
		NetPeers.send_all(multiplayer, _receive_host_hidden, [hidden])
		_peer.poll()


func uses_ws_transport() -> bool:
	return OS.has_feature("web") or prefer_ws_rooms or (public_route and PUBLIC_ROUTE_USES_WS)


func _ready() -> void:
	prefer_ws_rooms = OS.get_cmdline_user_args().has("--ws-rooms")
	Backend.registration_changed.connect(_on_directory_registration)
	Backend.account_changed.connect(_on_account_changed)
	Backend.reserved_commands_received.connect(_on_reserved_commands)
	Backend.owner_ticket_changed.connect(_on_owner_ticket_changed)
	_relay = RELAY_TUNNEL_SCRIPT.new()
	_relay.name = "GameplayRelayTunnel"
	_relay.relay_ready.connect(_on_relay_ready)
	_relay.relay_failed.connect(_on_relay_failed)
	_relay.host_left.connect(_on_relay_host_left)
	_relay.host_promoted.connect(_on_relay_host_promoted)
	_relay.host_migrating.connect(_on_relay_host_migrating)
	Backend.guest_name_changed.connect(func(_name: String) -> void:
		if not Backend.signed_in():
			_on_account_changed(false, "", false, ""))
	add_child(_relay)
	PackDownloads.install(self)
	_hook_web_visibility()
	# A room always exists, so nothing has to null-check it. Landing straight
	# in a mode from the editor gets a valid singleplayer room.
	if code.is_empty():
		create_local(Mode.DEFAULT)
	var dedicated_options := parse_dedicated_args(OS.get_cmdline_user_args())
	if not dedicated_options.is_empty():
		_start_dedicated.call_deferred(dedicated_options)


# --- dedicated headless host (docs/SERVER_HOSTING.md) ---------------------------------------------------------------
## This process is a dedicated host: no local runner, it only serves the route to guests (--dedicated-host CODE).
var dedicated := false
var dedicated_idle_minutes := 10.0
var _dedicated_empty_seconds := 0.0
const DEDICATED_NAME := "SERVER"


## `-- --dedicated-host CODE [--seed TEXT] [--mode N] [--scale N] [--difficulty N] [--port N] [--idle-minutes M]`
## as options, or {} when this is not a dedicated host. The room password / owner session for a reserved code come
## from the environment (LASTROUTE_ROOM_PASSWORD, LASTROUTE_HOST_SESSION), never the command line.
static func parse_dedicated_args(args: PackedStringArray) -> Dictionary:
	var index := args.find("--dedicated-host")
	if index < 0 or index + 1 >= args.size():
		return {}
	var room := String(args[index + 1]).strip_edges().to_upper()
	if not valid_join_code(room):
		return {}
	var options := {"code": room, "port": DEFAULT_PORT, "idle_minutes": 10.0}
	for key in ["--seed", "--mode", "--scale", "--difficulty", "--port", "--idle-minutes"]:
		var at := args.find(key)
		if at >= 0 and at + 1 < args.size():
			var value := String(args[at + 1])
			match key:
				"--seed": options["seed"] = value
				"--idle-minutes": options["idle_minutes"] = maxf(0.5, value.to_float())
				_: options[key.trim_prefix("--")] = value.to_int()
	return options


func _start_dedicated(options: Dictionary) -> void:
	create_local(Mode.DEFAULT)
	dedicated = true
	dedicated_idle_minutes = float(options.get("idle_minutes", 10.0))
	code = String(options["code"])
	players = PackedStringArray([DEDICATED_NAME])
	Backend.room_password = OS.get_environment("LASTROUTE_ROOM_PASSWORD")
	Backend.spawn_ticket = OS.get_environment("LASTROUTE_SPAWN_TICKET")   # set by the region agent, used once
	Backend.host_region = OS.get_environment("LASTROUTE_REGION")
	if not OS.get_environment("LASTROUTE_HOST_SESSION").is_empty():
		Backend.account_session_token = OS.get_environment("LASTROUTE_HOST_SESSION")
	if options.has("seed"):
		seed_text = String(options["seed"])
	else:
		reroll_seed()
	if options.has("mode") and Mode.values().has(int(options["mode"])):
		mode = int(options["mode"])
	if options.has("scale") and SCALE_LABELS.has(int(options["scale"])):
		map_scale = int(options["scale"])
	if options.has("difficulty"):
		difficulty = _selectable_difficulty_or_standard(int(options["difficulty"]))
	var error := host_room(int(options.get("port", DEFAULT_PORT)))
	print("[dedicated] room %s seed %s port %d: %s" % [code, seed_text, int(options.get("port", DEFAULT_PORT)),
		"hosting" if error.is_empty() else error])
	if not error.is_empty():
		get_tree().quit(2)
		return
	peers[1] = DEDICATED_NAME
	enter(get_tree())   # the route runs from the start; guests late-join into it


## Seconds of an empty room after which a dedicated host should shut down.
static func dedicated_should_exit(empty_seconds: float, idle_minutes: float) -> bool:
	return empty_seconds >= idle_minutes * 60.0


func _tick_dedicated(delta: float) -> void:
	_dedicated_empty_seconds = _dedicated_empty_seconds + delta if peers.size() <= 1 else 0.0
	if dedicated_should_exit(_dedicated_empty_seconds, dedicated_idle_minutes):
		print("[dedicated] room %s empty for %.0f min: shutting down" % [code, dedicated_idle_minutes])
		dedicated = false
		leave_network()   # unregisters: the code is gone at once
		get_tree().quit(0)


func _process(delta: float) -> void:
	_tick_start_heal(delta)
	_tick_host_presence(delta)
	if dedicated:
		_tick_dedicated(delta)
	if handoff_phase != Handoff.NONE or not _handoff_pending_identity.is_empty():
		_tick_handoff()
	if reconnect_active:
		_tick_reconnect()
		return
	if connecting and _connect_started_msec > 0 \
			and Time.get_ticks_msec() - _connect_started_msec >= CONNECTION_TIMEOUT_MSEC:
		_close_failed_connection(
			"ROOM CONNECTION TIMED OUT // GAMEPLAY RELAY UNREACHABLE")


func _exit_tree() -> void:
	if _relay != null:
		_relay.close()


## Open a room on this machine with one player in it.
##
## This IS singleplayer. There is no second code path to keep in step, which is
## the reason to do it now rather than after the networking exists.
func create_local(for_mode: Mode) -> void:
	reserved = false
	room_owner = ""
	public_route = false
	daytime = false
	GameState.clear_pending_route_checkpoint()
	code = _make_code()
	mode = for_mode if mode_available(for_mode) else Mode.DEFAULT
	map_scale = Scale.INFINITE
	difficulty = Difficulty.STANDARD
	leave_network()
	session_active = false
	status_message = ""
	players = PackedStringArray([_make_callsign()])
	reroll_seed()
	changed.emit()


func _on_room_resolved(resolved_code: String, endpoint: Dictionary,
		error: String, generation: int) -> void:
	if not _reconnect_lookup_current(generation, resolved_code):
		return
	_reconnect_request_in_flight = false
	if not error.is_empty():
		return
	var join_error := join_room(String(endpoint.get("address", "")),
		int(endpoint.get("port", DEFAULT_PORT)),
		String(endpoint.get("transport", "relay")), resolved_code, true)
	if not join_error.is_empty():
		status_message = "HOST SIGNAL LOST // %s" % join_error
		changed.emit()


## Online CREATE ROOM: the directory is hosting [param room_code] for [param owner]. This process never hosts it: it
## waits for the dedicated host to list the code, then joins by code like any guest. Polls the directory until listed.
const HOSTED_JOIN_ATTEMPTS := 60
const HOSTED_JOIN_INTERVAL := 2.0
var _hosted_join_generation := 0
## True from CREATE ROOM until this client has joined the listed room. ENTER ROUTE stays off meanwhile: this client's
## own solo room must never start a route under the hosted code.
var _hosted_join_pending := false
## Shown in the lobby while waiting: how many directory checks ran and what the last one answered.
var hosted_join_checks := 0
var hosted_join_last_error := ""


func join_hosted_room(room_code: String, owner: String) -> void:
	create_local(Mode.DEFAULT)
	code = room_code.strip_edges().to_upper()
	room_owner = owner.strip_edges().to_upper()
	_hosted_join_generation += 1
	_hosted_join_pending = true
	hosted_join_checks = 0
	hosted_join_last_error = ""
	status_message = "WAITING FOR ROOM %s TO START" % code
	changed.emit()
	_poll_hosted_room(_hosted_join_generation, 0)


func _poll_hosted_room(generation: int, attempt: int) -> void:
	Backend.resolve_room(code, _on_hosted_room_resolved.bind(generation, attempt))


func _on_hosted_room_resolved(resolved_code: String, endpoint: Dictionary, error: String,
		generation: int, attempt: int) -> void:
	if generation != _hosted_join_generation or resolved_code != code:
		return
	hosted_join_checks = attempt + 1
	hosted_join_last_error = error
	print("[hosted-join] check %d for %s: %s" % [attempt + 1, resolved_code,
		"listed" if error.is_empty() else error])
	changed.emit()
	if error.is_empty():
		var owner := String(endpoint.get("owner", room_owner)).to_upper()
		var join_error := join_room(String(endpoint.get("address", "")),
			int(endpoint.get("port", DEFAULT_PORT)),
			String(endpoint.get("transport", "relay")), resolved_code)
		if not join_error.is_empty():
			# this client never joined: leave, so ENTER cannot start a solo route under the hosted code
			leave_room_to_menu(join_error)
			return
		# join_room leaves any previous room first, which clears owner state, so the owner is set only after the join
		room_owner = owner
		# listed and joined: connecting holds ENTER until the handshake ends, and a guest's ENTER goes to the host
		_hosted_join_pending = false
		return
	if attempt + 1 >= HOSTED_JOIN_ATTEMPTS:
		leave_room_to_menu("ROOM %s DID NOT START // TRY CREATE ROOM AGAIN" % code)
		return
	await get_tree().create_timer(HOSTED_JOIN_INTERVAL).timeout
	if generation == _hosted_join_generation:
		_poll_hosted_room(generation, attempt + 1)


## True when this online room was created by the signed-in account. The owner's start, settings, reroll, kick and end go
## to the room's dedicated host through owner_send, which the host checks against the directory before it acts.
func is_room_owner() -> bool:
	return online and not room_owner.is_empty() and room_owner == Backend.account_username.to_upper()


func hosted_join_pending() -> bool:
	return _hosted_join_pending


## Leaving the room (or resetting it) cancels a pending hosted join: its poll stops and the pending state is dropped.
func _cancel_hosted_join() -> void:
	_hosted_join_generation += 1
	_hosted_join_pending = false


## Owner command: this guest client sends the directory's owner ticket with the request. The dedicated host runs the
## command only after it checks that ticket with the directory (backend owner-tickets/verify, bound to the room's host
## token). Returns false when this client is not the owner of the room, so the caller keeps its normal behaviour.
var _owner_pending_action := {}


func owner_send(action: String, args: Dictionary = {}) -> bool:
	if not (online and not is_host and is_room_owner()):
		return false
	var ticket := Backend.owner_ticket_for_room(code)
	if ticket.is_empty():
		if not _owner_pending_action.is_empty():
			# one command waits for its ticket at a time: a second one is refused (not queued) and shown to the owner
			status_message = "ANOTHER OWNER COMMAND IS STILL CONFIRMING // TRY AGAIN"
			changed.emit()
			return false
		# no fresh ticket yet: ask for one and send this action when it arrives
		_owner_pending_action = {"action": action, "args": args}
		status_message = "CONFIRMING ROOM OWNER..."
		changed.emit()
		Backend.request_owner_ticket(code)
		return true
	_owner_command.rpc_id(1, ticket, action, args)
	Backend.consume_owner_ticket(code)   # the primary server accepts a ticket once per action: the next command asks again
	if status_message == "CONFIRMING ROOM OWNER...":
		status_message = ""   # sent: drop the confirming note
		changed.emit()
	return true


func owner_kick(peer_id: int) -> bool:
	return owner_send("kick", {"peer": peer_id})


func owner_end_route() -> bool:
	return owner_send("end")


func _on_owner_ticket_changed(ready: bool, room_code: String, message: String) -> void:
	if _owner_pending_action.is_empty() or room_code != code:
		return
	var pending := _owner_pending_action
	_owner_pending_action = {}
	if not ready:
		status_message = message
		changed.emit()
		return
	owner_send(String(pending["action"]), pending["args"])


## Authority side (dedicated host, no player of its own): the sender is a guest of this room, so its ticket is checked
## with the directory first. Nothing here trusts the client's name or claim of ownership.
@rpc("any_peer", "call_remote", "reliable")
func _owner_command(ticket: String, action: String, args: Dictionary) -> void:
	if not (is_host and dedicated and online):
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender <= 1 or not peers.has(sender):
		return
	Backend.verify_owner_ticket(code, ticket, action, _on_owner_command_verified.bind(sender, action, args))


func _on_owner_command_verified(authorized: bool, message: String, sender: int, action: String, args: Dictionary) -> void:
	if not (is_host and dedicated and online) or not peers.has(sender):
		return
	if not authorized:
		# the refusal reason goes back to the sender so its lobby shows why the command did nothing
		_owner_refused.rpc_id(sender, message if not message.is_empty() else "THE ROOM OWNER COMMAND WAS REFUSED")
		return
	match action:
		"start":
			if not session_active:
				enter(get_tree())
		"difficulty":
			set_difficulty(int(args.get("value", difficulty)))
		"mode":
			set_mode(int(args.get("value", mode)))
		"map_scale":
			set_map_scale(int(args.get("value", map_scale)))
		"reroll":
			reroll_seed()
		"kick":
			var target := int(args.get("peer", 0))
			if target != sender:   # the owner's own peer is never removed by its own command
				kick_peer(target)
		"end":
			end_session("THE OWNER ENDED THE ROUTE")


## Guest side: the dedicated host refused an owner command this client sent. The reason shows in the lobby status.
@rpc("authority", "call_remote", "reliable")
func _owner_refused(reason: String) -> void:
	status_message = reason
	changed.emit()


## Prepare a saved procedural solo route without entering it yet. Keeping the
## validation here lets the account screen report a bad/stale save while the
## current room remains untouched. The next Main3D consumes GameState's queued
## values once; ordinary CREATE ROOM clears that queue above.
func prepare_route_checkpoint(checkpoint: Dictionary) -> String:
	if not GameState.route_checkpoint_valid(checkpoint):
		return "THE SAVED ROUTE CHECKPOINT IS INVALID"
	var saved_seed_text := String(checkpoint.get("room_seed_text", ""))
	var expected_run_seed := maxi(1, abs(int(saved_seed_text.hash())))
	if expected_run_seed != int(checkpoint.get("run_seed", 0)):
		return "THE SAVED ROUTE SEED DOES NOT MATCH ITS CHECKPOINT"
	var saved_scale := int(checkpoint.get("map_scale", -1))
	var saved_difficulty := int(checkpoint.get("difficulty", -1))
	if not SCALE_LABELS.has(saved_scale) or not difficulty_available(saved_difficulty):
		return "THE SAVED ROUTE USES AN UNAVAILABLE CONFIGURATION"
	if DIFFICULTY_IDS.get(saved_difficulty, "") != checkpoint.get("difficulty_id", ""):
		return "THE SAVED ROUTE DIFFICULTY DOES NOT MATCH ITS CHECKPOINT"
	create_local(Mode.DEFAULT)
	seed_text = saved_seed_text
	map_scale = saved_scale
	difficulty = saved_difficulty
	status_message = "CHECKPOINT READY // DEPTH %d" % int(checkpoint["depth"])
	if not GameState.queue_route_checkpoint(checkpoint):
		return "THE SAVED ROUTE CHECKPOINT COULD NOT BE PREPARED"
	changed.emit()
	return ""


## Open this room to the network.
##
## Everything above already describes a room; this only gives it a transport.
## The host keeps the room it already had -- same code, same seed, same
## configuration -- so hosting is not "start a multiplayer game", it is the
## singleplayer room you are already in becoming joinable.
func host_room(port: int = DEFAULT_PORT,
		fallback_to_solo_on_listing_failure: bool = false) -> String:
	var web_refusal := web_host_refusal(public_route)
	if not web_refusal.is_empty():
		_primary_create_fallback_enabled = false
		return web_refusal
	GameState.clear_pending_route_checkpoint()
	leave_network()
	_primary_create_fallback_enabled = fallback_to_solo_on_listing_failure
	var use_ws := uses_ws_transport()
	if use_ws:
		var ws_peer = WS_PEER_SCRIPT.new()
		ws_peer.create_host(code)
		ws_peer.link_ready.connect(_on_relay_ready)
		ws_peer.link_failed.connect(_on_relay_failed)
		_peer = ws_peer
	else:
		var enet_peer := ENetMultiplayerPeer.new()
		var error := enet_peer.create_server(port, MAX_PLAYERS)
		if error != OK:
			_primary_create_fallback_enabled = false
			return "COULD NOT CREATE ONLINE ROOM // NETWORK PORT UNAVAILABLE"
		_peer = enet_peer
	configure_world_auth(multiplayer as SceneMultiplayer, _on_world_auth_mismatch)
	multiplayer.multiplayer_peer = _peer
	_host_port = port
	online = true
	connecting = false
	is_host = true
	session_active = false
	status_message = "REGISTERING ROOM WITH PRIMARY SERVER"
	_directory_status = ""
	peers = {1: _local_name()}
	_bind_signals()
	var pack_error := RoomPacks.host_load(public_route)
	if not pack_error.is_empty():
		status_message = pack_error
	Backend.register_room(code, 0 if use_ws else port, peers.size(), session_active,
		"ws" if use_ws else "enet")
	changed.emit()
	return ""


## Host an empty reserved private room under its own code, with the route settings the server stored for it.
func host_reserved_room(reserved_code: String, settings: Dictionary) -> String:
	var web_refusal := web_host_refusal(false)
	if not web_refusal.is_empty():
		return web_refusal
	create_local(Mode.DEFAULT)
	code = reserved_code.strip_edges().to_upper()
	reserved = true
	_apply_reserved_settings(settings, false)
	var error := host_primary_room()
	if error.is_empty():
		status_message = "PRIVATE ROOM %s // YOU ARE HOSTING" % code
		changed.emit()
	return error


## Stored settings (seed, mode, scale, difficulty, daytime) onto this room; an empty stored seed means a fresh one.
func _apply_reserved_settings(settings: Dictionary, keep_seed: bool) -> void:
	if not keep_seed:
		var stored := String(settings.get("seed", "")).strip_edges()
		if stored.is_empty():
			var stamp := "%d%d" % [Time.get_ticks_usec(), randi()]
			seed_text = "ROOM-%s-%s" % [code, stamp.md5_text().substr(0, 20).to_upper()]
		else:
			seed_text = stored
	if settings.has("mode") and Mode.values().has(int(settings["mode"])) and mode_available(int(settings["mode"])):
		mode = int(settings["mode"])
	if settings.has("scale") and SCALE_LABELS.has(int(settings["scale"])):
		map_scale = int(settings["scale"])
	if settings.has("difficulty"):
		difficulty = _selectable_difficulty_or_standard(int(settings["difficulty"]))
	if settings.has("daytime"):
		daytime = bool(settings["daytime"])


## Owner commands for the reserved room this client hosts, from the directory heartbeat. Each is carried out here
## (the server only stores and echoes) and acked so it is not sent again.
func _on_reserved_commands(commands: Array) -> void:
	if not (online and is_host and reserved):
		return
	for entry_value in commands:
		var entry: Dictionary = entry_value
		var command := String(entry.get("command", ""))
		var args: Dictionary = entry.get("args", {}) if entry.get("args", {}) is Dictionary else {}
		print("[coop] private room %s: owner command %s %s" % [code, command, args])
		CrashWatch.crumb("reserved", "%s %s" % [command, args])
		match command:
			"restart", "end":
				carry_out_route_command(command, args)
			"kick":
				var target := String(args.get("target", "")).to_lower()
				for peer_id in peers.keys():
					if int(peer_id) != 1 and String(peers[peer_id]).to_lower() == target:
						kick_peer(int(peer_id))
			"settings":
				_apply_reserved_settings(args.get("settings", {}), true)
				broadcast()
				changed.emit()
			"transfer":
				# a deliberate handoff with a checkpoint barrier. This host stays in charge until the relay
				# confirms the commit; unsupported transports and refusals say so instead of dropping the room.
				var handoff_error := begin_host_handoff()
				if not handoff_error.is_empty():
					status_message = "PRIVATE ROOM // HOST TRANSFER NOT STARTED // %s" % handoff_error
					changed.emit()
		Backend.ack_reserved_command(int(entry.get("seq", 0)))


## Owner route controls, carried out by the client that hosts the room (or by a solo run): RESTART ROUTE re-enters the
## route with a new seed, or the same one when args.sameSeed; END ROUTE returns everyone to staging. Reserved rooms reach
## this through _on_reserved_commands; every other room reaches it through the route's admin path (InfiniteRouteTest).
func carry_out_route_command(command: String, args: Dictionary) -> void:
	match command:
		"restart":
			var same_seed := bool(args.get("sameSeed", false))
			var settings: Dictionary = args.get("settings", {}) if args.get("settings", {}) is Dictionary else {}
			_apply_reserved_settings(settings, same_seed)
			if not same_seed and String(settings.get("seed", "")).is_empty():
				reroll_seed()
			if session_active:
				end_session("ROUTE RESTARTING")
				get_tree().create_timer(1.5).timeout.connect(func() -> void:
					if (not online or is_host) and not session_active:
						enter(get_tree()))
			else:
				enter(get_tree())
		"end":
			if session_active:
				end_session("PRIVATE ROOM // THE OWNER ENDED THE ROUTE" if reserved else "THE OWNER ENDED THE ROUTE")


## Local whitelist for the room this client is in (WHITELIST outside a reserved private room). Only a reserved room
## enforces a whitelist on join; this list is kept on this client and checked by nothing else.
var local_whitelist_code := ""
var local_whitelist := PackedStringArray()


func local_whitelist_names() -> PackedStringArray:
	return local_whitelist.duplicate() if local_whitelist_code == code else PackedStringArray()


func add_local_whitelist(account: String) -> void:
	if local_whitelist_code != code:
		local_whitelist_code = code
		local_whitelist = PackedStringArray()
	if not account.is_empty() and not local_whitelist.has(account):
		local_whitelist.append(account)


## Main-menu CREATE ROOM path: make the ordinary room online automatically.
## A failed initial listing falls back to the already-created solo room; once
## listed, transient heartbeat trouble does not destroy a live co-op session.
func host_primary_room(port: int = DEFAULT_PORT) -> String:
	var error := host_room(port, true)
	if error == WEB_HOST_REFUSED:
		status_message = "SOLO ROOM // %s" % error
		changed.emit()
		return error
	if not error.is_empty():
		status_message = "PRIMARY SERVER UNAVAILABLE // SOLO ROOM // %s" % error
		changed.emit()
		return error
	return ""


## Join someone else's room. Their configuration replaces ours wholesale --
## the host owns the route, so a client that kept its own seed would generate a
## different building from the same room.
func join_room(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT,
		transport: String = "direct", room_code: String = "",
		preserve_session: bool = false) -> String:
	var use_ws := transport == "ws"
	if OS.has_feature("web") and not use_ws:
		return "THIS ROOM IS NATIVE-ONLY // ASK THE HOST FOR A WEB-COMPATIBLE ROOM"
	if preserve_session:
		_close_transport_only(false)
		_reconnect_room_received = false
	else:
		GameState.clear_pending_route_checkpoint()
		leave_network()
	var trimmed := address.strip_edges()
	if use_ws:
		if room_code.strip_edges().is_empty():
			return "ENTER A ROOM CODE"
		var ws_ticket := Backend.take_join_ticket(room_code)
		reserved = not ws_ticket.is_empty()   # only a reserved private room hands out join tickets
		var ws_peer = WS_PEER_SCRIPT.new()
		ws_peer.link_failed.connect(_on_ws_guest_link_failed)
		var ws_error: int = ws_peer.create_guest(WS_PEER_SCRIPT.relay_url(Backend.base_url), room_code, ws_ticket)
		if ws_error != OK:
			return "COULD NOT REACH THE WEB RELAY"
		_peer = ws_peer
	else:
		if trimmed.is_empty():
			return "ENTER A HOST ADDRESS"
		var connect_address := trimmed
		var connect_port := port
		if transport == "relay":
			var ticket := Backend.take_join_ticket(room_code)
			reserved = not ticket.is_empty()   # only a reserved private room hands out join tickets
			connect_port = _relay.start_guest(room_code, trimmed, port, ticket)
			if connect_port <= 0:
				return "COULD NOT OPEN GAMEPLAY RELAY TUNNEL"
			connect_address = DEFAULT_ADDRESS
		var enet_peer := ENetMultiplayerPeer.new()
		var error := enet_peer.create_client(connect_address, connect_port)
		if error != OK:
			return "COULD NOT REACH GAMEPLAY RELAY"
		_peer = enet_peer
	configure_world_auth(multiplayer as SceneMultiplayer, _on_world_auth_mismatch)
	multiplayer.multiplayer_peer = _peer
	online = false
	connecting = true
	_connect_started_msec = Time.get_ticks_msec()
	_host_port = port
	is_host = false
	if not preserve_session:
		session_active = false
		peers = {}
	if preserve_session:
		status_message = "RECONNECTING TO HOST"
	else:
		status_message = "JOINING ROOM THROUGH PRIMARY GAMEPLAY RELAY"
	_bind_signals()
	changed.emit()
	return ""


## Owner state ends with the room: the owner flag, a command still waiting for its ticket and the cached owner ticket.
## Every leave path (leave_network, and reset_after_leaving / leave_room_to_menu through it) runs this.
func _clear_owner_state() -> void:
	room_owner = ""
	_owner_pending_action = {}
	Backend.clear_owner_tickets()


func leave_network() -> void:
	_cancel_hosted_join()
	_clear_owner_state()
	Backend.skin_sync.clear_cache()   # other players' skins are memory-only: gone when you leave the room
	# Tell host authority which roster row is leaving before closing ENet. Relay
	# guests must also drain the loopback proxy once, or the reliable RPC can be
	# discarded when the relay socket is torn down immediately afterwards.
	if online and not is_host and _peer != null:
		_request_peer_leave.rpc_id(1)
		_peer.poll()
		if _relay != null:
			_relay.flush_guest_outbound()
	if online and is_host:
		Backend.unregister_room()
	_close_transport_only(true)
	_clear_reconnect_state()
	RoomPacks.leave()
	changed.emit()


func _close_transport_only(reset_room_identity: bool) -> void:
	_world_auth_mismatch_peer = null
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	if multiplayer is SceneMultiplayer:
		(multiplayer as SceneMultiplayer).auth_callback = Callable()
	if _relay != null:
		_relay.close()
	online = false
	connecting = false
	_connect_started_msec = 0
	_relay_status = ""
	_directory_status = ""
	_primary_create_fallback_enabled = false
	_host_silent_seconds = 0.0
	host_stalled = false
	if reset_room_identity:
		is_host = true
		session_active = false
		peers = {}
		_packs_waiting = {}
		_reset_handoff_identity()


func _bind_signals() -> void:
	var scene_api := multiplayer as SceneMultiplayer
	if scene_api != null and not scene_api.peer_authentication_failed.is_connected(_on_world_auth_failed):
		scene_api.peer_authentication_failed.connect(_on_world_auth_failed)
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_joined)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


## SceneMultiplayer excludes authenticating peers from get_peers() and rejects
## their RPCs until BOTH sides complete authentication. Thus room/start/heal,
## packs and gameplay RPCs cannot race generation admission on any transport.
static func configure_world_auth(api: SceneMultiplayer, on_mismatch: Callable = Callable()) -> void:
	api.auth_timeout = WORLD_AUTH_TIMEOUT_SECONDS
	api.auth_callback = _receive_world_auth.bind(api, on_mismatch)
	var send := _send_world_auth.bind(api)
	if not api.peer_authenticating.is_connected(send):
		api.peer_authenticating.connect(send)


static func _send_world_auth(id: int, api: SceneMultiplayer) -> void:
	api.send_auth(id, NetProtocol.fingerprint().to_utf8_buffer())


static func _receive_world_auth(id: int, data: PackedByteArray, api: SceneMultiplayer,
		on_mismatch: Callable = Callable()) -> void:
	# The id comes from the transport, never a claimed id inside a peer's payload.
	if not api.get_authenticating_peers().has(id):
		return
	if data != NetProtocol.fingerprint().to_utf8_buffer():
		if on_mismatch.is_valid():
			on_mismatch.call(id)
		api.disconnect_peer(id)
		return
	api.complete_auth(id)


func _on_world_auth_mismatch(id: int) -> void:
	if not is_host and id == 1 and connecting:
		_world_auth_mismatch_peer = _peer


func _on_world_auth_failed(id: int) -> void:
	if not is_host and id == 1 and connecting and _peer != null:
		_finish_world_auth_failure.call_deferred(_peer)


func _finish_world_auth_failure(failed_peer: MultiplayerPeer) -> void:
	# A queued failure from an abandoned attempt must not close a new transport.
	if _peer == failed_peer and connecting:
		if reconnect_active and _world_auth_mismatch_peer != failed_peer:
			# A lost auth packet is still a transient transport failure. Reuse the
			# retry path, which preserves the original eight-second deadline.
			_on_connection_failed()
		else:
			_close_failed_connection("BUILD MISMATCH OR COMPATIBILITY TIMEOUT // UPDATE")


func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	if handoff_phase in [Handoff.PREPARING, Handoff.RELEASING]:
		# a late joiner cannot be part of the checkpoint barrier: it retries and lands on whoever hosts next
		if multiplayer.multiplayer_peer != null:
			multiplayer.multiplayer_peer.disconnect_peer(id)
		return
	peers[id] = "SIGNAL-%d" % id
	# The host is the only authority on the route, so a joiner is TOLD the room
	# rather than asked about it.
	_receive_room.rpc_id(id, code, seed_text, mode, map_scale, difficulty, peers,
		session_active)
	_receive_daytime.rpc_id(id, daytime)
	NetPeers.send_all(multiplayer, _receive_room, [code, seed_text, mode, map_scale, difficulty, peers,
		session_active])
	# A room remains joinable while a route is running. The new peer first gets
	# the room seed/config above, then enters the same scene; RemotePlayers asks
	# the host for the current floor snapshot once that fixed RPC path exists.
	if session_active:
		_receive_start.rpc_id(id, code, seed_text, mode, map_scale, difficulty)
	Backend.update_room(peers.size(), session_active)
	changed.emit()


var _start_heal_elapsed := 0.0
const START_HEAL_SECONDS := 4.0


func _tick_start_heal(delta: float) -> void:
	if not (online and is_host and session_active) or multiplayer.multiplayer_peer == null:
		_start_heal_elapsed = 0.0
		return
	_start_heal_elapsed += delta
	if _start_heal_elapsed >= START_HEAL_SECONDS:
		_start_heal_elapsed = 0.0
		NetPeers.send_all(multiplayer, _receive_room, [code, seed_text, mode, map_scale, difficulty, peers, session_active])


func _on_peer_disconnected(id: int) -> void:
	_handoff_capable.erase(id)
	if not peers.has(id):
		return
	peers.erase(id)
	if is_host:
		NetPeers.send_all(multiplayer, _receive_room, [code, seed_text, mode, map_scale, difficulty, peers,
			session_active])
		Backend.update_room(peers.size(), session_active)
	changed.emit()


## Host only (owner/admin tools): remove a guest from the room, the same way a guest's own leave is handled.
func kick_peer(id: int) -> void:
	if not online or not is_host or id <= 1 or not peers.has(id):
		return
	peers.erase(id)
	_resume_hashes.erase(id)
	NetPeers.send_all(multiplayer, _receive_room, [code, seed_text, mode, map_scale, difficulty, peers, session_active])
	Backend.update_room(peers.size(), session_active)
	changed.emit()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(id)


## A graceful guest exit reaches host authority before its relay tunnel closes.
## The transport's later peer_disconnected signal is intentionally idempotent.
@rpc("any_peer", "call_remote", "reliable")
func _request_peer_leave() -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or not peers.has(id):
		return
	peers.erase(id)
	_resume_hashes.erase(id)   # an explicit leave gives up the resume identity
	NetPeers.send_all(multiplayer, _receive_room, [code, seed_text, mode, map_scale, difficulty, peers,
		session_active])
	Backend.update_room(peers.size(), session_active)
	changed.emit()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.disconnect_peer(id)


func _on_directory_registration(listed: bool, message: String) -> void:
	if not online or not is_host:
		return
	if not listed and _primary_create_fallback_enabled:
		var reason := message
		leave_network()
		status_message = "PRIMARY SERVER UNAVAILABLE // SOLO ROOM // %s" % reason
		changed.emit()
		return
	if listed:
		_primary_create_fallback_enabled = false
	_directory_status = message if listed else "PRIMARY SERVER LISTING FAILED // %s" % message
	status_message = _directory_status
	if listed and _peer != null and _peer.get_script() == WS_PEER_SCRIPT:
		var ws_endpoint := Backend.host_endpoint()
		if String(ws_endpoint.get("transport", "")) != "ws":
			_on_relay_failed("PRIMARY SERVER DID NOT ACCEPT A WEB-COMPATIBLE ROOM")
			return
		_peer.start_host_link(WS_PEER_SCRIPT.relay_url(Backend.base_url), Backend.host_token())
		_relay_status = "CONNECTING WEB RELAY"
		status_message += " // %s" % _relay_status
		changed.emit()
		return
	if listed:
		var endpoint := Backend.host_endpoint()
		var relay_address := String(endpoint.get("address", ""))
		var relay_port := int(endpoint.get("port", 0))
		if String(endpoint.get("transport", "")) != "relay" \
				or relay_address.is_empty() or relay_port <= 0:
			_on_relay_failed("PRIMARY SERVER RETURNED NO GAMEPLAY RELAY")
			return
		if _relay.mode == 1 and _relay.room_code == code:
			_relay.update_host_token(Backend.host_token())
		else:
			var error: String = _relay.start_host(code, Backend.host_token(), _host_port,
				relay_address, relay_port)
			if not error.is_empty():
				_on_relay_failed(error)
				return
		_relay_status = "CONNECTING GAMEPLAY RELAY"
		status_message += " // %s" % _relay_status
	changed.emit()


func _on_ws_guest_link_failed(message: String) -> void:
	if connecting:
		_close_failed_connection(message)


func _on_relay_ready() -> void:
	if handoff_phase == Handoff.SUCCESSOR_ADOPTING and online and is_host:
		_complete_successor()
	_relay_status = "GAMEPLAY RELAY READY // NO PORT FORWARDING REQUIRED"
	if online and is_host:
		status_message = _directory_status if not _directory_status.is_empty() \
			else "ROOM LISTED IN DIRECTORY"
		status_message += " // %s" % _relay_status
	elif connecting:
		status_message = "GAMEPLAY RELAY READY // CONNECTING TO HOST"
	changed.emit()


func _on_relay_failed(message: String) -> void:
	# A web-relay host whose link dropped may be talking to a restarted server that forgot the room: ask the
	# directory right away (the next heartbeat re-lists the room and re-opens the link) instead of waiting for the timer.
	if online and is_host and _peer != null and _peer.get_script() == WS_PEER_SCRIPT:
		Backend.update_room(peers.size(), session_active)
	_relay_status = "GAMEPLAY RELAY WAITING // %s" % message
	if online and is_host:
		status_message = _directory_status if not _directory_status.is_empty() \
			else "ROOM LISTED IN DIRECTORY"
		status_message += " // %s" % _relay_status
	elif connecting:
		status_message = _relay_status
	changed.emit()


func _on_joined() -> void:
	if not connecting or _peer == null:
		return
	connecting = false
	_connect_started_msec = 0
	online = true
	if reconnect_active:
		status_message = "RECONNECTED // WAITING FOR HOST SNAPSHOT"
	else:
		status_message = "CONNECTED // WAITING FOR HOST"
	peers[multiplayer.get_unique_id()] = _local_name()
	# the resume proof goes first so the host can rebind this runner before it answers the roster or a snapshot
	if not _resume_secret.is_empty():
		_handoff_present_resume.rpc_id(1, _resume_secret)
	_register_peer.rpc_id(1, _local_name())
	var relay_session: int = _relay.guest_session() if _relay != null else 0
	_handoff_hello.rpc_id(1, HOST_HANDOFF_SCRIPT.VERSION, relay_session)
	changed.emit()


func _on_connection_failed() -> void:
	if _peer != null and _world_auth_mismatch_peer == _peer:
		_close_failed_connection("BUILD MISMATCH // UPDATE")
		return
	if reconnect_active:
		# Invalidate even a lookup still outstanding from this transport attempt.
		_reconnect_generation += 1
		_close_transport_only(false)
		_reconnect_room_received = false
		_reconnect_request_in_flight = false
		_reconnect_next_lookup_msec = Time.get_ticks_msec() + RECONNECT_LOOKUP_INTERVAL_MSEC
		status_message = "HOST SIGNAL LOST // RETRYING ROOM"
		changed.emit()
		return
	_close_failed_connection("ROOM CONNECTION FAILED // TRY THE CODE AGAIN")


func _on_server_disconnected() -> void:
	if handoff_phase == Handoff.SUCCESSOR_ARMED:
		# keep the relay socket: the promotion arrives on it; the deadline or HOST_LEFT ends the wait otherwise
		_handoff_old_link_lost = true
		return
	if handoff_phase == Handoff.GUEST_WAITING and session_active:
		_start_handoff_reconnect()   # the "ready" notice was lost or late: same bounded path, handoff grace
		return
	if reconnect_active:
		_on_connection_failed()
		return
	if session_active and not is_host and not reconnect_active:
		_start_reconnect_grace()
		return
	_close_failed_connection(HOST_LEFT_NOTICE, true)


func _close_failed_connection(reason: String, to_menu: bool = false) -> void:
	var was_public := public_route
	_close_transport_only(true)
	_clear_reconnect_state()
	RoomPacks.leave()
	status_message = reason
	changed.emit()
	connection_lost.emit(reason)
	if was_public:
		# The shared route has no staging to fall back to: join it again, which
		# may make this client the new authority (see PublicRoute).
		public_route = true
		PublicRoute.on_connection_lost()
		return
	if to_menu:
		call_deferred("_finish_failed_transition", _reconnect_generation, code, reason, true)
		return
	call_deferred("_finish_failed_transition", _reconnect_generation, code, reason, false)


func _finish_failed_transition(generation: int, failed_code: String, reason: String, to_menu: bool) -> void:
	if generation != _reconnect_generation or code != failed_code or online or connecting:
		return
	if to_menu:
		leave_room_to_menu(reason)
	else:
		_return_to_staging()


func _start_reconnect_grace() -> void:
	_close_transport_only(false)
	_reconnect_generation += 1
	reconnect_active = true
	_reconnect_room_received = false
	_reconnect_deadline_msec = Time.get_ticks_msec() + RECONNECT_GRACE_MSEC
	_reconnect_next_lookup_msec = 0
	_reconnect_request_in_flight = false
	status_message = "HOST SIGNAL LOST // RECONNECTING ROOM"
	changed.emit()


func _tick_reconnect() -> void:
	var now := Time.get_ticks_msec()
	if now >= _reconnect_deadline_msec:
		_close_failed_connection(HOST_LEFT_NOTICE, true)
		return
	if online or connecting or _reconnect_request_in_flight or now < _reconnect_next_lookup_msec:
		return
	_reconnect_request_in_flight = true
	_reconnect_next_lookup_msec = now + RECONNECT_LOOKUP_INTERVAL_MSEC
	var generation := _reconnect_generation
	var lookup_code := code
	Backend.resolve_room(lookup_code, _on_room_resolved.bind(generation),
		_reconnect_lookup_current.bind(generation, lookup_code))


func _reconnect_lookup_current(generation: int, lookup_code: String) -> bool:
	return reconnect_active and generation == _reconnect_generation and lookup_code == code \
		and Time.get_ticks_msec() < _reconnect_deadline_msec


## The route calls this only AFTER validating/adopting the authoritative snapshot.
## A room roster is not a world snapshot: retain the original deadline until this acknowledgement.
func reconnect_snapshot_ready() -> bool:
	return not reconnect_active or (online and not is_host and _reconnect_room_received \
		and Time.get_ticks_msec() < _reconnect_deadline_msec)


func confirm_reconnect_snapshot() -> bool:
	if not reconnect_snapshot_ready():
		return false
	if not reconnect_active:
		return true
	_clear_reconnect_state()
	changed.emit()
	return true


func _clear_reconnect_state() -> void:
	_reconnect_generation += 1
	reconnect_active = false
	_reconnect_room_received = false
	_reconnect_deadline_msec = 0
	_reconnect_next_lookup_msec = 0
	_reconnect_request_in_flight = false


## Replace the host's temporary SIGNAL-id label with the callsign the joining
## peer already had in its local room. The sender id, never a client-supplied
## id, decides which roster row changes.
@rpc("any_peer", "call_remote", "reliable")
func _register_peer(requested_name: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or not peers.has(id):
		return
	# One rename / reclaim per peer every 5 s — stops a flood of callsign swaps.
	var now_msec := Time.get_ticks_msec()
	if now_msec - int(_register_peer_at.get(id, 0)) < 5000:
		return
	_register_peer_at[id] = now_msec
	var clean := requested_name.strip_edges().to_upper().substr(0, 32)
	# A guest that reconnects after a dropped link arrives as a NEW peer id while
	# its old id lingers until ENet times it out. Same callsign = same runner:
	# retire the stale row so the roster (and the party size) does not double count.
	# Only disconnect when that old id is no longer a live transport peer — never
	# boot someone still connected who happens to share a callsign.
	if not clean.is_empty():
		var live := multiplayer.get_peers() if multiplayer.multiplayer_peer != null else PackedInt32Array()
		for old_id in peers.keys().duplicate():
			if int(old_id) != id and int(old_id) > 1 and String(peers[old_id]) == clean:
				peers.erase(old_id)
				_register_peer_at.erase(int(old_id))
				if multiplayer.multiplayer_peer != null and not live.has(int(old_id)):
					multiplayer.multiplayer_peer.disconnect_peer(int(old_id))
	peers[id] = clean if not clean.is_empty() else "SIGNAL-%d" % id
	if not _resume_hashes.has(id):
		var secret: String = HOST_HANDOFF_SCRIPT.new_resume_secret()
		_resume_hashes[id] = HOST_HANDOFF_SCRIPT.resume_hash(secret)
		_handoff_issue_resume.rpc_id(id, secret)
	broadcast()
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_room(p_code: String, p_seed: String, p_mode: int, p_scale: int,
		p_difficulty: int, p_peers: Dictionary, p_session_active: bool) -> void:
	if not is_host:
		_heard_from_host()
	if reconnect_active and (p_code != code or Time.get_ticks_msec() >= _reconnect_deadline_msec):
		return
	code = p_code
	seed_text = p_seed
	mode = p_mode
	map_scale = p_scale
	difficulty = _selectable_difficulty_or_standard(p_difficulty)
	peers = p_peers
	session_active = p_session_active
	# A release admin guest mints her opaque room proof only after adopting the
	# host's real code. Her account session never enters an ENet packet.
	if not is_host and Backend.admin_authorized():
		Backend.request_admin_ticket(code)
	if reconnect_active:
		_reconnect_room_received = true
		if not p_session_active:
			# The host ended the run while we were away; staging has no world snapshot to await.
			_clear_reconnect_state()
			call_deferred("_finish_recovered_staging", _reconnect_generation, code)
	changed.emit()
	# Self-heal for the join/start race: a guest that joined while the host was starting can miss the one start RPC
	# (the playtest party saw one of two guests stay in the lobby). Every room update says whether the route is running,
	# so a guest still outside it enters now.
	if online and not is_host and p_session_active and not connecting:
		call_deferred("_enter_received_session", _reconnect_generation, code)


func _finish_recovered_staging(generation: int, recovered_code: String) -> void:
	if generation == _reconnect_generation and code == recovered_code and online \
			and not connecting and not session_active:
		_return_to_staging()


func _enter_received_session(generation: int, received_code: String) -> void:
	if generation == _reconnect_generation and code == received_code and online \
			and not connecting and session_active:
		_enter_session_scene(get_tree())


## Push the host's configuration to everyone. Called after any host-side change,
## so a client never generates a building from a stale route.
func broadcast() -> void:
	if online and is_host:
		NetPeers.send_all(multiplayer, _receive_packs, [RoomPacks.announce()])
		NetPeers.send_all(multiplayer, _receive_room, [code, seed_text, mode, map_scale, difficulty, peers,
			session_active])
		NetPeers.send_all(multiplayer, _receive_daytime, [daytime])


## The host's content packs, sent ahead of every room update (a separate RPC so the room RPC's signature stays as it
## was). A guest that cannot load the same packs leaves before it generates anything, with the reason in the status.
@rpc("authority", "call_remote", "reliable")
func _receive_packs(p_packs: Dictionary) -> void:
	if is_host:
		return
	var result := RoomPacks.adopt(p_packs, public_route)
	if result["ok"]:
		_packs_waiting = {}
		return
	# Missing packs in a private room: the mod UI asks (or auto-downloads) and calls back; anything else refuses.
	var dialog := get_tree().root.find_child("ModJoinDialog", true, false)
	if result["missing"].is_empty() or public_route or dialog == null or not dialog.has_method("begin"):
		_close_failed_connection(String(result["reason"]))
		return
	if String(_packs_waiting.get("hash", "")) == String(p_packs.get("hash", "")):
		return
	_packs_waiting = p_packs
	if not dialog.is_connected("join_allowed", _on_mod_join_allowed):
		dialog.connect("join_allowed", _on_mod_join_allowed)
		dialog.connect("cancelled", _on_mod_join_cancelled)
	status_message = "MODS NEEDED // %s" % String(result["reason"])
	changed.emit()
	dialog.begin(p_packs.get("packs", []), not public_route)


func _on_mod_join_allowed() -> void:
	if _packs_waiting.is_empty():
		return
	var result := RoomPacks.adopt(_packs_waiting, public_route)
	_packs_waiting = {}
	if not result["ok"]:
		_close_failed_connection(String(result["reason"]))
		return
	status_message = "MODS LOADED // WAITING FOR HOST"
	changed.emit()
	if online and session_active:
		call_deferred("_enter_session_scene", get_tree())


func _on_mod_join_cancelled() -> void:
	if not _packs_waiting.is_empty():
		_close_failed_connection("JOIN CANCELLED // ROOM MODS NOT DOWNLOADED")


## The host's City daytime flag (a separate small RPC so the room RPC's signature stays as it was).
@rpc("authority", "call_remote", "reliable")
func _receive_daytime(p_daytime: bool) -> void:
	daytime = p_daytime
	changed.emit()


## City only: whether this room is in daytime. Last Route rooms are never day.
func is_day() -> bool:
	return false   # only the archived City had daytime


## Host (or solo) toggles daytime before the run starts; guests see it through the room sync.
func set_daytime(value: bool) -> void:
	if online and not is_host:
		return
	if daytime == value:
		return
	daytime = value
	broadcast()
	changed.emit()


func _local_name() -> String:
	# Account verification completes asynchronously after RoomState creates its
	# initial local room. Prefer the current verified identity over that stale
	# startup callsign when hosting or registering with a remote host.
	if Backend.signed_in():
		return Backend.account_username
	return String(players[0]) if not players.is_empty() else _make_callsign()


func _on_account_changed(signed_in_now: bool, username: String,
		_admin: bool, _message: String) -> void:
	var updated_name := username.strip_edges().to_upper() if signed_in_now \
		else _random_guest_callsign()
	if updated_name.is_empty():
		return
	if players.is_empty():
		players.append(updated_name)
	else:
		players[0] = updated_name
	if online:
		var local_id := multiplayer.get_unique_id()
		peers[local_id] = updated_name
		if is_host:
			broadcast()
			Backend.update_room(peers.size(), session_active)
		else:
			_register_peer.rpc_id(1, updated_name)
	changed.emit()


func local_display_name() -> String:
	return _local_name()


func peer_display_name(peer_id: int) -> String:
	return String(peers.get(peer_id, "SIGNAL-%d" % peer_id))


## A fresh route for the same room. The web build regenerates the facility from
## the seed, so changing it is how you get a different building without leaving
## staging.
func reroll_seed() -> void:
	if online and not is_host:
		owner_send("reroll")
		return
	var stamp := "%d%d" % [Time.get_ticks_usec(), randi()]
	seed_text = "ROOM-%s-%s" % [code, stamp.md5_text().substr(0, 20).to_upper()]
	broadcast()
	changed.emit()


## The seed as GameState wants it. Derived from the text rather than stored
## separately, so the string on screen and the facility on the floor cannot
## disagree about which route this is.
##
## Never zero: GameState.start_new_run() reads zero as "pick one at random",
## which would hand two peers in the same room two different facilities.
func run_seed() -> int:
	return maxi(1, abs(int(seed_text.hash())))


## Everyone in the room WITH who they are: their peer id, whether they host it
## and whether they are you.
##
## roster() alone was not enough -- the staging screen printed "HOST // YOU" on
## every row because a bare name cannot say otherwise, so a guest's window
## claimed to be hosting.
##
## Peer 1 is always the host; that is ENet's rule, not ours, which is why the
## check is against the id rather than against this peer's own is_host flag.
func roster_rows() -> Array:
	var me := multiplayer.get_unique_id() if online else 1
	var rows: Array = []
	if not online:
		for name in players:
			rows.append({"name": String(name), "id": 1,
				"host": not connecting, "you": true})
		return rows
	var ids: Array = peers.keys()
	ids.sort()
	for id in ids:
		rows.append({"name": String(peers[id]), "id": id,
			"host": int(id) == 1, "you": int(id) == me})
	return rows


func roster() -> PackedStringArray:
	if not online:
		return players
	var out := PackedStringArray()
	for id in peers:
		out.append(String(peers[id]))
	return out


## Whether a mode can be picked in this room's current state. Disabled modes
## are rejected here as well as in staging so stale clients and direct calls
## cannot enter an unfinished ruleset.
func mode_available(candidate: Mode) -> bool:
	return candidate == Mode.DEFAULT


func mode_unavailable_reason(candidate: Mode) -> String:
	return "" if mode_available(candidate) else "MODE IS UNAVAILABLE"


func difficulty_available(candidate: Difficulty) -> bool:
	return DIFFICULTY_LABELS.has(candidate)


## What the button that leaves staging should say, in the web build's words.
func start_label() -> String:
	return "ENTER ROUTE"


func mode_label() -> String:
	return String(MODE_LABELS.get(mode, "?"))


static func valid_room_code(value: String) -> bool:
	var clean := value.strip_edges().to_upper()
	if clean.length() != CODE_LENGTH:
		return false
	for glyph in clean:
		if not CODE_ALPHABET.contains(glyph):
			return false
	return true


## A code someone may type to join: a generated one (valid_room_code) or an owner's reserved private room, which may
## use any five letters or digits (KATHY, AKIRI). The directory decides which codes exist.
static func valid_join_code(value: String) -> bool:
	var clean := value.strip_edges().to_upper()
	if clean.length() != CODE_LENGTH:
		return false
	for glyph in clean:
		if not (CODE_ALPHABET.contains(glyph) or glyph in "IO01"):
			return false
	return true


func seats() -> int:
	return MAX_PLAYERS


## What each map scale actually builds.
##
## The generator has taken these as options since it was ported -- cols, rows,
## room and pickup counts -- but nothing passed any, so every route came out
## the 45x45 default and MAP SCALE was a button that did nothing. Sizes stay
## inside the generator's own 35..121 clamp; relays scale with the walking
## distance so a SPRAWLING route is longer rather than merely emptier.
const SCALE_OPTIONS := {
	Scale.SMALL: {"cols": 35, "rows": 35, "room_count": 7, "relay_count": 4,
		"battery_count": 5},
	Scale.STANDARD: {"cols": 45, "rows": 45, "room_count": 9, "relay_count": 5,
		"battery_count": 7},
	Scale.LARGE: {"cols": 61, "rows": 61, "room_count": 12, "relay_count": 6,
		"battery_count": 9},
	# The old CAVERNOUS numbers -- the bigger of the two merged tiers, kept
	# rather than split the difference, so IMMENSE still means the biggest
	# route this port offers rather than a step down from what SPRAWLING used
	# to be on its own.
	Scale.IMMENSE: {"cols": 99, "rows": 99, "room_count": 20, "relay_count": 8,
		"battery_count": 15},
}


## The generator options this room's configuration asks for.
##
## Read by both facility views, so the 2D and 3D renderers cannot disagree
## about how big the route is -- and so a joined room builds the host's
## facility rather than its own.
func generator_options() -> Dictionary:
	var options := (SCALE_OPTIONS.get(map_scale,
		SCALE_OPTIONS[Scale.STANDARD]) as Dictionary).duplicate()
	# A runner cannot be allowed to stand forever in a hunter-proof refuge.
	# Every finite Last Route map currently has one spawn checkpoint at most;
	# difficulty may lower that cap now and leaves room for larger maps to grow
	# into the original multi-refuge budget later.
	var safe_zone_count := mini(
		GameConfig.FACILITY_SAFE_ZONE_COUNT,
		GameConfig.safe_zone_limit_for(difficulty_id()))
	options["safe_zone_count"] = safe_zone_count
	options["safe_zone_at_spawn"] = safe_zone_count > 0
	return options


func set_mode(value: Mode) -> void:
	if online and not is_host:
		owner_send("mode", {"value": int(value)})
		return
	if mode == value or not mode_available(value):
		return
	mode = value
	broadcast()
	changed.emit()


func set_map_scale(value: Scale) -> void:
	if online and not is_host:
		owner_send("map_scale", {"value": int(value)})
		return
	if map_scale == value or not map_scale_available(value):
		return
	map_scale = value
	broadcast()
	changed.emit()


func map_scale_available(value: int) -> bool:
	return value == Scale.STANDARD or value == Scale.INFINITE


func set_difficulty(value: Difficulty) -> void:
	if online and not is_host:
		owner_send("difficulty", {"value": int(value)})
		return
	if not difficulty_available(value) or difficulty == value:
		return
	difficulty = value
	broadcast()
	changed.emit()


func set_npc_teammates(value: int) -> void:
	if online and not is_host:
		return
	npc_teammates = NpcTeammates.clamp_count(value)
	changed.emit()


func difficulty_id() -> String:
	return String(DIFFICULTY_IDS.get(difficulty, "standard"))


func difficulty_profile() -> Dictionary:
	return GameConfig.difficulty_profile(difficulty_id())


static func _selectable_difficulty_or_standard(value: int) -> int:
	return value if value in [Difficulty.RELAXED, Difficulty.STANDARD,
		Difficulty.HARD, Difficulty.NIGHTMARE] else Difficulty.STANDARD


## Leave staging and start the run this room describes.
##
## The room seeds GameState rather than the mode scene seeding itself, so two
## players entering the same room get the same building -- which is the part
## that has to be true before any networking is worth writing.
func enter(tree: SceneTree) -> void:
	if _hosted_join_pending:
		return   # the hosted room is not listed yet, or this client has not joined it
	if connecting:
		return
	if online and not is_host:
		owner_send("start")   # the room owner asks the dedicated host to start; everyone else waits (no-op for guests)
		return
	if online and is_host and Backend.configured() and not Backend.registered:
		status_message = "WAITING FOR PRIMARY SERVER TO LIST THIS ROOM"
		changed.emit()
		return
	if not mode_available(mode):
		status_message = mode_unavailable_reason(mode)
		changed.emit()
		return
	var pack_error := RoomPacks.host_load(public_route)
	if not pack_error.is_empty():
		status_message = pack_error
		changed.emit()
		return
	session_active = true
	status_message = "ROUTE IN PROGRESS"
	broadcast()
	Backend.update_room(peers.size(), session_active)
	if online:
		NetPeers.send_all(multiplayer, _receive_daytime, [daytime])
		NetPeers.send_all(multiplayer, _receive_start, [code, seed_text, mode, map_scale, difficulty])
	_enter_session_scene(tree)


## Host-owned synchronized scene start. It lives on the autoload rather than
## the lobby so the RPC path exists before, during and after scene changes.
@rpc("authority", "call_remote", "reliable")
func _receive_start(p_code: String, p_seed: String, p_mode: int, p_scale: int,
		p_difficulty: int) -> void:
	if reconnect_active and (p_code != code or Time.get_ticks_msec() >= _reconnect_deadline_msec):
		return
	code = p_code
	seed_text = p_seed
	mode = p_mode
	map_scale = p_scale
	difficulty = _selectable_difficulty_or_standard(p_difficulty)
	session_active = true
	status_message = "ROUTE IN PROGRESS"
	if reconnect_active:
		_reconnect_room_received = true
	changed.emit()
	call_deferred("_enter_received_session", _reconnect_generation, code)


func _enter_session_scene(tree: SceneTree) -> void:
	if _scene_transitions_suppressed_for_tests or not _packs_waiting.is_empty():
		return
	var path := session_scene_path()
	if tree.current_scene != null and tree.current_scene.scene_file_path in [
			path, ROUTE_LOADING_SCENE]:
		return
	# Resource dependencies are loaded on the worker thread by the intermediate
	# scene. Main3D then keeps the same visual over a joining guest until her
	# authoritative host snapshot is installed.
	XRFade.change_scene(tree, ROUTE_LOADING_SCENE)


## The two-process ENet harness verifies the start RPC while deliberately
## remaining in its tiny transport scene. Debug-only and absent from all UI.
func suppress_scene_transitions_for_tests() -> void:
	assert(OS.is_debug_build())
	_scene_transitions_suppressed_for_tests = true


## The game this room belongs to; sent with the directory registration and checked when a code is resolved.
func game_id() -> String:
	return GAME_LAST_ROUTE


## The always-open shared route code of a game (the backend keeps one public route per game id).
func public_code() -> String:
	return PUBLIC_CODE


func is_city() -> bool:
	return false   # KYTTU: The City is archived


## Where "back" goes for this room's game: that game's own menu (Last Route's title menu, main_menu.tscn), so leaving staging
## or a route lands on the game, not the general games hub. Falls back to the hub for a game without a menu scene.
func menu_scene_path() -> String:
	var game := GameRegistry.get_game(game_id())
	var scene := String(game.get("scene", "")) if not game.is_empty() else ""
	Settings.hub_last_game = game_id()   # the hub opens on this game's card if the player goes on to it
	return scene if not scene.is_empty() and ResourceLoader.exists(scene) else GameRegistry.HUB_SCENE


## "BACK TO LAST ROUTE": the label of the back button that returns to menu_scene_path().
func menu_back_label() -> String:
	var game := GameRegistry.get_game(game_id())
	var title := String(game.get("title", "")).trim_prefix("THE ").trim_prefix("KYTTU: ") if not game.is_empty() else ""
	return "BACK TO %s" % title if not title.is_empty() else "BACK"


## Directory answers from servers that predate the `game` field are Last Route rooms.
static func game_matches(room_game: String, expected: String) -> bool:
	return (room_game if not room_game.is_empty() else GAME_LAST_ROUTE) == expected


func session_scene_path() -> String:
	if map_scale == Scale.INFINITE:
		return "res://game/infinite_route/infinite_route_test.tscn"
	return "res://game/infinite_route/infinite_route_test.tscn"


## The host can end a run without destroying the room. Guests stay connected
## and all peers return to staging together; a guest leaving on her own closes
## only her connection instead (handled by main_3d.gd).
func end_session(reason: String = "ROUTE ENDED // RETURNED TO STAGING") -> void:
	if online and not is_host:
		return
	if online:
		NetPeers.send_all(multiplayer, _receive_end, [reason])
	_receive_end(reason)


@rpc("authority", "call_remote", "reliable")
func _receive_end(reason: String) -> void:
	session_active = false
	status_message = reason
	if online and is_host:
		Backend.update_room(peers.size(), session_active)
	changed.emit()
	call_deferred("_return_to_staging")


## Validators set this so a leave can be checked without swapping out the validation scene.
var skip_scene_changes_for_test := false
const HOST_LEFT_NOTICE := "HOST LEFT THE ROOM // BACK AT THE MAIN MENU"
## One-shot line the main menu shows after a guest left a room (their own exit, or the host going away).
var menu_notice := ""


## The host leaving or quitting CLOSES the room (ending a run only returns to staging): guests are told, the server is told to drop
## it (leave_network -> Backend.unregister_room, sent before ENet closes), and the host's own room state is replaced by a fresh local one.
## The relay says the host quit or crashed (a HOST_LEFT frame): a guest goes to the main menu at once, without the reconnect grace
## that a plain connection drop gets.
func _on_relay_host_left(_message: String) -> void:
	if is_host or (not online and not reconnect_active):
		return
	leave_room_to_menu(HOST_LEFT_NOTICE)


func close_room() -> void:
	if online and is_host and _peer != null:
		_receive_room_closed.rpc(HOST_LEFT_NOTICE)
		_peer.poll()
	reset_after_leaving("")


@rpc("authority", "call_remote", "reliable")
func _receive_room_closed(reason: String) -> void:
	if is_host:
		return
	leave_room_to_menu(reason if not reason.is_empty() else HOST_LEFT_NOTICE)


## Quitting while hosting: the same close, then a short wait so the server really receives it before the process ends.
func close_room_for_quit() -> void:
	if online and is_host:
		close_room()
		await Backend.wait_for_room_close()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and online and is_host:
		close_room()


## A guest's way out of a co-op room: unregister from the host, close ENet/relay, unload the room's packs, replace the joined room
## with a fresh local one (no stale code, seed or roster) and land on the main menu with `notice`. The host keeps the staging flow.
func leave_room_to_menu(notice: String = "") -> void:
	_cancel_hosted_join()
	reset_after_leaving(notice)
	if skip_scene_changes_for_test:
		return
	var tree := get_tree()
	if tree == null:
		return
	XRFade.change_scene(tree, menu_scene_path())


## The state half of leave_room_to_menu (no scene change), so it can be checked on its own.
func reset_after_leaving(notice: String = "") -> void:
	var for_mode := mode
	leave_network()
	create_local(for_mode)
	menu_notice = notice
	status_message = ""


func consume_menu_notice() -> String:
	var notice := menu_notice
	menu_notice = ""
	return notice


func _return_to_staging() -> void:
	if _scene_transitions_suppressed_for_tests:
		return
	var tree := get_tree()
	if tree == null:
		return
	if tree.current_scene != null \
			and tree.current_scene.scene_file_path == "res://game/menus/room_lobby.tscn":
		return
	XRFade.change_scene(tree, "res://game/menus/room_lobby.tscn")


static func _make_code() -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return out


## A callsign in the web build's shape -- QUIET-EYE-307. Signed-in accounts
## use their canonical uppercase username; guests draw from the larger FIRST
## and LAST signal-name pools above.
static func _make_callsign() -> String:
	if Backend.signed_in():
		return Backend.account_username
	return _random_guest_callsign()


## A guest's name: one letter, a dash and four digits ("R-4821", GuestNames), kept per device. The server makes it unique
## (Backend.request_guest_name); until it answers, and offline, the local one stands.
static func _random_guest_callsign() -> String:
	if not GuestNames.valid(Settings.guest_name):
		Settings.set_guest_name(GuestNames.random_name(), "")
	return Settings.guest_name



# --- deliberate host handoff (docs/HOST_HANDOFF.md, game/network/host_handoff.gd) ----
##
## Old host: PREPARING (guests freeze + ack: the barrier) -> checkpoint to the successor -> RELEASING (relay commit)
##   -> leaves WITHOUT unregistering on a confirmed or ambiguous commit; a refusal resumes hosting (pre-commit).
## Successor: SUCCESSOR_ARMED (frozen, checkpoint validated) -> HOST_PROMOTE -> SUCCESSOR_ADOPTING (fresh ENet server
##   as peer 1 on the same relay socket, no gameplay) -> relay HOST_ACK -> SUCCESSOR_RELOADING (route scene rebuilt
##   from the checkpoint as authority) -> NONE. No relay ACK in time: the room is closed, never a guessed election.
## Other guests: GUEST_WAITING (frozen) -> relay "ready" -> the ordinary bounded reconnect (longer grace), resume proof,
##   committed snapshot from the new peer 1.
## Host crash/quit and HOST_LEFT still close the room; PublicRoute, direct-LAN and WebSocket rooms never take this path.
enum Handoff { NONE, PREPARING, RELEASING, SUCCESSOR_ARMED, SUCCESSOR_ADOPTING, SUCCESSOR_RELOADING, GUEST_WAITING }

const HANDOFF_BARRIER_MSEC := 4_000
const HANDOFF_SETTLE_MSEC := 300
const HANDOFF_CHECKPOINT_MSEC := 6_000
## Covers the relay's 20 s handoff deadline: a guest that hears nothing by then unfreezes (or the closure reaches it).
const HANDOFF_GUEST_WAIT_MSEC := 25_000
const HANDOFF_ADOPT_MSEC := 8_000
## The successor rebuilds its route scene before it can answer snapshots, so the post-handoff reconnect gets longer than
## the 8 s ordinary drop grace. Tune from measurements (design: do not copy the 8 s blindly).
const HANDOFF_RECONNECT_GRACE_MSEC := 20_000
const HANDOFF_REBIND_MSEC := 30_000
const HANDOFF_PORT_ATTEMPTS := 16
const HANDOFF_UNSUPPORTED := "HOST TRANSFER IS ONLY SUPPORTED FOR PRIVATE ROOMS ON THE GAMEPLAY RELAY"

var handoff_phase: Handoff = Handoff.NONE
## The last handoff result on this client ("" none): the old host's commit/cancel line, kept past the menu's notice.
var last_handoff_outcome := ""
var handoff_epoch := 0
var _handoff_deadline_msec := 0
var _handoff_candidate := 0
var _handoff_acks := {}
var _handoff_barrier_done_msec := 0
var _handoff_checkpoint_sent := false
## host: peer id -> {"version", "session", "order"} from _handoff_hello
var _handoff_capable := {}
var _handoff_hello_order := 0
## host: peer id -> sha256 of the resume secret it issued (or verified) for that runner
var _resume_hashes := {}
## guest: this runner's host-issued resume secret (memory only; never logged, saved or broadcast)
var _resume_secret := ""
## successor-to-be: the validated checkpoint for handoff_epoch
var _handoff_envelope := {}
var _handoff_successor_payload := {}
## successor: resume hash -> old peer id still waiting for its runner, and the deadline for it
var _handoff_pending_identity := {}
var _handoff_rebind_deadline_msec := 0
var _handoff_rebinds_queued: Array = []
var _handoff_reconnect := false
var _handoff_old_link_lost := false


func handoff_freezes_input() -> bool:
	return handoff_phase != Handoff.NONE


## The retained guest scene of a successor (before its rebuild) is not authority: no hunter simulation, no snapshots.
func handoff_blocks_authority() -> bool:
	return handoff_phase in [Handoff.SUCCESSOR_ADOPTING, Handoff.SUCCESSOR_RELOADING]


func handoff_supported() -> String:
	if not online or not is_host:
		return "ONLY THE HOST CAN HAND OVER THE ROOM"
	if public_route:
		return HANDOFF_UNSUPPORTED
	if _peer == null or not _peer is ENetMultiplayerPeer or _relay == null or _relay.mode != RELAY_TUNNEL_SCRIPT.Mode.HOST \
			or not Backend.registered:
		return HANDOFF_UNSUPPORTED
	return ""


func _gameplay_session() -> Node:
	var tree := get_tree()
	return tree.get_first_node_in_group("gameplay_session") if tree != null else null


## Old host: start a deliberate handoff. "" when the barrier started; otherwise why not (and nothing changed).
func begin_host_handoff() -> String:
	var unsupported := handoff_supported()
	if not unsupported.is_empty():
		return unsupported
	if handoff_phase != Handoff.NONE:
		return "A HOST TRANSFER IS ALREADY IN PROGRESS"
	if session_active:
		var scene := _gameplay_session()
		if scene == null or not scene.has_method("build_handoff_world"):
			return "THE ROUTE CANNOT BE CHECKPOINTED RIGHT NOW"
		var blocker := String(scene.call("handoff_blocker")) if scene.has_method("handoff_blocker") else ""
		if not blocker.is_empty():
			return "TRANSFER DEFERRED // %s" % blocker
	var candidate := handoff_candidate()
	if candidate <= 1:
		return "NO GUEST IN THIS ROOM CAN TAKE OVER AS HOST"
	handoff_epoch += 1
	_handoff_candidate = candidate
	_handoff_acks = {}
	_handoff_barrier_done_msec = 0
	_handoff_checkpoint_sent = false
	handoff_phase = Handoff.PREPARING
	_handoff_deadline_msec = Time.get_ticks_msec() + HANDOFF_BARRIER_MSEC
	status_message = "HOST TRANSFER // HOLDING THE ROUTE FOR %s" % String(peers.get(candidate, "SIGNAL"))
	NetPeers.send_all(multiplayer, _handoff_prepare, [handoff_epoch, candidate])
	handoff_changed.emit()
	changed.emit()
	return ""


## The capable guest that connected first (relay session known, current protocol). 0 when there is none.
func handoff_candidate() -> int:
	var best := 0
	var best_order := 0
	for peer_value in _handoff_capable:
		var peer := int(peer_value)
		var info: Dictionary = _handoff_capable[peer_value]
		if peer <= 1 or not peers.has(peer) or int(info.get("version", 0)) != HOST_HANDOFF_SCRIPT.VERSION \
				or int(info.get("session", 0)) <= 0 or not _resume_hashes.has(peer):
			continue
		if multiplayer.multiplayer_peer != null and not NetPeers.is_live(multiplayer, peer):
			continue
		if best == 0 or int(info.get("order", 0)) < best_order:
			best = peer
			best_order = int(info.get("order", 0))
	return best


func _tick_handoff() -> void:
	var now := Time.get_ticks_msec()
	if not _handoff_pending_identity.is_empty() and now >= _handoff_rebind_deadline_msec:
		for hash_value in _handoff_pending_identity.keys():
			_emit_rebind(int(_handoff_pending_identity[hash_value]), 0)
		_handoff_pending_identity.clear()
	match handoff_phase:
		Handoff.PREPARING:
			_tick_handoff_barrier(now)
		Handoff.SUCCESSOR_ARMED, Handoff.GUEST_WAITING:
			if now >= _handoff_deadline_msec:
				if _handoff_old_link_lost:
					_clear_handoff("")
					_close_failed_connection(HOST_LEFT_NOTICE, true)
				else:
					_clear_handoff("HOST TRANSFER DID NOT COMPLETE // ROUTE CONTINUES")
		Handoff.SUCCESSOR_ADOPTING:
			if now >= _handoff_deadline_msec:
				_fail_successor("HOST TRANSFER FAILED // ROOM CLOSED")


func _tick_handoff_barrier(now: int) -> void:
	if not online or not is_host:
		_clear_handoff("")
		return
	var waiting := false
	for peer_value in peers:
		if int(peer_value) > 1 and not _handoff_acks.has(int(peer_value)):
			waiting = true
	if waiting or not peers.has(_handoff_candidate):
		if now >= _handoff_deadline_msec or not peers.has(_handoff_candidate):
			_abort_handoff("A RUNNER DID NOT ANSWER THE TRANSFER")
		return
	if _handoff_barrier_done_msec == 0:
		_handoff_barrier_done_msec = now   # everyone is frozen; let requests already in flight land first
		return
	if _handoff_checkpoint_sent or now - _handoff_barrier_done_msec < HANDOFF_SETTLE_MSEC:
		if _handoff_checkpoint_sent and now >= _handoff_deadline_msec:
			_abort_handoff("THE NEW HOST DID NOT CONFIRM THE CHECKPOINT")
		return
	var envelope := build_handoff_envelope()
	if envelope.is_empty():
		_abort_handoff("THE ROUTE COULD NOT BE CHECKPOINTED")
		return
	_handoff_checkpoint_sent = true
	_handoff_deadline_msec = now + HANDOFF_CHECKPOINT_MSEC
	_handoff_checkpoint.rpc_id(_handoff_candidate, envelope)


func build_handoff_envelope() -> Dictionary:
	var world := {}
	if session_active:
		var scene := _gameplay_session()
		if scene == null or not scene.has_method("build_handoff_world"):
			return {}
		world = scene.call("build_handoff_world")
		if world.is_empty():
			return {}
	var identity := {}
	for peer_value in peers:
		var peer := int(peer_value)
		if peer > 1 and _resume_hashes.has(peer):
			identity[String(_resume_hashes[peer])] = peer
	return HOST_HANDOFF_SCRIPT.build_envelope(code, seed_text, run_seed(), handoff_epoch,
		ContentRegistry.pack_hash(), _handoff_candidate, identity, Backend.reserved_command_cursor(), world) \
		.merged({"session_active": session_active}, true)


func _abort_handoff(reason: String) -> void:
	var epoch := handoff_epoch
	if online and is_host:
		NetPeers.send_all(multiplayer, _handoff_abort, [epoch, reason])
	last_handoff_outcome = "HOST TRANSFER CANCELLED // %s // YOU ARE STILL HOSTING" % reason
	_clear_handoff(last_handoff_outcome)


func _clear_handoff(message: String) -> void:
	var was := handoff_phase
	handoff_phase = Handoff.NONE
	_handoff_deadline_msec = 0
	_handoff_candidate = 0
	_handoff_acks = {}
	_handoff_barrier_done_msec = 0
	_handoff_checkpoint_sent = false
	_handoff_envelope = {}
	_handoff_successor_payload = {}
	if _relay != null and _relay.mode == RELAY_TUNNEL_SCRIPT.Mode.GUEST:
		_relay.arm_handoff(0)
	if not message.is_empty():
		status_message = message
	if was != Handoff.NONE:
		handoff_changed.emit()
		changed.emit()


func _reset_handoff_identity() -> void:
	_clear_handoff("")
	_handoff_capable = {}
	_handoff_hello_order = 0
	_resume_hashes = {}
	_resume_secret = ""
	_handoff_pending_identity = {}
	_handoff_rebind_deadline_msec = 0
	_handoff_rebinds_queued = []
	_handoff_reconnect = false


## Guest -> host, after every (re)connect: this build speaks handoff VERSION and holds relay `session` (0 = none).
@rpc("any_peer", "call_remote", "reliable")
func _handoff_hello(version: int, session: int) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1 or not peers.has(id):
		return
	_handoff_hello_order += 1
	_handoff_capable[id] = {"version": version, "session": maxi(0, session), "order": _handoff_hello_order}


## Host -> one guest: its room-scoped resume secret.
@rpc("authority", "call_remote", "reliable")
func _handoff_issue_resume(secret: String) -> void:
	if is_host or HOST_HANDOFF_SCRIPT.resume_hash(secret).is_empty():
		return
	_resume_secret = secret


## Guest -> host: proof of a resume identity issued earlier (by this host, or by the old host via the checkpoint).
@rpc("any_peer", "call_remote", "reliable")
func _handoff_present_resume(secret: String) -> void:
	if not is_host:
		return
	var id := multiplayer.get_remote_sender_id()
	if id <= 1:
		return
	accept_resume_proof(id, secret)


## Host side of a resume proof (validators call it directly). True when `peer` now owns that identity.
func accept_resume_proof(peer: int, secret: String) -> bool:
	var proof: String = HOST_HANDOFF_SCRIPT.resume_hash(secret)
	if proof.is_empty():
		return false
	if _handoff_pending_identity.has(proof):
		var old_peer := int(_handoff_pending_identity[proof])
		_handoff_pending_identity.erase(proof)
		_resume_hashes[peer] = proof
		_emit_rebind(old_peer, peer)
		return true
	for other in _resume_hashes.keys():
		if String(_resume_hashes[other]) == proof:
			if int(other) != peer and peers.has(int(other)) and NetPeers.is_live(multiplayer, int(other)):
				return false   # the identity is held by a live runner: a copied secret cannot take it over
			_resume_hashes.erase(other)
			_resume_hashes[peer] = proof
			return true
	return false


func _emit_rebind(old_peer: int, new_peer: int) -> void:
	if handoff_peer_rebound.get_connections().is_empty():
		_handoff_rebinds_queued.append([old_peer, new_peer])
	else:
		handoff_peer_rebound.emit(old_peer, new_peer)


## The successor's rebuilt route scene takes the rebinds that happened while it was loading.
func take_handoff_rebinds() -> Array:
	var queued := _handoff_rebinds_queued
	_handoff_rebinds_queued = []
	return queued


## Host -> every guest: freeze for handoff `epoch`; `successor` is who will be promoted.
@rpc("authority", "call_remote", "reliable")
func _handoff_prepare(epoch: int, successor: int) -> void:
	if is_host or not online or epoch <= handoff_epoch:
		return
	_handoff_old_link_lost = false
	handoff_epoch = epoch
	_handoff_envelope = {}
	handoff_phase = Handoff.SUCCESSOR_ARMED if successor == multiplayer.get_unique_id() else Handoff.GUEST_WAITING
	_handoff_deadline_msec = Time.get_ticks_msec() + HANDOFF_GUEST_WAIT_MSEC
	if _relay != null and _relay.mode == RELAY_TUNNEL_SCRIPT.Mode.GUEST:
		_relay.arm_handoff(epoch)
	status_message = "HOST TRANSFER // HOLD ON" if handoff_phase == Handoff.GUEST_WAITING \
		else "HOST TRANSFER // YOU ARE TAKING OVER THE ROOM"
	_handoff_prepared.rpc_id(1, epoch)
	handoff_changed.emit()
	changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func _handoff_prepared(epoch: int) -> void:
	if not is_host or handoff_phase != Handoff.PREPARING or epoch != handoff_epoch:
		return
	var id := multiplayer.get_remote_sender_id()
	if id > 1 and peers.has(id):
		_handoff_acks[id] = true


## Host -> successor only: the checkpoint. Validated before it is acknowledged; nothing is installed until promotion.
@rpc("authority", "call_remote", "reliable")
func _handoff_checkpoint(envelope: Dictionary) -> void:
	var reason := receive_handoff_checkpoint(envelope)
	if online and not is_host:
		_handoff_checkpoint_result.rpc_id(1, int(envelope.get("epoch", 0)), reason.is_empty(), reason)


## Successor side of the checkpoint (validators call it directly). "" when stored.
func receive_handoff_checkpoint(envelope: Dictionary) -> String:
	if is_host or handoff_phase != Handoff.SUCCESSOR_ARMED:
		return "NOT THE CHOSEN SUCCESSOR"
	var reason: String = HOST_HANDOFF_SCRIPT.validate_envelope(envelope, {
		"code": code, "run_seed": run_seed(), "epoch": handoff_epoch,
		"pack_hash": ContentRegistry.pack_hash(), "successor_old_peer": multiplayer.get_unique_id()})
	if reason.is_empty() and bool(envelope.get("session_active", false)) != session_active:
		reason = "HANDOFF CHECKPOINT ROUTE STATE DIFFERS"
	if reason.is_empty() and session_active:
		var scene := _gameplay_session()
		if scene == null or not scene.has_method("handoff_local_player"):
			reason = "THE ROUTE IS NOT READY TO TAKE OVER"
	if not reason.is_empty():
		return reason
	_handoff_envelope = envelope.duplicate(true)
	return ""


@rpc("any_peer", "call_remote", "reliable")
func _handoff_checkpoint_result(epoch: int, accepted: bool, reason: String) -> void:
	if not is_host or handoff_phase != Handoff.PREPARING or epoch != handoff_epoch \
			or multiplayer.get_remote_sender_id() != _handoff_candidate:
		return
	if not accepted:
		_abort_handoff(reason.substr(0, 80))
		return
	var info: Dictionary = _handoff_capable.get(_handoff_candidate, {})
	handoff_phase = Handoff.RELEASING
	Backend.hold_heartbeat_for_handoff(true)   # a 403 after the rotation must not re-register this code
	status_message = "HOST TRANSFER // HANDING THE ROOM OVER"
	changed.emit()
	Backend.release_host_handoff(int(info.get("session", 0)), handoff_epoch, _on_handoff_released.bind(handoff_epoch))


func _on_handoff_released(result: Dictionary, epoch: int) -> void:
	if handoff_phase != Handoff.RELEASING or epoch != handoff_epoch:
		return
	if bool(result.get("migrating", false)):
		_finish_as_old_host("HOST HANDED OVER // THE ROUTE CONTINUES WITHOUT YOU")
	elif bool(result.get("unknown", false)):
		# the token may already be rotated: two hosts must never exist, so this one steps away
		_finish_as_old_host("HOST TRANSFER UNCONFIRMED // YOU LEFT THE ROOM")
	else:
		Backend.hold_heartbeat_for_handoff(false)
		_abort_handoff(String(result.get("error", "THE SERVER REFUSED THE TRANSFER")))


## Committed (or ambiguous): leave WITHOUT unregistering -- the code now belongs to the successor's token.
func _finish_as_old_host(notice: String) -> void:
	last_handoff_outcome = notice
	Backend.relinquish_host_after_handoff()
	_clear_handoff("")
	if dedicated:
		dedicated = false
		leave_network()
		get_tree().quit(0)
		return
	leave_room_to_menu(notice)


## Host -> guests: the barrier failed before commit; the old host carries on.
@rpc("authority", "call_remote", "reliable")
func _handoff_abort(epoch: int, reason: String) -> void:
	if is_host or epoch != handoff_epoch or handoff_phase not in [Handoff.SUCCESSOR_ARMED, Handoff.GUEST_WAITING]:
		return
	_clear_handoff("HOST TRANSFER CANCELLED // %s" % reason)


func _on_relay_host_promoted(epoch: int, token: String) -> void:
	if is_host or handoff_phase != Handoff.SUCCESSOR_ARMED or epoch != handoff_epoch or _handoff_envelope.is_empty():
		return
	var error := _adopt_promoted_host(token)
	if not error.is_empty():
		_fail_successor("HOST TRANSFER FAILED // %s" % error)


func _on_relay_host_migrating(epoch: int, ready: bool) -> void:
	if is_host or epoch != handoff_epoch or handoff_phase != Handoff.GUEST_WAITING:
		return
	if not ready:
		status_message = "HOST TRANSFER // WAITING FOR THE NEW HOST"
		changed.emit()
		return
	_start_handoff_reconnect()


## A waiting guest reconnects through the ordinary bounded path (room lookup, fresh tunnel, resume proof, snapshot).
func _start_handoff_reconnect() -> void:
	_clear_handoff("")
	_handoff_reconnect = true
	_start_reconnect_grace()
	_reconnect_deadline_msec = Time.get_ticks_msec() + HANDOFF_RECONNECT_GRACE_MSEC
	status_message = "NEW HOST READY // RECONNECTING"
	changed.emit()


## Successor: fresh ENet server as peer 1 behind the same relay socket, the rotated token, the checkpoint's cursor.
## Gameplay stays frozen (SUCCESSOR_ADOPTING) until the relay acknowledges the registration.
func _adopt_promoted_host(token: String) -> String:
	var payload := {}
	if session_active:
		var scene := _gameplay_session()
		if scene == null or not scene.has_method("handoff_local_player"):
			return "THE ROUTE IS NOT READY"
		payload = HOST_HANDOFF_SCRIPT.successor_payload(_handoff_envelope, scene.call("handoff_local_player"))
		if not RunSaves.payload_valid(payload):
			return "THE CHECKPOINT COULD NOT BE INSTALLED"
	var server := ENetMultiplayerPeer.new()
	var port := 0
	for attempt in HANDOFF_PORT_ATTEMPTS:
		if server.create_server(DEFAULT_PORT + attempt, MAX_PLAYERS) == OK:
			port = DEFAULT_PORT + attempt
			break
		server = ENetMultiplayerPeer.new()
	if port == 0:
		return "NETWORK PORT UNAVAILABLE"
	var my_old_id := multiplayer.get_unique_id()
	var promote_error: String = _relay.promote_to_host(token, port)
	if not promote_error.is_empty():
		server.close()
		return promote_error
	# the old client link is dead (the relay already dropped the old host); its last datagrams are ignored now
	if _peer != null:
		_peer.close()
	_peer = server
	multiplayer.multiplayer_peer = _peer
	_bind_signals()
	_host_port = port
	online = true
	connecting = false
	is_host = true
	peers = {1: _local_name()}
	_handoff_capable = {}
	_resume_hashes = {}
	_resume_secret = ""
	_handoff_pending_identity = {}
	var identity: Dictionary = _handoff_envelope.get("identity", {})
	for proof in identity:
		if int(identity[proof]) != my_old_id:
			_handoff_pending_identity[String(proof)] = int(identity[proof])
	_handoff_rebind_deadline_msec = Time.get_ticks_msec() + HANDOFF_REBIND_MSEC
	_handoff_successor_payload = payload
	handoff_phase = Handoff.SUCCESSOR_ADOPTING
	_handoff_deadline_msec = Time.get_ticks_msec() + HANDOFF_ADOPT_MSEC
	Backend.adopt_promoted_host(code, token, String(_relay.relay_address), int(_relay.relay_port), port,
		1, session_active, int(_handoff_envelope.get("reserved_seq", 0)))
	status_message = "HOST TRANSFER // TAKING OVER THE ROOM"
	handoff_changed.emit()
	changed.emit()
	return ""


func _complete_successor() -> void:
	var payload := _handoff_successor_payload
	_handoff_envelope = {}
	_handoff_successor_payload = {}
	_handoff_deadline_msec = 0
	status_message = "YOU ARE NOW HOSTING THIS ROOM"
	if session_active and not payload.is_empty():
		handoff_phase = Handoff.SUCCESSOR_RELOADING
		RunSaves.queue_handoff(payload)
		handoff_changed.emit()
		changed.emit()
		broadcast()
		if not _scene_transitions_suppressed_for_tests and get_tree() != null:
			XRFade.change_scene(get_tree(), ROUTE_LOADING_SCENE)   # rebuilt as authority from the checkpoint
		return
	handoff_phase = Handoff.NONE
	broadcast()
	handoff_changed.emit()
	changed.emit()


## The successor's rebuilt route scene calls this at the end of _ready: simulation and snapshots resume.
func finish_handoff_scene() -> void:
	if handoff_phase != Handoff.SUCCESSOR_RELOADING:
		return
	handoff_phase = Handoff.NONE
	handoff_changed.emit()
	changed.emit()


## Before commit nothing changed; after promotion the room cannot fall back to anyone: close it (the new token's
## unregister tells every guest) instead of guessing another host.
func _fail_successor(reason: String) -> void:
	_clear_handoff("")
	RunSaves.clear_pending()
	leave_room_to_menu(reason)
