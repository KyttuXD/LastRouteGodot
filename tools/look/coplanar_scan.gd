extends Node

## Loads the streamed route around the origin and prints every z-fighting (coplanar, overlapping, same-facing) pair.
##   godot --path . res://tools/look/coplanar_scan.tscn -- [SEED] [RADIUS_CHUNKS]
## Output: a summary by kind pair, then the 30 worst pairs with world positions.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := args[0] if args.size() > 0 else "COPLANAR-SCAN"
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = seed_text
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(route)
	await get_tree().process_frame
	for _i in 240:
		await get_tree().physics_frame
	var scan := CoplanarScan.new()
	scan.ignore_siblings = OS.get_environment("SIBLINGS") == ""
	var pairs := scan.scan(route.get_node("World/StreamedFacility"))
	print("COPLANAR triangles=%d axis-aligned-faces=%d pairs=%d" % [scan.triangles_seen, scan.faces.size(), pairs.size()])
	var summary := {}
	for pair in pairs:
		var key := "%s <-> %s" % [CoplanarScan.kind_of(String(pair["a"])), CoplanarScan.kind_of(String(pair["b"]))]
		summary[key] = int(summary.get(key, 0)) + 1
	var keys := summary.keys()
	keys.sort_custom(func(x, y) -> bool: return summary[x] > summary[y])
	for key in keys:
		print("COPLANAR   %5d  %s" % [summary[key], key])
	# the interesting ones: anything involving the room surface or a non-decor prop/door
	var interesting := pairs.filter(func(pair: Dictionary) -> bool:
		var ka := CoplanarScan.kind_of(String(pair["a"]))
		var kb := CoplanarScan.kind_of(String(pair["b"]))
		return not (ka.begins_with("decor:") and kb.begins_with("decor:")))
	var shown := {}
	for pair in interesting:
		var key := "%s <-> %s" % [CoplanarScan.kind_of(String(pair["a"])), CoplanarScan.kind_of(String(pair["b"]))]
		shown[key] = int(shown.get(key, 0)) + 1
		if int(shown[key]) <= 2:
			print("COPLANAR* %s  axis %d plane %.3f at %s area %.4f" % [key, pair["axis"], pair["plane"], pair["at"], pair["overlap"]])
	for pair in pairs.slice(0, 0):
		print("COPLANAR pair %.3f m2 axis %d plane %.3f at %s\n    %s\n    %s" % [pair["overlap"], pair["axis"], pair["plane"], pair["at"], pair["a"], pair["b"]])
	get_tree().quit()
