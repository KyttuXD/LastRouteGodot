class_name NightWatchMapRegistry
extends RefCounted

## Each mode's MAP (the rooms the hunters walk and the feeds look into) is its own themed layout, never a reskin of Classic's building (docs/NIGHT_WATCH_OFFICES.md, "Maps").
## `MAPS` maps a 2D mode id to a script with `static func map_layout() -> Dictionary`:
##   {"rooms": {room id: Vector3 centre (metres, building space)}, "edges": [[room a, room b], ...], "entrances": [room ids the office is reached from], "theme": "text"}
## Optional keys that drive the camera screen's minimap (NightWatchCamMap): "cams" (camera rooms in camera order), "labels" ({room: name}), "vents" (vent-shaft room ids, edges
## touching them are dashed), "office" (Vector3 where YOU is drawn). A mode with a camera monitor MUST give "cams" and "labels".
## A mode with no multi-room map (Bedtime: one bedroom) sets `script` to "" and `single_space` to true. `signature()` hashes the layout (sorted room centres and edges), and
## the validator suite `night_watch_maps` fails if two modes share a signature, if a mode shares more than SHARED_ROOM_IDS_MAX room ids with Classic, or if a mode's world
## extends NightWatchBuilding (Classic's shell). Keep connected-map pathing (NightWatchPaths pattern) and the OfficeSpec entrances in step with `entrances`.

const SHARED_ROOM_IDS_MAX := 3

const MAPS := {
	"classic":  {"script": "res://src/night_watch/night_watch_building.gd", "single_space": false},
	"mask":     {"script": "", "single_space": false},
	"lure":     {"script": "res://src/night_watch/lure/lure_map.gd", "single_space": false},
	"bedroom":  {"script": "res://src/night_watch/bedroom/bedroom_map.gd", "single_space": false},
	"story":    {"script": "res://src/night_watch/story/story_map.gd", "single_space": false},
	"descent":  {"script": "", "single_space": false},
	"dayshift": {"script": "", "single_space": false},
	"extra":    {"script": "", "single_space": false},
	"mixed":    {"script": "", "single_space": false, "rotates": true},
}


## Classic's own layout: the eight camera rooms on the grid, the graph from NightWatchData.
static func classic_layout() -> Dictionary:
	var rooms := {}
	for id in NightWatchData.ROOMS:
		var info: Dictionary = NightWatchData.ROOMS[id]
		if int(info["cam"]) == 0:
			continue
		var g: Vector2i = info["grid"]
		rooms[id] = NightWatchBuilding.ORIGIN + Vector3(g.x * NightWatchBuilding.CELL, 0.0, g.y * NightWatchBuilding.CELL)
	var edges := []
	for a in NightWatchData.GRAPH:
		for b in NightWatchData.GRAPH[a]:
			if String(a) < String(b) and rooms.has(a) and rooms.has(b):   # the two door nodes belong to the office, not the map
				edges.append([a, b])
	var cams := NightWatchData.cam_rooms()
	var labels := {}
	for id in cams:
		labels[id] = String(NightWatchData.ROOMS[id]["label"])
	return {"rooms": rooms, "edges": edges, "entrances": ["westhall", "easthall"], "cams": cams, "labels": labels, "vents": [], "theme": "FNAF 1 style pizzeria: eight rooms on a 3 x 3 grid, two halls to the office"}


static func layout_for(mode_id: String) -> Dictionary:
	if mode_id == "classic":
		return classic_layout()
	var path := String(MAPS.get(mode_id, {}).get("script", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		return {}
	return (load(path) as GDScript).call("map_layout")


## A hash of the layout: the sorted room centres (rounded to 0.5 m, relative to the first room) and the sorted edges. Two modes with the same value share a layout.
static func signature(layout: Dictionary) -> int:
	var rooms: Dictionary = layout.get("rooms", {})
	if rooms.is_empty():
		return 0
	var anchor := Vector3(INF, 0.0, INF)
	for id in rooms:
		var p: Vector3 = rooms[id]
		if p.x < anchor.x or (p.x == anchor.x and p.z < anchor.z):
			anchor = p
	var parts := []
	for id in rooms:
		var rel: Vector3 = (rooms[id] as Vector3) - anchor
		parts.append("%.1f,%.1f" % [snappedf(rel.x, 0.5), snappedf(rel.z, 0.5)])
	parts.sort()
	var edge_parts := []
	for e in layout.get("edges", []):
		var a: Vector3 = (rooms.get(e[0], Vector3.ZERO) as Vector3) - anchor
		var b: Vector3 = (rooms.get(e[1], Vector3.ZERO) as Vector3) - anchor
		var s := ["%.1f,%.1f" % [snappedf(a.x, 0.5), snappedf(a.z, 0.5)], "%.1f,%.1f" % [snappedf(b.x, 0.5), snappedf(b.z, 0.5)]]
		s.sort()
		edge_parts.append("-".join(s))
	edge_parts.sort()
	return hash("|".join(parts) + "#" + "|".join(edge_parts))
