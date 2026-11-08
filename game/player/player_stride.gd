class_name PlayerStride
extends RefCounted

## Walk and sprint pace for the runner's own body (the first-person model and every teammate's copy). As for the hunters
## (HunterStride), the clip plays at real ground speed / the clip's measured stride speed, so the planted foot stays on the
## ground instead of sliding. The mannequin's walk and sprint references are in assets/hunters_blocky/stride_table.json
## (dev/look/stride_table.tscn, measured at the authored size); HunterStride.ref_speed scales them by PlayerModels.SCALE.

const TABLE_ID := "player_mannequin"
## The travel clips of the runner's body, in the order HunterStride.choose may swap between them.
const CLIPS := ["walk", "sprint"]
## Below this real ground speed (m/s) the body is still: its clip holds its pose (speed_scale 0).
const STILL_SPEED := .05


static func travels(clip: String) -> bool:
	return clip in CLIPS


## The clip to play for a state clip ("walk" or "sprint") at a real ground speed in m/s, and the speed_scale to play it at.
static func pick(state_clip: String, ground_speed: float) -> Dictionary:
	if ground_speed < STILL_SPEED:
		return {"clip": state_clip, "scale": 0.0}
	return HunterStride.choose(TABLE_ID, state_clip, ground_speed, CLIPS)
