class_name XivvyFlight
extends RefCounted

## Presentation of Xivvy's flying chase: altitude, bank, pitch and wing cadence. Derived entirely from replicated data (the
## gimmick's `flying` flag, the travel speed, the body's turn rate and the distance to the runner), so a guest sees exactly
## the lift, bank and swoop the host does with no extra network traffic. The simulation stays on the 2D nav plane; this
## only moves the model.
##
## Altitude is the height of her FEET above the floor. She hovers HOVER_HEIGHT up, a readable low float in open ground and in
## tall halls alike, and only comes down where a ceiling would reach her head: the view measures the headroom with a ray and
## she stays BODY_HEIGHT + CEILING_GAP under it. Close to the runner she dips ("swoops") to a grab just above the floor. A
## small float (a bob and a sway, presentation only) rides on top of the altitude.

enum Phase { GROUND, TAKEOFF, CRUISE, SWOOP, LANDING }

## Her drawn height: the model's 1.78 m rig at the roster scale (HunterRoster.MODEL_SCALE, 1.5x like every humanoid), so 2.67 m.
const BODY_HEIGHT := 1.78 * HunterRoster.MODEL_SCALE
const CEILING_GAP := .14
## Her hover: feet this high above the floor wherever the ceiling allows it (open ground, 4 m halls, 9 m atriums).
const HOVER_HEIGHT := 1.2
## The float (view only; the simulation never reads it): a bob up and down and a sway side to side, both at FLOAT_HZ.
const FLOAT_AMPLITUDE := .05
const FLOAT_HZ := .7
## Headroom (floor to ceiling, metres) she needs to take off / must have to stay up. Route halls are 3 m (non-streamed) or 4 m
## (streamed), City ceilings 4 m with 3 m doors, rims 11 m, gates 7 m: so she flies in 4 m halls and open ground and walks 3 m rooms and doors.
const FLY_ENTER_HEADROOM := 3.6
const FLY_EXIT_HEADROOM := 3.2
const ENTER_DWELL := .45
## A gap this narrow on both sides (metres to the wall left and right) is a doorway: she walks.
const GAP_HALF_WIDTH := 1.0
const SWOOP_RANGE := 6.0
const GRAB_RANGE := 1.4
const SWOOP_ALTITUDE := .30
const BANK_LIMIT := deg_to_rad(38.0)
const PITCH_LIMIT := deg_to_rad(26.0)
const RISE_RATE := 3.4       # m/s ceiling on how fast she climbs or settles
const FLAP_BASE := 2.0       # Hz at a standstill
const FLAP_PER_SPEED := .38

var altitude := 0.0
var phase := Phase.GROUND
var bank := 0.0
var pitch := 0.0
var flap_phase := 0.0
## Set for the frame in which the downstroke wraps (the view plays the wing cue on it).
var flapped := false
var _altitude_rate := 0.0
## Clearance mode: false = walk (doors, low or cramped spaces), true = fly. Hysteresis + a dwell before lifting off.
var fly_ok := true
## A guest follows the host's cruise altitude instead of measuring headroom (<0 = measure).
var override_cruise := -1.0
## ("Xivvy flies into the next level, like she noclips"): the height of her storey, floor to ceiling slab. In the
## streamed facility every storey is LEVEL_HEIGHT and the next one's floor sits right above, but the headroom ray often sees
## no ceiling at all (open wells and decks, catwalk air, a storey above not streamed in yet), read INF, and her body rose
## through the slab into the storey above. Whatever the ray says, she never flies higher than this (INF = a single-storey
## map, where the measured headroom alone decides).
var storey_headroom := INF
## Presentation float on top of `altitude` (metres), set by update(): a vertical bob and a sideways sway, from `float_time`
## (no RNG). Zero on the ground. The bob is clamped so her head never rises into the ceiling it was measured under.
var float_time := 0.0
var float_bob := 0.0
var float_sway := 0.0
var wing_fold := 0.0
var mode_switches := 0
var _enter_timer := 0.0


## Decide walk vs fly from the route survey: `headroom` = lowest ceiling over the stretch ahead, `gap_ahead` = a doorway-sized
## gap on the way. Landing is immediate (she must be down before the door), taking off needs the way clear for ENTER_DWELL.
func update_mode(delta: float, headroom: float, gap_ahead: bool) -> bool:
	var before := fly_ok
	if gap_ahead or headroom < FLY_EXIT_HEADROOM:
		fly_ok = false
		_enter_timer = 0.0
	elif not fly_ok and headroom >= FLY_ENTER_HEADROOM:
		_enter_timer += delta
		if _enter_timer >= ENTER_DWELL:
			fly_ok = true
	else:
		_enter_timer = 0.0
	if fly_ok != before:
		mode_switches += 1
	return fly_ok


