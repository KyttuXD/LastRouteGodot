class_name HideOccupancy
extends RefCounted

## Who hides where (docs/HIDING_PROPS.md, KT: "only one player or bot should occupy a hiding spot, unless its a larger one
## like a wardrobe, then allow 2"). A spot holds `hide_capacity` runners (prop data, lr.prop/1: 1 by default, 2 for
## wardrobes; a mod may set it, clamped to MAX). Each occupant takes a slot: slot 0 is the front one, nearest the door,
## slot 1 beside and behind it, so two hiders never share a camera or a pose.
##
## Rebuilt every frame by the route from the remote runners' replicated hiding_spot / hide_slot, like SeatOccupancy; the
## local runner is never in it. A full spot offers "SPOT TAKEN" instead of HIDE. Two runners who climbed in on the same
## frame are sorted out by the host (overflow): the lowest peer keeps the spot, the rest are put back out. A hunter's
## check pulls the front occupant out first (grab_order).

const MAX := 2

## cell -> Array of {"peer": int, "slot": int}
static var occupants: Dictionary = {}


static func clamp_capacity(value: int) -> int:
	return clampi(value, 1, MAX)


## `list`: {"cell": Vector2i, "peer": int, "slot": int} for every hidden runner but the local one.
static func rebuild(list: Array) -> void:
	occupants = group(list)


static func group(list: Array) -> Dictionary:
	var out := {}
	for entry_value in list:
		var entry: Dictionary = entry_value
		var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))
		if cell.x < 0:
			continue
		if not out.has(cell):
			out[cell] = []
		(out[cell] as Array).append({"peer": int(entry.get("peer", 0)), "slot": int(entry.get("slot", 0))})
	return out


static func count(cell: Vector2i) -> int:
	return (occupants.get(cell, []) as Array).size()


static func is_full(cell: Vector2i, capacity: int) -> bool:
	return count(cell) >= clamp_capacity(capacity)


## The lowest slot nobody else holds, or -1 when the spot is full.
static func free_slot(cell: Vector2i, capacity: int) -> int:
	if is_full(cell, capacity):
		return -1
	var held := {}
	for entry in occupants.get(cell, []):
		held[int((entry as Dictionary)["slot"])] = true
	for slot in clamp_capacity(capacity):
		if not held.has(slot):
			return slot
	return -1


## Occupants in the order a hunter pulls them out: the front slot (nearest the door) first, then by peer.
static func grab_order(list: Array) -> Array:
	var out := list.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["slot"]) < int(b["slot"]) or (int(a["slot"]) == int(b["slot"]) and int(a["peer"]) < int(b["peer"])))
	return out


## Host: the peers to put back out. `list` is every hidden runner (the host's own included); `capacity_of` maps a cell to
## its capacity. Per spot the lowest peers keep it up to capacity; one sharing a kept runner's slot is out too.
static func overflow(list: Array, capacity_of: Callable) -> Array:
	var out := []
	var by_cell := group(list)
	for cell in by_cell:
		var entries: Array = (by_cell[cell] as Array).duplicate()
		entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["peer"]) < int(b["peer"]))
		var capacity := clamp_capacity(int(capacity_of.call(cell)))
		var held := {}
		for entry_value in entries:
			var entry: Dictionary = entry_value
			var slot := int(entry["slot"])
			if held.size() >= capacity or held.has(slot) or slot >= capacity:
				out.append(int(entry["peer"]))
				continue
			held[slot] = true
	return out
