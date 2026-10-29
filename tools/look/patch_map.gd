extends Node

## Top-down chunk map of the +1 deck patches and the Mezzanine void for a seed (and their coverage): one pixel block per
## chunk. Headless:  godot --headless --path . res://tools/look/patch_map.tscn -- <out dir> <seed> [radius]
func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "res://build/patches"
	var seeds: PackedStringArray = (args[1] if args.size() > 1 else "SOAKTEST,ENDLESS-ROUTE,KYTTU-LAB,VOID-A").split(",")
	var radius := int(args[2]) if args.size() > 2 else 12
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	for seed_text in seeds:
		var cell := 14
		var side := (radius * 2 + 1)
		var image := Image.create(side * cell, side * cell, false, Image.FORMAT_RGB8)
		image.fill(Color(.12, .12, .16))
		var decks := 0
		var total := 0
		var void_rect := VoidRegion.footprint(seed_text)
		for dz in range(-radius, radius + 1):
			for dx in range(-radius, radius + 1):
				total += 1
				var colour := Color(.16, .17, .22)
				if void_rect.has_point(Vector2i(dx, dz)):
					colour = Color(.8, .15, .15)
				elif DeckPatches.is_deck(seed_text, dx, dz):
					colour = Color(.3, .75, .5)
					decks += 1
				if dx == 0 and dz == 0:
					colour = Color(1, 1, 1)
				image.fill_rect(Rect2i((dx + radius) * cell + 1, (dz + radius) * cell + 1, cell - 2, cell - 2), colour)
		var path := "%s/patches_%s.png" % [ProjectSettings.globalize_path(out), seed_text]
		image.save_png(path)
		print("PATCHMAP %s decks %d/%d = %.0f%% (void red, spawn white) -> %s" % [seed_text, decks, total, 100.0 * decks / total, path])
	get_tree().quit()
