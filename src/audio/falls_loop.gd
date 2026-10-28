class_name FallsLoop
extends RefCounted

## The roar of the sewer's waterfall as one seamless loop (KT: "weird banging sound"). The old cue was a two-second
## noise burst whose every layer decayed to silence and restarted, so the roar dipped and thumped every two seconds.
## Here every layer is filtered noise made periodic (the filters run over two copies of the noise and keep the second),
## so the loop's end flows into its start; a fast level follower keeps narrowband noise from lurching; the swell has a
## whole number of cycles in the loop. One looping stream is shared by every fall.

const RATE := 44100
const SECONDS := 8.0
const LEVEL_SECONDS := .03
## [centre Hz, resonance 0..1, gain] of the broad sheet, the white-water hiss and a quiet body.
const LAYERS := [[520.0, .35, .6], [1500.0, .5, .8], [3200.0, .4, .3]]
const SWELL_CYCLES := 3
const SWELL_DEPTH := .05

static var _cache: AudioStreamWAV


static func stream() -> AudioStreamWAV:
	if _cache == null:
		_cache = _render()
	return _cache


static func samples() -> Array[PackedFloat32Array]:
	var frames := int(SECONDS * RATE)
	var out: Array[PackedFloat32Array] = []
	for channel in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7001 + channel * 977
		var mix := PackedFloat32Array()
		mix.resize(frames)
		for layer in LAYERS:
			var layer_samples := _layer(rng, frames, float(layer[0]), float(layer[1]))
			for i in frames:
				mix[i] += layer_samples[i] * float(layer[2])
		for i in frames:
			var swell := 1.0 + SWELL_DEPTH * sin(TAU * SWELL_CYCLES * float(i) / frames + channel)
			mix[i] *= swell * .22
		out.append(mix)
	return out


## A resonant bandpass driven by noise, ridden by a fast level follower; periodic over `frames`.
static func _layer(rng: RandomNumberGenerator, frames: int, hz: float, resonance: float) -> PackedFloat32Array:
	var noise := PackedFloat32Array()
	noise.resize(frames)
	for i in frames:
		noise[i] = rng.randf_range(-1.0, 1.0)
	var r := .9 + resonance * .07
	var c := 2.0 * r * cos(TAU * hz / RATE)
	var drive := (1.0 - r) * 4.0
	var follow := 1.0 - exp(-1.0 / (LEVEL_SECONDS * RATE))
	var result := PackedFloat32Array()
	result.resize(frames)
	var y1 := 0.0
	var y2 := 0.0
	var power := drive * drive / 3.0 / ((1.0 - r) * 4.0 * (1.0 - r))
	# two passes over the same noise: the first settles the filter and the follower, the second is kept
	for pass_index in 2:
		for i in frames:
			var y := noise[i] * drive + c * y1 - r * r * y2
			y2 = y1
			y1 = y
			power += (y * y - power) * follow
			if pass_index == 1:
				result[i] = y / sqrt(power + 1e-12) * .25
	return result


static func _render() -> AudioStreamWAV:
	var channels := samples()
	var frames := channels[0].size()
	var bytes := PackedByteArray()
	bytes.resize(frames * 4)
	for i in frames:
		for channel in 2:
			var value := int(clampf(channels[channel][i], -1.0, 1.0) * 32767.0)
			bytes.encode_s16(i * 4 + channel * 2, value)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.stereo = true
	wav.mix_rate = RATE
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = frames
	return wav
