extends Node

## Renders every ambience bed (districts and room purposes) and the footstep sets to WAV files for listening and for
## tools/audio/analyse_ambience.py: clicks at the loop seam, DC, hiss, pure tones, loudness against the footsteps.
##   godot --headless --path . res://tools/audio/render_ambience.tscn -- <out dir under res://build/>
## (a scene, not -s: the Sound autoload renders the beds.)


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "res://build/ambience" if args.is_empty() else String(args[0])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var count := 0
	for key in AmbienceTable.regions():
		_save(Sound.render_ambience(key), out, "bed_%s" % key)
		count += 1
	for purpose in AmbienceTable.room_purposes():
		_save(Sound.render_ambience("room:" + purpose), out, "room_%s" % purpose)
		count += 1
	for surface in SurfaceSounds.SURFACES:
		for mode in ["walk", "sprint"]:
			_save(Sound.render_cue("step:%s:%s:0" % [mode, surface]), out, "step_%s_%s" % [mode, surface])
			count += 1
	_save(Sound.render_cue("hunter_footstep"), out, "cue_hunter_footstep")
	print("wrote %d wav files to %s" % [count + 1, out])
	get_tree().quit()


func _save(stream: AudioStreamWAV, out: String, name: String) -> void:
	# the looping beds carry one guard frame past loop_end (Android mixer); write exactly one loop
	var copy := stream.duplicate() as AudioStreamWAV
	if copy.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		var frame_bytes := 4 if copy.stereo else 2
		var data := copy.data
		data.resize(copy.loop_end * frame_bytes)
		copy.data = data
		copy.loop_mode = AudioStreamWAV.LOOP_DISABLED
	copy.save_to_wav(ProjectSettings.globalize_path(out.path_join(name + ".wav")))
