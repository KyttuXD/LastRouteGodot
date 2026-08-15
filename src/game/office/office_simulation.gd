class_name OfficeSimulation
extends RefCounted

## Office Mode's stationary-defense simulation, ported from LastRoute's
## src/game/office-survivor-system.js. Presentation-agnostic in the same way
## facility_generator.gd and hunter_brain.gd are: this owns the complete night
## state and every timer, and a UI layer reads it and forwards named control
## calls back. Nothing here renders, plays audio, or advances on its own — the
## host calls update(delta) each frame and polls `phase`.
##
## Office shares nothing with Last Route's loop by design: no maze, no
## movement, no collision, no hunter perception, and its ten "Void" signals are
## explicitly NOT the A-Z hunter roster (HunterRoster is untouched here).
##
## Not ported (absent, not stubbed): audio cues (`queueOfficeCue` — no audio
## system exists in this port yet; the on-screen `event` ticker carries the
## same warnings, and every cue in the original was paired with one), the
## developer/admin invulnerability shield (no dev mode), and co-op (Office is
## host-only and single-player here).

enum Phase { ACTIVE, JUMPSCARE, LOST, WON }

var phase: Phase = Phase.ACTIVE
## Set when the shift ends: the failure/victory reason, shown by the UI.
var cause := ""
## Which Void signal ended the run (empty on victory).
var caught_by := ""

var elapsed := 0.0
var shift_duration := OfficeConfig.SHIFT_DURATION
var jumpscares_enabled := true
var jumpscare_remaining := 0.0

var power := 100.0
## How many systems are drawing power right now (1 = idle baseline), shown on
## the HUD as the classic usage-bar readout.
var usage := 1

var stamina := 100.0
var noise := 0.0
var exposure := 0

var left_door := false
var right_door := false
var desk_light := false
var monitor_open := false
var monitor_open_time := 0.0
var current_camera := "cam1"
var vent_sealed := false
var vent_seal_remaining := 0.0
var radio_frequency := 0

## Deliberately separate from the office power grid — it only ever spends on
## the reactive rear counter-flash, never on the desk systems.
var rear_flash_active := false
var rear_flash_charge := 100.0
var rear_flash_burst_timer := 0.0

var emergency_flash_ready := true
var stun_timer := 0.0
var blackout_timer := 0.0
var rear_threat_timer := 0.0

var gas_active := false

## Set by the presentation layer when the player leaves the office. The
## simulation owns the timer and the failure, so a 2D view, a 3D view or a
## headless test all reach the same outcome from the same report.
var away_from_desk := false
var away_timer := 0.0
var gas_remaining := 0.0
var gas_unmasked := 0.0
var gas_mask_held := false

var disabled_systems: Array = []
var corrupted_cameras: Array = []

## null when inactive; otherwise {"next": int, "remaining": float,
## "order": Array} — `order[position]` is the step number that node `position`
## answers to, shuffled so the correct click order isn't always left-to-right.
var gray_challenge = null

var event := ""
var event_timer := 0.0

## id -> threat state dictionary. Every threat carries every field (cheap, and
## avoids per-threat subclasses for what the original tracked as ad-hoc
## dynamic properties).
var threats := {}

var _rng: SeededRandom


