class_name RemotePlayers
extends Node3D

## The other players' bodies.
##
## Everyone wears the same mannequin, so a remote player is that model plus a
## position -- there is no per-player appearance to replicate, which is most of
## why this is short.
##
## Deliberately DUMB: each peer sends its own position on a timer and every
## other peer moves a body to match. No prediction, no interpolation of
## authority, no server-side movement. On loopback that is indistinguishable
## from correct, and it is the smallest thing that puts a second figure in the
## room to look at -- which is what this is for right now. Anything cleverer
## should wait until there is a real connection to be clever about.

const MODEL := "res://art/props-3d/characters/player.tscn"
## How often a peer tells the others where it is. 20 Hz is smooth enough to
## watch and cheap enough to ignore.
const SEND_HZ := 20.0

var local_player: Node3D

var _bodies := {}
## Peer id -> that body's AnimationPlayer, found once when the body is made
## rather than walked for every packet.
var _players := {}
var _since_send := 0.0


func _ready() -> void:
	if RoomState.online:
		multiplayer.peer_disconnected.connect(_drop)
		multiplayer.peer_connected.connect(_greet)


func _process(delta: float) -> void:
	if not RoomState.online or local_player == null:
		return
	_since_send += delta
	if _since_send < 1.0 / SEND_HZ:
		return
	_since_send = 0.0
	# The clip name rides along with the position. Everyone wears the same
	# mannequin, so the clip is all a body needs to move like the player it
	# belongs to -- and without it a remote player slid around frozen, which
	# read as a broken model rather than as missing sync.
	_place.rpc(local_player.global_position, local_player.rotation.y, _local_clip())


## Any peer may tell the others where IT is; nobody may move anyone else. That
## is what "call_remote" and the sender check together buy.
## What the local player's body is doing, in the vocabulary ModelSlot uses.
## Read from the controller rather than tracked here, so it cannot drift from
## what the local body is actually playing.
func _local_clip() -> String:
	if local_player == null or not local_player.has_method("current_clip"):
		return "idle"
	return String(local_player.call("current_clip"))


@rpc("any_peer", "call_remote", "unreliable_ordered")
func _place(at: Vector3, facing: float, clip: String) -> void:
	var id := multiplayer.get_remote_sender_id()
	if id == multiplayer.get_unique_id():
		return
	var body: Node3D = _bodies.get(id)
	if body == null:
		body = ModelSlot.instantiate(MODEL)
		if body == null:
			return
		body.name = "Peer%d" % id
		add_child(body)
		_bodies[id] = body
		_players[id] = ModelSlot.find_animation_player(body)
	body.global_position = at
	body.rotation.y = facing
	ModelSlot.play_if_available(_players.get(id), clip)


func _drop(id: int) -> void:
	var body: Node3D = _bodies.get(id)
	if body != null:
		body.queue_free()
	_bodies.erase(id)
	_players.erase(id)


## Hunters, from the host only.
##
## The brains run in ONE place. They are deterministic given the same inputs,
## but the biggest input is which player they are chasing -- so every client
## running its own would have every client chased by a hunter standing
## somewhere else. The host runs them against the room and says where they
## ended up.
##
## This lives here rather than on the scene root because RPCs need the same
## node path on every peer, and this node already has one.
signal hunters_received(data: Array)


func broadcast_hunters(data: Array) -> void:
	if RoomState.online and RoomState.is_host:
		_hunters.rpc(data)


@rpc("authority", "call_remote", "unreliable_ordered")
func _hunters(data: Array) -> void:
	hunters_received.emit(data)


## Whether this peer is allowed to run the simulation at all. Offline it is,
## because a solo room has no host to defer to and there is no second code path
## for a solo run.
func simulates() -> bool:
	return not RoomState.online or RoomState.is_host


## The shared world: pickups, the heater station, the lift.
##
## Positions are sent on a timer and a dropped packet costs nothing, because
## another one is 50ms behind it. These are the opposite: a relay is collected
## ONCE, and a peer that misses the packet keeps a relay nobody else can see and
## a count that never reaches the target. So they go reliable, and they carry
## the cell rather than a node path -- every peer generates the same facility
## from the same seed, so a cell names the same object everywhere without any
## agreement about spawn order.
##
## Anyone may collect. There is no host arbitration here on purpose: the race it
## would settle (two players reaching one relay in the same 50ms) resolves the
## same way either way, since the second `activate()` finds it already
## `completed` and does nothing.
signal world_event(event: Dictionary)
## The whole shared state at once, for a peer that arrived after some of it
## already happened.
signal world_snapshot(state: Dictionary)

## Fills a snapshot for a joining peer. Set by the scene that owns the world;
## only ever called on the host.
var snapshot_source: Callable


func broadcast_event(event: Dictionary) -> void:
	if RoomState.online:
		_event.rpc(event)


@rpc("any_peer", "call_remote", "reliable")
func _event(event: Dictionary) -> void:
	world_event.emit(event)


## A peer that joins mid-floor has generated the same facility everyone else
## has, which means it has generated every relay that was already picked up.
## Without this it would walk a floor of ghosts.
func _greet(id: int) -> void:
	if not RoomState.is_host or not snapshot_source.is_valid():
		return
	_snapshot.rpc_id(id, snapshot_source.call())


@rpc("authority", "call_remote", "reliable")
func _snapshot(state: Dictionary) -> void:
	world_snapshot.emit(state)


func count() -> int:
	return _bodies.size()
