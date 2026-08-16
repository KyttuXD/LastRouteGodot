extends SceneTree

## One-off: bakes the two dedicated block textures used by
## facility_view_3d.gd's GridMap floor/wall boxes, cropped once from the
## shared environment kit sheet. See that file's _build_mesh_library() for
## why this replaced the old runtime UV-guessing heuristic.

func _init() -> void:
	var floor_img := Image.load_from_file("res://art/props-3d/environment/floor_tile_0.png")
	var floor_crop := floor_img.get_region(Rect2i(4, 14, 72, 24))
	floor_crop.save_png("res://art/props-3d/environment/floor_texture.png")

	var wall_img := Image.load_from_file("res://art/props-3d/environment/wall_block_0.png")
	var wall_crop := wall_img.get_region(Rect2i(165, 4, 85, 36))
	wall_crop.save_png("res://art/props-3d/environment/wall_texture.png")
	quit()