## `ai_levels` optionally overrides per-threat AI (Custom Night): an id -> 0-20
## dictionary. Any id left out uses `default_ai`. Passing no config at all
## makes every threat roll its own level, matching the original's
## no-setup path.
func _init(seed_text: String, config: Dictionary = {}) -> void:
	_rng = SeededRandom.new(seed_text)

	var has_config := not config.is_empty()
	var ai_levels: Dictionary = config.get("ai_levels", {})
	var default_ai: int = clampi(int(config.get("default_ai", OfficeConfig.AI_DEFAULT)), OfficeConfig.AI_MIN, OfficeConfig.AI_MAX)
	jumpscares_enabled = bool(config.get("jumpscares", true))
	var requested_duration := float(config.get("shift_duration", OfficeConfig.SHIFT_DURATION))
	shift_duration = requested_duration if requested_duration in OfficeConfig.SHIFT_DURATION_CHOICES else OfficeConfig.SHIFT_DURATION

	# Draw order matters for seed determinism: each threat is built in
	# OfficeConfig.THREATS order, and only rolls its own AI when no config was
	# supplied (mirroring the original's `setup ? ... : randomInt(1, 20)`).
	for definition in OfficeConfig.THREATS:
		var id: String = definition["id"]
		var ai: int
		if has_config:
			ai = clampi(int(ai_levels.get(id, default_ai)), OfficeConfig.AI_MIN, OfficeConfig.AI_MAX)
		else:
			ai = _random_int(1, 20)
		threats[id] = {
			"id": id,
			"label": definition["label"],
			"color": definition["color"],
			"ai": ai,
			"progress": 0.0,
			"timer": 4.0 + _rng.next_float() * 5.0,
			"warned": false,
			# Crimson: which door she's approaching, and the window once there.
			"side": "left",
			"door_active": false,
			"door_timer": 0.0,
			# Azure: flash-edge detection and the repeating breath cue.
			"was_lit": false,
			"breath_timer": 0.0,
			# Rose: the current fake cue.
			"fake": "",
			"fake_pan": 0.0,
			# Orange: gas leak clock, lazily seeded on first update like the
			# original's `Number.isFinite(threat.gasTimer) ? ... : ...`.
			"gas_timer": 0.0,
			"gas_timer_set": false,
		}

	threats["crimson"]["side"] = "left" if _rng.next_float() < 0.5 else "right"
	threats["orange"]["timer"] = 18.0 + _rng.next_float() * 12.0
	threats["violet"]["timer"] = 16.0 + _rng.next_float() * 10.0
	threats["gray"]["timer"] = 30.0 + _rng.next_float() * 20.0
	threats["black"]["timer"] = 26.0 + _rng.next_float() * 20.0

	var active_count := active_threat_count()
	_announce("SHIFT START // %d VOID SIGNAL%s ACTIVE" % [active_count, "" if active_count == 1 else "S"], 3.0)


#region Queries

func is_threat_enabled(threat) -> bool:
	return threat != null and int(threat["ai"]) > 0


func active_threat_count() -> int:
	var count := 0
	for threat in threats.values():
		if is_threat_enabled(threat):
			count += 1
	return count


func is_system_disabled(system: String) -> bool:
	return disabled_systems.has(system)


## 0.0-1.0 "how close is the worst signal" readout, used for the danger meter.
func danger() -> float:
	return minf(1.0, _peak_threat_progress(false))


## Which threats are visible on a camera feed right now. Azure and Black are
## never on camera — they're already in/behind the office.
func camera_signals(camera_id := "") -> Array:
	var target: String = camera_id if not camera_id.is_empty() else current_camera
	if corrupted_cameras.has(target) or blackout_timer > 0.0:
		return []
	var visible: Array = []
	for threat in threats.values():
		var id: String = threat["id"]
		if not is_threat_enabled(threat) or id == "azure" or id == "black":
			continue
		if _camera_for(threat) == target:
			visible.append(id)
	return visible


## Positions for the camera feed: fixed per threat, spread horizontally when
## several share a camera. Scale grows with progress as a "getting closer" cue
## — position stays static so a portrait doesn't visibly jitter every frame.
func camera_actors(camera_id := "") -> Array:
	var signals_on_camera := camera_signals(camera_id)
	var actors: Array = []
	for index in signals_on_camera.size():
		var id: String = signals_on_camera[index]
		var offset := (index - (signals_on_camera.size() - 1) / 2.0) * 0.22
		actors.append({
			"id": id,
			"x": 0.5 + offset,
			"y": 0.53,
			"scale": 0.68 + minf(0.18, float(threats[id]["progress"]) * 0.16),
		})
	return actors


func camera_connections(camera_id := "") -> Array:
	var target: String = camera_id if not camera_id.is_empty() else current_camera
	return OfficeConfig.CAMERA_GRAPH.get(target, [])


func camera_view(camera_id := ""):
	var target: String = camera_id if not camera_id.is_empty() else current_camera
	return OfficeConfig.CAMERA_VIEWS.get(target, null)

#endregion


#region Frame update

