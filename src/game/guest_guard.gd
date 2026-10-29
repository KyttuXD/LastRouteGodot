class_name GuestGuard
extends RefCounted

## Host anti-cheat for co-op (docs/ANTI_CHEAT.md). The host owns the run, but every guest owns its own transform and
## meters; this sanity-checks each replicated sample before the host trusts it for targeting, pickups and relays.
## - speed: horizontal distance per sample against the fastest legit move (sprint, on the easiest difficulty) with lag
##   tolerance; upward speed against climb/jump; falling and plunges are never capped;
## - teleports: a jump beyond TELEPORT_DISTANCE needs a floor change, an authorised admin, or a host-known
##   legit spot (spawn / checkpoint, through `legit_spot`);
## - no-clip: a capsule sweep along the reported path through static world geometry (doors are ignored, they lag);
## - meters: stamina is not replicated, so an unbroken sprint longer than a full tank (plus slack) counts; lamp charge
##   must stay within 0..MAX and never rise without a battery being used up;
## - the reported grid "position" must match "at";
## - stacks: no slot holds more of a stackable than PlayerController3D.STACK_MAX ("stack");
## - a Stim Pack boost (STIM_BOOST_SPEED for STIM_BOOST_SECONDS) only counts once a stim was really used up.
## A violation snaps the guest back to its last good spot and adds a strike; strikes decay while clean, and STRIKE_KICK
## of them kicks the guest. Cheap: a handful of arithmetic checks per 20 Hz sample, one shape cast only when moving.
##
## Lag (KT: "make sure heavy internet lag isnt triggered as a false alarm"):
## - the movement budget earns credit for the real time between arrivals, capped by the longest gap seen lately, so a
##   freeze followed by a burst of catch-up samples adds up to the legit distance;
## - budgets widen with the guest's round trip and jitter (`rtt_ms`, measured arrival jitter);
## - samples carry a sequence number: duplicates and out-of-order samples are dropped, never judged; a skipped run
##   (packet loss) or a long gap skips the wall sweep, whose straight line would cut corners the guest walked round;
## - under heavy lag (round trip > HEAVY_RTT_MS, a gap > HEAVY_GAP_SECONDS lately, or jitter > HEAVY_JITTER_SECONDS) a
##   movement or stamina violation still snaps back but is tagged "lag": no strike, no kick, no troll mode.

const TOLERANCE := 1.35
const LAG_SLACK_M := 1.0
const MAX_SAMPLE_GAP := 1.0
const GAP_MEMORY_SECONDS := 10.0
const SAMPLE_INTERVAL := 1.0 / 20.0
const HEAVY_RTT_MS := 400.0
const HEAVY_GAP_SECONDS := 1.5
const HEAVY_JITTER_SECONDS := .25
const HEAVY_LAG_HOLD_SECONDS := 5.0
const SWEEP_MAX_DT := .3
const SPRINT_MAX_DT := .25
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
## Optional: rtt_ms(peer_id) -> float, the transport's round trip for that guest (0 when unknown).
var rtt_ms: Callable

var _peers := {}


func forget(peer_id: int) -> void:
	_peers.erase(peer_id)


## The host caused (or approved) a long move for this guest — a vent transit, a hunter pulling it out of hiding, an axe
## rescue, a revive — so jumps within `seconds` from `now` pass and the speed budget refills.
func allow_jump(peer_id: int, now: float, seconds := 3.0) -> void:
	if _peers.has(peer_id):
		_peers[peer_id]["jump_ok_until"] = now + seconds


func strikes(peer_id: int) -> int:
	return int((_peers.get(peer_id, {}) as Dictionary).get("strikes", 0))


## Whether the guest is in heavy lag right now (its snaps are tagged "lag").
func lagging(peer_id: int) -> bool:
	return float((_peers.get(peer_id, {}) as Dictionary).get("lag_until", -1.0)) \
		>= float((_peers.get(peer_id, {}) as Dictionary).get("now", 0.0))


func last_good(peer_id: int) -> Variant:
	return (_peers.get(peer_id, {}) as Dictionary).get("good")


