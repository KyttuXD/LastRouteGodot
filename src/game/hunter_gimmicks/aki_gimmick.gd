class_name AkiGimmick
extends HunterGimmick

## Aki's phantom exposure (hunterAbilities.aki.phantomExposure). Ported from
## hunter-gimmicks.js's updatePhantomExposure plus aki.js's resolver.
##
## She does nothing at all until you point your torch at her and hold it there.
## That one deliberate flash starts a ten-second fuse, and then she spikes your
## exposure to full three times, five seconds apart — you lit her up, so now
## everything on the floor can see you. Then she goes quiet again and waits for
## you to do it a second time.
##
## The trigger is the RISING EDGE of the beam dwell (HunterBrain.flash_triggered),
## not "is she currently lit". Firing on the latter would restart the fuse on
## every frame the beam stayed on her, which is sixty fuses a second.
##
## She is the first hunter to read the player's beam, and the reason the
## beam-attention unlock was finally worth building.

enum Phase { IDLE, DELAY, INTERVAL }

var phase: Phase = Phase.IDLE
var bursts_remaining := 0

var _timer := 0.0


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, _generator) -> void:
	if phase == Phase.IDLE:
		if not brain.flash_triggered:
			return
		phase = Phase.DELAY
		_timer = GameConfig.AKI_INITIAL_DELAY
		bursts_remaining = GameConfig.AKI_BURST_COUNT
		return

	_timer = maxf(0.0, _timer - delta)
	if _timer > 0.0:
		return

	# The burst itself: exposure straight to full, on the player's own meters.
	var meters = target.get("meters")
	if meters != null and meters.has_method("add_exposure"):
		meters.add_exposure(GameConfig.AKI_BURST_EXPOSURE)
	bursts_remaining = maxi(0, bursts_remaining - 1)
	var burst_number := GameConfig.AKI_BURST_COUNT - bursts_remaining
	brain.world_events.append({"what": "message", "sound": "alert",
		"message": "AKI PHANTOM BURST // EXPOSURE %d%%" % int(GameConfig.AKI_BURST_EXPOSURE * minf(1.0, float(burst_number)))})
	if bursts_remaining <= 0:
		phase = Phase.IDLE
		_timer = 0.0
	else:
		phase = Phase.INTERVAL
		_timer = GameConfig.AKI_BURST_INTERVAL
