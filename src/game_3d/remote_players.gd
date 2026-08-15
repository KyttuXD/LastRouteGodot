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
var _since_send := 0.0


func _ready() -> void:
	if RoomState.online:
		multiplayer.peer_disconnected.connect(_drop)


func _process(delta: float) -> void:
	if not RoomState.online or local_player == null:
		return
	_since_send += delta
	if _since_send < 1.0 / SEND_HZ:
		return
	_since_send = 0.0
	_place.rpc(local_player.global_position, local_player.rotation.y)


## Any peer may tell the others where IT is; nobody may move anyone else. That
## is what "call_remote" and the sender check together buy.
@rpc("any_peer", "call_remote", "unreliable_ordered")
func _place(at: Vector3, facing: float) -> void:
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
	body.global_position = at
	body.rotation.y = facing


func _drop(id: int) -> void:
	var body: Node3D = _bodies.get(id)
	if body != null:
		body.queue_free()
	_bodies.erase(id)


func count() -> int:
	return _bodies.size()
