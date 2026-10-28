class_name QualityGovernor
extends Node

## Live quality adaptation inside the detected (or chosen) tier. Watches a rolling frame time against the device's
## frame target (QualityTier.frame_target); when the target is missed for MISS_SECONDS it gives up one "notch", in
## this order: draw distance, shadows, prop density, lamps, streaming slice, render scale, and last a 30 fps cap (steady
## pacing on hardware that cannot hold 60 even fully stepped down, instead of swinging between 30 and 50). After a sustained margin it takes one
## back. Separate thresholds, cooldowns and a hold after every step-down keep it from flickering. Only in GRAPHICS AUTO.
##
## The decision core (feed) is pure so scripts/validate_quality_tiers.gd can run it on synthetic frame times.

signal notch_changed(notch: int)

const MAX_NOTCH := 7
const WINDOW_SECONDS := 2.0
const MISS_SECONDS := 3.0          # target missed this long -> one notch down
const MARGIN_SECONDS := 12.0       # comfortably under budget this long -> one notch up
const MISS_FACTOR := 1.12          # rolling frame time over target x this = missing
const MARGIN_FACTOR := .7          # under target x this = margin
const DOWN_COOLDOWN := 4.0
const HOLD_AFTER_DOWN := 25.0      # no step up this soon after a step down

var notch := 0
var target_ms := 1000.0 / 60.0
var _window: Array[float] = []
var _window_ms := 0.0
var _miss_time := 0.0
var _margin_time := 0.0
var _since_down := 1e9
var _since_change := 1e9
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


## One frame of `ms`; returns -1/+1 when the notch moved down/up a step (notch grows as quality drops: +1 = down).
func feed(ms: float) -> int:
	_window.append(ms)
	_window_ms += ms
	while _window_ms - _window[0] > WINDOW_SECONDS * 1000.0 and _window.size() > 1:
		_window_ms -= _window.pop_front()
	var seconds := ms / 1000.0
	_since_down += seconds
	_since_change += seconds
	if _window_ms < WINDOW_SECONDS * 500.0:
		return 0   # not a full window yet
	var avg := _window_ms / _window.size()
	if avg > target_ms * MISS_FACTOR:
		_miss_time += seconds
		_margin_time = 0.0
	elif avg < target_ms * MARGIN_FACTOR:
		_margin_time += seconds
		_miss_time = 0.0
	else:
		_miss_time = maxf(0.0, _miss_time - seconds)
		_margin_time = maxf(0.0, _margin_time - seconds)
	if _miss_time >= MISS_SECONDS and notch < MAX_NOTCH and _since_change >= DOWN_COOLDOWN:
		notch += 1
		_after_step(true)
		return 1
	if _margin_time >= MARGIN_SECONDS and notch > 0 and _since_down >= HOLD_AFTER_DOWN:
		notch -= 1
		_after_step(false)
		return -1
	return 0


func _after_step(down: bool) -> void:
	_miss_time = 0.0
	_margin_time = 0.0
	_since_change = 0.0
	if down:
		_since_down = 0.0
	# the new settings need a fresh window before they are judged
	_window.clear()
	_window_ms = 0.0


## A tier's budgets with `n` notches given up (QualityTier.budgets is notch 0).
static func degrade(budgets: Dictionary, n: int) -> Dictionary:
	var out := budgets.duplicate()
	if n >= 1:
		var far := float(out.get("camera_far", 0.0))
		out["camera_far"] = (far if far > 0.0 else 200.0) * .7
	if n >= 2 and not bool(out.get("keep_shadows", false)):
		out["shadows"] = false   # desktop MEDIUM+ keeps the flashlight's shadows through every step (core to the horror)
	if n >= 3:
		out["prop_range_scale"] = float(out.get("prop_range_scale", 1.0)) * .75
	if n >= 4:
		out["lamp_pool"] = maxi(2, int(out.get("lamp_pool", 8)) - 2)
	if n >= 5:
		out["stream_budget_ms"] = maxf(1.5, float(out.get("stream_budget_ms", 4.0)) - 1.0)
		out["stream_budget_max_ms"] = maxf(3.0, float(out.get("stream_budget_max_ms", 9.0)) - 2.0)
	if n >= 6:
		out["render_scale"] = maxf(.6, float(out.get("render_scale", 1.0)) * .8)
	if n >= 7:
		out["fps_cap"] = 30
	return out