## Checks one sample. Returns {} when it is fine, {"drop": true} for a duplicate / out-of-order sample (ignore it), else
## {"reason", "snap_to": Vector3, "strikes", "kick": bool, "lag": bool}.
## `space` may be null (no sweep). `now` is seconds.
func check(peer_id: int, state: Dictionary, now: float, space: PhysicsDirectSpaceState3D = null) -> Dictionary:
	var at = state.get("at")
	if not at is Vector3:
		return {}
	var peer: Dictionary = _peers.get(peer_id, {})
	if peer.is_empty():
		_peers[peer_id] = {"good": at, "time": now, "depth": int(state.get("depth", 0)), "strikes": 0,
			"clean_since": now, "sprint": 0.0, "lamp": float(state.get("lamp_charge", GameConfig.MAX_LAMP_CHARGE)),
			"batteries": _batteries(state), "stims": _carried(state, "stim_pack"), "boost_until": -1.0,
			"seq": int(state.get("seq", -1)), "jitter": 0.0, "gaps": [],
			"lag_until": -1.0, "now": now, "id": peer_id}
		return {}
	var seq := int(state.get("seq", -1))
	var seq_jump := 1
	if seq >= 0 and int(peer["seq"]) >= 0:
		if seq <= int(peer["seq"]):
			return {"drop": true}
		seq_jump = seq - int(peer["seq"])
	peer["seq"] = seq
	var dt := maxf(now - float(peer["time"]), 0.0)
	_note_gap(peer, dt, now)
	var good: Vector3 = peer["good"]
	var depth := int(state.get("depth", 0))
	# a ghost (spectating) walks like a runner, so it is checked like one; only the death screen itself is let off
	var free_pass: bool = (exempt.is_valid() and bool(exempt.call(peer_id))) \
		or (bool(state.get("game_over", false)) and not bool(state.get("spectating", false)))
	var reason := ""
	peer["now"] = now
	_note_stim(peer, state, now)
	if not free_pass:
		reason = _movement_reason(peer, state, at, good, depth, dt, space, seq_jump)
		if reason.is_empty():
			reason = _meter_reason(peer, state, minf(dt, SPRINT_MAX_DT))
	peer["time"] = now
	peer["lamp"] = clampf(float(state.get("lamp_charge", peer["lamp"])), 0.0, GameConfig.MAX_LAMP_CHARGE)
	peer["batteries"] = _batteries(state)
	peer["stims"] = _carried(state, "stim_pack")
	if reason.is_empty():
		peer["good"] = at
		peer["depth"] = depth
		if int(peer["strikes"]) > 0 and now - float(peer["clean_since"]) >= STRIKE_DECAY_SECONDS:
			peer["strikes"] = int(peer["strikes"]) - 1
			peer["clean_since"] = now
		return {}
	peer["sprint"] = 0.0
	if reason in LAG_EXCUSABLE and float(peer["lag_until"]) >= now:
		return {"reason": "lag", "snap_to": good, "strikes": int(peer["strikes"]), "kick": false, "lag": true}
	peer["strikes"] = int(peer["strikes"]) + 1
	peer["clean_since"] = now
	return {"reason": reason, "snap_to": good, "strikes": int(peer["strikes"]),
		"kick": int(peer["strikes"]) >= STRIKE_KICK, "lag": false}


const LAG_EXCUSABLE := ["speed", "fly", "teleport", "noclip", "stamina"]


## A Stim Pack boost is trusted only when the sample both reports it and carries one stim fewer than the last: then
## for its length (plus a second of slack) the speed budget runs at STIM_SPEED_SCALE and the unbroken-sprint clock
## restarts, since the stim refilled the tank. A claimed boost with no stim used buys nothing.
func _note_stim(peer: Dictionary, state: Dictionary, now: float) -> void:
	if float(state.get("stim_boost", 0.0)) > 0.0 and _carried(state, "stim_pack") < int(peer.get("stims", 0)):
		peer["boost_until"] = now + GameConfig.STIM_BOOST_SECONDS + 1.0
	if boosted(peer):
		peer["sprint"] = 0.0


static func boosted(peer: Dictionary) -> bool:
	return float(peer.get("boost_until", -1.0)) >= float(peer.get("now", 0.0))


## Arrival gaps feed the credit cap (longest lately), jitter, and the heavy-lag hold.
func _note_gap(peer: Dictionary, dt: float, now: float) -> void:
	var gaps: Array = peer["gaps"]
	gaps.append(Vector2(now, dt))
	while not gaps.is_empty() and now - (gaps[0] as Vector2).x > GAP_MEMORY_SECONDS:
		gaps.pop_front()
	peer["jitter"] = lerpf(float(peer["jitter"]), absf(dt - SAMPLE_INTERVAL), .1)
	var rtt := float(rtt_ms.call(int(peer.get("id", 0)))) if rtt_ms.is_valid() else 0.0
	peer["rtt"] = rtt
	if dt > HEAVY_GAP_SECONDS or rtt > HEAVY_RTT_MS or float(peer["jitter"]) > HEAVY_JITTER_SECONDS:
		peer["lag_until"] = now + HEAVY_LAG_HOLD_SECONDS


