extends SceneTree

## Top-down map of the City master layout (no rendering needed):
##   godot --headless --path . -s tools/look/city_map.gd -- OUT.png [SEED] [SCALE]
## Prints the zone counts as well.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/city_map.png"
	var seed_text := args[1] if args.size() > 1 else "CITY-MAP"
	var scale := int(args[2]) if args.size() > 2 else 5
	var layout := CityLayout.build(seed_text)
	var image := layout.to_image(scale)
	# Doors and decor on top of the tile colours.
	for building in layout.buildings:
		for door_value in building["doors"]:
			var door: Vector2i = door_value
			image.fill_rect(Rect2i(door.x * scale, door.y * scale, scale, scale), Color("ffe066"))
	for cell_value in layout.decor.keys():
		var cell: Vector2i = cell_value
		var type := String(layout.decor[cell]["type"])
		var color := Color("e8a33a") if type == "lamp" else Color("e06fa0") if type in ["tree", "cypress"] else Color("c9c9d9")
		image.fill_rect(Rect2i(cell.x * scale + scale / 4, cell.y * scale + scale / 4, maxi(1, scale / 2), maxi(1, scale / 2)), color)
	for shelter in layout.shelters:
		var center: Vector2i = shelter["center"]
		image.fill_rect(Rect2i(center.x * scale - 1, center.y * scale - 1, 3, 3), Color("00ffff"))
	var error := image.save_png(out)
	var counts := {}
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			var name: String = CityLayout.KIND_NAMES[layout.kind_at(gx, gz)]
			counts[name] = int(counts.get(name, 0)) + 1
	print("saved %s (%d)  buildings %d  shelters %d  decor %d" % [out, error, layout.buildings.size(),
		layout.shelters.size(), layout.decor.size()])
	print(counts)
	quit()
