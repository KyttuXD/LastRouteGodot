class_name MaskLogic
extends RefCounted

## Masked Hours' rules: a port of createMaskGame in the 2D game's modes/mask/mask-logic.js, number for number. No scene, no input, no Node:
## the shift scene feeds step() the state of the mask, the monitor, the lights and the wind and draws what happens; scripts/
## validate_night_watch_mask.gd replays whole nights headless. It draws from NightWatchMulberry (the 2D mulberry32), so the same seed gives
## the same night as the 2D game, event for event.
##
## step(dt_ms, input) with input {mask, monitor, cam, lightL, lightR, lightH, winding, lamp} returns the events (dictionaries with `type`):
## room / hall / step / office / leave / rush / flashHit / rushRetreat / door / duct / vent / fetch / creep / ventRetreat / dark / boxStart /
## boxEmpty / boxSaved / caught {by} / win. `over` is "win" or "caught" (by whom: `by`).

const NIGHT_MS := 270000.0
const HOUR_MS := NIGHT_MS / 6.0

## AI level (0-20) per night; each hunter moves on the shared random wait (NightWatchPacer), like Classic.
const LEVELS := {
	"thessine": [3, 5, 9, 12, 14, 17],
	"umbriel": [0, 0, 10, 11, 12, 12],
	"verrine": [0, 3, 5, 7, 9, 11],
	"haelith": [0, 0, 0, 6, 4, 3],
	"ilyra": [0, 0, 0, 0, 3, 3],
	"nyxie": [3, 4, 6, 8, 10, 12],
}
## Music box: % lost per second per night. Flashlight: the seconds of light per night, scaled to the shorter night.
const BOX_DECAY := [2.0, 2.0, 3.0, 4.0, 5.0, 6.0]
const FLASH_SECONDS := [117.0, 100.0, 83.0, 67.0, 50.0, 50.0]   # x TIME_SCALE, rounded, see flash_seconds()

const T := {
	"hallSteps": 4, "stepMs": 2300.0, "stepJitter": 0.4,
	"windowMs": 3500.0, "leaveMs": 2500.0, "offGraceMs": 1200.0, "coolMs": 4000.0,
	"coolSpread": 0.05, "offDrain": 0.5,
	"ventWaitMs": 6000.0, "ventNeedMs": 1400.0, "ventCoolMs": 6000.0, "boxGraceMs": 6000.0,
	"ventMaskRate": 0.9, "windPerSec": 12.0,
	"roomMs": 4000.0, "roomJitter": 0.5, "ductMs": 4000.0, "ductJitter": 0.5,
	"hallCool0": 0.0, "ventCool0": 2000.0,
	"rushCoolMs": 12000.0, "rushCool0": 8000.0, "flashCost": 0.25,
	"haelithDuctMs": 1900.0, "haelithDuctJitter": 0.3, "haelithWaitMs": 3400.0, "haelithNeedMs": 500.0, "haelithFetchMs": 1500.0, "haelithCoolMs": 6000.0,
	"ilyraStepMs": 2600.0, "ilyraStepJitter": 0.3, "ilyraSteps": 3, "ilyraVentMs": 3000.0, "ilyraNeedMs": 1200.0, "ilyraCoolMs": 8000.0,
	"ventFrom": {"verrine": 0.0, "haelith": HOUR_MS, "ilyra": 2.0 * HOUR_MS},
	"lampDrain": 0.1, "camDrain": 0.025,
}

## Variety (docs/VARIETY.md): rests +/-30%, vent waits +/-20% (never under 90%), the favoured vent, and the pressure phases.
const VARIETY := {"restSpread": 0.3, "killSpread": 0.2, "killFloor": 0.9, "sideBias": [0.35, 0.65], "salt": 0x3d1f8a57,
	"factors": [0.88, 1.0, 1.12], "ms": [30000.0, 60000.0]}

## Where a watched hunter is held still.
const FREEZE := {"walkerRoom": true, "walkerLastStep": true, "rusherPoised": true, "rusherRun": false, "verrineDuct": true,
	"haelithDuct": true, "ilyraDuct": false, "beamHolds": true, "home": false, "musicBox": false}

static var _dist_to_office: Dictionary = {}

var night_idx := 0
var rng: NightWatchMulberry
var vr: NightWatchMulberry = null
var levels: Dictionary = {}
var infinite_battery := false
var custom := false
var s: Dictionary = {}
var _box_starts := 0.0
var _decay := 0.0
var _flash_per_sec := 0.0


