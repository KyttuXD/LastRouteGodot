class_name GuestNames
extends RefCounted

## Guest names in the 2D game's short style: one letter, a dash and four digits ("R-4821"). Letters skip I and O, digits skip 0 and 1.
## The server (backend/guest_names.mjs, POST /api/guest/name) hands them out unique and leases them to the client; this side makes a
## local one until the server answers (offline play keeps it), and the NPC teammates use the same shape.

const LETTERS := "ABCDEFGHJKLMNPQRSTUVWXYZ"
const DIGITS := "23456789"


static func valid(name: String) -> bool:
	if name.length() != 6 or name[1] != "-" or not LETTERS.contains(name[0]):
		return false
	for i in range(2, 6):
		if not DIGITS.contains(name[i]):
			return false
	return true


static func random_name() -> String:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return _build(rng)


## The same name for the same seed on every peer (NPC teammates: the room seed plus the NPC's slot).
static func from_seed(seed_value: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return _build(rng)


static func _build(rng: RandomNumberGenerator) -> String:
	var name := LETTERS[rng.randi() % LETTERS.length()] + "-"
	for i in 4:
		name += DIGITS[rng.randi() % DIGITS.length()]
	return name