func update(delta: float) -> void:
	_update_away_from_desk(delta)
	if phase == Phase.JUMPSCARE:
		jumpscare_remaining = maxf(0.0, jumpscare_remaining - delta)
		if jumpscare_remaining <= 0.0:
			phase = Phase.LOST
		return
	if phase != Phase.ACTIVE:
		return

	elapsed += delta
	event_timer = maxf(0.0, event_timer - delta)
	blackout_timer = maxf(0.0, blackout_timer - delta)
	stun_timer = maxf(0.0, stun_timer - delta)

	if vent_sealed:
		vent_seal_remaining = maxf(0.0, vent_seal_remaining - delta)
		if vent_seal_remaining <= 0.0:
			vent_sealed = false
			_announce("VENT HATCH AUTO-REOPENED")

	_update_rear_flash_burst(delta)
	_update_gas_mask(delta)
	if phase != Phase.ACTIVE:
		return

	_update_power(delta)
	_update_monitor_reveal(delta)
	_update_meters(delta)
	if phase != Phase.ACTIVE:
		return

	if stun_timer <= 0.0:
		for id in OfficeConfig.threat_ids():
			# AI 0 means genuinely disabled: no timer, sabotage, challenge or
			# failure path runs for this signal at all.
			if not is_threat_enabled(threats[id]):
				continue
			_update_threat(id, delta)
			if phase != Phase.ACTIVE:
				return

	if elapsed >= shift_duration:
		_win()


func _update_threat(id: String, delta: float) -> void:
	match id:
		"crimson": _update_crimson(delta)
		"azure": _update_azure(delta)
		"amber": _update_amber(delta)
		"emerald": _update_emerald(delta)
		"rose": _update_rose(delta)
		"orange": _update_orange(delta)
		"violet": _update_violet(delta)
		"white": _update_white(delta)
		"gray": _update_gray(delta)
		"black": _update_black(delta)


func _update_power(delta: float) -> void:
	var current_usage := 1
	var drain := OfficeConfig.POWER_BASE
	if left_door and not is_system_disabled("leftDoor"):
		current_usage += 1
		drain += OfficeConfig.POWER_DOOR
	if right_door and not is_system_disabled("rightDoor"):
		current_usage += 1
		drain += OfficeConfig.POWER_DOOR
	if desk_light and not is_system_disabled("deskLight"):
		current_usage += 1
		drain += OfficeConfig.POWER_LIGHT
	if monitor_open and not is_system_disabled("cameras"):
		current_usage += 1
		drain += OfficeConfig.POWER_CAMERAS
	if vent_sealed and not is_system_disabled("vent"):
		current_usage += 1
		drain += OfficeConfig.POWER_VENT
	if radio_frequency != 0 and not is_system_disabled("radio"):
		current_usage += 1
		drain += OfficeConfig.POWER_RADIO
	if is_threat_enabled(threats["orange"]):
		drain += float(threats["orange"]["progress"]) * 0.38

	usage = current_usage
	power = maxf(0.0, power - drain * delta)
	if power <= 0.0:
		_fail("OFFICE POWER DEPLETED", "black")


## Ticks unconditionally, not inside Amber's updater: disabling Amber in Custom
## Night would otherwise freeze this at 0 forever, and the camera feed reuses it
## to drive the monitor's power-up reveal.
func _update_monitor_reveal(delta: float) -> void:
	if monitor_open and not is_system_disabled("cameras") and blackout_timer <= 0.0:
		monitor_open_time += delta
	else:
		monitor_open_time = 0.0


func _update_rear_flash_burst(delta: float) -> void:
	if rear_flash_burst_timer <= 0.0:
		return
	rear_flash_burst_timer = maxf(0.0, rear_flash_burst_timer - delta)
	if rear_flash_burst_timer <= 0.0:
		rear_flash_active = false


func _update_gas_mask(delta: float) -> void:
	if not gas_active:
		return
	gas_remaining = maxf(0.0, gas_remaining - delta)
	if gas_mask_held:
		gas_unmasked = maxf(0.0, gas_unmasked - delta * 1.8)
	else:
		gas_unmasked += delta
	if gas_unmasked >= 1.15:
		_fail("ORANGE GAS LEAK // MASK MISSED", "orange")
		return
	if gas_remaining <= 0.0:
		gas_active = false
		gas_mask_held = false
		gas_unmasked = 0.0
		_announce("GAS CLEARED // OFFICE AIR STABLE")


## Office shows the same HUD meter set as Last Route (battery/stamina/noise/
## exposure), but tracks its own: battery IS the office power, and the other
## three are derived here rather than borrowed from a player that doesn't exist.
func _update_meters(delta: float) -> void:
	stamina = minf(100.0, stamina + 9.0 * delta)
	var loud := left_door or right_door or vent_sealed
	noise = clampf(noise + (18.0 if loud else -22.0) * delta, 0.0, 100.0)
	exposure = roundi(clampf(_peak_threat_progress(true), 0.0, 1.0) * 100.0)


