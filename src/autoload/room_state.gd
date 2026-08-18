extends Node

const RELAY_TUNNEL_SCRIPT := preload("res://src/network/enet_relay_tunnel.gd")

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

enum Mode { DEFAULT, HIDE_SEEK, OFFICE }
## SPRAWLING and CAVERNOUS merged into one top tier, IMMENSE -- two "big"
## steps that only differed by how big, with nothing else changing between
## them, was a choice that cost more attention at the lobby than it earned.
## Not named LARGE: that name was already taken by the tier below it, and
## renaming an existing tier just to free the word felt like a bigger change
## than "merge the two biggest" asked for.
enum Scale { SMALL, STANDARD, LARGE, IMMENSE }
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
	# HIDE & SEEK remains a legacy enum for old room packets, but is removed
	# from the selectable UI until its design returns. OFFICE stays visible as
	# a disabled preview so players can see that it is planned.
	Mode.DEFAULT: "DEFAULT", Mode.OFFICE: "OFFICE",
}
const SCALE_LABELS := {
	Scale.SMALL: "SMALL", Scale.STANDARD: "STANDARD", Scale.LARGE: "LARGE",
	Scale.IMMENSE: "IMMENSE",
}
const DIFFICULTY_LABELS := {
	Difficulty.RELAXED: "RELAXED", Difficulty.STANDARD: "STANDARD",
	Difficulty.HARD: "HARD", Difficulty.NIGHTMARE: "NIGHTMARE",
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
	Mode.HIDE_SEEK: "res://scenes/main_3d.tscn",
	Mode.OFFICE: "res://scenes/office_3d.tscn",
}
const ROUTE_LOADING_SCENE := "res://scenes/route_loading.tscn"

var code := ""
## The full route seed, shown on the staging screen and the in-run HUD so two
## players can confirm they are on the same route.
var seed_text := ""
var mode: Mode = Mode.DEFAULT
var map_scale: Scale = Scale.STANDARD
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
var status_message := ""

## Peer id -> callsign. The host is always peer 1. Kept as a dictionary rather
## than a list so a player leaving removes the right row without the others
## shuffling under it.
var peers := {}

const DEFAULT_PORT := 8421
const CONNECTION_TIMEOUT_MSEC := 15_000
## Loopback by default: this exists to test with two windows on one machine
## before there is anything to connect to.
const DEFAULT_ADDRESS := "127.0.0.1"

var _peer: ENetMultiplayerPeer
var _host_port := DEFAULT_PORT
var _connect_started_msec := 0
var _relay: Node
var _relay_status := ""
var _directory_status := ""
## CREATE ROOM uses this only until its first successful directory listing.
## If the primary service cannot accept the room, the staging screen remains
## usable as solo instead of waiting forever behind an online-only button.
var _primary_create_fallback_enabled := false
var _scene_transitions_suppressed_for_tests := false


func _ready() -> void:
	Backend.registration_changed.connect(_on_directory_registration)
	_relay = RELAY_TUNNEL_SCRIPT.new()
	_relay.name = "GameplayRelayTunnel"
	_relay.relay_ready.connect(_on_relay_ready)
	_relay.relay_failed.connect(_on_relay_failed)
	add_child(_relay)
	# A room always exists, so nothing has to null-check it. Landing straight
	# in a mode from the editor gets a valid singleplayer room.
	if code.is_empty():
		create_local(Mode.DEFAULT)


