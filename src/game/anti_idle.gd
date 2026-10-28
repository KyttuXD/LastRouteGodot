class_name AntiIdle
extends RefCounted

## The anti-AFK clock's notion of "the party moved". Only what the player really does counts: walking (WALK_DISTANCE from
## the last anchor) or a deliberate turn (the facing vector changes by TURN_CHANGE; head sway on an XR headset is far below
## XR_TURN_CHANGE). Input events -- touch layer, d-pad, look-drag deltas of zero, emulated mouse motion -- the keep-awake
## flag and the platform never count, so a phone or a Quest standing still is as idle as a desktop with no key held and the
## Gray Void pressure comes on schedule everywhere.
##
## `anchors` is peer_id -> {"position", "facing"}; a peer seen for the first time counts as moved.

const WALK_DISTANCE := .35
const TURN_CHANGE := .22
const XR_TURN_CHANGE := .55


static func turn_change() -> float:
	return XR_TURN_CHANGE if PlatformProfile.is_xr else TURN_CHANGE


static func party_moved(anchors: Dictionary, targets: Array, turn_threshold: float = -1.0) -> bool:
	if turn_threshold < 0.0:
		turn_threshold = turn_change()
	var moved := false
	var present := {}
	for target_value in targets:
		var target: Dictionary = target_value
		var position_value = target.get("position")
		if not position_value is Vector2 or bool(target.get("game_over", false)):
			continue
		var peer_id := int(target.get("peer_id", 1))
		var position: Vector2 = position_value
		var facing := Vector2.ZERO
		if target.get("facing") is Vector2:
			facing = target["facing"]
		present[peer_id] = true
		var previous = anchors.get(peer_id)
		var anchor_position := position
		var anchor_facing := Vector2.ZERO
		var had_anchor := false
		if previous is Dictionary:
			had_anchor = true
			if previous.get("position") is Vector2:
				anchor_position = previous["position"]
			if previous.get("facing") is Vector2:
				anchor_facing = previous["facing"]
		elif previous is Vector2:
			had_anchor = true
			anchor_position = previous
		var walked := had_anchor and anchor_position.distance_to(position) >= WALK_DISTANCE
		var turned := had_anchor and facing.length_squared() > .0001 and anchor_facing.length_squared() > .0001 \
			and anchor_facing.distance_to(facing) >= turn_threshold
		if not had_anchor or walked or turned:
			anchors[peer_id] = {"position": position, "facing": facing}
			moved = true
		elif facing.length_squared() > .0001 and anchor_facing.length_squared() <= .0001:
			anchors[peer_id] = {"position": anchor_position, "facing": facing}
	for peer_id_value in anchors.keys().duplicate():
		if not present.has(peer_id_value):
			anchors.erase(peer_id_value)
	return moved or present.is_empty()