## Worst current threat progress, treating the three "you have seconds to react"
## states as maximum. `include_gas` adds Orange's leak (exposure meter only —
## the danger readout leaves it out, matching the original).
func _peak_threat_progress(include_gas: bool) -> float:
	var peak := 0.0
	for threat in threats.values():
		if is_threat_enabled(threat):
			peak = maxf(peak, float(threat["progress"]))
	if is_threat_enabled(threats["black"]) and rear_threat_timer > 0.0:
		peak = maxf(peak, 1.0)
	if is_threat_enabled(threats["gray"]) and gray_challenge != null:
		peak = maxf(peak, 1.0)
	if include_gas and is_threat_enabled(threats["orange"]) and gas_active:
		peak = maxf(peak, minf(1.0, 0.35 + gas_unmasked * 0.4))
	return peak

#endregion


#region Void threats

## Crimson walks a camera route to one door, then gives a 2-second window to
## shut it. Closing the right door sends her back to the start on a fresh side.
func _update_crimson(delta: float) -> void:
	var threat: Dictionary = threats["crimson"]
	if threat["door_active"]:
		var blocked: bool = left_door if threat["side"] == "left" else right_door
		if blocked:
			_retreat(threat)
			threat["door_active"] = false
			threat["side"] = "left" if _rng.next_float() < 0.5 else "right"
			_announce("CRIMSON RETREATED // %s ROUTE RESET" % String(threat["side"]).to_upper())
			return
		threat["door_timer"] = float(threat["door_timer"]) - delta
		if float(threat["door_timer"]) <= 0.0:
			_fail("%s DOOR MISSED" % String(threat["side"]).to_upper(), "crimson")
		return

	threat["timer"] = float(threat["timer"]) - delta
	if float(threat["timer"]) > 0.0:
		return
	threat["progress"] = minf(1.0, float(threat["progress"]) + 0.27)
	threat["timer"] = maxf(2.4, 8.2 - float(threat["ai"]) * 0.24) + _rng.next_float() * 1.5
	if float(threat["progress"]) >= 1.0:
		threat["door_active"] = true
		threat["door_timer"] = 2.0
		_announce("CRIMSON AT %s DOOR // 2 SECONDS" % String(threat["side"]).to_upper(), 2.0)


## Azure is countered by FLASHING the desk light, not holding it: the push-back
## fires on the off->on edge only. Leaving the light on afterward doesn't keep
## helping — that asymmetry is what rewards flashing over just leaving it lit.
func _update_azure(delta: float) -> void:
	var threat: Dictionary = threats["azure"]
	var lit := desk_light and not is_system_disabled("deskLight")
	if lit and not threat["was_lit"]:
		threat["progress"] = maxf(0.0, float(threat["progress"]) - 0.35)
		if float(threat["progress"]) < 0.55:
			threat["warned"] = false
	threat["was_lit"] = lit
	if not lit:
		threat["progress"] = float(threat["progress"]) + delta * (0.015 + float(threat["ai"]) * 0.00155)

	if float(threat["progress"]) >= 0.72 and not threat["warned"]:
		threat["warned"] = true
		_announce("AZURE SHAPE IN OFFICE // FLASH DESK LIGHT")
		threat["breath_timer"] = 1.7
	# Once warned she keeps audibly breathing rather than cueing once — the
	# primary warning while dark, since her shape is only revealed by a flash.
	if threat["warned"]:
		threat["breath_timer"] = float(threat["breath_timer"]) - delta
		if float(threat["breath_timer"]) <= 0.0:
			threat["breath_timer"] = 1.7
	if float(threat["progress"]) < 0.55:
		threat["warned"] = false
	if float(threat["progress"]) >= 1.0:
		_fail("AZURE REACHED THE DESK", "azure")


## Amber builds while the monitor is raised, accelerating the longer it stays
## up, and bleeds back down whenever it's lowered.
func _update_amber(delta: float) -> void:
	var threat: Dictionary = threats["amber"]
	if monitor_open and not is_system_disabled("cameras") and blackout_timer <= 0.0:
		var acceleration := 1.0 + minf(2.0, monitor_open_time * 0.16)
		threat["progress"] = float(threat["progress"]) + delta * (0.009 + float(threat["ai"]) * 0.00115) * acceleration
	else:
		threat["progress"] = maxf(0.0, float(threat["progress"]) - delta * 0.045)

	if float(threat["progress"]) >= 0.75 and not threat["warned"]:
		threat["warned"] = true
		_announce("AMBER AUDIO BUILDING // LOWER MONITOR")
	if float(threat["progress"]) < 0.55:
		threat["warned"] = false
	if float(threat["progress"]) >= 1.0:
		_fail("CAMERAS HELD OPEN TOO LONG", "amber")


