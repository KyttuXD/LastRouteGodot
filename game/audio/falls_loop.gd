class_name FallsLoop
extends RefCounted

## The roar of the sewer's waterfall as one seamless loop ("weird banging sound"). The old cue was a two-second
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

## Rendering the loop is about a second of GDScript on one core (measured 946-1294 ms on the main thread at the first
## bind, single runs under concurrent load). In the real game LevelAmbience therefore asks poll() instead of stream():
## the render runs once on its own high-priority worker job and the main thread adopts the result.
##
## What that does and does not change: the freeze is gone, the onset is NOT audio-neutral. A waterfall or flood that
## comes into range for the first time is silent until the job has landed (roughly: the wait for a free pool thread, plus
## the render time, plus up to one 250 ms pick of granularity) and then starts at full level in one step, as the old
## blocking bind did. Unmeasured on the Air, where it can be longer.
##
## The wait is bounded: if the job has not been adopted FALLBACK_MSEC after it was submitted (the deadline counts from
## submission, not from the pick that noticed it), poll() joins it and adopts it. The job runs concurrently from
## submission, so the join returns at max(deadline, render finish): the main-thread block is at most render - 1750 ms
## (zero on the dev PC) and the silence is about the render time, not "silence plus a full render". The remaining risk
## is a saturated worker pool or CPU contention, unmeasured on the Air.
##
## The worker lambda captures only its `out` array and calls only the static, pure _render() (local
## RandomNumberGenerators with fixed seeds, never writes _cache), so it holds no node reference and needs no join when a
## level is freed: the job lives in these statics and the next LevelAmbience simply polls the same holder. Headless and
## web keep the blocking stream() path (async_enabled false).
const FALLBACK_MSEC := 1750

static var _cache: AudioStreamWAV
## Off in headless (tests, dedicated servers) and on web: poll() then answers true and stream() renders on the caller,
## exactly as before. A test seam too.
static var async_enabled := DisplayServer.get_name() != "headless" and not OS.has_feature("web")
## Test seam: the bounded-wait deadline in ms after submission.
static var fallback_msec := FALLBACK_MSEC
static var _job := {}   # {"out": Array, "task": WorkerThreadPool id}
static var _submit_msec := -1


static func stream() -> AudioStreamWAV:
	if _cache == null:
		_cache = _render()
	return _cache


static func is_cached() -> bool:
	return _cache != null


## stream() without the wait: true once the loop is cached (stream() is then free), false while the worker job is still
## running. Starts the job on the first call, adopts it on the main thread, and joins it after fallback_msec.
static func poll() -> bool:
	if _cache != null:
		if not _job.is_empty() and WorkerThreadPool.is_task_completed(int(_job["task"])):
			WorkerThreadPool.wait_for_task_completion(int(_job["task"]))
			_job = {}
		return true
	if not async_enabled:
		return true
	if _job.is_empty():
		var fresh := []
		_job = {"out": fresh, "task": WorkerThreadPool.add_task(func() -> void:
			fresh.append(_render()), true, "falls loop")}
		_submit_msec = Time.get_ticks_msec()
	var task := int(_job["task"])
	if not WorkerThreadPool.is_task_completed(task) and Time.get_ticks_msec() - _submit_msec < fallback_msec:
		return false
	WorkerThreadPool.wait_for_task_completion(task)
	var out: Array = _job["out"]
	_job = {}
	_cache = out[0] if not out.is_empty() else _render()
	return true


## Tests only: waits for and discards any job in flight (the next poll() starts a fresh one).
static func finish() -> void:
	if not _job.is_empty():
		WorkerThreadPool.wait_for_task_completion(int(_job["task"]))
		_job = {}


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
