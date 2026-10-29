class_name AmbienceSynth
extends RefCounted

## Renders an AmbienceTable bed to a seamless looping AudioStreamWAV (docs/AMBIENCE.md). Pure and static: safe on the
## worker thread Sound renders beds on. The layer kinds keep their AmbienceTable meaning but are voiced as a space, not
## as test tones (KT: "ambient sounds are weird sounding"; tools/audio/analyse_ambience.py measured pure sine hums 50-120
## dB above the spectrum, clicks at the loop seam, hiss, and beds louder than the footsteps):
##   "noise"  room tone: decorrelated stereo noise through a two-pole low-pass (never above MAX_TONE_HZ: no hiss)
##   "hum"    a drone: narrow band noise ringing at the frequency with only a faint sine under it, slowly breathing
##   "pulse"  sparse one-shot details at jittered intervals: short ones become resonant ticks (drips, clanks, relays),
##            long ones soft swelled notes (the carnival and mall chimes), never bare beeps
##   "chirp"  scattered soft triangle trills (birds, rats), quiet and randomly placed
## Level beds (LevelAmbience) add:
##   "wind"    band-passed noise in slow gusts; a high `q` makes it hollow (the void shaft)
##   "thump"   distant low thuds at jittered intervals, sometimes a double (something heavy, far off)
##   "creak"   metal creaks: a stick-slip pulse train ringing two resonances, gliding in pitch (catwalks, cages)
##   "groan"   pipe groans: a slow gliding buzz under a low-pass, swelling in and out
##   "water"   running water: a dense spray of tiny rising bubbles over a band of noise
##   "crackle" ember cracks: sparse clicks and small bursts of them
## Then a small room reverb sized per space, a DC-blocking high-pass, a crossfade of the tail into the head (seamless
## loop) and loudness normalisation to TARGET_RMS_DB so every district sits at the same level under the footsteps.

const RATE := 22050
const LOOP_SECONDS := 10.0
const CROSSFADE_SECONDS := 1.0
## Stored loop loudness (RMS dBFS); Sound plays beds at AMBIENCE_GAIN_DB, which lands them ~12 dB under a walking step.
const TARGET_RMS_DB := -54.0
const MAX_TONE_HZ := 1600.0
const DC_CUTOFF_HZ := 30.0
## Reverb by space: [wet, feedback]. Unlisted keys are "medium".
const SPACES := {
	"small": [0.10, 0.55], "medium": [0.18, 0.68], "large": [0.30, 0.80], "huge": [0.40, 0.86],
}
const SPACE_OF := {
	"apartment": "small", "hotel": "small", "prison": "medium", "hospital": "small", "lab": "small",
	"maze": "medium", "mansion": "medium", "beach": "large", "gothic": "large", "carnival": "large",
	"greenhouse": "medium", "sewer": "large", "mall": "large", "inferno": "large",
	"room:archive": "medium", "room:chapel": "large", "room:kitchen": "small", "room:big_top": "large",
	"room:office_reception": "small", "room:cubicle_room": "small",
	"level:maze": "small", "level:mezzanine": "medium", "level:sewer": "large", "level:inferno": "medium",
	"level:void": "huge",
}


static func render(key: String, layers: Array) -> AudioStreamWAV:
	var frames := int((LOOP_SECONDS + CROSSFADE_SECONDS) * RATE)
	var left := PackedFloat32Array()
	var right := PackedFloat32Array()
	left.resize(frames)
	right.resize(frames)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for layer_value in layers:
		var layer: Dictionary = layer_value
		match String(layer.get("kind", "hum")):
			"noise":
				_room_tone(left, right, layer, rng)
			"hum":
				_drone(left, right, layer, rng)
			"pulse":
				_details(left, right, layer, rng)
			"chirp":
				_chirps(left, right, layer, rng)
			"wind":
				_wind(left, right, layer, rng)
			"thump":
				_thumps(left, right, layer, rng)
			"creak":
				_creaks(left, right, layer, rng)
			"groan":
				_groans(left, right, layer, rng)
			"water":
				_water(left, right, layer, rng)
			"crackle":
				_crackle(left, right, layer, rng)
	var space: Array = SPACES[String(SPACE_OF.get(key, "medium"))]
	_reverb(left, float(space[0]), float(space[1]), 0)
	_reverb(right, float(space[0]), float(space[1]), 7)
	_high_pass(left)
	_high_pass(right)
	var loop := int(LOOP_SECONDS * RATE)
	_fold_tail(left, loop)
	_fold_tail(right, loop)
	_normalise(left, right, loop)
	return _to_stream(left, right, loop)


