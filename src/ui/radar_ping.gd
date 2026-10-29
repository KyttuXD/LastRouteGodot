class_name RadarPing
extends RefCounted

## Porcelle's radar blip on the HUD minimap: a short, slow ping every few seconds, "there now and then" rather than a
## constant dot. Cosmetic and local (every client computes it from its own clock and the hunter mark it already has, so
## nothing extra is sent). Tune the feel here and only here.

## Seconds between pings (centre of the range) and how far each gap may wander (+- seconds, fixed per cycle so it never
## looks like a metronome but every client with the same clock agrees).
const INTERVAL := 8.0
const JITTER := 2.0
## How long one ping lasts (ease in, ease out), and how far its ring grows (in mark radii).
const DURATION := 0.7
const RING_GROWTH := 3.0
## Brightest the dot and ring get (0..1 alpha).
const PEAK_ALPHA := 0.9
## Reduced motion / calm settings: no flashing; a steady dim dot that fades slowly and only a little.
const REDUCED_ALPHA := 0.38
const REDUCED_FADE := 0.10
const REDUCED_PERIOD := 6.0
## Mark size on the minimap, in cell units, and the edge margin for the "she is out of range" tick.
const MARK_RADIUS_CELLS := 0.55
const MIN_RADIUS := 3.0   # HUD units: never smaller than this, so the blip reads on a small minimap
const EDGE_MARGIN := 4.0

static var _cycle_index := 0
static var _cycle_start := 0.0


## Length of one cycle: INTERVAL +- JITTER, deterministic per index.
static func cycle_length(index: int) -> float:
	var noise := fposmod(sin(float(index) * 12.9898 + 78.233) * 43758.5453, 1.0)
	return INTERVAL + JITTER * (noise * 2.0 - 1.0)


## {"strength": 0..1 (0 = hidden between pings), "progress": 0..1 across the ping, "index": cycle number}. With
## `reduced` the strength is the steady dim level with a slow, small fade instead of a ping.
static func sample(time: float, reduced: bool = false) -> Dictionary:
	if reduced:
		var wave := 0.5 + 0.5 * sin(TAU * time / REDUCED_PERIOD)
		return {"strength": REDUCED_ALPHA - REDUCED_FADE * wave, "progress": 0.0, "index": -1}
	if time < _cycle_start:
		_cycle_index = 0
		_cycle_start = 0.0
	while time >= _cycle_start + cycle_length(_cycle_index):
		_cycle_start += cycle_length(_cycle_index)
		_cycle_index += 1
	var inside := time - _cycle_start
	if inside >= DURATION:
		return {"strength": 0.0, "progress": 1.0, "index": _cycle_index}
	var progress := inside / DURATION
	return {"strength": PEAK_ALPHA * sin(progress * PI), "progress": progress, "index": _cycle_index}


## Where and how to draw the blip for a mark at `at` (control coordinates) inside `view`: {"visible", "strength",
## "progress", "pos", "clamped", "direction"}. Out-of-range marks clamp to the edge and keep their direction for the tick.
static func marker(at: Vector2, view: Rect2, time: float, reduced: bool = false) -> Dictionary:
	var state := sample(time, reduced)
	var inner := view.grow(-EDGE_MARGIN)
	var inside := inner.has_point(at)
	var pos := at if inside else Vector2(clampf(at.x, inner.position.x, inner.end.x), clampf(at.y, inner.position.y, inner.end.y))
	var direction := (at - view.get_center()).normalized() if not inside else Vector2.ZERO
	return {"visible": float(state["strength"]) > 0.001, "strength": float(state["strength"]), "progress": float(state["progress"]),
		"pos": pos, "clamped": not inside, "direction": direction}
