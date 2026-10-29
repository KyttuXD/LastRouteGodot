class_name NightWatchStalker
extends RefCounted

## One hunter, ported from createStalker in the 2D game's classic-logic.js (the variety levers and Kathy's fading are later
## milestones, see docs/NIGHT_WATCH_3D.md). She walks the building graph toward her door after a random wait, then waits at
## it: a shut door (T_CLOSED_MS) or the light held on her (push_ms) sends her back, otherwise she attacks after `attack_ms`.
## Deterministic: every roll comes from the shared seeded RandomNumberGenerator.

var id := ""
var room := ""
var level := 0
var base := 0
var at_door_ms := 0.0
var closed_ms := 0.0
var lit_ms := 0.0
var attack_ms := 5200.0
var push_ms := INF
var behind := false
var focus := NightWatchData.FOCUS

var _rng: RandomNumberGenerator
var _pace := 1.0
var _graph: Dictionary = NightWatchData.GRAPH
var _doors: Array = []
var _which := 0
var _door := ""
var _dist: Dictionary = {}
var _retreat_to := ""
var _push_to := ""
var _alternate := false
var _only_when_cams_down := false
var _freezes_when_watched := false
var _blocked: Callable = func(_room: String) -> bool: return false

# the pacer (core/time.js createPacer): time waited and the wait drawn for this move (-1 = none drawn yet)
var _t := 0.0
var _next := -1.0
## Kathy's differences (all off for everyone else): the light never holds her wait (`unseen`), a shut door has to stay shut for a rolled time (`need_ms`,
## from `need_range` with an exponential tail) and then she FADES to one of `fade_to` on a fresh door instead of retreating.
var unseen := false
var need_ms := NightWatchData.T_CLOSED_MS
var need_range := Vector2.ZERO
var need_tail := 0.0
var fade_to: Array = []


static func make(hunter_id: String, rng: RandomNumberGenerator, base_level: int, attack: float, pace: float,
		push: float, blocked: Callable) -> NightWatchStalker:
	var def: Dictionary = NightWatchData.HUNTERS[hunter_id]
	var s := NightWatchStalker.new()
	s.id = hunter_id
	s._rng = rng
	s.base = base_level
	s.level = base_level
	s.attack_ms = attack
	s._pace = pace
	s.push_ms = push
	s._blocked = blocked
	s.room = String(def["start"])
	s._doors = def["doors"]
	s._door = String(s._doors[0])
	s._dist = NightWatchData.distances_to(s._door)
	s._retreat_to = String(def["retreat_to"])
	s._push_to = String(def["push_to"])
	s._alternate = bool(def.get("alternate", false))
	s._only_when_cams_down = bool(def.get("only_when_cams_down", false))
	s._freezes_when_watched = bool(def.get("freezes_when_watched", false))
	return s


## Night 7: Kathy, alone (2D createStalker with fadeTo / unseen / closedNeedMs). `tuning` {grace_ms, pace}.
static func make_kathy(rng: RandomNumberGenerator, base_level: int, grace_ms: float, pace: float) -> NightWatchStalker:
	var k := NightWatchData.KATHY
	var s := NightWatchStalker.new()
	s.id = "kathy"
	s._rng = rng
	s.base = base_level
	s.level = base_level
	s.attack_ms = grace_ms
	s._pace = pace
	s.push_ms = INF
	s._blocked = func(_r: String) -> bool: return false
	s.room = String(k["start"])
	s._doors = k["doors"]
	s._which = mini(s._doors.size() - 1, int(floor(rng.randf() * s._doors.size())))
	s._door = String(s._doors[s._which])
	s._dist = NightWatchData.distances_to(s._door)
	s._retreat_to = String(k["start"])
	s._push_to = String(k["start"])
	s.unseen = true
	s.fade_to = k["fade_to"]
	var hold: Array = k["hold_ms"]
	s.need_range = Vector2(float(hold[0]), float(hold[1]))
	s.need_tail = float(k["hold_tail_ms"])
	s.need_ms = s.need_range.x
	return s


## Kathy fades: she turns up in one of the fade_to rooms, on a door chosen afresh, with a fresh wait.
func fade() -> void:
	room = String(fade_to[mini(fade_to.size() - 1, int(floor(_rng.randf() * fade_to.size())))])
	at_door_ms = 0.0
	closed_ms = 0.0
	lit_ms = 0.0
	behind = false
	reset_pacer()
	_which = mini(_doors.size() - 1, int(floor(_rng.randf() * _doors.size())))
	_door = String(_doors[_which])
	_dist = NightWatchData.distances_to(_door)


## Admin: put her in `to_room` now. A door node makes it her door (she waits there as if she had walked up to it).
func admin_send(to_room: String) -> void:
	room = to_room
	at_door_ms = 0.0
	closed_ms = 0.0
	lit_ms = 0.0
	behind = false
	reset_pacer()
	if to_room.begins_with("door"):
		_door = to_room
		_dist = NightWatchData.distances_to(_door)


