class_name HunterDirector
extends RefCounted

## Host-side coordination of the hunters on one level. Every mode cooperates, scaled by difficulty:
## a hunter that sees a runner tells nearby idle hunters (share), a small team splits so one comes straight in while the others
## flank or cover an exit, hunters crowded together spread out (scatter), and no runner gets more than `cap` hunters committed to
## them (no overload; the surplus is sent away). It never touches a hunter that is chasing, stunned or inactive: it only gives
## wandering / idle ones somewhere to investigate, through HunterBrain.direct_to().
##
## Relay rush: once the runners are ahead on relays (relays_collected >= RELAY_RUSH_COUNT) and that has
## held for RELAY_RUSH_DELAY seconds, a few free hunters (profile "rushers") are sent to investigate the nearest remaining
## (uncollected) relays, each to a different relay where possible, then search around it. Same rules as the rest: only wandering /
## idle hunters, never a chasing, stunned or held one, host only. Callers set `relays_collected` (and `relay_rush_enabled`,
## off for the Public Route) before tick().
##
##   var director := HunterDirector.new("nightmare", seed_text)
##   director.relays_collected = GameState.relays_collected
##   director.tick(delta, [{"id": "a", "brain": brain, "target": target_dict_or_empty}], generator)

const PROFILES := {
	"relaxed": {"share_radius": 10.0, "share_chance": .5, "cap": 2, "team": 1, "flank": 0.0, "cover": 0.0,
		"gap": 7.0, "interval": 2.0, "rushers": 1},
	"standard": {"share_radius": 16.0, "share_chance": .8, "cap": 3, "team": 2, "flank": .1, "cover": .25,
		"gap": 8.0, "interval": 1.5, "rushers": 2},
	"hard": {"share_radius": 24.0, "share_chance": 1.0, "cap": 3, "team": 2, "flank": .6, "cover": .5,
		"gap": 9.0, "interval": 1.0, "rushers": 2},
	"nightmare": {"share_radius": 40.0, "share_chance": 1.0, "cap": 4, "team": 3, "flank": 1.0, "cover": .8,
		"gap": 10.0, "interval": .7, "rushers": 3},
}
const DIRECTED_HOLD := 9.0
const SCATTER_HOLD := 16.0
const SCATTER_CLEAR := 12.0   # a hunter this close to a runner is working, not spreading
## Every frame, every mode: active hunters closer than SEPARATION cells push apart at SEPARATION_SPEED (cells/s) so a
## pack chasing one runner never stacks into one body. A push into a wall or prop is skipped.
const SEPARATION := 1.1
const SEPARATION_SPEED := 2.5
## Relay rush knobs: relays collected before the pressure gate opens, seconds the count must hold first ("after a while"),
## how long a rusher is left alone on its way, and how close counts as already there (it searches from there itself).
const RELAY_RUSH_COUNT := 7
const RELAY_RUSH_DELAY := 45.0
const RUSH_HOLD := 14.0
const RUSH_ARRIVED := 3.0

var mode_id := "standard"
var stats := {"shares": 0, "flanks": 0, "covers": 0, "scatters": 0, "released": 0, "rushes": 0}
## Set by the caller each frame (GameState.relays_collected); drives the relay rush gate.
var relays_collected := 0
var relay_rush_enabled := true

var _rng: SeededRandom
var _clock := 0.0
var _timer := 0.0
var _held := {}   # id -> clock until which the director leaves that hunter alone
var _rushing := {}   # id -> "x,y" of the relay that hunter was sent to
var _rush_since := -1.0   # clock when relays_collected first reached RELAY_RUSH_COUNT, -1 while below


func _init(mode: String, seed_text: String = "DIRECTOR") -> void:
	mode_id = mode if PROFILES.has(mode) else "standard"
	_rng = SeededRandom.new("%s-%s" % [seed_text, mode_id])


func profile() -> Dictionary:
	return PROFILES[mode_id]


