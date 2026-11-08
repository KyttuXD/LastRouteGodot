class_name MusicProps
extends RefCounted

## Playable music-wing props (docs/MUSIC_WING.md). Interacting with a mic or an instrument plays its short cue (Sound.music)
## and, while `noise_enabled` ("music_noise", on by default), makes a noise burst that nearby hunters hear, like the
## water splash. Props not listed here are dressing.

## type -> cue (Sound.music), prompt, and the noise burst [level, seconds] (the splash is 3.0 for 1.2 s).
const PLAYABLE := {
	"micStand": {"cue": "mic", "prompt": "TAP THE MIC", "noise": [2.2, 1.4]},
	"podiumMic": {"cue": "podium", "prompt": "TAP THE MIC", "noise": [1.2, 1.0]},
	"drumKit": {"cue": "drums", "prompt": "PLAY THE DRUMS", "noise": [2.6, 2.0]},
	"electricGuitarStand": {"cue": "electric", "prompt": "STRUM THE GUITAR", "noise": [2.0, 1.6]},
	"acousticGuitarStand": {"cue": "acoustic", "prompt": "STRUM THE GUITAR", "noise": [1.2, 1.2]},
	"bassGuitarStand": {"cue": "bass", "prompt": "PLUCK THE BASS", "noise": [1.8, 1.4]},
	"keyboardStand": {"cue": "keys", "prompt": "PLAY A CHORD", "noise": [1.4, 1.2]},
	"uprightPianoMusic": {"cue": "piano", "prompt": "PLAY THE PIANO", "noise": [1.6, 1.6]},
}
## A key cannot be mashed into a wall of noise: one play per prop per this many seconds.
const COOLDOWN_SECONDS := 0.6

## music_noise defaults on. Tests and modes can turn it off; the props then only make their sound.
static var noise_enabled := true


static func is_playable(type: String) -> bool:
	return PLAYABLE.has(type)


static func prompt_for(type: String) -> String:
	return String(PLAYABLE.get(type, {}).get("prompt", "PLAY"))


## Plays `type`'s cue and, if enabled, alerts hunters through `player`'s noise burst. Returns the noise level used (0 = none).
static func play(type: String, player: Node) -> float:
	var entry: Dictionary = PLAYABLE.get(type, {})
	if entry.is_empty():
		return 0.0
	Sound.music(String(entry["cue"]))
	if not noise_enabled or player == null or not player.has_method("emit_noise_burst"):
		return 0.0
	var noise: Array = entry["noise"]
	player.emit_noise_burst(float(noise[0]), float(noise[1]))
	return float(noise[0])
