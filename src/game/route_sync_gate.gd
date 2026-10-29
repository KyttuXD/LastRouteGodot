class_name RouteSyncGate
extends RefCounted

## A guest joining or rejoining a co-op route stays on the loading screen until every step below holds, then drops in
## at its synced spawn (KT, 2026-10-28: "keep the loading player in the load screen, not stuck in spawn"). Until then
## it cannot move, is not drawn for others, and is never a hunter's target or grab (RemotePlayers skips "syncing").

const STEPS: Array[String] = ["ROUTE SIGNAL", "HOST WORLD STATE", "NEARBY FACILITY", "HOST LINK", "SPAWN"]
## After this the loading screen offers STILL SYNCING // LEAVE (the sync keeps going behind it).
const TIMEOUT_SECONDS := 30.0
## The spawn step waits for the runner to stand on built floor, or this long once everything else is ready.
const SETTLE_SECONDS := 1.0

var elapsed := 0.0
var settle := 0.0


## Index of the first step not yet met (STEPS.size() when every step holds). `checks` is one bool per step but the
## last; the spawn step is judged here from `on_floor` and how long the rest have held.
func first_unmet(checks: Array, on_floor: bool, delta: float) -> int:
	for index in checks.size():
		if not bool(checks[index]):
			settle = 0.0
			return index
	settle += delta
	return STEPS.size() if on_floor or settle >= SETTLE_SECONDS else STEPS.size() - 1


func tick(delta: float) -> void:
	elapsed += delta


func timed_out() -> bool:
	return elapsed >= TIMEOUT_SECONDS


static func label(index: int) -> String:
	var step := clampi(index, 0, STEPS.size() - 1)
	return "SYNCING ROUTE %d/%d // %s" % [step + 1, STEPS.size(), STEPS[step]]
