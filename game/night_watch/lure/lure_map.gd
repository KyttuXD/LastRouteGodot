class_name LureMap
extends RefCounted

## Dead Air's MAP (docs/NIGHT_WATCH_OFFICES.md, "Maps"): a radio station, not Classic's grid of cells. A wide reception sits on top of a plus-shaped floor: a
## tall studio A and studio B either side of the big live room, the transmitter room below it with the tape library beside it, and two crawlspaces (left and
## right) that run out of the transmitter room toward the broadcast booth. The rooms have different sizes and the doorways sit in the walls they share. The
## RULES graph is unchanged (the original's GRAPH), so every sim room has a station room: lobby = reception, arcade = studio A, party = studio B, ballpit = live
## room, prize = tape library, storage = transmitter room, ventl / ventr = the crawlspaces. Coordinates are metres on the XZ plane, relative to ORIGIN.

const ORIGIN := Vector3(-8.0, 0.0, -40.0)

## station room id -> [sim room id, x0, z0, x1, z1, theme]
const ROOMS := {
	"reception": ["lobby", -4.0, 0.0, 4.0, 5.0, "reception"],
	"studio_a": ["arcade", -10.0, 0.0, -4.0, 11.0, "studio"],
	"studio_b": ["party", 4.0, 0.0, 10.0, 11.0, "studio"],
	"live_room": ["ballpit", -4.0, 5.0, 4.0, 11.0, "live"],
	"tape_library": ["prize", 4.0, 11.0, 10.0, 17.0, "tapes"],
	"transmitter": ["storage", -4.0, 11.0, 4.0, 17.0, "transmitter"],
	"crawl_l": ["ventl", -9.0, 12.0, -4.0, 15.0, "crawl"],
	"crawl_r": ["ventr", -2.0, 17.0, 2.0, 20.0, "crawl"],
}
const EDGES := [["reception", "studio_a"], ["reception", "studio_b"], ["studio_a", "live_room"], ["studio_b", "live_room"], ["studio_b", "tape_library"],
	["live_room", "transmitter"], ["tape_library", "transmitter"], ["transmitter", "crawl_l"], ["transmitter", "crawl_r"]]


static func sim_to_map(sim_room: String) -> String:
	for id in ROOMS:
		if String(ROOMS[id][0]) == sim_room:
			return id
	return ""


static func rect(map_id: String) -> Rect2:
	var r: Array = ROOMS[map_id]
	return Rect2(float(r[1]), float(r[2]), float(r[3]) - float(r[1]), float(r[4]) - float(r[2]))


static func center(map_id: String) -> Vector3:
	var rc := rect(map_id)
	return ORIGIN + Vector3(rc.position.x + rc.size.x * 0.5, 0.0, rc.position.y + rc.size.y * 0.5)


## The doorway between two rooms that share a wall: [point in map coordinates, the wall's axis: "x" when the wall runs along x (a north / south wall)].
static func door_between(a: String, b: String) -> Dictionary:
	var ra := rect(a)
	var rb := rect(b)
	# vertical shared wall (x equal)
	for pair in [[ra.end.x, rb.position.x], [rb.end.x, ra.position.x]]:
		if is_equal_approx(pair[0], pair[1]):
			var lo := maxf(ra.position.y, rb.position.y)
			var hi := minf(ra.end.y, rb.end.y)
			if hi - lo > 1.5:
				return {"point": Vector2(pair[0], (lo + hi) * 0.5), "along": "z"}
	for pair in [[ra.end.y, rb.position.y], [rb.end.y, ra.position.y]]:
		if is_equal_approx(pair[0], pair[1]):
			var lo2 := maxf(ra.position.x, rb.position.x)
			var hi2 := minf(ra.end.x, rb.end.x)
			if hi2 - lo2 > 1.5:
				return {"point": Vector2((lo2 + hi2) * 0.5, pair[0]), "along": "x"}
	return {}


## The contract data for NightWatchMapRegistry: station rooms on the floor plan, the doors between them, and where the booth is reached from (the crawlspaces).
static func map_layout() -> Dictionary:
	var rooms := {}
	for id in ROOMS:
		rooms[id] = center(id)
	# the camera screen's minimap (NightWatchCamMap): camera n is cams[n - 1] (the rules' camera order), labels are the feed names, the crawlspaces are the vent shafts
	var cams := []
	var labels := {}
	for sim_id in LureData.ROOMS:
		var map_id := sim_to_map(sim_id)
		cams.append(map_id)
		labels[map_id] = String(LureData.INFO[sim_id]["label"])
	return {"rooms": rooms, "edges": EDGES, "entrances": ["crawl_l", "crawl_r"], "cams": cams, "labels": labels, "vents": ["crawl_l", "crawl_r"],
		"theme": "radio station: reception, two studios round a live room, tape library, transmitter room and two crawlspaces out to the booth"}
