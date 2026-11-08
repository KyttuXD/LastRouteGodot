extends RefCounted

## The +1 deck patches (DeckPatches, the Mezzanine catwalks over the maze) are removed from play
## with the void. This suite now guards the removal: over every column the noise used to mark as a deck, +1 is not a
## chunk, no level-0 chunk plans a stairwell up, no link leads above level 0, and the maze keeps its vents (has_ducts).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- deck_patches

const SEEDS := ["SOAKTEST", "ENDLESS-ROUTE", "KYTTU-LAB", "VOID-A", "UPPER-A", "REAL-B"]
const RADIUS := 6

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var old_decks := 0
	var built := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				var was_deck := DeckPatches.is_deck(seed_text, dx, dz)
				var top := Vector3i(dx, StreamedRouteGenerator.MEZZANINE_LEVEL, dz)
				_expect(not generator.is_chunk_allowed(top), "%s +1 still exists at (%d, %d)" % [seed_text, dx, dz])
				_expect(generator.highest_level_at(dx, dz) == 0, "%s the top of column (%d, %d) is above level 0" % [seed_text, dx, dz])
				_expect(generator.stairwell_between(dx, dz, StreamedRouteGenerator.MEZZANINE_LEVEL).is_empty(),
					"%s a stairwell still leads up to +1 at (%d, %d)" % [seed_text, dx, dz])
				if not was_deck:
					continue
				old_decks += 1
				if built >= 24:
					continue
				built += 1
				var maze_coord := Vector3i(dx, 0, dz)
				var data: Dictionary = generator.chunk(maze_coord)
				for well in data.get("stairwells", []):
					_expect(int(well["upper"]) <= 0, "%s maze chunk (%d, %d) still plans a way up" % [seed_text, dx, dz])
				for link in generator.vertical_links(maze_coord):
					_expect(int(link["from_level"]) <= 0 and int(link["to_level"]) <= 0,
						"%s a link above level 0 at (%d, %d): %s" % [seed_text, dx, dz, link.get("id", "")])
				_expect(generator.vents().has_ducts(maze_coord), "%s the maze under the old deck (%d, %d) has no vents" % [seed_text, dx, dz])
	_expect(old_decks > 0 and built > 0, "no old deck columns sampled")
	if _failures == 0:
		print("  deck_patches  removed: %d old deck columns (%d built) have no +1, no way up, and keep their vents" % [old_decks, built])
	return _failures