static func flash_seconds(night_index: int) -> float:
	return roundf(float(FLASH_SECONDS[night_index]) * NightWatchData.TIME_SCALE)


static func dark_grace_ms(level: int) -> float:
	return maxf(4000.0, 12500.0 - level * 450.0)


static func box_decay_for_level(level: int) -> float:
	return 0.3 + level * 0.25 if level > 0 else 0.0


static func rush_flashes(level: int) -> int:
	return 3 + (1 if level >= 10 else 0) + (1 if level >= 16 else 0)


static func rush_run_ms(level: int) -> float:
	return maxf(1200.0, 3000.0 - level * 90.0)


static func rush_door_ms(level: int) -> float:
	return maxf(1000.0, 2400.0 - level * 70.0)


static func next_toward(room: String) -> String:
	if _dist_to_office.is_empty():
		_dist_to_office = NightWatchData.distances_to("office", MaskData.GRAPH)
	var best := room
	for r in MaskData.GRAPH.get(room, []):
		if int(_dist_to_office[r]) < int(_dist_to_office[best]):
			best = r
	return best


## Who is on the floor on a night (0-based): the hunters with a level above 0, and Glyra once the music box matters.
static func active_hunters(level_idx: int) -> Array:
	var out := []
	for id in MaskData.CAST:
		if id == "glyra":
			if level_idx >= 1:
				out.append(id)
		elif int((LEVELS[id] as Array)[mini(level_idx, 5)]) > 0:
			out.append(id)
	return out


## The first night each hunter is on the floor (Zellia introduces her that night).
static func first_night(id: String) -> int:
	if id == "glyra":
		return 2
	var lv: Array = LEVELS[id]
	for i in lv.size():
		if int(lv[i]) > 0:
			return i + 1
	return 0


func _init(night: int, rng_in: NightWatchMulberry, opts := {}) -> void:
	night_idx = clampi(night, 1, 6) - 1
	rng = rng_in
	levels = opts.get("levels", {})
	infinite_battery = bool(opts.get("infinite_battery", false))
	custom = bool(opts.get("custom", false))
	var variety := bool(opts.get("variety", true))
	if variety:
		vr = opts["variety_rng"] if opts.has("variety_rng") else NightWatchMulberry.new((rng.get_state() ^ int(VARIETY["salt"])) & 0xFFFFFFFF)
	_decay = box_decay_for_level(int(levels["glyra"])) if levels.has("glyra") and int(levels["glyra"]) >= 0 else float(BOX_DECAY[night_idx])
	_box_starts = 2.0 * HOUR_MS if (not custom and night_idx == 0) else 0.0
	_flash_per_sec = 100.0 / flash_seconds(night_idx)
	_build()


# --- draws -----------------------------------------------------------------------------------------------------------

func _spread_ms(ms: float, spread := 0.2) -> float:
	return ms * (1.0 - spread + 2.0 * spread * rng.next())


func _rest0(ms: float) -> float:
	return _spread_ms(ms, float(VARIETY["restSpread"]) if vr != null else 0.2)


func _kill_wait(ms: float) -> float:
	if vr == null:
		return ms
	var k := float(VARIETY["killSpread"])
	return maxf(ms * float(VARIETY["killFloor"]), ms * (1.0 - k + 2.0 * k * vr.next()))


func _draw_phase() -> Dictionary:
	var f: Array = VARIETY["factors"]
	var v: float = f[mini(f.size() - 1, int(floor(vr.next() * f.size())))]
	var m: Array = VARIETY["ms"]
	return {"v": v, "left": float(m[0]) + vr.next() * (float(m[1]) - float(m[0]))}


func _calm() -> Dictionary:
	return {"v": 1.0, "left": 1e12}


func _step_need() -> float:
	return float(T["stepMs"]) * (1.0 - float(T["stepJitter"]) / 2.0 + rng.next() * float(T["stepJitter"]))


func _room_need() -> float:
	return float(T["roomMs"]) * (1.0 - float(T["roomJitter"]) / 2.0 + rng.next() * float(T["roomJitter"]))


func _duct_need() -> float:
	return float(T["ductMs"]) * (1.0 - float(T["ductJitter"]) / 2.0 + rng.next() * float(T["ductJitter"]))