## Decorrelated stereo noise, two cascaded one-pole low-passes at the layer frequency, an optional slow swell.
static func _room_tone(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := minf(float(layer.get("hz", 200.0)), MAX_TONE_HZ)
	var vol := float(layer.get("vol", .005)) * 6.0
	var swell := float(layer.get("swell", 0.0))
	var a := 1.0 - exp(-TAU * hz / RATE)
	var l1 := 0.0
	var l2 := 0.0
	var r1 := 0.0
	var r2 := 0.0
	var phase := rng.randf() * TAU
	for i in left.size():
		l1 += (rng.randf_range(-1.0, 1.0) - l1) * a
		l2 += (l1 - l2) * a
		r1 += (rng.randf_range(-1.0, 1.0) - r1) * a
		r2 += (r1 - r2) * a
		var env := 1.0
		if swell > 0.0:
			env = .6 + .4 * sin(TAU * float(i) / (swell * RATE) + phase)
		left[i] += l2 * vol * env
		right[i] += r2 * vol * env


## A two-pole resonator (bandpass) driven by noise: a hum with body and no pure-tone whine, plus a faint sine for pitch.
## The resonator's level is ridden by a fast envelope follower (LEVEL_SECONDS): raw narrowband noise lurches by ~8 dB at
## random moments, which in a low hum reads as thuds (KT on the lab bed: "some sort of banging").
const LEVEL_SECONDS := .03


static func _drone(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 100.0)), 30.0, MAX_TONE_HZ)
	var vol := float(layer.get("vol", .008))
	var r := 0.995
	var c := 2.0 * r * cos(TAU * hz / RATE)
	var y1 := 0.0
	var y2 := 0.0
	var wobble := rng.randf_range(.07, .13)
	var follow := 1.0 - exp(-1.0 / (LEVEL_SECONDS * RATE))
	# expected resonator power for unit-range drive, so the follower starts settled
	var power := pow((1.0 - r) * 4.0, 2.0) / 3.0 / ((1.0 - r) * 4.0 * (1.0 - r))
	for i in left.size():
		var t := float(i) / RATE
		var y := rng.randf_range(-1.0, 1.0) * (1.0 - r) * 4.0 + c * y1 - r * r * y2
		y2 = y1
		y1 = y
		power += (y * y - power) * follow
		var level := y / sqrt(power + 1e-12) * .25
		var breath := .85 + .15 * sin(TAU * wobble * t)
		var v := (level + .18 * sin(TAU * hz * t)) * vol * breath
		left[i] += v
		right[i] += v * .92


## Sparse details at jittered intervals. Short layers: a noise burst through a resonator at the layer frequency (a drip,
## a clank, a relay tick). Long layers (>= .25 s): a soft triangle note with a slow swell in and out.
static func _details(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 800.0)), 60.0, 2400.0)
	var vol := float(layer.get("vol", .006))
	var every := maxf(.3, float(layer.get("every", 1.5)))
	var length := clampf(float(layer.get("len", .1)), .03, 1.2)
	var t := rng.randf_range(0.0, every)
	var end := float(left.size()) / RATE - length - .05
	while t < end:
		var pan := rng.randf_range(-.6, .6)
		var gain := vol * rng.randf_range(.55, 1.0)
		if length >= .25:
			_soft_note(left, right, t, hz * rng.randf_range(.995, 1.005), length * 1.6, gain * .8, pan)
		else:
			_tick(left, right, t, hz * rng.randf_range(.9, 1.1), length, gain * 2.2, pan, rng)
		# irregular spacing: a clock-like repeat is what made these read as beeps
		t += every * rng.randf_range(.6, 1.7)