## Emerald crawls the vent on a constant timer; sealing the hatch once she's
## far enough along turns her back.
func _update_emerald(delta: float) -> void:
	var threat: Dictionary = threats["emerald"]
	threat["progress"] = float(threat["progress"]) + delta * (0.012 + float(threat["ai"]) * 0.0009)
	if vent_sealed and not is_system_disabled("vent") and float(threat["progress"]) >= 0.7:
		_retreat(threat)
		_announce("EMERALD BLOCKED // VENT RETREATING")
	elif float(threat["progress"]) >= 0.72 and not threat["warned"]:
		threat["warned"] = true
		_announce("VENT SCRAPING // SEAL HATCH")
	if float(threat["progress"]) < 0.55:
		threat["warned"] = false
	if float(threat["progress"]) >= 1.0:
		_fail("VENT HATCH LEFT OPEN", "emerald")


## Rose never actually attacks — she only ever fires false cues, so every other
## signal's warnings become untrustworthy.
func _update_rose(delta: float) -> void:
	var threat: Dictionary = threats["rose"]
	threat["timer"] = float(threat["timer"]) - delta
	if float(threat["timer"]) > 0.0:
		return
	var fakes := [
		"FAKE FOOTSTEPS // VERIFY SIGNAL",
		"CAMERA GHOST // ROSE PATTERN",
		"FALSE BREATHING // HOLD POSITION",
		"FALSE DOOR SHADOW",
	]
	threat["fake"] = fakes[_random_int(0, fakes.size() - 1)]
	threat["fake_pan"] = -0.46 if _rng.next_float() < 0.5 else 0.46
	_announce(String(threat["fake"]))
	threat["timer"] = maxf(7.0, 18.0 - float(threat["ai"]) * 0.35) + _rng.next_float() * 9.0


## Orange knocks individual systems offline (fixed at the breaker) and
## periodically floods the office with gas, which must be masked against.
func _update_orange(delta: float) -> void:
	var threat: Dictionary = threats["orange"]
	if not threat["gas_timer_set"]:
		threat["gas_timer"] = 28.0 + _rng.next_float() * 12.0
		threat["gas_timer_set"] = true
	else:
		threat["gas_timer"] = float(threat["gas_timer"]) - delta

	if not gas_active and float(threat["gas_timer"]) <= 0.0:
		gas_active = true
		gas_remaining = 5.2
		gas_unmasked = 0.0
		gas_mask_held = false
		threat["gas_timer"] = maxf(24.0, 48.0 - float(threat["ai"]) * 0.7) + _rng.next_float() * 10.0
		_announce("ORANGE GAS LEAK // HOLD MASK", 5.2)
		return

	threat["progress"] = minf(1.0, float(threat["progress"]) + delta * (0.004 + float(threat["ai"]) * 0.00025))
	threat["timer"] = float(threat["timer"]) - delta
	if float(threat["timer"]) > 0.0:
		return

	var candidates: Array = []
	for system in OfficeConfig.SABOTAGE_SYSTEMS:
		if not disabled_systems.has(system):
			candidates.append(system)
	if not candidates.is_empty():
		var system: String = candidates[_random_int(0, candidates.size() - 1)]
		disabled_systems.append(system)
		match system:
			"leftDoor": left_door = false
			"rightDoor": right_door = false
			"deskLight": desk_light = false
			"cameras": monitor_open = false
			"vent": vent_sealed = false
			"radio": radio_frequency = 0
		_announce("ORANGE FAULT // %s OFFLINE" % _system_label(system))
	threat["timer"] = maxf(12.0, 28.0 - float(threat["ai"]) * 0.55) + _rng.next_float() * 8.0


## Violet corrupts cameras one at a time; three corrupted forces a monitor
## blackout until the feed is rebooted.
func _update_violet(delta: float) -> void:
	var threat: Dictionary = threats["violet"]
	threat["timer"] = float(threat["timer"]) - delta
	if float(threat["timer"]) > 0.0:
		return
	var available: Array = []
	for camera in OfficeConfig.CAMERAS:
		if not corrupted_cameras.has(camera):
			available.append(camera)
	if not available.is_empty():
		corrupted_cameras.append(available[_random_int(0, available.size() - 1)])
	if corrupted_cameras.size() >= 3:
		monitor_open = false
		blackout_timer = maxf(blackout_timer, 4.0)
		_announce("VIOLET MONITOR BLACKOUT // REBOOT CAMERAS")
	else:
		_announce("VIOLET CAMERA CORRUPTION // REBOOT ADVISED")
	threat["timer"] = maxf(10.0, 24.0 - float(threat["ai"]) * 0.5) + _rng.next_float() * 7.0


