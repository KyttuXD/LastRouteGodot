class_name PlayerColors
extends RefCounted

## One colour per player slot, colour-blind friendly (Okabe-Ito plus Tol-style extensions), used by every screen that shows a player:
## the minimap / full-map arrows, the HUD waypoints, the player list, the 3D nametag and the chat. A player's slot is their rank among
## the room's peers (host first), the same on every client, so each peer keeps one colour everywhere.

const PALETTE: Array[Color] = [
	Color("e69f00"),   # orange
	Color("56b4e9"),   # sky blue
	Color("009e73"),   # bluish green
	Color("f0e442"),   # yellow
	Color("0072b2"),   # blue
	Color("d55e00"),   # vermillion
	Color("cc79a7"),   # reddish purple
	Color("b8b8b8"),   # light grey
	Color("882255"),   # wine
	Color("88ccee"),   # cyan
	Color("ddcc77"),   # sand
	Color("aa4499"),   # purple
]


static func for_slot(slot: int) -> Color:
	return PALETTE[posmod(slot, PALETTE.size())]


## The slot of `peer_id` among the room's peers (sorted ids, so the host is first); a peer not on the roster (a validator, a stale id)
## falls back to its id, which still keeps 1..N distinct.
static func slot_of(peer_id: int, peers: Array) -> int:
	var ids: Array = peers.duplicate()
	ids.sort()
	var index := ids.find(peer_id)
	return index if index >= 0 else posmod(peer_id, PALETTE.size())


static func for_peer(peer_id: int, peers: Array) -> Color:
	return for_slot(slot_of(peer_id, peers))
