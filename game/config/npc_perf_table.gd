class_name NpcPerfTable
extends RefCounted

## Host upload and CPU budget for admin NPC teammates (docs/NPC_TEAMMATES.md).
## One full state packet per NPC per guest at SEND_HZ, at most PACKET_BUDGET bytes. The host pathfinds once per NPC
## every REPATH seconds and does not give an NPC a physics body. This table only estimates that budget; it does not
## simulate NPCs. SEND_HZ, COUNT_LIMIT and REPATH match NpcTeammates; the npc_teammates suite fails if either side drifts.

const PACKET_BUDGET := 600
const SEND_HZ := 12.0
const COUNT_LIMIT := 0   # NpcTeammates.COUNT_LIMIT: 0 = unlimited, so the rows below are estimates, not a cap
const REPATH := 0.5
## Documented rows: NPC counts up to the scroller's top, for one guest and for a small co-op party.
const NPC_COUNTS := [1, 4, 8, 16, 32, 64]
const GUEST_COUNTS := [1, 3]


## Host upload in bytes/s: npc_count * guest_count * SEND_HZ * packet_size. packet_size defaults to the ceiling.
static func host_upload_bytes_per_sec(npc_count: int, guest_count: int, packet_size: int = PACKET_BUDGET) -> int:
	return npc_count * guest_count * int(SEND_HZ) * packet_size


## Same upload in decimal KB/s (bytes/s / 1000), the unit the Budget table prints.
static func host_upload_kb_per_sec(npc_count: int, guest_count: int, packet_size: int = PACKET_BUDGET) -> float:
	return float(host_upload_bytes_per_sec(npc_count, guest_count, packet_size)) / 1000.0


## Grid pathfinds per second on the host: npc_count / REPATH. No physics body.
static func pathfinds_per_sec(npc_count: int) -> float:
	return float(npc_count) / REPATH


## One dictionary per documented (npcs, guests) pair: bytes_per_sec, kb_per_sec, pathfinds_per_sec.
static func rows() -> Array:
	var out: Array = []
	for npc_count in NPC_COUNTS:
		for guest_count in GUEST_COUNTS:
			var npcs := int(npc_count)
			var guests := int(guest_count)
			out.append({
				"npcs": npcs,
				"guests": guests,
				"bytes_per_sec": host_upload_bytes_per_sec(npcs, guests),
				"kb_per_sec": host_upload_kb_per_sec(npcs, guests),
				"pathfinds_per_sec": pathfinds_per_sec(npcs),
			})
	return out
