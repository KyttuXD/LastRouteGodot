extends Node

const RELAY_TUNNEL_SCRIPT := preload("res://src/network/enet_relay_tunnel.gd")
const WS_PEER_SCRIPT := preload("res://src/network/ws_room_peer.gd")
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

## KYTTU: The City used to be Mode 1; it was archived (branch archive/city-20261027).
enum Mode { DEFAULT }
## SPRAWLING and CAVERNOUS merged into one top tier, IMMENSE -- two "big"
## steps that only differed by how big, with nothing else changing between
## them, was a choice that cost more attention at the lobby than it earned.
## Not named LARGE: that name was already taken by the tier below it, and
## renaming an existing tier just to free the word felt like a bigger change
## than "merge the two biggest" asked for.
enum Scale { SMALL, STANDARD, LARGE, IMMENSE, INFINITE }
## Nightmare is intentionally visible but not selectable. Its eventual design
## includes a larger active hunter lineup, so the disabled label can advertise
## the plan without exposing an incomplete simulation/co-op ruleset.
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
const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
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
const DIFFICULTY_BLURBS := {
	Difficulty.RELAXED: "Plain hunters: no extra abilities, longer clocks.",
	Difficulty.STANDARD: "Hunters work together, with the odd pounce, burst or flank (very rare).",
	Difficulty.HARD: "Hunters pounce, burst, flank and slam doors, and search harder.",
	Difficulty.NIGHTMARE: "Full hunter abilities: pounces, ambushes, flanking teams, shrugging off torches.",
}
const DIFFICULTY_IDS := {
	Difficulty.RELAXED: "relaxed", Difficulty.STANDARD: "standard",
	Difficulty.HARD: "hard", Difficulty.NIGHTMARE: "nightmare",
}

## Anonymous room guests use a two-word signal callsign. Keeping the words as
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

## Which scene each mode opens. The route now includes office-region rooms and
## Office Mode is available as the focused single-runner shift; a future pass
## can move the shared simulation into a route room without changing staging.
const MODE_SCENES := {
	Mode.DEFAULT: "res://scenes/main_3d.tscn",
}
const ROUTE_LOADING_SCENE := "res://scenes/route_loading.tscn"

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
## Display names, host first. One entry while offline.
var players: PackedStringArray = []
## True after an ENet room handshake (or immediately for its host).
var online := false
var is_host := true
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
var _relay: Node
var _relay_status := ""
var _directory_status := ""
var reconnect_active := false
var _reconnect_deadline_msec := 0
var _reconnect_next_lookup_msec := 0
var _reconnect_request_in_flight := false
## CREATE ROOM uses this only until its first successful directory listing.
## If the primary service cannot accept the room, the staging screen remains
## usable as solo instead of waiting forever behind an online-only button.
var _primary_create_fallback_enabled := false
var _scene_transitions_suppressed_for_tests := false
## The host's pack announcement while this guest is still confirming or downloading packs ({} when none): the guest
## stays in staging until RoomPacks.adopt() succeeds.
var _packs_waiting := {}


func uses_ws_transport() -> bool:
	return OS.has_feature("web") or prefer_ws_rooms or (public_route and PUBLIC_ROUTE_USES_WS)


func _ready() -> void:
	prefer_ws_rooms = OS.get_cmdline_user_args().has("--ws-rooms")
	Backend.registration_changed.connect(_on_directory_registration)
	Backend.account_changed.connect(_on_account_changed)
	Backend.room_resolved.connect(_on_room_resolved)
	Backend.reserved_commands_received.connect(_on_reserved_commands)
	_relay = RELAY_TUNNEL_SCRIPT.new()
	_relay.name = "GameplayRelayTunnel"
	_relay.relay_ready.connect(_on_relay_ready)
	_relay.relay_failed.connect(_on_relay_failed)
	_relay.host_left.connect(_on_relay_host_left)
	add_child(_relay)
	PackDownloads.install(self)
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
	if dedicated:
		_tick_dedicated(delta)
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
		error: String) -> void:
	if not reconnect_active or resolved_code != code:
		return
	_reconnect_request_in_flight = false
	if not error.is_empty() or not bool(endpoint.get("sessionActive", true)):
		return
	var join_error := join_room(String(endpoint.get("address", "")),
		int(endpoint.get("port", DEFAULT_PORT)),
		String(endpoint.get("transport", "relay")), resolved_code, true)
	if not join_error.is_empty():
		status_message = "HOST SIGNAL LOST // %s" % join_error
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
			"restart":
				_apply_reserved_settings(args.get("settings", {}), bool(args.get("sameSeed", false)))
				if not bool(args.get("sameSeed", false)) and String((args.get("settings", {}) as Dictionary).get("seed", "")).is_empty():
					reroll_seed()
				if session_active:
					end_session("PRIVATE ROOM // ROUTE RESTARTING")
					get_tree().create_timer(1.5).timeout.connect(func() -> void:
						if online and is_host and not session_active:
							enter(get_tree()))
				else:
					enter(get_tree())
			"end":
				if session_active:
					end_session("PRIVATE ROOM // THE OWNER ENDED THE ROUTE")
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
				# the relay promotes the longest-connected guest (host migration); this client then leaves
				Backend.release_host()
				status_message = "PRIVATE ROOM // HOST HANDED OVER"
				get_tree().create_timer(1.0).timeout.connect(leave_network)
		Backend.ack_reserved_command(int(entry.get("seq", 0)))


## Main-menu CREATE ROOM path: make the ordinary room online automatically.
## A failed initial listing falls back to the already-created solo room; once
## listed, transient heartbeat trouble does not destroy a live co-op session.
func host_primary_room(port: int = DEFAULT_PORT) -> String:
	var error := host_room(port, true)
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


