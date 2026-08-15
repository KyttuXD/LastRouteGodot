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

enum Mode { DEFAULT, HIDE_SEEK, OFFICE }
## SPRAWLING and CAVERNOUS merged into one top tier, IMMENSE -- two "big"
## steps that only differed by how big, with nothing else changing between
## them, was a choice that cost more attention at the lobby than it earned.
## Not named LARGE: that name was already taken by the tier below it, and
## renaming an existing tier just to free the word felt like a bigger change
## than "merge the two biggest" asked for.
enum Scale { SMALL, STANDARD, LARGE, IMMENSE }
enum Difficulty { RELAXED, STANDARD, NIGHTMARE }

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
	Difficulty.NIGHTMARE: "NIGHTMARE",
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
## False until there is a backend. Everything that would need one asks this.
var online := false
var is_host := true

## Peer id -> callsign. The host is always peer 1. Kept as a dictionary rather
## than a list so a player leaving removes the right row without the others
## shuffling under it.
var peers := {}

const DEFAULT_PORT := 8421
## Loopback by default: this exists to test with two windows on one machine
## before there is anything to connect to.
const DEFAULT_ADDRESS := "127.0.0.1"

var _peer: ENetMultiplayerPeer


func _ready() -> void:
	# A room always exists, so nothing has to null-check it. Landing straight
	# in a mode from the editor gets a valid singleplayer room.
	if code.is_empty():
		create_local(Mode.DEFAULT)


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
	leave_network()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_server(port, MAX_PLAYERS)
	if error != OK:
		_peer = null
		return "COULD NOT OPEN PORT %d" % port
	multiplayer.multiplayer_peer = _peer
	online = true
	is_host = true
	peers = {1: _local_name()}
	_bind_signals()
	changed.emit()
	return ""


## Join someone else's room. Their configuration replaces ours wholesale --
## the host owns the route, so a client that kept its own seed would generate a
## different building from the same room.
func join_room(address: String = DEFAULT_ADDRESS, port: int = DEFAULT_PORT) -> String:
	leave_network()
	_peer = ENetMultiplayerPeer.new()
	var error := _peer.create_client(address, port)
	if error != OK:
		_peer = null
		return "COULD NOT REACH %s:%d" % [address, port]
	multiplayer.multiplayer_peer = _peer
	online = true
	is_host = false
	peers = {}
	_bind_signals()
	changed.emit()
	return ""


func leave_network() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
	multiplayer.multiplayer_peer = null
	online = false
	is_host = true
	peers = {}
	changed.emit()


func _bind_signals() -> void:
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
		multiplayer.connected_to_server.connect(_on_joined)
		multiplayer.server_disconnected.connect(leave_network)


func _on_peer_connected(id: int) -> void:
	if not is_host:
		return
	peers[id] = "SIGNAL-%d" % id
	# The host is the only authority on the route, so a joiner is TOLD the room
	# rather than asked about it.
	_receive_room.rpc_id(id, code, seed_text, mode, map_scale, difficulty, peers)
	_receive_room.rpc(code, seed_text, mode, map_scale, difficulty, peers)
	changed.emit()


func _on_peer_disconnected(id: int) -> void:
	peers.erase(id)
	if is_host:
		_receive_room.rpc(code, seed_text, mode, map_scale, difficulty, peers)
	changed.emit()


func _on_joined() -> void:
	peers[multiplayer.get_unique_id()] = _local_name()
	changed.emit()


@rpc("authority", "call_remote", "reliable")
func _receive_room(p_code: String, p_seed: String, p_mode: int, p_scale: int,
		p_difficulty: int, p_peers: Dictionary) -> void:
	code = p_code
	seed_text = p_seed
	mode = p_mode
	map_scale = p_scale
	difficulty = p_difficulty
	peers = p_peers
	changed.emit()


## Push the host's configuration to everyone. Called after any host-side change,
## so a client never generates a building from a stale route.
func broadcast() -> void:
	if online and is_host:
		_receive_room.rpc(code, seed_text, mode, map_scale, difficulty, peers)


func _local_name() -> String:
	return String(players[0]) if not players.is_empty() else _make_callsign()


## A fresh route for the same room. The web build regenerates the facility from
## the seed, so changing it is how you get a different building without leaving
## staging.
func reroll_seed() -> void:
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
			rows.append({"name": String(name), "id": 1, "host": true, "you": true})
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
	return true


func mode_unavailable_reason(candidate: Mode) -> String:
	if candidate == Mode.HIDE_SEEK and not online:
		return "NEEDS A SECOND SIGNAL // NO BACKEND YET"
	if candidate == Mode.HIDE_SEEK:
		return "NEEDS A SECOND SIGNAL IN THE ROOM"
	return ""


## What the button that leaves staging should say, in the web build's words.
func start_label() -> String:
	return "START OFFICE SHIFT" if mode == Mode.OFFICE else "ENTER ROUTE"


func mode_label() -> String:
	return String(MODE_LABELS.get(mode, "?"))


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
	return (SCALE_OPTIONS.get(map_scale, SCALE_OPTIONS[Scale.STANDARD]) as Dictionary).duplicate()


func set_mode(value: Mode) -> void:
	if mode == value or not mode_available(value):
		return
	mode = value
	broadcast()
	changed.emit()


func set_map_scale(value: Scale) -> void:
	if map_scale == value:
		return
	map_scale = value
	broadcast()
	changed.emit()


func set_difficulty(value: Difficulty) -> void:
	if difficulty == value:
		return
	difficulty = value
	broadcast()
	changed.emit()


## Leave staging and start the run this room describes.
##
## The room seeds GameState rather than the mode scene seeding itself, so two
## players entering the same room get the same building -- which is the part
## that has to be true before any networking is worth writing.
func enter(tree: SceneTree) -> void:
	if mode != Mode.OFFICE:
		GameState.start_new_run(run_seed())
	tree.change_scene_to_file(String(MODE_SCENES.get(mode, MODE_SCENES[Mode.DEFAULT])))


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
