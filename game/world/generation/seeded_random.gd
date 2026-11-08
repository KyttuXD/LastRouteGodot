class_name SeededRandom
extends RefCounted

## Deterministic PRNG ported bit-for-bit from the original's maze generator
## (hashSeed: FNV-1a: createRandom: mulberry32). The same seed text always
## produces the same draw sequence as the original JavaScript implementation,
## verified against the reference by running both side by side.

const MASK32 := 0xFFFFFFFF

var _state: int


func _init(seed_text: String) -> void:
	_state = SeededRandom.hash_seed(seed_text)


static func hash_seed(text: String) -> int:
	var value := text if not text.is_empty() else "NIGHT-01"
	var hash := 2166136261
	for i in value.length():
		hash = (hash ^ value.unicode_at(i)) & MASK32
		hash = (hash * 16777619) & MASK32
	return hash


func next_float() -> float:
	_state = (_state + 0x6d2b79f5) & MASK32
	var value := _state
	value = ((value ^ (value >> 15)) * (value | 1)) & MASK32
	var mixed := (value + (((value ^ (value >> 7)) * (value | 61)) & MASK32)) & MASK32
	value = (value ^ mixed) & MASK32
	return float((value ^ (value >> 14)) & MASK32) / 4294967296.0


## Matches the common `Math.floor(random() * n)` call pattern used throughout the original.
func next_index(exclusive_max: int) -> int:
	return int(floor(next_float() * exclusive_max))
