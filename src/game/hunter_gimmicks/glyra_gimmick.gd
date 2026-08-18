class_name GlyraGimmick
extends HunterGimmick

## Glyra's spawn-room music box (hunterAbilities.glyra.musicBoxThreat).
## Ported from glyra.js's updateMusicBoxThreat/windGlyraMusicBox.
##
## She never moves at all -- vx/vy pinned to zero every frame in the original,
## holds_position() here -- she is a timer wearing a hunter's slot, not a
## threat that comes looking for you. The music box she sits beside (placed
## in the spawn room, see FacilityView3D._spawn_interactables) stays wound for
## GLYRA_BAY_SECONDS after the last time someone worked it; while wound, she
## does nothing. Unwound, she raises the facility noise meter every frame at a
## real net rate -- the meter's own decay constantly eats into a raw
## noise-per-second contribution, so the rate here adds the decay back in,
## matching what the original does so the meter genuinely climbs by the
## configured amount instead of net-zero.
##
## Winding the box does not just stop the noise, it gives back exactly what
## she has added since the last wind (PlayerMeters.reclaim_noise) -- otherwise
## the meter would sit wherever it happened to be when you got there instead
## of resetting, and repeated visits would ratchet it up over a whole floor.

var _remaining := 0.0
var _warned := false
var _noise_gained := 0.0
var _started := false


func after_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	if not _started:
		_remaining = GameConfig.GLYRA_BAY_SECONDS
		_started = true
	if _remaining > 0.0:
		_remaining -= delta
		return

	if not _warned:
		_warned = true
		brain.world_events.append({"what": "message",
			"message": "MUSIC BOX WOUND DOWN // FACILITY NOISE RISING"})

	var meters = target.get("meters")
	if meters == null or not meters.has_method("add_noise"):
		return
	var rate := GameConfig.GLYRA_NOISE_PER_SECOND + GameConfig.NOISE_METER_DECAY
	var noise := rate * delta
	meters.add_noise(noise)
	_noise_gained += noise


func holds_position() -> bool:
	return true


## Called by main_3d's music-box resolver -- the interactable knows nothing
## about Glyra, only that pressing [E] on it should ask whoever owns this
## gimmick to wind it, the same indirection Ceryth's riddle uses.
func wind(meters) -> void:
	_remaining = GameConfig.GLYRA_BAY_SECONDS
	_warned = false
	if meters != null and meters.has_method("reclaim_noise") and _noise_gained > 0.0:
		meters.reclaim_noise(_noise_gained)
	_noise_gained = 0.0
