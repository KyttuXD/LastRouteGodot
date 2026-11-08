class_name HostHandoff
extends RefCounted

## Deliberate private-room host handoff (game/autoload/room_state.gd).
##
## The relay forwards raw ENet datagrams, so a successor cannot inherit the old server's connections: it opens a
## FRESH ENet server (peer 1) and every other guest reconnects. What moves across is this versioned checkpoint,
## sent by the old host to the chosen successor only, after every guest froze and acknowledged (the barrier):
##
##   room code / seed / epoch / content-pack hash, the reserved-command cursor, the route world (the same shape as
##   a route save, WITHOUT the old host's own runner), and the stable identity map.
##
## Identity: every guest holds a room-scoped resume secret the HOST issued (never its callsign, never its account
## session). The checkpoint carries only sha256 hashes of those secrets, so the successor can verify a reconnecting
## guest without holding -- or leaking -- anybody's secret. Peer ids change across the rebuild; peer-owned world
## records (waypoints, revive windows, Gray's binding) are rekeyed old -> new only after that proof.
##
## Inventory is never transferred between runners: each runner keeps its own local inventory (the successor
## restores its own record through the route-save path); nobody restores a self-asserted inventory for someone else.

const VERSION := 1
const KIND := "lastroute_host_handoff"
## The old host itself (peer 1 before the rebuild). Its runner leaves with it.
const OLD_HOST_PEER := 1


static func new_resume_secret() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()


static func resume_hash(secret: String) -> String:
	if secret.length() != 32 or not secret.is_valid_hex_number(false):
		return ""
	return secret.sha256_text()


## `identity` is {resume hash: old peer id} for every guest the old host verified.
static func build_envelope(room_code: String, seed_text: String, run_seed: int, epoch: int, pack_hash: String,
		successor_old_peer: int, identity: Dictionary, reserved_seq: int, world: Dictionary) -> Dictionary:
	var payload := world.duplicate(true)
	payload.erase("player")   # the old host's own runner never becomes anybody's runner
	return {
		"kind": KIND,
		"version": VERSION,
		"code": room_code,
		"seed_text": seed_text,
		"run_seed": run_seed,
		"epoch": epoch,
		"pack_hash": pack_hash,
		"successor_old_peer": successor_old_peer,
		"identity": identity.duplicate(),
		"reserved_seq": maxi(0, reserved_seq),
		"world": payload,
	}


## "" when `envelope` is a checkpoint this successor may install, else why not. `expected` has code, run_seed,
## epoch, pack_hash and successor_old_peer as this guest sees them.
static func validate_envelope(envelope: Dictionary, expected: Dictionary) -> String:
	if String(envelope.get("kind", "")) != KIND:
		return "NOT A HANDOFF CHECKPOINT"
	if int(envelope.get("version", 0)) != VERSION:
		return "HANDOFF CHECKPOINT VERSION %d IS NOT SUPPORTED" % int(envelope.get("version", 0))
	if String(envelope.get("code", "")) != String(expected.get("code", "")):
		return "HANDOFF CHECKPOINT IS FOR ANOTHER ROOM"
	if int(envelope.get("epoch", 0)) <= 0 or int(envelope.get("epoch", 0)) != int(expected.get("epoch", -1)):
		return "HANDOFF CHECKPOINT EPOCH IS STALE"
	if int(envelope.get("run_seed", 0)) != int(expected.get("run_seed", -1)) \
			or String(envelope.get("seed_text", "")).is_empty():
		return "HANDOFF CHECKPOINT SEED DOES NOT MATCH"
	if String(envelope.get("pack_hash", "")) != String(expected.get("pack_hash", "")):
		return "HANDOFF CHECKPOINT CONTENT PACKS DIFFER"
	if int(envelope.get("successor_old_peer", 0)) <= OLD_HOST_PEER \
			or int(envelope.get("successor_old_peer", 0)) != int(expected.get("successor_old_peer", -1)):
		return "HANDOFF CHECKPOINT NAMES ANOTHER SUCCESSOR"
	var identity = envelope.get("identity")
	if not identity is Dictionary:
		return "HANDOFF CHECKPOINT HAS NO IDENTITY MAP"
	for key in identity:
		if String(key).length() != 64 or not String(key).is_valid_hex_number(false) or int(identity[key]) <= OLD_HOST_PEER:
			return "HANDOFF CHECKPOINT IDENTITY MAP IS MALFORMED"
	var world = envelope.get("world")
	if not world is Dictionary or not (world as Dictionary).get("world_state") is Dictionary:
		return "HANDOFF CHECKPOINT HAS NO WORLD"
	if int((world as Dictionary).get("run_seed", 0)) != int(expected.get("run_seed", -1)):
		return "HANDOFF CHECKPOINT WORLD SEED DOES NOT MATCH"
	return ""


