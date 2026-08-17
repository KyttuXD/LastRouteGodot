extends Node

## The room a session belongs to.
##
## Singleplayer is not a separate path here -- it is a room with one player in
## it, hosted locally, with no transport attached. That is the whole point of
## introducing this before there is any networking: every entry into the game
## already goes through a room, so adding multiplayer later means giving the
## room a transport rather than rewriting how runs start.
##
## Concretely, the things a run needs -- which mode, which seed, how big the
## map, how hard -- live on the room, not on whoever pressed the button. When
## PLAY and OFFICE MODE become CREATE ROOM and JOIN ROOM, nothing downstream of
## this file has to change: a joined room fills these same fields from the host
## instead of from `create_local`.
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
## Nightmare is intentionally reserved but not selectable. Its eventual design
## includes a larger active hunter lineup, which is not a safe thing to expose
## as a label before the corresponding simulation and co-op rules exist.
enum Difficulty { RELAXED, STANDARD, HARD, NIGHTMARE }

## The web build calls a slot a "signal" and seats sixteen of them.
const MAX_PLAYERS := 16

## Room codes are read aloud and typed in, so the alphabet drops the glyphs
## that get confused doing either: I/1, O/0, and lowercase entirely.
const CODE_ALPHABET := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
const CODE_LENGTH := 5

const MODE_LABELS := {
	Mode.DEFAULT: "DEFAULT", Mode.HIDE_SEEK: "HIDE & SEEK", Mode.OFFICE: "OFFICE",
}
const SCALE_LABELS := {
	Scale.SMALL: "SMALL", Scale.STANDARD: "STANDARD", Scale.LARGE: "LARGE",
	Scale.IMMENSE: "IMMENSE",
}
const DIFFICULTY_LABELS := {
	Difficulty.RELAXED: "RELAXED", Difficulty.STANDARD: "STANDARD",
	Difficulty.HARD: "HARD",
}
const DIFFICULTY_IDS := {
	Difficulty.RELAXED: "relaxed", Difficulty.STANDARD: "standard",
	Difficulty.HARD: "hard", Difficulty.NIGHTMARE: "nightmare",
}

## Which scene each mode opens. OFFICE is its own self-contained shift and
## shares no state with a Last Route run.
const MODE_SCENES := {
	Mode.DEFAULT: "res://scenes/main_3d.tscn",
	Mode.HIDE_SEEK: "res://scenes/main_3d.tscn",
	Mode.OFFICE: "res://scenes/office_3d.tscn",
}

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
const CONNECTION_TIMEOUT_MSEC := 12_000
## Loopback by default: this exists to test with two windows on one machine
## before there is anything to connect to.
const DEFAULT_ADDRESS := "127.0.0.1"

var _peer: ENetMultiplayerPeer
var _host_port := DEFAULT_PORT
var _connect_started_msec := 0
var _upnp_thread: Thread
var _upnp: UPNP
var _upnp_mapped_port := 0
var _upnp_status := ""
var _directory_status := ""


func _ready() -> void:
	Backend.registration_changed.connect(_on_directory_registration)
	# A room always exists, so nothing has to null-check it. Landing straight
	# in a mode from the editor gets a valid singleplayer room.
	if code.is_empty():
		create_local(Mode.DEFAULT)


func _process(_delta: float) -> void:
	if _upnp_thread != null and not _upnp_thread.is_alive():
		var outcome: Dictionary = _upnp_thread.wait_to_finish()
		_upnp_thread = null
		_finish_upnp_mapping(outcome)
	if connecting and _connect_started_msec > 0 \
			and Time.get_ticks_msec() - _connect_started_msec >= CONNECTION_TIMEOUT_MSEC:
		_close_failed_connection(
			"ROOM CONNECTION TIMED OUT // HOST MUST ALLOW UDP %d" % _host_port)


func _exit_tree() -> void:
	_stop_upnp_mapping()


## Open a room on this machine with one player in it.
##
## This IS singleplayer. There is no second code path to keep in step, which is
## the reason to do it now rather than after the networking exists.
func create_local(for_mode: Mode) -> void:
	code = _make_code()
	mode = for_mode
	map_scale = Scale.STANDARD
	difficulty = Difficulty.STANDARD
	leave_network()
	session_active = false
	status_message = ""
	players = PackedStringArray([_make_callsign()])
	reroll_seed()
	changed.emit()