func _process(_delta: float) -> void:
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
	GameState.clear_pending_route_checkpoint()
	code = _make_code()
	mode = for_mode if mode_available(for_mode) else Mode.DEFAULT
	map_scale = Scale.STANDARD
	difficulty = Difficulty.STANDARD
	leave_network()
	session_active = false
	status_message = ""
	players = PackedStringArray([_make_callsign()])
	reroll_seed()
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
	if OS.has_feature("web"):
		return "WEB BUILD IS SOLO // ENET/UDP NEEDS A WEBSOCKET OR WEBRTC TRANSPORT"
	GameState.clear_pending_route_checkpoint()
	leave_network()
	_primary_create_fallback_enabled = fallback_to_solo_on_listing_failure
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		_peer = null
		_primary_create_fallback_enabled = false
		return "COULD NOT CREATE ONLINE ROOM // NETWORK PORT UNAVAILABLE"
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
	Backend.register_room(code, port, peers.size(), session_active)
	changed.emit()
	return ""


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
		transport: String = "direct", room_code: String = "") -> String:
	if OS.has_feature("web"):
		return "WEB BUILD IS SOLO // ENET/UDP NEEDS A WEBSOCKET OR WEBRTC TRANSPORT"
	GameState.clear_pending_route_checkpoint()
	leave_network()
	var trimmed := address.strip_edges()
	if trimmed.is_empty():
		return "ENTER A HOST ADDRESS"
	var connect_address := trimmed
	var connect_port := port
	if transport == "relay":
		connect_port = _relay.start_guest(room_code, trimmed, port)
		if connect_port <= 0:
			return "COULD NOT OPEN GAMEPLAY RELAY TUNNEL"
		connect_address = DEFAULT_ADDRESS
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(connect_address, connect_port)
	if error != OK:
		_peer = null
		return "COULD NOT REACH GAMEPLAY RELAY"
	multiplayer.multiplayer_peer = _peer
	online = false
	connecting = true
	_connect_started_msec = Time.get_ticks_msec()
	_host_port = port
	is_host = false
	session_active = false
	status_message = "JOINING ROOM THROUGH PRIMARY GAMEPLAY RELAY"
	peers = {}
	_bind_signals()
	changed.emit()
	return ""


func leave_network() -> void:
	if online and is_host:
		Backend.unregister_room()
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	if _relay != null:
		_relay.close()
	online = false
	connecting = false
	_connect_started_msec = 0
	is_host = true
	session_active = false
	peers = {}
	_relay_status = ""
	_directory_status = ""
	_primary_create_fallback_enabled = false
	changed.emit()


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
	_receive_room.rpc(code, seed_text, mode, map_scale, difficulty, peers,
		session_active)
	# A room remains joinable while a route is running. The new peer first gets
	# the room seed/config above, then enters the same scene; RemotePlayers asks
	# the host for the current floor snapshot once that fixed RPC path exists.
	if session_active:
		_receive_start.rpc_id(id, code, seed_text, mode, map_scale, difficulty)
	Backend.update_room(peers.size(), session_active)
	changed.emit()


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	if is_host:
		_receive_room.rpc(code, seed_text, mode, map_scale, difficulty, peers,
			session_active)
		Backend.update_room(peers.size(), session_active)
	changed.emit()


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
	status_message = "CONNECTED // WAITING FOR HOST"
	peers[multiplayer.get_unique_id()] = _local_name()
	_register_peer.rpc_id(1, _local_name())
	changed.emit()


func _on_connection_failed() -> void:
	_close_failed_connection("ROOM CONNECTION FAILED // TRY THE CODE AGAIN")


func _on_server_disconnected() -> void:
	_close_failed_connection("HOST DISCONNECTED // RETURNED TO STAGING")


func _close_failed_connection(reason: String) -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	online = false
	connecting = false
	_connect_started_msec = 0
	is_host = true
	session_active = false
	peers = {}
	status_message = reason
	changed.emit()
	connection_lost.emit(reason)
	call_deferred("_return_to_staging")


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
	changed.emit()


## Push the host's configuration to everyone. Called after any host-side change,
## so a client never generates a building from a stale route.
func broadcast() -> void:
	if online and is_host:
		_receive_room.rpc(code, seed_text, mode, map_scale, difficulty, peers,
			session_active)


func _local_name() -> String:
	return String(players[0]) if not players.is_empty() else _make_callsign()


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
	return candidate == Mode.DEFAULT or (candidate == Mode.OFFICE and not online)


