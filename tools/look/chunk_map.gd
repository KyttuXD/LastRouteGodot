extends SceneTree

## Top-down picture of generated chunks (no rendering needed):
##   godot --headless --path . -s tools/look/chunk_map.gd -- OUT.png [SEED] [CX0 CZ0 CX1 CZ1]
## walls dark, open cells light, room interiors tinted by room, doors and arches marked.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/chunk_map.png"
	var seed_text := args[1] if args.size() > 1 else "MAP-CHECK"
	var c0 := Vector2i(int(args[2]) if args.size() > 2 else -1, int(args[3]) if args.size() > 3 else -1)
	var c1 := Vector2i(int(args[4]) if args.size() > 4 else 1, int(args[5]) if args.size() > 5 else 1)
	var gen := StreamedRouteGenerator.new(seed_text)
	var cs := StreamedRouteGenerator.CHUNK_SIZE
	var scale := 4
	var width := (c1.x - c0.x + 1) * cs
	var height := (c1.y - c0.y + 1) * cs
	var image := Image.create(width * scale, height * scale, false, Image.FORMAT_RGB8)
	image.fill(Color(.05, .04, .06))
	var tints := [Color("a8c8e8"), Color("e8c8a8"), Color("c8e8a8"), Color("e8a8c8"), Color("c8a8e8"), Color("e8e8a8")]
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var coord := Vector3i(cx, 0, cz)
			if not gen.is_chunk_allowed(coord):
				continue
			var data: Dictionary = gen.chunk(coord)
			var grid: Array = data["grid"]
			var room_color := {}
			var index := 0
			for room in data.get("rooms", []):
				var rect: Rect2i = room["rect"]
				for z in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						room_color[Vector2i(x, z)] = tints[index % tints.size()]
				index += 1
			var doors := {}
			for prop in data.get("region_props", []):
				if prop.get("room_door", false):
					for cell in prop.get("doorway_cells", []):
						doors[cell] = Color("ff5050") if prop.get("arch", false) else Color("ffd040")
			for z in cs:
				for x in cs:
					var cell := Vector2i(x, z)
					var color := Color(.12, .1, .14)
					if int(grid[z][x]) == 0:
						color = room_color.get(cell, Color(.85, .85, .85))
					if doors.has(cell):
						color = doors[cell]
					var px := ((cx - c0.x) * cs + x) * scale
					var py := ((cz - c0.y) * cs + z) * scale
					for dy in scale:
						for dx in scale:
							image.set_pixel(px + dx, py + dy, color)
	image.save_png(out)
	print("saved ", out)
	quit()
