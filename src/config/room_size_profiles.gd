class_name RoomSizeProfiles
extends RefCounted

## What size each kind of room should be, and how much of its signature furniture it holds (docs/ROOM_SIZES.md).
## Sizes are cells (x, z) in either orientation. `generated` says whether the generators make this room type today; the
## planned types (classroom, library, gym, warehouse...) are listed so new districts and the city follow the same table.
## Small rooms never go below the 9x9 playable minimum; corridors and halls are not rooms and are not listed.

const PROFILES := {
	# music wing (src/game/music_wing.gd; MusicWing.SIZE_PROFILES): real sizes x 1.5, kept in step with that table
	"music_stage": {"min": Vector2i(9, 9), "preferred": Vector2i(15, 13), "max": Vector2i(21, 21), "tables": Vector2i(0, 0),
		"signature": ["drumKit"], "generated": true},
	"carnival_stage": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0),
		"signature": ["drumKit"], "generated": true},
	"practice_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0),
		"signature": ["drumKit"], "generated": true},
	"instrument_storage": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(11, 11), "tables": Vector2i(0, 0),
		"signature": ["instrumentCases"], "generated": true},
	"recording_booth": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0),
		"signature": ["mixingDesk"], "generated": true},
	"music_store": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0),
		"signature": ["guitarWallHanger"], "generated": true},
	# great gathering rooms
	"restaurant_dining": {"min": Vector2i(11, 9), "preferred": Vector2i(21, 21), "max": Vector2i(21, 21), "tables": Vector2i(2, 12),
		"signature": ["restaurantPartyTable"], "generated": true},
	"prison_cafeteria": {"min": Vector2i(11, 9), "preferred": Vector2i(21, 21), "max": Vector2i(21, 21), "tables": Vector2i(1, 9),
		"signature": ["prisonCafeteriaTable"], "generated": true},
	"dining_room": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 21), "max": Vector2i(21, 21), "tables": Vector2i(1, 6),
		"signature": ["diningTable"], "generated": true},
	"family_dining": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 11), "tables": Vector2i(1, 1),
		"signature": ["woodenTable"], "generated": true},
	"drawing_room": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 4), "signature": [], "generated": true},
	"big_top": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"midway": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"kitchen": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 11), "max": Vector2i(13, 13), "tables": Vector2i(0, 1),
		"signature": ["normalKitchenCounter", "normalKitchenStove"], "generated": true},
	"archive": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 2), "signature": [], "generated": true},
	"chapel": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"crypt": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"storage": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": ["supplyCrates"], "generated": true},
	"cove": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"tide_pool": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"forge": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"thermal_chamber": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"lava_gallery": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"altar_room": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	# small rooms: stay small, never under 9x9 where that rule applies
	"guest_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 11), "tables": Vector2i(0, 1), "signature": ["singleBed", "doubleBed", "bunkBed", "gothicDoubleBed"], "generated": true},
	"bedroom": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 1), "signature": ["doubleBed", "singleBed", "bunkBed", "gothicDoubleBed"], "generated": true},
	"hotel_bathroom": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(11, 9), "tables": Vector2i(0, 0), "signature": ["houseToilet"], "generated": true},
	"house_bathroom": {"min": Vector2i(9, 9), "preferred": Vector2i(9, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": ["houseToilet"], "generated": true},
	"luxury_bathroom": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"public_restroom": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"infirmary": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": ["hospitalBed"], "generated": true},
	"prison_cell": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(11, 9), "tables": Vector2i(0, 0), "signature": ["prisonBunk"], "generated": true},
	"living_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 11), "max": Vector2i(15, 15), "tables": Vector2i(0, 2), "signature": ["loungeCouch"], "generated": true},
	"mourning_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 1), "signature": [], "generated": true},
	"arcade_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 11), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": ["arcadeCabinet"], "generated": true},
	"game_stall": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"backstage": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"beach_hut": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 1), "signature": [], "generated": true},
	"boardwalk_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	# hospital, research lab and greenhouse (scripts/validate_biomes.gd); the great halls seat nobody, so no chair rule
	"ward": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 21), "tables": Vector2i(0, 0), "signature": [], "generated": true, "seated": false},
	"operating_theatre": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"nurses_station": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"waiting_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"icu": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"morgue": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"pharmacy": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"imaging": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"supply_closet": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"chem_lab": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"pod_room": {"min": Vector2i(19, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": ["divePod"], "generated": true},
	"bio_lab": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"decon": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"cold_storage": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"lab_office": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"control_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"potting_shed": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"cactus_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"irrigation_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"overgrown_room": {"min": Vector2i(9, 9), "preferred": Vector2i(11, 9), "max": Vector2i(13, 13), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"clean_room": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"server_hall": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": ["serverRack"], "generated": true},
	"containment": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 21), "tables": Vector2i(0, 0), "signature": [], "generated": true, "seated": false},
	"glasshouse": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": ["raisedPlanter"], "generated": true},
	"palm_house": {"min": Vector2i(9, 9), "preferred": Vector2i(21, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"dome_atrium": {"min": Vector2i(21, 21), "preferred": Vector2i(21, 21), "max": Vector2i(21, 21), "tables": Vector2i(1, 1), "signature": ["domeFountain"], "generated": true, "seated": false},
	# shopping arcade: 20x9 shopfronts on the five-wide main hall
	"donut_shop": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"cinema": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"corner_store": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"food_court": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"bakery": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"laundromat": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"electronics": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"night_diner": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"drugstore": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"florist": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"barber": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"pawn_shop": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	"stationery": {"min": Vector2i(9, 9), "preferred": Vector2i(20, 9), "max": Vector2i(21, 9), "tables": Vector2i(0, 0), "signature": [], "generated": true},
	# planned (no generator yet): the sizes new districts and the city should use
	"classroom": {"min": Vector2i(15, 11), "preferred": Vector2i(17, 13), "max": Vector2i(21, 15), "tables": Vector2i(8, 24), "signature": ["officeDesk"], "generated": false},
	"lecture_hall": {"min": Vector2i(21, 15), "preferred": Vector2i(21, 21), "max": Vector2i(33, 21), "tables": Vector2i(8, 30), "signature": [], "generated": false},
	"conference_room": {"min": Vector2i(13, 11), "preferred": Vector2i(15, 11), "max": Vector2i(21, 13), "tables": Vector2i(1, 2), "signature": ["woodenTable"], "generated": false},
	"open_office": {"min": Vector2i(21, 15), "preferred": Vector2i(21, 21), "max": Vector2i(33, 21), "tables": Vector2i(8, 24), "signature": ["officeDesk"], "generated": false},
	"lobby": {"min": Vector2i(15, 11), "preferred": Vector2i(21, 15), "max": Vector2i(33, 21), "tables": Vector2i(0, 4), "signature": [], "generated": false},
	"ballroom": {"min": Vector2i(21, 21), "preferred": Vector2i(33, 21), "max": Vector2i(41, 33), "tables": Vector2i(6, 24), "signature": [], "generated": false},
	"warehouse": {"min": Vector2i(21, 15), "preferred": Vector2i(33, 21), "max": Vector2i(41, 33), "tables": Vector2i(0, 0), "signature": ["supplyCrates"], "generated": false},
	"library": {"min": Vector2i(21, 15), "preferred": Vector2i(21, 21), "max": Vector2i(33, 21), "tables": Vector2i(2, 8), "signature": ["normalBookcase"], "generated": false},
	"gym": {"min": Vector2i(21, 15), "preferred": Vector2i(21, 21), "max": Vector2i(33, 21), "tables": Vector2i(0, 0), "signature": [], "generated": false},
	"greenhouse": {"min": Vector2i(21, 9), "preferred": Vector2i(21, 15), "max": Vector2i(33, 21), "tables": Vector2i(0, 0), "signature": [], "generated": false},
	"workshop": {"min": Vector2i(15, 11), "preferred": Vector2i(21, 15), "max": Vector2i(33, 21), "tables": Vector2i(2, 8), "signature": [], "generated": false},
}


static func profile(room_type: String) -> Dictionary:
	return PROFILES.get(room_type, {})


## True when `size` (either orientation) lies between the profile's min and max: its short side within the short sides of
## min..max and its long side within the long sides.
static func within(room_type: String, size: Vector2i) -> bool:
	var p := profile(room_type)
	if p.is_empty():
		return true
	var lo: Vector2i = p["min"]
	var hi: Vector2i = p["max"]
	var short := mini(size.x, size.y)
	var long := maxi(size.x, size.y)
	return short >= mini(lo.x, lo.y) and long >= maxi(lo.x, lo.y) and short <= mini(hi.x, hi.y) and long <= maxi(hi.x, hi.y)
