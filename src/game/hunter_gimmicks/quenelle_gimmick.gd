class_name QuenelleGimmick
extends HunterGimmick

## Quenelle's flashlight tracker (hunterAbilities.quenelle.flashlightTracker in
## the original). Mirrors quenelle.js's updateFlashlightTracker(): sustained
## flashlight-on time earns a permanent lock (never un-sets once true); once
## locked, every frame she re-affirms chase + last_known + a zeroed
## lost_sight_timer, so HunterBrain's own perception grace-timer decay never
## actually accumulates past a single frame — functionally perfect tracking,
## matching the original's every-frame reassignment. Off-to-on flashlight
## flicks (tracked regardless of lock state) ramp her chase speed, applied
## via speed_scale(), capped after QUENELLE_SPEED_RAMP_ACTIVATIONS. "not
## hidden" isn't checked here (unlike the original's flashlightOn) since
## hiding spots don't exist in this port yet — target_hidden is always false.

var _tracking := false
var _track_elapsed := 0.0
var _activations := 0
var _was_on := false
var _speed_scale := 1.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	var target_position: Vector2 = target["position"]
	var target_in_safe_zone: bool = target.get("in_safe_zone", false)
	# 2D: counts only while the torch is on AND charged AND the runner is not hidden.
	var target_flashlight_on: bool = bool(target.get("flashlight_on", true)) \
		and float(target.get("lamp_charge", 1.0)) > 0.0 and not bool(target.get("hidden", false))

	if target_flashlight_on and not _was_on:
		_activations += 1
	_was_on = target_flashlight_on

	if not _tracking:
		_track_elapsed = _track_elapsed + delta if target_flashlight_on else 0.0
		if _track_elapsed >= lock_seconds(brain.difficulty_id):
			_tracking = true
			brain.world_events.append({"what": "message", "sound": "alert", "message": "QUENELLE LOCKED ON"})

	var activation_progress := minf(1.0, float(_activations) / GameConfig.QUENELLE_SPEED_RAMP_ACTIVATIONS)
	_speed_scale = 1.0 + activation_progress * (GameConfig.QUENELLE_MAX_SPEED_SCALE - 1.0) \
		if _tracking and target_flashlight_on else 1.0

	if _tracking and not target_in_safe_zone:
		brain.state = HunterBrain.State.CHASE
		brain.has_last_known = true
		brain.last_known = target_position
		brain.lost_sight_timer = 0.0


func speed_scale(_brain: HunterBrain) -> float:
	return _speed_scale


static func lock_seconds(difficulty_id: String) -> float:
	return GameConfig.QUENELLE_NIGHTMARE_LOCK_SECONDS if difficulty_id == "nightmare" else GameConfig.QUENELLE_FLASHLIGHT_LOCK_SECONDS
