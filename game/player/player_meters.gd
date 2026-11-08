class_name PlayerMeters
extends RefCounted

## The three facility-pressure meters — exposure, noise and temperature —
## ported from the original's updatePlayerExposure / updateNoiseMeter /
## updatePlayerTemperature. Presentation-agnostic like the rest of the
## simulation: it takes the player's per-frame situation and returns nothing,
## and both the HUD and hunter gimmicks read the resulting fields.
##
## Kept out of PlayerController so hunter code can read the meters without
## depending on a presentation node, and so the 2D and 3D controllers can
## share one implementation.
##
## Not ported: per-room climate profiles (this port's rooms are still
## geometric-only, see GameConfig's temperature block), the ocean/tideline
## hazard (that's a themed room type), and the co-op remote-occupant pass.

## 0-100, how detectable the runner is right now.
var exposure := 0.0
## 0-100, facility-wide accumulated racket.
var noise_meter := 0.0
## 0-100 body temperature; 60 is neutral.
var temperature := GameConfig.TEMPERATURE_START
## The facility's ambient the body chases.
var ambient := GameConfig.TEMPERATURE_START

var overheating := false
var freezing := false

## Latched by Solyth's summon: once she wakes, temperature can never fall
## back below the extreme for the rest of the run (see solyth_gimmick.gd).
var heat_locked := false

## Banked by props/hunters during a frame and consumed by the next update —
## mirrors the original's noiseMeterInput, so several sources in one frame
## all land rather than overwriting each other.
var _noise_input := 0.0
var _ambient_rise_timer := 0.0


## `situation` keys: flashlight_on, noise (raw hearing distance), crouching,
## hidden, in_safe_zone, heater_on.
func update(delta: float, situation: Dictionary) -> void:
	_update_exposure(delta, situation)
	_update_noise(delta, situation)
	_update_temperature(delta, situation)


## Additive push from a hunter or prop (Aki's phantom burst).
func add_exposure(amount: float) -> void:
	exposure = clampf(exposure + amount, 0.0, 100.0)


## Glyra's counter: winding the music box takes back exactly what her
## unwound timer has contributed so far, from both the visible meter and
## whatever is still staged in this frame's input bank -- reclaiming only the
## meter would have it fall on wind, then rise right back up next frame from
## an already-cancelled tick still sitting in the bank.
func reclaim_noise(amount: float) -> void:
	noise_meter = maxf(0.0, noise_meter - amount)
	_noise_input = maxf(0.0, _noise_input - amount)


## Banked, not applied immediately — see _noise_input.
func add_noise(amount: float) -> void:
	_noise_input += amount


## Host-side co-op adapters reconstruct a temporary meter object for a guest.
## Hunter noise is banked rather than immediately visible, so the adapter needs
## this read-only value to forward the same delta to the meter's real owner.
func pending_noise_input() -> float:
	return _noise_input


func _update_exposure(delta: float, situation: Dictionary) -> void:
	var target := 0.0
	if not situation.get("hidden", false):
		target = GameConfig.EXPOSURE_BASE
		if situation.get("flashlight_on", false):
			target += GameConfig.EXPOSURE_FLASHLIGHT
		# `noise` is a raw hearing distance (crouch/walk/sprint), not a 0-1
		# fraction, so normalise by the loudest gait before scaling.
		var noise_fraction := clampf(float(situation.get("noise", 0.0)) / GameConfig.NOISE_SPRINT, 0.0, 1.0)
		target += noise_fraction * GameConfig.EXPOSURE_NOISE_SCALE
		if situation.get("crouching", false):
			target *= GameConfig.EXPOSURE_CROUCH_SCALE
	target = clampf(target, 0.0, 100.0)

	var ease := clampf(GameConfig.EXPOSURE_EASE * delta, 0.0, 1.0)
	exposure = clampf(exposure + (target - exposure) * ease, 0.0, 100.0)


func _update_noise(delta: float, situation: Dictionary) -> void:
	var rise := _noise_input
	_noise_input = 0.0
	if not situation.get("hidden", false):
		var noise_fraction := clampf(float(situation.get("noise", 0.0)) / GameConfig.NOISE_SPRINT, 0.0, 1.0)
		rise += noise_fraction * GameConfig.NOISE_METER_PLAYER_RATE * delta
	noise_meter = clampf(noise_meter + rise - GameConfig.NOISE_METER_DECAY * delta, 0.0, 100.0)


