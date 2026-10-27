class_name FloorSets
extends RefCounted

## Which floor each area of The Last Route gets (docs/WALL_THEMES.md). One table to tweak: halls per district, rooms by
## purpose, and the district default for a room purpose not listed. Kinds are RefTextures floor kinds (painted in the blocky
## pixel style, matte via MaterialLook). Halls and rooms differ but share a district palette; a doorway cell and a hall
## junction take the hall's floor (the room floor starts inside the door line).

## District halls: floor kinds, and whether the hall gets the brass-edged carpet runner down its middle.
const HALLS := {
	"maze": {"floor": ["concrete0", "concrete1"], "runner": false},     # service corridors: bare concrete
	"mansion": {"floor": ["parquet0", "parquet1"], "runner": true},
	"hotel": {"floor": ["carpet_teal"], "runner": false},               # teal and gold hotel carpet
	"apartment": {"floor": ["parquet0", "parquet1"], "runner": true},
	"beach": {"floor": ["stone0", "stone1", "stone2"], "runner": false},
	"gothic": {"floor": ["stone0", "stone1"], "runner": true},
	"carnival": {"floor": ["check0", "check1"], "runner": false},
	"prison": {"floor": ["concrete0", "concrete1"], "runner": false},
	"inferno": {"floor": ["hazard", "metal3"], "runner": false},
}

## District default for rooms whose purpose is not in ROOMS.
const ROOM_DEFAULT := {
	"maze": ["carpet_tile0", "carpet_tile1"],
	"mansion": ["parquet0", "parquet1"],
	"hotel": ["floral0", "floral1"],
	"apartment": ["parquet1", "floral1"],
	"beach": ["stone0", "stone2"],
	"gothic": ["carpet_red"],
	"carnival": ["star0", "star1"],
	"prison": ["concrete0", "concrete1"],
	"inferno": ["metal3", "stone1"],
}

## Room purpose -> floor kinds.
const ROOMS := {
	# offices: grey carpet tiles
	"office_reception": ["carpet_tile0", "carpet_tile1"], "cubicle_room": ["carpet_tile1", "carpet_tile0"],
	"office_job": ["carpet_tile0"], "office_suite": ["carpet_tile0", "carpet_tile1"], "private_office": ["carpet_plum"],
	"storage": ["concrete1", "hazard"],
	# food and wet rooms: checker tile, clinic vinyl
	"kitchen": ["check0", "check1"], "restaurant_dining": ["check0", "parquet0"], "prison_cafeteria": ["check0", "check1"],
	"public_restroom": ["vinyl0", "vinyl1"], "hotel_bathroom": ["check0", "check1"], "house_bathroom": ["check1", "vinyl0"],
	"luxury_bathroom": ["check0"],
	# homes and hotels
	"bedroom": ["floral0", "parquet1"], "guest_room": ["floral0", "floral1"], "living_room": ["floral1", "parquet0"],
	"apartment_suite": ["parquet1", "floral1"], "family_dining": ["floral1", "parquet0"], "stairwell": ["floral0"],
	# mansion: ballroom parquet, red drawing room
	"dining_room": ["parquet0", "parquet1"], "drawing_room": ["carpet_red"],
	# gothic: library green, mourning plum, stone chapel and crypt
	"archive": ["carpet_green"], "mourning_room": ["carpet_plum"], "chapel": ["stone1", "stone0"], "crypt": ["stone1"],
	# carnival
	"arcade_room": ["star0", "star1"], "big_top": ["star0", "star1"], "midway": ["check0", "check1"],
	"game_stall": ["star1", "check1"], "backstage": ["concrete1", "grate"],
	# beach
	"cove": ["stone2", "stone0"], "tide_pool": ["stone2"], "beach_hut": ["parquet1"], "boardwalk_room": ["parquet0", "parquet1"],
	# prison
	"prison_cell": ["concrete0"],
	# inferno
	"thermal_chamber": ["hazard", "metal3"], "forge": ["hazard", "metal3"], "altar_room": ["stone1", "metal3"],
	"lava_gallery": ["metal3", "hazard"],
}


static func hall(region: String) -> Array:
	return (HALLS.get(region, HALLS["maze"]) as Dictionary)["floor"]


static func hall_runner(region: String) -> bool:
	return bool((HALLS.get(region, HALLS["maze"]) as Dictionary)["runner"])


static func room(region: String, room_type: String) -> Array:
	if ROOMS.has(room_type):
		return ROOMS[room_type]
	return ROOM_DEFAULT.get(region, ROOM_DEFAULT["maze"])


## True when this purpose has its own entry (the validator wants every generated purpose listed).
static func has_room(room_type: String) -> bool:
	return ROOMS.has(room_type)
