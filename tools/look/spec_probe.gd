extends SceneTree

func _init() -> void:
	process_frame.connect(_probe, CONNECT_ONE_SHOT)


func _probe() -> void:
	var gen = load("res://src/game/streamed_route_generator.gd")
	var rng = load("res://src/game/seeded_random.gd").new("x")
	for ds in [7, 8, 9]:
		var specs: Array = gen._room_template_specs("prison_cafeteria", "prison", 9, ds, 1, rng)
		var line := "depth_span %d: " % ds
		for s in specs:
			if s.get("type") == "prisonCafeteriaTable":
				line += "table@%s " % s["depth"]
		print(line)
	quit()
