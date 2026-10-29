class_name GrabStyles
extends RefCounted

## How a hunter takes hold of a runner it has caught (docs/HUNTER_GRABS.md). Every hunter has a weighted pool of styles in
## res://data/grabs/<hunter_id>.json (schema lr.grab/1, the per-id layout of docs/DATA_DRIVEN_CONTENT.md, so a content pack can
## later ship grabs/<id>.json and list "grabs/<id>" under its manifest's overrides). On a catch the host rolls one number per
## catch (roll_for, seeded) and sends it with the capture event; the caught runner drops every style its surroundings rule out
## (a lift under a low ceiling, a wall pin with no wall, a tackle into a wall) and picks from the rest with that roll. The
## runner's state then carries the chosen pose to every peer, so everybody sees the same grab.
##
## The poses themselves are code (pose()): data only says who uses which style how often.

const SCHEMA := "lr.grab/1"
const ROOT := "res://data/grabs"

const NECK_LIFT := "neck_lift"
const SHOULDER_GRAB := "shoulder_grab"
const TACKLE := "tackle"
const WRIST_YANK := "wrist_yank"
const WRAP := "wrap"
const LEG_GRAB := "leg_grab"
const UPSIDE_DOWN := "upside_down"
const SHOULDER_CARRY := "shoulder_carry"
const COLLAR_DRAG := "collar_drag"
const WALL_PIN := "wall_pin"
const POUNCE_PIN := "pounce_pin"

## Every style and what it needs around the runner. `ceiling`: clear height above the runner's floor; `back`: clear floor
## behind the runner (away from the hunter); `side`: clear floor to both sides of the runner; `wall`: a wall at most this far behind the runner; `hunter_back`: clear floor
## behind the hunter (it steps back); `creature`: only for the non-humanoid rigs (and they use nothing else).
const STYLES := {
	NECK_LIFT: {"short": "NL", "ceiling": 2.5},
	SHOULDER_GRAB: {"short": "SG"},
	TACKLE: {"short": "TK", "back": 1.7},
	WRIST_YANK: {"short": "WY"},
	WRAP: {"short": "WR"},
	LEG_GRAB: {"short": "LG", "back": 1.8},
	UPSIDE_DOWN: {"short": "UD", "ceiling": 2.4, "back": 1.5},   # the head swings out past the feet as they go up
	SHOULDER_CARRY: {"short": "SC", "ceiling": 2.75, "back": 2.8},   # stands tall with the runner up, then walks on
	COLLAR_DRAG: {"short": "CD", "hunter_back": 1.6},
	WALL_PIN: {"short": "WP", "wall": 1.3},
	POUNCE_PIN: {"short": "PP", "back": 1.7, "creature": true},
}
## When nothing in a pool fits the spot, these always do.
const FALLBACK := SHOULDER_GRAB
const CREATURE_FALLBACK := POUNCE_PIN

## Seconds: the hunter reaches, the grab plays out, then holds before the run ends.
const REACH_SECONDS := .35
const ACT_SECONDS := .7
const HOLD_SECONDS := .85
const TOTAL_SECONDS := REACH_SECONDS + ACT_SECONDS + HOLD_SECONDS
## The shoulder carry walks a few steps before the end, so it runs longer; the longest grab bounds every timer.
const CARRY_METRES := 2.4
const CARRY_SECONDS := 3.2
const MAX_SECONDS := CARRY_SECONDS


static func duration(style: String) -> float:
	return CARRY_SECONDS if style == SHOULDER_CARRY else TOTAL_SECONDS