static func _free(entry: Dictionary) -> bool:
	var brain: HunterBrain = entry["brain"]
	return brain != null and brain.active and brain.stun_timer <= 0.0 \
		and (brain.state == HunterBrain.State.WANDER or brain.state == HunterBrain.State.IDLE)


static func _nearest_runner(position: Vector2, runners: Array) -> int:
	var best := -1
	var best_gap := INF
	for i in runners.size():
		var gap := position.distance_to(runners[i])
		if gap < best_gap:
			best_gap = gap
			best = i
	return best


func _open_near(generator, point: Vector2, from: Vector2) -> Variant:
	var open: Dictionary = generator.nearest_open_position(point.x, point.y, 2.0)
	if open.is_empty():
		return null
	var found := Vector2(open["x"], open["y"])
	if found.distance_to(from) < 1.0 or generator.find_path(HunterBrain._cell_of(from), HunterBrain._cell_of(found)).is_empty():
		return null
	return found


func _send(entry: Dictionary, point: Vector2, hold: float) -> void:
	(entry["brain"] as HunterBrain).direct_to(point)
	_held[entry["id"]] = _clock + hold


func tick(delta: float, entries: Array, generator) -> void:
	_clock += delta
	_timer += delta
	if relay_rush_enabled and relays_collected >= RELAY_RUSH_COUNT:
		if _rush_since < 0.0:
			_rush_since = _clock
	else:
		_rush_since = -1.0
	var p := profile()
	if _timer < float(p["interval"]):
		return
	_timer = 0.0
	# the runners are the distinct targets any hunter holds
	var runners: Array = []
	for entry in entries:
		var target: Dictionary = entry.get("target", {})
		if target.is_empty():
			continue
		var at: Vector2 = target["position"]
		var known := false
		for existing in runners:
			if existing.distance_to(at) < 1.0:
				known = true
		if not known:
			runners.append(at)
	if runners.is_empty():
		_relay_rush(entries, generator, runners)
		return
	# who is committed to which runner
	var committed := []
	for _r in runners:
		committed.append(0)
	for entry in entries:
		var brain: HunterBrain = entry["brain"]
		if not brain.active:
			continue
		var directed := float(_held.get(entry["id"], 0.0)) > _clock and brain.state == HunterBrain.State.INVESTIGATE
		if brain.state == HunterBrain.State.CHASE or directed:
			var which := _nearest_runner(brain.position, runners)
			if which >= 0 and brain.position.distance_to(runners[which]) <= float(p["share_radius"]) + 8.0:
				committed[which] += 1
	# share: one spotter per runner calls up a team
	for r in runners.size():
		var spotter: Dictionary = {}
		for entry in entries:
			var brain: HunterBrain = entry["brain"]
			if brain.active and brain.state == HunterBrain.State.CHASE and brain.direct_chase_visible \
					and _nearest_runner(brain.position, runners) == r:
				spotter = entry
				break
		if spotter.is_empty():
			continue
		var spot_at: Vector2 = (spotter["brain"] as HunterBrain).position
		var seen_at: Vector2 = runners[r]
		var slots := int(p["cap"]) - int(committed[r])
		var members := mini(slots, int(p["team"]))
		if members <= 0:
			continue
		var candidates: Array = []
		for entry in entries:
			if entry == spotter or not _free(entry) or float(_held.get(entry["id"], 0.0)) > _clock:
				continue
			var gap: float = (entry["brain"] as HunterBrain).position.distance_to(seen_at)
			if gap <= float(p["share_radius"]):
				candidates.append([gap, entry])
		candidates.sort_custom(func(a, b): return a[0] < b[0])
		var sent := 0
		for pair in candidates:
			if sent >= members:
				break
			var entry: Dictionary = pair[1]
			if _rng.next_float() >= float(p["share_chance"]):
				continue
			var brain: HunterBrain = entry["brain"]
			var point := seen_at
			var role := "share"
			var toward := (seen_at - spot_at).normalized() if seen_at.distance_to(spot_at) > .1 else Vector2.RIGHT
			if sent > 0 and _rng.next_float() < float(p["flank"]):
				role = "flank"
				var side := -1.0 if sent % 2 == 0 else 1.0
				point = seen_at + toward.rotated(side * 1.2) * 4.0
			elif sent > 0 and _rng.next_float() < float(p["cover"]):
				role = "cover"
				point = _exit_point(generator, seen_at, toward)
			var open: Variant = _open_near(generator, point, brain.position)
			if open == null:
				open = _open_near(generator, seen_at, brain.position)
				role = "share"
			if open == null:
				continue
			_send(entry, open, DIRECTED_HOLD)
			stats[{"share": "shares", "flank": "flanks", "cover": "covers"}[role]] += 1
			committed[r] += 1
			sent += 1
	# overload: hunters over the cap that are only being directed (not chasing) are sent away
	for r in runners.size():
		var excess := int(committed[r]) - int(p["cap"])
		if excess <= 0:
			continue
		var extras: Array = []
		for entry in entries:
			var brain: HunterBrain = entry["brain"]
			if float(_held.get(entry["id"], 0.0)) > _clock and brain.state == HunterBrain.State.INVESTIGATE \
					and _nearest_runner(brain.position, runners) == r:
				extras.append([brain.position.distance_to(runners[r]), entry])
		extras.sort_custom(func(a, b): return a[0] > b[0])
		for pair in extras:
			if excess <= 0:
				break
			var held_brain: HunterBrain = pair[1]["brain"]
			var away: Vector2 = (held_brain.position - Vector2(runners[r])).normalized()
			var open: Variant = _open_near(generator, held_brain.position + away * 14.0, held_brain.position)
			if open != null:
				_send(pair[1], open, SCATTER_HOLD)
				stats["released"] += 1
				excess -= 1
	# scatter: crowded, idle hunters walk apart
	for entry in entries:
		if not _free(entry) or float(_held.get(entry["id"], 0.0)) > _clock:
			continue
		var brain: HunterBrain = entry["brain"]
		var near_runner := false
		for at in runners:
			if brain.position.distance_to(at) < SCATTER_CLEAR:
				near_runner = true
		if near_runner:
			continue
		var crowd := Vector2.ZERO
		var crowded := false
		for other in entries:
			if other == entry or not (other["brain"] as HunterBrain).active:
				continue
			var gap := brain.position.distance_to((other["brain"] as HunterBrain).position)
			if gap < float(p["gap"]):
				crowded = true
				crowd += (brain.position - (other["brain"] as HunterBrain).position) / maxf(gap, .5)
		if not crowded:
			continue
		var away: Vector2 = crowd.normalized() if crowd.length() > .01 else Vector2.from_angle(_rng.next_float() * TAU)
		var open: Variant = _open_near(generator, brain.position + away * float(p["gap"]) * 1.8, brain.position)
		if open != null:
			_send(entry, open, SCATTER_HOLD)
			stats["scatters"] += 1
	_relay_rush(entries, generator, runners)


