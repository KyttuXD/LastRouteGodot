class_name GuestGuard
extends RefCounted

## Host anti-cheat for co-op (docs/ANTI_CHEAT.md). The host owns the run, but every guest owns its own transform and
## meters; this sanity-checks each replicated sample before the host trusts it for targeting, pickups and relays.
## - speed: horizontal distance per sample against the fastest legit move (sprint, on the easiest difficulty) with lag
##   tolerance; upward speed against climb/jump; falling and plunges are never capped;
## - teleports: a jump beyond TELEPORT_DISTANCE needs a floor change, an authorised admin, a spectator, or a host-known
##   legit spot (spawn / checkpoint, through `legit_spot`);
## - no-clip: a capsule sweep along the reported path through static world geometry (doors are ignored, they lag);
## - meters: stamina is not replicated, so an unbroken sprint longer than a full tank (plus slack) counts; lamp charge
##   must stay within 0..MAX and never rise without a battery being used up;
## - the reported grid "position" must match "at".
## A violation snaps the guest back to its last good spot and adds a strike; strikes decay while clean, and STRIKE_KICK
## of them kicks the guest. Cheap: a handful of arithmetic checks per 20 Hz sample, one shape cast only when moving.

const TOLERANCE := 1.35
const LAG_SLACK_M := 1.0
const MAX_SAMPLE_GAP := 1.0
const UP_SPEED := 4.5
const TELEPORT_DISTANCE := 12.0
const STRIKE_KICK := 5
const STRIKE_DECAY_SECONDS := 30.0
const SPRINT_SLACK_SECONDS := 1.5
const SWEEP_MIN_M := .05
const SWEEP_RADIUS := .2
const SWEEP_HEIGHT := 1.0
const SWEEP_CENTER_Y := 1.0
const WORLD_MASK := 1

## Fastest legit horizontal speed in m/s (sprint on the most generous difficulty).
static var max_speed := GameConfig.PLAYER_SPRINT_SPEED * 1.08 / GameConfig.TILE_SIZE
## Longest legit unbroken sprint: a full tank at the gentlest drain.
static var max_sprint_seconds := GameConfig.MAX_STAMINA / GameConfig.STAMINA_SPRINT_DRAIN

## Optional host hooks: legit_spot(at: Vector3, depth: int) -> bool, exempt(peer_id) -> bool (admin rights).
var legit_spot: Callable
var exempt: Callable

var _peers := {}


func forget(peer_id: int) -> void:
	_peers.erase(peer_id)


func strikes(peer_id: int) -> int:
	return int((_peers.get(peer_id, {}) as Dictionary).get("strikes", 0))


func last_good(peer_id: int) -> Variant:
	return (_peers.get(peer_id, {}) as Dictionary).get("good")


## Checks one sample. Returns {} when it is fine, else {"reason", "snap_to": Vector3, "strikes", "kick": bool}.
## `space` may be null (no sweep). `now` is seconds.
func check(peer_id: int, state: Dictionary, now: float, space: PhysicsDirectSpaceState3D = null) -> Dictionary:
	var at = state.get("at")
	if not at is Vector3:
		return {}
	var peer: Dictionary = _peers.get(peer_id, {})
	if peer.is_empty():
		_peers[peer_id] = {"good": at, "time": now, "depth": int(state.get("depth", 0)), "strikes": 0,
			"clean_since": now, "sprint": 0.0, "lamp": float(state.get("lamp_charge", GameConfig.MAX_LAMP_CHARGE)),
			"batteries": _batteries(state)}
		return {}
	var dt := clampf(now - float(peer["time"]), 0.0, MAX_SAMPLE_GAP)
	var good: Vector3 = peer["good"]
	var depth := int(state.get("depth", 0))
	var free_pass: bool = (exempt.is_valid() and bool(exempt.call(peer_id))) \
		or bool(state.get("spectating", false)) or bool(state.get("game_over", false))
	var reason := ""
	if not free_pass:
		reason = _movement_reason(peer, state, at, good, depth, dt, space)
		if reason.is_empty():
			reason = _meter_reason(peer, state, dt)
	peer["time"] = now
	peer["lamp"] = clampf(float(state.get("lamp_charge", peer["lamp"])), 0.0, GameConfig.MAX_LAMP_CHARGE)
	peer["batteries"] = _batteries(state)
	if reason.is_empty():
		peer["good"] = at
		peer["depth"] = depth
		if int(peer["strikes"]) > 0 and now - float(peer["clean_since"]) >= STRIKE_DECAY_SECONDS:
			peer["strikes"] = int(peer["strikes"]) - 1
			peer["clean_since"] = now
		return {}
	peer["strikes"] = int(peer["strikes"]) + 1
	peer["clean_since"] = now
	peer["sprint"] = 0.0
	return {"reason": reason, "snap_to": good, "strikes": int(peer["strikes"]),
		"kick": int(peer["strikes"]) >= STRIKE_KICK}