## Points on the 2.2 m runner body (measured at 1.60 m, times PlayerModels.SCALE / 0.9) the hunter's hands go to, in the body's own frame (facing -Z, +X its right, feet at 0).
const BODY_POINTS := {
	"neck": Vector3(0, 1.483, -0.233),
	"l_shoulder": Vector3(-0.412, 1.744, -0.041),
	"r_shoulder": Vector3(0.412, 1.744, -0.041),
	"l_wrist": Vector3(-0.48, 1.52, -0.58),   # held out low and to the side, not up in front of the runner's own face
	"back_l": Vector3(-0.33, 1.442, 0.11),
	"back_r": Vector3(0.33, 1.442, 0.11),
	"r_ankle": Vector3(0.137, 0.343, 0.137),   # the lower calf just above the ankle: her big hand closes round it clear of the floor
	"knees": Vector3(0, 1.099, -0.371),   # the front of the thighs, legs folded down her front in the shoulder carry (0.8 / -0.27 at the old 1.60 m)
}
## The mannequin's joints these points were measured from (at the old scale .9; multiplied by 1.236 / 0.9 here): neck pivot 1.18, shoulders 1.08 (arm tops ~1.2),
## arms .44 long, torso .2 deep, head .4. Contacts sit just off the surface so a hunter's (much bigger) hand closes on it.

## Standing eye height of the runner the poses assume when no real camera is involved (the other players' view of a body).
const BODY_EYE := 1.868   # 1.36 at the old 1.60 m runner, times PlayerModels.SCALE / 0.9

static var _pools := {}
static var _looks := {}
static var _errors := PackedStringArray()
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var files := Array(DirAccess.get_files_at(ROOT))
	files.sort()
	for file_name in files:
		if String(file_name).ends_with(".json"):
			var parsed := parse_file("%s/%s" % [ROOT, file_name])
			_errors.append_array(parsed["errors"])
			if not parsed["def"].is_empty():
				_pools[String(parsed["def"]["id"])] = parsed["def"]["pool"]
				_looks[String(parsed["def"]["id"])] = parsed["def"]["look"]
	for message in _errors:
		push_error("GrabStyles: " + message)


static func errors() -> PackedStringArray:
	ensure_loaded()
	return _errors


## One lr.grab/1 file -> {"def": {"id", "pool": {style: weight}}, "errors": [...]}. Unknown keys, unknown styles and
## non-positive weights are errors naming the file, like ContentRegistry.
static func parse_file(path: String) -> Dictionary:
	var out := {"def": {}, "errors": PackedStringArray()}
	var text := FileAccess.get_file_as_string(path)
	var data = JSON.parse_string(text)
	if not data is Dictionary:
		out["errors"].append("%s: not a JSON object" % path)
		return out
	return parse_def(data, path)


static func parse_def(data: Dictionary, where: String) -> Dictionary:
	var out := {"def": {}, "errors": PackedStringArray()}
	var errors: PackedStringArray = out["errors"]
	for key in data:
		if not key in ["schema", "id", "pool", "look"]:
			errors.append("%s: unknown key \"%s\"" % [where, key])
	if String(data.get("schema", "")) != SCHEMA:
		errors.append("%s: schema must be %s" % [where, SCHEMA])
	var id := String(data.get("id", ""))
	if id.is_empty():
		errors.append("%s: no id" % where)
	var pool = data.get("pool")
	if not pool is Dictionary or (pool as Dictionary).is_empty():
		errors.append("%s: pool must be a non-empty object of style: weight" % where)
		return out
	var clean := {}
	for style in pool:
		if not STYLES.has(style):
			errors.append("%s: unknown grab style \"%s\"" % [where, style])
			continue
		var weight = pool[style]
		if not (typeof(weight) in [TYPE_INT, TYPE_FLOAT]) or float(weight) <= 0.0:
			errors.append("%s: weight of %s must be a positive number" % [where, style])
			continue
		clean[String(style)] = float(weight)
	var look := {}
	var raw = data.get("look", {})
	if not raw is Dictionary:
		errors.append("%s: look must be an object" % where)
	else:
		for key in raw:
			if key in ["yaw", "up", "down", "chest", "delay"]:
				if not (typeof(raw[key]) in [TYPE_INT, TYPE_FLOAT]):
					errors.append("%s: look.%s must be a number" % [where, key])
				else:
					look[key] = deg_to_rad(float(raw[key])) if key in ["yaw", "up", "down"] else float(raw[key])
			elif key == "forward":
				var axis = raw[key]
				if not axis is Array or (axis as Array).size() != 3:
					errors.append("%s: look.forward must be [x, y, z]" % where)
				else:
					look["forward"] = Vector3(float(axis[0]), float(axis[1]), float(axis[2])).normalized()
			else:
				errors.append("%s: unknown look key \"%s\"" % [where, key])
	if errors.is_empty():
		out["def"] = {"id": id, "pool": clean, "look": look}
	return out


