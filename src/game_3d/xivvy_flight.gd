class_name XivvyFlight
extends RefCounted

## Presentation of Xivvy's flying chase: altitude, bank, pitch and wing cadence. Derived entirely from replicated data (the
## gimmick's `flying` flag, the travel speed, the body's turn rate and the distance to the runner), so a guest sees exactly
## the lift, bank and swoop the host does with no extra network traffic. The simulation stays on the 2D nav plane; this
## only moves the model.
##
## Altitude is the height of her FEET above the floor. Indoors the ceiling decides how high she may go: the view measures the
## headroom with a ray and she cruises BODY_HEIGHT + CEILING_GAP under it; in the open she cruises at CRUISE_OPEN and dips low
## ("swoops") as she closes on the runner, ending in a grab just above the floor.

enum Phase { GROUND, TAKEOFF, CRUISE, SWOOP, LANDING }

const BODY_HEIGHT := 1.78
const CEILING_GAP := .14
const CRUISE_OPEN := 5.5
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


## `headroom`: free height above the floor in metres (INF in the open). `runner_distance`: INF when she has no target.
func cruise_altitude(headroom: float) -> float:
	return clampf(minf(CRUISE_OPEN, headroom - BODY_HEIGHT - CEILING_GAP), 0.0, CRUISE_OPEN)


func target_altitude(flying: bool, headroom: float, runner_distance: float) -> float:
	if not flying:
		return 0.0
	var cruise := override_cruise if override_cruise >= 0.0 else cruise_altitude(headroom)
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
	# phase
	var cruise := override_cruise if override_cruise >= 0.0 else cruise_altitude(headroom)
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
