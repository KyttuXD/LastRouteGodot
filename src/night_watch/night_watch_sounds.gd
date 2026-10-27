class_name NightWatchSounds
extends RefCounted

## Night Watch's sounds: nothing of its own. Every sound goes through the shared Sound autoload (its SFX bus, the master and SFX
## volume settings, the mute switch), using the cues Last Route already has: the office cues (camera, static, footsteps, presence,
## scrape, warning, drain, shift, control, crimson_door, breath), the door sounds, the interaction fail, the menu blip, the
## pickup and the capture sting. The shared player controller plays its own footsteps through Sound.footstep (surface-aware walk,
## sprint and crouch variants), so Night Watch adds none. The 2D game's sounds (camera static, door slam, power out, radio and
## call blips, footsteps by room, the knock at a door) are mapped to those cues here and nowhere else.

## cue -> the Sound call it is (for the validator: every Night Watch sound is one of these).
const CUES := ["camera", "static", "footsteps", "presence", "scrape", "warning", "drain", "shift", "control", "crimson_door", "breath"]


static func office(cue: String, pan := 0.0, intensity := 1.0) -> void:
	Sound.queue_office_cue(cue, pan, intensity)


## A door slab moved (shut = true when it closes).
static func door(shut: bool) -> void:
	Sound.door(not shut)


static func panel_button() -> void:
	office("control", 0.0, 0.8)


static func monitor_toggle() -> void:
	office("camera")


static func camera_switch() -> void:
	office("camera")
	office("static", 0.0, 0.6)


## A hunter moved: heard by room (the pan comes from the room table) when she is in a hall or at a door.
static func hunter_event(e: Dictionary) -> void:
	var room := String(e.get("room", ""))
	var pan := float(NightWatchData.ROOMS.get(room, {}).get("pan", 0.0))
	match String(e["type"]):
		"moved":
			if room == "westhall" or room == "easthall":
				office("footsteps", pan, 1.0)
		"arrived":
			office("crimson_door", pan, 1.0)
		"flinch":
			office("presence", pan, 1.0)
		"repelled", "pushed":
			office("scrape", pan, 0.9)


static func power_out() -> void:
	office("drain")


static func hour_change() -> void:
	office("shift")


static func call_line() -> void:
	office("control", 0.0, 0.6)


static func attack_warning(pan: float) -> void:
	office("warning", pan, 1.0)


static func win() -> void:
	Sound.collect()


static func caught() -> void:
	Sound.capture()