## A content pack's grab definitions replace the built-in ones for the ids it names (the pack loader checks overrides).
static func apply_defs(defs: Array) -> void:
	ensure_loaded()
	for def in defs:
		_pools[String(def["id"])] = (def["pool"] as Dictionary).duplicate()
		_looks[String(def["id"])] = (def.get("look", {}) as Dictionary).duplicate()


## How a hunter's head follows the runner during a grab (radians, chest share 0..1, Aki's look-away seconds): the data's
## "look" over these defaults.
const LOOK_DEFAULTS := {"yaw": 2.0, "up": 1.05, "down": 1.4, "chest": 0.0, "delay": 0.0}


static func look_for(hunter_id: String) -> Dictionary:
	ensure_loaded()
	var out := LOOK_DEFAULTS.duplicate()
	out.merge(_looks.get(hunter_id, {}), true)
	return out


static func pool_for(hunter_id: String) -> Dictionary:
	ensure_loaded()
	return _pools.get(hunter_id, {FALLBACK: 1.0})


static func main_style(hunter_id: String) -> String:
	var pool := pool_for(hunter_id)
	var best := ""
	for style in pool:
		if best.is_empty() or float(pool[style]) > float(pool[best]):
			best = style
	return best


static func is_creature(hunter_id: String) -> bool:
	return SecretCreatures.uses_creature_rig(hunter_id)


## The host's roll for a catch: the same on every peer for the same seed, runner and catch number.
static func roll_for(seed_text: String, peer_id: int, catch_index: int) -> float:
	return SeededRandom.new("%s:GRAB:%d:%d" % [seed_text, peer_id, catch_index]).next_float()


## Can `style` play out in a spot with this much room? `room`: {"ceiling", "back", "hunter_back"} in metres (missing = open).
static func fits(style: String, room: Dictionary) -> bool:
	var needs: Dictionary = STYLES.get(style, {})
	if needs.has("ceiling") and float(room.get("ceiling", 99.0)) < float(needs["ceiling"]):
		return false
	if needs.has("back") and float(room.get("back", 99.0)) < float(needs["back"]):
		return false
	if needs.has("hunter_back") and float(room.get("hunter_back", 99.0)) < float(needs["hunter_back"]):
		return false
	if needs.has("side") and float(room.get("side", 99.0)) < float(needs["side"]):
		return false
	if needs.has("wall"):
		var back := float(room.get("back", 99.0))
		if back > float(needs["wall"]) or back < .25:
			return false
	return true


## The style this catch plays: a weighted pick, with `roll` in [0, 1), over the pool styles that fit the room.
static func pick(hunter_id: String, roll: float, room: Dictionary) -> String:
	var pool := pool_for(hunter_id)
	var styles := pool.keys()
	styles.sort()   # dictionary order must not decide the pick on different peers
	var fitting := []
	var total := 0.0
	for style in styles:
		if fits(String(style), room):
			fitting.append(style)
			total += float(pool[style])
	if fitting.is_empty():
		return CREATURE_FALLBACK if is_creature(hunter_id) else FALLBACK
	var at := clampf(roll, 0.0, .999999) * total
	for style in fitting:
		at -= float(pool[style])
		if at < 0.0:
			return String(style)
	return String(fitting[-1])


## 1 while a shy hunter is still looking away from the runner, easing to 0 for the final beat of the hold.
static func look_away(hunter_id: String, t: float) -> float:
	var delay := float(look_for(hunter_id)["delay"])
	if delay <= 0.0:
		return 0.0
	return 1.0 - smooth((t - delay) / .4)


