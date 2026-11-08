class_name SeatOccupancy
extends RefCounted

## Who sits where: plan positions (x, z in metres) of every occupied seat, shared by runners and
## hunters. Rebuilt every frame by the route from the remote runners' replicated `seat_at` and the seated hunters' views;
## the local runner is never in it. A seat within NEAR of an occupant is taken: it offers no prompt to anyone else, and
## HunterSeats skips it. Sit points on one bench are 0.9 m+ apart, so a neighbour never blocks the next seat.

const NEAR := .35

static var taken: Array = []


static func plan_of(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)


static func is_taken(at: Vector2) -> bool:
	for p in taken:
		if (p as Vector2).distance_to(at) <= NEAR:
			return true
	return false


static func rebuild(occupied: Array) -> void:
	taken = occupied
