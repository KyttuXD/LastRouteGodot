extends Node

## Counts the dressing the look module builds for a block of chunks: fixtures,
## windows, lamps (and how many of those get a real light), per chunk and per
## room. Headless:  godot --headless --path . res://dev/look/decor_stats.tscn

func _ready() -> void:
	var generator := StreamedRouteGenerator.new("DECOR-STATS")
	var chunks := 0
	var totals := {}
	var lamps := 0
	var rooms := 0
	var room_lamp_max := 0
	var window_rooms := 0
	for cz in range(-3, 4):
		for cx in range(-3, 4):
			var data := generator.chunk(Vector3i(cx, 0, cz))
			var root := Node3D.new()
			root.position = Vector3(cx * 45, 0, cz * 45)
			var room_map: Dictionary = StreamedFacilityView3D._room_type_map(data)
			var decor := RefDecor.new(root, data, room_map, RefLook.chunk_heights(data),
				RefLook.corridor_height(String(data.get("region", "maze")), Vector3i(cx, 0, cz)))
			while not decor.step():
				pass
			chunks += 1
			lamps += decor.lamps.size()
			for child in root.get_children():
				var inst := child as MultiMeshInstance3D
				if inst != null:
					totals[inst.name] = int(totals.get(inst.name, 0)) + inst.multimesh.instance_count
			rooms += (data["rooms"] as Array).size()
			root.free()
	var keys := totals.keys()
	keys.sort()
	print("DECOR chunks=%d rooms=%d lamps(real-light candidates)=%d" % [chunks, rooms, lamps])
	for key in keys:
		print("DECOR %-18s %6d  (%.1f per chunk)" % [key, totals[key], float(totals[key]) / chunks])
	get_tree().quit()
