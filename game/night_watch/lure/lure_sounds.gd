class_name LureSounds
extends RefCounted

## Dead Air's cues: nothing of its own. Everything is one of the shared office cues through NightWatchSounds.

static func moved(room: String) -> void:
	var pan := float(LureData.INFO.get(room, {}).get("pan", 0.0))
	NightWatchSounds.office("scrape" if room.begins_with("vent") else "footsteps", pan, 0.8)


static func at_vent(room: String) -> void:
	NightWatchSounds.office("crimson_door", float(LureData.INFO.get(room, {}).get("pan", 0.0)), 1.0)


static func retreat(side: String) -> void:
	NightWatchSounds.office("scrape", -0.6 if side == "L" else 0.6, 0.9)


static func seal(shut: bool) -> void:
	NightWatchSounds.door(shut)


static func phantom() -> void:
	NightWatchSounds.office("static", 0.0, 0.9)


static func broken() -> void:
	NightWatchSounds.office("drain")


static func fixed() -> void:
	NightWatchSounds.office("control", 0.0, 0.9)


static func lure(room: String) -> void:
	NightWatchSounds.office("presence", float(LureData.INFO.get(room, {}).get("pan", 0.0)), 0.8)


static func deny() -> void:
	NightWatchSounds.office("control", 0.0, 0.3)


static func appliance() -> void:
	NightWatchSounds.panel_button()


static func warning(pan: float) -> void:
	NightWatchSounds.attack_warning(pan)
