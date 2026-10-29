class_name NetPeers
extends RefCounted

## Sends only to peers whose ENet link is still up. Between a peer dropping and ENet's timeout it stays in
## multiplayer.get_peers(), and every .rpc() to it logs "Unable to send packet on channel N, max channels: 0" (the
## KTMXN host logged 537 of them after a bot guest restarted, 2026-10-28).


static func is_live(api: MultiplayerAPI, peer_id: int) -> bool:
	if api == null or not api.has_multiplayer_peer() or peer_id == api.get_unique_id():
		return false
	if not peer_id in api.get_peers():
		return false
	var enet := api.multiplayer_peer as ENetMultiplayerPeer
	if enet == null:
		return true
	# A guest's only ENet link is to the host; other guests are reached through the host's relay.
	if api.get_unique_id() != 1 and peer_id != 1:
		return true
	var packet_peer := enet.get_peer(peer_id)
	return packet_peer == null or packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED


## method.rpc(args...) to every live peer.
static func send_all(api: MultiplayerAPI, method: Callable, args: Array = []) -> void:
	if api == null or not api.has_multiplayer_peer():
		return
	for peer_id in api.get_peers():
		if is_live(api, peer_id):
			method.rpc_id.callv([peer_id] + args)
