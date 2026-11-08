class_name NightWatchSession
extends RefCounted

## What the menu hands to the shift scene: which mode and level (a night, a week, a watch), the seed it plays from (so Retry replays the
## same shift) and, for a Custom Night, the hunters' sliders. `night` is the level number classic has always read.

static var mode_id := "classic"
static var night := 1
static var seed_value := 0
static var custom_levels := {}
static var is_custom := false
## Which menu screen the menu opens on ("title" at the start; "board" after a shift, as the 2D game returns to its hub).
static var menu_screen := "title"


static func start(night_number: int, seed_number: int = -1) -> void:
	start_mode("classic", night_number, {}, seed_number)


## While Night Watch is locked (GameRegistry) only a tester starts a shift; is_open() is what the mode scenes check.
static func is_open() -> bool:
	return GameRegistry.is_launchable("night_watch")


static func start_mode(mode: String, level: int, custom := {}, seed_number: int = -1) -> void:
	mode_id = mode
	night = maxi(1, level)
	if mode == "classic":
		night = clampi(night, 1, NightWatchData.NIGHTS)
	seed_value = seed_number if seed_number >= 0 else int(Time.get_ticks_usec() & 0x7fffffff)
	custom_levels = custom.duplicate()
	is_custom = not custom.is_empty()
