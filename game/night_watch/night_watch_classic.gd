class_name NightWatchClassic
extends RefCounted

## Night Watch Classic: the night's rules (a port of createClassicGame in the 2D game plus the power meter that
## lives in the 2D scene). No scene, no input, no Node: the shift scene feeds it the state of the doors, lights and monitor and
## draws what happens, and tests/validate_night_watch.gd replays whole nights headless. The same seed gives the same night.
##
## step(dt_ms, input) with input {doorL, doorR: shut, lightL, lightR: held, cam: monitor up, cam_room} returns the events:
##   moved / arrived / repelled / pushed / flinch {id, room, from}, attack {id, room}, out {} (power gone),
##   caught {id} / win {} (the night is over: `over` is "caught" or "win", `by` the hunter).

var night := 1
var seed_value := 0
var elapsed := 0.0
var over := ""
var by := ""
var power := 100.0
var out := false
var out_ms := 0.0
var hunters := {}
var nyxie_level := 0
## The doors and lights as the rules saw them on the last step (doors open and lights dark once the power is out).
var door_shut := {"doorL": false, "doorR": false}
var light_on := {"doorL": false, "doorR": false}

var _rng := RandomNumberGenerator.new()
var _tuning := {}
var _lines := {"doorL": [], "doorR": []}
var kathy_night := false
## Admin hooks (NightWatchAdmin): god mode (attacks are shrugged off), infinite power, hunter speed multiplier. All off / 1.0 normally.
var god := false
var infinite_power := false
var hunter_speed := 1.0
var _hum_t := 0.0
var _meet_lock_ms := 0.0


## `levels` optionally overrides the night's AI levels { id: level } (Custom Night, admin tools, tests).
func _init(night_number: int = 1, seed_number: int = 0, levels: Dictionary = {}, custom := false) -> void:
	night = clampi(night_number, 1, NightWatchData.NIGHTS)
	seed_value = seed_number
	_rng.seed = seed_number
	var i := NightWatchData.night_index(night)
	_tuning = {"grace_ms": NightWatchData.DOOR_GRACE_MS[i], "pace": NightWatchData.NIGHT_PACE[i],
		"push_ms": NightWatchData.LIGHT_PUSH_MS[i]}
	kathy_night = NightWatchData.is_kathy_night(night, custom)
	if kathy_night:
		# Night 7: Kathy alone, on Night 6's door pacing scaled (she walks faster, waits less at an open door; the light never moves her)
		var k := NightWatchData.KATHY
		var grace := roundf(float(_tuning["grace_ms"]) * float(k["grace_scale"]))
		var pace := snappedf(float(_tuning["pace"]) * float(k["pace_scale"]), 0.001)
		hunters["kathy"] = NightWatchStalker.make_kathy(_rng, int(levels["kathy"]) if levels.has("kathy") else int(k["level"]), grace, pace)
		nyxie_level = 0
		return
	for id in NightWatchData.HUNTERS:
		var base := int(levels[id]) if levels.has(id) else NightWatchData.level_for(id, night)
		hunters[id] = NightWatchStalker.make(id, _rng, base, float(_tuning["grace_ms"]), float(_tuning["pace"]),
			float(_tuning["push_ms"]), _occupied.bind(id))
	nyxie_level = int(levels["nyxie"]) if levels.has("nyxie") else NightWatchData.nyxie_level(night)


func _occupied(room: String, except: String) -> bool:
	if not room.begins_with("door"):
		return false
	var n := 0
	for id in hunters:
		if id != except and (hunters[id] as NightWatchStalker).room == room:
			n += 1
	return n >= NightWatchData.DOOR_CAPACITY


func hour() -> int:
	return NightWatchData.hour_index(elapsed)


## Who is at a door, in the order they arrived (front first).
func at_door(door: String) -> Array:
	_refresh_lines()
	var out_list := []
	for id in _lines[door]:
		out_list.append(hunters[id])
	return out_list


func _refresh_lines() -> void:
	for door in _lines:
		var kept := []
		for id in _lines[door]:
			if (hunters[id] as NightWatchStalker).room == door:
				kept.append(id)
		_lines[door] = kept
	for id in hunters:
		var r: String = (hunters[id] as NightWatchStalker).room
		if _lines.has(r) and not _lines[r].has(id):
			_lines[r].append(id)


## Devices in use (door shut, light held, monitor up) for the power drain and the HUD.
static func usage(input: Dictionary) -> int:
	var n := 0
	for key in ["doorL", "doorR", "lightL", "lightR", "cam"]:
		if bool(input.get(key, false)):
			n += 1
	return n