## Longest arrival gap in the last GAP_MEMORY_SECONDS (at least MAX_SAMPLE_GAP).
static func _longest_gap(peer: Dictionary) -> float:
	var longest := MAX_SAMPLE_GAP
	for gap in peer["gaps"]:
		longest = maxf(longest, (gap as Vector2).y)
	return longest


## Budget widening for the guest's round trip and jitter. Kept modest: the elapsed-time credit already absorbs gaps,
## so this only covers bunching noise; a 2.5x speed cheat stays over budget even at a 2 s round trip.
static func _lag_scale(peer: Dictionary) -> float:
	return 1.0 + minf(float(peer.get("rtt", 0.0)) / 4000.0, .15) + minf(2.0 * float(peer.get("jitter", 0.0)), .5)


func _movement_reason(peer: Dictionary, state: Dictionary, at: Vector3, good: Vector3, depth: int, dt: float,
		space: PhysicsDirectSpaceState3D, seq_jump: int) -> String:
	var grid = state.get("position")
	if grid is Vector2 and (grid as Vector2).distance_to(Vector2(at.x, at.z)) > 1.5:
		return "position"
	if depth != int(peer["depth"]) or float(peer.get("jump_ok_until", -1.0)) >= float(peer.get("now", 0.0)):
		peer["flat_credit"] = LAG_SLACK_M
		return ""   # level links / stairs between floors: the floor change itself is the proof
	var flat := Vector2(at.x - good.x, at.z - good.z).length()
	var rise := at.y - good.y
	# Leaky budgets: each sample earns distance at the legit top speed for the real time since the last one and spends
	# what it moved. The cap is the longest gap seen lately, so the catch-up burst after a freeze passes while a steady
	# over-speed runs dry within a second or two. A move past the budget and beyond TELEPORT_DISTANCE is a teleport.
	var tolerance := TOLERANCE * _lag_scale(peer) * (GameConfig.STIM_SPEED_SCALE if boosted(peer) else 1.0)
	var window := _longest_gap(peer)
	var flat_credit := minf(float(peer.get("flat_credit", LAG_SLACK_M)) + max_speed * tolerance * dt,
		max_speed * tolerance * window + LAG_SLACK_M) - flat
	var up_credit := minf(float(peer.get("up_credit", LAG_SLACK_M)) + UP_SPEED * tolerance * dt,
		UP_SPEED * tolerance * window + LAG_SLACK_M) - maxf(rise, 0.0)
	if flat_credit < 0.0 or up_credit < 0.0:
		if legit_spot.is_valid() and bool(legit_spot.call(at, depth)):
			peer["flat_credit"] = LAG_SLACK_M
			return ""
		peer["flat_credit"] = LAG_SLACK_M
		peer["up_credit"] = LAG_SLACK_M
		if flat > TELEPORT_DISTANCE or rise > TELEPORT_DISTANCE:
			return "teleport"
		return "speed" if flat_credit < 0.0 else "fly"
	peer["flat_credit"] = flat_credit
	peer["up_credit"] = up_credit
	if space != null and flat >= SWEEP_MIN_M and dt <= SWEEP_MAX_DT and seq_jump <= 2 \
			and not bool(state.get("in_vent", false)) \
			and not bool(state.get("hidden", false)) and _blocked(space, good, at):
		return "noclip"
	return ""


func _meter_reason(peer: Dictionary, state: Dictionary, dt: float) -> String:
	if _over_stacked(state):
		return "stack"
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


## A slot holding more of a stackable than PlayerController3D.STACK_MAX allows (pickups and drops are all-or-nothing and
## capped, so only an edited client gets there).
static func _over_stacked(state: Dictionary) -> bool:
	var order = state.get("inventory_order", [])
	var counts = state.get("inventory_slot_durability", [])
	if not order is Array or not counts is Array:
		return false
	for slot in mini((order as Array).size(), (counts as Array).size()):
		var item_id := String(order[slot])
		if PlayerController3D.STACK_MAX.has(item_id) and int(counts[slot]) > PlayerController3D.stack_max(item_id):
			return true
	return false


static func _batteries(state: Dictionary) -> int:
	return _carried(state, "battery")


## How many of a stackable item the sample carries (each slot's count lives in inventory_slot_durability).
static func _carried(state: Dictionary, item_id: String) -> int:
	var order = state.get("inventory_order", [])
	if not order is Array:
		return 0
	var counts = state.get("inventory_slot_durability", [])
	var total := 0
	for slot in (order as Array).size():
		if String(order[slot]) == item_id:
			total += clampi(int(counts[slot]) if counts is Array and slot < (counts as Array).size() else 1,
				1, PlayerController3D.stack_max(item_id))
	return total


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
