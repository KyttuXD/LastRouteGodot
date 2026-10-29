extends Node

## Mansion luxury before/after (docs/MANSION_LUXURY.md): the first mansion bedroom, drawing room, dining room and luxury
## bathroom of a seeded route, from a back corner, with the region finishes off (before) and on (after). Windowed, so
## run it on the mini:
##   mini-run.sh <dir> props-lane --scene res://tools/look/mansion_rooms.tscn -- /tmp/mansion_caps before
##   mini-run.sh <dir> props-lane --scene res://tools/look/mansion_rooms.tscn -- /tmp/mansion_caps after
## (one pass per process: built chunks are cached for the run)

const ROOM_TYPES := ["bedroom", "drawing_room", "dining_room", "luxury_bathroom"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out := args[0] if args.size() > 0 else "/tmp/mansion_caps"
	DirAccess.make_dir_recursive_absolute(out)
	get_window().size = Vector2i(1280, 720)
	for pass_name in [args[1] if args.size() > 1 else "after"]:
		PropModelCatalog.use_region_finishes = pass_name == "after"
		RoomState.create_local(RoomState.Mode.DEFAULT)
		RoomState.seed_text = "MANSION-LOOK"
		var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
		add_child(route)
		for _i in 30:
			await get_tree().process_frame
		var player: PlayerController3D = route.player
		var generator: StreamedRouteGenerator = route.facility.generator
		var found := {}
		for r in range(0, 8):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, 0, dz)
					if not generator.is_chunk_allowed(coord) or generator.region_for(coord) != "mansion":
						continue
					for room in generator.chunk(coord)["rooms"]:
						var type := String(room.get("room_type", ""))
						if type in ROOM_TYPES and not found.has(type) and (room["rect"] as Rect2i).size.x >= 7:
							found[type] = {"coord": coord, "rect": room["rect"]}
		for type in ROOM_TYPES:
			if not found.has(type):
				print("MANSIONCAP no %s" % type)
				continue
			var coord: Vector3i = found[type]["coord"]
			var rect: Rect2i = found[type]["rect"]
			var origin := Vector2(coord.x * StreamedRouteGenerator.CHUNK_SIZE, coord.z * StreamedRouteGenerator.CHUNK_SIZE)
			# stand a third of the way along the long axis and look down it at the far end
			var along := Vector2(1, 0) if rect.size.x >= rect.size.y else Vector2(0, 1)
			var mid := origin + Vector2(rect.position) + Vector2(rect.size) * .5
			var half := (Vector2(rect.size) * .5).dot(along)
			var corner := mid - along * (half - 1.6)
			var centre := mid + along * half
			route._admin_teleport_to(Vector3(corner.x, 0.1, corner.y))
			for _i in 90:
				await get_tree().process_frame
			route._admin_teleport_to(Vector3(corner.x, 0.1, corner.y))
			for _i in 10:
				await get_tree().process_frame
			print("MANSIONCAP player at %s" % player.global_position)
			var look := (centre - corner).normalized()
			player._yaw = atan2(-look.x, -look.y)
			player.rotation.y = player._yaw
			player._pitch = deg_to_rad(-14.0)
			player.first_person_pivot.rotation.x = player._pitch
			player.flashlight_enabled = true
			for _i in 20:
				await get_tree().process_frame
			var image := get_viewport().get_texture().get_image()
			if image != null:
				image.save_png("%s/%s_%s.png" % [out, type, pass_name])
			print("MANSIONCAP %s %s at %s" % [pass_name, type, coord])
		route.queue_free()
		for _i in 5:
			await get_tree().process_frame
	PropModelCatalog.use_region_finishes = true
	print("MANSIONCAP done")
	get_tree().quit()
