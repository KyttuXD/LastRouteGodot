extends Node

## Parity dump for the Rust port of the Infinite route (LastRoute Rust, src/world/route).
## Run as a scene, because --script mode registers no autoloads and the generator needs them (see validate.tscn):
##
##   godot --headless --path . res://tests/parity/dump.tscn -- ROOM_TEXT OUT_PATH [LEVELS] [RADIUS]
##
## ROOM_TEXT is the room seed text, "ROOM-<code>-<20 hex>". The world seed is the decimal run seed of that text,
## as the live Infinite route starts it (infinite_route_test.gd: str(RoomState.run_seed())), where
## run_seed = maxi(1, abs(int(text.hash()))) (room_state.gd run_seed()). LEVELS is a comma list (default "0,-1,-2,-3"),
## RADIUS the chunk radius around the origin (default 3).


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var room_text := args[0] if args.size() > 0 else "ROOM-DEMO-00000000000000000000"
	var out_path := args[1] if args.size() > 1 else "user://parity_dump.json"
	var levels: Array[int] = []
	for part in (args[2] if args.size() > 2 else "0,-1,-2,-3").split(","):
		levels.append(int(part))
	var radius := int(args[3]) if args.size() > 3 else 3

	var run_seed := maxi(1, absi(int(room_text.hash())))
	var world_seed := str(run_seed)
	var gen := StreamedRouteGenerator.new(world_seed)
	var chunks := []
	for level in levels:
		for x in range(-radius, radius + 1):
			for z in range(-radius, radius + 1):
				var coord := Vector3i(x, level, z)
				chunks.append({"coord": _plain(coord), "data": _plain(gen.chunk(coord))})
	var out := {"room_text": room_text, "world_seed": world_seed, "levels": levels, "radius": radius, "chunks": chunks}
	var file := FileAccess.open(out_path, FileAccess.WRITE)
	if file == null:
		push_error("cannot write %s" % out_path)
		get_tree().quit(1)
		return
	file.store_string(JSON.stringify(out, "\t"))
	print("parity dump: %d chunks for %s (world seed %s) -> %s" % [chunks.size(), room_text, world_seed, out_path])
	get_tree().quit(0)


## Turns Godot values into plain JSON-friendly data: Vector2i and Vector3i become arrays,
## Rect2i becomes [x, y, w, h], dictionary keys become strings, and typed arrays stay arrays.
func _plain(value: Variant) -> Variant:
	match typeof(value):
		TYPE_VECTOR2I:
			return [value.x, value.y]
		TYPE_VECTOR3I:
			return [value.x, value.y, value.z]
		TYPE_VECTOR2:
			return [value.x, value.y]
		TYPE_RECT2I:
			return [value.position.x, value.position.y, value.size.x, value.size.y]
		TYPE_DICTIONARY:
			var out := {}
			for key in value:
				out[str(_plain(key))] = _plain(value[key])
			return out
		TYPE_ARRAY:
			var arr := []
			for item in value:
				arr.append(_plain(item))
			return arr
		TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_FLOAT32_ARRAY:
			return Array(value)
		TYPE_OBJECT:
			return str(value)
		_:
			return value
