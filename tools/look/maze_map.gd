extends Node

## Top-down cell map of the level-0 chunks around the spawn: walls dark, halls light, rooms tinted, doors yellow, the
## chunk seams marked. Headless:  godot --headless --path . res://tools/look/maze_map.tscn -- <out dir> <tag> [seed] [radius]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://build/maze_map"
	var tag := args[1] if args.size() > 1 else "now"
	var seed_text := args[2] if args.size() > 2 else "MAZE-LOOK"
	var radius := int(args[3]) if args.size() > 3 else 2
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var generator := StreamedRouteGenerator.new(seed_text)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var px := 4
	var side := (radius * 2 + 1) * size
	var image := Image.create(side * px, side * px, false, Image.FORMAT_RGB8)
	image.fill(Color(.08, .08, .1))
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var coord := Vector3i(dx, 0, dz)
			if not generator.is_chunk_allowed(coord):
				continue
			var data := generator.chunk(coord)
			var grid: Array = data["grid"]
			var room_cells := {}
			for room in data.get("rooms", []):
				var rect: Rect2i = room["rect"]
				for z in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						room_cells[Vector2i(x, z)] = true
			var region := generator.region_for(coord)
			var tint := Color(.55, .75, .95) if region == "maze" else Color(.75, .7, .6)
			for z in size:
				for x in size:
					var colour := Color(.12, .12, .15)
					if int(grid[z][x]) == 0:
						colour = tint.darkened(.35) if room_cells.has(Vector2i(x, z)) else Color(.92, .92, .88)
					var at := Vector2i(((dx + radius) * size + x) * px, ((dz + radius) * size + z) * px)
					image.fill_rect(Rect2i(at, Vector2i(px, px)), colour)
			for room in data.get("rooms", []):
				var door = room.get("doorway")
				if door is Vector2i:
					var at := Vector2i(((dx + radius) * size + door.x) * px, ((dz + radius) * size + door.y) * px)
					image.fill_rect(Rect2i(at, Vector2i(px, px)), Color(1, .8, .1))
	var path := "%s/maze_%s_%s.png" % [ProjectSettings.globalize_path(out), seed_text, tag]
	image.save_png(path)
	print("MAZEMAP %s" % path)
	get_tree().quit()