func step(dt_ms: float, input: Dictionary = {}) -> Array:
	var events := []
	if over != "":
		return events
	elapsed += dt_ms
	var h := hour()
	# Power: base drain plus a little for every device in use. At zero the doors open, the lights fail and Nyxie comes.
	if not out and not infinite_power:
		power = maxf(0.0, power - (NightWatchData.POWER_BASE + NightWatchData.POWER_PER_DEVICE * usage(input)) * dt_ms / 1000.0)
		if power <= 0.0:
			out = true
			out_ms = 0.0
			events.append({"type": "out"})
	else:
		out_ms += dt_ms
	var shut := {"doorL": bool(input.get("doorL", false)) and not out, "doorR": bool(input.get("doorR", false)) and not out}
	var lit := {"doorL": bool(input.get("lightL", false)) and not out, "doorR": bool(input.get("lightR", false)) and not out}
	door_shut = shut
	light_on = lit
	var ctx := {"cam": bool(input.get("cam", false)) and not out, "cam_room": String(input.get("cam_room", "")), "lit": lit}
	for id in hunters:
		var hunter := hunters[id] as NightWatchStalker
		hunter.level = NightWatchData.effective_level(hunter.base, h)
		# Working together: while a partner already waits at a door, this one's patience runs out sooner.
		var patience := 0.0
		for combo in NightWatchData.COMBOS:
			if not (combo["ids"] as Array).has(id):
				continue
			var other_id: String = combo["ids"][0] if combo["ids"][1] == id else combo["ids"][1]
			var other := hunters[other_id] as NightWatchStalker
			if other.room.begins_with("door") and other.level >= int(combo["min_level"]) \
					and hunter.level >= int(combo["min_level"]):
				patience = maxf(patience, float(combo["patience_ms"]))
		if not kathy_night:
			hunter.attack_ms = float(_tuning["grace_ms"]) - patience
		_refresh_lines()
		var line: Array = _lines.get(hunter.room, [])
		var is_behind := not line.is_empty() and line.find(id) > 0
		var step_ctx := ctx.duplicate()
		if is_behind:
			step_ctx["behind"] = true
		var stepped := hunter.step(dt_ms * hunter_speed, bool(shut.get(hunter.door(), false)), step_ctx)
		for e in stepped:
			events.append(e)
			if String(e["type"]) == "attack":
				if god:
					hunter.at_door_ms = 0.0   # god mode: she is sent back to wait again instead of catching you
					continue
				over = "caught"
				by = id
				events.append({"type": "caught", "id": id})
		if over != "":
			return events
	# Nyxie never walks the building: in the dark she reaches the office after a while.
	if out and nyxie_level > 0 and not god and out_ms >= NightWatchData.blackout_ms(nyxie_level):
		over = "caught"
		by = "nyxie"
		events.append({"type": "caught", "id": "nyxie", "cause": "darkness"})
		return events
	if kathy_night:
		_meet_lock_ms = maxf(0.0, _meet_lock_ms - dt_ms)
		var kathy := hunters["kathy"] as NightWatchStalker
		if kathy.is_at_door():
			_hum_t += dt_ms
			if _hum_t >= float(NightWatchData.KATHY["hum_ms"]):
				_hum_t = 0.0
				events.append({"type": "hum", "id": "kathy", "door": kathy.door(), "muffled": bool(shut.get(kathy.door(), false))})
		else:
			_hum_t = 0.0
	_refresh_lines()
	if elapsed >= NightWatchData.NIGHT_MS:
		over = "win"
		events.append({"type": "win"})
	return events


## The pose each hunter at a door shows, front first (for the scene).
func door_poses(door: String) -> Array:
	var poses := []
	for hunter in at_door(door):
		poses.append((hunter as NightWatchStalker).door_pose())
	return poses


## Night 7's tell: is this door's light dipping right now? Only while she stands at that door and its light is on (open or shut).
func light_dip(door: String) -> bool:
	if not kathy_night or not bool(light_on.get(door, false)):
		return false
	var kathy := hunters["kathy"] as NightWatchStalker
	return kathy.room == door and NightWatchData.kathy_dip_on(elapsed)


## Meet her eyes (Night 7): works while she is on the feed you are watching and that feed is one of the two halls; she fades back to the stage or the kitchen on a fresh
## door. Anything else is a miss, and the key is dead for KATHY_MISS_LOCK_MS after it. Returns {"result": "met" | "miss" | "locked" | "none", "events": [...]}.
func meet(cam: bool, cam_room: String, lost := false) -> Dictionary:
	if not kathy_night or over != "":
		return {"result": "none", "events": []}
	if _meet_lock_ms > 0.0:
		return {"result": "locked", "events": []}
	var kathy := hunters["kathy"] as NightWatchStalker
	if cam and not lost and not out and cam_room == kathy.room and NightWatchData.KATHY_MEET_ROOMS.has(kathy.room):
		var from := kathy.room
		kathy.fade()
		return {"result": "met", "events": [{"type": "repelled", "id": "kathy", "room": kathy.room, "from": from}]}
	_meet_lock_ms = NightWatchData.KATHY_MISS_LOCK_MS
	return {"result": "miss", "events": []}
