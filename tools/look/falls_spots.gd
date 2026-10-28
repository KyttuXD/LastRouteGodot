extends Node

## Prints CAP_AT strings (x,z,yaw,y) for the waterfall: the top (level -1, on the walkway looking up the spur at the lip)
## and the bottom (level -2, across the cistern looking at the fall), and for a cage pit (level -3).
##
##   godot --headless --path . res://tools/look/falls_spots.tscn -- SEED [falls|pit]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := String(args[0]) if args.size() > 0 else "ENDLESS-ROUTE"
	var what := String(args[1]) if args.size() > 1 else "falls"
	var generator := StreamedRouteGenerator.new(seed_text)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var spots: Array[String] = []
	if what == "time":
		for level in [0, -1, -2, -3]:
			var t0 := Time.get_ticks_usec()
			for cz in range(10, 14):
				for cx in range(10, 14):
					generator.chunk(Vector3i(cx, level, cz))
			print("level ", level, ": ", (Time.get_ticks_usec() - t0) / 16000.0, " ms per chunk")
		var t1 := Time.get_ticks_usec()
		var tun_total := 0.0
		var plan_total := 0.0
		for cz in range(10, 14):
			for cx in range(10, 14):
				var at := Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)
				var g := generator._solid_grid()
				var edges := {"west": generator.edge_openings(at, Vector2i(-1, 0)), "east": generator.edge_openings(at, Vector2i(1, 0)), "north": generator.edge_openings(at, Vector2i(0, -1)), "south": generator.edge_openings(at, Vector2i(0, 1))}
				var tunnels: Array = []
				var a := Time.get_ticks_usec()
				var chambers := InfernoCaverns.carve(generator.world_seed, at, g, edges, [], false, {}, tunnels)
				tun_total += Time.get_ticks_usec() - a
				var b := Time.get_ticks_usec()
				SealPlanner.plan_cave(generator.world_seed, at, g, chambers, tunnels)
				plan_total += Time.get_ticks_usec() - b
		print("carve ", tun_total / 16000.0, " ms, plan ", plan_total / 16000.0, " ms per chunk")
		get_tree().quit(0)
		return
	if what == "cave":
		var at := Vector3i(int(args[2]), StreamedRouteGenerator.INFERNO_LEVEL, int(args[3]))
		var data := generator.chunk(at)
		var grid: Array = data["grid"]
		var covered := {}
		for z in range(1, size - 1):
			for x in range(1, size - 1):
				if InfernoCaverns.clearance(grid, Vector2i(x, z), 1) >= 1:
					for dz in range(-1, 2):
						for dx in range(-1, 2):
							covered[Vector2i(x + dx, z + dz)] = true
		for z in size:
			var row := ""
			for x in size:
				var lava_here := false
				for pit in InfernoCaverns.pits_in(data):
					if (pit["lava"] as Array).has(Vector2i(x, z)):
						lava_here = true
				row += "L" if lava_here else ("#" if int(grid[z][x]) != 0 else ("x" if not covered.has(Vector2i(x, z)) else "."))
			print(row)
		print("ramps ", data.get("ramps", []).size(), " pits ", InfernoCaverns.pits_in(data).size())
		get_tree().quit(0)
		return
	if what == "ascii":
		var at := Vector2i(int(args[2]), int(args[3]))
		var falls := generator.sewer().falls_between(at.x, at.y)
		print("falls: ", falls)
		for level in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
			var grid: Array = generator.sewer().chunk(Vector3i(at.x, level, at.y))["grid"]
			print("level ", level)
			for z in size:
				var row := ""
				for x in size:
					row += str(int(grid[z][x]))
				print(row)
		get_tree().quit(0)
		return
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			if not spots.is_empty():
				break
			if what == "falls":
				var falls := generator.sewer().falls_between(cx, cz)
				if falls.is_empty():
					continue
				var qc: Vector2i = falls["center"]
				var north: bool = falls["north"]
				var spur_deck: Rect2i = falls["spur_deck"]
				var top_z := float(spur_deck.position.y) + (2.5 if north else .5)
				spots.append("%.1f,%.1f,%d,%.2f" % [cx * size + qc.x + .5, cz * size + top_z, 0 if north else 180,
					SewerRouteGenerator.LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05])
				var bottom_z := float(qc.y) - 4.5 if north else float(qc.y) + 4.5
				spots.append("%.1f,%.1f,%d,%.2f" % [cx * size + qc.x + .5, cz * size + bottom_z, 180 if north else 0,
					SewerRouteGenerator.LOWER_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05])
			else:
				var coord := Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)
				for pit in InfernoCaverns.pits_in(generator.chunk(coord)):
					var span: Rect2i = pit["bridge"]
					var north: bool = pit["north"]
					# on the open side of the channel, looking across the bridge
					var z := float(span.end.y) + 4.5 if north else float(span.position.y) - 4.5
					spots.append("%.1f,%.1f,%d,%.2f" % [cx * size + span.position.x + 1.5, cz * size + z, 0 if north else 180,
						StreamedRouteGenerator.INFERNO_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05])
					break
	print("CAP_AT=" + ";".join(spots))
	get_tree().quit(0)
