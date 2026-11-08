class_name RouteStartGate
extends RefCounted

## Solo and host runners entering a route stay on the loading screen, frozen, until the route is ready to play (entering a run was laggy -- the runner could walk while the first stream window, its colliders and the
## first-frame hitches were still landing). Guests already wait on RouteSyncGate; this is the same idea for the machine
## that builds the route itself. Only a real entry through RouteLoadingScreen arms it (RouteLoadingScreen.entering), so
## validators and in-place restarts that build the scene directly are unchanged.
##
## Ready = the nearby facility is built (chunks loaded, nothing queued or mid-build), then SMOOTH_FRAMES frames in a row
## no longer than SMOOTH_FRAME_MS (shader / first-draw hitches are over), then the runner stands on the built floor.
## Never a trap: past MAX_SECONDS it lets the runner in whatever the state.
##
## Sliced startup (opt-in, see use_sliced_startup): the opening window builds in 30 ms slices instead of a few multi-second
## frames, so the 12 s cap would no longer measure the real startup window. With a progress counter the gate instead
## gives up only after STALL_SECONDS without any progress, HARD_SECONDS in all, or MAX_SECONDS counted from the moment the
## world was built (the legacy wait for the smooth frames). The route calls StreamedFacilityView3D.finish_startup() before
## physics comes on whenever the gate opens, so the half-built window is never the state she plays in.
## STALL_SECONDS / HARD_SECONDS / LINKED_WAIT_SECONDS are UNMEASURED placeholders (needs windowed verification: the
## 2015 MacBook Air's largest single frame so far was 10.6 s).

const SMOOTH_FRAMES := 8
const SMOOTH_FRAME_MS := 50.0
## Physics is on once ready; the runner lands on the floor within a frame or two, or this long at most.
const SETTLE_SECONDS := 1.0
const MAX_SECONDS := 12.0
const STALL_SECONDS := 30.0
const HARD_SECONDS := 120.0
## Once the runner's own storey window is built, how long the gate waits for the linked storeys (their chunks stream on
## behind the player in normal play) before it counts the world as built.
const LINKED_WAIT_SECONDS := 6.0
## Flip to true to slice the opening of every real route entry; false keeps the synchronous opening as the default and
## LR_SLICED_STARTUP=1 (or 0) forces it on (or off) for a single run.
const SLICED_ON_ENTRY := false

var elapsed := 0.0
var smooth := 0
var settle := 0.0
var stall := 0.0
var built_for := 0.0
var window_for := 0.0
var _last_progress := -1


## Whether the route should build its opening window time-sliced behind the loading screen. Dedicated hosts and guests
## (waiting on the host snapshot) never slice, whatever the flag says. `flag` is the LR_SLICED_STARTUP value: "1" forces
## it on, "0" forces it off, anything else leaves SLICED_ON_ENTRY (which only applies to a real loading-screen entry).
## A forced run that did not come through the loading screen has no gate: it is a measurement mode (the benchmark), the
## player is not held and nothing completes the window for her.
static func use_sliced_startup(entering: bool, dedicated: bool, awaiting_snapshot: bool, flag: String) -> bool:
	if dedicated or awaiting_snapshot:
		return false
	if flag == "0":
		return false
	if flag == "1":
		return true
	return SLICED_ON_ENTRY and entering


## True once the world is ready for physics (the runner may fall onto the floor, still without input).
func world_ready() -> bool:
	return smooth >= SMOOTH_FRAMES


## Advances the gate one frame; returns true when the runner may play. `progress` is the sliced opening's progress
## counter (StreamedFacilityView3D.startup_progress_units(); pass nothing for the legacy gate: MAX_SECONDS from the start).
## `window` says the runner's own storey window is built: after LINKED_WAIT_SECONDS of that the linked storeys no longer
## hold the gate (`built` is then taken as true).
func tick(delta: float, built: bool, on_floor: bool, progress := -1, window := false) -> bool:
	elapsed += delta
	if progress >= 0 and window:
		window_for += delta
		if window_for >= LINKED_WAIT_SECONDS:
			built = true
	var was_smooth := smooth
	if not world_ready():
		smooth = smooth + 1 if built and delta * 1000.0 <= SMOOTH_FRAME_MS else 0
	else:
		settle += delta
	if progress < 0:
		if elapsed >= MAX_SECONDS:
			return true
	else:
		if progress != _last_progress or smooth > was_smooth:
			stall = 0.0
		else:
			stall += delta
		_last_progress = progress
		if built:
			built_for += delta
		if stall >= STALL_SECONDS or elapsed >= HARD_SECONDS or built_for >= MAX_SECONDS:
			return true
	return world_ready() and (on_floor or settle >= SETTLE_SECONDS)
