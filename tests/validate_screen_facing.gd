extends RefCounted

## "computers facing backwards". Every screen prop (computer, CRT console, terminal, monitor) with a seat within
## StreamedRouteGenerator.SCREEN_SEAT_REACH faces that seat: its forward (gameplay -Z, the side the model's screen is on)
## points at the nearest seat with dot > 0.7. All districts on level 0 and the upper levels the generator allows.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- screen_facing

const SEEDS := ["SCREEN-A", "SCREEN-B", "SCREEN-C"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var pairs := 0
	var wrong := []
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
					var props: Array = data.get("region_props", [])
					for screen_value in props:
						var screen: Dictionary = screen_value
						if not StreamedRouteGenerator.is_screen_type(String(screen.get("type", ""))):
							continue
						var at := StreamedRouteGenerator.prop_point(screen)
						var seat_at := Vector2.INF
						var best := StreamedRouteGenerator.SCREEN_SEAT_REACH
						for seat_value in props:
							var seat: Dictionary = seat_value
							if String(seat.get("room_id", "")) != String(screen.get("room_id", "")) \
									or PropModelCatalog.interaction_for(String(seat.get("type", ""))) != "sit":
								continue
							var d := at.distance_to(StreamedRouteGenerator.prop_point(seat))
							if d > .05 and d < best:
								best = d
								seat_at = StreamedRouteGenerator.prop_point(seat)
						if seat_at == Vector2.INF:
							continue
						pairs += 1
						regions[String(data.get("region", ""))] = true
						var yaw := float(screen.get("yaw", 0.0))
						var forward := Vector2(-sin(yaw), -cos(yaw))
						if forward.dot((seat_at - at).normalized()) <= .7:
							wrong.append("%s %s at %s" % [data.get("region", ""), screen.get("type", ""), at])
	_expect(pairs > 20, "only %d screen+seat pairs in the sample" % pairs)
	_expect(wrong.is_empty(), "%d screens face away from their seat: %s" % [wrong.size(), wrong.slice(0, 6)])
	if _failures == 0:
		print("  screen_facing  %d pairs in %s" % [pairs, regions.keys()])
	return _failures
