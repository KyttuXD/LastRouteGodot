class_name NightWatchStream
extends RefCounted

## The 2D game's seeded random streams, ported bit for bit so a 3D shift replays the 2D shift for a seed (core/rng.js mulberry32,
## core/variety-stream.js, core/jitter.js, core/time.js createPacer). Used by the Dead Air, Bedtime and The Facility logic; Classic keeps its
## own RandomNumberGenerator. A stream is an object whose `next()` gives a float in [0, 1). `stub` streams answer a fixed number (the
## rule tests' `() => 0.999`); the NEUTRAL stream answers 0.5, so every jitter is its base value, every chance fails and every pick is the first.

const VARIETY_SALT := 0x7a3c19e5
const MASK := 0xFFFFFFFF

var a := 0
var stub_value := -1.0
var neutral := false


static func seeded(seed_number: int) -> NightWatchStream:
	var s := NightWatchStream.new()
	s.a = seed_number & MASK
	return s


## A fixed answer, with no state (the 2D tests' `hit` and `first`).
static func fixed(value: float) -> NightWatchStream:
	var s := NightWatchStream.new()
	s.stub_value = value
	return s


static func make_neutral() -> NightWatchStream:
	var s := NightWatchStream.new()
	s.stub_value = 0.5
	s.neutral = true
	return s


static func _imul(x: int, y: int) -> int:
	return (x * y) & MASK


func has_state() -> bool:
	return stub_value < 0.0


func next() -> float:
	if stub_value >= 0.0:
		return stub_value
	a = (a + 0x6d2b79f5) & MASK
	var t := a
	t = _imul(t ^ (t >> 15), t | 1)
	t = t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & MASK)
	return float((t ^ (t >> 14)) & MASK) / 4294967296.0


func get_state() -> int:
	return a if has_state() else 0


func set_state(v: int) -> void:
	a = v & MASK


## core/variety-stream.js varietyStream: `given` wins, else a stream derived from rng's state (before the night's first draw), else NEUTRAL.
static func variety_of(rng: NightWatchStream, given: NightWatchStream = null) -> NightWatchStream:
	if given != null:
		return given
	if rng.has_state():
		return NightWatchStream.seeded((rng.get_state() ^ VARIETY_SALT) & MASK)
	return make_neutral()


## base +/- spread (a fraction), one draw (core/jitter.js).
static func jitter(base: float, spread: float, stream: NightWatchStream) -> float:
	var k := minf(0.9, maxf(0.0, spread))
	return base * (1.0 - k + 2.0 * k * stream.next())


## ms +/- spread, evenly (core/time.js spreadMs; default spread 0.2).
static func spread_ms(ms: float, rng: NightWatchStream, spread := 0.2) -> float:
	return ms * (1.0 - spread + 2.0 * spread * rng.next())


## A pacer multiplier built so the WAIT is what is even (core/variety-stream.js tempo).
static func tempo(vr: NightWatchStream, spread: float) -> float:
	return 1.0 / jitter(1.0, spread, vr)


static func chance(vr: NightWatchStream, p: float) -> bool:
	var u := vr.next()
	return (not vr.neutral) and u < p


static func pick_index(vr: NightWatchStream, n: int) -> int:
	var u := vr.next()
	return 0 if vr.neutral else mini(n - 1, int(floor(u * n)))