## The route payload the successor installs through the route-save path (RunSaves pending): the checkpoint world,
## peer-owned records remapped for the rebuild (old host dropped, successor -> 1), plus the successor's OWN runner.
static func successor_payload(envelope: Dictionary, own_player: Dictionary) -> Dictionary:
	var payload: Dictionary = (envelope.get("world", {}) as Dictionary).duplicate(true)
	payload["player"] = own_player.duplicate(true)
	var authority: Dictionary = payload.get("authority", {}) if payload.get("authority") is Dictionary else {}
	authority["source"] = "host_handoff"
	authority["handoff_epoch"] = int(envelope.get("epoch", 0))
	payload["authority"] = authority
	if payload.get("world_state") is Dictionary:
		payload["world_state"] = remap_world_snapshot(payload["world_state"],
			{int(envelope.get("successor_old_peer", 0)): OLD_HOST_PEER}, [OLD_HOST_PEER])
	return payload


## Rekey peer-owned records in a StreamedWorldState.snapshot(). `mapping` old -> new; `dropped` ids are removed.
## Applied in one pass, so swapping ids (successor -> 1 while 1 is dropped) cannot collide.
static func remap_world_snapshot(world: Dictionary, mapping: Dictionary, dropped: Array) -> Dictionary:
	var out := world.duplicate(true)
	var waypoints = out.get("waypoints", {})
	if waypoints is Dictionary:
		var rekeyed := {}
		for key in waypoints:
			var entry = waypoints[key]
			var target := _target(int(key), mapping, dropped)
			if target > 0 and entry is Dictionary:
				var copy: Dictionary = (entry as Dictionary).duplicate(true)
				copy["peer_id"] = target
				rekeyed[target] = copy
		out["waypoints"] = rekeyed
	var downs = out.get("downs", {})
	if downs is Dictionary:
		var rekeyed_downs := {}
		for key in downs:
			var record = downs[key]
			var target := _target(int(key), mapping, dropped)
			if target > 0 and record is Dictionary:
				var copy: Dictionary = (record as Dictionary).duplicate(true)
				copy["by"] = 0   # holds are host-timed; a reviver restarts the hold on the new host
				rekeyed_downs[str(target)] = copy
		out["downs"] = rekeyed_downs
	var hunters = out.get("hunters", {})
	if hunters is Dictionary:
		for entity in hunters:
			var state = hunters[entity]
			if state is Dictionary and (state as Dictionary).has("gray_peer"):
				var target := _target(int(state["gray_peer"]), mapping, dropped)
				if target > 0:
					state["gray_peer"] = target
				else:
					(state as Dictionary).erase("gray_peer")
					(state as Dictionary).erase("gray_reason")
	return out


static func _target(peer: int, mapping: Dictionary, dropped: Array) -> int:
	if mapping.has(peer):
		return int(mapping[peer])
	if peer in dropped:
		return 0
	return peer


## Live rekey on the successor once a reconnecting guest proved its resume identity (old -> new), or drop (new = 0)
## when its rebind window closes. Works on the running StreamedWorldState through its snapshot/adopt pair.
static func rebind_world_state(world_state: Object, old_peer: int, new_peer: int) -> bool:
	if world_state == null or old_peer <= OLD_HOST_PEER or old_peer == new_peer:
		return false
	var snapshot: Dictionary = world_state.call("snapshot")
	var mapping := {} if new_peer <= 0 else {old_peer: new_peer}
	var remapped := remap_world_snapshot(snapshot, mapping, [old_peer])
	if remapped.hash() == snapshot.hash():
		return false
	var waypoints = world_state.get("waypoints")
	if waypoints != null:
		waypoints.call("adopt", remapped.get("waypoints", {}))
	var downs = world_state.get("downs")
	if downs != null:
		downs.call("adopt", remapped.get("downs", {}))
	var hunters = world_state.get("hunters")
	if hunters is Dictionary:
		var remapped_hunters: Dictionary = remapped.get("hunters", {})
		for entity in remapped_hunters:
			if (hunters as Dictionary).has(entity):
				(hunters as Dictionary)[entity] = remapped_hunters[entity]
	return true
