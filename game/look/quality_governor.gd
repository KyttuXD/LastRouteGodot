class_name QualityGovernor
extends Node

## Live quality adaptation inside the detected (or chosen) tier. Watches a rolling frame time against the tier's frame
## target (QualityTier.frame_target: desktop LOW 40, MEDIUM 50, HIGH 60, phones 60 or 40 on LOW, the Quest 72, all
## capped by the display refresh and the player's FPS limit). When the target is missed (over MISS_FACTOR x target) for
## MISS_SECONDS it gives up one "notch", in this order: draw distance + minimap rate, streaming slice, prop range, and
## last ONE conditional notch (QualityTier.budgets "last_notch": a phone renders at 0.85 scale; a desktop that still
## has flashlight shadows turns them off; MEDIUM, LOW and the Quest have only the first three). There is no fps cap, no
## lamp-pool notch and no desktop render-scale notch: those cost more than they saved on the machines that reached them.
##
## Step-up has no model of what a notch saves. It takes one notch back when the rolling frame time has stayed at or under
## OK_FACTOR x target for UP_SECONDS, and a single global hold has expired. The hold starts after a "bounce" (a step-down
## within BOUNCE_WINDOW of a step-up) and doubles with each consecutive bounce (60/120/240/480 s). The escalation is
## forgotten once a step-up has survived STABLE_FORGET seconds without a step-down; a machine that merely sits held down
## keeps its escalation, so a borderline machine does not restart the 60 s cycle.
## Known dead band: after a step-down, a machine whose frame time settles between OK_FACTOR and MISS_FACTOR x target
## stays one notch down (it never misses, so it never steps down further, and it is never clean enough to step up).
##
## The decision core (feed) is pure so tests/validate_quality_tiers.gd can run it on synthetic frame times.

signal notch_changed(notch: int)

const MAX_NOTCH := 4               # ceiling; PlatformProfile sets max_notch per device with notches_for()
const WINDOW_SECONDS := 2.0
const MISS_SECONDS := 3.0          # target missed this long -> one notch down
const MISS_FACTOR := 1.12          # rolling frame time over target x this = missing
const OK_FACTOR := 1.05            # at or under target x this = clean enough to count toward a step up
const UP_SECONDS := 20.0           # clean this long (and no hold) -> one notch up
const DOWN_COOLDOWN := 4.0
const BOUNCE_WINDOW := 60.0        # a step-down this soon after a step-up is a bounce
const BOUNCE_HOLD := 60.0          # first hold after a bounce; doubles per consecutive bounce
const BOUNCE_MAX := 4              # 60 / 120 / 240 / 480 s
const STABLE_FORGET := 300.0       # a step-up that lasted this long clears the escalation

var notch := 0
var max_notch := MAX_NOTCH
var target_ms := 1000.0 / 60.0
var _window: Array[float] = []
var _window_ms := 0.0
var _miss_time := 0.0
var _ok_time := 0.0
var _hold_left := 0.0
var _bounces := 0
var _since_change := 1e9
var _since_up := 1e9
var _last_was_up := false
var _last_usec := 0
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1001


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec != 0 and enabled and not get_tree().paused:
		var ms := (now - _last_usec) / 1000.0
		# a frame this long is a load or a stall the stream layer owns, not a steady-state shortfall
		if ms < 250.0:
			var change := feed(ms)
			if change != 0:
				notch_changed.emit(notch)
	_last_usec = now


## Back to notch 0 with no history (a preset change: the old measurements describe different settings).
func reset() -> void:
	notch = 0
	_window.clear()
	_window_ms = 0.0
	_miss_time = 0.0
	_ok_time = 0.0
	_hold_left = 0.0
	_bounces = 0
	_last_was_up = false
	_since_change = 1e9
	_since_up = 1e9


## How many notches a tier's budgets offer (QualityTier.budgets, before any degrade): 3, plus the conditional last one.
static func notches_for(budgets: Dictionary) -> int:
	return 3 + (1 if String(budgets.get("last_notch", "")) != "" else 0)


## One frame of `ms`; returns +1/-1 when the notch moved down/up a step (notch grows as quality drops: +1 = down).
func feed(ms: float) -> int:
	_window.append(ms)
	_window_ms += ms
	while _window_ms - _window[0] > WINDOW_SECONDS * 1000.0 and _window.size() > 1:
		_window_ms -= _window.pop_front()
	var seconds := ms / 1000.0
	_since_change += seconds
	_since_up += seconds
	_hold_left = maxf(0.0, _hold_left - seconds)
	if _last_was_up and _since_up >= STABLE_FORGET:
		_bounces = 0   # the last step-up survived: forget the escalation
	if _window_ms < WINDOW_SECONDS * 500.0:
		return 0   # not a full window yet
	var avg := _window_ms / _window.size()
	if avg > target_ms * MISS_FACTOR:
		_miss_time += seconds
		_ok_time = 0.0
	else:
		_miss_time = maxf(0.0, _miss_time - seconds)
		if avg <= target_ms * OK_FACTOR:
			_ok_time += seconds
		else:
			_ok_time = 0.0
	if _miss_time >= MISS_SECONDS and notch < max_notch and _since_change >= DOWN_COOLDOWN:
		if _last_was_up and _since_up < BOUNCE_WINDOW:
			_bounces = mini(_bounces + 1, BOUNCE_MAX)
			_hold_left = BOUNCE_HOLD * pow(2.0, _bounces - 1)
		_last_was_up = false   # a cascaded step-down is not a bounce
		notch += 1
		_after_step()
		return 1
	if _ok_time >= UP_SECONDS and notch > 0 and _hold_left <= 0.0:
		_last_was_up = true
		_since_up = 0.0
		notch -= 1
		_after_step()
		return -1
	return 0


func _after_step() -> void:
	_miss_time = 0.0
	_ok_time = 0.0
	_since_change = 0.0
	# the new settings need a fresh window before they are judged
	_window.clear()
	_window_ms = 0.0


## A tier's budgets with `n` notches given up (QualityTier.budgets is notch 0).
static func degrade(budgets: Dictionary, n: int) -> Dictionary:
	var out := budgets.duplicate()
	if n >= 1:
		var far := float(out.get("camera_far", 0.0))
		out["camera_far"] = (far if far > 0.0 else 200.0) * .7
		var hz := float(out.get("map_update_hz", 0.0))
		out["map_update_hz"] = 30.0 if hz <= 0.0 else minf(hz, 30.0)
	if n >= 2:
		out["stream_budget_ms"] = maxf(1.5, float(out.get("stream_budget_ms", 4.0)) - 1.0)
		out["stream_budget_max_ms"] = maxf(3.0, float(out.get("stream_budget_max_ms", 9.0)) - 2.0)
		out["stream_budget_burst_ms"] = maxf(float(out["stream_budget_max_ms"]), float(out.get("stream_budget_burst_ms", 14.0)) - 3.0)
	if n >= 3:
		out["prop_range_scale"] = float(out.get("prop_range_scale", 1.0)) * .75
	if n >= 4:
		match String(out.get("last_notch", "")):
			"shadows":
				out["shadows"] = false
			"render_scale":
				out["render_scale"] = maxf(.6, float(out.get("render_scale", 1.0)) * .85)
	return out
