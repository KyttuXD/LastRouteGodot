class_name RemoteMotion
extends RefCounted

## Snapshot interpolation for one remote runner (RemotePlayers draws every peer body through one of these, host too).
##
## Bodies used to chase the newest 20 Hz sample with an exponential lerp, so every late, lost or bunched packet showed
## as a stall-then-lurch, and a gap became a slide or a teleport. Now samples are stamped with the sender's clock and
## drawn DELAY_MS behind the newest one, between the two samples that bracket that moment. Past the newest sample the
## body carries on at its last velocity for at most MAX_EXTRAPOLATE_MS, then holds. A jump over SNAP_METRES between
## two samples (respawn, stairs, anti-cheat snap) is a step, never a slide through walls.

const DELAY_MS := 100.0
const MAX_EXTRAPOLATE_MS := 150.0
const SNAP_METRES := 6.0
const BUFFER_SAMPLES := 32
## Clock offset = the smallest (local receive - sender stamp) over this many samples: network jitter only ever adds
## delay, so the minimum tracks the clock difference plus the fastest path, and drifts with it over ~2 s.
const OFFSET_SAMPLES := 40

var _times: Array[float] = []
var _ats: Array[Vector3] = []
var _facings: Array[float] = []
var _offsets: Array[float] = []
var _offset := 0.0


## Adds a sample stamped `sender_ms` (sender clock) that arrived at `local_ms`. Returns false (and ignores it) when it
## is not newer than the newest sample held: a duplicate or a late, reordered one.
func push(sender_ms: float, local_ms: float, at: Vector3, facing: float) -> bool:
	if not _times.is_empty() and sender_ms <= _times[-1]:
		return false
	_times.append(sender_ms)
	_ats.append(at)
	_facings.append(facing)
	if _times.size() > BUFFER_SAMPLES:
		_times.pop_front()
		_ats.pop_front()
		_facings.pop_front()
	_offsets.append(local_ms - sender_ms)
	if _offsets.size() > OFFSET_SAMPLES:
		_offsets.pop_front()
	_offset = _offsets.min()
	return true


func is_empty() -> bool:
	return _times.is_empty()


## {"at": Vector3, "facing": float} to draw at local time `local_ms`, or {} before the first sample.
func sample(local_ms: float) -> Dictionary:
	if _times.is_empty():
		return {}
	var t := local_ms - _offset - DELAY_MS
	if t <= _times[0] or _times.size() == 1:
		return {"at": _ats[0] if t <= _times[0] else _ats[-1], "facing": _facings[0] if t <= _times[0] else _facings[-1]}
	var last := _times.size() - 1
	if t < _times[last]:
		var index := last
		while index > 0 and _times[index - 1] > t:
			index -= 1
		var a := index - 1
		if _ats[a].distance_to(_ats[index]) > SNAP_METRES:
			return {"at": _ats[a], "facing": _facings[a]}
		var weight := (t - _times[a]) / maxf(_times[index] - _times[a], 0.001)
		return {"at": _ats[a].lerp(_ats[index], weight), "facing": lerp_angle(_facings[a], _facings[index], weight)}
	var ahead := minf(t - _times[last], MAX_EXTRAPOLATE_MS)
	var span := _times[last] - _times[last - 1]
	var step := _ats[last] - _ats[last - 1]
	if span <= 0.0 or step.length() > SNAP_METRES:
		return {"at": _ats[last], "facing": _facings[last]}
	return {"at": _ats[last] + step * (ahead / span), "facing": _facings[last]}