func _ilyra_need() -> float:
	return float(T["ilyraStepMs"]) * (1.0 - float(T["ilyraStepJitter"]) / 2.0 + rng.next() * float(T["ilyraStepJitter"]))


func _haelith_duct() -> float:
	return float(T["haelithDuctMs"]) * (1.0 - float(T["haelithDuctJitter"]) / 2.0 + rng.next() * float(T["haelithDuctJitter"]))


func _build() -> void:
	var hall := {}
	for id in MaskData.HALL_HUNTERS:
		hall[id] = {"state": "away", "room": MaskData.HOME[id], "t": 0.0, "step": 0, "need": 0.0, "pacer": NightWatchPacer.new(rng),
			"cool": float(T["hallCool0"]), "fooled": 0.0, "off": 0.0, "window": float(T["windowMs"])}
	var vent := {"state": "away", "room": MaskData.HOME["verrine"], "side": "L", "t": 0.0, "need": 0.0, "lit": 0.0, "pacer": NightWatchPacer.new(rng),
		"cool": _rest0(float(T["ventCool0"])), "wait": float(T["ventWaitMs"])}
	var rush := {"state": "away", "room": MaskData.HOME[MaskData.RUSHER], "t": 0.0, "need": 0.0, "flashes": 0, "pacer": NightWatchPacer.new(rng),
		"cool": _rest0(float(T["rushCool0"])), "runs": 0, "flashTotal": 0, "goal": 0, "doorNeed": 0.0}
	var haelith := {"state": "away", "room": MaskData.HOME["haelith"], "side": "L", "t": 0.0, "need": 0.0, "lit": 0.0, "step": 0, "wait": float(T["haelithWaitMs"])}
	var ilyra := {"state": "away", "room": MaskData.HOME["ilyra"], "side": "L", "t": 0.0, "need": 0.0, "lit": 0.0, "step": 0, "wait": float(T["ilyraVentMs"])}
	var side_bias := 0.5
	var mood := {"hall": _calm(), "rush": _calm(), "vent": _calm()}
	if vr != null:
		var sb: Array = VARIETY["sideBias"]
		side_bias = float(sb[0]) + vr.next() * (float(sb[1]) - float(sb[0]))
		mood = {"hall": _draw_phase(), "rush": _draw_phase(), "vent": _draw_phase()}
	s = {"elapsed": 0.0, "battery": 100.0, "box": 100.0, "boxZero": 0.0, "dark": 0.0, "hall": hall, "vent": vent, "haelith": haelith, "ilyra": ilyra,
		"rush": rush, "over": "", "by": "", "flashCount": 0, "flashSpent": 0.0, "prevH": false, "prevV": {"L": false, "R": false}, "ventFlashCount": 0,
		"lamp": false, "frozen": [], "spent": {"light": 0.0, "flash": 0.0, "lamp": 0.0, "cam": 0.0}, "sideBias": side_bias, "mood": mood,
		"lit": {"L": false, "R": false, "H": false}, "boxStarted": false}


# --- queries ---------------------------------------------------------------------------------------------------------

func base_level(id: String) -> int:
	if levels.has(id) and int(levels[id]) >= 0:
		return int(levels[id])
	return int((LEVELS[id] as Array)[night_idx])


func level(id: String) -> int:
	return NightWatchData.effective_level(base_level(id), NightWatchData.hour_index(float(s["elapsed"])))


func vent_state(id: String) -> Dictionary:
	return s["vent"] if id == "verrine" else s[id]


## Who is out in the ducts or vents right now (at most one), or {}: {id, side, state: "duct" | "vent" | "fetch", room}.
func vent_occupant() -> Dictionary:
	for id in MaskData.VENT_HUNTERS:
		var h := vent_state(id)
		if String(h["state"]) != "away":
			return {"id": id, "side": h["side"], "state": h["state"], "room": h["room"]}
	return {}


func _vent_out() -> bool:
	return String(s["vent"]["state"]) != "away" or String(s["haelith"]["state"]) != "away" or String(s["ilyra"]["state"]) != "away"


## What the player can SEE of a vent hunter in the office's vent opening: only while the light is on that side.
func vent_seen(side: String) -> String:
	var o := vent_occupant()
	if not o.is_empty() and String(o["state"]) == "vent" and String(o["side"]) == side and bool(s["lit"][side]):
		return String(o["id"])
	return ""


