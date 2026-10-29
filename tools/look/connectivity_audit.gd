extends SceneTree

## Floor connectivity across chunk seams: from the centre of each chunk, a flood over a 5x5 chunk window must reach every open
## cell of the centre chunk (rooms behind doors, great halls, halls trimmed by a great hall...). Prints the unreachable cells.
##   godot --headless --path . -s tools/look/connectivity_audit.gd -- [SEED] [RADIUS]

func _init() -> void:
	var seed_text := "REAL-B"
	var radius := 7
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed_text = args[0]
	if args.size() > 1:
		radius = int(args[1])
	var generator := StreamedRouteGenerator.new(seed_text)
	var bad := 0
	var checked := 0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := Vector3i(dx, 0, dz)
			if not generator.is_chunk_allowed(coord):
				continue
			var cells := {}
			for oz in range(-2, 3):
				for ox in range(-2, 3):
					var c := Vector3i(dx + ox, 0, dz + oz)
					if not generator.is_chunk_allowed(c):
						continue
					var grid: Array = generator.chunk(c)["grid"]
					for z in grid.size():
						for x in (grid[z] as Array).size():
							if int(grid[z][x]) == 0:
								cells[Vector2i(c.x * 45 + x, c.z * 45 + z)] = true
			var start := Vector2i(dx * 45 + 22, dz * 45 + 10)
			if not cells.has(start):
				continue
			var seen := {start: true}
			var frontier := [start]
			while not frontier.is_empty():
				var cur: Vector2i = frontier.pop_back()
				for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cur + d
					if cells.has(n) and not seen.has(n):
						seen[n] = true
						frontier.append(n)
			var missing := 0
			var sample := Vector2i.ZERO
			var grid_c: Array = generator.chunk(coord)["grid"]
			for z in grid_c.size():
				for x in (grid_c[z] as Array).size():
					var cell := Vector2i(dx * 45 + x, dz * 45 + z)
					if int(grid_c[z][x]) == 0 and not seen.has(cell):
						missing += 1
						sample = Vector2i(x, z)
			checked += 1
			if missing > 0:
				bad += 1
				print("UNREACHABLE chunk %s %s: %d open cells cut off (e.g. local %s) plan %s" % [coord, generator.region_for(coord), missing, sample, generator.large_plan(coord)])
	print("connectivity: %d chunks checked, %d with cut-off floor" % [checked, bad])
	quit()