static func smooth(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## The whole grab at `t` seconds, in the hunter's frame: `along` is the floor direction from the hunter to the runner, `side`
## to its right. `ctx`: {"eye", "shoulder_side", "shoulder_fwd", "shoulder_y", "arm", "back"} from the real hunter and spot.
## Returns {
##   "at": Vector3(side, lift, along)  the runner's feet (lift = feet off the floor),
##   "face": 1 facing the hunter / -1 facing away,  "tilt": body lean, positive = head moves away from the hunter,
##   "view_pitch", "view_roll": first-person camera on top of the body's own lean,  "hands": first-person hand pose, "k": its amount,
##   "arms": [[hunter arm "R"/"L", BODY_POINTS key, amount]],  "hunter": [forward, drop, lean] for the hunter's own body,
##   "clip": what other players' copy of the runner plays, and optionally "wide" (elbows out, for arms that go round the runner),
##   "runner_arms" (the runner's own arm reaching the named point), "flip" (the upside-down turn, 0..1), "fold" (the carried
##   runner's hips bent, 0..1), "walk" (she walks: her walk clip), "look_down_back", "look" (0..1, how far the
##   first-person view has turned to her face; 1 when absent) }
static func pose(style: String, t: float, ctx: Dictionary) -> Dictionary:
	var r := smooth(t / REACH_SECONDS)
	var a := smooth((t - REACH_SECONDS) / ACT_SECONDS)
	var hold := maxf(t - REACH_SECONDS - ACT_SECONDS, 0.0)
	var shake := sin(t * 9.0) * a * .6
	var sway := sin(t * 7.0) * a
	var eye := float(ctx.get("eye", BODY_EYE))
	var shoulder_side := float(ctx.get("shoulder_side", -.45))
	var shoulder_fwd := float(ctx.get("shoulder_fwd", 0.0))
	var shoulder_y := float(ctx.get("shoulder_y", 1.8))
	var arm := float(ctx.get("arm", .66))
	var back := float(ctx.get("back", 3.0))
	var out := {"at": Vector3(0.0, 0.0, .75), "face": 1.0, "tilt": 0.0, "view_pitch": 0.0, "view_roll": 0.0,
		"hands": "push", "k": r, "arms": [], "hunter": [0.0, 0.0, 0.0], "clip": "idle"}
	match style:
		NECK_LIFT:
			# one hand nearly straight out at shoulder height; the runner's neck rises to it
			var grip_y := shoulder_y - arm * .1
			var lift := clampf(grip_y - BODY_POINTS["neck"].y * eye / BODY_EYE, .3, 1.2)
			out["at"] = Vector3(shoulder_side, lift * a, shoulder_fwd + arm * .95 + .22)
			out["view_pitch"] = .25 * a
			out["view_roll"] = .07 * a + sway * .03
			out["hands"] = "grip_arm"
			out["arms"] = [["R", "neck", r]]
			out["clip"] = "fall"
		SHOULDER_GRAB:
			out["at"] = Vector3(shake * .015, .08 * a, 1.25)   # held off at arm's length (she steps in only as far as her arms need)
			out["tilt"] = shake * .06
			out["view_roll"] = shake * .03
			out["arms"] = [["R", "l_shoulder", r], ["L", "r_shoulder", r]]
		TACKLE:
			var flat := smooth((t - REACH_SECONDS) / (ACT_SECONDS + .35))   # knocked flat, not snapped flat
			out["at"] = Vector3(0.0, 0.0, lerpf(.75, 1.25, flat))
			out["tilt"] = lerpf(0.0, PI * .5 - .1, flat)
			out["view_pitch"] = .25 * flat
			out["hands"] = "push_up"
			out["arms"] = [["R", "l_shoulder", r], ["L", "r_shoulder", r]]
			var down := smooth((t - REACH_SECONDS - ACT_SECONDS * .4) / (ACT_SECONDS * .6 + HOLD_SECONDS * .4))
			out["hunter"] = [.3 * down, .3 * down, .3 * down]   # she follows the runner down once they have hit the floor, kneeling over them
			out["clip"] = "fall"
		WRIST_YANK:
			# her hand closes on the runner's outstretched wrist and she hauls them in, leaning back into the pull
			var yank := smooth((t - REACH_SECONDS) / (ACT_SECONDS * .45))
			out["at"] = Vector3(0.0, 0.0, lerpf(1.05, .88, yank))
			out["tilt"] = -.06 * yank
			out["view_pitch"] = -.08 * yank
			out["view_roll"] = -.08 * yank
			out["hands"] = "held"
			out["k"] = r
			out["arms"] = [["R", "l_wrist", r]]   # her right hand on the runner's left wrist, the one in front of it
			out["runner_arms"] = [["L", "l_wrist"]]
			out["hunter"] = [0.0, 0.0, -.18 * yank]
		WRAP:
			out["at"] = Vector3(0.0, .1 * a, 1.3)   # her long arms round the runner from a step away: her face stays in front of theirs
			out["view_roll"] = sway * .04
			out["hands"] = "pinned"
			out["arms"] = [["R", "back_l", r], ["L", "back_r", r]]
			out["wide"] = true   # elbows out wide, so the arms come round the runner instead of through them
		SHOULDER_CARRY:
			# hoisted over her right shoulder, torso hanging down her back, legs down her front locked by her arm; then she
			# carries the runner off a few steps (CARRY_METRES) before the end
			var hoist := smooth((t - REACH_SECONDS) / .9)
			var walk := smooth((t - REACH_SECONDS - 1.0) / 1.5)
			var tilt := -(PI - .35) * hoist
			var pelvis := Vector3(shoulder_side, shoulder_y + .05, shoulder_fwd + walk * CARRY_METRES)
			var carried := pelvis - Vector3(0.0, .6 * cos(tilt), .6 * sin(tilt))
			# out to her side first, then up and over, so the body never swings through hers
			var out_side := smooth((t - REACH_SECONDS * .5) / .35)   # stepped out to her shoulder side before going up
			# swung a little wider on the way up (the runner's head passes her side close to her body), in again at the top
			var wide := 1.0 + .3 * sin(PI * clampf(hoist, 0.0, 1.0))
			out["at"] = Vector3(carried.x * out_side * wide, carried.y * hoist, lerpf(.75, carried.z, hoist))
			out["tilt"] = tilt
			out["fold"] = hoist
			out["view_pitch"] = 0.0
			out["look_down_back"] = hoist   # looking down her back at the floor going away
			out["hands"] = "dangle"
			out["k"] = hoist
			out["arms"] = [["R", "knees", r]]
			out["hunter"] = [walk * CARRY_METRES, 0.0, 0.0]
			out["walk"] = walk > .001 and walk < .999
			out["walk_t"] = maxf(t - REACH_SECONDS - 1.0, 0.0)   # her steps from the clip's start, not from mid-stride
			out["her_look_ahead"] = true   # she looks where she is carrying them, not round at the runner over her shoulder
			out["clip"] = "idle"
		LEG_GRAB:
			# grabbed low from behind: the runner falls forward on their face and is dragged back to the hunter
			var fall := smooth((t - REACH_SECONDS) / (ACT_SECONDS + .25))
			var drag := smooth((t - REACH_SECONDS - ACT_SECONDS * .35) / (ACT_SECONDS * .65 + HOLD_SECONDS * .6))
			out["face"] = -1.0
			out["at"] = Vector3(0.0, 0.0, lerpf(1.25, .75, drag))
			out["tilt"] = lerpf(.25 * r, PI * .5 - .06, fall)
			out["view_pitch"] = -.2 * fall
			out["hands"] = "claw"
			out["k"] = fall
			# she bends for the ankle a beat after the runner pitches forward, so she never stoops through their head
			var stoop := smooth((t - REACH_SECONDS - .2) / (ACT_SECONDS * .55))
			out["arms"] = [["R", "r_ankle", maxf(stoop, r * .3)]]
			out["hunter"] = [0.0, .7 * stoop, .45 * stoop]
			out["clip"] = "fall"
		UPSIDE_DOWN:
			# a leg in one hand, hoisted to shoulder height: the runner hangs head down; the view turns over slowly (eased, about
			# 1.5 s), then only sways a little
			var hoist := smooth((t - REACH_SECONDS) / (ACT_SECONDS + .65))
			var flip := smooth((t - REACH_SECONDS) / 1.5)
			# held out in front of her by the ankle at arm's length, the runner's back to her: hanging there you look up at her
			out["at"] = Vector3(shoulder_side, lerpf(0.0, shoulder_y - .15, hoist), lerpf(.85, shoulder_fwd + arm * .95, hoist))
			out["tilt"] = PI * hoist   # the head swings down as the feet go up, evenly (no fast swing through)
			out["flip"] = flip
			out["view_roll"] = PI * flip + sway * .05
			out["hands"] = "dangle"
			out["k"] = hoist
			out["arms"] = [["R", "r_ankle", r]]
			out["clip"] = "fall"
		COLLAR_DRAG:
			# the hunter takes the runner by the collar, pulls them face down towards the floor and backs off, dragging them
			var pull := smooth((t - REACH_SECONDS - ACT_SECONDS * .5) / (ACT_SECONDS * .5 + HOLD_SECONDS * .7))
			out["at"] = Vector3(shoulder_side * r, 0.0, lerpf(.9, .6, pull))
			out["tilt"] = -.9 * a
			out["view_pitch"] = .55 * a
			out["hands"] = "claw"
			out["k"] = a
			out["arms"] = [["R", "neck", r]]
			# backed off as far again as the runner is tall: dragged face down, their face stays where she can look at it
			out["hunter"] = [(lerpf(0.0, -.9, a) - .4 * pull) * PlayerModels.SCALE / .9, .3 * a, .35 * a]
			out["clip"] = "fall"
		WALL_PIN:
			# shoved back against the wall behind the runner and held there by the throat at arm's length, feet off the floor
			var to_wall := clampf(back - .2, 0.0, 1.1)
			var shove := smooth((t - REACH_SECONDS) / (ACT_SECONDS * .5))
			out["at"] = Vector3(shoulder_side, .3 * shove, .75 + to_wall * shove)
			out["view_pitch"] = .1 * shove
			out["view_roll"] = sin(maxf(t - REACH_SECONDS - ACT_SECONDS * .5, 0.0) * 12.0) * .04 * exp(-hold * 4.0) * shove
			out["hands"] = "grip_arm"
			out["arms"] = [["R", "neck", r]]
			out["hunter"] = [0.0, 0.0, 0.0]   # she steps in only as far as her arm needs
		POUNCE_PIN:
			var down := smooth((t - REACH_SECONDS) / (ACT_SECONDS + .4))   # knocked flat, not snapped flat
			out["at"] = Vector3(0.0, 0.0, lerpf(.9, 1.2, down))
			out["tilt"] = lerpf(0.0, PI * .5 - .1, down)
			out["view_pitch"] = .25 * a
			out["hands"] = "push_up"
			out["hunter"] = [lerpf(0.0, .3, a), 0.0, .15 * a]
			out["clip"] = "fall"
	return out


## The runner body's basis for a pose: turned to face (or face away from) the hunter, then leaned by tilt about its own X.
static func body_basis(along: Vector3, face: float, tilt: float) -> Basis:
	return Basis.from_euler(Vector3(tilt * face, body_yaw(along, face), 0.0))


## The body's yaw: its front (-Z) at the hunter when face = 1, away from it when -1.
static func body_yaw(along: Vector3, face: float) -> float:
	var forward := -along * face
	return atan2(-forward.x, -forward.z)
