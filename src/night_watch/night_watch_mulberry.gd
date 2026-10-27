class_name NightWatchMulberry
extends RefCounted

## The 2D game's seeded random stream (core/rng.js mulberry32), bit for bit, so a Masked Hours or Salvage Run shift made from the same seed
## draws the same numbers as the 2D logic and the validators can compare event logs with the 2D game's. `next()` is one draw in [0, 1).

const M := 0xFFFFFFFF

var a := 0


func _init(seed_number := 0) -> void:
	a = seed_number & M


static func _imul(x: int, y: int) -> int:
	return ((x & M) * (y & M)) & M


func next() -> float:
	a = (a + 0x6d2b79f5) & M
	var t := a
	t = _imul(t ^ (t >> 15), t | 1)
	t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & M)) & M
	return float((t ^ (t >> 14)) & M) / 4294967296.0


func get_state() -> int:
	return a


func set_state(v: int) -> void:
	a = v & M
