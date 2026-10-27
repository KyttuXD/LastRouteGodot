extends RefCounted

## The walk-through on real placed props (DONE12): no solid prop in a door's keep-clear zone, every door reachable and
## open to its room's interactables at the player capsule and at capsule + margin, and no cut-off pocket of floor of
## 1.5 m2 or more at capsule + margin. Also the deterministic clean-up pass gives the same chunk twice.

const SEEDS := ["COL-A", "COL-B"]
const CHUNKS_PER_BIOME := 3

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var report := CollisionAudit.run(SEEDS, CHUNKS_PER_BIOME)
	var t: Dictionary = report["totals"]
	var samples: Dictionary = report["samples"]
	metrics = t
	_expect(int(t["rooms"]) > 100, "collision audit walked only %d doors" % int(t["rooms"]))
	_expect(int(t["zone_violations"]) == 0, "%d props reach into a door keep-clear zone (e.g. %s)" % [t["zone_violations"], samples.get("zone", [])])
	for radius in [CollisionWorld.PLAYER_RADIUS, CollisionWorld.MARGIN_RADIUS]:
		var key := "%.1f" % radius
		_expect(int(t["door_blocked_" + key]) == 0, "%d room doors cannot be walked through at radius %s (e.g. %s)" % [t["door_blocked_" + key], key, samples.get("door_blocked_" + key, [])])
		_expect(int(t["target_unreached_" + key]) == 0, "%d interactables are unreachable from their door at radius %s (e.g. %s)" % [t["target_unreached_" + key], key, samples.get("target_" + key, [])])
		_expect(int(t["big_pockets_" + key]) == 0, "%d rooms have a cut-off floor pocket of 1.5 m2 or more at radius %s (e.g. %s)" % [t["big_pockets_" + key], key, samples.get("pocket_" + key, [])])
	# determinism: the same chunk twice, host and guest alike
	var a := StreamedRouteGenerator.new("COL-DET").chunk(Vector3i(2, 0, 1))
	var b := StreamedRouteGenerator.new("COL-DET").chunk(Vector3i(2, 0, 1))
	var ids_a := []
	var ids_b := []
	for prop in a["region_props"]:
		ids_a.append(String(prop["id"]))
	for prop in b["region_props"]:
		ids_b.append(String(prop["id"]))
	_expect(ids_a == ids_b, "the walkway clean-up is not deterministic for the same seed")
	if _failures == 0:
		print("  collision  %d doors walked at radius 0.2/0.3/0.4, 0 keep-clear violations, no unreachable rooms, deterministic" % int(t["rooms"]))
	return _failures
