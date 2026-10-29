extends Node

## Prop orientation before/after (docs/PROP_ORIENTATION.md): the first furnished room of each listed district on a seeded
## route, from high in one corner looking down across the room, so facing pairs and wall-backed props read. Windowed:
##   mini-run.sh <dir> <lane> --scene res://tools/look/orientation_rooms.tscn -- /tmp/out tag

const REGIONS := ["maze", "lab", "hospital", "hotel", "mansion", "prison", "apartment", "gothic"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/orient_caps"
	var tag := args[1] if args.size() > 1 else "after"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "ORIENT-LOOK"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	add_child(route)
	for _i in 30:
		await get_tree().process_frame
	var generator: StreamedRouteGenerator = route.facility.generator
	var found := {}
	for r in range(0, 9):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var coord := Vector3i(dx, 0, dz)
				var region := generator.region_for(coord)
				if not generator.is_chunk_allowed(coord) or found.has(region) or not REGIONS.has(region):
					continue
				var data := generator.chunk(coord)
				var counts := {}
				for prop in data.get("region_props", []):
					var room_id := String((prop as Dictionary).get("room_id", ""))
					if not String((prop as Dictionary).get("room_template", "")).is_empty():
						counts[room_id] = int(counts.get(room_id, 0)) + 1
				for room in data["rooms"]:
					var rect: Rect2i = room["rect"]
					if int(counts.get(String(room["id"]), 0)) >= 6 and mini(rect.size.x, rect.size.y) >= 7:
						found[region] = {"coord": coord, "rect": rect}
						break
	var camera := Camera3D.new()
	camera.fov = 70.0
	add_child(camera)
	for region in REGIONS:
		if not found.has(region):
			print("ORIENTCAP no %s" % region)
			continue
		var coord: Vector3i = found[region]["coord"]
		var rect: Rect2i = found[region]["rect"]
		var origin := Vector2(coord.x * StreamedRouteGenerator.CHUNK_SIZE, coord.z * StreamedRouteGenerator.CHUNK_SIZE)
		var centre := origin + Vector2(rect.position) + Vector2(rect.size) * .5
		var corner := origin + Vector2(rect.position) + Vector2(.8, .8)
		route._admin_teleport_to(Vector3(centre.x, 0.1, centre.y))
		for _i in 120:
			await get_tree().process_frame
		camera.current = true
		camera.global_position = Vector3(corner.x, 3.3, corner.y)
		camera.look_at(Vector3(centre.x + rect.size.x * .15, 0.0, centre.y + rect.size.y * .15), Vector3.UP)
		route.player.flashlight_enabled = true
		for _i in 10:
			await get_tree().process_frame
		var image := get_viewport().get_texture().get_image()
		if image != null:
			image.save_png("%s/%s_%s.png" % [out, region, tag])
		print("ORIENTCAP %s %s" % [tag, region])
		camera.current = false
	print("ORIENTCAP done")
	get_tree().quit()