## The only trace of a hunter in the dark: eyeshine at a fixed spot in the duct she is in (a camera).
func glint(room: String) -> bool:
	var o := vent_occupant()
	return not o.is_empty() and MaskData.DUCT_SIDE.has(room) and String(o["state"]) == "duct" and String(o["room"]) == room \
		and not bool(s["lit"][MaskData.DUCT_SIDE[room]])


func vent_glint(side: String) -> bool:
	var o := vent_occupant()
	return not o.is_empty() and String(o["state"]) == "vent" and String(o["side"]) == side and not bool(s["lit"][side])


func _in_office() -> String:
	for id in MaskData.HALL_HUNTERS:
		if String(s["hall"][id]["state"]) == "office":
			return id
	return ""


func _walker_in_hall() -> bool:
	for id in MaskData.HALL_HUNTERS:
		var st := String(s["hall"][id]["state"])
		if st == "hall" or st == "office":
			return true
	return false


func _rusher_in_hall() -> bool:
	var st := String(s["rush"]["state"])
	return st == "run" or st == "door"


## What a camera shows: [{id, at}] with `at` one of stand / far / near / crouch / mid (where in the picture, for the scene).
func cam_figures(room: String) -> Array:
	var figs := []
	for id in s["hall"]:
		var h: Dictionary = s["hall"][id]
		if level(id) <= 0:
			continue
		if room == "hall":
			if String(h["state"]) == "hall" and int(h["step"]) >= int(T["hallSteps"]) - 1:
				figs.append({"id": id, "at": "stand"})
		elif String(h["room"]) == room:
			figs.append({"id": id, "at": "stand"})
	var r: Dictionary = s["rush"]
	if level(MaskData.RUSHER) > 0 and String(r["room"]) == room:
		if room == "hall":
			var p := 1.0 if String(r["state"]) == "door" else minf(1.0, float(r["t"]) / float(r["need"]))
			figs.append({"id": MaskData.RUSHER, "at": "run", "progress": p})
		elif String(r["state"]) == "poised":
			figs.append({"id": MaskData.RUSHER, "at": "crouch"})
		else:
			figs.append({"id": MaskData.RUSHER, "at": "stand"})
	var lit := bool(s["lit"][MaskData.DUCT_SIDE[room]]) if MaskData.DUCT_SIDE.has(room) else true
	if lit:
		for id in MaskData.VENT_HUNTERS:
			var h2 := vent_state(id)
			if String(h2["room"]) != room or level(id) <= 0:
				continue
			var at := "stand"
			if id == "ilyra" and MaskData.DUCT_SIDE.has(room):
				at = ["far", "stand", "near"][clampi(int(h2["step"]) - 1, 0, 2)]
			figs.append({"id": id, "at": at})
	return figs


# --- the clock -------------------------------------------------------------------------------------------------------

func _finish(ev: Array, by: String) -> Array:
	s["over"] = "caught"
	s["by"] = by
	ev.append({"type": "caught", "by": by})
	return ev


func _rest(h: Dictionary, home: String, ms: float, id: String, ev: Array) -> void:
	h["state"] = "away"
	h["room"] = home
	var vent: Dictionary = s["vent"]
	vent["cool"] = _rest0(ms)
	(vent["pacer"] as NightWatchPacer).reset()
	ev.append({"type": "ventRetreat", "id": id, "side": h["side"]})


