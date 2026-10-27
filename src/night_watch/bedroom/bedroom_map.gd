class_name BedroomMap
extends RefCounted

## Bedtime's MAP (docs/NIGHT_WATCH_OFFICES.md, "Maps"): a house wing around the child's bedroom. The bedroom (the player's room, BedroomOffice) opens east into a long
## hall and west into the wardrobe (Loxelle's closet). Off the hall: a kids' room (south), a bathroom (north) and the landing with the stairs (north, east end); the hall
## ends in the living room, which opens north into the galley kitchen. The mechanics are unchanged (listen, hold the closet, light the hall, light the bed): Javelle walks
## from the living room up the hall to the bedroom door and back, so the rest of the house is heard and glimpsed, never watched on a camera. Coordinates are metres in the
## bedroom's space (the bedroom's centre is the origin; x runs east along the hall, z south).

## map room id -> [x0, z0, x1, z1, theme]
const ROOMS := {
	"bedroom": [-2.7, -2.6, 2.7, 2.6, "office"],
	"wardrobe": [-3.8, -1.7, -2.7, -0.1, "office"],
	"hall": [2.7, -2.0, 10.7, 0.2, "office"],
	"kids_room": [4.0, 0.2, 8.0, 4.2, "kids"],
	"bathroom": [3.5, -6.0, 7.5, -2.0, "bath"],
	"landing": [8.0, -5.0, 10.6, -2.0, "landing"],
	"stairs": [8.0, -9.0, 10.6, -5.0, "stairs"],
	"living_room": [10.7, -4.5, 17.7, 2.5, "living"],
	"galley": [10.7, -9.5, 17.7, -4.5, "galley"],
}
const EDGES := [["bedroom", "wardrobe"], ["bedroom", "hall"], ["hall", "kids_room"], ["hall", "bathroom"], ["hall", "landing"], ["landing", "stairs"],
	["hall", "living_room"], ["living_room", "galley"]]
## Where the hall's three waypoints sit (Javelle's breathing and near stages): the doors of the side rooms hang off the nearest one.
const HALL_NODES := {"near": 3.4, "mid": 6.9, "far": 10.0}


static func rect(id: String) -> Rect2:
	var r: Array = ROOMS[id]
	return Rect2(float(r[0]), float(r[1]), float(r[2]) - float(r[0]), float(r[3]) - float(r[1]))


static func center(id: String) -> Vector3:
	var rc := rect(id)
	return Vector3(rc.position.x + rc.size.x * 0.5, 0.0, rc.position.y + rc.size.y * 0.5)


## The doorway between two rooms that share a wall: {"point": Vector2 (x, z), "along": "z" for a wall running north-south, "x" for east-west}.
static func door_between(a: String, b: String) -> Dictionary:
	var ra := rect(a)
	var rb := rect(b)
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


static func map_layout() -> Dictionary:
	var rooms := {}
	for id in ROOMS:
		rooms[id] = center(id)
	return {"rooms": rooms, "edges": EDGES, "entrances": ["hall", "wardrobe"],
		"theme": "a house wing: the bedroom with its wardrobe and a long hall to a kids' room, bathroom, stair landing and living room with the galley beyond"}
