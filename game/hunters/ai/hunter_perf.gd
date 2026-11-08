class_name HunterPerf
extends RefCounted

## Opt-in microsecond counters for the hunter simulation (docs/PERF_PASS.md). Off in the game: every site is one static bool test.
## tests/validate_hunter_scaling.gd switches it on around its measured steps and prints where a 30 Hz step goes.
##
##   var t := HunterPerf.begin()
##   ... work ...
##   HunterPerf.end("brain.pursue", t)

static var on := false
static var usec := {}
static var calls := {}
## Plain totals (seconds stepped, ...): value added per call.
static var sums := {}
## Slowest single span per key, microseconds (hitch hunting).
static var peak := {}


static func begin() -> int:
	return Time.get_ticks_usec() if on else 0


static func end(key: String, started: int) -> void:
	if started == 0:
		return
	var spent := Time.get_ticks_usec() - started
	usec[key] = int(usec.get(key, 0)) + spent
	if spent > int(peak.get(key, 0)):
		peak[key] = spent
	calls[key] = int(calls.get(key, 0)) + 1


static func count(key: String) -> void:
	if on:
		calls[key] = int(calls.get(key, 0)) + 1


static func total(key: String, value: float) -> void:
	if on:
		sums[key] = float(sums.get(key, 0.0)) + value


static func reset() -> void:
	sums.clear()
	usec.clear()
	calls.clear()
	peak.clear()
