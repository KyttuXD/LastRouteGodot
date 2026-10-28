class_name MusicBoxTune
extends AudioStreamPlayer3D

## The tune a wound music box plays, positional (about 12 m), read from the shared MusicBoxes clock every peer ticks:
## the steady tune while it plays, slower and off-key in the last MUSIC_BOX_WINDDOWN_SECONDS, then silence. These
## sounds are the whole signal: there is no HUD for the music state.

const HEAR_DISTANCE := 12.0

var box_id := ""
var boxes: MusicBoxes
var _clock := 0.0


func _ready() -> void:
	name = "MusicBoxTune"
	unit_size = 5.0
	max_distance = HEAR_DISTANCE
	volume_db = 6.0
	position = Vector3(0, .4, 0)
	var tune := Sound.render_cue("music_box_tune").duplicate() as AudioStreamWAV
	if tune != null:
		tune.loop_mode = AudioStreamWAV.LOOP_FORWARD
		tune.loop_begin = 0
		tune.loop_end = int(tune.data.size() / 4)
		stream = tune


func _process(delta: float) -> void:
	if boxes == null:
		return
	_clock += delta
	match boxes.mood(box_id):
		MusicBoxes.Mood.PLAYING:
			pitch_scale = 1.0
			_play()
		MusicBoxes.Mood.WINDING_DOWN:
			# the spring running out: slower the closer it gets to stopping, with a wobble that pulls it off-key
			var left := boxes.seconds_left(box_id) / GameConfig.MUSIC_BOX_WINDDOWN_SECONDS
			pitch_scale = maxf(.55, .78 + .2 * left + .045 * sin(_clock * 6.3))
			_play()
		MusicBoxes.Mood.STOPPED:
			if playing:
				stop()


func _play() -> void:
	if not playing and stream != null and DisplayServer.get_name() != "headless":
		play()