func leave_network() -> void:
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
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	if _relay != null:
		_relay.close()
	online = false
	connecting = false
	_connect_started_msec = 0
	_relay_status = ""
	_directory_status = ""
	_primary_create_fallback_enabled = false
	if reset_room_identity:
		is_host = true
		session_active = false
		peers = {}
		_packs_waiting = {}


func _bind_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_joined)
		multiplayer.connection_failed.connect(_on_connection_failed)
		multiplayer.server_disconnected.connect(_on_server_disconnected)


func _on_peer_connected(id: int) -> void:
	if not is_host:
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
	connecting = false
	_connect_started_msec = 0
	online = true
	if reconnect_active:
		status_message = "RECONNECTED // WAITING FOR HOST SNAPSHOT"
	else:
		status_message = "CONNECTED // WAITING FOR HOST"
	peers[multiplayer.get_unique_id()] = _local_name()
	_register_peer.rpc_id(1, _local_name())
	changed.emit()


func _on_connection_failed() -> void:
	if reconnect_active:
		_close_transport_only(false)
		_reconnect_request_in_flight = false
		_reconnect_next_lookup_msec = Time.get_ticks_msec() + RECONNECT_LOOKUP_INTERVAL_MSEC
		status_message = "HOST SIGNAL LOST // RETRYING ROOM"
		changed.emit()
		return
	_close_failed_connection("ROOM CONNECTION FAILED // TRY THE CODE AGAIN")


func _on_server_disconnected() -> void:
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
		call_deferred("leave_room_to_menu", reason)
		return
	call_deferred("_return_to_staging")


func _start_reconnect_grace() -> void:
	_close_transport_only(false)
	reconnect_active = true
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
	if connecting or _reconnect_request_in_flight or now < _reconnect_next_lookup_msec:
		return
	_reconnect_request_in_flight = true
	_reconnect_next_lookup_msec = now + RECONNECT_LOOKUP_INTERVAL_MSEC
	Backend.resolve_room(code)


func _clear_reconnect_state() -> void:
	reconnect_active = false
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
	var clean := requested_name.strip_edges().to_upper().substr(0, 32)
	# A guest that reconnects after a dropped link arrives as a NEW peer id while
	# its old id lingers until ENet times it out. Same callsign = same runner:
	# retire the stale row so the roster (and the party size) does not double count.
	if not clean.is_empty():
		for old_id in peers.keys().duplicate():
			if int(old_id) != id and int(old_id) > 1 and String(peers[old_id]) == clean:
				peers.erase(old_id)
				if multiplayer.multiplayer_peer != null:
					multiplayer.multiplayer_peer.disconnect_peer(int(old_id))
	peers[id] = clean if not clean.is_empty() else "SIGNAL-%d" % id
	broadcast()
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_room(p_code: String, p_seed: String, p_mode: int, p_scale: int,
		p_difficulty: int, p_peers: Dictionary, p_session_active: bool) -> void:
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
	_clear_reconnect_state()
	changed.emit()
	# Self-heal for the join/start race: a guest that joined while the host was starting can miss the one start RPC
	# (the playtest party saw one of two guests stay in the lobby). Every room update says whether the route is running,
	# so a guest still outside it enters now.
	if online and not is_host and p_session_active and not connecting:
		call_deferred("_enter_session_scene", get_tree())


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
	return DIFFICULTY_LABELS.has(candidate) and candidate != Difficulty.NIGHTMARE


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
		return
	if mode == value or not mode_available(value):
		return
	mode = value
	broadcast()
	changed.emit()


func set_map_scale(value: Scale) -> void:
	if online and not is_host:
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
		return
	# NIGHTMARE stays visible but disabled. Rejecting it here also keeps scripts
	# and stale clients from starting the incomplete multi-hunter ruleset.
	if not difficulty_available(value) or difficulty == value:
		return
	difficulty = value
	broadcast()
	changed.emit()


func difficulty_id() -> String:
	return String(DIFFICULTY_IDS.get(difficulty, "standard"))


func difficulty_profile() -> Dictionary:
	return GameConfig.difficulty_profile(difficulty_id())


static func _selectable_difficulty_or_standard(value: int) -> int:
	return value if value in [Difficulty.RELAXED, Difficulty.STANDARD,
		Difficulty.HARD] else Difficulty.STANDARD


## Leave staging and start the run this room describes.
##
## The room seeds GameState rather than the mode scene seeding itself, so two
## players entering the same room get the same building -- which is the part
## that has to be true before any networking is worth writing.
func enter(tree: SceneTree) -> void:
	if connecting or (online and not is_host):
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
	code = p_code
	seed_text = p_seed
	mode = p_mode
	map_scale = p_scale
	difficulty = _selectable_difficulty_or_standard(p_difficulty)
	session_active = true
	status_message = "ROUTE IN PROGRESS"
	_clear_reconnect_state()
	changed.emit()
	call_deferred("_enter_session_scene", get_tree())


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
		return "res://scenes/infinite_route_test.tscn"
	return "res://scenes/infinite_route_test.tscn"


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
	if is_host or not online:
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
	var tree := get_tree()
	if tree == null:
		return
	if tree.current_scene != null \
			and tree.current_scene.scene_file_path == "res://scenes/room_lobby.tscn":
		return
	XRFade.change_scene(tree, "res://scenes/room_lobby.tscn")


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


static func _random_guest_callsign() -> String:
	return "%s-%s-%d" % [GUEST_FIRST_NAMES[randi() % GUEST_FIRST_NAMES.size()],
		GUEST_LAST_NAMES[randi() % GUEST_LAST_NAMES.size()], 100 + randi() % 900]
