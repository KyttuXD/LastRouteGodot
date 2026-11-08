extends RefCounted

## The chase cue for the runner standing on one floor (the chase sting, the chase ducking of the ambience bed and the danger meter all
## read it). A hunter counts only when she is on the runner's floor: audio never bleeds vertically, so a hunter one floor up or down
## that stood within the brain's cue range in plan view (directly above or below the runner) is not a chase for this floor (B4).
## Pure helpers with no scene access, so tests/validate_chase_cue.gd can check them headlessly.
## Preloaded (no class_name) so no global class cache entry is needed.


## True when any hunter on `level` is pursuing the runner at `at` (grid cells). `views` maps entity id -> view (anything with a
## `brain`), `levels` maps entity id -> the level that hunter is on. Inactive or unassigned hunters never count.
static func pursued_on_floor(views: Dictionary, levels: Dictionary, level: int, at: Vector2) -> bool:
	for entity_id in views:
		if int(levels.get(entity_id, 999999)) != level:
			continue
		var view = views[entity_id]
		if view == null or view.brain == null:
			continue
		if view.brain.pursuit_cue(at):
			return true
	return false
