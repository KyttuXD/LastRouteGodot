class_name BedroomSounds
extends RefCounted

## Bedtime's cues: nothing of its own, only the shared office cues through NightWatchSounds. Everything is heard, so every
## cue is panned to the side its hunter comes from (BedroomData.PAN).

static func breath(id: String, intensity: float) -> void:
	NightWatchSounds.office("breath", float(BedroomData.PAN[id]), intensity)


static func step_in(id: String) -> void:
	NightWatchSounds.office("footsteps", float(BedroomData.PAN[id]), 0.5)


static func leave(id: String) -> void:
	NightWatchSounds.office("scrape", float(BedroomData.PAN[id]), 0.9)


static func stir() -> void:
	NightWatchSounds.office("presence", 0.0, 0.7)


static func restless() -> void:
	NightWatchSounds.office("warning", 0.0, 0.8)


static func light_on() -> void:
	NightWatchSounds.panel_button()


static func door(held: bool) -> void:
	NightWatchSounds.door(held)