## `headroom`: free height above the floor in metres (INF in the open). Her hover, lowered only when the ceiling (or the storey
## slab) would otherwise reach her head: never above HOVER_HEIGHT, never up into a ceiling.
func cruise_altitude(headroom: float) -> float:
	return clampf(minf(headroom, storey_headroom) - BODY_HEIGHT - CEILING_GAP, 0.0, HOVER_HEIGHT)


## The highest her feet may be on this storey: head CEILING_GAP under the storey's ceiling slab.
func storey_ceiling_altitude() -> float:
	return maxf(0.0, storey_headroom - BODY_HEIGHT - CEILING_GAP)


func _cruise(headroom: float) -> float:
	# a guest's replicated hint is capped too: an older host (or one on a map without the cap) must not lift her out of the storey
	return minf(override_cruise, storey_ceiling_altitude()) if override_cruise >= 0.0 else cruise_altitude(headroom)


func target_altitude(flying: bool, headroom: float, runner_distance: float) -> float:
	if not flying:
		return 0.0
	var cruise := _cruise(headroom)
	if runner_distance >= SWOOP_RANGE:
		return cruise
	var closeness := clampf((SWOOP_RANGE - runner_distance) / (SWOOP_RANGE - GRAB_RANGE), 0.0, 1.0)
	return lerpf(cruise, minf(SWOOP_ALTITUDE, cruise), closeness * closeness)


func update(delta: float, flying: bool, speed: float, yaw_rate: float, runner_distance: float, headroom: float) -> void:
	var frame := clampf(delta, 1.0 / 240.0, .1)
	var wanted := target_altitude(flying, headroom, runner_distance)
	var before := altitude
	var eased := lerpf(altitude, wanted, 1.0 - exp(-(4.2 if wanted > altitude else 5.0) * frame))
	altitude = move_toward(altitude, eased, RISE_RATE * frame)
	altitude = move_toward(altitude, wanted, .5 * frame)   # the exponential tail never lingers
	_altitude_rate = (altitude - before) / frame
	if altitude < .004 and wanted == 0.0:
		altitude = 0.0
	# hard storey clamp: even mid-ease (a cap arriving late, a guest's stale hint) she never rises through the slab
	altitude = minf(altitude, storey_ceiling_altitude())
	# presentation float (view only): a bob and a sway that fade in with the lift. The bob is clamped to the clearance above her
	# feet (never her head into the ceiling) and never takes her below the floor. fposmod keeps float_time small (a period wrap).
	float_time = fposmod(float_time + frame, 1.0 / FLOAT_HZ)
	var lift := clampf(altitude / .25, 0.0, 1.0)
	var clearance := minf(headroom, storey_headroom) - BODY_HEIGHT - CEILING_GAP
	float_bob = clampf(sin(TAU * FLOAT_HZ * float_time) * FLOAT_AMPLITUDE * lift, -altitude, maxf(0.0, clearance - altitude))
	float_sway = cos(TAU * FLOAT_HZ * float_time) * FLOAT_AMPLITUDE * lift
	# phase
	var cruise := _cruise(headroom)
	if altitude <= 0.0 and not flying:
		phase = Phase.GROUND
	elif not flying:
		phase = Phase.LANDING
	elif altitude < cruise * .85 and _altitude_rate > .05:
		phase = Phase.TAKEOFF
	elif wanted < cruise - .1:
		phase = Phase.SWOOP
	else:
		phase = Phase.CRUISE
	# wings fold while she comes down and open again once she is on her feet
	var fold_target := 1.0 if (phase == Phase.LANDING and altitude < 1.4) else 0.0
	wing_fold = lerpf(wing_fold, fold_target, 1.0 - exp(-6.0 * frame))
	# bank into the turn (yaw rate is positive turning left, and +z roll tips the head to the left), nose down when diving
	var airborne := clampf(altitude / .25, 0.0, 1.0)
	var bank_target := clampf(yaw_rate * .16, -BANK_LIMIT, BANK_LIMIT) * airborne
	var settle := 16.0 if altitude <= 0.0 else 7.0
	bank = lerpf(bank, bank_target, 1.0 - exp(-settle * frame))
	var dive := maxf(0.0, -_altitude_rate) * .09 + clampf(speed * .02, 0.0, .18)
	var pitch_target := -clampf(dive, 0.0, PITCH_LIMIT) * airborne
	pitch = lerpf(pitch, pitch_target, 1.0 - exp(-(settle if altitude <= 0.0 else 6.0) * frame))
	if altitude <= 0.0 and absf(pitch) < .004 and absf(bank) < .004:
		pitch = 0.0
		bank = 0.0
	# wings: cadence follows speed, slower on the glide, quick on the climb
	flapped = false
	if altitude > .05:
		var rate := FLAP_BASE + speed * FLAP_PER_SPEED + maxf(0.0, _altitude_rate) * .5
		var previous := flap_phase
		flap_phase = fposmod(flap_phase + rate * frame, 1.0)
		flapped = flap_phase < previous
	else:
		flap_phase = 0.0


func flight_clip_speed(speed: float) -> float:
	return clampf(.85 + speed * .22, .85, 2.3)
