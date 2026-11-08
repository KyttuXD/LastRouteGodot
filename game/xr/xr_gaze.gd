class_name XRGaze
extends RefCounted

## Head-gaze clicking for the headset panels when no Touch controller is tracked and no gamepad is connected
## (docs/XR_ANDROID.md, "Playing without Touch controllers"): the panel pointer follows the head, and resting it on a
## button for DWELL_SECONDS clicks it once. Moving off (more than MOVE_TOLERANCE canvas units) restarts the dwell.

const DWELL_SECONDS := 1.2
const MOVE_TOLERANCE := 8.0

var progress := 0.0
var _anchor := Vector2(-1, -1)
var _fired := false


## Which controller points at the panels: the right one if it is tracked, else the left, else null (the head points).
static func pointer_hand(left: XRController3D, right: XRController3D) -> XRController3D:
	for hand in [right, left]:
		if hand != null and hand.get_has_tracking_data():
			return hand
	return null


## Whether dwell clicking should run: nothing else can click (no tracked hand, no gamepad).
static func dwell_wanted(hand: XRController3D) -> bool:
	return hand == null and Input.get_connected_joypads().is_empty()


## One frame with the pointer at `canvas` over `viewport`. Returns true on the frame the dwell completes over a button.
func update(viewport: Viewport, canvas: Vector2, delta: float) -> bool:
	if canvas.x < 0.0:
		reset()
		return false
	if _anchor.x < 0.0 or canvas.distance_to(_anchor) > MOVE_TOLERANCE:
		_anchor = canvas
		progress = 0.0
		_fired = false
	var hovered := viewport.gui_get_hovered_control()
	if not hovered is BaseButton or (hovered as BaseButton).disabled or _fired:
		progress = 0.0
		return false
	progress = minf(1.0, progress + delta / DWELL_SECONDS)
	if progress >= 1.0:
		_fired = true
		return true
	return false


func reset() -> void:
	progress = 0.0
	_anchor = Vector2(-1, -1)
	_fired = false