func door() -> String:
	return _door


func is_at_door() -> bool:
	return room == _door


func reset_pacer() -> void:
	_t = 0.0
	_next = -1.0


func _pacer_step(dt_ms: float) -> bool:
	if level <= 0:
		_t = 0.0
		_next = -1.0
		return false
	if _next < 0.0:
		var window := NightWatchData.move_window(level)
		_next = window.x + _rng.randf() * (window.y - window.x)
	_t += dt_ms
	if _t < _next:
		return false
	_t = 0.0
	var window2 := NightWatchData.move_window(level)
	_next = window2.x + _rng.randf() * (window2.y - window2.x)
	return true


func _can_move(ctx: Dictionary) -> bool:
	if _only_when_cams_down and bool(ctx.get("cam", false)):
		return false
	if _freezes_when_watched and bool(ctx.get("cam", false)) and String(ctx.get("cam_room", "")) == room:
		return false
	return true


func _next_room() -> String:
	var around := []
	for r in _graph.get(room, []):
		if not _blocked.call(r):
			around.append(r)
	var closer := []
	var sideways := []
	for r in around:
		if int(_dist.get(r, 99)) < int(_dist.get(room, 99)):
			closer.append(r)
		elif r != _door and not String(r).begins_with("door") and int(_dist.get(r, 99)) >= int(_dist.get(room, 99)):
			sideways.append(r)
	var pool: Array = closer
	if not (not closer.is_empty() and (_rng.randf() < focus or sideways.is_empty())):
		pool = sideways if not sideways.is_empty() else closer
	if pool.is_empty():
		return room
	return String(pool[mini(pool.size() - 1, int(floor(_rng.randf() * pool.size())))])


## Advance by `dt_ms`. `door_closed` says whether her door is shut. ctx: {cam, cam_room, lit {doorL, doorR}, behind}.
## Returns the events that happened, in order.
func step(dt_ms: float, door_closed: bool, ctx: Dictionary) -> Array:
	var events := []
	behind = room == _door and bool(ctx.get("behind", false))
	if room != _door and _can_move(ctx) and _pacer_step(dt_ms if _pace == 1.0 else dt_ms / _pace):
		var from := room
		room = _next_room()
		if room != from:
			events.append({"type": "arrived" if room == _door else "moved", "id": id, "room": room, "from": from})
			if room == _door:
				at_door_ms = 0.0
				closed_ms = 0.0
				lit_ms = 0.0
				if need_range != Vector2.ZERO:
					need_ms = NightWatchData.roll_hold(_rng.randf(), need_range.x, need_range.y, need_tail)
				return events
	if room == _door:
		# A shut door sends her away almost at once (about half a second); an open one gives her the wait. A light on her
		# door pauses the wait. A shut door works on the one behind too, so it clears both at once.
		if door_closed:
			closed_ms += dt_ms
			lit_ms = 0.0
			if closed_ms >= need_ms:
				var from2 := room
				room = _retreat_to
				at_door_ms = 0.0
				closed_ms = 0.0
				lit_ms = 0.0
				behind = false
				reset_pacer()
				if not fade_to.is_empty():
					fade()
				elif _alternate:
					_which = (_which + 1) % _doors.size()
					_door = String(_doors[_which])
					_dist = NightWatchData.distances_to(_door)
				events.append({"type": "repelled", "id": id, "room": room, "from": from2})
			return events
		closed_ms = 0.0
		var lit: Dictionary = ctx.get("lit", {})
		if unseen or not bool(lit.get(_door, false)):
			at_door_ms += dt_ms
			lit_ms = 0.0
		elif behind:
			lit_ms = 0.0
		else:
			# The light on her: her wait holds, and if it stays on her long enough she backs off to push_to. Halfway there
			# she flinches (once per stare-down).
			var before := lit_ms
			lit_ms += dt_ms
			if before < push_ms / 2.0 and lit_ms >= push_ms / 2.0 and lit_ms < push_ms:
				events.append({"type": "flinch", "id": id, "room": room})
			if lit_ms >= push_ms:
				var from3 := room
				room = _push_to
				at_door_ms = 0.0
				closed_ms = 0.0
				lit_ms = 0.0
				behind = false
				reset_pacer()
				events.append({"type": "pushed", "id": id, "room": room, "from": from3})
				return events
		if at_door_ms >= attack_ms:
			events.append({"type": "attack", "id": id, "room": room})
	return events


## Is she giving way? Lit at her door for at least half of the stare-down.
func flinching() -> bool:
	return lit_ms > 0.0 and lit_ms >= push_ms / 2.0


## The pose she shows at her door, from how long she has waited (the 2D game's doorPose stages scale with the night's door wait).
func door_pose() -> String:
	var waited := at_door_ms * 5200.0 / maxf(1.0, attack_ms)
	return "lean" if waited > 3600.0 else ("stand" if waited > 1900.0 else "peek")
