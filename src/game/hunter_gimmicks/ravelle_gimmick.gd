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


func before_perception(brain: HunterBrain, delta: float, target: Dictionary, generator: FacilityGenerator) -> void:
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
		if target_position.distance_to(wire["position"]) > GameConfig.RAVELLE_TRIGGER_RADIUS:
			continue
		wire["triggered"] = true
		_window_triggered = true
		triggered_count += 1
		brain.state = HunterBrain.State.CHASE
		brain.has_last_known = true
		brain.last_known = target_position
		brain.lost_sight_timer = 0.0


## Permanent and cumulative — never reset for the rest of the floor.
func speed_scale(_brain: HunterBrain) -> float:
	return 1.0 + triggered_count * GameConfig.RAVELLE_SPEED_PER_TRIGGER


func _place_wires(brain: HunterBrain, generator: FacilityGenerator) -> void:
	var candidates := _doorway_cells(generator)
	_wires.clear()
	while not candidates.is_empty() and _wires.size() < GameConfig.RAVELLE_TRIPWIRE_COUNT:
		var index := brain.next_random_index(candidates.size())
		var cell: Vector2i = candidates[index]
		candidates.remove_at(index)
		_wires.append({
			"position": Vector2(cell) + Vector2(0.5, 0.5),
			"cell": cell,
			"triggered": false,
		})
	_has_wires = true


## A doorway-shaped cell: open along one axis with at least one side of the
## other axis blocked — a pinch point rather than open floor. Direct port of
## ravelle.js's doorwayCandidates().
static func _doorway_cells(generator: FacilityGenerator) -> Array:
	var cells: Array = []
	for cell in generator.floor_cells():
		var open_left := generator.is_floor(cell.x - 1 + 0.5, cell.y + 0.5)
		var open_right := generator.is_floor(cell.x + 1 + 0.5, cell.y + 0.5)
		var open_up := generator.is_floor(cell.x + 0.5, cell.y - 1 + 0.5)
		var open_down := generator.is_floor(cell.x + 0.5, cell.y + 1 + 0.5)
		var horizontal := open_left and open_right and (not open_up or not open_down)
		var vertical := open_up and open_down and (not open_left or not open_right)
		if horizontal or vertical:
			cells.append(cell)
	return cells
