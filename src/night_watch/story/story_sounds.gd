class_name StorySounds
extends RefCounted

## The Facility's cues: nothing of its own, only the shared office cues through NightWatchSounds (docs/NIGHT_WATCH_3D.md 5c).

static func hunter_close(id: String, away: bool) -> void:
	NightWatchSounds.office("footsteps", float(StoryData.PAN[id]), 0.5 if away else 0.9)


static func hunter_back(id: String) -> void:
	NightWatchSounds.office("scrape", float(StoryData.PAN[id]), 0.6)


static func pushed(id: String) -> void:
	NightWatchSounds.office("scrape", float(StoryData.PAN[id]), 0.9)


static func alert() -> void:
	NightWatchSounds.office("presence", 0.8, 0.7)


static func bell() -> void:
	NightWatchSounds.office("warning", 0.0, 1.0)


static func lift_open() -> void:
	NightWatchSounds.office("crimson_door", 0.0, 1.0)


static func lift_leave() -> void:
	NightWatchSounds.office("shift", 0.0, 0.6)


static func door() -> void:
	NightWatchSounds.door(true)


static func arrive() -> void:
	NightWatchSounds.office("footsteps", 0.0, 0.4)


static func step_ok() -> void:
	NightWatchSounds.panel_button()


static func wrong() -> void:
	NightWatchSounds.office("warning", 0.0, 0.5)


static func deny() -> void:
	NightWatchSounds.office("control", 0.0, 0.3)


static func task_done() -> void:
	NightWatchSounds.office("shift", 0.0, 0.8)