## True once the relay rush gate is open: enough relays collected, held for RELAY_RUSH_DELAY.
func relay_rush_active() -> bool:
	return relay_rush_enabled and _rush_since >= 0.0 and _clock - _rush_since >= RELAY_RUSH_DELAY


static func _relay_key(relay: Dictionary) -> String:
	return "%d,%d" % [int(relay["x"]), int(relay["y"])]


## Remaining relays the generator knows about (finite floor or the streamed window): not collected.
static func _remaining_relays(generator) -> Array:
	var out: Array = []
	if generator == null or not ("relays" in generator):
		return out
	for relay in generator.relays:
		if relay is Dictionary and relay.has("x") and relay.has("y") and not bool(relay.get("collected", false)):
			out.append(relay)
	return out


## Relay rush: up to profile "rushers" free hunters investigate the nearest remaining relays, spread over different relays.
## Hunters near a runner are left to the share / scatter rules; a hunter already at a relay is not sent again.
func _relay_rush(entries: Array, generator, runners: Array) -> void:
	if not relay_rush_active():
		_rushing.clear()
		return
	var remaining := _remaining_relays(generator)
	if remaining.is_empty():
		return
	# rushers still on their way keep their relay; finished / pulled-off ones free the slot
	var claimed := {}
	for entry in entries:
		var id := String(entry["id"])
		if not _rushing.has(id):
			continue
		var brain: HunterBrain = entry["brain"]
		if brain != null and brain.active and float(_held.get(id, 0.0)) > _clock and brain.state == HunterBrain.State.INVESTIGATE:
			claimed[_rushing[id]] = true
		else:
			_rushing.erase(id)
	var slots := int(profile().get("rushers", 0)) - _rushing.size()
	if slots <= 0:
		return
	var candidates: Array = []
	for entry in entries:
		if not _free(entry) or float(_held.get(entry["id"], 0.0)) > _clock:
			continue
		var brain: HunterBrain = entry["brain"]
		var near_runner := false
		for at in runners:
			if brain.position.distance_to(at) < SCATTER_CLEAR:
				near_runner = true
		if near_runner:
			continue
		var best := INF
		for relay in remaining:
			best = minf(best, brain.position.distance_to(Vector2(float(relay["x"]) + .5, float(relay["y"]) + .5)))
		candidates.append([best, entry])
	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for pair in candidates:
		if slots <= 0:
			break
		var entry: Dictionary = pair[1]
		var brain: HunterBrain = entry["brain"]
		# nearest relay nobody else is rushing, else the nearest one at all
		var pick: Dictionary = {}
		var pick_gap := INF
		var fallback: Dictionary = {}
		var fallback_gap := INF
		for relay in remaining:
			var gap := brain.position.distance_to(Vector2(float(relay["x"]) + .5, float(relay["y"]) + .5))
			if gap < fallback_gap:
				fallback_gap = gap
				fallback = relay
			if not claimed.has(_relay_key(relay)) and gap < pick_gap:
				pick_gap = gap
				pick = relay
		if pick.is_empty():
			pick = fallback
			pick_gap = fallback_gap
		if pick.is_empty() or pick_gap <= RUSH_ARRIVED:
			continue
		var open: Variant = _open_near(generator, Vector2(float(pick["x"]) + .5, float(pick["y"]) + .5), brain.position)
		if open == null:
			continue
		_send(entry, open, RUSH_HOLD)
		_rushing[String(entry["id"])] = _relay_key(pick)
		claimed[_relay_key(pick)] = true
		stats["rushes"] += 1
		slots -= 1


