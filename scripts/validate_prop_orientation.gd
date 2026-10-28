extends RefCounted

## KT: "check other connected props and make sure they're rotated correctly or decently". Every pair in
## StreamedRouteGenerator.ORIENT_PAIRS (seats to tables and desks, sofas to the TV, benches to pianos, screens to seats and
## beds) faces its anchor with dot > 0.7, and every wall-backed prop that sits against a wall (recipe wall-backed, or a
## one-cell prop whose cell touches a wall) has its back within 15 cm of the wall. All districts, levels 0-5.
##
##   godot --headless --path . res://scenes/validate.tscn -- prop_orientation

const SEEDS := ["ORIENT-A", "ORIENT-B", "ORIENT-C"]

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var pairs := 0
	var backed := 0
	var bad_pairs := []
	var bad_walls := []
	var regions := {}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for level in [0, 1, 2, 3, 4, 5]:
			for dz in range(-5, 6):
				for dx in range(-5, 6):
					var coord := Vector3i(dx, level, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var data := generator.chunk(coord)
					var grid: Array = data.get("grid", [])
					var props: Array = data.get("region_props", [])
					for prop_value in props:
						var prop: Dictionary = prop_value
						var type := String(prop.get("type", ""))
						if String(prop.get("room_template", "")).is_empty():
							continue
						regions[String(data.get("region", ""))] = true
						if RoomCatalog.is_wall_backed(type) and bool(prop.get("solid", true)) and not bool(prop.get("wall_mounted", false)):
							var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
							var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
							var touches := false
							for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
								var w: Vector2i = cell + dir
								if w.y >= 0 and w.y < grid.size() and w.x >= 0 and w.x < (grid[w.y] as Array).size() and int(grid[w.y][w.x]) != 0:
									touches = true
							var expected := (prop.get("backing_wall", Vector2i.ZERO) as Vector2i) != Vector2i.ZERO \
								or (touches and size.z <= .95 and size.x <= .95)
							if expected:
								backed += 1
								if not StreamedRouteGenerator.wall_behind(prop, grid):
									bad_walls.append("%s %s at %s" % [data.get("region", ""), type, StreamedRouteGenerator.prop_point(prop)])
						for rule_value in StreamedRouteGenerator.ORIENT_PAIRS:
							var rule: Dictionary = rule_value
							if not StreamedRouteGenerator._type_has(type, rule["child"]) or RoomCatalog.is_wall_backed(type) \
									or StreamedRouteGenerator._type_has(type, StreamedRouteGenerator.ORIENT_EXCLUDE):
								continue
							var anchor := StreamedRouteGenerator.nearest_anchor(prop, props, rule["anchor"], float(rule["reach"]))
							if anchor.is_empty():
								continue
							pairs += 1
							var yaw := float(prop.get("yaw", 0.0))
							var toward := (StreamedRouteGenerator.prop_point(anchor) - StreamedRouteGenerator.prop_point(prop)).normalized()
							if Vector2(-sin(yaw), -cos(yaw)).dot(toward) <= .7:
								bad_pairs.append("%s %s -> %s" % [data.get("region", ""), type, anchor.get("type", "")])
							break
	metrics = {"pairs": pairs, "wall_backed": backed, "regions": regions.keys()}
	_expect(pairs > 100 and backed > 100, "too few pairs (%d) or wall-backed props (%d) sampled" % [pairs, backed])
	_expect(bad_pairs.is_empty(), "%d props do not face their anchor: %s" % [bad_pairs.size(), bad_pairs.slice(0, 8)])
	_expect(bad_walls.is_empty(), "%d wall-backed props have no wall behind them: %s" % [bad_walls.size(), bad_walls.slice(0, 8)])
	if _failures == 0:
		print("  prop_orientation  %s" % [metrics])
	return _failures
