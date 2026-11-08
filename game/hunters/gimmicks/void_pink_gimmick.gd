class_name VoidPinkGimmick
extends VoidGimmick

## Pink Void, falseSignal: she never attacks. Every 11 s she has a 60 % chance to make the runner hear false footsteps somewhere
## close: a short run of quiet footfalls, no text, no HUD, no alert stinger. (The two fake radar contacts for 6 s need the radar
## to accept ghost marks and are still to do, see docs/HUNTER_PARITY.md.)
##
## The host decides everything from the brain's deterministic RNG and queues one mechanic event, `fake_footsteps`:
##   {"what": "fake_footsteps", "peer_id": int (target, when known), "target_depth": int (target's level, when known),
##    "steps": 4..7, "pan": -0.8..0.8, "gap": ~0.42 s between steps, "distance": 4..9 m, "approach": bool}
## It travels the same host -> targeted-player path as the other Void player events (signal_route, system_outage, radar_corrupt) and
## VoidPlayerEffects plays it on that player's machine only. An old client ignores the unknown `what`.

const INTERVAL := 11.0
const CHANCE := 0.6
const STEPS_MIN := 4
const STEPS_SPAN := 4          # steps = 4..7
const PAN_MAX := 0.8
const GAP := 0.42
const GAP_JITTER := 0.08       # gap = 0.38..0.46 s
const DISTANCE_MIN := 4.0
const DISTANCE_SPAN := 5.0     # distance = 4..9 m

var _cooldown := INTERVAL


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	_cooldown -= delta
	if _cooldown > 0.0:
		return
	_cooldown = INTERVAL
	if target.is_empty() or brain.next_random_float() >= CHANCE:
		return
	# Every draw below comes from the brain's own stream, so the same seed gives every peer the same event.
	var steps := clampi(STEPS_MIN + int(brain.next_random_float() * STEPS_SPAN), STEPS_MIN, STEPS_MIN + STEPS_SPAN - 1)
	var event := {
		"what": "fake_footsteps",
		"steps": steps,
		"pan": (brain.next_random_float() * 2.0 - 1.0) * PAN_MAX,
		"distance": DISTANCE_MIN + brain.next_random_float() * DISTANCE_SPAN,
		"approach": brain.next_random_float() < 0.5,
		"gap": GAP - GAP_JITTER * .5 + brain.next_random_float() * GAP_JITTER,
	}
	if target.has("peer_id"):
		event["peer_id"] = int(target["peer_id"])
	if target.has("depth"):
		event["target_depth"] = int(target["depth"])
	brain.emit_world_event(event)


func immune_to_capture() -> bool:
	return true
