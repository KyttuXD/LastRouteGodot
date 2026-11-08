extends Node

## Renders the HUD minimap and full map with co-op teammates (same floor, far off the map, another floor, downed) over a streamed
## floor and saves captures/minimap_teammates.png.
##   godot --path . res://dev/look/minimap_teammates_capture.tscn

func _ready() -> void:
	var root := get_tree().root
	root.size = Vector2i(960, 540)
	var world := StreamedRouteGenerator.new("TEAMMATES")
	var chunks := {}
	for z in range(-1, 2):
		for x in range(-1, 2):
			chunks[Vector3i(x, 0, z)] = world.chunk(Vector3i(x, 0, z))
	var hud := (load("res://game/hud/hud.tscn") as PackedScene).instantiate() as HUD
	add_child(hud)
	await get_tree().process_frame
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var centre := Vector2(size * .5, size * .5)
	var marks := [
		{"at": centre + Vector2(7, 3), "level": 0, "name": "Ana", "facing": Vector2.RIGHT, "colour": Color("63d9f1")},
		{"at": centre + Vector2(-8, -6), "level": 0, "name": "Bo", "facing": Vector2.UP, "colour": Color("f1a363")},
		{"at": centre + Vector2(400, 0), "level": 0, "name": "Cy", "facing": Vector2.LEFT, "colour": Color("a3f163")},
		{"at": centre + Vector2(3, 9), "level": -1, "name": "Di", "other_floor": true, "colour": Color("f163d9")},
		{"at": centre + Vector2(-5, 8), "level": 1, "name": "Ed", "other_floor": true, "colour": Color("f1e663")},
		{"at": centre + Vector2(10, -9), "level": 0, "name": "Fay", "spectating": true, "colour": Color("63d9f1")},
	]
	hud.update_streamed_minimap(chunks, 0, size, centre, Vector2.DOWN, [], marks)
	hud.update_streamed_map(chunks, 0, size, centre, Vector2.DOWN, [], marks)
	for _i in 12:
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://captures"))
	root.get_texture().get_image().save_png("res://captures/minimap_teammates.png")
	hud.set_map_open(true)
	for _i in 12:
		await get_tree().process_frame
	root.get_texture().get_image().save_png("res://captures/minimap_teammates_full_map.png")
	print("saved captures/minimap_teammates*.png")
	get_tree().quit()
