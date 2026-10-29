class_name RavelleGimmick
extends HunterGimmick

## Ravelle's tripwire trapper (hunterAbilities.ravelle.tripwireTrapper).
## Ported from ravelle.js's updateTripwireTraps(): two invisible wires sit on
## doorway-shaped floor cells; crossing one locks her into a chase and
## PERMANENTLY raises her speed, compounding with every trigger. Her chase
## speed starts deliberately below the roster floor — the per-trigger bonus is
## what carries her past everyone else as the run goes on.
##
## The relocation rule is the subtle part and is preserved exactly: a window
## in which a wire fired does NOT earn a fresh pair. She stays locked to the
## same (now-spent) wires until a full refresh window passes with neither
## triggered.
##
## Her fake doorway is not ported — grepping the original shows only its
## renderer reads it; no gameplay logic does. It's future art, not behaviour.

var triggered_count := 0

var _wires: Array = []
var _has_wires := false
var _refresh_timer := 0.0
var _window_triggered := false


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator) -> void:
	_refresh_timer -= delta
	if not _has_wires or _refresh_timer <= 0.0:
		if not _has_wires or not _window_triggered:
			_place_wires(brain, generator)
		_refresh_timer = GameConfig.RAVELLE_TRIPWIRE_REFRESH
		_window_triggered = false

	if target.get("hidden", false) or target.get("in_safe_zone", false):
		return

	var target_position: Vector2 = target["position"]
	for wire in _wires:
		if wire["triggered"]:
			continue
		if _distance_to_segment(target_position, wire["a"], wire["b"]) > GameConfig.RAVELLE_TRIGGER_RADIUS:
			continue
		wire["triggered"] = true
		_window_triggered = true
		triggered_count += 1
		# RAVELLE TRAPS (docs/RAVELLE_TRAPS.md): the wire trips the runner -- a short stun for the one who walked into it,
		# and the bells ring: nearby hunters come to the spot (Ravelle herself is already locked on below).
		brain.world_events.append({"what": "stun", "seconds": GameConfig.RAVELLE_TRAP_STUN,
			"message": "TRIPWIRE // STUNNED"})
		brain.world_events.append({"what": "facility_alert", "at": target_position, "sound": "alert",
			"message": "BELLS RING DOWN THE HALL"})
		brain.state = HunterBrain.State.CHASE
		brain.has_last_known = true
		brain.last_known = target_position
		brain.lost_sight_timer = 0.0


## Permanent and cumulative — never reset for the rest of the floor.
func speed_scale(_brain: HunterBrain) -> float:
	return 1.0 + triggered_count * GameConfig.RAVELLE_SPEED_PER_TRIGGER


func _place_wires(brain: HunterBrain, generator) -> void:
	var candidates := _doorway_cells(generator)
	_wires.clear()
	while not candidates.is_empty() and _wires.size() < GameConfig.RAVELLE_TRIPWIRE_COUNT:
		var index := brain.next_random_index(candidates.size())
		var cell: Vector2i = candidates[index]
		candidates.remove_at(index)
		# 2D hallwayCrossingSpan: the wire spans the whole 3-wide hall, not just the doorway cell's centre.
		var centre := Vector2(cell) + Vector2(0.5, 0.5)
		var across := Vector2(0, 1.42) if generator.is_floor(cell.x - 1 + 0.5, cell.y + 0.5) \
			and generator.is_floor(cell.x + 1 + 0.5, cell.y + 0.5) else Vector2(1.42, 0)
		_wires.append({
			"position": centre,
			"a": centre - across, "b": centre + across,
			"cell": cell,
			"triggered": false,
		})
	_has_wires = true


## A doorway-shaped cell: open along one axis with at least one side of the
## other axis blocked — a pinch point rather than open floor. Direct port of
## ravelle.js's doorwayCandidates().
static func _doorway_cells(generator) -> Array:
	var cells: Array = []
	for cell in generator.floor_cells():
		var open_left: bool = generator.is_floor(cell.x - 1 + 0.5, cell.y + 0.5)
		var open_right: bool = generator.is_floor(cell.x + 1 + 0.5, cell.y + 0.5)
		var open_up: bool = generator.is_floor(cell.x + 0.5, cell.y - 1 + 0.5)
		var open_down: bool = generator.is_floor(cell.x + 0.5, cell.y + 1 + 0.5)
		var horizontal: bool = open_left and open_right and (not open_up or not open_down)
		var vertical: bool = open_up and open_down and (not open_left or not open_right)
		if horizontal or vertical:
			cells.append(cell)
	return cells


## Cuts a wire (the runner's slow, noisy disarm); returns true when one was cut. `index` is the wire's slot.
func cut_wire(index: int) -> bool:
	if index < 0 or index >= _wires.size() or bool(_wires[index]["triggered"]):
		return false
	_wires[index]["triggered"] = true
	return true


## The wires every peer draws (live ones shimmer; spent ones are gone) and the host's trap state for late joiners.
func wires() -> Array:
	return _wires


func network_state() -> Dictionary:
	var out := []
	for wire in _wires:
		out.append({"a": wire["a"], "b": wire["b"], "t": bool(wire["triggered"])})
	return {"wires": out, "n": triggered_count}


func apply_network_state(state: Dictionary) -> void:
	var list = state.get("wires", [])
	if not list is Array:
		return
	_wires.clear()
	for entry in list:
		if entry is Dictionary and entry.get("a") is Vector2 and entry.get("b") is Vector2:
			var a: Vector2 = entry["a"]
			var b: Vector2 = entry["b"]
			_wires.append({"a": a, "b": b, "position": (a + b) * .5, "cell": Vector2i((a + b) * .5), "triggered": bool(entry.get("t", false))})
	_has_wires = true
	triggered_count = int(state.get("n", triggered_count))


static func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((point - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return point.distance_to(a + ab * t)
