extends RefCounted

## The runner's safety net under the world. Nothing exists below the Inferno (level -3 is the lowest storey and the view clamps
## its level there), so a runner who loses the ground under her there -- a hole in a chunk's collision, a chunk that was
## unloaded or never built -- falls for good ("I fell through the map underneath the inferno region"). The hunters already
## have this (HunterView3D fall recovery); the runner had none.
##
## Pure bookkeeping, no nodes: StreamedFacilityView3D feeds it the runner's position every frame. While she stands on the floor
## of a loaded chunk it remembers where; once she has been below the lowest floor by MARGIN for HOLD seconds it names that
## place to put her back. The bottom is a fixed height (the Inferno's floor minus MARGIN), so a runner on any real floor,
## in a pit, a channel trench or on the plunge can never trip it.

const MARGIN := 3.0
## Seconds below the bottom before the net acts (a deterministic debounce, not a gameplay allowance: a fall that deep is never legitimate).
const HOLD := .3
## How often the last safe place is refreshed while she stands on ground.
const REMEMBER_EVERY := .25

var last_safe := Vector3.INF
var recoveries := 0
var _below := 0.0
var _since_remember := REMEMBER_EVERY


## The height under which a runner is out of the world.
static func bottom_y() -> float:
	return float(StreamedRouteGenerator.INFERNO_LEVEL) * StreamedFacilityView3D.LEVEL_HEIGHT - MARGIN


## Advance by `delta`. `grounded`: she stands on a floor; `floor_loaded`: the chunk under her is built; `exempt`: noclip,
## spectating (the net must not fight a free camera). True when she must be put back now: at `last_safe`, or where the caller
## chooses when that is still Vector3.INF (she never stood anywhere).
func tick(delta: float, at: Vector3, grounded: bool, floor_loaded: bool, exempt: bool) -> bool:
	if exempt or not at.is_finite():
		_below = 0.0
		return false
	if at.y >= bottom_y():
		_below = 0.0
		_since_remember += delta
		if grounded and floor_loaded and _since_remember >= REMEMBER_EVERY:
			_since_remember = 0.0
			last_safe = at
		return false
	_below += delta
	if _below < HOLD:
		return false
	_below = 0.0
	recoveries += 1
	return true


## Forget the remembered place (a teleport to somewhere unrelated, a new run).
func reset() -> void:
	last_safe = Vector3.INF
	_below = 0.0
	_since_remember = REMEMBER_EVERY