static func _chirps(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 2600.0)), 200.0, 3200.0)
	var vol := float(layer.get("vol", .004)) * .6
	var seconds := float(left.size()) / RATE
	for _i in int(layer.get("count", 3)) * 2:
		var at := rng.randf_range(0.0, seconds - .6)
		var pan := rng.randf_range(-.8, .8)
		for k in rng.randi_range(2, 4):
			_soft_note(left, right, at + k * .09, hz * rng.randf_range(.92, 1.12), .07, vol, pan)


## Gusting wind: decorrelated noise through a state-variable band-pass at `hz` (Q `q`), its level and centre riding a
## smooth random gust curve with a new target about every `gust` seconds.
static func _wind(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 400.0)), 60.0, MAX_TONE_HZ)
	var vol := float(layer.get("vol", .01)) * 5.0
	var q := clampf(float(layer.get("q", 1.2)), .5, 8.0)
	var gust := maxf(1.0, float(layer.get("gust", 6.0)))
	var curve := _smooth_curve(left.size(), gust * .5, rng)
	var damp := 1.0 / q
	var states := [[0.0, 0.0], [0.0, 0.0]]
	for i in left.size():
		var g := curve[i]
		var f := 2.0 * sin(PI * hz * (.8 + .4 * g) / RATE)
		var env := (.35 + .65 * g) * vol
		for channel in 2:
			var st: Array = states[channel]
			var low: float = st[0] + f * st[1]
			var high: float = rng.randf_range(-1.0, 1.0) - low - damp * float(st[1])
			var band: float = st[1] + f * high
			st[0] = low
			st[1] = band
			if channel == 0:
				left[i] += band * env
			else:
				right[i] += band * env


## A smooth random 0..1 curve over `frames` samples: cosine-eased between random points `step` seconds apart.
static func _smooth_curve(frames: int, step: float, rng: RandomNumberGenerator) -> PackedFloat32Array:
	var curve := PackedFloat32Array()
	curve.resize(frames)
	var span := maxi(1, int(step * RATE))
	var a := rng.randf()
	var b := rng.randf()
	for i in frames:
		var k := i % span
		if k == 0 and i > 0:
			a = b
			b = rng.randf()
		var p := float(k) / span
		curve[i] = lerpf(a, b, .5 - .5 * cos(PI * p))
	return curve


## Distant thuds: a sine falling from 1.6x to `hz` with a fast decay plus a muffled noise knock, low-passed, sometimes
## followed by a softer second one.
static func _thumps(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 50.0)), 25.0, 200.0)
	var vol := float(layer.get("vol", .02))
	var every := maxf(.8, float(layer.get("every", 4.0)))
	var t := rng.randf_range(.2, every)
	var end := float(left.size()) / RATE - .8
	while t < end:
		var pan := rng.randf_range(-.7, .7)
		var gain := vol * rng.randf_range(.5, 1.0)
		_thud(left, right, t, hz * rng.randf_range(.85, 1.15), gain, pan, rng)
		if rng.randf() < .3:
			_thud(left, right, t + rng.randf_range(.18, .4), hz * rng.randf_range(.9, 1.1), gain * .55, pan, rng)
		t += every * rng.randf_range(.5, 1.6)