func _movement_reason(peer: Dictionary, state: Dictionary, at: Vector3, good: Vector3, depth: int, dt: float,
		space: PhysicsDirectSpaceState3D) -> String:
	var grid = state.get("position")
	if grid is Vector2 and (grid as Vector2).distance_to(Vector2(at.x, at.z)) > 1.5:
		return "position"
	if depth != int(peer["depth"]):
		peer["flat_credit"] = LAG_SLACK_M
		return ""   # level links / stairs between floors: the floor change itself is the proof
	var flat := Vector2(at.x - good.x, at.z - good.z).length()
	var rise := at.y - good.y
	if flat > TELEPORT_DISTANCE or rise > TELEPORT_DISTANCE:
		if legit_spot.is_valid() and bool(legit_spot.call(at, depth)):
			return ""
		return "teleport"
	# Leaky budgets: each sample earns distance at the legit top speed and spends what it moved. The cap is one full
	# lag gap of credit, so bunched packets after a stall pass while a steady over-speed runs dry within a second or two.
	var flat_credit := minf(float(peer.get("flat_credit", LAG_SLACK_M)) + max_speed * TOLERANCE * dt,
		max_speed * TOLERANCE * MAX_SAMPLE_GAP + LAG_SLACK_M) - flat
	var up_credit := minf(float(peer.get("up_credit", LAG_SLACK_M)) + UP_SPEED * TOLERANCE * dt,
		UP_SPEED * TOLERANCE * MAX_SAMPLE_GAP + LAG_SLACK_M) - maxf(rise, 0.0)
	if flat_credit < 0.0:
		peer["flat_credit"] = LAG_SLACK_M
		return "speed"
	if up_credit < 0.0:
		peer["up_credit"] = LAG_SLACK_M
		return "fly"
	peer["flat_credit"] = flat_credit
	peer["up_credit"] = up_credit
	if space != null and flat >= SWEEP_MIN_M and not bool(state.get("in_vent", false)) \
			and not bool(state.get("hidden", false)) and _blocked(space, good, at):
		return "noclip"
	return ""


func _meter_reason(peer: Dictionary, state: Dictionary, dt: float) -> String:
	var lamp := float(state.get("lamp_charge", peer["lamp"]))
	if lamp < -0.01 or lamp > GameConfig.MAX_LAMP_CHARGE + 0.01:
		return "lamp"
	if lamp > float(peer["lamp"]) + 1.0 and _batteries(state) >= int(peer["batteries"]):
		return "lamp"
	if bool(state.get("sprinting", false)):
		peer["sprint"] = float(peer["sprint"]) + dt
		if float(peer["sprint"]) > max_sprint_seconds + SPRINT_SLACK_SECONDS:
			return "stamina"
	else:
		peer["sprint"] = 0.0
	return ""


static func _batteries(state: Dictionary) -> int:
	var order = state.get("inventory_order", [])
	return (order as Array).count("battery") if order is Array else 0


## True when a slim capsule swept from `from` to `to` (raised off the floor) hits static world geometry that is not a
## door. Doors open and close on the host a little behind the guest, so they never count.
static func _blocked(space: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = SWEEP_RADIUS
	shape.height = SWEEP_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = WORLD_MASK
	query.collide_with_areas = false
	var lift := Vector3(0.0, SWEEP_CENTER_Y, 0.0)
	query.transform = Transform3D(Basis.IDENTITY, from + lift)
	query.motion = Vector3(to.x - from.x, 0.0, to.z - from.z)
	var result := space.cast_motion(query)
	if result.is_empty() or float(result[0]) >= 0.98:
		return false
	# The ray runs one capsule radius past the end: the capsule may already have touched the wall last sample.
	var ahead := Vector3(to.x - from.x, 0.0, to.z - from.z).normalized() * SWEEP_RADIUS
	var ray := PhysicsRayQueryParameters3D.create(from + lift, Vector3(to.x, from.y, to.z) + ahead + lift, WORLD_MASK)
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		return false   # only grazed a corner with the capsule's side
	var node := hit.get("collider") as Node
	for _i in 4:
		if node == null:
			break
		if node is RouteInteractable3D or node is CharacterBody3D or node is RigidBody3D:
			return false
		node = node.get_parent()
	return true
