class_name BriselleGimmick
extends HunterGimmick

## Briselle's relay tracker (hunterAbilities.briselle.relayTracker). Ported from briselle.js. It replaced the old
## relay saboteur, which Endless routes cannot use (there is no final-relay escape to protect).
##
## Whenever ANY relay is collected she locks on to it: INVESTIGATE toward that relay for BRISELLE_HUNT_SECONDS at
## BRISELLE_SPEED_SCALE x her speed. An aimed player torch breaks the lock: she is stunned BRISELLE_FLASH_STUN_SECONDS,
## searches, and forgets the relay. The collection is detected by watching the navigation's collected-relay count, so
## no call site has to know about her.

var locked := false
var _lock_remaining := 0.0
var _relay_cell := Vector2i(-1, -1)
var _collected_seen := -1


func after_perception(brain: HunterBrain, delta: float, _target: Dictionary, generator) -> void:
	var collected := _collected_relays(generator)
	if _collected_seen < 0:
		_collected_seen = collected.size()
	elif collected.size() > _collected_seen:
		# the newest collected relay is the one that was just taken
		var newest: Dictionary = collected[collected.size() - 1]
		for entry in collected:
			if Vector2i(int(entry["x"]), int(entry["y"])) not in _known:
				newest = entry
		_lock_on(brain, newest)
	_collected_seen = collected.size()
	_known = collected.map(func(e: Dictionary) -> Vector2i: return Vector2i(int(e["x"]), int(e["y"])))

	if not locked:
		return
	if brain.flash_triggered:
		locked = false
		_lock_remaining = 0.0
		brain.apply_stun(GameConfig.BRISELLE_FLASH_STUN_SECONDS)
		brain.state = HunterBrain.State.SEARCH
		brain.has_last_known = false
		brain.world_events.append({"what": "message", "message": "SIGNAL LOCK BROKEN"})
		return
	_lock_remaining -= delta
	if _lock_remaining <= 0.0:
		locked = false
		return
	# a real sighting or heard runner takes over; otherwise stay pointed at the relay
	if brain.state != HunterBrain.State.CHASE:
		brain.state = HunterBrain.State.INVESTIGATE
		brain.has_last_known = true
		brain.last_known = Vector2(_relay_cell) + Vector2(0.5, 0.5)


var _known: Array = []


func speed_scale(_brain: HunterBrain) -> float:
	return GameConfig.BRISELLE_SPEED_SCALE if locked else 1.0


func _lock_on(brain: HunterBrain, relay: Dictionary) -> void:
	_relay_cell = Vector2i(int(relay["x"]), int(relay["y"]))
	locked = true
	_lock_remaining = GameConfig.BRISELLE_HUNT_SECONDS
	brain.state = HunterBrain.State.INVESTIGATE
	brain.has_last_known = true
	brain.last_known = Vector2(_relay_cell) + Vector2(0.5, 0.5)
	brain.world_events.append({"what": "message", "sound": "alert",
		"message": "BRISELLE DETECTED RELAY // BREAK HER LOCK WITH LIGHT"})


static func _collected_relays(generator) -> Array:
	var out := []
	for relay in generator.relays:
		if relay.get("collected", false):
			out.append(relay)
	return out


func network_state() -> Dictionary:
	return {"locked": locked}


func apply_network_state(state: Dictionary) -> void:
	locked = bool(state.get("locked", locked))