static func _thud(left: PackedFloat32Array, right: PackedFloat32Array, at: float, hz: float, gain: float, pan: float,
		rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var count := int(.6 * RATE)
	var lg := cos((pan + 1.0) * PI * .25)
	var rg := sin((pan + 1.0) * PI * .25)
	var a := 1.0 - exp(-TAU * 180.0 / RATE)
	var lp := 0.0
	var phase := 0.0
	for k in count:
		var i := start + k
		if i >= left.size():
			break
		var tt := float(k) / RATE
		var f := hz * (1.0 + .6 * exp(-tt * 18.0))
		phase += f / RATE
		var body := sin(TAU * phase) * exp(-tt * 7.0)
		var knock := rng.randf_range(-1.0, 1.0) * exp(-tt * 40.0) * .6
		lp += (body + knock - lp) * a
		left[i] += lp * gain * lg
		right[i] += lp * gain * rg


## Metal creaks: a stick-slip pulse train (rate 25-70 Hz, jittered) ringing resonances at `hz` and 2.31x, its pitch
## gliding, under a slow swell.
static func _creaks(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 420.0)), 120.0, MAX_TONE_HZ)
	var vol := float(layer.get("vol", .008))
	var every := maxf(1.0, float(layer.get("every", 3.5)))
	var t := rng.randf_range(.3, every)
	var end := float(left.size()) / RATE - 1.6
	while t < end:
		var length := rng.randf_range(.45, 1.3)
		var pan := rng.randf_range(-.8, .8)
		var lg := cos((pan + 1.0) * PI * .25)
		var rg := sin((pan + 1.0) * PI * .25)
		var gain := vol * rng.randf_range(.5, 1.0) * 3.0
		var glide := rng.randf_range(-.18, .18)
		var rate := rng.randf_range(25.0, 70.0)
		var start := int(t * RATE)
		var count := int(length * RATE)
		var res := [[0.0, 0.0], [0.0, 0.0]]
		var next_pulse := 0.0
		for k in count:
			var i := start + k
			if i >= left.size():
				break
			var p := float(k) / count
			var x := 0.0
			if float(k) >= next_pulse:
				x = rng.randf_range(.5, 1.0)
				next_pulse = float(k) + RATE / (rate * (1.0 + .5 * sin(PI * p)) * rng.randf_range(.8, 1.2))
			var y := 0.0
			for m in 2:
				var f0 := hz * (2.31 if m == 1 else 1.0) * (1.0 + glide * p)
				var r := .992
				var c := 2.0 * r * cos(TAU * f0 / RATE)
				var st: Array = res[m]
				var v: float = x * (1.0 - r) * 10.0 + c * float(st[0]) - r * r * float(st[1])
				st[1] = st[0]
				st[0] = v
				y += v * (.6 if m == 1 else 1.0)
			var env := sin(PI * p)
			left[i] += y * gain * env * lg
			right[i] += y * gain * env * rg
		t += every * rng.randf_range(.6, 1.6)


## Pipe groans: a sawtooth gliding around `hz` with a slow vibrato, low-passed at a few times its pitch, swelling in and out.
static func _groans(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 90.0)), 40.0, 400.0)
	var vol := float(layer.get("vol", .008))
	var every := maxf(2.0, float(layer.get("every", 6.0)))
	var t := rng.randf_range(.5, every)
	var end := float(left.size()) / RATE - 2.8
	while t < end:
		var length := rng.randf_range(1.1, 2.5)
		var pan := rng.randf_range(-.6, .6)
		var lg := cos((pan + 1.0) * PI * .25)
		var rg := sin((pan + 1.0) * PI * .25)
		var gain := vol * rng.randf_range(.6, 1.0)
		var f_start := hz * rng.randf_range(.85, 1.15)
		var f_end := f_start * rng.randf_range(.8, 1.25)
		var a := 1.0 - exp(-TAU * minf(hz * 4.0, 900.0) / RATE)
		var lp1 := 0.0
		var lp2 := 0.0
		var phase := 0.0
		var start := int(t * RATE)
		var count := int(length * RATE)
		for k in count:
			var i := start + k
			if i >= left.size():
				break
			var p := float(k) / count
			var f := lerpf(f_start, f_end, p) * (1.0 + .012 * sin(TAU * 5.5 * k / RATE))
			phase = fmod(phase + f / RATE, 1.0)
			lp1 += (phase * 2.0 - 1.0 - lp1) * a
			lp2 += (lp1 - lp2) * a
			var env := pow(sin(PI * p), 1.5)
			left[i] += lp2 * gain * env * lg
			right[i] += lp2 * gain * env * rg
		t += every * rng.randf_range(.6, 1.5)


