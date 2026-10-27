extends RefCounted

## Every relay and pickup has a real path (StreamedHunterNavigation over the real props) from its chunk's main hall: the
## playtest bots found relays at (8,-4) and (-32,72) on ALPHA and a stuck spot near (63,-132). Seeds include ALPHA.
##
##   godot --headless --path . res://scenes/validate.tscn -- pickup_reach

const SEEDS := ["ALPHA", "REAL-B", "PICKUPS"]
const RADIUS := 4

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		if _failures < 20:
			print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var checked := 0
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for cz in range(-RADIUS, RADIUS + 1):
			for cx in range(-RADIUS, RADIUS + 1):
				var coord := Vector3i(cx, 0, cz)
				if not generator.is_chunk_allowed(coord):
					continue
				var navigation := StreamedHunterNavigation.new(generator, 0)
				var coords := []
				for dz in range(-1, 2):
					for dx in range(-1, 2):
						coords.append(Vector3i(cx + dx, 0, cz + dz))
				navigation.refresh(0, coords)
				var base := Vector2i(cx, cz) * StreamedRouteGenerator.CHUNK_SIZE
				var hall := _hall_cell(navigation, base)
				if hall.x == -999999:
					continue
				for pickup_value in generator.chunk(coord).get("pickups", []):
					var pickup: Dictionary = pickup_value
					var cell: Vector2i = base + (pickup["cell"] as Vector2i)
					checked += 1
					var path: Array = navigation.find_path(hall, cell)
					_expect(not path.is_empty(), "%s: %s %s at %s has no path from the hall %s" % [seed_text, pickup.get("kind", "?"), pickup.get("id", ""), cell, hall])
	_expect(checked > 100, "only %d pickups checked" % checked)
	if _failures == 0:
		print("  pickup_reach  %d relays/pickups on %d seeds, every one reachable from its chunk's hall on the real props" % [checked, SEEDS.size()])
	return _failures


## An open cell of the chunk's middle hall (row 22, any column), else none.
func _hall_cell(navigation: StreamedHunterNavigation, base: Vector2i) -> Vector2i:
	for x in range(2, StreamedRouteGenerator.CHUNK_SIZE - 2):
		for z in [22, 21, 23, 10, 34]:
			if navigation.can_occupy(base.x + x + .5, base.y + z + .5):
				return base + Vector2i(x, z)
	return Vector2i(-999999, 0)