## White is pure light pressure: advances only in darkness, freezes solid the
## instant the desk light is on. No build-up warning, no minigame — just "keep
## the light on sometimes" weighed against what the light costs in power.
func _update_white(delta: float) -> void:
	var threat: Dictionary = threats["white"]
	if desk_light and not is_system_disabled("deskLight"):
		return
	threat["progress"] = minf(1.0, float(threat["progress"]) + delta * (0.006 + float(threat["ai"]) * 0.0006))
	if float(threat["progress"]) >= 1.0:
		_fail("WHITE REACHED THE DESK", "white")


## Gray has no build-up meter — unlike White's darkness pressure his route
## opens cold off a plain AI-scaled timer, giving no early warning.
func _update_gray(delta: float) -> void:
	var threat: Dictionary = threats["gray"]
	if gray_challenge != null:
		gray_challenge["remaining"] = float(gray_challenge["remaining"]) - delta
		if float(gray_challenge["remaining"]) <= 0.0:
			_fail("GRAY PARKOUR FAILED", "gray")
		return
	threat["timer"] = float(threat["timer"]) - delta
	if float(threat["timer"]) > 0.0:
		return
	gray_challenge = {
		"next": 0,
		"remaining": OfficeConfig.GRAY_CHALLENGE_DURATION,
		"order": _shuffled_order(4),
	}
	_announce("GRAY SIGNAL // COMPLETE THE PARKOUR IN ORDER", OfficeConfig.GRAY_CHALLENGE_DURATION)
	threat["timer"] = maxf(18.0, 42.0 - float(threat["ai"]) * 1.1) + _rng.next_float() * 14.0


## Black is already behind you — a one-second window to turn and flash.
func _update_black(delta: float) -> void:
	var threat: Dictionary = threats["black"]
	if rear_threat_timer > 0.0:
		rear_threat_timer -= delta
		if rear_threat_timer <= 0.0:
			_fail("BREATHING SIGNAL MISSED", "black")
		return
	threat["timer"] = float(threat["timer"]) - delta
	if float(threat["timer"]) <= 0.0:
		rear_threat_timer = 1.0
		_announce("BREATHING BEHIND YOU // TURN + FLASH", 1.0)

#endregion


#region Controls

## `control` is one of leftDoor / rightDoor / deskLight / cameras / vent.
## Returns the control's new state (false if the toggle was refused).
func toggle_control(control: String) -> bool:
	if phase != Phase.ACTIVE:
		return false
	if not OfficeConfig.SABOTAGE_SYSTEMS.has(control) or control == "radio":
		return false
	if is_system_disabled(control):
		_announce("%s OFFLINE // USE BREAKER" % control.to_upper())
		return false
	if power <= 0.0:
		return false

	var result := false
	match control:
		"leftDoor":
			left_door = not left_door
			result = left_door
		"rightDoor":
			right_door = not right_door
			result = right_door
		"deskLight":
			desk_light = not desk_light
			result = desk_light
		"cameras":
			monitor_open = not monitor_open
			result = monitor_open
		"vent":
			vent_sealed = not vent_sealed
			result = vent_sealed
			if vent_sealed:
				vent_seal_remaining = OfficeConfig.VENT_SEAL_DURATION

	# Violet's forced blackout used to silently revert this with no feedback,
	# which read as the monitor being broken rather than a timed lockout.
	if control == "cameras" and blackout_timer > 0.0:
		monitor_open = false
		result = false
		_announce("CAMERAS OFFLINE // BLACKOUT %dS REMAINING" % ceili(blackout_timer))
	return result


func select_camera(camera_id: String) -> bool:
	if not OfficeConfig.CAMERAS.has(camera_id):
		return false
	current_camera = camera_id
	return true


## Cycles through 4 radio frequencies; 1/2/3 each push back one specific
## signal (Crimson/Azure/Emerald) that isn't already too close to matter.
func cycle_radio() -> bool:
	if phase != Phase.ACTIVE or is_system_disabled("radio"):
		return false
	radio_frequency = (radio_frequency + 1) % 4
	var tuned_ids := ["", "crimson", "azure", "emerald"]
	var tuned_id: String = tuned_ids[radio_frequency]
	if not tuned_id.is_empty():
		var target: Dictionary = threats[tuned_id]
		if is_threat_enabled(target) and float(target["progress"]) < 0.75:
			target["progress"] = maxf(0.0, float(target["progress"]) - 0.16)
	return true