## Running water: `density` tiny bubbles a second (a sine whose pitch rises as it decays, 300 Hz..`hz`) over a band of
## noise. Writes `left`/`right` only (shared with EmitterLoops).
static func _water(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 1400.0)), 300.0, 3000.0)
	var vol := float(layer.get("vol", .01))
	var density := clampf(float(layer.get("density", 40.0)), 2.0, 200.0)
	var low := float(layer.get("low", 300.0))
	_room_tone(left, right, {"hz": minf(hz * .5, MAX_TONE_HZ), "vol": vol * .35, "swell": float(layer.get("swell", 0.0))}, rng)
	var seconds := float(left.size()) / RATE
	for _n in int(seconds * density):
		var at := rng.randf_range(0.0, seconds - .06)
		var f0 := exp(rng.randf_range(log(low), log(hz)))
		var decay := rng.randf_range(.012, .04) * (600.0 / f0)
		var gain := vol * rng.randf_range(.2, 1.0) * 2.0
		var pan := rng.randf_range(-.7, .7)
		var lg := cos((pan + 1.0) * PI * .25)
		var rg := sin((pan + 1.0) * PI * .25)
		var start := int(at * RATE)
		var count := mini(int(decay * 5.0 * RATE), int(.08 * RATE))
		var phase := 0.0
		for k in count:
			var i := start + k
			if i >= left.size():
				break
			var tt := float(k) / RATE
			phase += f0 * (1.0 + tt / decay * .25) / RATE
			var v := sin(TAU * phase) * exp(-tt / decay) * gain
			left[i] += v * lg
			right[i] += v * rg


## Ember cracks: `rate` events a second, each a 1-3 ms click ringing at `hz`, now and then a small burst of them.
static func _crackle(left: PackedFloat32Array, right: PackedFloat32Array, layer: Dictionary, rng: RandomNumberGenerator) -> void:
	var hz := clampf(float(layer.get("hz", 2200.0)), 400.0, 3200.0)
	var vol := float(layer.get("vol", .006))
	var rate := clampf(float(layer.get("rate", 3.0)), .2, 40.0)
	var seconds := float(left.size()) / RATE
	for _n in int(seconds * rate):
		var at := rng.randf_range(0.0, seconds - .3)
		var pan := rng.randf_range(-.8, .8)
		var clicks := 1 if rng.randf() < .7 else rng.randi_range(3, 6)
		for c in clicks:
			_tick(left, right, at + c * rng.randf_range(.008, .03), hz * rng.randf_range(.7, 1.3), .02,
				vol * pow(rng.randf(), 2.0) * 3.0, pan, rng)


static func _tick(left: PackedFloat32Array, right: PackedFloat32Array, at: float, hz: float, length: float, gain: float,
		pan: float, rng: RandomNumberGenerator) -> void:
	var start := int(at * RATE)
	var count := int((length + .25) * RATE)
	var r := exp(-1.0 / (length * RATE * .5))
	var c := 2.0 * r * cos(TAU * hz / RATE)
	var y1 := 0.0
	var y2 := 0.0
	var lg := cos((pan + 1.0) * PI * .25)
	var rg := sin((pan + 1.0) * PI * .25)
	var burst := int(.004 * RATE)
	for k in count:
		var i := start + k
		if i >= left.size():
			break
		var x := rng.randf_range(-1.0, 1.0) * (1.0 if k < burst else 0.0)
		var y := x * (1.0 - r) * 8.0 + c * y1 - r * r * y2
		y2 = y1
		y1 = y
		left[i] += y * gain * lg
		right[i] += y * gain * rg


