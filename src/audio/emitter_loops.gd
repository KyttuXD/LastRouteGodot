class_name EmitterLoops
extends RefCounted

## The looping sounds of the level layer's positional sources (LevelAmbience, docs/AMBIENCE.md): mono, seamless, rendered
## once and shared by every emitter of a kind. The waterfall and the flood gush are FallsLoop (the seamless roar that
## replaced the old banging cue); the outflow trickle and the lava are synthesized here from AmbienceSynth's primitives.
## A content pack may replace any of them as the ambience bed "emitter:<kind>" (Sound.ambience_stream).

const RATE := AmbienceSynth.RATE
const LOOP_SECONDS := 6.0
## Stored loudness of a synthesized emitter loop (RMS dBFS); positional sources are loud near and fall off with distance.
const TARGET_RMS_DB := -26.0

## The trickle out of an outflow main: dense small bubbles and a light rush.
const OUTFLOW := [{"kind": "water", "hz": 2400.0, "low": 650.0, "vol": .012, "density": 90.0, "swell": 3.0}]

static var _cache := {}


static func stream(kind: String) -> AudioStream:
	if kind == "falls" or kind == "flood":
		return FallsLoop.stream()
	if not _cache.has(kind):
		_cache[kind] = _render(kind)
	return _cache[kind]


static func kinds() -> Array:
	return ["falls", "outflow", "flood", "lava"]


static func _render(kind: String) -> AudioStreamWAV:
	var frames := int((LOOP_SECONDS + AmbienceSynth.CROSSFADE_SECONDS) * RATE)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(frames)
	right.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("emitter:" + kind)
	match kind:
		"outflow":
			for layer in OUTFLOW:
				AmbienceSynth._water(left, right, layer, rng)
		"lava":
			_lava(left, right, rng)
	var loop := int(LOOP_SECONDS * RATE)
	AmbienceSynth._high_pass(left)
	AmbienceSynth._high_pass(right)
	AmbienceSynth._fold_tail(left, loop)
	AmbienceSynth._fold_tail(right, loop)
	var mono := PackedFloat32Array()
	mono.resize(loop)
	var sum := 0.0
	for i in loop:
		mono[i] = (left[i] + right[i]) * .5
		sum += mono[i] * mono[i]
	var rms := sqrt(sum / loop)
	var gain := pow(10.0, TARGET_RMS_DB / 20.0) / maxf(rms, 1e-9)
	var bytes := PackedByteArray()
	# one guard frame past loop_end (a copy of frame 0) for Android's mixer, as AmbienceSynth does
	bytes.resize((loop + 1) * 2)
	for i in loop + 1:
		bytes.encode_s16(i * 2, roundi(clampf(mono[i % loop] * gain, -.98, .98) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = loop
	return wav


## Molten rock: slow thick bubbles (a low sine rising as it swells and bursts, 70-240 Hz), the odd plop, a faint sizzle
## and a few embers cracking.
static func _lava(left: PackedFloat32Array, right: PackedFloat32Array, rng: RandomNumberGenerator) -> void:
	AmbienceSynth._room_tone(left, right, {"hz": 700.0, "vol": .0025, "swell": 2.0}, rng)
	AmbienceSynth._crackle(left, right, {"hz": 1800.0, "vol": .004, "rate": 2.0}, rng)
	var seconds := float(left.size()) / RATE
	for _n in int(seconds * 6.0):
		var at := rng.randf_range(0.0, seconds - .5)
		var f0 := rng.randf_range(70.0, 240.0)
		var length := rng.randf_range(.12, .35)
		var gain := rng.randf_range(.3, 1.0) * .05
		var pan := rng.randf_range(-.6, .6)
		var lg := cos((pan + 1.0) * PI * .25)
		var rg := sin((pan + 1.0) * PI * .25)
		var start := int(at * RATE)
		var count := int(length * RATE)
		var phase := 0.0
		for k in count:
			var i := start + k
			if i >= left.size():
				break
			var p := float(k) / count
			phase += f0 * (1.0 + 1.4 * p * p) / RATE
			# swells, then bursts: the level rises, then a quick release with a little pop of noise
			var env := p * p * (1.0 - p) * 6.75
			var pop := rng.randf_range(-1.0, 1.0) * .4 * maxf(0.0, (p - .9) * 10.0)
			var v := (sin(TAU * phase) * env + pop) * gain
			left[i] += v * lg
			right[i] += v * rg