## The physical breaker always restores a disabled system — even when the
## failed system is the monitor itself. A live CAM 7 view additionally clears
## Orange's parasite; blind resets repair the fault but leave its drain alive.
func reset_breaker() -> bool:
	if phase != Phase.ACTIVE:
		return false
	var has_repairs := not disabled_systems.is_empty()
	var orange_confirmed := monitor_open and current_camera == "cam7" and blackout_timer <= 0.0
	if not has_repairs and not orange_confirmed:
		_announce("NO BREAKER FAULT // CAM 7 CONFIRMS ORANGE")
		return false

	disabled_systems.clear()
	if orange_confirmed and is_threat_enabled(threats["orange"]):
		threats["orange"]["progress"] = 0.0
		threats["orange"]["timer"] = 20.0 + _rng.next_float() * 10.0
	_announce("BREAKER RESET // ORANGE CLEARED" if orange_confirmed
		else "BREAKER RESET // SYSTEMS RESTORED // ORANGE UNCONFIRMED")
	return true


func reboot_cameras() -> bool:
	if phase != Phase.ACTIVE or is_system_disabled("cameras"):
		return false
	corrupted_cameras.clear()
	blackout_timer = 2.5
	monitor_open = false
	if is_threat_enabled(threats["violet"]):
		threats["violet"]["timer"] = 16.0 + _rng.next_float() * 8.0
	_announce("CAMERA REBOOT // BLIND FOR 3 SECONDS", 2.5)
	return true


## One-use panic button: stuns every signal for 5 seconds and clears whichever
## instant-death prompt is currently open.
func trigger_emergency_flash() -> bool:
	if phase != Phase.ACTIVE or not emergency_flash_ready:
		return false
	emergency_flash_ready = false
	stun_timer = OfficeConfig.EMERGENCY_STUN_DURATION
	rear_threat_timer = 0.0
	gray_challenge = null
	for threat in threats.values():
		threat["progress"] = maxf(0.0, float(threat["progress"]) - 0.35)
	if is_threat_enabled(threats["black"]):
		threats["black"]["timer"] = 30.0 + _rng.next_float() * 20.0
	_announce("EMERGENCY FLASH // ALL SIGNALS STUNNED 5 SECONDS", 5.0)
	return true


## The answer to Black's rear prompt — spends rear-flash charge, not power.
func answer_rear_threat() -> bool:
	if phase != Phase.ACTIVE or rear_threat_timer <= 0.0:
		return false
	if rear_flash_charge < OfficeConfig.REAR_FLASH_COST:
		_announce("REAR THREAT // FLASH CHARGE DEPLETED")
		return false
	rear_flash_charge = maxf(0.0, rear_flash_charge - OfficeConfig.REAR_FLASH_COST)
	rear_flash_active = true
	rear_flash_burst_timer = 0.35
	rear_threat_timer = 0.0
	if is_threat_enabled(threats["black"]):
		threats["black"]["timer"] = 30.0 + _rng.next_float() * 22.0
	_announce("BLACK SIGNAL REPELLED // REAR FLASH CLEAR")
	return true


## A node's label is shuffled, so the position clicked only counts if it's the
## one currently holding the next required number — anything else (including an
## already-completed node) is an instant miss.
func advance_gray_challenge(position: int) -> bool:
	if gray_challenge == null:
		return false
	var order: Array = gray_challenge["order"]
	if position < 0 or position >= order.size():
		return false
	if order[position] != gray_challenge["next"]:
		_fail("GRAY PARKOUR MISSED // WRONG NODE", "gray")
		return false
	gray_challenge["next"] = int(gray_challenge["next"]) + 1
	if int(gray_challenge["next"]) >= order.size():
		gray_challenge = null
		_announce("GRAY PARKOUR COMPLETE // SIGNAL LOST")
	return true


func set_gas_mask(held: bool) -> bool:
	if phase != Phase.ACTIVE or not gas_active:
		return false
	gas_mask_held = held
	return gas_mask_held

#endregion


#region Internals