static func _soft_note(left: PackedFloat32Array, right: PackedFloat32Array, at: float, hz: float, length: float, gain: float,
		pan: float) -> void:
	var start := int(at * RATE)
	var count := int(length * RATE)
	var lg := cos((pan + 1.0) * PI * .25)
	var rg := sin((pan + 1.0) * PI * .25)
	var lp := 0.0
	var a := 1.0 - exp(-TAU * minf(hz * 2.0, MAX_TONE_HZ * 2.0) / RATE)
	for k in count:
		var i := start + k
		if i >= left.size():
			break
		var p := float(k) / float(count)
		var env := sin(PI * p)
		env *= env
		var phase := hz * float(k) / RATE
		var tri := 4.0 * absf(phase - floorf(phase + .5)) - 1.0
		lp += (tri - lp) * a
		left[i] += lp * gain * env * lg
		right[i] += lp * gain * env * rg


## Three feedback combs and an allpass (Schroeder), mixed in at `wet`; offset staggers the delays per channel.
static func _reverb(buf: PackedFloat32Array, wet: float, feedback: float, offset: int) -> void:
	var delays := [1116 + offset, 1356 + offset, 1617 + offset]
	var dry := buf.duplicate()
	var out := PackedFloat32Array()
	out.resize(buf.size())
	for d_value in delays:
		var d: int = d_value / 2   # tuned at 44.1 kHz, rendered at 22.05
		var line := PackedFloat32Array()
		line.resize(d)
		var idx := 0
		var damp := 0.0
		for i in buf.size():
			var y := line[idx]
			damp += (y - damp) * .45
			line[idx] = dry[i] + damp * feedback
			idx = (idx + 1) % d
			out[i] += y / 3.0
	var ad := 278 + offset
	var aline := PackedFloat32Array()
	aline.resize(ad)
	var aidx := 0
	for i in buf.size():
		var b := aline[aidx]
		var y := -out[i] * .5 + b
		aline[aidx] = out[i] + b * .5
		aidx = (aidx + 1) % ad
		buf[i] = dry[i] * (1.0 - wet * .5) + y * wet


static func _high_pass(buf: PackedFloat32Array) -> void:
	var r := exp(-TAU * DC_CUTOFF_HZ / RATE)
	var x1 := 0.0
	var y1 := 0.0
	for i in buf.size():
		var x := buf[i]
		var y := x - x1 + r * y1
		x1 = x
		y1 = y
		buf[i] = y


## Equal-power crossfade of the rendered tail (past `loop`) into the head, so frame loop-1 flows into frame 0.
static func _fold_tail(buf: PackedFloat32Array, loop: int) -> void:
	var fade := buf.size() - loop
	for k in fade:
		var p := float(k) / float(fade)
		buf[k] = buf[k] * sin(p * PI * .5) + buf[loop + k] * cos(p * PI * .5)


static func _normalise(left: PackedFloat32Array, right: PackedFloat32Array, loop: int) -> void:
	var sum := 0.0
	for i in loop:
		var m := (left[i] + right[i]) * .5
		sum += m * m
	var rms := sqrt(sum / float(loop))
	if rms <= 1e-9:
		return
	var gain := pow(10.0, TARGET_RMS_DB / 20.0) / rms
	for i in loop:
		left[i] *= gain
		right[i] *= gain


static func _to_stream(left: PackedFloat32Array, right: PackedFloat32Array, loop: int) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	# one guard frame past loop_end, a copy of frame 0: Android's mixer reads one frame past the end (SIGSEGV otherwise)
	bytes.resize((loop + 1) * 4)
	for i in loop + 1:
		var src := i % loop
		bytes.encode_s16(i * 4, roundi(clampf(left[src], -.98, .98) * 32767.0))
		bytes.encode_s16(i * 4 + 2, roundi(clampf(right[src], -.98, .98) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.stereo = true
	stream.data = bytes
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = loop
	return stream