static func separate(delta: float, entries: Array, generator) -> int:
	var pushed := 0
	for i in entries.size():
		var brain: HunterBrain = entries[i]["brain"]
		if brain == null or not brain.active:
			continue
		var push := Vector2.ZERO
		for j in entries.size():
			var other: HunterBrain = entries[j]["brain"]
			if i == j or other == null or not other.active:
				continue
			var offset := brain.position - other.position
			var gap := offset.length()
			if gap >= SEPARATION:
				continue
			# exactly on top of each other: split by entry order so the two go opposite ways
			var away := offset / gap if gap > .001 else Vector2.RIGHT.rotated(float(i) * 2.4)
			push += away * (SEPARATION - gap) / SEPARATION
		if push == Vector2.ZERO:
			continue
		var step := push.limit_length(1.0) * SEPARATION_SPEED * delta
		var to := brain.position + step
		if generator != null and generator.has_method("can_occupy") and not generator.can_occupy(to.x, to.y):
			continue
		brain.position = to
		pushed += 1
	return pushed


## A way out near the runner (a relay / objective point when the level has them), else straight ahead of the sighting.
func _exit_point(generator, seen_at: Vector2, toward: Vector2) -> Vector2:
	if "relays" in generator:
		var best := INF
		var found := seen_at + toward * 6.0
		for relay in generator.relays:
			if not (relay is Dictionary and relay.has("x") and relay.has("y")):
				continue
			var at := Vector2(float(relay["x"]) + .5, float(relay["y"]) + .5)
			var gap := at.distance_to(seen_at)
			if gap < best and gap <= 16.0:
				best = gap
				found = at
		return found
	return seen_at + toward * 6.0