## Advance by dt_ms with the player's current inputs. Returns the events in order; `caught` ends the game.
func step(dt_ms: float, input := {}) -> Array:
	if String(s["over"]) != "":
		return []
	var ev := []
	var dt := dt_ms / 1000.0
	s["elapsed"] = float(s["elapsed"]) + dt_ms
	if vr != null:
		for k in ["hall", "rush", "vent"]:
			var ph: Dictionary = s["mood"][k]
			ph["left"] = float(ph["left"]) - dt_ms
			if float(ph["left"]) <= 0.0:
				var nxt := _draw_phase()
				ph["v"] = nxt["v"]
				ph["left"] = nxt["left"]
	var mood: Dictionary = s["mood"]
	var spent: Dictionary = s["spent"]

	# Battery: the lights, the desk lamp and the monitor all draw on it; the monitor still works at 0 (the building's emergency feed).
	var lit := {"L": false, "R": false, "H": false}
	if float(s["battery"]) > 0.0:
		lit = {"L": bool(input.get("lightL", false)), "R": bool(input.get("lightR", false)) and not bool(input.get("lightL", false)), "H": bool(input.get("lightH", false))}
	var using: bool = lit["L"] or lit["R"] or lit["H"]
	s["lamp"] = float(s["battery"]) > 0.0 and bool(input.get("lamp", false))
	var monitor := bool(input.get("monitor", false))
	if not infinite_battery:
		var want := {"light": _flash_per_sec * dt if using else 0.0, "lamp": _flash_per_sec * float(T["lampDrain"]) * dt if bool(s["lamp"]) else 0.0,
			"cam": _flash_per_sec * float(T["camDrain"]) * dt if monitor and float(s["battery"]) > 0.0 else 0.0}
		for k in ["light", "lamp", "cam"]:
			var c := minf(float(s["battery"]), float(want[k]))
			s["battery"] = float(s["battery"]) - c
			spent[k] = float(spent[k]) + c
	# A flash: the hall light coming on. Each one costs a little extra charge.
	var flash: bool = lit["H"] and not bool(s["prevH"])
	s["prevH"] = lit["H"]
	if flash:
		s["flashCount"] = int(s["flashCount"]) + 1
		if not infinite_battery:
			var c2 := minf(float(s["battery"]), float(T["flashCost"]))
			s["battery"] = float(s["battery"]) - c2
			s["flashSpent"] = float(s["flashSpent"]) + c2
			spent["flash"] = float(spent["flash"]) + c2
	# A vent light coming on is a flash as well; swapping from one vent to the other is a new light coming on.
	for side in ["L", "R"]:
		if lit[side] and not bool(s["prevV"][side]):
			s["ventFlashCount"] = int(s["ventFlashCount"]) + 1
			if not infinite_battery:
				var c3 := minf(float(s["battery"]), float(T["flashCost"]))
				s["battery"] = float(s["battery"]) - c3
				s["flashSpent"] = float(s["flashSpent"]) + c3
				spent["flash"] = float(spent["flash"]) + c3
		s["prevV"][side] = lit[side]
	s["lit"] = lit
	var mask := bool(input.get("mask", false))
	var watched := String(input.get("cam", "")) if monitor else ""
	var frozen := []
	s["frozen"] = frozen

	# The dark: with the battery gone she is coming, and nothing you do brings the light back.
	var nyx := base_level("nyxie")
	if float(s["battery"]) <= 0.0 and nyx > 0:
		if float(s["dark"]) == 0.0:
			ev.append({"type": "dark", "id": "nyxie"})
		s["dark"] = float(s["dark"]) + dt_ms
		if float(s["dark"]) >= dark_grace_ms(nyx):
			return _finish(ev, "nyxie")

	# Music box. On night 1 it is wound and silent until 2 AM.
	if _box_starts > 0.0 and not bool(s["boxStarted"]) and float(s["elapsed"]) >= _box_starts:
		s["boxStarted"] = true
		ev.append({"type": "boxStart"})
	var drain := _decay if float(s["elapsed"]) >= _box_starts else 0.0
	s["box"] = maxf(0.0, minf(100.0, float(s["box"]) - drain * dt + (float(T["windPerSec"]) * dt if bool(input.get("winding", false)) else 0.0)))
	if float(s["box"]) <= 0.0:
		if float(s["boxZero"]) == 0.0:
			ev.append({"type": "boxEmpty"})
		s["boxZero"] = float(s["boxZero"]) + dt_ms
		if float(s["boxZero"]) >= float(T["boxGraceMs"]):
			return _finish(ev, "glyra")
	elif float(s["boxZero"]) > 0.0:
		s["boxZero"] = 0.0
		ev.append({"type": "boxSaved"})

	# Hall hunters.
	for id in MaskData.HALL_HUNTERS:
		var h: Dictionary = s["hall"][id]
		var st := String(h["state"])
		if st == "away":
			h["cool"] = maxf(0.0, float(h["cool"]) - dt_ms * float(mood["hall"]["v"]))
			if float(h["cool"]) <= 0.0 and (h["pacer"] as NightWatchPacer).step(dt_ms * float(mood["hall"]["v"]), level(id)):
				h["state"] = "room"
				h["room"] = next_toward(String(h["room"]))
				h["t"] = 0.0
				h["need"] = _room_need()
				ev.append({"type": "room", "id": id, "room": h["room"]})
		elif st == "room":
			if watched == String(h["room"]):
				frozen.append(id)
			else:
				h["t"] = float(h["t"]) + dt_ms
			if float(h["t"]) >= float(h["need"]):
				var nxt2 := next_toward(String(h["room"]))
				if nxt2 == "hall" and _rusher_in_hall():
					pass   # one at a time: she waits at the hall doors while Umbriel is in the hall
				elif nxt2 == "hall":
					h["state"] = "hall"
					h["room"] = "hall"
					h["t"] = 0.0
					h["step"] = 0
					h["need"] = _step_need()
					ev.append({"type": "hall", "id": id})
				else:
					h["room"] = nxt2
					h["t"] = 0.0
					h["need"] = _room_need()
					ev.append({"type": "room", "id": id, "room": h["room"]})
		elif st == "hall":
			var on_cam: bool = watched == "hall" and int(h["step"]) >= int(T["hallSteps"]) - 1
			if on_cam:
				frozen.append(id)
			if not lit["H"] and not on_cam:
				h["t"] = float(h["t"]) + dt_ms
			if float(h["t"]) >= float(h["need"]) and int(h["step"]) < int(T["hallSteps"]):
				h["t"] = 0.0
				h["step"] = int(h["step"]) + 1
				h["need"] = _step_need()
				ev.append({"type": "step", "id": id, "step": h["step"]})
			if int(h["step"]) >= int(T["hallSteps"]) and _in_office() == "":
				h["state"] = "office"
				h["room"] = "office"
				h["t"] = 0.0
				h["step"] = 0
				h["fooled"] = 0.0
				h["off"] = 0.0
				h["window"] = float(T["windowMs"])
				(h["pacer"] as NightWatchPacer).reset()
				ev.append({"type": "office", "id": id})
		elif st == "office":
			if mask:
				h["fooled"] = float(h["fooled"]) + dt_ms
				h["off"] = maxf(0.0, float(h["off"]) - dt_ms * float(T["offDrain"]))
				if float(h["fooled"]) >= float(T["leaveMs"]):
					h["state"] = "away"
					h["room"] = MaskData.HOME[id]
					h["cool"] = _spread_ms(float(T["coolMs"]), float(T["coolSpread"]))
					(h["pacer"] as NightWatchPacer).reset()
					ev.append({"type": "leave", "id": id})
			elif float(h["fooled"]) == 0.0:
				h["window"] = float(h["window"]) - dt_ms
				if float(h["window"]) <= 0.0:
					return _finish(ev, id)
			else:
				h["off"] = float(h["off"]) + dt_ms
				if float(h["off"]) >= float(T["offGraceMs"]):
					return _finish(ev, id)

	# The rusher. The mask is not checked anywhere here: it does nothing to her.
	var r: Dictionary = s["rush"]
	var rl := level(MaskData.RUSHER)
	if String(r["state"]) == "away":
		r["cool"] = maxf(0.0, float(r["cool"]) - dt_ms * float(mood["rush"]["v"]))
		if float(r["cool"]) <= 0.0 and (r["pacer"] as NightWatchPacer).step(dt_ms * float(mood["rush"]["v"]), rl):
			r["state"] = "poised"
			r["room"] = "ballroom"
			r["t"] = 0.0
			r["need"] = _room_need()
			ev.append({"type": "room", "id": MaskData.RUSHER, "room": "ballroom", "poised": true})
	elif String(r["state"]) == "poised":
		if watched == "ballroom":
			frozen.append(MaskData.RUSHER)
		else:
			r["t"] = float(r["t"]) + dt_ms
		if float(r["t"]) >= float(r["need"]) and not _walker_in_hall():
			r["state"] = "run"
			r["room"] = "hall"
			r["t"] = 0.0
			r["need"] = rush_run_ms(rl)
			r["flashes"] = 0
			r["runs"] = int(r["runs"]) + 1
			r["goal"] = rush_flashes(rl)
			r["doorNeed"] = rush_door_ms(rl)
			ev.append({"type": "rush", "id": MaskData.RUSHER, "flashes": r["goal"]})
	else:
		if flash:
			r["flashes"] = int(r["flashes"]) + 1
			r["flashTotal"] = int(r["flashTotal"]) + 1
			ev.append({"type": "flashHit", "id": MaskData.RUSHER, "n": r["flashes"], "of": r["goal"]})
		r["t"] = float(r["t"]) + dt_ms
		if int(r["flashes"]) >= int(r["goal"]):
			r["state"] = "away"
			r["room"] = MaskData.HOME[MaskData.RUSHER]
			r["cool"] = _rest0(float(T["rushCoolMs"]))
			(r["pacer"] as NightWatchPacer).reset()
			ev.append({"type": "rushRetreat", "id": MaskData.RUSHER})
		elif String(r["state"]) == "run" and float(r["t"]) >= float(r["need"]):
			r["state"] = "door"
			r["t"] = 0.0
			r["need"] = r["doorNeed"]
			ev.append({"type": "door", "id": MaskData.RUSHER})
		elif String(r["state"]) == "door" and float(r["t"]) >= float(r["need"]):
			return _finish(ev, MaskData.RUSHER)

	# The vents: one clock, one visitor at a time. When the clock fires, who comes is drawn from the vent hunters on the floor.
	var vent: Dictionary = s["vent"]
	var haelith: Dictionary = s["haelith"]
	var ilyra: Dictionary = s["ilyra"]
	if not _vent_out():
		vent["cool"] = maxf(0.0, float(vent["cool"]) - dt_ms * float(mood["vent"]["v"]))
		var pool := []
		var top := 0
		for id in MaskData.VENT_HUNTERS:
			if level(id) > 0 and float(s["elapsed"]) >= float(T["ventFrom"][id]):
				pool.append(id)
				top = maxi(top, level(id))
		if float(vent["cool"]) <= 0.0 and (vent["pacer"] as NightWatchPacer).step(dt_ms * float(mood["vent"]["v"]), top):
			var who: String = pool[0]
			if pool.size() > 1:
				var total := 0
				for id in pool:
					total += level(id)
				var roll := rng.next() * total
				who = String(pool[pool.size() - 1])
				for id in pool:
					roll -= level(id)
					if roll < 0.0:
						who = id
						break
			var side := "L" if rng.next() < float(s["sideBias"]) else "R"
			var duct: String = MaskData.DUCTS[0 if side == "L" else 1]
			if who == "verrine":
				vent["side"] = side
				vent["state"] = "duct"
				vent["room"] = duct
				vent["t"] = 0.0
				vent["need"] = _duct_need()
				ev.append({"type": "duct", "id": "verrine", "side": side, "room": duct})
			elif who == "haelith":
				haelith.merge({"side": side, "state": "duct", "room": duct, "t": 0.0, "need": _haelith_duct(), "lit": 0.0, "step": 0}, true)
				ev.append({"type": "duct", "id": "haelith", "side": side, "room": duct, "leg": 0})
			else:
				ilyra.merge({"side": side, "state": "duct", "room": duct, "t": 0.0, "need": _ilyra_need(), "lit": 0.0, "step": 1}, true)
				ev.append({"type": "duct", "id": "ilyra", "side": side, "room": duct, "step": 1})

	# Verrine.
	if String(vent["state"]) == "duct":
		if watched == String(vent["room"]):
			frozen.append("verrine")
		else:
			vent["t"] = float(vent["t"]) + dt_ms
		if float(vent["t"]) >= float(vent["need"]):
			vent["state"] = "vent"
			vent["room"] = next_toward(String(vent["room"]))
			vent["t"] = 0.0
			vent["lit"] = 0.0
			vent["wait"] = _kill_wait(float(T["ventWaitMs"]))
			ev.append({"type": "vent", "id": "verrine", "side": vent["side"]})
	elif String(vent["state"]) == "vent":
		if mask:
			vent["t"] = float(vent["t"]) + dt_ms * float(T["ventMaskRate"])
		elif lit[String(vent["side"])]:
			vent["lit"] = float(vent["lit"]) + dt_ms
		else:
			vent["lit"] = maxf(0.0, float(vent["lit"]) - dt_ms * 0.5)
			vent["t"] = float(vent["t"]) + dt_ms
		if float(vent["lit"]) >= float(T["ventNeedMs"]):
			_rest(vent, MaskData.HOME["verrine"], float(T["ventCoolMs"]), "verrine", ev)
		elif float(vent["t"]) >= float(vent["wait"]):
			return _finish(ev, "verrine")

	# Haelith, the fetcher: bounds down a duct, waits for a quick throw of the light, fetches it across to the other duct, wants it there too.
	var hs := String(haelith["state"])
	if hs == "duct":
		if watched == String(haelith["room"]):
			frozen.append("haelith")
		else:
			haelith["t"] = float(haelith["t"]) + dt_ms
		if float(haelith["t"]) >= float(haelith["need"]):
			haelith["state"] = "vent"
			haelith["room"] = next_toward(String(haelith["room"]))
			haelith["t"] = 0.0
			haelith["lit"] = 0.0
			haelith["wait"] = _kill_wait(float(T["haelithWaitMs"]))
			ev.append({"type": "vent", "id": "haelith", "side": haelith["side"]})
	elif hs == "fetch":
		haelith["t"] = float(haelith["t"]) + dt_ms
		if float(haelith["t"]) >= float(T["haelithFetchMs"]):
			haelith["side"] = "R" if String(haelith["side"]) == "L" else "L"
			haelith["state"] = "duct"
			haelith["room"] = MaskData.DUCTS[0 if String(haelith["side"]) == "L" else 1]
			haelith["t"] = 0.0
			haelith["need"] = _haelith_duct()
			haelith["lit"] = 0.0
			ev.append({"type": "duct", "id": "haelith", "side": haelith["side"], "room": haelith["room"], "leg": 1})
	elif hs == "vent":
		var beam_h: bool = not mask and lit[String(haelith["side"])]
		if beam_h:
			haelith["lit"] = float(haelith["lit"]) + dt_ms
		else:
			haelith["lit"] = maxf(0.0, float(haelith["lit"]) - dt_ms * 0.5)
			haelith["t"] = float(haelith["t"]) + dt_ms
		if float(haelith["lit"]) >= float(T["haelithNeedMs"]):
			if int(haelith["step"]) == 0:
				var to_side := "R" if String(haelith["side"]) == "L" else "L"
				haelith["step"] = 1
				haelith["state"] = "fetch"
				haelith["room"] = MaskData.HOME["haelith"]
				haelith["t"] = 0.0
				haelith["lit"] = 0.0
				ev.append({"type": "fetch", "id": "haelith", "side": haelith["side"], "to": to_side})
			else:
				haelith["step"] = 0
				haelith["t"] = 0.0
				haelith["lit"] = 0.0
				_rest(haelith, MaskData.HOME["haelith"], float(T["haelithCoolMs"]), "haelith", ev)
		elif float(haelith["t"]) >= float(haelith["wait"]):
			return _finish(ev, "haelith")

	# Ilyra, the creeper: a step only in the dark, frozen in the light, sent home by enough light.
	if String(ilyra["state"]) != "away":
		var beam_i: bool = not mask and lit[String(ilyra["side"])]
		if beam_i:
			ilyra["lit"] = float(ilyra["lit"]) + dt_ms
		else:
			ilyra["lit"] = maxf(0.0, float(ilyra["lit"]) - dt_ms)
			ilyra["t"] = float(ilyra["t"]) + dt_ms
		if float(ilyra["lit"]) >= float(T["ilyraNeedMs"]):
			ilyra["step"] = 0
			ilyra["t"] = 0.0
			ilyra["lit"] = 0.0
			_rest(ilyra, MaskData.HOME["ilyra"], float(T["ilyraCoolMs"]), "ilyra", ev)
		elif String(ilyra["state"]) == "duct" and float(ilyra["t"]) >= float(ilyra["need"]):
			ilyra["step"] = int(ilyra["step"]) + 1
			ilyra["t"] = 0.0
			if int(ilyra["step"]) <= int(T["ilyraSteps"]):
				ilyra["need"] = _ilyra_need()
				ev.append({"type": "creep", "id": "ilyra", "side": ilyra["side"], "step": ilyra["step"]})
			else:
				ilyra["state"] = "vent"
				ilyra["room"] = next_toward(String(ilyra["room"]))
				ilyra["wait"] = _kill_wait(float(T["ilyraVentMs"]))
				ev.append({"type": "vent", "id": "ilyra", "side": ilyra["side"]})
		elif String(ilyra["state"]) == "vent" and float(ilyra["t"]) >= float(ilyra["wait"]):
			return _finish(ev, "ilyra")

	if float(s["elapsed"]) >= NIGHT_MS:
		s["over"] = "win"
		ev.append({"type": "win"})
	return ev
