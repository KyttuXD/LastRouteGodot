extends RefCounted

## Every mode's map is its own themed layout (NightWatchMapRegistry): no two modes share a layout signature, no mode shares more than SHARED_ROOM_IDS_MAX room ids with Classic,
## every provided layout is connected (every room reachable from the entrances along its edges) with sensible sizes, and no mode's world scene extends NightWatchBuilding (Classic's
## shell). Modes whose map is not provided yet are listed (planned); set REQUIRE_ALL when every lane has delivered. A single-space mode (Bedtime, Salvage Run) is exempt.

const REQUIRE_ALL := false

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var classic := NightWatchMapRegistry.classic_layout()
	var classic_sig := NightWatchMapRegistry.signature(classic)
	_expect(classic_sig != 0 and (classic["rooms"] as Dictionary).size() == 8, "Classic's own layout is not 8 rooms")
	var seen := {classic_sig: "classic"}
	var provided := ["classic"]
	var planned := []
	for mode_id in NightWatchMapRegistry.MAPS:
		if mode_id == "classic":
			continue
		var entry: Dictionary = NightWatchMapRegistry.MAPS[mode_id]
		var layout := NightWatchMapRegistry.layout_for(String(mode_id))
		if layout.is_empty():
			if not bool(entry.get("single_space", false)):
				planned.append(mode_id)
			continue
		provided.append(mode_id)
		var sig := NightWatchMapRegistry.signature(layout)
		_expect(not seen.has(sig), "%s has the same layout as %s" % [mode_id, seen.get(sig, "")])
		seen[sig] = mode_id
		var rooms: Dictionary = layout["rooms"]
		var shared := 0
		for id in rooms:
			if classic["rooms"].has(id):
				shared += 1
		_expect(shared <= NightWatchMapRegistry.SHARED_ROOM_IDS_MAX, "%s reuses %d of Classic's room ids (max %d)" % [mode_id, shared, NightWatchMapRegistry.SHARED_ROOM_IDS_MAX])
		_expect(rooms.size() >= 4, "%s has only %d rooms" % [mode_id, rooms.size()])
		# connected from its entrances
		var adj := {}
		for e in layout["edges"]:
			adj[e[0]] = adj.get(e[0], []) + [e[1]]
			adj[e[1]] = adj.get(e[1], []) + [e[0]]
		var reach := {}
		var queue: Array = (layout["entrances"] as Array).duplicate()
		for q in queue:
			reach[q] = true
		while not queue.is_empty():
			var cur: String = queue.pop_back()
			for n in adj.get(cur, []):
				if not reach.has(n):
					reach[n] = true
					queue.append(n)
		_expect(reach.size() == rooms.size(), "%s: only %d of %d rooms are reachable from the entrances" % [mode_id, reach.size(), rooms.size()])
		var script_path := String(entry["script"])
		var src := FileAccess.get_file_as_string(script_path)
		_expect(not src.contains("extends NightWatchBuilding"), "%s: its map script extends NightWatchBuilding (Classic's shell)" % mode_id)
	if REQUIRE_ALL:
		_expect(planned.is_empty(), "maps not delivered: %s" % str(planned))
	if _failures == 0:
		print("  night_watch_maps  %d layouts distinct from Classic's (%s); single-space: Bedtime, Salvage Run; planned: %s" % [provided.size() - 1, ", ".join(PackedStringArray(provided)), ", ".join(PackedStringArray(planned))])
	return _failures
