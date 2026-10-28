extends Node

## Prints CAP_AT strings (x,z,yaw,y) for the waterfall: the top (level -1, on the walkway looking up the spur at the lip)
## and the bottom (level -2, across the cistern looking at the fall), and for a cage pit (level -3).
##
##   godot --headless --path . res://tools/look/falls_spots.tscn -- SEED [falls|pit]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var seed_text := String(args[0]) if args.size() > 0 else "ENDLESS-ROUTE"
	var what := String(args[1]) if args.size() > 1 else "falls"
	var generator := StreamedRouteGenerator.new(seed_text)
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var spots: Array[String] = []
	if what == "ascii":
		var at := Vector2i(int(args[2]), int(args[3]))
		var falls := generator.sewer().falls_between(at.x, at.y)
		print("falls: ", falls)
		for level in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
			var grid: Array = generator.sewer().chunk(Vector3i(at.x, level, at.y))["grid"]
			print("level ", level)
			for z in size:
				var row := ""
				for x in size:
					row += str(int(grid[z][x]))
				print(row)
		get_tree().quit(0)
		return
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			if not spots.is_empty():
				break
			if what == "falls":
				var falls := generator.sewer().falls_between(cx, cz)
				if falls.is_empty():
					continue
				var qc: Vector2i = falls["center"]
				var north: bool = falls["north"]
				var spur_deck: Rect2i = falls["spur_deck"]
				var top_z := float(spur_deck.position.y) + (2.5 if north else .5)
				spots.append("%.1f,%.1f,%d,%.2f" % [cx * size + qc.x + .5, cz * size + top_z, 0 if north else 180,
					SewerRouteGenerator.LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05])
				var bottom_z := float(qc.y) - 4.5 if north else float(qc.y) + 4.5
				spots.append("%.1f,%.1f,%d,%.2f" % [cx * size + qc.x + .5, cz * size + bottom_z, 180 if north else 0,
					SewerRouteGenerator.LOWER_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05])
			else:
				var coord := Vector3i(cx, StreamedRouteGenerator.INFERNO_LEVEL, cz)
				for pit in InfernoCaverns.pits_in(generator.chunk(coord)):
					var span: Rect2i = pit["bridge"]
					var north: bool = pit["north"]
					# on the open side of the channel, looking across the bridge
					var z := float(span.end.y) + 4.5 if north else float(span.position.y) - 4.5
					spots.append("%.1f,%.1f,%d,%.2f" % [cx * size + span.position.x + 1.5, cz * size + z, 0 if north else 180,
						StreamedRouteGenerator.INFERNO_LEVEL * StreamedFacilityView3D.LEVEL_HEIGHT + .05])
					break
	print("CAP_AT=" + ";".join(spots))
	get_tree().quit(0)
