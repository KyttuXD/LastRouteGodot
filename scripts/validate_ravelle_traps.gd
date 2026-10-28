extends RefCounted

## RAVELLE TRAPS (docs/RAVELLE_TRAPS.md): her wires span the hall at pinch points, walking into one stuns that runner and
## rings the bells (alert), a cut wire is spent, budgets hold (RAVELLE_TRIPWIRE_COUNT per Ravelle), the trap state
## round-trips through the network state (guests / late joiners), and a wire is never a collider (never a permanent block).
##
##   godot --headless --path . res://scenes/validate.tscn -- ravelle_traps

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var generator := StreamedRouteGenerator.new("RAVELLE")
	var navigation := StreamedHunterNavigation.new(generator, 0)
	var coords := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			coords.append(Vector3i(dx, 0, dz))
	navigation.refresh(0, coords)
	var brain := HunterBrain.new(Vector2(22.5, 22.5), "RAVELLE-T", "ravelle", "standard")
	brain.activate_at(Vector2(22.5, 22.5))
	var gimmick := brain.gimmick as RavelleGimmick
	_expect(gimmick != null, "Ravelle has no trap gimmick")
	if gimmick == null:
		return _failures
	var far := {"position": Vector2(-500, -500), "hidden": false, "in_safe_zone": false, "noise": 0.0, "flashlight_on": false}
	brain.update(1.0 / 30.0, navigation, far, 1, 0)
	var wires := gimmick.wires()
	_expect(wires.size() == GameConfig.RAVELLE_TRIPWIRE_COUNT, "%d wires placed, budget is %d" % [wires.size(), GameConfig.RAVELLE_TRIPWIRE_COUNT])
	for wire in wires:
		_expect(absf((wire["a"] as Vector2).distance_to(wire["b"]) - 2.84) < .05, "a wire does not span the 3-wide hall")
		_expect(navigation.is_floor((wire["position"] as Vector2).x, (wire["position"] as Vector2).y), "a wire sits off the floor")
	# walking through the first wire: stun + alert, wire spent
	brain.world_events.clear()
	var through: Vector2 = wires[0]["position"]
	var walker := {"position": through, "hidden": false, "in_safe_zone": false, "noise": 2.0, "flashlight_on": false}
	brain.update(1.0 / 30.0, navigation, walker, 1, 0)
	var whats := []
	for event in brain.world_events:
		whats.append(String((event as Dictionary).get("what", "")))
	_expect(whats.has("stun"), "walking into a wire did not stun the runner (%s)" % [whats])
	_expect(whats.has("facility_alert"), "the bells did not alert the hunters")
	_expect(bool(wires[0]["triggered"]), "the tripped wire is not spent")
	for event in brain.world_events:
		if String((event as Dictionary).get("what", "")) == "stun":
			_expect(is_equal_approx(float(event["seconds"]), GameConfig.RAVELLE_TRAP_STUN), "stun is not RAVELLE_TRAP_STUN")
	# a spent wire does not fire again
	brain.world_events.clear()
	brain.update(1.0 / 30.0, navigation, walker, 1, 0)
	var again := 0
	for event in brain.world_events:
		if String((event as Dictionary).get("what", "")) == "stun":
			again += 1
	_expect(again == 0, "a spent wire stunned again")
	# cutting the other one
	if wires.size() > 1:
		_expect(gimmick.cut_wire(1) and bool(wires[1]["triggered"]) and not gimmick.cut_wire(1), "cutting a wire did not spend it exactly once")
	# replication
	var copy := RavelleGimmick.new()
	copy.apply_network_state(gimmick.network_state())
	_expect(copy.wires().size() == wires.size() and bool(copy.wires()[0]["triggered"]) and copy.triggered_count == gimmick.triggered_count,
		"the trap state does not round-trip through the network state")
	if _failures == 0:
		print("  ravelle_traps  %d hall-wide wires, trip -> %.1f s stun + bells alert, spent once, cut works, replicated state matches" % [wires.size(), GameConfig.RAVELLE_TRAP_STUN])
	return _failures
