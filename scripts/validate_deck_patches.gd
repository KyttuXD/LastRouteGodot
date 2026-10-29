extends RefCounted

## The +1 deck patches (DeckPatches): clustered blobs over about 30-50% of the maze, the spawn ring clear, and every patch
## reachable: each connected patch of deck chunks (near the spawn, where the whole patch is sampled) has a spiral well up
## from level 0, and the well's landing is walkable on both levels.
##
##   godot --headless --path . res://scenes/validate.tscn -- deck_patches

const SEEDS := ["SOAKTEST", "ENDLESS-ROUTE", "KYTTU-LAB", "VOID-A", "UPPER-A", "REAL-B"]
const RADIUS := 16

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var covered := 0.0
	var patches := 0
	var wells := 0
	var no_well := []
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		var decks := 0
		var total := 0
		for dz in range(-RADIUS, RADIUS + 1):
			for dx in range(-RADIUS, RADIUS + 1):
				if generator.is_void_column(Vector3i(dx, 0, dz)):
					continue
				total += 1
				if DeckPatches.is_deck(seed_text, dx, dz):
					decks += 1
					_expect(absi(dx) > DeckPatches.SPAWN_CLEAR or absi(dz) > DeckPatches.SPAWN_CLEAR, "%s a deck over the spawn ring at (%d, %d)" % [seed_text, dx, dz])
		var share := float(decks) / float(total)
		covered += share
		_expect(share > .15 and share < .6, "%s deck coverage %.0f%% is far from the 30-50%% target" % [seed_text, share * 100.0])
		# every patch wholly inside the sampled window has a way up
		var seen := {}
		for dz in range(-RADIUS + 2, RADIUS - 1):
			for dx in range(-RADIUS + 2, RADIUS - 1):
				var key := Vector2i(dx, dz)
				if seen.has(key) or generator.is_void_column(Vector3i(dx, 0, dz)) or not DeckPatches.is_deck(seed_text, dx, dz):
					continue
				var members := generator.deck_component(dx, dz)
				for member in members:
					seen[member] = true
				# a patch that reaches the window's edge or the void is judged where it is whole
				var whole := true
				for member in members:
					whole = whole and absi(member.x) < RADIUS - 1 and absi(member.y) < RADIUS - 1 and not generator.is_void_column(Vector3i(member.x, 0, member.y))
				if not whole or members.size() >= StreamedRouteGenerator.DECK_PATCH_CAP:
					continue
				patches += 1
				var has_well := false
				for member in members:
					var well := generator.stairwell_between(member.x, member.y, StreamedRouteGenerator.MEZZANINE_LEVEL)
					if well.is_empty():
						continue
					has_well = true
					wells += 1
					var landing: Vector2i = well["landing"]
					_expect(int(generator.chunk(Vector3i(member.x, 0, member.y))["grid"][landing.y][landing.x]) == 0
						and int(generator.chunk(Vector3i(member.x, 1, member.y))["grid"][landing.y][landing.x]) == 0,
						"%s the well at %s lands in a wall" % [seed_text, member])
				if not has_well:
					no_well.append("%s %s (%d chunks)" % [seed_text, members[0], members.size()])
	_expect(no_well.is_empty(), "%d of %d patches have no way up: %s" % [no_well.size(), patches, no_well.slice(0, 5)])
	if _failures == 0:
		print("  deck_patches  %.0f%% deck coverage over %d seeds; %d whole patches, %d wells, %d patches without one" % [
			100.0 * covered / SEEDS.size(), SEEDS.size(), patches, wells, no_well.size()])
	return _failures
