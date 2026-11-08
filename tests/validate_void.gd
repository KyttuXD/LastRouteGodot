extends RefCounted

## the Mezzanine void (VoidRegion) is removed from play ("too broken"). This suite now guards the
## removal over many seeds: VoidRegion is off, no column is inside it, no chunk of any level -3..+1 is a void chunk or
## reads as the "mezzanine" region, nothing carries a mezzanine_grid, and the void's stair tower is gone (its column is
## an ordinary maze/sewer/Inferno column with ordinary stairwells only).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- void

const SEEDS := ["VOID-A", "VOID-B", "ENDLESS-ROUTE", "SOAKTEST", "KYTTU-LAB", "PICKUPS", "BIOME-A", "REAL-B"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_expect(not VoidRegion.ENABLED, "VoidRegion is still enabled (removed)")
	var checked := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		# the old footprint (pure seed maths) is where the shaft used to stand: every column of it is ordinary now
		var rect := VoidRegion.footprint(seed_text)
		for z in range(rect.position.y - 1, rect.end.y + 1):
			for x in range(rect.position.x - 1, rect.end.x + 1):
				_expect(not VoidRegion.contains(seed_text, x, z) and not generator.is_void_column(Vector3i(x, 0, z)),
					"%s column (%d, %d) is still inside the void" % [seed_text, x, z])
				for level in range(VoidRegion.BOTTOM_LEVEL, VoidRegion.TOP_LEVEL + 1):
					var coord := Vector3i(x, level, z)
					_expect(not VoidRegion.is_void_chunk(seed_text, coord), "%s %s is a void chunk" % [seed_text, coord])
					if not generator.is_chunk_allowed(coord):
						continue
					checked += 1
					var data: Dictionary = generator.chunk(coord)
					_expect(not data.has("mezzanine_grid") and String(data.get("region", "")) != "mezzanine"
						and generator.region_for(coord) != "mezzanine", "%s %s is still built as the void/mezzanine" % [seed_text, coord])
					_expect(String(data.get("ambience_level", "")) != "void", "%s %s still plays the void's ambience" % [seed_text, coord])
		var tower := VoidRegion.tower_chunk(seed_text)
		for upper in range(VoidRegion.BOTTOM_LEVEL + 1, VoidRegion.TOP_LEVEL + 1):
			var well := generator.stairwell_between(tower.x, tower.y, upper)
			_expect(upper == 0 or well.is_empty(), "%s the void tower still has a stairwell %d -> %d" % [seed_text, upper, upper - 1])
	_expect(checked > 0, "no chunks sampled where the void used to be")
	if _failures == 0:
		print("  void  removed: %d chunks over %d seeds where the shaft stood are ordinary; no void chunk, mezzanine region or tower" % [checked, SEEDS.size()])
	return _failures