func mode_unavailable_reason(candidate: Mode) -> String:
	if candidate == Mode.HIDE_SEEK:
		return "HIDE & SEEK IS REMOVED WHILE ITS RULESET IS REBUILT"
	if candidate == Mode.OFFICE:
		return "OFFICE MODE IS A SINGLE-RUNNER LOCAL SHIFT"
	return ""


func difficulty_available(candidate: Difficulty) -> bool:
	return DIFFICULTY_LABELS.has(candidate) and candidate != Difficulty.NIGHTMARE


## What the button that leaves staging should say, in the web build's words.
func start_label() -> String:
	return "START OFFICE SHIFT" if mode == Mode.OFFICE else "ENTER ROUTE"


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


## Office Mode is singleplayer by design -- the mode is a lone night shift, and
## its whole premise is that there is nobody else to call. It seats one however
## the room was opened.
func seats() -> int:
	return 1 if mode == Mode.OFFICE else MAX_PLAYERS


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
	# A hider cannot be allowed to stand forever in a hunter-proof refuge.
	# Every finite Last Route map currently has one spawn checkpoint at most;
	# difficulty may lower that cap now and leaves room for larger maps to grow
	# into the original multi-refuge budget later.
	var safe_zone_count := 0 if mode == Mode.HIDE_SEEK else mini(
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
	if map_scale == value:
		return
	map_scale = value
	broadcast()
	changed.emit()


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
	session_active = true
	status_message = "ROUTE IN PROGRESS"
	broadcast()
	Backend.update_room(peers.size(), session_active)
	if online:
		_receive_start.rpc(code, seed_text, mode, map_scale, difficulty)
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
	changed.emit()
	call_deferred("_enter_session_scene", get_tree())


func _enter_session_scene(tree: SceneTree) -> void:
	if _scene_transitions_suppressed_for_tests:
		return
	var path := session_scene_path()
	if tree.current_scene != null and tree.current_scene.scene_file_path in [
			path, ROUTE_LOADING_SCENE]:
		return
	# Resource dependencies are loaded on the worker thread by the intermediate
	# scene. Main3D then keeps the same visual over a joining guest until her
	# authoritative host snapshot is installed.
	tree.change_scene_to_file(ROUTE_LOADING_SCENE)


## The two-process ENet harness verifies the start RPC while deliberately
## remaining in its tiny transport scene. Debug-only and absent from all UI.
func suppress_scene_transitions_for_tests() -> void:
	assert(OS.is_debug_build())
	_scene_transitions_suppressed_for_tests = true


func session_scene_path() -> String:
	return String(MODE_SCENES.get(mode, MODE_SCENES[Mode.DEFAULT]))


## The host can end a run without destroying the room. Guests stay connected
## and all peers return to staging together; a guest leaving on her own closes
## only her connection instead (handled by main_3d.gd).
func end_session(reason: String = "ROUTE ENDED // RETURNED TO STAGING") -> void:
	if online and not is_host:
		return
	if online:
		_receive_end.rpc(reason)
	_receive_end(reason)


@rpc("authority", "call_remote", "reliable")
func _receive_end(reason: String) -> void:
	session_active = false
	status_message = reason
	if online and is_host:
		Backend.update_room(peers.size(), session_active)
	changed.emit()
	call_deferred("_return_to_staging")


func _return_to_staging() -> void:
	var tree := get_tree()
	if tree == null:
		return
	if tree.current_scene != null \
			and tree.current_scene.scene_file_path == "res://scenes/room_lobby.tscn":
		return
	tree.change_scene_to_file("res://scenes/room_lobby.tscn")


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
	return "%s-%s-%d" % [GUEST_FIRST_NAMES[randi() % GUEST_FIRST_NAMES.size()],
		GUEST_LAST_NAMES[randi() % GUEST_LAST_NAMES.size()], 100 + randi() % 900]