func _update_temperature(delta: float, situation: Dictionary) -> void:
	_drift_ambient(delta, situation)

	# The body chases the ambient rather than jumping to it, and never
	# overshoots within a frame (the original's rate clamp).
	var difference := ambient - temperature
	var response := GameConfig.BODY_TEMPERATURE_RESPONSE
	var proposed := clampf(difference * response, -response * 4.0, response * 4.0)
	var rate := difference / delta if delta > 0.0 and absf(proposed * delta) > absf(difference) else proposed
	temperature = clampf(temperature + rate * delta, 0.0, 100.0)

	# A safe zone is genuine shelter: it pulls the body straight back toward
	# neutral regardless of what the facility is doing.
	if situation.get("in_safe_zone", false):
		temperature = move_toward(temperature, GameConfig.TEMPERATURE_NEUTRAL, GameConfig.TEMPERATURE_SAFE_ZONE_PULL * delta)

	if temperature >= 100.0:
		heat_locked = true
	# Once latched, temperature can never fall back below the extreme — applied
	# after the clamp so it only ever raises.
	if heat_locked:
		temperature = maxf(temperature, GameConfig.TEMPERATURE_OVERHEAT)

	overheating = temperature >= GameConfig.TEMPERATURE_OVERHEAT
	freezing = temperature <= GameConfig.TEMPERATURE_FREEZE


## The facility warms on its own, and faster the hotter it already is — the
## original's shortening five-degree interval, which is what eventually forces
## a temperature extreme if the runner never manages it.
func _drift_ambient(delta: float, situation: Dictionary) -> void:
	if situation.get("heater_on", false):
		ambient = minf(100.0, ambient + GameConfig.TEMPERATURE_HEATER_WARM * delta)
		return

	var heat_step: int = maxi(0, int(floor((ambient - GameConfig.TEMPERATURE_NEUTRAL) / 5.0)))
	var rise_interval := maxf(0.5, 5.0 - heat_step * 0.5)
	_ambient_rise_timer += delta
	if _ambient_rise_timer < rise_interval:
		return
	_ambient_rise_timer -= rise_interval
	ambient = clampf(ambient + GameConfig.TEMPERATURE_AMBIENT_DRIFT, 0.0, 100.0)


## Movement multiplier from the current thermal state, for the player
## controller to apply. Freezing genuinely slows you down.
func movement_scale() -> float:
	return GameConfig.TEMPERATURE_FREEZE_SLOW if freezing else 1.0


## Lamp/stamina drain multiplier — overheating burns supplies faster.
func drain_scale() -> float:
	return GameConfig.TEMPERATURE_OVERHEAT_DRAIN if overheating else 1.0


func snapshot() -> Dictionary:
	return {
		"exposure": exposure,
		"noise_meter": noise_meter,
		"temperature": temperature,
		"ambient": ambient,
		"heat_locked": heat_locked,
		"ambient_rise_timer": _ambient_rise_timer,
	}


func adopt(state: Dictionary) -> bool:
	if state.is_empty():
		return false
	exposure = clampf(float(state.get("exposure", 0.0)), 0.0, 100.0)
	noise_meter = clampf(float(state.get("noise_meter", 0.0)), 0.0, 100.0)
	temperature = clampf(float(state.get("temperature",
		GameConfig.TEMPERATURE_START)), 0.0, 100.0)
	ambient = clampf(float(state.get("ambient",
		GameConfig.TEMPERATURE_START)), 0.0, 100.0)
	heat_locked = bool(state.get("heat_locked", false))
	_ambient_rise_timer = maxf(0.0, float(state.get("ambient_rise_timer", 0.0)))
	_noise_input = 0.0
	overheating = temperature >= GameConfig.TEMPERATURE_OVERHEAT
	freezing = temperature <= GameConfig.TEMPERATURE_FREEZE
	return true


## Reset between floors; the heat lock deliberately survives, matching the
## original's "permanent for the rest of the round" Solyth latch.
func reset_for_floor() -> void:
	exposure = 0.0
	noise_meter = 0.0
	_noise_input = 0.0
	_ambient_rise_timer = 0.0
	ambient = GameConfig.TEMPERATURE_START
	temperature = maxf(GameConfig.TEMPERATURE_START, GameConfig.TEMPERATURE_OVERHEAT if heat_locked else 0.0)
	overheating = false
	freezing = false