## Open this room to the network.
##
## Everything above already describes a room; this only gives it a transport.
## The host keeps the room it already had -- same code, same seed, same
## configuration -- so hosting is not "start a multiplayer game", it is the
## singleplayer room you are already in becoming joinable.
func host_room(port: int = DEFAULT_PORT) -> String:
	if OS.has_feature("web"):
		return "WEB BUILD IS SOLO // ENET/UDP NEEDS A WEBSOCKET OR WEBRTC TRANSPORT"
	leave_network()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		_peer = null
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
	if Backend.configured():
		_start_upnp_mapping(port)
	Backend.register_room(code, port, peers.size(), session_active, host_addresses())
	changed.emit()
	return ""


## Join someone else's room. Their configuration replaces ours wholesale --
## the host owns the route, so a client that kept its own seed would generate a
## different building from the same room.
func join_room(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> String:
	if OS.has_feature("web"):
		return "WEB BUILD IS SOLO // ENET/UDP NEEDS A WEBSOCKET OR WEBRTC TRANSPORT"
	leave_network()
	var trimmed := address.strip_edges()
	if trimmed.is_empty():
		return "ENTER A HOST ADDRESS"
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(trimmed, port)
	if error != OK:
		_peer = null
		return "COULD NOT REACH %s:%d" % [trimmed, port]
	multiplayer.multiplayer_peer = _peer
	online = false
	connecting = true
	_connect_started_msec = Time.get_ticks_msec()
	_host_port = port
	is_host = false
	session_active = false
	status_message = "JOINING ROOM THROUGH PRIMARY SERVER"
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
	_stop_upnp_mapping()
	online = false
	connecting = false
	_connect_started_msec = 0
	is_host = true
	session_active = false
	peers = {}
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
	_directory_status = message if listed else "PRIMARY SERVER LISTING FAILED // %s" % message
	status_message = _directory_status
	if listed and not _upnp_status.is_empty():
		status_message += " // %s" % _upnp_status
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


## Whether a mode can be picked in this room's current state.
##
## HIDE & SEEK needs someone to hide from, so it is unavailable offline. That
## is a property of the room rather than a disabled button in the menu, so the
## rule holds wherever a mode gets chosen.
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


func mode_available(candidate: Mode) -> bool:
	if candidate == Mode.HIDE_SEEK:
		return online and roster().size() > 1
	if candidate == Mode.OFFICE:
		return not online
	return true


func mode_unavailable_reason(candidate: Mode) -> String:
	if candidate == Mode.HIDE_SEEK and not online:
		return "NEEDS A SECOND SIGNAL IN THE ROOM"
	if candidate == Mode.HIDE_SEEK:
		return "NEEDS A SECOND SIGNAL IN THE ROOM"
	if candidate == Mode.OFFICE and online:
		return "OFFICE MODE IS SOLO ONLY // CLOSE ONLINE ROOM FIRST"
	return ""


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
	# NIGHTMARE is a reservation, not a hidden back door. Rejecting it here as
	# well as omitting its lobby button keeps scripts and stale clients from
	# starting an only-partially-defined ruleset.
	if not DIFFICULTY_LABELS.has(value) or difficulty == value:
		return
	difficulty = value
	broadcast()
	changed.emit()


func difficulty_id() -> String:
	return String(DIFFICULTY_IDS.get(difficulty, "standard"))


func difficulty_profile() -> Dictionary:
	return GameConfig.difficulty_profile(difficulty_id())


static func _selectable_difficulty_or_standard(value: int) -> int:
	return value if DIFFICULTY_LABELS.has(value) else Difficulty.STANDARD


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
	var path := String(MODE_SCENES.get(mode, MODE_SCENES[Mode.DEFAULT]))
	if tree.current_scene != null and tree.current_scene.scene_file_path == path:
		return
	tree.change_scene_to_file(path)


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


## ENet is peer-to-peer UDP. The primary backend can publish the host's public
## address, but a home router still has to forward that UDP port to the game.
## UPnP handles the common case automatically on a worker thread because SSDP
## discovery is synchronous. Routers without UPnP get an explicit lobby
## warning and can use an ordinary manual UDP 8421 forwarding rule.
func _start_upnp_mapping(port: int) -> void:
	_stop_upnp_mapping()
	_upnp_status = "CHECKING UDP %d AUTO-FORWARD" % port
	_upnp_thread = Thread.new()
	var error := _upnp_thread.start(_discover_upnp_mapping.bind(port))
	if error != OK:
		_upnp_thread = null
		_upnp_status = "FORWARD UDP %d TO HOST // AUTO-FORWARD COULD NOT START" % port


static func _discover_upnp_mapping(port: int) -> Dictionary:
	var upnp := UPNP.new()
	var result := upnp.discover(2000, 2, "InternetGatewayDevice")
	var mapped := false
	if result == UPNP.UPNP_RESULT_SUCCESS:
		var gateway := upnp.get_gateway()
		if gateway != null and gateway.is_valid_gateway():
			result = upnp.add_port_mapping(port, port, "Last Route ENet", "UDP", 0)
			mapped = result == UPNP.UPNP_RESULT_SUCCESS
	return {"upnp": upnp, "port": port, "result": result, "mapped": mapped}


func _finish_upnp_mapping(outcome: Dictionary) -> void:
	var upnp = outcome.get("upnp") as UPNP
	var port := int(outcome.get("port", 0))
	var mapped := bool(outcome.get("mapped", false))
	# The player may have left during discovery. Remove a mapping made for a
	# room that no longer exists instead of leaking it on the router.
	if not online or not is_host or port != _host_port:
		if mapped and upnp != null:
			upnp.delete_port_mapping(port, "UDP")
		return
	if mapped:
		_upnp = upnp
		_upnp_mapped_port = port
		_upnp_status = "UDP %d OPENED AUTOMATICALLY" % port
	else:
		_upnp_status = "FORWARD UDP %d TO THIS HOST // AUTO-FORWARD UNAVAILABLE (%d)" \
			% [port, int(outcome.get("result", -1))]
	status_message = _directory_status if not _directory_status.is_empty() \
		else "REGISTERING ROOM WITH PRIMARY SERVER"
	status_message += " // %s" % _upnp_status
	changed.emit()


func _stop_upnp_mapping() -> void:
	if _upnp_thread != null:
		var outcome: Dictionary = _upnp_thread.wait_to_finish()
		_upnp_thread = null
		var pending_upnp = outcome.get("upnp") as UPNP
		if bool(outcome.get("mapped", false)) and pending_upnp != null:
			pending_upnp.delete_port_mapping(int(outcome.get("port", 0)), "UDP")
	if _upnp != null and _upnp_mapped_port > 0:
		_upnp.delete_port_mapping(_upnp_mapped_port, "UDP")
	_upnp = null
	_upnp_mapped_port = 0
	_upnp_status = ""
	_directory_status = ""


## Addresses worth showing beside the host button. Loopback and IPv6 link-local
## entries are omitted because another machine cannot use the former and the
## latter needs a scope id the simple address field does not expose.
func host_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for address in IP.get_local_addresses():
		if address == "127.0.0.1" or address.contains(":"):
			continue
		out.append(address)
	return out


static func _make_code() -> String:
	var out := ""
	for i in CODE_LENGTH:
		out += CODE_ALPHABET[randi() % CODE_ALPHABET.length()]
	return out


## A callsign in the web build's shape -- QUIET-EYE-307. Anonymous on purpose:
## a room is joined by code, and nobody has an account yet.
static func _make_callsign() -> String:
	const FIRST := ["QUIET", "LOW", "DIM", "COLD", "LONG", "THIN", "FAINT", "LAST"]
	const SECOND := ["EYE", "STEP", "LAMP", "WIRE", "ROUTE", "DOOR", "SIGNAL", "WATCH"]
	return "%s-%s-%d" % [FIRST[randi() % FIRST.size()],
		SECOND[randi() % SECOND.size()], 100 + randi() % 900]