## Time spent outside the office. Being away is safe for a while and then it
## is not -- which is what makes leaving the desk a decision rather than a
## free action.
func _update_away_from_desk(delta: float) -> void:
	if phase != Phase.ACTIVE:
		return
	if not away_from_desk:
		if away_timer > 0.0:
			away_timer = 0.0
			_announce("BACK AT THE DESK")
		return
	var was := away_timer
	away_timer += delta
	var left := OfficeConfig.AWAY_FROM_DESK_GRACE - away_timer
	if left <= 0.0:
		_fail("CAUGHT AWAY FROM THE DESK", _nearest_active_threat())
		return
	if left <= OfficeConfig.AWAY_FROM_DESK_WARNING \
			and was < OfficeConfig.AWAY_FROM_DESK_GRACE - OfficeConfig.AWAY_FROM_DESK_WARNING:
		_announce("SOMETHING IS MOVING // RETURN TO THE DESK",
			OfficeConfig.AWAY_FROM_DESK_WARNING)


## Whichever signal is live takes the credit, so the game-over screen names a
## real threat rather than a placeholder.
func _nearest_active_threat() -> String:
	for id in threats:
		var threat: Dictionary = threats[id]
		if threat.get("active", false):
			return String(id)
	return "crimson"


func _fail(failure_cause: String, threat_id: String) -> void:
	if phase != Phase.ACTIVE:
		return
	cause = failure_cause
	caught_by = threat_id
	if not jumpscares_enabled:
		phase = Phase.LOST
		return
	phase = Phase.JUMPSCARE
	jumpscare_remaining = OfficeConfig.JUMPSCARE_DURATION


func _win() -> void:
	if phase != Phase.ACTIVE:
		return
	phase = Phase.WON
	cause = "SHIFT COMPLETE"


func _retreat(threat: Dictionary) -> void:
	threat["progress"] = 0.0
	threat["timer"] = 4.0 + _rng.next_float() * 6.0


func _announce(message: String, duration := 2.4) -> void:
	event = message
	event_timer = duration


func _system_label(system: String) -> String:
	# leftDoor -> "LEFT DOOR", matching the original's camelCase-to-spaced split.
	var spaced := ""
	for i in system.length():
		var character := system[i]
		if character == character.to_upper() and character != character.to_lower():
			spaced += " "
		spaced += character
	return spaced.to_upper()


func _random_int(minimum: int, maximum: int) -> int:
	return minimum + int(floor(_rng.next_float() * (maximum - minimum + 1)))


## Fisher-Yates over [0, count), using the same seeded stream as the rest of
## the Void AI so a challenge's node order stays deterministic for a seed.
func _shuffled_order(count: int) -> Array:
	var order: Array = []
	for i in count:
		order.append(i)
	for index in range(order.size() - 1, 0, -1):
		var swap_with := _random_int(0, index)
		var temporary = order[index]
		order[index] = order[swap_with]
		order[swap_with] = temporary
	return order


## Which camera a threat currently reads as being on, or "" if it's not on any
## feed (already in the office, ambient, or not yet visible).
func _camera_for(threat: Dictionary) -> String:
	var id: String = threat["id"]
	var progress := float(threat["progress"])
	match id:
		"crimson":
			var route: Dictionary = OfficeConfig.THREAT_ROUTES["crimson"]
			return _camera_at_progress(route["start"], route[threat["side"]], progress)
		"amber":
			var route: Dictionary = OfficeConfig.THREAT_ROUTES["amber"]
			return _camera_at_progress(route["start"], route["destination"], progress)
		"emerald":
			var route: Dictionary = OfficeConfig.THREAT_ROUTES["emerald"]
			return _camera_at_progress(route["start"], route["destination"], progress)
		"orange":
			return "cam7"
		"white":
			return "cam4" if progress > 0.65 else ""
	return ""


func _camera_at_progress(start: String, destination: String, progress: float) -> String:
	var path := _camera_path(start, destination)
	if path.is_empty():
		return ""
	var index: int = mini(path.size() - 1, int(floor(maxf(0.0, progress) * path.size())))
	return path[index]


## Breadth-first shortest route through the camera graph.
func _camera_path(start: String, destination: String) -> Array:
	if not OfficeConfig.CAMERA_GRAPH.has(start) or not OfficeConfig.CAMERA_GRAPH.has(destination):
		return []
	var queue: Array = [[start]]
	var visited := {start: true}
	while not queue.is_empty():
		var path: Array = queue.pop_front()
		var camera: String = path[path.size() - 1]
		if camera == destination:
			return path
		for linked in OfficeConfig.CAMERA_GRAPH[camera]:
			if visited.has(linked):
				continue
			visited[linked] = true
			queue.append(path + [linked])
	return []

#endregion
