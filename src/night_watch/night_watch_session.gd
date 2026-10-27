class_name NightWatchSession
extends RefCounted

## What the menu hands to the shift scene: which night, and the seed it plays from (so Retry replays the same night).

static var night := 1
static var seed_value := 0
static var custom_levels := {}


static func start(night_number: int, seed_number: int = -1) -> void:
	night = clampi(night_number, 1, NightWatchData.NIGHTS)
	seed_value = seed_number if seed_number >= 0 else int(Time.get_ticks_usec() & 0x7fffffff)
	custom_levels = {}
