class_name NightWatchSounds
extends RefCounted

## Night Watch's sounds are the 2D game's: the synthesized `sfx` table, recreated as Sound.nw(...) cues (the same pitches, lengths, volumes and pans), played through the shared
## Sound autoload (its SFX bus, the master and SFX volume settings, the mute switch). The shared player controller still plays its own footsteps. Which cue plays when follows the 2D game: a door is `door`, the
## monitor and every camera switch `camera`, a lit door light `light_on`, a hunter in a hall `step` (panned by room, louder the nearer), at a door `step` again and `clank` on the arrival, the power going out `power_out` then a
## `chime` every 2.4 s in the dark, the hour `chime`, Zellia's ring `ring` and a `talk` blip on every second word, a caught shift `scare`, the menus `move` / `pick` / `deny`.

## the 2D cues this port plays (for the validator: every Night Watch sound is one of these, as Sound.nw cues).
const CUES := ["move", "pick", "deny", "burst", "step", "clank", "bound", "pad", "ring", "lure", "crackle", "hum", "hum_muffled", "breath", "talk", "door", "light_on", "camera", "scare", "scare_short", "power_out", "chime",
	"tape", "radio", "rustle", "zip", "clunk", "glass_tap", "hinge", "latch", "squeak", "bed_breath", "bed_step", "bed_leave", "bed_stir", "bed_restless"]


## The names an office spec's `tone_cue` may use (the room tone each mode plays through office()): mapped to 2D cues below.
const OFFICE_TONES := ["camera", "static", "footsteps", "presence", "scrape", "warning", "drain", "shift", "control", "crimson_door", "breath"]


## One 2D cue by name.
static func cue(name: String, pan := 0.0, intensity := 1.0) -> void:
	Sound.nw(name, pan, intensity)


## The old shared-cue entry point some modes still call with a Last Route cue name: mapped to the 2D cue that does the same job.
static func office(cue_name: String, pan := 0.0, intensity := 1.0) -> void:
	match cue_name:
		"camera":
			cue("camera", pan, intensity)
		"static":
			cue("burst", pan, intensity)
		"footsteps":
			cue("step", pan, intensity)
		"presence":
			cue("clank", pan, intensity)
		"scrape":
			cue("step", pan, 0.5 * intensity)
		"warning":
			cue("crackle", pan, intensity)
		"drain":
			cue("power_out", pan, intensity)
		"shift":
			cue("chime", pan, intensity)
		"crimson_door":
			cue("clank", pan, intensity)
		"breath":
			cue("breath", pan, 0.7 * intensity)
		_:
			cue("move", pan, intensity)


## A door slab moved (the 2D `door` plays for both directions).
static func door(_shut: bool) -> void:
	cue("door")


static func panel_button() -> void:
	cue("move")


static func monitor_toggle() -> void:
	cue("camera")


static func camera_switch() -> void:
	cue("camera")
	cue("burst", 0.0, 0.8)


static func light_on() -> void:
	cue("light_on")


## A hunter moved: heard by room (the pan comes from the room table) when she is in a hall or at a door.
static func hunter_event(e: Dictionary) -> void:
	var room := String(e.get("room", ""))
	var pan := float(NightWatchData.ROOMS.get(room, {}).get("pan", 0.0))
	match String(e["type"]):
		"moved":
			if room == "westhall" or room == "easthall":
				cue("step", pan, 1.0)
		"arrived":
			cue("step", pan, 0.55 / 0.35)
			cue("clank", pan)
		"flinch":
			cue("burst", pan)
		"repelled", "pushed":
			cue("door")
			cue("step", pan, 0.5 / 0.35)


static func power_out() -> void:
	cue("power_out")


static func hour_change() -> void:
	cue("chime")


## The call's ring (2D sfx.ring), when "Incoming call..." comes up.
static func call_ring() -> void:
	cue("ring")


## A talking blip on every second typed word (2D sfx.talk).
static func call_line() -> void:
	cue("talk")


static func attack_warning(pan: float) -> void:
	cue("crackle", pan)


static func win() -> void:
	cue("chime")


static func caught(short := false) -> void:
	cue("scare_short" if short else "scare")


## The 2D menu sounds on every button under `root`: a `move` blip when the pointer or the focus arrives, a `pick` when it is pressed (the shared menu blip is switched off for them). The 2D game's `deny`
## plays for a locked choice: pass `deny_when_disabled` to wire a press on a disabled button, which Godot never emits, through its gui_input.
static func wire_buttons(root: Node) -> void:
	if root is BaseButton:
		var b := root as BaseButton
		if not b.has_meta(&"nw_sounds"):
			b.set_meta(&"nw_sounds", true)
			b.set_meta(&"silent_ui", true)
			var shared := Callable(Sound, "menu_blip")   # the autoload wired its own blip when the button was added
			if b.pressed.is_connected(shared):
				b.pressed.disconnect(shared)
			b.mouse_entered.connect(func() -> void: if not b.disabled: cue("move"))
			b.focus_entered.connect(func() -> void: cue("move"))
			b.pressed.connect(func() -> void: cue("pick"))
			b.gui_input.connect(func(event: InputEvent) -> void:
				if b.disabled and event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
					cue("deny"))
	for child in root.get_children():
		wire_buttons(child)
