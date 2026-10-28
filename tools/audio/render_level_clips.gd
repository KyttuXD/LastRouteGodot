extends Node

## Renders a short listening clip per level of the level layer (docs/AMBIENCE.md, "Level layer"): the level's district
## bed and level bed at their in-game gains, the runner's steps where they show the level's reverb, and a walk past the
## level's positional sources (a waterfall in the sewers, lava in the Inferno) with the in-game distance falloff. The Level
## bus reverb is approximated offline (AmbienceSynth's reverb sized from LevelAmbience.REVERB plus its pre-delay echo);
## every clip gets the same make-up gain, so their loudness compares.
##   godot --headless --path . res://tools/audio/render_level_clips.tscn -- <out dir>

const RATE := AmbienceSynth.RATE
const SECONDS := 16.0
const MAKEUP_DB := 34.0
## level bed -> [district bed under it ("" none), step surface ("" none), positional kind ("" none), nearest metres]
const CLIPS := {
	"level:maze": ["maze", "concrete", "", 0.0],
	"level:mezzanine": ["", "metal", "", 0.0],
	"level:sewer": ["sewer", "", "falls", 4.0],
	"level:inferno": ["inferno", "", "lava", 2.5],
	"level:void": ["", "", "", 0.0],
}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "res://build/level_clips" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out) if out.begins_with("res://") else out)
	for key in CLIPS:
		var spec: Array = CLIPS[key]
		var frames := int(SECONDS * RATE)
		var left := PackedFloat32Array()
		var right := PackedFloat32Array()
		left.resize(frames)
		right.resize(frames)
		if String(spec[0]) != "":
			_add_loop(left, right, Sound.render_ambience(String(spec[0])), Sound.AMBIENCE_GAIN_DB, func(_t: float) -> float: return 1.0)
		var wet_left := PackedFloat32Array()
		var wet_right := PackedFloat32Array()
		wet_left.resize(frames)
		wet_right.resize(frames)
		_add_loop(wet_left, wet_right, Sound.render_ambience(key), float(LevelAmbience.GAIN_DB[key]), func(_t: float) -> float: return 1.0)
		if String(spec[1]) != "":
			for n in int(SECONDS / .5):
				if n % 8 < 5:   # walk a few steps, pause
					_add_once(wet_left, wet_right, Sound.render_cue("step:walk:%s:%d" % [spec[1], n % 4]), n * .5, 0.0)
		if String(spec[2]) != "":
			var kind := String(spec[2])
			var source := LevelAmbience.KINDS[kind] as Dictionary
			var nearest := float(spec[3])
			var far := float(source["range"])
			# walk past: far, nearest at the middle, far again; inverse-distance falloff from the source's unit size
			_add_loop(wet_left, wet_right, EmitterLoops.stream(kind), float(source["db"]), func(t: float) -> float:
				var d := lerpf(far, nearest, 1.0 - absf(t / SECONDS * 2.0 - 1.0))
				return float(source["unit"]) / maxf(d, float(source["unit"])))
		_level_reverb(wet_left, wet_right, LevelAmbience.REVERB[key] as Array)
		for i in frames:
			left[i] += wet_left[i]
			right[i] += wet_right[i]
		var gain := db_to_linear(MAKEUP_DB)
		for i in frames:
			left[i] = clampf(left[i] * gain, -.98, .98)
			right[i] = clampf(right[i] * gain, -.98, .98)
		_save(left, right, out, "level_%s" % key.trim_prefix("level:"))
	print("wrote %d level clips to %s" % [CLIPS.size(), out])
	get_tree().quit()


## Adds a looping stream (any rate, mono or stereo) at `db`, its level scaled per second by `amount`.
func _add_loop(left: PackedFloat32Array, right: PackedFloat32Array, stream: AudioStreamWAV, db: float, amount: Callable) -> void:
	var gain := db_to_linear(db)
	var frame := 4 if stream.stereo else 2
	var loop := stream.loop_end if stream.loop_mode != AudioStreamWAV.LOOP_DISABLED else stream.data.size() / frame
	var step := float(stream.mix_rate) / RATE
	var data := stream.data
	for i in left.size():
		var src := int(i * step) % loop
		var a := float(amount.call(float(i) / RATE)) * gain
		var l := data.decode_s16(src * frame) / 32767.0
		var r := data.decode_s16(src * frame + 2) / 32767.0 if stream.stereo else l
		left[i] += l * a
		right[i] += r * a


func _add_once(left: PackedFloat32Array, right: PackedFloat32Array, stream: AudioStreamWAV, at: float, db: float) -> void:
	var gain := db_to_linear(db)
	var frame := 4 if stream.stereo else 2
	var count := stream.data.size() / frame
	var step := float(stream.mix_rate) / RATE
	var start := int(at * RATE)
	var data := stream.data
	for k in int(count / step):
		var i := start + k
		if i >= left.size():
			break
		var src := int(k * step)
		var l := data.decode_s16(src * frame) / 32767.0
		var r := data.decode_s16(src * frame + 2) / 32767.0 if stream.stereo else l
		left[i] += l * gain
		right[i] += r * gain


## The Level bus reverb, offline: a Schroeder room sized by room_size and mixed at wet, then the pre-delay echo
## (predelay_msec, repeating at predelay_feedback).
func _level_reverb(left: PackedFloat32Array, right: PackedFloat32Array, preset: Array) -> void:
	var room := float(preset[0])
	var wet := float(preset[2])
	if wet <= 0.0:
		return
	AmbienceSynth._reverb(left, minf(1.0, wet * 2.0), .5 + .4 * room, 0)
	AmbienceSynth._reverb(right, minf(1.0, wet * 2.0), .5 + .4 * room, 7)
	var delay := int(float(preset[3]) / 1000.0 * RATE)
	var feedback := float(preset[4])
	if delay <= 0 or feedback <= 0.0:
		return
	for buf in [left, right]:
		var b: PackedFloat32Array = buf
		for i in range(delay, b.size()):
			b[i] += b[i - delay] * feedback * wet * 2.0


func _save(left: PackedFloat32Array, right: PackedFloat32Array, out: String, name: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(left.size() * 4)
	for i in left.size():
		bytes.encode_s16(i * 4, roundi(left[i] * 32767.0))
		bytes.encode_s16(i * 4 + 2, roundi(right[i] * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = true
	wav.data = bytes
	var path := out.path_join(name + ".wav")
	wav.save_to_wav(ProjectSettings.globalize_path(path) if path.begins_with("res://") else path)
