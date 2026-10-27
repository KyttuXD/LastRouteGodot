class_name CityAmbience
extends Node

## The City's sound bed: a low wind-and-city hum, a distant traffic rumble, and rain when it is on. All three are short
## seamless loops rendered once from filtered noise (no audio files, like the rest of Sound) and played on the SFX bus, so the
## SFX volume setting and Sound.muted apply. Levels follow where the runner stands: indoors the street fades to a murmur
## and the rain to a patter on the roof; by day the hum is brighter and the rumble busier.

const SAMPLE_RATE := 22050
const LOOP_SECONDS := 4.0
const FADE_PER_SECOND := 1.2

var indoor_check: Callable = Callable()
var _players := {}        # name -> AudioStreamPlayer
var _targets := {}        # name -> target volume (linear)
var _levels := {}
var _rain_on := false
var _day := false
var _tracked: Node3D


func _ready() -> void:
	for entry in [["hum", 0.9, 180.0, 0.35, 7], ["rumble", 0.9, 60.0, 0.25, 11], ["rain", 1.0, 2600.0, 0.45, 19]]:
		var player := AudioStreamPlayer.new()
		player.name = String(entry[0])
		player.bus = &"SFX"
		player.stream = _loop(float(entry[1]), float(entry[2]), float(entry[3]), int(entry[4]))
		player.volume_db = -80.0
		add_child(player)
		_players[entry[0]] = player
		_targets[entry[0]] = 0.0
		_levels[entry[0]] = 0.0
	if DisplayServer.get_name() != "headless":
		for player_value in _players.values():
			(player_value as AudioStreamPlayer).play()


func configure(tracked: Node3D, rain_on: bool, day: bool) -> void:
	_tracked = tracked
	_rain_on = rain_on
	_day = day


func set_rain(on: bool) -> void:
	_rain_on = on


func is_indoors() -> bool:
	if _tracked == null or not indoor_check.is_valid():
		return false
	return bool(indoor_check.call(Vector2(_tracked.global_position.x, _tracked.global_position.z)))


## Target levels (linear 0..1) for the current situation; exposed so the validator can read them without audio hardware.
func targets() -> Dictionary:
	var indoors := is_indoors()
	var muted := Sound.muted
	var out := {
		"hum": 0.0 if muted else (0.10 if indoors else (0.30 if _day else 0.22)),
		"rumble": 0.0 if muted else (0.06 if indoors else (0.26 if _day else 0.16)),
		"rain": 0.0 if muted or not _rain_on else (0.12 if indoors else 0.34),
	}
	return out


func _process(delta: float) -> void:
	var wanted := targets()
	for name in _players:
		var level: float = _levels[name]
		level = move_toward(level, float(wanted[name]), FADE_PER_SECOND * delta)
		_levels[name] = level
		(_players[name] as AudioStreamPlayer).volume_db = linear_to_db(maxf(level, .0001))


## A seamless loop of band-limited noise: a one-pole low-pass (hum/rumble) or a bright hiss (rain) with a slow amplitude
## wobble, crossfaded over its last 0.4 s so the join is silent.
static func _loop(seconds: float, cutoff_hz: float, gain: float, seed_value: int) -> AudioStreamWAV:
	var frames := int(seconds * SAMPLE_RATE)
	var data := PackedFloat32Array()
	data.resize(frames)
	var state := maxi(1, seed_value)
	var filtered := 0.0
	var alpha := clampf(cutoff_hz / SAMPLE_RATE * 5.0, .01, .6)
	for frame in frames:
		state = int((state * 1103515245 + 12345) & 0x7fffffff)
		var white := float(state) / 1073741823.5 - 1.0
		filtered += (white - filtered) * alpha
		var sample := filtered
		if cutoff_hz > 1000.0:
			sample = white * .6 + filtered * .4   # rain keeps its hiss
		var wobble := .8 + .2 * sin(TAU * float(frame) / float(frames) * 3.0 + float(seed_value))
		data[frame] = sample * gain * wobble
	var fade := int(.4 * SAMPLE_RATE)
	for index in fade:
		var t := float(index) / float(fade)
		var head := index
		var tail := frames - fade + index
		var mixed := data[tail] * (1.0 - t) + data[head] * t
		data[tail] = mixed
	var bytes := PackedByteArray()
	bytes.resize(frames * 2)
	for frame in frames:
		bytes.encode_s16(frame * 2, roundi(clampf(data[frame], -.98, .98) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = frames
	stream.data = bytes
	return stream
