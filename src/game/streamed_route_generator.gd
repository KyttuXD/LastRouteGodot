class_name StreamedRouteGenerator
extends RefCounted

## Deterministic foundation for the endless route. This class intentionally
## owns topology/data only; StreamedFacilityView3D consumes it for the solo
## debug playtest while FacilityView3D remains the shipping fixed-floor view.
## Keeping the seam contract pure makes host authority and persistence testable.

## One streamed chunk is deliberately the same footprint as the original
## Standard finite floor. That gives each newly generated piece enough room
## for the familiar central lobby, bounded rooms and three-wide halls instead
## of stretching a tiny maze cell pattern into an open parking structure.
const CHUNK_SIZE := 45
## Level zero is the spawn floor. It uses the same horizontally unbounded
## stream as every other Infinite level; origin stairs still guarantee routes
## both upward and downward.
const REGION_SIZE_CHUNKS := 4
## Deprecated pre-rename name (biome -> region), kept until the other lanes' branches have landed; use REGION_SIZE_CHUNKS.
const BIOME_REGION_SIZE := REGION_SIZE_CHUNKS
## Level of the sewer/waterworks layer under the maze (SewerRouteGenerator).
const SEWER_LEVEL := -1
## The collector sewer under the first one, and the Inferno maze under that
## (docs/SEWERS.md): reached only by ramps from the sewer level above.
const LOWER_SEWER_LEVEL := -2
## The Mezzanine (MezzanineRouteGenerator): grated catwalks over the maze, reached by the stairwells from level 0.
const MEZZANINE_LEVEL := 1
const INFERNO_LEVEL := -3
const CHUNK_CACHE_LIMIT := 192
const REGIONS := ["maze", "mansion", "hotel", "apartment", "beach", "gothic",
	"prison", "inferno", "carnival", "hospital", "lab", "greenhouse", "mall"]
## Deprecated pre-rename names (biome -> region), kept until the other lanes' branches have landed; use REGIONS.
const BIOMES := REGIONS
const EDGE_OFFSETS := [5, 11, 17, 22, 27, 33, 39]
## Keep vertical links far enough from the chunk centre to fit the physical
## eight-metre flight used by StreamedFacilityView3D. Ordinary door seams may
## still use every odd offset above.
## Stair anchors sit inside one of four reserved room sectors. Keeping them
## away from the outer edge lane and central hall leaves enough wall shoulder
## for a real stairwell instead of dropping a flight into an ordinary room.
## Stair links are shared by the two chunks on either side of a vertical
## boundary, so their placement must depend only on that canonical boundary.
## Even and odd boundaries use opposite diagonal bay pairs. A chunk can
## therefore contain both an up and a down link without ever stacking two
## flights, landings, or slab openings inside the same stairwell room.
const STAIR_BAY_ANCHORS := {
	0: [Vector2i(8, 8), Vector2i(12, 8), Vector2i(8, 12), Vector2i(12, 12)],
	1: [Vector2i(32, 8), Vector2i(36, 8), Vector2i(32, 12), Vector2i(36, 12)],
	2: [Vector2i(8, 32), Vector2i(12, 32), Vector2i(8, 36), Vector2i(12, 36)],
	3: [Vector2i(32, 32), Vector2i(36, 32), Vector2i(32, 36), Vector2i(36, 36)],
}
const STAIR_BAYS_BY_BOUNDARY_PARITY := {
	0: [0, 3],
	1: [1, 2],
}
const STAIR_RUN_CELLS := 8
const CORRIDOR_WIDTH := 3
## Share of seeds whose spawn region (level 0 around chunk 0) is the maze.
const SPAWN_MAZE_SHARE := 0.6
## Regions laid out as banks of rooms along a central three-wide cross (see _linear_room_layout).
const LINEAR_REGIONS := ["hotel", "prison"]
## Per-district density: dense districts use tight rooms along the halls (see _dense_linear_layout); the others keep
## their spacious sector layout (_mixed_room_layout). Apartments are already dense suites.
const DENSE_DISTRICTS := ["hotel", "prison", "maze", "mansion", "beach", "gothic", "carnival", "inferno",
	"hospital", "lab", "greenhouse", "mall"]
## Share of bank sides that become ONE big room (21x9, a hall/ballroom/greenhouse/big top) instead of two 11x9 rooms, and the
## hall-type rooms to pick from. Hotel and prison stay all small rooms; apartments are all suites (_mixed_room_layout).
const BANK_BIG_CHANCE := {"mansion": .5, "carnival": .5, "gothic": .35, "inferno": .35, "beach": .4, "maze": .2,
	"hospital": .5, "lab": .55, "greenhouse": .55}
const BANK_BIG_TYPES := {
	"mansion": ["drawing_room", "dining_room"], "carnival": ["midway", "carnival_stage"],
	"gothic": ["crypt", "chapel", "archive"], "inferno": ["forge", "thermal_chamber", "lava_gallery", "altar_room"],
	"beach": ["cove", "tide_pool"], "maze": ["restaurant_dining", "storage", "arcade_room"],
	# hunter-scale beds, imaging, benches and consoles need 1.4 m aisles (docs/ROOM_REFERENCE.md): these are 21x9 rooms
	"hospital": ["ward", "operating_theatre", "icu", "nurses_station", "imaging"],
	"lab": ["server_hall", "containment", "clean_room", "chem_lab", "bio_lab", "control_room"],
	"greenhouse": ["glasshouse", "palm_house"],
}
## Room types of the three facility regions, in the order a bank cycles through them (big/great-hall types also appear
## through BANK_BIG_TYPES and LARGE_ROOM_TYPES). The research lab is Kyttu's Lab, the story's home, and gets the most.
const HOSPITAL_ROOMS := ["ward", "nurses_station", "waiting_room", "operating_theatre", "icu", "morgue",
	"pharmacy", "imaging", "supply_closet"]
const LAB_ROOMS := ["clean_room", "chem_lab", "control_room", "containment", "bio_lab", "decon",
	"server_hall", "cold_storage", "lab_office"]
const GREENHOUSE_ROOMS := ["glasshouse", "potting_shed", "palm_house", "cactus_room", "irrigation_room",
	"overgrown_room"]
## Shopping arcade: every shop is a 20x9 shopfront on a five-wide main hall (_dense_linear_layout), named over its
## door in lit letters (StreamedFacilityView3D). The City's shop list, ported as Last Route rooms.
## The Mall's shops and their lit names live in res://data/regions/mall.json (docs/DATA_DRIVEN_CONTENT.md).
static var MALL_ROOMS: Array = ContentRegistry.get_def("regions", "mall").get("room_roles", [])
static var SHOP_NAMES: Dictionary = ContentRegistry.get_def("regions", "mall").get("shop_names", {})
const MALL_SHOP_WIDTH := 20
## Region recipes laid twice (at sides -5 and +5) across a 21-wide hall room; the rest size themselves to the room.
const REGION_REPEAT_TEMPLATES := ["operating_theatre", "icu", "morgue", "pharmacy", "imaging", "supply_closet",
	"nurses_station", "waiting_room", "clean_room", "control_room", "decon", "chem_lab", "bio_lab", "cold_storage",
	"lab_office", "palm_house", "cactus_room", "potting_shed", "irrigation_room", "overgrown_room", "glasshouse"]
## Great halls (docs/ROOM_SIZES.md): a side of a dense chunk can merge its two middle banks and the east-west hall between
## them into ONE 21x21 room for the districts' big gathering rooms (restaurant, mess hall, dining hall). The room opens on
## the vertical hall; both chunks at that seam give up the seam row and trim the hall stub so no dead-end hall remains.
const LARGE_ROOM_CHANCE := {"prison": .30, "hotel": .25, "mansion": .30,
	"hospital": .25, "lab": .30, "greenhouse": .45, "carnival": .35}
const LARGE_ROOM_TYPES := {"maze": ["restaurant_dining"], "prison": ["prison_cafeteria"],
	"hotel": ["restaurant_dining"], "mansion": ["dining_room"],
	"hospital": ["ward"], "lab": ["containment", "server_hall"], "greenhouse": ["dome_atrium", "glasshouse"],
	# the merry-go-round (6.7 m across) needs 2-3 cells clear on every side: only a 21x21 big top holds it (KT)
	"carnival": ["big_top"]}
const LARGE_ROOM_SIZE := 21
## The music wing (MusicWing): rare, hotel chunks only (the mall's slots are 20 wide), both slots of a chunk or neither.
const MUSIC_WING_REGIONS := ["hotel"]
const MUSIC_WING_CHANCE := .06
## Wall cleanup pass (stubs, diagonal pinches); off only for before/after maps.
const REMOVE_HUMPS := true
## Run PlacementClearance on every chunk: door keep-clear zones and the margin-wide walk-through (off only for audits).
static var clear_walkways := true
const STAIR_ACCESS_WIDTH := 5
## Rooms are big enough to furnish properly: nothing below 9x9 here (no closets, no 3x3 cells).
const ROOM_SIZES := [Vector2i(9, 9), Vector2i(9, 11), Vector2i(11, 9), Vector2i(11, 11),
	Vector2i(11, 13), Vector2i(13, 11), Vector2i(13, 13), Vector2i(15, 15)]
## Every runner starts with a flashlight, so it is not a world pickup (batteries recharge it).
const PICKUP_TYPES := ["taser", "lockpick", "crowbar", "rescue_axe"]
## How often each world tool turns up (KT: the Axe is rarer; it is the one tool that breaks the sewer's pipes).
const PICKUP_WEIGHTS := {"taser": 0.3, "lockpick": 0.3, "crowbar": 0.3, "rescue_axe": 0.1}
const BACKPACK_TYPES := ["backpack_small", "backpack_medium", "backpack_large"]
## Read REGION_PROP_SETS, not this: ContentRegistry.DATA regions take their prop_set from res://data/regions.
const _CODE_REGION_PROP_SETS := {
	"maze": [
		{"type": "arcadeCabinet", "size": Vector3(.75, 1.85, .7)},
		{"type": "arcadeCabinetCyanMagenta", "size": Vector3(.75, 1.85, .7)},
		{"type": "serverRack", "size": Vector3(.8, 2.0, .55)},
		{"type": "supplyCrates", "size": Vector3(1.4, 1.0, .8)},
		{"type": "vendingMachine", "size": Vector3(.85, 1.9, .6)},
		{"type": "woodenChair", "size": Vector3(.65, 1.0, .65)},
		{"type": "loungeCouchWide", "size": Vector3(2.6, 1.0, .95)},
		{"type": "normalPictureFrameEmpty", "size": Vector3(.7, .9, .12), "solid": false},
	],
	"mansion": [
		{"type": "mansionBookshelf", "size": Vector3(1.5, 2.1, .45)},
		{"type": "loungeCouchWide", "size": Vector3(2.6, 1.0, .95)},
		{"type": "diningSideboard", "size": Vector3(1.4, 1.1, .5)},
		{"type": "diningChair", "size": Vector3(.65, 1.0, .65)},
		{"type": "singleBed", "size": Vector3(1.0, .75, 2.0)},
		{"type": "bunkBed", "size": Vector3(1.06, 1.88, 2.1)},
		{"type": "mansionAreaRug", "size": Vector3(2.6, .03, 1.6), "solid": false},
		{"type": "bathroomMirror", "size": Vector3(.85, 1.4, .14), "solid": false},
		{"type": "luxuryPictureFrameEmpty", "size": Vector3(.75, 1.0, .12), "solid": false},
		{"type": "luxuryPaintingFrameEmpty", "size": Vector3(1.2, 1.55, .12), "solid": false},
	],
	"hotel": [
		{"type": "singleBed", "size": Vector3(1.0, .75, 2.0)},
		{"type": "bunkBed", "size": Vector3(1.06, 1.88, 2.1)},
		{"type": "bedroomWardrobe", "size": Vector3(1.2, 2.1, .55)},
		{"type": "bedroomNightstand", "size": Vector3(.65, .8, .55)},
		{"type": "loungeCouchWide", "size": Vector3(2.6, 1.0, .95)},
		{"type": "woodenChairCushion", "size": Vector3(.65, 1.0, .65)},
		{"type": "hotelCarpet", "size": Vector3(2.2, .03, 1.4), "solid": false},
		{"type": "bathroomMirror", "size": Vector3(.85, 1.4, .14), "solid": false},
		{"type": "luxuryPictureFrameEmpty", "size": Vector3(.75, 1.0, .12), "solid": false},
		{"type": "luxuryPaintingFrameEmpty", "size": Vector3(1.2, 1.55, .12), "solid": false},
	],
	"apartment": [
		{"type": "normalKitchenFridge", "size": Vector3(.85, 2.0, .75)},
		{"type": "normalBookcase", "size": Vector3(1.25, 1.9, .45)},
		{"type": "loungeCouchWide", "size": Vector3(2.6, 1.0, .95)},
		{"type": "singleBed", "size": Vector3(1.0, .75, 2.0)},
		{"type": "bunkBed", "size": Vector3(1.06, 1.88, 2.1)},
		{"type": "woodenChair", "size": Vector3(.65, 1.0, .65)},
		{"type": "apartmentCarpet", "size": Vector3(2.0, .03, 1.35), "solid": false},
		{"type": "bathroomMirror", "size": Vector3(.85, 1.4, .14), "solid": false},
		{"type": "normalPictureFrameEmpty", "size": Vector3(.7, .9, .12), "solid": false},
		{"type": "normalPaintingFrameEmpty", "size": Vector3(1.2, 1.5, .12), "solid": false},
	],
	"beach": [
		{"type": "beachUmbrella", "size": Vector3(.45, 2.35, .45)},
		{"type": "beachChair", "size": Vector3(.75, 1.0, 1.2)},
		{"type": "surfboardRack", "size": Vector3(1.4, 1.7, .55)},
		{"type": "beachMat", "size": Vector3(1.4, .03, .85), "solid": false},
		{"type": "frozenTidelinePool", "size": Vector3(6.2, .2, 5.2),
			"solid": false},
	],
	"gothic": [
		{"type": "gothicBookcase", "size": Vector3(1.4, 2.1, .5)},
		{"type": "gothicHighbackChair", "size": Vector3(.7, 1.35, .7)},
		{"type": "gothicCoffinChest", "size": Vector3(.85, .65, 1.9)},
		{"type": "gothicDoubleBed", "size": Vector3(1.8, .9, 2.2)},
		{"type": "gothicBedroomBench", "size": Vector3(1.4, .7, .55)},
		{"type": "gothicBedroomRug", "size": Vector3(2.2, .03, 1.4), "solid": false},
		{"type": "gothicPictureFrameEmpty", "size": Vector3(.75, 1.0, .12), "solid": false},
		{"type": "gothicPaintingFrameEmpty", "size": Vector3(1.2, 1.55, .12), "solid": false},
	],
	"inferno": [
		{"type": "basaltPillar", "size": Vector3(.8, 2.4, .8)},
		{"type": "emberBrazier", "size": Vector3(.8, 1.0, .8)},
		{"type": "magmaCrystalCluster", "size": Vector3(1.0, 1.1, 1.0)},
	],
	"prison": [
		{"type": "prisonBunk", "size": Vector3(.55, .95, 1.75)},
		{"type": "supplyCrates", "size": Vector3(1.4, 1.0, .8)},
		{"type": "prisonCafeteriaTable", "size": Vector3(2.65, .78, 1.62)},
		{"type": "prisonServingCounter", "size": Vector3(2.46, 2.05, .88)},
		{"type": "prisonTrayReturn", "size": Vector3(1.0, 1.45, .72)},
		{"type": "prisonKitchenRack", "size": Vector3(1.35, 1.82, .62)},
		{"type": "ceilingLight", "size": Vector3(.75, .3, .75)},
	],
	"carnival": [
		{"type": "carnivalTicketBooth", "size": Vector3(1.75, 2.45, 1.25)},
		{"type": "popcornCart", "size": Vector3(1.45, 1.9, .9)},
		{"type": "ringTossStall", "size": Vector3(2.6, 2.65, 1.55)},
		{"type": "strengthTester", "size": Vector3(1.0, 2.95, .8)},
		{"type": "shootingGallery", "size": Vector3(2.6, 2.65, 1.55)},
		{"type": "whackAMole", "size": Vector3(2.6, 2.65, 1.55)},
		{"type": "duckPond", "size": Vector3(1.7, .8, 1.7)},
		{"type": "prizeClawMachine", "size": Vector3(.9, 2.0, .8)},
		{"type": "circusPedestal", "size": Vector3(1.7, .8, 1.7)},
		{"type": "arcadeCabinet", "size": Vector3(.75, 1.85, .7)},
		{"type": "arcadeCabinetCyanMagenta", "size": Vector3(.75, 1.85, .7)},
		{"type": "vendingMachine", "size": Vector3(.85, 1.9, .6)},
		{"type": "privacyCurtain", "size": Vector3(.9, 2.4, .5)},
		{"type": "floorLamp", "size": Vector3(.55, 1.9, .55)},
	],
	"mall": ContentRegistry.DATA,
	"hospital": [
		{"type": "hospitalBed", "size": Vector3(.95, 1.05, 2.1)},
		{"type": "wheelchair", "size": Vector3(.65, .95, .95)},
		{"type": "ivDripStand", "size": Vector3(.45, 1.95, .45)},
		{"type": "medicalSupplyRack", "size": Vector3(1.2, 1.9, .5)},
		{"type": "waitingChairs", "size": Vector3(2.0, .86, .62)},
		{"type": "hospitalWardSign", "size": Vector3(.95, .36, .06), "solid": false},
		{"type": "xrayLightbox", "size": Vector3(1.3, .85, .08), "solid": false},
	],
	"lab": [
		{"type": "labBench", "size": Vector3(2.0, 1.45, .8)},
		{"type": "specimenTank", "size": Vector3(.95, 2.3, .95)},
		{"type": "gasCylinderRack", "size": Vector3(.95, 1.65, .45)},
		{"type": "biohazardBin", "size": Vector3(.5, .82, .5)},
		{"type": "serverRack", "size": Vector3(.8, 2.0, .55)},
		{"type": "hazardSign", "size": Vector3(.6, .62, .05), "solid": false},
		{"type": "labWhiteboard", "size": Vector3(1.8, 1.15, .08), "solid": false},
	],
	"greenhouse": [
		{"type": "raisedPlanter", "size": Vector3(2.0, 1.05, .9)},
		{"type": "bananaPlant", "size": Vector3(1.1, 1.8, 1.1)},
		{"type": "cactusCluster", "size": Vector3(.95, 1.0, .95)},
		{"type": "seedlingRack", "size": Vector3(1.2, 1.85, .5)},
		{"type": "wateringCart", "size": Vector3(1.0, .95, .6)},
		{"type": "overgrowthPatch", "size": Vector3(1.6, .35, 1.3), "solid": false},
	],
}
const _CODE_REGION_ROOM_DOORS := {
	"maze": "normalRoomDoor",
	"apartment": "normalRoomDoor",
	"hotel": "luxuryRoomDoor",
	"mansion": "luxuryRoomDoor",
	"gothic": "gothicRoomDoor",
	"mall": ContentRegistry.DATA,
}
const _CODE_REGION_DOUBLE_ROOM_DOORS := {
	"maze": "normalDoubleRoomDoor",
	"apartment": "normalDoubleRoomDoor",
	"hotel": "luxuryDoubleRoomDoor",
	"mansion": "luxuryDoubleRoomDoor",
	"gothic": "gothicDoubleRoomDoor",
	"mall": ContentRegistry.DATA,
}
static var REGION_PROP_SETS: Dictionary = ContentRegistry.resolve(_CODE_REGION_PROP_SETS, "regions", "prop_set")
static var REGION_ROOM_DOORS: Dictionary = ContentRegistry.resolve(_CODE_REGION_ROOM_DOORS, "regions", "room_door")
static var REGION_DOUBLE_ROOM_DOORS: Dictionary = ContentRegistry.resolve(_CODE_REGION_DOUBLE_ROOM_DOORS, "regions",
	"double_room_door")


static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


## Packs changed (ContentRegistry.load_packs / unload_packs): recompute the tables read from the registry. Chunks a
## generator already cached keep their old dressing; callers build a fresh generator per room.
static func rebuild_from_registry() -> void:
	MALL_ROOMS = ContentRegistry.get_def("regions", "mall").get("room_roles", [])
	SHOP_NAMES = ContentRegistry.get_def("regions", "mall").get("shop_names", {})
	REGION_PROP_SETS = ContentRegistry.resolve(_CODE_REGION_PROP_SETS, "regions", "prop_set")
	REGION_ROOM_DOORS = ContentRegistry.resolve(_CODE_REGION_ROOM_DOORS, "regions", "room_door")
	REGION_DOUBLE_ROOM_DOORS = ContentRegistry.resolve(_CODE_REGION_DOUBLE_ROOM_DOORS, "regions", "double_room_door")
## Collision envelopes for deterministic furnished-room recipes. These follow
## the authored GLB footprints rather than the old one-cell placeholder rule.
## Local X runs across a prop's front and local Z runs from its back into the
## room; _template_prop_entry rotates both visual and collision together.
const TEMPLATE_PROP_SIZES := {
	"mansionMarbleColumn": Vector3(.5, 2.25, .5), "mansionPorcelainVase": Vector3(.44, .94, .44),
	# Room-purpose catalog (tools/props/blocky_props_rework4.py); fitted boxes come from prop_collider_sizes.gd.
	"ivStand": Vector3(.5, 1.9, .5), "medicalCart": Vector3(.75, 1.0, .5),
	"readingTable": Vector3(1.5, .75, .88), "libraryGlobe": Vector3(.62, 1.06, .62), "storageBarrel": Vector3(.62, .94, .62),
	"storageShelving": Vector3(1.25, 1.94, .5), "receptionDesk": Vector3(2.0, 1.12, .88), "pottedPlant": Vector3(.5, 1.25, .5),
	"standingMirror": Vector3(.62, 1.75, .44),
	"arcadeCarpetCircle": Vector3(3.0, .03, 3.0), "beachMat": Vector3(1.4, .03, .85),
	"gothicFloorCandelabra": Vector3(.5, 1.6, .5), "gothicPedestalTable": Vector3(.8, .75, .8),
	"normalBookcase": Vector3(1.3, 2.0, .45),
	"diningTable": Vector3(2.3, .8, .95),
	"diningChair": Vector3(.65, 1.0, .65),
	"diningChairCushion": Vector3(.65, 1.0, .65),
	"diningSideboard": Vector3(1.5, 1.15, .55),
	"singleBed": Vector3(1.1, .78, 2.7),
	"doubleBed": Vector3(1.9, .92, 2.7),
	"prisonBunk": Vector3(.55, .98, 1.75),
	"bunkBed": Vector3(1.06, 1.88, 2.1),
	"officeDesk": Vector3(1.65, .78, .72),
	"officeChair": Vector3(.68, 1.42, .68),
	"officeCrtSecurityConsole": Vector3(1.65, 1.45, .78),
	"officeCubiclePartition": Vector3(1.82, 1.72, .20),
	"officePrinter": Vector3(.72, .68, .58),
	"officeWaterCooler": Vector3(.58, 1.82, .52),
	"officePhotocopier": Vector3(.92, 1.25, .80),
	"officeShredder": Vector3(.54, 1.45, .44),
	"officeFileBoxes": Vector3(1.05, .92, .68),
	"officeCornerWorkstation": Vector3(1.72, .90, 1.12),
	# Linear prison wings are only three interior cells deep. Keep the bolted
	# table's navigation envelope to one cell so it can sit in the middle row
	# without claiming the serving line or the doorway, matching the restaurant
	# party-table treatment of a wide visual and a compact collider.
	"prisonCafeteriaTable": Vector3(2.65, .78, .95),
	"prisonServingCounter": Vector3(2.46, 2.05, .88),
	"prisonTrayReturn": Vector3(1.0, 1.45, .72),
	# Corner placement in a 5-wide wing needs a one-cell width. The authored
	# rack remains taller than a crate; only the lateral envelope is tightened.
	"prisonKitchenRack": Vector3(.95, 1.82, .62),
	"bedroomNightstand": Vector3(.6, .82, .55),
	"bedroomWardrobe": Vector3(1.25, 2.15, .65),
	"bedroomDresser": Vector3(1.3, 1.1, .6),
	"woodenTable": Vector3(1.25, .8, .8),
	"woodenChair": Vector3(.65, 1.0, .65),
	"woodenChairCushion": Vector3(.65, 1.0, .65),
	"woodenDresserSideboard": Vector3(1.25, 1.0, .65),
	# The authored cloth is 1.02 m deep, but its solid tabletop is narrower.
	# Keeping the navigation envelope below one grid cell lets adjacent dining
	# chairs own their cells without visually or physically entering the table.
	"restaurantPartyTable": Vector3(2.75, 2.2, .9),
	"diningChandelier": Vector3(.55, 1.5, .55),
	"ceilingLight": Vector3(.75, .30, .75),
	"ceilingFan": Vector3(1.65, .59, 1.65),
	"tableLamp": Vector3(.50, .65, .36),
	"retroComputerCompact": Vector3(1.15, .92, .72),
	"retroComputerTower": Vector3(1.30, .92, .72),
	"retroComputerDesktop": Vector3(1.15, .92, .72),
	"retroComputerTerminal": Vector3(1.15, .92, .72),
	"floorLamp": Vector3(.55, 1.75, .55),
	"normalTvConsole": Vector3(1.45, 1.45, .55),
	"normalKitchenCounter": Vector3(1.5, 1.05, .7),
	"normalKitchenSink": Vector3(1.25, 1.05, .7),
	"normalKitchenStove": Vector3(.85, 1.15, .7),
	"normalKitchenFridge": Vector3(.85, 2.05, .75),
	"normalKitchenWallCabinet": Vector3(1.05, 1.96, .45),
	"normalKitchenIsland": Vector3(1.7, 1.05, .95),
	"luxuryKitchenCounter": Vector3(1.5, 1.05, .7),
	"luxuryKitchenSink": Vector3(1.25, 1.05, .7),
	"luxuryKitchenStove": Vector3(.85, 1.15, .7),
	"luxuryKitchenFridge": Vector3(.85, 2.05, .75),
	"luxuryKitchenIsland": Vector3(1.7, 1.05, .95),
	"gothicDoubleBed": Vector3(2.05, .95, 2.85),
	"gothicNightstand": Vector3(.7, .85, .6),
	"gothicWardrobe": Vector3(1.35, 2.2, .7),
	"gothicHighbackChair": Vector3(.75, 1.65, .7),
	"arcadeCabinet": Vector3(.75, 1.85, .7),
	"arcadeCabinetCyanMagenta": Vector3(.75, 1.85, .7),
	"vendingMachine": Vector3(.85, 1.95, .7),
	"carnivalTicketBooth": Vector3(1.75, 2.45, 1.25),
	"popcornCart": Vector3(1.45, 1.9, .9),
	"ringTossStall": Vector3(2.6, 2.65, 1.55),
	"carouselCenterpiece": Vector3(1.3, 3.3, 1.3),
	"shootingGallery": Vector3(2.6, 2.65, 1.55),
	"whackAMole": Vector3(2.6, 2.65, 1.55),
	"duckPond": Vector3(1.7, .8, 1.7),
	"prizeClawMachine": Vector3(.9, 2.0, .8),
	"strengthTester": Vector3(1.0, 2.95, .8),
	"circusPedestal": Vector3(1.7, .8, 1.7),
	"frozenTidelinePool": Vector3(6.2, .2, 5.2),
	"beachChair": Vector3(.75, 1.0, 1.2),
	"beachUmbrella": Vector3(.55, 2.6, .55),
	"surfboardRack": Vector3(1.4, 1.7, .65),
	"tikiBar": Vector3(1.6, 2.5, 1.1),
	"frozenBeachHut": Vector3(2.3, 2.8, 2.0),
	"loungeCouchWide": Vector3(2.7, 1.05, 1.0),
	"loungeCouch": Vector3(1.7, 1.0, .95),
	"normalCoffeeTable": Vector3(1.25, .6, .75),
	"filingCabinet": Vector3(.75, 1.45, .55),
	"privacyCurtain": Vector3(.9, 2.4, .5),
	"bathroomStall": Vector3(.72, 1.95, .65),
	"bathroomSink": Vector3(.85, 1.35, .5),
	"bathroomMirror": Vector3(.75, 1.25, .16),
	"normalPictureFrameEmpty": Vector3(.72, .95, .12),
	"normalPaintingFrameEmpty": Vector3(1.22, 1.52, .12),
	"luxuryPictureFrameEmpty": Vector3(.78, 1.05, .12),
	"luxuryPaintingFrameEmpty": Vector3(1.24, 1.58, .12),
	"gothicPictureFrameEmpty": Vector3(.78, 1.05, .12),
	"gothicPaintingFrameEmpty": Vector3(1.24, 1.58, .12),
	"bedroomRug": Vector3(2.2, .03, 1.45),
	"hotelCarpet": Vector3(2.2, .03, 1.4),
	"apartmentCarpet": Vector3(2.0, .03, 1.35),
	"gothicBedroomRug": Vector3(2.2, .03, 1.4),
	"bathroomVanity": Vector3(.9, 1.65, .55),
	"publicRestroomToilet": Vector3(.55, 1.25, .82),
	"publicMensUrinal": Vector3(.48, 1.15, .42),
	"publicSinkBank": Vector3(1.75, 1.25, .55),
	"publicHandDryer": Vector3(.45, .55, .18),
	"publicSoapDispenser": Vector3(.28, .42, .18),
	"publicPaperTowelDispenser": Vector3(.45, .65, .18),
	"publicMensShowerStall": Vector3(.95, 2.2, .95),
	"publicWomensShowerStall": Vector3(.95, 2.2, .95),
	"publicShowerBench": Vector3(1.25, .65, .5),
	"houseBathtub": Vector3(1.85, .9, .85),
	"houseToilet": Vector3(.55, 1.25, .82),
	"houseShowerEnclosure": Vector3(1.0, 2.2, 1.0),
	"houseMedicineCabinet": Vector3(.75, 1.1, .16),
	"houseTowelRack": Vector3(.85, .65, .16),
	"houseBathMat": Vector3(.95, .08, .65),
	"houseBathroomShelf": Vector3(.9, .65, .16),
	"lavaVent": Vector3(.68, .6, .60),
	"basaltRubble": Vector3(1.25, .62, 1.10),
	"infernoAltar": Vector3(1.35, 1.3, .95),
	"infernoChainLantern": Vector3(.42, 1.6, .42),
	"lavaPipeManifold": Vector3(1.35, 1.45, .55),
	"charredSupplyCrate": Vector3(.95, .92, .85),
	# hospital, research lab and greenhouse props (tools/props/blocky_props_regions.py: the authored size in metres)
	"hospitalBed": Vector3(.95, 1.05, 2.1), "hospitalCurtain": Vector3(1.9, 2.4, .16),
	"ivDripStand": Vector3(.45, 1.95, .45), "vitalsMonitor": Vector3(.6, 1.62, .55),
	"nursesStation": Vector3(2.4, 1.18, .95), "waitingChairs": Vector3(2, .86, .62),
	"operatingTable": Vector3(.75, 1, 2), "surgicalLight": Vector3(1.5, .9, 1.5),
	"instrumentTrolley": Vector3(.9, .95, .55), "morgueCabinet": Vector3(2, 2.1, .95),
	"autopsyTable": Vector3(.85, .95, 2), "pharmacyShelf": Vector3(1.6, 2, .45), "xrayMachine": Vector3(1.6, 2.2, 1.5),
	"xrayLightbox": Vector3(1.3, .85, .08), "medicalSupplyRack": Vector3(1.2, 1.9, .5),
	"wheelchair": Vector3(.65, .95, .95), "hospitalWardSign": Vector3(.95, .36, .06), "labBench": Vector3(2, 1.45, .8),
	"fumeHood": Vector3(1.5, 2.35, .9), "specimenTank": Vector3(.95, 2.3, .95),
	"containmentCell": Vector3(2.2, 2.6, 1.7), "labCoolingUnit": Vector3(1, 2.1, .85),
	"controlConsole": Vector3(2.4, 1.4, 1), "monitorWall": Vector3(2.4, 1.4, .1), "divePod": Vector3(1.0, 1.35, 2.2), "divePodFilm": Vector3(1.0, 1.35, 2.2),
	"divePodLit": Vector3(1.0, 1.35, 2.2), "diveHeadsetStand": Vector3(.32, 1.25, .32),
	"diveHeadsetShelf": Vector3(1.9, .45, .32), "diveConsole": Vector3(2.0, 1.3, .8), "deconShower": Vector3(1.3, 2.5, 1.3),
	"coldStorageUnit": Vector3(1.4, 2.1, .85), "labWhiteboard": Vector3(1.8, 1.15, .08),
	"hazardSign": Vector3(.6, .62, .05), "labGlassPartition": Vector3(1.95, 2.5, .14),
	"labStool": Vector3(.42, .75, .42), "labMicroscope": Vector3(.34, .46, .36),
	"gasCylinderRack": Vector3(.95, 1.65, .45), "biohazardBin": Vector3(.5, .82, .5),
	"raisedPlanter": Vector3(2, 1.05, .9), "pottingBench": Vector3(1.6, 1.45, .7), "pottedPalm": Vector3(1.5, 2.7, 1.5),
	"bananaPlant": Vector3(1.1, 1.8, 1.1), "saguaroCactus": Vector3(.8, 2.15, .6),
	"cactusCluster": Vector3(.95, 1, .95), "seedlingRack": Vector3(1.2, 1.85, .5),
	"irrigationManifold": Vector3(1.5, 1.85, .6), "mistingPost": Vector3(.4, 2.5, .4),
	"overgrowthPatch": Vector3(1.6, .35, 1.3), "hangingVines": Vector3(1.2, 1.25, 1.2),
	"domeFountain": Vector3(2.6, 1.6, 2.6), "wateringCart": Vector3(1, .95, .6),
	"greenhouseBench": Vector3(1.6, .85, .6), "compostBins": Vector3(1.4, 1, .75),
	# shopping arcade props (tools/props/blocky_props_mall.py)
	"shopShelf": Vector3(1.2, 1.9, .5), "shopFridge": Vector3(1, 2.1, .75), "checkoutCounter": Vector3(1.8, 1.32, .75),
	"displayCase": Vector3(1.4, 1.25, .75), "coffeeStation": Vector3(1.3, 1.55, .65),
	"donutFryer": Vector3(1.3, 1.25, .8), "bakeryRack": Vector3(1, 1.9, .6), "dinerStool": Vector3(.42, .78, .42),
	"dinerBooth": Vector3(1.6, 1.15, 1.5), "menuBoard": Vector3(1.5, .9, .08), "donutSign": Vector3(1.3, 1.3, .3),
	"washingMachine": Vector3(.75, 1.15, .72), "dryerStack": Vector3(.75, 2.05, .72),
	"flowerStand": Vector3(1.3, 1.2, .65), "barberChair": Vector3(.7, 1.25, .95),
	"barberStation": Vector3(1.2, 1.9, .45), "clothesRack": Vector3(1.4, 1.65, .55), "tvWall": Vector3(1.6, 1.9, .5),
	"cinemaSeats": Vector3(2.4, 1, .8), "cinemaScreen": Vector3(4.2, 2.2, .12), "ticketBooth": Vector3(1.7, 2.35, 1.2),
	"concessionCounter": Vector3(2.2, 1.7, .8), "foodCourtTable": Vector3(1.7, .78, 1.7),
	"mallPlanter": Vector3(1.3, 2.4, 1.3), "mallBench": Vector3(1.8, .5, .6),
	# music wing
	"micStand": Vector3(0.5, 1.6, 0.5),
	"podiumMic": Vector3(0.6, 1.15, 0.5),
	"deskMic": Vector3(0.15, 0.25, 0.15),
	"drumKit": Vector3(1.8, 1.2, 1.5),
	"electricGuitarStand": Vector3(0.4, 1, 0.35),
	"acousticGuitarStand": Vector3(0.45, 1.05, 0.35),
	"bassGuitarStand": Vector3(0.4, 1.15, 0.35),
	"keyboardStand": Vector3(1.3, 0.95, 0.4),
	"uprightPianoMusic": Vector3(1.5, 1.25, 0.95),
	"ampStack": Vector3(0.75, 1.3, 0.4),
	"comboAmp": Vector3(0.6, 0.5, 0.3),
	"stageMonitor": Vector3(0.55, 0.35, 0.4),
	"paSpeakerPole": Vector3(0.5, 2, 0.5),
	"mixingDesk": Vector3(1.5, 0.95, 0.8),
	"studioMonitors": Vector3(0.8, 0.35, 0.25),
	"rackGear": Vector3(0.6, 1.2, 0.6),
	"musicStand": Vector3(0.45, 1.2, 0.4),
	"cableCoil": Vector3(0.4, 0.06, 0.4),
	"cableRun": Vector3(1.4, 0.03, 0.15),
	"stageLightRig": Vector3(3, 2.4, 0.4),
	"acousticPanel": Vector3(1, 1, 0.08),
	"guitarWallHanger": Vector3(1, 0.8, 0.2),
	"instrumentCases": Vector3(1, 0.8, 0.6),
	"onAirSign": Vector3(0.6, 0.25, 0.1),
}
## Only hunters whose gimmicks depend on the shared navigation contract (or no
## gimmick at all) enter the streamed route today. Finite-floor objective and
## hiding-place hunters stay in the standard mode until those world entities
## have streamed equivalents.
const STREAMED_HUNTER_IDS := [
	"dovelle", "quenelle", "elise", "xivvy", "thessine", "umbriel",
	"aki", "porcelle", "glyra", "haelith", "opalie", "ysolde",
	"briselle", "verrine",
]

var world_seed := "ENDLESS-ROUTE"
## PUBLIC route: safe rooms are spread through the map (see is_safe_room).
var public_route := false
## Co-op room (several runners): Revive Kits spawn at GameConfig.REVIVE_KIT_CHANCE_COOP, else at the solo chance. Every
## peer in a room agrees (RoomState.online), so the world stays the same for all of them.
var coop := false
var _chunk_cache := {}
var _chunk_cache_order: Array[Vector3i] = []


var _sewer: SewerRouteGenerator
var _vents: VentNetwork
var _mezzanine: MezzanineRouteGenerator
var _stairwell_cache := {}


func _init(seed_text: String = "ENDLESS-ROUTE") -> void:
	world_seed = seed_text if not seed_text.is_empty() else "ENDLESS-ROUTE"


## A same-seed copy for the streaming worker thread (chunks are a pure function of the seed and settings, so the copy
## produces identical dictionaries). Null means "generate on the main thread only": subclasses (layout-backed maps) opt out.
func make_worker_copy() -> StreamedRouteGenerator:
	if get_script() != StreamedRouteGenerator:
		return null
	var copy := StreamedRouteGenerator.new(world_seed)
	copy.public_route = public_route
	copy.coop = coop
	return copy


func has_chunk_cached(coord: Vector3i) -> bool:
	return _chunk_cache.has(coord)


## Take a chunk generated by a worker copy, unless this generator already built it.
func adopt_chunk(coord: Vector3i, data: Dictionary) -> void:
	if _chunk_cache.has(coord):
		return
	_chunk_cache[coord] = data
	_chunk_cache_order.append(coord)
	while _chunk_cache_order.size() > CHUNK_CACHE_LIMIT:
		_chunk_cache.erase(_chunk_cache_order.pop_front())


## The stairwell from `upper_level` down one storey in column (x, z), or {} (Stairwells).
## 0 <-> -1 is decided by the maze chunk, which keeps it clear of the sewer's
## ramp and falls quadrants and of its own suites (it is read from that chunk,
## as the sewer's ladders are); +1..+3 are pure seed maths, planned here for the
## upper-levels lane, which builds around them.
func stairwell_between(x: int, z: int, upper_level: int) -> Dictionary:
	if VoidRegion.contains(world_seed, x, z):
		# inside the void the only stairs are the tower's
		var tower := VoidRegion.tower_chunk(world_seed)
		return VoidRegion.tower_well(world_seed, upper_level) if x == tower.x and z == tower.y else {}
	if upper_level == 0 or (upper_level == MEZZANINE_LEVEL and is_chunk_allowed(Vector3i(x, MEZZANINE_LEVEL, z))):
		for well in chunk(Vector3i(x, 0, z)).get("stairwells", []):
			if int(well["upper"]) == upper_level:
				return well
		return {}
	return {}


const MAX_STAIRWELL_DROPPED_ROOM_CELLS := 100
const MAX_FORCED_STAIRWELL_DROPPED_ROOM_CELLS := 220


## The maze <-> sewer stairwell for a maze chunk being built: clear of the
## sewer's ramp and falls quadrants, and only where it fits the maze as built
## (_maze_stairwell_fits), so no suite or hall loses anything to it.
func _plan_maze_stairwell(x: int, z: int, grid: Array, layout: Dictionary, circulation: Dictionary,
		upper_level: int = 0, also_avoid: Array = [], force: bool = false) -> Dictionary:
	var avoid := also_avoid.duplicate()
	var ramp: Dictionary = sewer().ramp_between(x, z, SEWER_LEVEL)
	if not ramp.is_empty():
		avoid.append(int(ramp["quadrant"]))
	var falls: Dictionary = sewer().falls_between(x, z)
	if not falls.is_empty():
		avoid.append(int(falls["quadrant"]))
	return Stairwells.plan(world_seed, x, z, upper_level, avoid,
		func(well: Dictionary) -> bool: return _maze_stairwell_fits(grid, layout, circulation, well, force),
		Stairwells.MAZE_AREAS if upper_level == 0 else Stairwells.MAZE_UP_AREAS, force)


## True when a stairwell's box (and a cell round it) touches no suite or main
## hall, it drops at most MAX_STAIRWELL_DROPPED_ROOM_CELLS of plain rooms, and a
## trial carve cuts no open area in two.
static func _maze_stairwell_fits(grid: Array, layout: Dictionary, circulation: Dictionary, well: Dictionary,
		relaxed: bool = false) -> bool:
	var reach: Rect2i = (well["box"] as Rect2i).grow(1)
	for suite_value in layout.get("suites", []):
		if ((suite_value as Dictionary).get("rect", Rect2i()) as Rect2i).intersects(reach):
			return false
	for corridor_value in layout.get("corridors", []):
		var corridor: Dictionary = corridor_value
		if String(corridor.get("id", "")).contains(":HALL:") and corridor.has("rect") \
				and (corridor["rect"] as Rect2i).intersects(well["box"]):
			return false
	var trial_grid := grid.duplicate(true)
	var trial_layout := {"rooms": (layout["rooms"] as Array).duplicate(), "suites": layout.get("suites", [])}
	_carve_stairwell(trial_grid, trial_layout, circulation.duplicate(), well, 0, {})
	# a plain room or two may give way (they go back to solid), not a whole bank of them
	var dropped := 0
	for room_value in layout["rooms"]:
		if not (trial_layout["rooms"] as Array).has(room_value):
			if not String((room_value as Dictionary).get("suite_id", "")).is_empty():
				return false
			dropped += ((room_value as Dictionary).get("rect", Rect2i()) as Rect2i).get_area()
	# a deck patch's only way up (relaxed) may take a second room's worth of floor
	if dropped > (MAX_FORCED_STAIRWELL_DROPPED_ROOM_CELLS if relaxed else MAX_STAIRWELL_DROPPED_ROOM_CELLS):
		return false
	# the well's walls must not pinch a hall or warren lane beside it under three wide
	var around := reach.grow(3).intersection(Rect2i(0, 0, CHUNK_SIZE, CHUNK_SIZE))
	if _narrow_open_cells(trial_grid, around, well["box"]) > _narrow_open_cells(grid, around, well["box"]):
		return false
	# nor leave a notch: a hall cell beside the box that was three wide must stay so without counting the well
	for z in range(around.position.y, around.end.y):
		for x in range(around.position.x, around.end.x):
			var cell := Rect2i(x, z, 1, 1)
			if _narrow_open_cells(trial_grid, cell, well["box"], well["box"]) > 0 \
					and (int(grid[z][x]) != 0 or _narrow_open_cells(grid, cell, Rect2i()) == 0):
				return false
	# the seams are carved later, so pockets may exist already: the carve must not add one
	return _open_components(trial_grid) <= _open_components(grid)


## Open cells in `area` (outside `box`) whose straight open run, `wall` counted as wall, is under three along either axis.
static func _narrow_open_cells(grid: Array, area: Rect2i, box: Rect2i, wall: Rect2i = Rect2i()) -> int:
	var count := 0
	for z in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if int(grid[z][x]) != 0 or box.has_point(Vector2i(x, z)):
				continue
			var runs := []
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var run := 1
				for sign in [1, -1]:
					var at: Vector2i = Vector2i(x, z) + step * sign
					while run < 3 and at.x >= 0 and at.y >= 0 and at.x < CHUNK_SIZE and at.y < CHUNK_SIZE and int(grid[at.y][at.x]) == 0 \
							and not wall.has_point(at):
						run += 1
						at += step * sign
				runs.append(run)
			if mini(runs[0], runs[1]) < 3:
				count += 1
	return count


static func _open_components(grid: Array) -> int:
	var seen := {}
	var count := 0
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if int(grid[z][x]) != 0 or seen.has(Vector2i(x, z)):
				continue
			count += 1
			seen[Vector2i(x, z)] = true
			var queue: Array[Vector2i] = [Vector2i(x, z)]
			while not queue.is_empty():
				var cell: Vector2i = queue.pop_back()
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cell + step
					if n.x < 0 or n.y < 0 or n.x >= CHUNK_SIZE or n.y >= CHUNK_SIZE or seen.has(n) or int(grid[n.y][n.x]) != 0:
						continue
					seen[n] = true
					queue.append(n)
	return count


## Every stairwell touching `level` in column (x, z) whose other end is on a
## level this world has (+1..+3 appear once the upper-levels lane allows them).
func stairwells_at(x: int, z: int, level: int) -> Array:
	var out := []
	for upper in [level, level + 1]:
		if not is_chunk_allowed(Vector3i(x, upper, z)) or not is_chunk_allowed(Vector3i(x, upper - 1, z)):
			continue
		var well := stairwell_between(x, z, upper)
		if not well.is_empty():
			out.append(well)
	return out


## Every ladder and ramp touching the chunk's level: ladders between the maze
## and the first sewer, ramps between the sewers and down into the Inferno.
## With `cached_only` the ladders are left out until the sewer chunk holding
## them is generated, so asking costs nothing on this thread (ramps are pure
## seed maths and always included).
func vertical_links(coord: Vector3i, cached_only: bool = false) -> Array:
	var out := []
	if VoidRegion.contains(world_seed, coord.x, coord.z):
		# the void has no ladders, ramps or maze stairwells: only the tower
		for well in stairwells_at(coord.x, coord.z, coord.y):
			out.append(well["link"])
		return out
	if coord.y == 0 or coord.y == SEWER_LEVEL:
		var ladder_coord := Vector3i(coord.x, SEWER_LEVEL, coord.z)
		if not cached_only or _chunk_cache.has(ladder_coord):
			out.append_array(sewer().links_for(coord))
	for ramp in sewer().ramps_at(coord.x, coord.z, coord.y):
		out.append(ramp["link"])
	# a maze <-> sewer stairwell is read from the maze chunk, like the ladders
	var maze_coord := Vector3i(coord.x, 0, coord.z)
	if coord.y not in [0, SEWER_LEVEL] or not cached_only or _chunk_cache.has(maze_coord):
		for well in stairwells_at(coord.x, coord.z, coord.y):
			out.append(well["link"])
	return out


## The sewer layer under the maze (SewerRouteGenerator). Built lazily: it reads
## the maze chunk above to place each ladder on clear hallway floor.
func mezzanine() -> MezzanineRouteGenerator:
	if _mezzanine == null:
		_mezzanine = MezzanineRouteGenerator.new(self)
	return _mezzanine


## The vents (VentNetwork) of the streamed levels: today the maze storey (level 0).
func vents() -> VentNetwork:
	if _vents == null:
		_vents = VentNetwork.new(self, [])
	return _vents


func sewer() -> SewerRouteGenerator:
	if _sewer == null:
		_sewer = SewerRouteGenerator.new(self)
	return _sewer


## Guarantee (PLAYTEST BUGS b): every pickup and relay can be walked to. A flood from the chunk's halls and seam openings
## over open cells that no solid prop occupies; a pickup the flood does not reach (sealed behind furniture or a partition,
## as the lab decon room did) moves to the nearest reached cell. Deterministic, so every peer agrees.
static func _ensure_pickups_reachable(data: Dictionary) -> void:
	var pickups: Array = data.get("pickups", [])
	if pickups.is_empty() or not data.has("grid"):
		return
	var grid: Array = data["grid"]
	var size := grid.size()
	var blocked := {}
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if not bool(prop.get("solid", true)) or bool(prop.get("room_door", false)):
			continue
		for cell in prop.get("occupied_cells", [prop.get("cell", Vector2i(-1, -1))]):
			blocked[cell] = true
	var open := func(c: Vector2i) -> bool:
		return c.x >= 0 and c.y >= 0 and c.x < size and c.y < size and int(grid[c.y][c.x]) == 0 and not blocked.has(c)
	var reached := {}
	var frontier: Array = []
	for i in size:
		for c in [Vector2i(i, 0), Vector2i(i, size - 1), Vector2i(0, i), Vector2i(size - 1, i), Vector2i(i, size / 2)]:
			if open.call(c) and not reached.has(c):
				reached[c] = true
				frontier.append(c)
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if open.call(n) and not reached.has(n):
				reached[n] = true
				frontier.append(n)
	if reached.is_empty():
		return
	for pickup_value in pickups:
		var pickup: Dictionary = pickup_value
		var cell: Vector2i = pickup.get("cell", Vector2i(-1, -1))
		if reached.has(cell):
			continue
		var seen := {cell: true}
		var queue: Array = [cell]
		var head := 0
		while head < queue.size():
			var cur: Vector2i = queue[head]
			head += 1
			if reached.has(cur):
				pickup["cell"] = cur
				break
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = cur + d
				if n.x >= 0 and n.y >= 0 and n.x < size and n.y < size and not seen.has(n):
					seen[n] = true
					queue.append(n)


func chunk(coord: Vector3i) -> Dictionary:
	if VoidRegion.is_void_chunk(world_seed, coord) or (coord.y == MEZZANINE_LEVEL and is_chunk_allowed(coord)):
		if _chunk_cache.has(coord):
			return _chunk_cache[coord]
		var mezzanine_data := mezzanine().chunk(coord)
		adopt_chunk(coord, mezzanine_data)
		return mezzanine_data
	if (coord.y == SEWER_LEVEL or coord.y == LOWER_SEWER_LEVEL) and is_chunk_allowed(coord):
		# one cache for every level, so a sewer chunk the view's worker thread built
		# (adopt_chunk) is reused here instead of being generated again
		if _chunk_cache.has(coord):
			return _chunk_cache[coord]
		var sewer_data := sewer().chunk(coord)
		adopt_chunk(coord, sewer_data)
		return sewer_data
	if _chunk_cache.has(coord):
		_chunk_cache_order.erase(coord)
		_chunk_cache_order.append(coord)
		return _chunk_cache[coord]
	var data := _build_chunk(coord)
	_ensure_pickups_reachable(data)
	_chunk_cache[coord] = data
	_chunk_cache_order.append(coord)
	while _chunk_cache_order.size() > CHUNK_CACHE_LIMIT:
		_chunk_cache.erase(_chunk_cache_order.pop_front())
	return data


func cached_chunk_count() -> int:
	return _chunk_cache.size()


func _dual_level_pair_active(_coord: Vector3i) -> bool:
	return false


func dual_level_room_spec(coord: Vector3i) -> Dictionary:
	if not _dual_level_pair_active(coord):
		return {}
	var lower_level := floori(float(coord.y) / 2.0) * 2
	var rng := SeededRandom.new("%s:DUAL-ROOM:%d:%d:%d" % [
		world_seed, coord.x, lower_level, coord.z])
	var sector := rng.next_index(4)
	var sector_position := Vector2i(24 if sector % 2 == 1 else 4,
		24 if sector >= 2 else 4)
	var rect := Rect2i(sector_position + Vector2i.ONE, Vector2i(15, 15))
	return {
		"id": "DUAL:%d:%d:%d" % [coord.x, lower_level, coord.z],
		"lower": Vector3i(coord.x, lower_level, coord.z),
		"upper": Vector3i(coord.x, lower_level + 1, coord.z),
		"role": "lower" if coord.y == lower_level else "upper",
		"sector": sector,
		"rect": rect,
		"interior": Rect2i(rect.position + Vector2i.ONE,
			rect.size - Vector2i(2, 2)),
		"height_floors": 2,
		"region": "carnival",
	}


func _apply_dual_level_room(coord: Vector3i, region: String, grid: Array,
		layout: Dictionary, spec: Dictionary, floor_voids: Array[Vector2i],
		ceiling_voids: Array[Vector2i],
		structural_voids: Array[Vector2i]) -> void:
	var rect: Rect2i = spec.get("rect", Rect2i())
	var interior: Rect2i = spec.get("interior", Rect2i())
	var sector := int(spec.get("sector", 0))
	var rooms: Array = layout.get("rooms", [])
	var removed_suite_ids := {}
	for index in range(rooms.size() - 1, -1, -1):
		var existing_room: Dictionary = rooms[index]
		var existing: Rect2i = existing_room.get("rect", Rect2i())
		if existing.intersects(rect):
			var suite_id := String(existing_room.get("suite_id", ""))
			if not suite_id.is_empty():
				removed_suite_ids[suite_id] = true
			rooms.remove_at(index)
	var corridors: Array = layout.get("corridors", [])
	for index in range(corridors.size() - 1, -1, -1):
		var corridor: Dictionary = corridors[index]
		var corridor_id := String(corridor.get("id", ""))
		if corridor_id.ends_with(":HALL:%d" % sector) \
				or removed_suite_ids.has(String(corridor.get("suite_id", ""))):
			corridors.remove_at(index)
	var suites: Array = layout.get("suites", [])
	for index in range(suites.size() - 1, -1, -1):
		if removed_suite_ids.has(String((suites[index] as Dictionary).get("id", ""))):
			suites.remove_at(index)
	if String(spec.get("role", "")) == "lower":
		_carve_rect(grid, rect)
		var rng := SeededRandom.new("%s:DUAL-CONNECTION" % String(spec.get("id", "")))
		var circulation: Dictionary = layout.get("circulation", {})
		var connection := _connect_room_to_main_hall(grid, circulation, rect,
			sector, rng)
		corridors.append({
			"id": "%s:DUAL-HALL" % chunk_id(coord),
			"axis": String(connection["axis"]),
			"width": CORRIDOR_WIDTH,
			"length": int(connection["length"]),
			"branch": true,
			"from_main_hall": true,
			"serves_many_rooms": false,
			"doorway": connection["doorway"],
		})
		var room := _room_entry(coord, rooms.size(), region, rect, "big_top")
		room["doorway"] = connection["doorway"]
		room["height_floors"] = 2
		room["vertical_role"] = "lower"
		room["vertical_pair_id"] = String(spec.get("id", ""))
		rooms.append(room)
		for z in range(interior.position.y, interior.end.y):
			for x in range(interior.position.x, interior.end.x):
				ceiling_voids.append(Vector2i(x, z))
	else:
		# The upper half is air, not a second walkable room and not a column of
		# wall cubes. The renderer uses structural_voids to omit the GridMap cell
		# while still placing the upper floor's ceiling as the room's final cap.
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				grid[z][x] = 1
		for z in range(interior.position.y, interior.end.y):
			for x in range(interior.position.x, interior.end.x):
				var cell := Vector2i(x, z)
				floor_voids.append(cell)
				structural_voids.append(cell)


func _build_chunk(coord: Vector3i) -> Dictionary:
	if not is_chunk_allowed(coord):
		return {"schema": 2, "coord": coord, "chunk_id": chunk_id(coord),
			"biome": "sealed", "region": "sealed", "rooms": [], "corridors": [],
			"suites": [],
			"grid": _solid_grid(), "edges": {"west": [], "east": [],
				"north": [], "south": []}, "stairs": [], "safe_room": false,
			"safe_room_data": {}, "region_props": [], "fixtures": [],
			"pickups": [], "hunter_spawns": [], "dual_level_room": {},
			"floor_voids": [], "ceiling_voids": [], "structural_voids": [],
			"difficulty": difficulty_for_level(coord.y)}
	var grid := _solid_grid()
	var region := region_for(coord)
	# Vertical links participate in room planning. When layout ran first, its
	# rooms could be carved directly through the later stair footprint.
	var stairs := stair_links(coord)
	# Level -3 is a cave network, not a maze: no rooms, halls or doorways to plan (InfernoCaverns).
	var layout := {"rooms": [], "corridors": [], "suites": [], "circulation": {}} if coord.y == INFERNO_LEVEL \
		else _region_layout(coord, region, grid, stairs)
	var dual_level := dual_level_room_spec(coord)
	var floor_voids: Array[Vector2i] = []
	var ceiling_voids: Array[Vector2i] = []
	var structural_voids: Array[Vector2i] = []
	if not dual_level.is_empty():
		_apply_dual_level_room(coord, region, grid, layout, dual_level,
			floor_voids, ceiling_voids, structural_voids)
	# This mask is presentation-independent circulation space: central halls,
	# room connectors, chunk seams and stair approaches. Solid dressing must
	# never consume it, even though all of those cells are ordinary floor in the
	# structural GridMap.
	var circulation: Dictionary = layout.get("circulation", {})
	var edges := {
		"west": edge_openings(coord, Vector2i(-1, 0)),
		"east": edge_openings(coord, Vector2i(1, 0)),
		"north": edge_openings(coord, Vector2i(0, -1)),
		"south": edge_openings(coord, Vector2i(0, 1)),
	}
	var ramps: Array = sewer().ramps_at(coord.x, coord.z, coord.y) if coord.y == INFERNO_LEVEL else []
	var inferno_caverns := []
	var breakables: Array = []
	var sealed_cells := {}
	var cave_tunnels: Array = []
	if coord.y == INFERNO_LEVEL:
		inferno_caverns = InfernoCaverns.carve(world_seed, coord, grid, edges, ramps, is_safe_room(coord), circulation, cave_tunnels)
		for ramp in ramps:
			_carve_ramp_bottom(grid, layout, circulation, ramp)
			# the landing's 3x3 reaches the chunk's edge column, which the shared carve leaves as one brick cell
			for part in ["bottom", "connector"]:
				for z in range((ramp[part] as Rect2i).position.y, (ramp[part] as Rect2i).end.y):
					for x in range((ramp[part] as Rect2i).position.x, (ramp[part] as Rect2i).end.x):
						if x == 0 or x == CHUNK_SIZE - 1:
							grid[z][x] = 0
		# lava is rock to the walk grid but no wall and no floor to the view
		for pit in InfernoCaverns.pits_in({"inferno_caverns": inferno_caverns}):
			for cell in pit["lava"]:
				floor_voids.append(cell)
				structural_voids.append(cell)
	else:
		var wide_seams := {}
		for side in edges:
			wide_seams[side] = wide_seam(coord, {"west": Vector2i(-1, 0), "east": Vector2i(1, 0), "north": Vector2i(0, -1),
				"south": Vector2i(0, 1)}[side])
		var edge_corridors := _carve_edges(grid, edges, layout["rooms"], circulation, DENSE_DISTRICTS.has(region), wide_seams)
		(layout["corridors"] as Array).append_array(edge_corridors)
		for stair in stairs:
			_carve_stair_access(grid, stair, layout["rooms"], circulation)
	var wells := []
	if coord.y == 0:
		var down := _plan_maze_stairwell(coord.x, coord.z, grid, layout, circulation)
		if not down.is_empty():
			wells.append(down)
		if is_chunk_allowed(Vector3i(coord.x, MEZZANINE_LEVEL, coord.z)) and not is_void_column(coord):
			# the way up to the deck patch above this chunk is decided here too, in a different quadrant from the way down;
			# a patch with no well yet forces one here (DeckPatches)
			var avoid_down: Array = [int(down["quadrant"])] if not down.is_empty() else []
			var up := _plan_maze_stairwell(coord.x, coord.z, grid, layout, circulation, MEZZANINE_LEVEL, avoid_down)
			if up.is_empty() and _deck_needs_well(coord):
				up = _plan_maze_stairwell(coord.x, coord.z, grid, layout, circulation, MEZZANINE_LEVEL, avoid_down, true)
			if not up.is_empty():
				wells.append(up)
	var shaft_cells := {}
	for well in wells:
		_carve_stairwell(grid, layout, circulation, well, coord.y, shaft_cells)
	# Perimeter seams and stair approaches are carved after the room banks. They
	# must never punch a second opening through a room which already owns one
	# canonical branch doorway. Rebuild each ordinary room's boundary now that
	# all shared circulation is known; stairwell rooms retain their wide flights.
	_restore_single_room_thresholds(grid, layout["rooms"])
	var safe := is_safe_room(coord)
	if safe:
		_carve_safe_room(grid)
	var region_props := _region_props(coord, region, layout["rooms"], grid, safe,
		stairs, circulation)
	if coord.y == INFERNO_LEVEL:
		region_props.append_array(_cave_props(coord, inferno_caverns, grid, ramps))
	# Safe-lobby carving and door-frame planning are the final topology-aware
	# operations. Reassert every room threshold afterwards so a central safe
	# square or overlapping suite perimeter cannot reopen a diagonal corner.
	# Canonical doorway cells remain open, including the suite's shared entrance
	# and each amenity room's own internal door.
	_restore_single_room_thresholds(grid, layout["rooms"])
	# Double doors deliberately widen a room's canonical one-cell threshold to
	# two adjacent cells. The perimeter restoration above must run after room
	# dressing, but it cannot be allowed to re-seal the second leaf's lane.
	_restore_authored_room_door_thresholds(grid, region_props)
	if REMOVE_HUMPS:
		_remove_wall_humps(grid, layout["rooms"], region_props)
	# Props a few centimetres inside a wall slide clear of it first (GeometryAudit prop_in_wall), then the walkway checks run.
	region_props = GeometryResolve.push_out(grid, region_props)
	scale_surface_mounts(region_props)
	# Keep-clear zones at every door and a margin-wide walk from each door into its room (docs/COLLISION.md).
	if clear_walkways:
		region_props = PlacementClearance.clear(grid, layout["rooms"], region_props)
	var fixtures := _fixtures(coord, grid, layout["rooms"], stairs,
		region_props, safe)
	fixtures.append_array(_prop_hiding_fixtures(coord, region_props, safe))
	# Sealed wings (SealPlanner) are planned on the finished grid, then relays and tools are placed against them.
	if coord.y == INFERNO_LEVEL and not safe:
		var seal_plan := SealPlanner.plan_cave(world_seed, coord, grid, inferno_caverns, cave_tunnels)
		breakables = SealPlanner.specs(world_seed, coord, seal_plan, coord.y)
		for cell in seal_plan["sealed"]:
			sealed_cells[cell] = true
	var pickups := _pickups(coord, grid, stairs, safe, region_props, fixtures, sealed_cells)
	var music_boxes := _music_boxes(coord, grid, stairs, safe, region_props, fixtures, pickups)
	var hunters := _hunter_spawns(coord, grid, stairs, safe, region_props)
	return {
		"schema": 2,
		"coord": coord,
		"chunk_id": chunk_id(coord),
		"biome": region,   # deprecated alias of "region" for branches written before the rename; nothing here reads it
		"region": region,
		"rooms": layout["rooms"],
		"warren": layout.get("warren", {}),
		"corridors": layout["corridors"],
		"suites": layout.get("suites", []),
		"difficulty": difficulty_for_level(coord.y),
		"grid": grid,
		"edges": edges,
		"stairs": stairs,
		"safe_room": safe,
		"safe_room_data": safe_room_data(coord) if safe else {},
		"region_props": region_props,
		"fixtures": fixtures,
		"pickups": pickups,
		"music_boxes": music_boxes,
		"hunter_spawns": hunters,
		"dual_level_room": dual_level,
		"floor_voids": floor_voids,
		"ceiling_voids": ceiling_voids,
		"structural_voids": structural_voids,
		"ramps": ramps,
		"ramp_cells": sewer().ramp_cells(coord.x, coord.z, coord.y) if coord.y == INFERNO_LEVEL else {},
		"inferno_caverns": inferno_caverns,
		"landing_pile": _landing_pile(coord, grid, inferno_caverns, ramps),
		"breakables": breakables,
		"sealed_cells": sealed_cells.keys(),
		"stairwells": wells,
		"shaft_cells": shaft_cells,
	}


## A stairwell in a maze chunk: rooms its footprint or corridor would cut are
## dropped, the walled box goes back to solid, then its landing, doorway and a
## three-wide corridor to the central hall open. The well itself stays off the
## walk grid (the stairs are walked as a link); `shaft_cells` tells the view.
static func _carve_stairwell(grid: Array, layout: Dictionary, circulation: Dictionary, well: Dictionary,
		level: int, shaft_cells: Dictionary) -> void:
	var box: Rect2i = well["box"]
	# the corridor starts at the doorway and runs on below until it meets floor
	var door_row: int = (well["door"] as Rect2i).position.y
	var lane := Stairwells.corridor(well, door_row + 1 if bool(well["north"]) else door_row - 1)
	var kept := []
	for room_value in layout["rooms"]:
		var rect: Rect2i = (room_value as Dictionary).get("rect", Rect2i())
		if rect.grow(1).intersects(box) or rect.intersects(lane):
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					grid[z][x] = 1
		else:
			kept.append(room_value)
	layout["rooms"] = kept
	for z in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			grid[z][x] = 1
	var cells := Stairwells.cells_for(well, level)
	for cell in cells["walk"]:
		grid[cell.y][cell.x] = 0
	# Carry the corridor on, a row at a time, until it opens onto floor that was
	# already there (normally the main hall right outside the doorway). A room in the way is dropped
	# like the ones under the box, so none gets a second doorway.
	var outward := 1 if bool(well["north"]) else -1
	var row := lane.end.y if outward > 0 else lane.position.y - 1
	while row > 0 and row < CHUNK_SIZE - 1:
		var step := Rect2i(lane.position.x, row, lane.size.x, 1)
		var still := []
		for room_value in layout["rooms"]:
			var rect: Rect2i = (room_value as Dictionary).get("rect", Rect2i())
			if rect.grow(1).intersects(step):
				for z in range(rect.position.y, rect.end.y):
					for x in range(rect.position.x, rect.end.x):
						grid[z][x] = 1
			else:
				still.append(room_value)
		layout["rooms"] = still
		var open := false
		for x in range(step.position.x, step.end.x):
			if int(grid[row][x]) == 0:
				open = true
		if open:
			# the row it meets is opened all three wide, so no wall cell is left in front of the door
			_carve_rect(grid, step)
			_mark_rect_cells(circulation, step)
			break
		lane = lane.merge(step)
		row += outward
	_carve_rect(grid, lane)
	_mark_rect_cells(circulation, lane)
	for cell in cells["shaft"]:
		shaft_cells[cell] = {"upper": level == int(well["upper"]), "well": well}


## The bottom of a ramp down from the collector sewer into an Inferno chunk: the
## ramp's footprint, its landing and a three-wide connector to the central hall.
## Rooms the footprint would cut through are dropped (their cells go back to
## solid first) so no half-room is left with a hole in it.
static func _carve_ramp_bottom(grid: Array, layout: Dictionary, circulation: Dictionary, ramp: Dictionary) -> void:
	var footprint: Array[Rect2i] = [ramp["ramp"], ramp["bottom"], ramp["connector"]]
	var kept := []
	for room_value in layout["rooms"]:
		var rect: Rect2i = (room_value as Dictionary).get("rect", Rect2i())
		var hit := false
		for part in footprint:
			if rect.grow(1).intersects(part):
				hit = true
		if hit:
			for z in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					grid[z][x] = 1
		else:
			kept.append(room_value)
	layout["rooms"] = kept
	_carve_rect(grid, ramp["bottom"])
	_carve_rect(grid, ramp["connector"])
	_mark_rect_cells(circulation, ramp["bottom"])
	_mark_rect_cells(circulation, ramp["connector"])
	var slope: Rect2i = ramp["ramp"]
	for z in range(slope.position.y, slope.end.y):
		for x in range(slope.position.x, slope.end.x):
			grid[z][x] = 1      # the slope itself is reached only as a ramp link


## The breakable spec with this id (Breach.make_id), or {}: found by regenerating its chunk, so a guest can name it.
func breakable_by_id(id: String) -> Dictionary:
	var parsed := Breach.parse_id(id)
	if parsed.is_empty() or not is_chunk_allowed(parsed["chunk"]):
		return {}
	var list: Array = chunk(parsed["chunk"]).get("breakables", [])
	var index := int(parsed["index"])
	if index >= 0 and index < list.size() and String((list[index] as Dictionary).get("id", "")) == id:
		return list[index]
	# the index is an id, not a position: a sewer chunk lists its pipes (ids from 0) before its seals (ids from 100), so a
	# seal's index ran off the end of the list and the host dropped every hit on it (KT: "with crowbar, doesnt work")
	for spec in list:
		if String((spec as Dictionary).get("id", "")) == id:
			return spec
	return {}


## The caverns carved into a level -3 chunk ({"rect", "cells", "halls", "crevices"} each); [] elsewhere.
func inferno_caverns_at(coord: Vector3i) -> Array:
	if coord.y != INFERNO_LEVEL or not is_chunk_allowed(coord):
		return []
	return chunk(coord).get("inferno_caverns", [])


## Where something dropped into the Inferno lands: a chunk-local walkable cell with a clear 3x3, in the chunk's main
## cavern or a 5-wide hall (otherwise its clearest open ground). (-1, -1) if the chunk has none.
## Chunk coordinates (level -3) that must show a landing pile because something is dumped into them (the dump holes of the
## level above fill this); any other chunk shows one for a share of its caves.
var dump_landing_chunks := {}
const LANDING_PILE_SHARE := .3


func dump_landing(coord: Vector3i) -> Vector2i:
	if coord.y != INFERNO_LEVEL or not is_chunk_allowed(coord):
		return Vector2i(-1, -1)
	return InfernoCaverns.landing(chunk(coord))



## Deprecated pre-rename name, kept until the other lanes' branches have landed; use region_for().
func biome_for(coord: Vector3i) -> String:
	return region_for(coord)

func region_for(coord: Vector3i) -> String:
	if VoidRegion.is_void_chunk(world_seed, coord):
		return "mezzanine"
	if coord.y == SEWER_LEVEL or coord.y == LOWER_SEWER_LEVEL:
		return "sewer"
	# The Inferno is no longer a district of the maze: it is the whole level under
	# the sewers, and only there.
	if coord.y == INFERNO_LEVEL:
		return "inferno"
	# A two-storey room owns one visual identity on both participating floors.
	# Resolve this before ordinary region choice so walls, props and the upper cap
	# never change theme halfway up a carousel or other tall landmark.
	if _dual_level_pair_active(coord):
		return "carnival"
	# Four-by-four regions read as facility regions rather than every doorway
	# changing material language. Level participates so a stair can lead into a
	# visibly different wing without destabilising horizontal neighbours.
	var region_x := floori(float(coord.x) / REGION_SIZE_CHUNKS)
	var region_z := floori(float(coord.z) / REGION_SIZE_CHUNKS)
	# "BIOME" is part of the seed, not a name: changing it would move every region (kept through the rename).
	var rng := SeededRandom.new("%s:BIOME:%d:%d:%d" % [
		world_seed, region_x, coord.y, region_z])
	var choices := ["maze", "mansion", "hotel", "apartment", "beach", "gothic",
		"prison", "carnival", "mansion", "hotel", "maze",
		"hospital", "lab", "lab", "greenhouse", "mall"]
	if coord.y == 0:
		if region_x == 0 and region_z == 0:
			# KT: "make the maze the most common spawn point". The run starts in chunk (0, 0, 0), so the region around it is
			# the maze SPAWN_MAZE_SHARE of the time, else any other level-0 region (the safe-spawn room is unchanged).
			var spawn_rng := SeededRandom.new("%s:SPAWN-REGION" % world_seed)
			if spawn_rng.next_float() < SPAWN_MAZE_SHARE:
				return "maze"
			var others := choices.filter(func(choice: String) -> bool: return choice != "maze")
			return others[spawn_rng.next_index(others.size())]
		return choices[rng.next_index(choices.size())]
	# Upper levels remain recognizable and forgiving. Gothic wings begin below
	# the central floor; Inferno is a deep-only region and can never leak upward.
	if coord.y <= -1:
		choices.append("gothic")
		choices.append("gothic")
	if coord.y <= -2:
		choices.append("prison")
		choices.append("prison")
	if coord.y <= -3:
		choices.append("inferno")
		choices.append("inferno")
		if coord.y <= -6:
			choices.append("inferno")
	if coord.y >= 2:
		choices.append("hotel")
		choices.append("apartment")
		choices.append("beach")
	elif coord.y >= 0:
		choices.append("beach")
	return choices[rng.next_index(choices.size())]


func difficulty_for_level(level: int) -> Dictionary:
	# Zero is the central arrival floor. Positive levels relax toward a floor,
	# while every step downward adds pursuit pressure without a hard depth cap.
	var danger := clampf(0.48 - float(level) * 0.075, 0.12, 1.0)
	return {
		"level": level,
		"danger": danger,
		"hunter_speed_scale": lerpf(0.86, 1.28, danger),
		"hunter_count_bias": floori(maxf(0.0, -float(level)) / 3.0),
		"safe_room_bias": lerpf(1.45, 0.55, danger),
	}


var _large_cache := {}
var _base_large_cache := {}


## Which sides of this chunk hold a great hall: {"W": room_type or "", "E": room_type or ""}. Pure function of the seed and
## the chunk, so every peer and both chunks at a seam agree.
func large_plan(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if _large_cache.has(key):
		return _large_cache[key]
	var plan := _base_large_plan(coord).duplicate()
	# the music wing takes BOTH great-hall slots of a hotel chunk or none (MusicWing)
	if _wing_roll(coord):
		var both := true
		for dx in [-1, 1]:
			var next_door := coord + Vector3i(dx, 0, 0)
			both = both and is_chunk_allowed(next_door) and DENSE_DISTRICTS.has(region_for(next_door)) \
				and not _wing_roll(next_door) and String(_base_large_plan(next_door)["E" if dx < 0 else "W"]).is_empty()
		if both:
			plan["W"] = MusicWing.LARGE_TYPE
			plan["E"] = MusicWing.LARGE_TYPE
	_large_cache[key] = plan
	return plan


## The ordinary great-hall slots of a chunk (no music wing); pure, so the wing can look at its neighbours without recursing.
func _base_large_plan(coord: Vector3i) -> Dictionary:
	var key := chunk_id(coord)
	if _base_large_cache.has(key):
		return _base_large_cache[key]
	var plan := {"W": "", "E": ""}
	var region := region_for(coord) if is_chunk_allowed(coord) else ""
	if LARGE_ROOM_CHANCE.has(region) and not is_safe_room(coord) and not is_warren_chunk(coord):
		var rng := SeededRandom.new("%s:LARGE:%s" % [world_seed, key])
		var types: Array = LARGE_ROOM_TYPES[region]
		for side in ["W", "E"]:
			var roll := rng.next_float()
			var type_index := rng.next_index(types.size())
			if roll >= float(LARGE_ROOM_CHANCE[region]):
				continue
			if region == "maze" and side == "E":
				continue   # the office suite owns the south-east quarter
			var neighbour := coord + Vector3i(-1 if side == "W" else 1, 0, 0)
			if not is_chunk_allowed(neighbour) or not DENSE_DISTRICTS.has(region_for(neighbour)):
				continue
			plan[side] = String(types[type_index])
	_base_large_cache[key] = plan
	return plan


## The raw roll for a music wing at this chunk: a hotel chunk, its own roll (so the other plans are unchanged).
func _wing_roll(coord: Vector3i) -> bool:
	if not is_chunk_allowed(coord) or not MUSIC_WING_REGIONS.has(region_for(coord)) or is_safe_room(coord) \
			or is_warren_chunk(coord):
		return false
	return SeededRandom.new("%s:MUSICWING:%s" % [world_seed, chunk_id(coord)]).next_float() < MUSIC_WING_CHANCE


## True when the middle east-west hall is cut short on this chunk's west (dx -1) or east (dx +1) end: its own great hall
## there, or the neighbour's across the seam.
func hall_trimmed(coord: Vector3i, dx: int) -> bool:
	var neighbour := coord + Vector3i(dx, 0, 0)
	if not DENSE_DISTRICTS.has(region_for(coord)):
		return false
	var mine: String = String(large_plan(coord)["W" if dx < 0 else "E"])
	var theirs := ""
	if is_chunk_allowed(neighbour) and DENSE_DISTRICTS.has(region_for(neighbour)):
		theirs = String(large_plan(neighbour)["E" if dx < 0 else "W"])
	return not mine.is_empty() or not theirs.is_empty()


func edge_openings(coord: Vector3i, direction: Vector2i) -> Array:
	var neighbour := coord + Vector3i(direction.x, 0, direction.y)
	if not is_chunk_allowed(coord) or not is_chunk_allowed(neighbour):
		return []
	# Every seam meets the centre cross of both chunks (an off-centre seam needs a perimeter lane, and the lanes of two
	# neighbouring chunks run as a double line beside the border). Hotel/prison chunks side by side also pass their two
	# extra halls through the seam.
	if DENSE_DISTRICTS.has(region_for(coord)) and DENSE_DISTRICTS.has(region_for(neighbour)) and direction.x != 0:
		var openings := [10, CHUNK_SIZE / 2, 34]   # all three halls run on through the seam
		if hall_trimmed(coord, direction.x):
			openings.erase(CHUNK_SIZE / 2)   # a great hall stands where the middle hall would cross
		return openings
	return [CHUNK_SIZE / 2]


## Maze chunks on both sides of a seam: their five-wide centre halls meet through a five-wide opening. Symmetric, so
## both chunks carve the same gap.
func wide_seam(coord: Vector3i, direction: Vector2i) -> bool:
	var neighbour := coord + Vector3i(direction.x, 0, direction.y)
	return is_chunk_allowed(coord) and is_chunk_allowed(neighbour) and biome_for(coord) == "maze" \
		and biome_for(neighbour) == "maze"


## The route is a single level: no stair links exist, so no chunk has a
## stairwell, floor void or ceiling void.
func stair_links(_coord: Vector3i) -> Array:
	return []


func is_safe_room(coord: Vector3i) -> bool:
	if coord == Vector3i.ZERO:
		return true
	var rng := SeededRandom.new("%s:SAFE:%d:%d:%d" % [
		world_seed, coord.x, coord.y, coord.z])
	var profile := difficulty_for_level(coord.y)
	# The shared PUBLIC route has no lobby to retreat to, so checkpoints are spread
	# through the infinite map: each chunk rolls its own deterministic chance, the
	# same on every client, and none of them is large enough to seal a wing off.
	var chance := 0.22 if public_route else 0.055 * float(profile["safe_room_bias"])
	return rng.next_float() < chance


func safe_room_data(coord: Vector3i) -> Dictionary:
	var danger := float(difficulty_for_level(coord.y)["danger"])
	return {
		"id": "%s:SAFE" % chunk_id(coord),
		"checkpoint_id": "%s:CHECKPOINT" % chunk_id(coord),
		"max_integrity": 100,
		"breachable": true,
		"repairable": true,
		"breach_pressure": snappedf(lerpf(0.55, 1.65, danger), 0.01),
	}


func spawn_chunk() -> Vector3i:
	return Vector3i.ZERO


func spawn_cell() -> Vector2i:
	return Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)


func is_chunk_allowed(coord: Vector3i) -> bool:
	# One maze level (y == 0), unbounded horizontally, over the sewer layer; level +1 only where a deck patch or the void is.
	if coord.y == MEZZANINE_LEVEL:
		return VoidRegion.contains(world_seed, coord.x, coord.z) or DeckPatches.is_deck(world_seed, coord.x, coord.z)
	return coord.y <= 0 and coord.y >= INFERNO_LEVEL


var _deck_component_cache := {}


## The deck chunks joined to (x, z) through shared edges (4-neighbours), capped, in a fixed order: the patch it belongs to.
func deck_component(x: int, z: int) -> Array:
	var key := Vector2i(x, z)
	if _deck_component_cache.has(key):
		return _deck_component_cache[key]
	var members: Array[Vector2i] = []
	var seen := {key: true}
	var queue: Array[Vector2i] = [key]
	while not queue.is_empty() and members.size() < DECK_PATCH_CAP:
		var cell: Vector2i = queue.pop_front()
		members.append(cell)
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if not seen.has(next) and DeckPatches.is_deck(world_seed, next.x, next.y):
				seen[next] = true
				queue.append(next)
	# a fixed per-chunk order (hash), the same from every member of the patch
	members.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return SeededRandom.new("%s:DECKRANK:%d:%d" % [world_seed, a.x, a.y]).next_float() \
			< SeededRandom.new("%s:DECKRANK:%d:%d" % [world_seed, b.x, b.y]).next_float())
	for member in members:
		_deck_component_cache[member] = members
	return members


const DECK_PATCH_CAP := 60


## True when no earlier-ranked chunk of this chunk's deck patch has a way up: then this chunk must have one. Earlier chunks
## are built first (strictly earlier ranks, so no cycle).
func _deck_needs_well(coord: Vector3i) -> bool:
	for member in deck_component(coord.x, coord.z):
		if member == Vector2i(coord.x, coord.z):
			return true
		if not stairwell_between(member.x, member.y, MEZZANINE_LEVEL).is_empty():
			return false
	return true


## True for a chunk column inside the Mezzanine void's footprint (VoidRegion): no maze, sewer or Inferno chunk is made there.
func is_void_column(coord: Vector3i) -> bool:
	return VoidRegion.contains(world_seed, coord.x, coord.z)


func coordinates_around(world_xz: Vector2, level: int, radius: int = 2) -> Array:
	var center := Vector2i(floori(world_xz.x / CHUNK_SIZE),
		floori(world_xz.y / CHUNK_SIZE))
	var result := []
	for z in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			var coord := Vector3i(x, level, z)
			if is_chunk_allowed(coord):
				result.append(coord)
	return result


func chunk_id(coord: Vector3i) -> String:
	return "%d:%d:%d" % [coord.x, coord.y, coord.z]


func pickup_id(coord: Vector3i, index: int, kind: String = "tool") -> String:
	# Stable entity ids are the authority key for "one pickup, one winner".
	# The future host mutation store records these ids after collection; clients
	# never infer ownership from whether a mesh is currently loaded.
	return "%s:PICKUP:%s:%d" % [chunk_id(coord), kind.to_upper(), index]


func hunter_id(coord: Vector3i, index: int) -> String:
	return "%s:HUNTER:%d" % [chunk_id(coord), index]


func _solid_grid() -> Array:
	var grid := []
	for z in CHUNK_SIZE:
		var row := []
		row.resize(CHUNK_SIZE)
		row.fill(1)
		grid.append(row)
	return grid


func _carve_edges(grid: Array, edges: Dictionary, rooms: Array,
		circulation: Dictionary = {}, dense: bool = false, wide_seams: Dictionary = {}) -> Array:
	var corridors := []
	var center := CHUNK_SIZE / 2
	for side in ["west", "east", "north", "south"]:
		for offset_value in edges[side]:
			var offset := int(offset_value)
			var start := Vector2i(1, offset)
			match side:
				"east":
					start = Vector2i(CHUNK_SIZE - 2, offset)
				"north":
					start = Vector2i(offset, 1)
				"south":
					start = Vector2i(offset, CHUNK_SIZE - 2)
			if dense and (side == "west" or side == "east") and offset != CHUNK_SIZE / 2:
				# a dense chunk's side halls already reach the border: just open the seam, no lane
				for spread in range(-1, 2):
					grid[offset + spread][0 if side == "west" else CHUNK_SIZE - 1] = 0
				continue
			var reach := 2 if bool(wide_seams.get(side, false)) and offset == CHUNK_SIZE / 2 else 1
			for spread in range(-reach, reach + 1):
				if side == "west":
					grid[offset + spread][0] = 0
				elif side == "east":
					grid[offset + spread][CHUNK_SIZE - 1] = 0
				elif side == "north":
					grid[0][offset + spread] = 0
				else:
					grid[CHUNK_SIZE - 1][offset + spread] = 0
			# Enter an outer three-wide lane first, then join the canonical central
			# cross. Routing a seam straight to a room centre used to cut across
			# unrelated rooms and merge most of a chunk into one irregular blob.
			var lane := start
			var junction := Vector2i(center, center)
			if side == "west" or side == "east":
				lane.x = 2 if side == "west" else CHUNK_SIZE - 3
				var hall_entry := Vector2i(lane.x, center)
				_carve_corridor_segment(grid, circulation, start, lane)
				_carve_corridor_segment(grid, circulation, lane, hall_entry)
				_carve_corridor_segment(grid, circulation, hall_entry, junction)
			else:
				lane.y = 2 if side == "north" else CHUNK_SIZE - 3
				var hall_entry := Vector2i(center, lane.y)
				_carve_corridor_segment(grid, circulation, start, lane)
				_carve_corridor_segment(grid, circulation, lane, hall_entry)
				_carve_corridor_segment(grid, circulation, hall_entry, junction)
			corridors.append({
				"id": "EDGE:%s:%d" % [side, offset],
				"axis": side,
				"from_perimeter": true,
				"room_id": "",
				"width": CORRIDOR_WIDTH,
				"length": absi(start.x - junction.x) + absi(start.y - junction.y),
			})
	return corridors


static func _carve_corridor_segment(grid: Array, circulation: Dictionary,
		from: Vector2i, to: Vector2i) -> void:
	_carve_corridor(grid, from, to, CORRIDOR_WIDTH)
	_mark_corridor_cells(circulation, from, to, CORRIDOR_WIDTH)


func _nearest_perimeter_room(rooms: Array, side: String,
		offset: int) -> Dictionary:
	var chosen := {}
	var best_score := INF
	for room_value in rooms:
		var room: Dictionary = room_value
		if String(room.get("room_type", "")) == "lobby":
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		if rect.size.x <= 0 or rect.size.y <= 0:
			continue
		var anchor := rect.position + rect.size / 2
		var edge_distance := 0
		var cross_distance := 0
		match side:
			"west":
				anchor = Vector2i(rect.position.x,
					clampi(offset, rect.position.y + 1, rect.end.y - 2))
				edge_distance = rect.position.x
				cross_distance = absi(offset - anchor.y)
			"east":
				anchor = Vector2i(rect.end.x - 1,
					clampi(offset, rect.position.y + 1, rect.end.y - 2))
				edge_distance = CHUNK_SIZE - rect.end.x
				cross_distance = absi(offset - anchor.y)
			"north":
				anchor = Vector2i(clampi(offset, rect.position.x + 1,
					rect.end.x - 2), rect.position.y)
				edge_distance = rect.position.y
				cross_distance = absi(offset - anchor.x)
			"south":
				anchor = Vector2i(clampi(offset, rect.position.x + 1,
					rect.end.x - 2), rect.end.y - 1)
				edge_distance = CHUNK_SIZE - rect.end.y
				cross_distance = absi(offset - anchor.x)
		var score := edge_distance * 4 + cross_distance
		if score < best_score:
			best_score = score
			chosen = {"anchor": anchor, "room_id": String(room.get("id", ""))}
	return chosen


static func stair_path_cells(cell: Vector2i) -> Array[Vector2i]:
	var center := Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2)
	var delta := center - cell
	var direction := Vector2i(signi(delta.x), 0) \
		if abs(delta.x) >= abs(delta.y) else Vector2i(0, signi(delta.y))
	var result: Array[Vector2i] = []
	for index in range(STAIR_RUN_CELLS + 1):
		result.append(cell + direction * index)
	return result


static func stair_bay_index(cell: Vector2i) -> int:
	return (1 if cell.x > CHUNK_SIZE / 2 else 0) \
		+ (2 if cell.y > CHUNK_SIZE / 2 else 0)


static func stair_access_cells(cell: Vector2i) -> Array[Vector2i]:
	var path := stair_path_cells(cell)
	var result: Array[Vector2i] = []
	var occupied := {}
	var travel := path[1] - path[0] if path.size() > 1 else Vector2i.RIGHT
	var across := Vector2i(-travel.y, travel.x)
	for path_cell in path:
		for offset in range(-STAIR_ACCESS_WIDTH / 2, STAIR_ACCESS_WIDTH / 2 + 1):
			var cell_at: Vector2i = path_cell + across * offset
			if occupied.has(cell_at):
				continue
			occupied[cell_at] = true
			result.append(cell_at)
	return result


func _carve_stair_access(grid: Array, stair: Dictionary, rooms: Array,
		circulation: Dictionary = {}) -> void:
	var cell: Vector2i = stair.get("cell", Vector2i.ZERO)
	var path := stair_path_cells(cell)
	# The visible flight and its smooth collision ramp occupy the full path at
	# almost two cells wide. Carve that footprint explicitly before connecting
	# it to the room network; a generic cell-to-room corridor can turn away from
	# the flight and leave a solid wall halfway up it.
	for path_cell in path:
		_carve_corridor_cell(grid, path_cell, STAIR_ACCESS_WIDTH)
		_mark_corridor_cell(circulation, path_cell, STAIR_ACCESS_WIDTH)
	var connector: Vector2i = path[0] if String(stair.get("direction", "")) == "up" \
		else path[-1]
	var center := CHUNK_SIZE / 2
	# Join the nearest arm of the same three-wide hall cross as rooms and chunk
	# seams. A stair-to-room-centre path could bisect several rooms and was a
	# major source of the malformed map silhouettes seen in fullscreen view.
	var horizontal_target := Vector2i(connector.x, center)
	var vertical_target := Vector2i(center, connector.y)
	var target := horizontal_target if absi(connector.y - center) \
		<= absi(connector.x - center) else vertical_target
	_carve_corridor(grid, connector, target, CORRIDOR_WIDTH)
	_mark_corridor_cells(circulation, connector, target, CORRIDOR_WIDTH)


func _carve_safe_room(grid: Array) -> void:
	var center := CHUNK_SIZE / 2
	# The central halls already provide a generous safe lobby. Limit the extra
	# opening to five cells so it cannot punch diagonal entrances through the
	# inner corners of neighbouring rooms.
	for z in range(center - 2, center + 3):
		for x in range(center - 2, center + 3):
			grid[z][x] = 0


func _region_layout(coord: Vector3i, region: String, grid: Array,
		stairs: Array = []) -> Dictionary:
	# A region is the multi-chunk visual/gameplay identity. Rooms are the small
	# bounded spaces inside one chunk; corridors serve many rooms and stairs
	# bridge the same circulation network vertically.
	if stairs.is_empty() and is_warren_chunk(coord):
		return _maze_warren_layout(coord, grid, region)
	if DENSE_DISTRICTS.has(region) and stairs.is_empty():
		return _dense_linear_layout(coord, region, grid)
	if region in ["hotel", "prison"]:
		return _linear_room_layout(coord, region, grid, stairs)
	return _mixed_room_layout(coord, region, grid, stairs)


func _linear_room_layout(coord: Vector3i, region: String, grid: Array,
		stairs: Array = []) -> Dictionary:
	if stairs.is_empty() and DENSE_DISTRICTS.has(region):
		return _dense_linear_layout(coord, region, grid)
	var rooms := []
	var corridors := []
	var suites := []
	var circulation := {}
	var center := CHUNK_SIZE / 2
	var horizontal_hall := Rect2i(1, center - 1, CHUNK_SIZE - 2, 3)
	var vertical_hall := Rect2i(center - 1, 1, 3, CHUNK_SIZE - 2)
	for hall in [horizontal_hall, vertical_hall]:
		_carve_rect(grid, hall)
		_mark_rect_cells(circulation, hall)
	corridors.append({"id": "%s:HALL:0" % chunk_id(coord),
		"rect": horizontal_hall, "width": CORRIDOR_WIDTH,
		"axis": "east_west", "serves_many_rooms": true})
	corridors.append({"id": "%s:HALL:1" % chunk_id(coord),
		"rect": vertical_hall, "width": CORRIDOR_WIDTH,
		"axis": "north_south", "serves_many_rooms": true})
	# Two room banks on either side of the north/south hall. Keeping the
	# three-wide centre reservation out of every room prevents a vertical seam
	# or stair connector from slicing a guest room in half.
	# Hotel rooms are 9x9 and the banks sit right on the E-W hall (a one-cell door, no connector hall).
	var room_columns := [Vector2i(5, 5), Vector2i(11, 7),
		Vector2i(25, 7), Vector2i(33, 5)]
	if LINEAR_REGIONS.has(region):
		# Hotel rooms and prison cells are both 9x9 (a cell needs space for the bunk, toilet and a walking aisle).
		room_columns = [Vector2i(2, 9), Vector2i(11, 9), Vector2i(24, 9), Vector2i(33, 9)]
	var stair_bays := _stairwell_bays(stairs)
	var room_index := 0
	for side in [-1, 1]:
		for column in room_columns:
			var cursor: int = column.x
			var width: int = column.y
			var depth := 9 if LINEAR_REGIONS.has(region) else 5
			var z := center - 2 - depth if side < 0 else center + 3
			var rect := Rect2i(cursor, z, width, depth)
			if stair_bays.values().any(func(stair_rect: Rect2i) -> bool:
				return stair_rect.intersects(rect)):
				continue
			_carve_rect(grid, rect)
			var room_rng := SeededRandom.new("%s:ROOM-BRANCH:%d:%d" % [
				chunk_id(coord), side, room_index])
			var connection := _connect_room_to_main_hall(grid, circulation,
				rect, 0 if side < 0 else 2, room_rng, "north_south")
			corridors.append({
				"id": "%s:ROOM-BRANCH:%d" % [chunk_id(coord), room_index],
				"axis": String(connection["axis"]),
				"width": CORRIDOR_WIDTH,
				"length": int(connection["length"]),
				"branch": true,
				"from_main_hall": true,
				"serves_many_rooms": false,
				"doorway": connection["doorway"],
			})
			var linear_room_type := "prison_cell"
			if region == "hotel":
				# Every fourth hotel doorway becomes a compact bathroom; the
				# remaining doors retain coordinated guest-room furnishing.
				linear_room_type = "hotel_bathroom" \
					if room_index % 4 == 3 else "guest_room"
			elif region == "prison":
				# Prison wings are linear but need occasional mess-like spaces
				# to avoid repetitive cell-block generation.
				linear_room_type = "prison_cafeteria" \
					if room_index % 5 == 2 else ("infirmary" if room_index % 5 == 4 else "prison_cell")
			var room_entry := _room_entry(coord, room_index, region, rect,
				linear_room_type)
			room_entry["doorway"] = connection["doorway"]
			rooms.append(room_entry)
			room_index += 1
	for bay_index_value in stair_bays:
		var bay_index := int(bay_index_value)
		var stair_rect: Rect2i = stair_bays[bay_index]
		_carve_rect(grid, stair_rect)
		var stair_rng := SeededRandom.new("%s:STAIRWELL:%d" % [chunk_id(coord), bay_index])
		var connection := _connect_room_to_main_hall(grid, circulation,
			stair_rect, bay_index, stair_rng)
		corridors.append({"id": "%s:STAIR-HALL:%d" % [chunk_id(coord), bay_index],
			"axis": String(connection["axis"]), "width": CORRIDOR_WIDTH,
			"length": int(connection["length"]), "branch": true,
			"from_main_hall": true, "serves_many_rooms": false,
			"doorway": connection["doorway"]})
		var stair_room := _room_entry(coord, room_index, region, stair_rect, "stairwell")
		stair_room["stair_ids"] = _stair_ids_in_bay(stairs, bay_index)
		rooms.append(stair_room)
		room_index += 1
	return {"rooms": rooms, "corridors": corridors, "suites": suites,
		"circulation": circulation}


## Dense districts (hotel, prison): three east-west halls (rows 9-11, 21-23 and 33-35) and the central north-south hall,
## with 11x9 rooms (9x7 inside) in tight banks that share walls and open straight onto a hall (no connector, no dead block between
## rooms). Per chunk: four rows of four rooms. The centre hall is the one the chunk seams meet.
## Share of maze chunks that are warrens (_maze_warren_layout) rather than room banks.
const WARREN_SHARE := .55
## The dense regions whose chunks can be warrens (KT: "the other regions need this change too"). The rest keep their banks;
## each region's special rooms (carousel big top, music wing, maze office suite) live in its bank chunks.
const WARREN_REGIONS := ["maze", "hospital", "lab", "greenhouse", "mall", "carnival", "hotel", "prison", "mansion", "beach", "gothic"]
## Room types whose recipes are tuned to bank shapes (rows of beds): they stay in the bank chunks.
const WARREN_ROOM_EXCLUDE := ["ward", "pod_room"]
## Warren macro cells: each quadrant beside the spine is 3 x 3 cells of WARREN_CELL x WARREN_CELL.
const WARREN_CELL := 6


## KT: "re-do the maze hallway styles, with twists and turns, scattered rooms". A maze chunk is either the bank layout or,
## WARREN_SHARE of the time, a warren. Never the spawn chunk; deterministic per seed.
func is_warren_chunk(coord: Vector3i) -> bool:
	if coord.y != 0 or not WARREN_REGIONS.has(region_for(coord)) or is_safe_room(coord) or is_pod_room_chunk(coord):
		return false   # the dive lab's pod room needs its bank
	return SeededRandom.new("%s:WARREN:%s" % [world_seed, chunk_id(coord)]).next_float() < WARREN_SHARE


## A warren: the five-wide spine cross (rows/columns 20-24) runs straight across the chunk (the long calm sightlines,
## unbroken: the maze has no great halls), and each quadrant beside it is a 3 x 3 grid of macro cells joined by
## three-wide corridors along a seeded spanning tree with the odd extra loop: turns, dead ends and loops. A quadrant may
## give a 2 x 2 corner of its macro cells to one 12 x 12 room (any maze room type, door onto a corridor through a short
## stub) or open its centre into a plaza. The corridors reach the spine and the E/W seam rows 10 and 34. The office
## suite lives in the bank chunks.
func _maze_warren_layout(coord: Vector3i, grid: Array, region: String = "maze") -> Dictionary:
	var rooms := []
	var corridors := []
	var suites := []
	var circulation := {}
	var metrics := {"corridor_cells": 0, "turns": 0, "dead_ends": 0, "nodes": 0, "loops": 0}
	var rng := SeededRandom.new("%s:WARRENLAYOUT:%s" % [world_seed, chunk_id(coord)])
	var spine := [Rect2i(1, 20, CHUNK_SIZE - 2, 5), Rect2i(20, 1, 5, CHUNK_SIZE - 2)]
	for index in spine.size():
		var hall: Rect2i = spine[index]
		_carve_rect(grid, hall)
		_mark_rect_cells(circulation, hall)
		corridors.append({"id": "%s:HALL:%d" % [chunk_id(coord), 1 if index == 0 else 3], "rect": hall, "width": CORRIDOR_WIDTH,
			"axis": "east_west" if index == 0 else "north_south", "serves_many_rooms": true})
	# the region's own rooms that fit a 12 x 12 corner (RoomSizeProfiles)
	var room_types := []
	# the hotel's rooms are named by its bank layout, not the region table
	var choices: Array = ["guest_room", "hotel_bathroom"] if region == "hotel" else _room_type_choices(region)
	for type_name in choices:
		if RoomSizeProfiles.within(String(type_name), Vector2i(WARREN_CELL * 2, WARREN_CELL * 2)) and not room_types.has(type_name) \
				and not WARREN_ROOM_EXCLUDE.has(type_name):
			room_types.append(type_name)
	for quadrant in 4:
		var east := quadrant % 2 == 1
		var south := quadrant >= 2
		var origin := Vector2i(25 if east else 1, 25 if south else 1)
		# the macro cell on the seam row (row 10 or 34) at the chunk's outer side keeps its corridor
		var seam_node := Vector2i(2 if east else 0, 1)
		var spine_x := 0 if east else 2
		var spine_z := 0 if south else 2
		var room_corner := Vector2i(-1, -1)
		if rng.next_float() < .65 and not room_types.is_empty():   # a region with no 12 x 12 room type gets plazas
			var options: Array[Vector2i] = []
			for cx in 2:
				for cz in 2:
					var corner := Vector2i(cx, cz)
					var covers_seam := Rect2i(corner, Vector2i(2, 2)).has_point(seam_node)
					if not covers_seam:
						options.append(corner)
			if not options.is_empty():
				room_corner = options[rng.next_index(options.size())]
		var nodes := {}
		for i in 3:
			for j in 3:
				if room_corner.x >= 0 and Rect2i(room_corner, Vector2i(2, 2)).has_point(Vector2i(i, j)):
					continue
				nodes[Vector2i(i, j)] = true
		# spanning tree (randomised depth-first), then a loop or two
		var tree := {}
		var start: Vector2i = seam_node
		var seen := {start: true}
		var stack: Array[Vector2i] = [start]
		while not stack.is_empty():
			var at: Vector2i = stack.back()
			var options: Array[Vector2i] = []
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var next: Vector2i = at + step
				if nodes.has(next) and not seen.has(next):
					options.append(next)
			if options.is_empty():
				stack.pop_back()
				continue
			var chosen: Vector2i = options[rng.next_index(options.size())]
			seen[chosen] = true
			tree[_edge_key(at, chosen)] = [at, chosen]
			stack.append(chosen)
		var extra: Array = []
		for node_value in nodes:
			var node: Vector2i = node_value
			for step in [Vector2i(1, 0), Vector2i(0, 1)]:
				var next: Vector2i = node + step
				if nodes.has(next) and not tree.has(_edge_key(node, next)):
					extra.append([node, next])
		for _loop in (1 if rng.next_float() < .6 else 0) + (1 if rng.next_float() < .25 else 0):
			if extra.is_empty():
				break
			var pick: Array = extra.pop_at(rng.next_index(extra.size()))
			tree[_edge_key(pick[0], pick[1])] = pick
			metrics["loops"] = int(metrics["loops"]) + 1
		var centre_of := func(node: Vector2i) -> Vector2i:
			return origin + node * WARREN_CELL + Vector2i(3, 3)
		var degree := {}
		var dirs := {}
		for key in tree:
			var pair: Array = tree[key]
			var a: Vector2i = pair[0]
			var b: Vector2i = pair[1]
			_carve_warren_lane(grid, circulation, centre_of.call(a), centre_of.call(b))
			degree[a] = int(degree.get(a, 0)) + 1
			degree[b] = int(degree.get(b, 0)) + 1
			(dirs.get_or_add(a, []) as Array).append(b - a)
			(dirs.get_or_add(b, []) as Array).append(a - b)
		for node_value in nodes:
			var node: Vector2i = node_value
			var c: Vector2i = centre_of.call(node)
			_carve_warren_lane(grid, circulation, c, c)
		# joins to the spine: the nodes on the spine side, one always, a second sometimes
		var spine_nodes: Array[Vector2i] = []
		for node_value in nodes:
			var node: Vector2i = node_value
			if node.x == spine_x or node.y == spine_z:
				spine_nodes.append(node)
		spine_nodes.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * 7 + a.y < b.x * 7 + b.y)
		var joins := 1 + (1 if rng.next_float() < .5 else 0)
		for join in mini(joins, spine_nodes.size()):
			var node: Vector2i = spine_nodes.pop_at(rng.next_index(spine_nodes.size()))
			var c: Vector2i = centre_of.call(node)
			var toward := Vector2i(22, c.y) if node.x == spine_x and (node.y != spine_z or rng.next_float() < .5) else Vector2i(c.x, 22)
			_carve_warren_lane(grid, circulation, c, toward)
			corridors.append({"id": "%s:WARREN-JOIN:%d:%d" % [chunk_id(coord), quadrant, join], "axis": "east_west" if toward.y == c.y else "north_south",
				"width": CORRIDOR_WIDTH, "length": absi(toward.x - c.x) + absi(toward.y - c.y), "branch": true, "from_main_hall": true,
				"serves_many_rooms": true})
			degree[node] = int(degree.get(node, 0)) + 1
			(dirs.get_or_add(node, []) as Array).append((toward - c).sign())
		# the seam row out to the chunk border (rows 10 / 34): the neighbour's hall comes through there
		var seam_c: Vector2i = centre_of.call(seam_node)
		_carve_warren_lane(grid, circulation, seam_c, Vector2i(CHUNK_SIZE - 2 if east else 1, seam_c.y))
		degree[seam_node] = int(degree.get(seam_node, 0)) + 1
		(dirs.get_or_add(seam_node, []) as Array).append(Vector2i(1 if east else -1, 0))
		# a plaza in a quadrant with no room
		if room_corner.x < 0 and rng.next_float() < .5 and nodes.has(Vector2i(1, 1)):
			var plaza := Rect2i(origin + Vector2i(WARREN_CELL + 1, WARREN_CELL + 1), Vector2i(WARREN_CELL - 1, WARREN_CELL - 1))
			_carve_rect(grid, plaza)
			_mark_rect_cells(circulation, plaza)
			corridors.append({"id": "%s:PLAZA:%d" % [chunk_id(coord), quadrant], "rect": plaza, "width": CORRIDOR_WIDTH,
				"axis": "east_west", "serves_many_rooms": true})
		# the room: a 12 x 12 corner, its door through a stub onto the nearest corridor beside it
		if room_corner.x >= 0:
			var rect := Rect2i(origin + room_corner * WARREN_CELL, Vector2i(WARREN_CELL * 2, WARREN_CELL * 2))
			_carve_rect(grid, rect)
			var door_options := []
			for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				for along in 2:
					var inside := room_corner + Vector2i(along if step.x == 0 else (1 if step.x > 0 else 0), along if step.y == 0 else (1 if step.y > 0 else 0))
					var outside: Vector2i = inside + step
					if nodes.has(outside):
						door_options.append([inside, outside])
			if door_options.is_empty():
				door_options.append([room_corner, room_corner])
			var pick: Array = door_options[rng.next_index(door_options.size())]
			var target: Vector2i = centre_of.call(pick[1])
			var inner: Vector2i = centre_of.call(pick[0])
			# the door sits mid-side (a door by a corner leaves a one-cell wall stub), the stub bends to the corridor
			var middle := rect.position + rect.size / 2
			var doorway := Vector2i(rect.position.x if target.x < inner.x else rect.end.x - 1, middle.y) if target.x != inner.x \
				else Vector2i(middle.x, rect.position.y if target.y < inner.y else rect.end.y - 1)
			_seal_room_perimeter_except(grid, rect, doorway)
			_carve_warren_lane(grid, circulation, doorway + (target - inner).sign(), target)
			_mark_corridor_cell(circulation, doorway, 1)
			corridors.append({"id": "%s:ROOM-BRANCH:%d" % [chunk_id(coord), rooms.size()], "axis": "north_south",
				"width": CORRIDOR_WIDTH, "length": 1, "branch": true, "from_main_hall": false, "serves_many_rooms": false,
				"doorway": doorway})
			var entry := _room_entry(coord, rooms.size(), region, rect, String(room_types[rng.next_index(room_types.size())]))
			entry["doorway"] = doorway
			rooms.append(entry)
		for node_value in nodes:
			var node: Vector2i = node_value
			metrics["nodes"] = int(metrics["nodes"]) + 1
			var node_dirs: Array = dirs.get(node, [])
			if int(degree.get(node, 0)) == 1:
				metrics["dead_ends"] = int(metrics["dead_ends"]) + 1
			elif node_dirs.size() == 2 and (node_dirs[0] as Vector2i) != -(node_dirs[1] as Vector2i):
				metrics["turns"] = int(metrics["turns"]) + 1
	for z in CHUNK_SIZE:
		for x in CHUNK_SIZE:
			if circulation.has(Vector2i(x, z)) and not (x >= 20 and x <= 24) and not (z >= 20 and z <= 24):
				metrics["corridor_cells"] = int(metrics["corridor_cells"]) + 1
	return {"rooms": rooms, "corridors": corridors, "suites": suites, "circulation": circulation, "warren": metrics}


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	return "%s-%s" % [a, b] if a.x * 99 + a.y < b.x * 99 + b.y else "%s-%s" % [b, a]


## A three-wide straight lane between two cells on a row or a column (an L when they differ in both).
static func _carve_warren_lane(grid: Array, circulation: Dictionary, from: Vector2i, to: Vector2i) -> void:
	var corner := Vector2i(to.x, from.y)
	for leg in [[from, corner], [corner, to]]:
		var a: Vector2i = leg[0]
		var b: Vector2i = leg[1]
		var rect := Rect2i(mini(a.x, b.x) - 1, mini(a.y, b.y) - 1, absi(a.x - b.x) + 3, absi(a.y - b.y) + 3)
		rect = rect.intersection(Rect2i(1, 1, CHUNK_SIZE - 2, CHUNK_SIZE - 2))
		_carve_rect(grid, rect)
		_mark_rect_cells(circulation, rect)


func _dense_linear_layout(coord: Vector3i, region: String, grid: Array) -> Dictionary:
	var rooms := []
	var corridors := []
	var suites := []
	var circulation := {}
	var rng := SeededRandom.new("%s:BANKS:%s" % [world_seed, chunk_id(coord)])
	var center := CHUNK_SIZE / 2
	# Maze keeps its signature office suite in the south-east quarter: the banks leave that quarter alone.
	var office_quarter := region == "maze"
	# KT: "5 wide maze region hallways". The maze's two main halls (the centre cross the seams meet) are five wide; its
	# outer east-west halls stay three wide as side passages, so the banks either side keep usable room depths.
	var wide := region == "maze"
	var half := 2 if wide else 1
	var plan := large_plan(coord)
	var middle_start := center - half if hall_trimmed(coord, -1) else 1
	# the maze office suite is entered from this hall (doors at x 32-33), so its east trim leaves the hall past the entrance (the wall beside the door then runs on, not a one-cell stub)
	var middle_end := (37 if office_quarter else center + 1 + half) if hall_trimmed(coord, 1) else CHUNK_SIZE - 1
	var mall := region == "mall"
	# the arcade's and the maze's main halls are five wide; every other district keeps a three-wide centre hall
	var main_hall := Rect2i(center - 2, 1, 5, CHUNK_SIZE - 2) if mall or wide else Rect2i(center - 1, 1, 3, CHUNK_SIZE - 2)
	var halls := [Rect2i(1, 9, CHUNK_SIZE - 2, 3),
		Rect2i(middle_start, center - half, middle_end - middle_start, 1 + 2 * half),
		Rect2i(1, 33, 22 if office_quarter else CHUNK_SIZE - 2, 3), main_hall]
	for hall_index in halls.size():
		var hall: Rect2i = halls[hall_index]
		_carve_rect(grid, hall)
		_mark_rect_cells(circulation, hall)
		corridors.append({"id": "%s:HALL:%d" % [chunk_id(coord), hall_index], "rect": hall, "width": CORRIDOR_WIDTH,
			"axis": "north_south" if hall_index == 3 else "east_west", "serves_many_rooms": true})
	# rows of rooms (top y, door on the top wall when facing a hall above, bottom wall when facing one below); each
	# side is either two 11x9 rooms sharing a wall or one 21x9 hall room, from the chunk border to the centre hall.
	var rows := [{"y": 0, "h": 9, "door_top": false}, {"y": 12, "h": 9, "door_top": true},
		{"y": 24, "h": 9, "door_top": false}, {"y": 36, "h": 9, "door_top": true}]
	if wide:
		# the five-wide middle hall (rows 20-24) takes a row from each middle bank
		rows[1]["h"] = 8
		rows[2]["y"] = 25
		rows[2]["h"] = 8
	var side_x := [0, 25] if mall or wide else [0, 24]
	# a bank side runs from the border to the centre hall: 21 cells beside a three-wide hall, 20 beside a five-wide one
	var bank_w := 20 if wide else 21
	var big_types: Array = BANK_BIG_TYPES.get(region, [])
	var small_types := []
	for type_name in (_room_type_choices(region) as Array):
		if not big_types.has(type_name) and not (region == "carnival" and type_name == "big_top"):
			small_types.append(type_name)
	if small_types.is_empty():
		small_types = _room_type_choices(region)
	var pod_pending := region == "lab" and is_pod_room_chunk(coord)
	var room_index := 0
	# a mall chunk holds eight shops: start its cycle through the thirteen shop kinds at a per-chunk offset
	var type_offset := rng.next_index(small_types.size()) if mall else 0
	# great halls first: two middle banks and the hall between them become one 21x21 room opening on the vertical hall
	var merged_sides := {}
	for side in 2:
		var hall_type: String = String(plan["W" if side == 0 else "E"])
		if hall_type.is_empty():
			continue
		merged_sides[side] = true
		var big := Rect2i(side_x[side], 12, bank_w if wide else LARGE_ROOM_SIZE, LARGE_ROOM_SIZE)
		_carve_rect(grid, big)
		var big_door := Vector2i(big.end.x - 1 if side == 0 else big.position.x, center)
		_seal_room_perimeter_except(grid, big, big_door)
		_mark_corridor_cell(circulation, big_door, 1)
		corridors.append({"id": "%s:ROOM-BRANCH:%d" % [chunk_id(coord), room_index],
			"axis": "east_west", "width": CORRIDOR_WIDTH, "length": 1, "branch": true,
			"from_main_hall": true, "serves_many_rooms": false, "doorway": big_door})
		if hall_type == "big_top":
			# the merry-go-round hall opens onto the vertical hall three cells wide (no narrowing beside the ride)
			for door_row in range(big_door.y - 1, big_door.y + 2):
				grid[door_row][big_door.x] = 0
		if hall_type == MusicWing.LARGE_TYPE:
			var wing := MusicWing.carve(grid, big, big_door, null, MusicWing.part_for_side(side))
			for wing_room in wing["rooms"]:
				var wing_entry := _room_entry(coord, room_index, region, wing_room["rect"], String(wing_room["room_type"]))
				wing_entry["doorway"] = wing_room["doorway"]
				wing_entry["preset_room"] = true
				rooms.append(wing_entry)
				room_index += 1
			if (wing["hall"] as Rect2i).has_area():
				# the wing hall is three wide, so its entrance from the vertical hall is a three-wide opening, not one cell
				for door_row in range(big_door.y - 1, big_door.y + 2):
					grid[door_row][big_door.x] = 0
				corridors.append({"id": "%s:WING-HALL:%d" % [chunk_id(coord), side], "rect": wing["hall"],
					"axis": "east_west", "width": CORRIDOR_WIDTH, "branch": true, "serves_many_rooms": true})
			for wing_cell in wing["circulation"]:
				_mark_corridor_cell(circulation, wing_cell, 1)
			continue
		var big_entry := _room_entry(coord, room_index, region, big, hall_type)
		big_entry["doorway"] = big_door
		big_entry["great_hall"] = true
		if hall_type == "big_top":
			big_entry["extra_doorways"] = [Vector2i(big_door.x, big_door.y - 1), Vector2i(big_door.x, big_door.y + 1)]
		rooms.append(big_entry)
		room_index += 1
	for row in rows:
		for side in 2:
			if office_quarter and side == 1 and int(row["y"]) >= 24:
				continue
			if merged_sides.has(side) and int(row["y"]) > 0 and int(row["y"]) < 36:
				continue
			var specs := []
			# the maze's 8-deep banks cannot seat a restaurant's two rows of six: they cycle through the other rooms
			var shallow := int(row["h"]) < 9
			if pod_pending:
				pod_pending = false
				specs.append({"x": side_x[side], "w": 21, "type": "pod_room"})
			elif mall:
				specs.append({"x": side_x[side], "w": MALL_SHOP_WIDTH, "type": ""})
			elif not big_types.is_empty() and rng.next_float() < float(BANK_BIG_CHANCE.get(region, 0.0)):
				var big_type: String = big_types[rng.next_index(big_types.size())]
				if shallow and big_type == "restaurant_dining":
					big_type = "storage"
				specs.append({"x": side_x[side], "w": bank_w, "type": big_type})
			elif wide:
				# two rooms sharing a wall, the one nearer the centre hall a cell narrower
				var outer := 0 if side == 0 else 9
				specs.append({"x": side_x[side] + outer, "w": 11, "type": ""})
				specs.append({"x": side_x[side] + (10 if side == 0 else 0), "w": 10, "type": ""})
			else:
				specs.append({"x": side_x[side], "w": 11, "type": ""})
				specs.append({"x": side_x[side] + 10, "w": 11, "type": ""})
			for spec in specs:
				var rect := Rect2i(int(spec["x"]), int(row["y"]), int(spec["w"]), int(row["h"]))
				_carve_rect(grid, rect)
				var door_top: bool = row["door_top"]
				var doorway := Vector2i(rect.position.x + rect.size.x / 2, rect.position.y if door_top else rect.end.y - 1)
				_seal_room_perimeter_except(grid, rect, doorway)
				_mark_corridor_cell(circulation, doorway, 1)
				corridors.append({"id": "%s:ROOM-BRANCH:%d" % [chunk_id(coord), room_index],
					"axis": "north_south", "width": CORRIDOR_WIDTH, "length": 1, "branch": true,
					"from_main_hall": true, "serves_many_rooms": false, "doorway": doorway})
				var room_type := String(spec["type"])
				if room_type.is_empty():
					if region == "hotel":
						room_type = "hotel_bathroom" if room_index % 4 == 3 else "guest_room"
					elif region == "prison":
						room_type = "prison_cafeteria" if room_index % 5 == 2 \
							else ("infirmary" if room_index % 5 == 4 else "prison_cell")
					else:
						room_type = String(small_types[(room_index + type_offset) % small_types.size()])
						if shallow and room_type == "restaurant_dining":
							room_type = String(small_types[(room_index + type_offset + 1) % small_types.size()])
				var entry := _room_entry(coord, room_index, region, rect, room_type)
				entry["doorway"] = doorway
				rooms.append(entry)
				room_index += 1
	if office_quarter and 34 in edge_openings(coord, Vector2i(1, 0)):
		# the lower hall stops short of the east border here (the office suite owns that quarter); the seam row the
		# neighbour's lower hall comes through gets a full three-wide bay instead of a one-cell stub in the wall
		var bay := Rect2i(CHUNK_SIZE - 3, 33, 3, 3)
		_carve_rect(grid, bay)
		_mark_rect_cells(circulation, bay)
	if office_quarter:
		var suite := _carve_suite_cluster(coord, region, grid, circulation, Rect2i(25, 25, 17, 19), 3, "office", rng)
		rooms.append_array(suite["rooms"])
		corridors.append_array(suite["corridors"])
		suites.append(suite["suite"])
	return {"rooms": rooms, "corridors": corridors, "suites": suites, "circulation": circulation}


## The dive lab's pod room is rare: one chunk of each lab district (REGION_SIZE_CHUNKS squared chunks) holds it.
func is_pod_room_chunk(coord: Vector3i) -> bool:
	if coord.y != 0 or region_for(coord) != "lab":
		return false
	var region_x := floori(float(coord.x) / REGION_SIZE_CHUNKS)
	var region_z := floori(float(coord.z) / REGION_SIZE_CHUNKS)
	var rng := SeededRandom.new("%s:PODROOM:%d:%d" % [world_seed, region_x, region_z])
	return posmod(coord.x, REGION_SIZE_CHUNKS) == rng.next_index(REGION_SIZE_CHUNKS) \
		and posmod(coord.z, REGION_SIZE_CHUNKS) == rng.next_index(REGION_SIZE_CHUNKS)


## The room-type names of a district (the table _room_type_for cycles through).
static func _room_type_choices(region: String) -> Array:
	var types := {
		"mansion": ["drawing_room", "bedroom", "dining_room", "luxury_bathroom"],
		"beach": ["cove", "beach_hut", "tide_pool", "boardwalk_room"],
		"inferno": ["thermal_chamber", "forge", "altar_room", "lava_gallery"],
		"gothic": ["crypt", "chapel", "mourning_room", "archive"],
		"apartment": ["bedroom", "kitchen", "living_room", "house_bathroom"],
		"carnival": ["big_top", "midway", "game_stall", "backstage"],
		"maze": ["restaurant_dining", "arcade_room", "public_restroom", "storage"],
		"prison": ["prison_cell", "prison_cafeteria", "prison_cell", "prison_cell"],
		"hospital": HOSPITAL_ROOMS, "lab": LAB_ROOMS, "greenhouse": GREENHOUSE_ROOMS, "mall": MALL_ROOMS,
	}
	return types.get(region, ["room"])


func _mixed_room_layout(coord: Vector3i, region: String, grid: Array,
		stairs: Array = []) -> Dictionary:
	var rng := SeededRandom.new("%s:ROOMS:%s" % [world_seed, chunk_id(coord)])
	var rooms := []
	var corridors := []
	var suites := []
	var circulation := {}
	var center := CHUNK_SIZE / 2
	# A canonical three-wide cross divides four bounded room sectors. Earlier
	# centre-to-centre connectors travelled through neighbouring sectors and
	# dissolved their walls into huge irregular open shapes on the map.
	var horizontal_hall := Rect2i(1, center - 1, CHUNK_SIZE - 2, 3)
	var vertical_hall := Rect2i(center - 1, 1, 3, CHUNK_SIZE - 2)
	for hall in [horizontal_hall, vertical_hall]:
		_carve_rect(grid, hall)
		_mark_rect_cells(circulation, hall)
	corridors.append({"id": "%s:HALL:MAIN-X" % chunk_id(coord),
		"rect": horizontal_hall, "width": CORRIDOR_WIDTH,
		"axis": "east_west", "serves_many_rooms": true})
	corridors.append({"id": "%s:HALL:MAIN-Z" % chunk_id(coord),
		"rect": vertical_hall, "width": CORRIDOR_WIDTH,
		"axis": "north_south", "serves_many_rooms": true})
	var sectors := [
		Rect2i(4, 4, 17, 17), Rect2i(24, 4, 17, 17),
		Rect2i(4, 24, 17, 17), Rect2i(24, 24, 17, 17),
	]
	var stair_bays := _stairwell_bays(stairs)
	var size_pool := ROOM_SIZES
	if region in ["mansion", "carnival"]:
		size_pool = [Vector2i(9, 9), Vector2i(11, 13), Vector2i(13, 11), Vector2i(15, 15)]
	elif region == "beach":
		size_pool = [Vector2i(9, 9), Vector2i(11, 13), Vector2i(15, 15)]
	elif region == "maze":
		# Maze sectors now own named restaurant, arcade and restroom recipes.
		# An eleven-cell minimum leaves a sealed perimeter, two complete six-chair
		# party tables, and the protected three-wide doorway shoulder. The former
		# 9x9 option necessarily dropped the three seats nearest the exit.
		size_pool = [Vector2i(11, 11),
			Vector2i(11, 13), Vector2i(13, 11)]
	elif region == "apartment":
		# Furnished apartments need a real wall run and a clear aisle. Tiny 3x3
		# utility closets remain available in maze chunks, not as fake bedrooms.
		size_pool = [Vector2i(9, 9),
			Vector2i(11, 13), Vector2i(13, 11)]
	elif region in ["gothic", "inferno"]:
		size_pool = [Vector2i(9, 9), Vector2i(9, 11), Vector2i(11, 13)]
	for sector_index in sectors.size():
		var sector: Rect2i = sectors[sector_index]
		if stair_bays.has(sector_index):
			var stair_rect: Rect2i = stair_bays[sector_index]
			_carve_rect(grid, stair_rect)
			var stair_connection := _connect_room_to_main_hall(grid,
				circulation, stair_rect, sector_index, rng)
			corridors.append({
				"id": "%s:STAIR-HALL:%d" % [chunk_id(coord), sector_index],
				"axis": String(stair_connection["axis"]),
				"width": CORRIDOR_WIDTH,
				"length": int(stair_connection["length"]),
				"branch": true,
				"from_main_hall": true,
				"serves_many_rooms": false,
				"doorway": stair_connection["doorway"],
			})
			var stair_room := _room_entry(coord, sector_index, region,
				stair_rect, "stairwell")
			stair_room["stair_ids"] = _stair_ids_in_bay(stairs, sector_index)
			rooms.append(stair_room)
			continue
		var suite_kind := ""
		# Two opposite apartment units open from the same main hallway. Each unit
		# is one persisted suite containing its own bedroom, kitchen, dining room
		# and bathroom rather than four unrelated maze rooms.
		if region == "apartment":
			suite_kind = "apartment"
		elif region == "maze" and sector_index == 3:
			suite_kind = "office"
		if not suite_kind.is_empty():
			var suite := _carve_suite_cluster(coord, region, grid, circulation,
				sector, sector_index, suite_kind, rng)
			rooms.append_array(suite["rooms"])
			corridors.append_array(suite["corridors"])
			suites.append(suite["suite"])
			continue
		if sector_index == 0 and region in ["mansion", "beach", "carnival"]:
			# Pull the landmark away from the central cross so its connector reads
			# as a real secondary hall instead of dissolving into the room edge.
			var landmark_rect := Rect2i(4, 4, 15, 15)
			_carve_rect(grid, landmark_rect)
			var landmark_connection := _connect_room_to_main_hall(grid,
				circulation, landmark_rect, sector_index, rng)
			corridors.append({
				"id": "%s:HALL:%d" % [chunk_id(coord), sector_index],
				"axis": String(landmark_connection["axis"]),
				"width": CORRIDOR_WIDTH,
				"length": int(landmark_connection["length"]),
				"branch": true,
				"from_main_hall": true,
				"serves_many_rooms": false,
				"doorway": landmark_connection["doorway"],
			})
			var landmark_room := _room_entry(coord, sector_index, region,
				landmark_rect, _room_type_for(region, sector_index))
			landmark_room["doorway"] = landmark_connection["doorway"]
			rooms.append(landmark_room)
			continue
		var fitting := size_pool.filter(func(candidate: Vector2i) -> bool:
			return candidate.x <= sector.size.x - 2 \
				and candidate.y <= sector.size.y - 2)
		if fitting.is_empty():
			fitting = [Vector2i(9, 9)]
		var wanted: Vector2i = fitting[rng.next_index(fitting.size())]
		var room_size := Vector2i(mini(wanted.x, sector.size.x - 2),
			mini(wanted.y, sector.size.y - 2))
		# Anchor rooms toward the INNER corner of their sector (next to the central cross), leaving a
		# one to three cell connector, so no long hallway leads to a room. Larger rooms simply leave
		# the shorter gap.
		var gap_x := clampi(1 + rng.next_index(3), 1, maxi(1, sector.size.x - room_size.x - 1))
		var gap_y := clampi(1 + rng.next_index(3), 1, maxi(1, sector.size.y - room_size.y - 1))
		var at := Vector2i(
			sector.end.x - room_size.x - gap_x if sector_index % 2 == 0 \
				else sector.position.x + gap_x,
			sector.end.y - room_size.y - gap_y if sector_index < 2 \
				else sector.position.y + gap_y)
		var rect := Rect2i(at, room_size)
		_carve_rect(grid, rect)
		var connection := _connect_room_to_main_hall(grid, circulation,
			rect, sector_index, rng)
		corridors.append({
			"id": "%s:HALL:%d" % [chunk_id(coord), sector_index],
			"axis": String(connection["axis"]),
			"width": CORRIDOR_WIDTH,
			"length": int(connection["length"]),
			"branch": true,
			"from_main_hall": true,
			"serves_many_rooms": false,
			"doorway": connection["doorway"],
		})
		var room_entry := _room_entry(coord, sector_index, region, rect,
			_room_type_for(region, sector_index))
		room_entry["doorway"] = connection["doorway"]
		rooms.append(room_entry)
	return {"rooms": rooms, "corridors": corridors, "suites": suites,
		"circulation": circulation}


func _carve_suite_cluster(coord: Vector3i, region: String, grid: Array,
		circulation: Dictionary, rect: Rect2i, sector_index: int,
		suite_kind: String, rng: SeededRandom) -> Dictionary:
	# A suite occupies one complete 17x17 room sector. Its three-wide internal
	# cross is a real shared hall, while four 7x7 rooms retain their own walls and
	# thresholds. This lets one corridor-facing door own an apartment/office
	# instead of treating every amenity as an unrelated maze room.
	if suite_kind == "apartment":
		return _carve_apartment_suite(coord, region, grid, circulation, rect,
			sector_index)
	var suite_id := "%s:SUITE:%d:%s" % [chunk_id(coord), sector_index,
		suite_kind.to_upper()]
	_carve_rect(grid, rect)
	var entrance := _connect_room_to_main_hall(grid, circulation, rect,
		sector_index, rng)
	var suite_rooms := []
	var suite_corridors := [{
		"id": "%s:ENTRY-HALL" % suite_id,
		"axis": String(entrance["axis"]),
		"width": CORRIDOR_WIDTH,
		"length": int(entrance["length"]),
		"branch": true,
		"from_main_hall": true,
		"serves_many_rooms": true,
		"doorway": entrance["doorway"],
		"suite_id": suite_id,
	}]
	var parent := _room_entry(coord, sector_index, region, rect,
		"%s_suite" % suite_kind)
	parent["id"] = "%s:ENTRY" % suite_id
	parent["doorway"] = entrance["doorway"]
	parent["suite_id"] = suite_id
	parent["suite_kind"] = suite_kind
	parent["suite_parent"] = true
	parent["preset_room"] = true
	suite_rooms.append(parent)

	# four rooms round a three-wide cross: 7 x 7 in a 17 x 17 sector; the maze's office sector is 17 wide (the seam bay
	# needs the last three columns) and 19 tall under the five-wide hall, so its rooms are 7 x 8 (hunter scale needs the
	# depth; docs/ROOM_REFERENCE.md). A 21 sector would give 9 x 9.
	var room_w := (rect.size.x - 3) / 2
	var room_h := (rect.size.y - 3) / 2
	var far_x := room_w + 3
	var far_z := room_h + 3
	var hall_x := Rect2i(rect.position + Vector2i(room_w, 1), Vector2i(3, rect.size.y - 2))
	var hall_z := Rect2i(rect.position + Vector2i(1, room_h), Vector2i(rect.size.x - 2, 3))
	for hall in [hall_x, hall_z]:
		_carve_rect(grid, hall)
		_mark_rect_cells(circulation, hall)
	var child_specs := [
		{"rect": Rect2i(rect.position, Vector2i(room_w, room_h)), "door_side": "right"},
		{"rect": Rect2i(rect.position + Vector2i(far_x, 0), Vector2i(room_w, room_h)),
			"door_side": "left"},
		{"rect": Rect2i(rect.position + Vector2i(0, far_z), Vector2i(room_w, room_h)),
			"door_side": "right"},
		{"rect": Rect2i(rect.position + Vector2i(far_x, far_z), Vector2i(room_w, room_h)),
			"door_side": "left"},
	]
	var apartment_roles := ["bedroom", "kitchen", "family_dining",
		"house_bathroom"]
	var office_roles := ["office_reception", "cubicle_room", "office_job",
		"private_office"]
	var roles := apartment_roles if suite_kind == "apartment" else office_roles
	var child_ids := []
	for child_index in child_specs.size():
		var child_spec: Dictionary = child_specs[child_index]
		var child_rect: Rect2i = child_spec["rect"]
		var doorway := Vector2i(child_rect.end.x - 1,
			child_rect.position.y + child_rect.size.y / 2)
		if String(child_spec["door_side"]) == "left":
			doorway.x = child_rect.position.x
		_seal_room_perimeter_except(grid, child_rect, doorway)
		_mark_corridor_cell(circulation, doorway, 1)
		var child := _room_entry(coord, child_index, region, child_rect,
			String(roles[child_index]))
		child["id"] = "%s:ROOM:%d:%s" % [suite_id, child_index,
			String(roles[child_index]).to_upper()]
		child["doorway"] = doorway
		child["suite_id"] = suite_id
		child["suite_kind"] = suite_kind
		child["suite_role"] = String(roles[child_index])
		child["preset_room"] = true
		suite_rooms.append(child)
		child_ids.append(child["id"])
	for axis_data in [
		{"rect": hall_x, "axis": "north_south"},
		{"rect": hall_z, "axis": "east_west"},
	]:
		suite_corridors.append({
			"id": "%s:INNER:%s" % [suite_id, String(axis_data["axis"])],
			"rect": axis_data["rect"], "axis": axis_data["axis"],
			"width": CORRIDOR_WIDTH, "branch": true,
			"from_main_hall": false, "serves_many_rooms": true,
			"suite_id": suite_id,
		})
	return {
		"rooms": suite_rooms,
		"corridors": suite_corridors,
		"suite": {
			"id": suite_id, "kind": suite_kind, "region": region,
			"rect": rect, "entry_doorway": entrance["doorway"],
			"parent_room_id": parent["id"], "room_ids": child_ids,
		},
	}


## A real apartment in one 17x17 sector: four rooms that share walls, joined by single doors
## (no cross hall). Local plan, entrance on the west wall (mirrored for the east-entrance sector):
##   bedroom  (0,0)  9x9   | bathroom (8,0)  9x9   (en suite: door between bedroom and bathroom)
##   living   (0,8) 11x9   | kitchen  (10,8) 7x9
## living <-> bedroom door at (4,8), bedroom <-> bathroom at (8,4), living <-> kitchen at (10,14);
## the entrance (0,12) opens straight into the living room. The suite parent room owns the entrance door.
func _carve_apartment_suite(coord: Vector3i, region: String, grid: Array,
		circulation: Dictionary, rect: Rect2i, sector_index: int) -> Dictionary:
	var suite_id := "%s:SUITE:%d:APARTMENT" % [chunk_id(coord), sector_index]
	var flip := sector_index in [0, 2]    # these sectors enter from the east side
	var size := rect.size.x
	var to_world_cell := func(local: Vector2i) -> Vector2i:
		var x: int = (size - 1 - local.x) if flip else local.x
		return rect.position + Vector2i(x, local.y)
	var to_world_rect := func(local: Rect2i) -> Rect2i:
		var x: int = (size - local.end.x) if flip else local.position.x
		return Rect2i(rect.position + Vector2i(x, local.position.y), local.size)
	_carve_rect(grid, rect)
	var entry_cell: Vector2i = to_world_cell.call(Vector2i(0, 12))
	var junction := Vector2i(CHUNK_SIZE / 2, entry_cell.y)
	_carve_corridor_segment(grid, circulation, entry_cell, junction)
	var plan := [
		{"role": "bedroom", "rect": Rect2i(0, 0, 9, 9), "door": Vector2i(4, 8)},
		{"role": "house_bathroom", "rect": Rect2i(8, 0, 9, 9), "door": Vector2i(8, 4)},
		{"role": "living_room", "rect": Rect2i(0, 8, 11, 9), "door": Vector2i(0, 12)},
		{"role": "kitchen", "rect": Rect2i(10, 8, 7, 9), "door": Vector2i(10, 15)},   # door beside the bottom wall: no one-cell wall stub below it
	]
	for entry in plan:
		var world_rect: Rect2i = to_world_rect.call(entry["rect"])
		_seal_room_perimeter_except(grid, world_rect, entry_cell)
		grid[entry_cell.y][entry_cell.x] = 1
	var door_cells := [Vector2i(4, 8), Vector2i(8, 4), Vector2i(10, 15), Vector2i(0, 12)]
	for door_local in door_cells:
		var world_door: Vector2i = to_world_cell.call(door_local)
		grid[world_door.y][world_door.x] = 0
		_mark_corridor_cell(circulation, world_door, 1)
	var parent := _room_entry(coord, sector_index, region, rect, "apartment_suite")
	parent["id"] = "%s:ENTRY" % suite_id
	parent["doorway"] = entry_cell
	parent["suite_id"] = suite_id
	parent["suite_kind"] = "apartment"
	parent["suite_parent"] = true
	parent["preset_room"] = true
	var suite_rooms := [parent]
	var child_ids := []
	for child_index in plan.size():
		var entry: Dictionary = plan[child_index]
		var role := String(entry["role"])
		var world_rect: Rect2i = to_world_rect.call(entry["rect"])
		var child := _room_entry(coord, child_index, region, world_rect, role)
		child["id"] = "%s:ROOM:%d:%s" % [suite_id, child_index, role.to_upper()]
		child["doorway"] = to_world_cell.call(entry["door"])
		var extra := []
		for door_local in door_cells:
			var world_door: Vector2i = to_world_cell.call(door_local)
			if world_rect.has_point(world_door) and world_door != child["doorway"]:
				extra.append(world_door)
		child["extra_doorways"] = extra
		child["suite_id"] = suite_id
		child["suite_kind"] = "apartment"
		child["suite_role"] = role
		child["preset_room"] = true
		suite_rooms.append(child)
		child_ids.append(child["id"])
	return {
		"rooms": suite_rooms,
		"corridors": [{
			"id": "%s:ENTRY-HALL" % suite_id,
			"axis": "east_west",
			"width": CORRIDOR_WIDTH,
			"length": absi(entry_cell.x - junction.x),
			"branch": true,
			"from_main_hall": true,
			"serves_many_rooms": true,
			"doorway": entry_cell,
			"suite_id": suite_id,
		}],
		"suite": {
			"id": suite_id, "kind": "apartment", "region": region,
			"rect": rect, "entry_doorway": entry_cell,
			"parent_room_id": parent["id"], "room_ids": child_ids,
		},
	}


static func _stairwell_bays(stairs: Array) -> Dictionary:
	var result := {}
	for stair_value in stairs:
		var stair: Dictionary = stair_value
		var cell: Vector2i = stair.get("cell", Vector2i.ZERO)
		var index := stair_bay_index(cell)
		# The 17x17 sector retains a one-cell structural wall on all sides;
		# the resulting 15x15 room comfortably encloses the five-wide flight.
		var sector_position := Vector2i(24 if index % 2 == 1 else 4,
			24 if index >= 2 else 4)
		result[index] = Rect2i(sector_position + Vector2i.ONE,
			Vector2i(15, 15))
	return result


static func _stair_ids_in_bay(stairs: Array, bay_index: int) -> Array:
	var result := []
	for stair_value in stairs:
		var stair: Dictionary = stair_value
		var cell: Vector2i = stair.get("cell", Vector2i.ZERO)
		var index := stair_bay_index(cell)
		if index == bay_index:
			result.append(String(stair.get("id", "")))
	return result


static func _connect_room_to_main_hall(grid: Array, circulation: Dictionary,
		rect: Rect2i, sector_index: int, rng: SeededRandom,
		axis_hint: String = "") -> Dictionary:
	var center := CHUNK_SIZE / 2
	var room_center := rect.position + rect.size / 2
	var horizontal_door := Vector2i(
		rect.end.x - 1 if sector_index in [0, 2] else rect.position.x,
		_safe_room_door_coordinate(rect.position.y, rect.end.y, room_center.y))
	var vertical_door := Vector2i(
		_safe_room_door_coordinate(rect.position.x, rect.end.x, room_center.x),
		rect.end.y - 1 if sector_index in [0, 1] else rect.position.y)
	var horizontal_length := absi(horizontal_door.x - center)
	var vertical_length := absi(vertical_door.y - center)
	var connect_horizontally := false
	if axis_hint == "east_west":
		connect_horizontally = true
	elif axis_hint == "north_south":
		connect_horizontally = false
	elif horizontal_length == vertical_length:
		connect_horizontally = rng.next_float() < .5
	else:
		# Prefer the longer route so ordinary rooms have an unmistakable branch
		# off the central hall. The boundary is rebuilt below, so this cannot cut
		# an alternate entrance through a room corner.
		connect_horizontally = horizontal_length > vertical_length
	var start := room_center
	var target := room_center
	if connect_horizontally:
		start = horizontal_door
		target = Vector2i(center, start.y)
	else:
		start = vertical_door
		target = Vector2i(start.x, center)
	_carve_corridor_segment(grid, circulation, start, target)
	_seal_room_perimeter_except(grid, rect, start)
	return {"axis": "east_west" if connect_horizontally else "north_south",
		"length": absi(start.x - target.x) + absi(start.y - target.y),
		"doorway": start, "junction": target}


static func _safe_room_door_coordinate(start: int, finish: int,
		preferred: int) -> int:
	# Three-wide corridors may approach the room, but their final threshold is
	# one centered cell. Preserve at least one wall shoulder on compact rooms
	# and two on rooms wide enough to support a full authored door frame.
	var shoulder := 2 if finish - start >= 5 else 1
	return clampi(preferred, start + shoulder, finish - shoulder - 1)


static func _seal_room_perimeter_except(grid: Array, rect: Rect2i,
		doorway: Vector2i) -> void:
	for x in range(rect.position.x, rect.end.x):
		grid[rect.position.y][x] = 1
		grid[rect.end.y - 1][x] = 1
	for z in range(rect.position.y, rect.end.y):
		grid[z][rect.position.x] = 1
		grid[z][rect.end.x - 1] = 1
	grid[doorway.y][doorway.x] = 0


static func _restore_single_room_thresholds(grid: Array, rooms: Array) -> void:
	for room_value in rooms:
		var room: Dictionary = room_value
		if String(room.get("room_type", "")) == "stairwell":
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		var doorway = room.get("doorway")
		if rect.size.x <= 0 or rect.size.y <= 0 or not doorway is Vector2i:
			continue
		_seal_room_perimeter_except(grid, rect, doorway)
	# Rooms that share walls (apartments) re-sealed each other's doors: open every doorway again.
	for room_value in rooms:
		var room: Dictionary = room_value
		var primary = room.get("doorway")
		if primary is Vector2i and (room.get("rect", Rect2i()) as Rect2i).size.x > 0:
			grid[(primary as Vector2i).y][(primary as Vector2i).x] = 0
		for extra_value in room.get("extra_doorways", []):
			var extra: Vector2i = extra_value
			grid[extra.y][extra.x] = 0


## Straightens walls: deletes one-cell stubs (a wall cell attached to a wall run by one side, open on the other three)
## and opens one wall cell of every diagonal pinch (two walls touching only at a corner). Room perimeters, doorways and
## the chunk border are never touched, so rooms stay sealed and connectivity can only improve.
static func _remove_wall_humps(grid: Array, rooms: Array, region_props: Array) -> void:
	var protected_cells := {}
	for room_value in rooms:
		var rect: Rect2i = (room_value as Dictionary).get("rect", Rect2i())
		for x in range(rect.position.x, rect.end.x):
			protected_cells[Vector2i(x, rect.position.y)] = true
			protected_cells[Vector2i(x, rect.end.y - 1)] = true
		for z in range(rect.position.y, rect.end.y):
			protected_cells[Vector2i(rect.position.x, z)] = true
			protected_cells[Vector2i(rect.end.x - 1, z)] = true
	for prop_value in region_props:
		for cell_value in (prop_value as Dictionary).get("doorway_cells", []):
			protected_cells[cell_value] = true
	var size := CHUNK_SIZE
	var solid := func(x: int, z: int) -> bool:
		return x < 0 or z < 0 or x >= size or z >= size or int(grid[z][x]) != 0
	for _pass in 3:
		var changed := false
		for z in range(2, size - 2):
			for x in range(2, size - 2):
				var here: bool = solid.call(x, z)
				if here and not protected_cells.has(Vector2i(x, z)):
					var attached := []
					for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if solid.call(x + d.x, z + d.y):
							attached.append(d)
					if attached.size() == 1:
						var d: Vector2i = attached[0]
						var n := Vector2i(x, z) + d
						var side := Vector2i(d.y, d.x)
						if solid.call(n.x + side.x, n.y + side.y) and solid.call(n.x - side.x, n.y - side.y):
							grid[z][x] = 0
							changed = true
							continue
				if here and solid.call(x + 1, z + 1) and not solid.call(x + 1, z) and not solid.call(x, z + 1):
					if not protected_cells.has(Vector2i(x, z)):
						grid[z][x] = 0
						changed = true
					elif not protected_cells.has(Vector2i(x + 1, z + 1)):
						grid[z + 1][x + 1] = 0
						changed = true
				elif here and solid.call(x - 1, z + 1) and not solid.call(x - 1, z) and not solid.call(x, z + 1):
					if not protected_cells.has(Vector2i(x, z)):
						grid[z][x] = 0
						changed = true
					elif not protected_cells.has(Vector2i(x - 1, z + 1)):
						grid[z + 1][x - 1] = 0
						changed = true
		if not changed:
			break


static func _restore_authored_room_door_thresholds(grid: Array,
		region_props: Array) -> void:
	for prop_value in region_props:
		var prop: Dictionary = prop_value
		if not bool(prop.get("room_door", false)):
			continue
		for doorway_value in prop.get("doorway_cells",
				[prop.get("cell", Vector2i.ZERO)]):
			var doorway_cell: Vector2i = doorway_value
			if doorway_cell.x < 0 or doorway_cell.y < 0 \
					or doorway_cell.x >= CHUNK_SIZE \
					or doorway_cell.y >= CHUNK_SIZE:
				continue
			grid[doorway_cell.y][doorway_cell.x] = 0


func _room_entry(coord: Vector3i, index: int, region: String, rect: Rect2i,
		room_type: String) -> Dictionary:
	return {"id": "%s:ROOM:%d" % [chunk_id(coord), index], "region": region,
		"room_type": room_type, "rect": rect, "size": rect.size,
		"center": rect.position + rect.size / 2}


static func _room_type_for(region: String, index: int) -> String:
	var types := {
		"mansion": ["drawing_room", "bedroom", "dining_room", "luxury_bathroom"],
		"beach": ["cove", "beach_hut", "tide_pool", "boardwalk_room"],
		"inferno": ["thermal_chamber", "forge", "altar_room", "lava_gallery"],
		"gothic": ["crypt", "chapel", "mourning_room", "archive"],
		"apartment": ["bedroom", "kitchen", "living_room", "house_bathroom"],
		"carnival": ["big_top", "midway", "game_stall", "backstage"],
		"maze": ["restaurant_dining", "arcade_room", "public_restroom", "storage"],
		"prison": ["prison_cell", "prison_cafeteria", "prison_cell", "prison_cell"],
		"hospital": HOSPITAL_ROOMS, "lab": LAB_ROOMS, "greenhouse": GREENHOUSE_ROOMS, "mall": MALL_ROOMS,
	}
	var choices: Array = types.get(region, ["room"])
	return String(choices[index % choices.size()])


static func _carve_rect(grid: Array, rect: Rect2i) -> void:
	for z in range(maxi(1, rect.position.y), mini(CHUNK_SIZE - 1, rect.end.y)):
		for x in range(maxi(1, rect.position.x), mini(CHUNK_SIZE - 1, rect.end.x)):
			grid[z][x] = 0


static func _carve_corridor(grid: Array, from: Vector2i, to: Vector2i,
		width: int) -> void:
	var cursor := from
	while cursor.x != to.x:
		_carve_corridor_cell(grid, cursor, width)
		cursor.x += -1 if cursor.x > to.x else 1
	while cursor.y != to.y:
		_carve_corridor_cell(grid, cursor, width)
		cursor.y += -1 if cursor.y > to.y else 1
	_carve_corridor_cell(grid, to, width)


static func _carve_corridor_cell(grid: Array, cell: Vector2i, width: int) -> void:
	var half := floori(float(width) / 2.0)
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var at := cell + Vector2i(dx, dz)
			if at.x > 0 and at.y > 0 and at.x < CHUNK_SIZE - 1 \
					and at.y < CHUNK_SIZE - 1:
				grid[at.y][at.x] = 0


static func _mark_corridor_cells(marked: Dictionary, from: Vector2i,
		to: Vector2i, width: int) -> void:
	var cursor := from
	while cursor.x != to.x:
		_mark_corridor_cell(marked, cursor, width)
		cursor.x += -1 if cursor.x > to.x else 1
	while cursor.y != to.y:
		_mark_corridor_cell(marked, cursor, width)
		cursor.y += -1 if cursor.y > to.y else 1
	_mark_corridor_cell(marked, to, width)


static func _mark_corridor_cell(marked: Dictionary, cell: Vector2i,
		width: int) -> void:
	var half := floori(float(width) / 2.0)
	for dz in range(-half, half + 1):
		for dx in range(-half, half + 1):
			var at := cell + Vector2i(dx, dz)
			if at.x >= 0 and at.y >= 0 and at.x < CHUNK_SIZE \
					and at.y < CHUNK_SIZE:
				marked[at] = true


static func _mark_rect_cells(marked: Dictionary, rect: Rect2i) -> void:
	for z in range(maxi(0, rect.position.y), mini(CHUNK_SIZE, rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(CHUNK_SIZE, rect.end.x)):
			marked[Vector2i(x, z)] = true


func _region_props(coord: Vector3i, region: String, rooms: Array, grid: Array,
		safe: bool, stairs: Array = [], circulation: Dictionary = {}) -> Array:
	if rooms.is_empty():
		return []
	var choices: Array = (REGION_PROP_SETS.get(region,
		REGION_PROP_SETS["maze"]) as Array).duplicate()
	if choices.is_empty():
		return []
	var rng := SeededRandom.new("%s:DRESSING:%s" % [world_seed, chunk_id(coord)])
	# Residential doors own true room thresholds, not random room corners. Door
	# candidates must have navigable room and corridor cells on opposite sides,
	# and stair footprints are excluded so access carving cannot leave a door
	# floating beside a stairwell.
	var result := _room_door_props(coord, region, rooms, grid, stairs)
	# A lower dual-level carnival room always receives the tall authored ride and
	# two playable midway stations. They are not random dressing: they are the
	# reason this room reserved its matching upper-floor volume.
	for room_value in rooms:
		var dual_room: Dictionary = room_value
		if int(dual_room.get("height_floors", 1)) != 2 \
				or String(dual_room.get("vertical_role", "")) != "lower":
			continue
		var dual_center: Vector2i = dual_room.get("center", Vector2i.ZERO)
		var activity_specs := [
			{"type": "carouselCenterpiece", "cell": dual_center,
				"size": Vector3(1.3, 6.45, 1.3), "offset": Vector2i.ZERO},
			{"type": "ringTossStall", "cell": dual_center + Vector2i(-5, 4),
				"size": Vector3(2.6, 2.65, 1.55), "offset": Vector2i(-5, 4)},
			{"type": "strengthTester", "cell": dual_center + Vector2i(5, 4),
				"size": Vector3(1.0, 2.95, .8), "offset": Vector2i(5, 4)},
		]
		for activity_index in activity_specs.size():
			var activity: Dictionary = activity_specs[activity_index]
			var activity_cell: Vector2i = activity["cell"]
			result.append({
				"id": "%s:DUAL-ACTIVITY:%d" % [chunk_id(coord), activity_index],
				"type": String(activity["type"]), "cell": activity_cell,
				"yaw": 0.0, "facing_target": dual_center,
				"blocker_size": activity["size"], "solid": true,
				"occupied_cells": [activity_cell], "corridor_clear": true,
				"room_id": String(dual_room.get("id", "")),
				"dual_level_activity": true,
			})
	var reserved := {}
	for door in result:
		reserved[door.get("cell", Vector2i.ZERO)] = true
		for threshold_cell in door.get("threshold_wall_cells", []):
			reserved[threshold_cell] = true
	var wall_mount_exclusion := _stair_door_exclusion(stairs)
	var solid_exclusion := circulation.duplicate()
	# Leave a one-cell shoulder around the authored three-wide route. Wide
	# couches, beds and cabinets can then keep their real collision without
	# pinching the shared hallway down to a player-sized slit.
	for traffic_cell_value in circulation:
		_exclude_neighbourhood(solid_exclusion,
			traffic_cell_value as Vector2i, 1)
	for reserved_cell_value in reserved:
		_exclude_neighbourhood(solid_exclusion,
			reserved_cell_value as Vector2i, 1)
	for stair_cell_value in wall_mount_exclusion:
		solid_exclusion[stair_cell_value] = true
	# Furnish named rooms as one deterministic composition. Randomness chooses
	# the mirrored arrangement and visual variants, never a pile of unrelated
	# furniture. Rooms without a recipe retain the lightweight dressing path.
	var templated_rooms := {}
	for room_value in rooms:
		var furnished_room: Dictionary = room_value
		if String(furnished_room.get("room_type", "")) == "stairwell" \
				or bool(furnished_room.get("suite_parent", false)) \
				or int(furnished_room.get("height_floors", 1)) == 2:
			continue
		var furnishing := _furnished_room_props(coord, region, furnished_room,
			grid, reserved)
		if furnishing.is_empty():
			continue
		templated_rooms[String(furnished_room.get("id", ""))] = true
		result.append_array(furnishing)
	var room_order := rooms.duplicate()
	for shuffle_index in range(room_order.size() - 1, 0, -1):
		var swap_index := rng.next_index(shuffle_index + 1)
		var swap_value = room_order[shuffle_index]
		room_order[shuffle_index] = room_order[swap_index]
		room_order[swap_index] = swap_value
	var prop_count := mini(6 if safe else 10, room_order.size())
	for index in prop_count:
		var room: Dictionary = room_order[index]
		# prison_cell interiors are owned by the streamed cell-block dresser.
		# Extra fallback scatter stacked restaurant tables through bunks.
		if String(room.get("room_type", "")) in ["stairwell", "prison_cell"] \
				or bool(room.get("suite_parent", false)) \
				or int(room.get("height_floors", 1)) == 2 \
				or templated_rooms.has(String(room.get("id", ""))):
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		if rect.size.x < 3 or rect.size.y < 3:
			continue
		var choice: Dictionary = choices[rng.next_index(choices.size())]
		var prop_type := String(choice.get("type", "supplyCrates"))
		if PropModelCatalog.is_wall_mounted(prop_type):
			var mount := _wall_mount_for_room(rect, grid, reserved,
				wall_mount_exclusion, rng)
			if mount.is_empty():
				continue
			var mount_cell: Vector2i = mount["cell"]
			var backing_wall: Vector2i = mount["backing_wall"]
			var open_direction := -backing_wall
			result.append({"id": "%s:PROP:%d" % [chunk_id(coord), index],
				"type": prop_type, "cell": mount_cell,
				"yaw": _room_facing_yaw(mount_cell,
					mount_cell + open_direction),
				"facing_target": mount_cell + open_direction,
				# Move the thin model from the open cell centre to just in front of
				# the wall face. The remaining 6 cm avoids coplanar wall z-fighting.
				"mount_offset": Vector2(backing_wall) * .44,
				"backing_wall": backing_wall,
				"open_direction": open_direction,
				"wall_mounted": true,
				"blocker_size": choice.get("size", Vector3.ONE),
				"solid": false})
			reserved[mount_cell] = true
			continue
		var blocker_size: Vector3 = choice.get("size", Vector3.ONE)
		var solid := bool(choice.get("solid", true))
		var room_center: Vector2i = room.get("center", rect.position + rect.size / 2)
		if not solid:
			# Rugs are intentional room-centred dressing. Wall-mounted art takes the
			# dedicated branch above; neither kind can obstruct circulation.
			result.append({"id": "%s:PROP:%d" % [chunk_id(coord), index],
				"type": prop_type, "cell": room_center, "yaw": 0.0,
				"facing_target": room_center,
				"blocker_size": blocker_size, "solid": false,
				"occupied_cells": []})
			reserved[room_center] = true
			continue
		var placement := _solid_prop_placement(rect, grid, solid_exclusion,
			reserved, blocker_size, rng)
		if placement.is_empty():
			continue
		var cell: Vector2i = placement["cell"]
		var open_direction: Vector2i = placement["open_direction"]
		result.append({"id": "%s:PROP:%d" % [chunk_id(coord), index],
			"type": prop_type, "cell": cell,
			"yaw": _room_facing_yaw(cell, cell + open_direction),
			"facing_target": cell + open_direction,
			"placement_offset": placement["placement_offset"],
			"backing_wall": -open_direction,
			"open_direction": open_direction,
			"blocker_size": blocker_size, "solid": true,
			# blocker_size sizes the placement (cells reserved); collider_size is the box the player walks into, from the model
			"collider_size": _collider_size(prop_type, blocker_size),
			"occupied_cells": placement["occupied_cells"],
			"corridor_clear": true})
		for occupied_value in placement["occupied_cells"]:
			var occupied: Vector2i = occupied_value
			reserved[occupied] = true
			_exclude_neighbourhood(solid_exclusion, occupied, 1)
	return result


## The cell of a landing pile in a level -3 chunk, or (-1, -1): forced for dump-hole chunks, else a share of them. It stands
## in the middle chamber, away from ramp landings.
func _landing_pile(coord: Vector3i, grid: Array, chambers: Array, ramps: Array) -> Vector2i:
	if coord.y != INFERNO_LEVEL or chambers.is_empty():
		return Vector2i(-1, -1)
	if not dump_landing_chunks.has(coord) and SeededRandom.new("%s:PILE:%s" % [world_seed, chunk_id(coord)]).next_float() >= LANDING_PILE_SHARE:
		return Vector2i(-1, -1)
	var cell := InfernoCaverns.landing({"grid": grid, "inferno_caverns": chambers})
	for ramp in ramps:
		if (ramp["bottom"] as Rect2i).grow(4).has_point(cell):
			return Vector2i(-1, -1)
	return cell


## Dressing for level -3's caves: basalt pillars, ember braziers and crystal clusters standing against the walls of each
## chamber, off the tunnel mouths, the crevices, the lava and the cages.
func _cave_props(coord: Vector3i, chambers: Array, grid: Array, ramps: Array) -> Array:
	var choices: Array = REGION_PROP_SETS["inferno"]
	var rng := SeededRandom.new("%s:CAVE-DRESSING:%s" % [world_seed, chunk_id(coord)])
	var excluded := {}
	var reserved := {}
	for ramp in ramps:
		for part in ["ramp", "bottom", "connector"]:
			_exclude_rect(excluded, (ramp[part] as Rect2i).grow(2))
	var result := []
	var index := 0
	for chamber_value in chambers:
		var chamber: Dictionary = chamber_value
		for tunnel_cell in chamber["tunnel_cells"]:
			_exclude_neighbourhood(excluded, tunnel_cell as Vector2i, 1)
		for slit in chamber["crevices"]:
			_exclude_neighbourhood(excluded, slit["mouth"] as Vector2i, 2)
		var pit: Dictionary = chamber.get("pit", {})
		if not pit.is_empty():
			for cell in pit["lava"]:
				_exclude_neighbourhood(excluded, cell as Vector2i, 1)
			_exclude_rect(excluded, (pit["bridge"] as Rect2i).grow(3))
			for cage in pit["cages"]:
				excluded[cage["cell"]] = true
			for entry in pit["row"]:
				excluded[entry["cell"]] = true
		var rect: Rect2i = chamber["rect"]
		for _k in 5:
			var choice: Dictionary = choices[rng.next_index(choices.size())]
			var blocker_size: Vector3 = choice.get("size", Vector3.ONE)
			var placement := _solid_prop_placement(rect, grid, excluded, reserved, blocker_size, rng)
			if placement.is_empty():
				continue
			var cell: Vector2i = placement["cell"]
			var open_direction: Vector2i = placement["open_direction"]
			var prop_type := String(choice["type"])
			result.append({"id": "%s:PROP:CAVE:%d" % [chunk_id(coord), index],
				"type": prop_type, "cell": cell,
				"yaw": _room_facing_yaw(cell, cell + open_direction),
				"facing_target": cell + open_direction,
				"placement_offset": placement["placement_offset"],
				"backing_wall": -open_direction,
				"open_direction": open_direction,
				"blocker_size": blocker_size, "solid": true,
				"collider_size": _collider_size(prop_type, blocker_size),
				"occupied_cells": placement["occupied_cells"],
				"corridor_clear": true})
			index += 1
			for occupied_value in placement["occupied_cells"]:
				reserved[occupied_value as Vector2i] = true
				_exclude_neighbourhood(excluded, occupied_value as Vector2i, 1)
	return result


static func _exclude_rect(excluded: Dictionary, rect: Rect2i) -> void:
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			excluded[Vector2i(x, z)] = true


func _furnished_room_props(coord: Vector3i, region: String, room: Dictionary,
		grid: Array, reserved: Dictionary) -> Array:
	var room_type := String(room.get("room_type", ""))
	var rect: Rect2i = room.get("rect", Rect2i())
	if rect.size.x < 5 or rect.size.y < 5:
		return []
	var basis := _room_template_basis(room)
	if basis.is_empty():
		return []
	var side_span := int(basis["side_span"])
	var depth_span := int(basis["depth_span"])
	var template := ""
	if room_type in ["bedroom", "guest_room"]:
		template = "bedroom"
	elif room_type == "kitchen":
		template = "kitchen"
	elif room_type == "dining_room":
		template = "mansion_dining"
	elif room_type == "family_dining":
		template = "family_dining"
	elif room_type == "living_room":
		template = "apartment_living"
	elif room_type == "restaurant_dining":
		template = "restaurant_dining"
	elif room_type == "house_bathroom":
		template = "house_bathroom"
	elif room_type == "hotel_bathroom":
		template = "hotel_bathroom"
	elif room_type == "luxury_bathroom":
		template = "luxury_bathroom"
	elif room_type == "public_restroom":
		template = "public_restroom"
	elif room_type == "arcade_room":
		template = "arcade"
	elif region == "carnival" and room_type in ["midway", "game_stall", "backstage"]:
		template = "carnival_%s" % room_type
	elif region == "beach" and room_type in ["cove", "tide_pool"]:
		template = "frozen_tideline"
	elif region == "beach" and room_type == "beach_hut":
		template = "beach_hut"
	elif region == "gothic" and room_type == "mourning_room":
		template = "gothic_bedroom"
	elif region == "gothic" and room_type in ["archive", "chapel", "crypt"]:
		template = "gothic_%s" % room_type
	elif room_type == "prison_cell":
		template = "prison_cell"
	elif region == "maze" and room_type == "storage":
		template = "maze_storage"
	elif region == "carnival" and room_type == "big_top":
		template = "carnival_big_top"
	elif region == "beach" and room_type == "boardwalk_room":
		template = "boardwalk"
	elif room_type in ["drawing_room", "lounge"]:
		template = "lounge"
	elif room_type == "office_reception":
		template = "office_reception"
	elif room_type == "cubicle_room":
		template = "office_cubicles"
	elif room_type == "office_job":
		template = "office_job"
	elif room_type == "meeting_room":
		template = "office_meeting"
	elif room_type == "private_office":
		template = "private_office"
	elif room_type == "prison_cafeteria":
		template = "prison_cafeteria"
	elif room_type == "infirmary":
		template = "infirmary"
	elif room_type in ["thermal_chamber", "forge", "altar_room", "lava_gallery"]:
		template = room_type
	elif region in ["hospital", "lab", "greenhouse", "mall"] and (HOSPITAL_ROOMS + LAB_ROOMS + GREENHOUSE_ROOMS
			+ MALL_ROOMS + ["dome_atrium", "pod_room"]).has(room_type):
		template = room_type
	elif MusicWing.TEMPLATES.has(room_type):
		template = room_type
	# a room type with no code recipe may have a data recipe (RoomRecipes: built-in data or a content pack)
	if template.is_empty() and RoomRecipes.has(room_type):
		template = room_type
	if template.is_empty():
		return []
	# Great halls (21x21) get the table-grid versions of their gathering-room recipes (docs/ROOM_SIZES.md).
	if side_span >= 15 and depth_span >= 15:
		match template:
			"restaurant_dining":
				template = "restaurant_hall"
			"prison_cafeteria":
				template = "prison_mess"
			"mansion_dining":
				template = "dining_hall"
	# Full furniture compositions require room around the entrance aisle. If a
	# rare narrow room cannot hold one safely, leave it to generic dressing.
	if template in ["mansion_dining", "family_dining", "restaurant_dining",
			"kitchen", "arcade", "frozen_tideline", "luxury_bathroom",
			"public_restroom", "apartment_living"] \
			and (side_span < 7 or depth_span < 7):
		return []
	var rng := SeededRandom.new("%s:TEMPLATE:%s:%s" % [world_seed,
		chunk_id(coord), String(room.get("id", ""))])
	var mirror := -1 if rng.next_float() < .5 else 1
	var specs := _room_template_specs(template, region, side_span, depth_span,
		mirror, rng)
	if specs.is_empty() and RoomRecipes.has(room_type):
		# data recipes draw from their own stream, so they can never shift a code draw
		specs = RoomRecipes.specs(room_type, side_span, depth_span,
			SeededRandom.new("%s:ROOMDATA:%s" % [world_seed, String(room.get("id", ""))]),
			{"@frame": _frame_type_for_region(region, false), "@painting": _frame_type_for_region(region, true),
				"@rug": _rug_type_for_region(region)})
	specs = _vary_specs(specs, side_span, depth_span, SeededRandom.new("%s:VARIETY:%s:%s" % [world_seed, chunk_id(coord),
		String(room.get("id", ""))]))
	var result := []
	for spec_index in _claim_order(specs):
		var spec: Dictionary = specs[spec_index]
		var entry := _template_prop_entry(coord, room, basis, template,
			spec_index, spec, grid, reserved)
		if entry.is_empty():
			continue
		if RoomCatalog.is_surface_prop(String(entry.get("type", ""))) \
				and float(entry.get("mount_y", 0.0)) > 0.0 \
				and not result.any(func(other: Dictionary) -> bool:
					return RoomCatalog.surface_parent_covers(other, entry)):
			continue
		if not _collider_clear(entry, result) and not _nudge_seat_clear(entry, result, grid, rect):
			continue
		entry["spec_index"] = spec_index
		result.append(entry)
		for occupied_value in entry.get("occupied_cells", []):
			if not reserved.has(occupied_value as Vector2i):
				reserved[occupied_value as Vector2i] = SEAT_SHAREABLE    # a placed prop's cell: a seat may tuck into it
	result = even_ceiling_fixtures(one_ceiling_family(result), rect)
	orient_props(result, grid)
	if guarantee_beds and template in BED_TEMPLATES and not result.any(func(e: Dictionary) -> bool:
			return PropModelCatalog.interaction_for(String(e.get("type", ""))) == "lay"):
		var bed := _fallback_bed(coord, room, basis, template, specs, grid, reserved, result)
		if bed.is_empty():
			# hunter-scale furniture can fill a small bedroom before the bed gets a wall: the bed wins, and the floor
			# furniture in its way goes (wall and ceiling props stay)
			var movable := result.filter(func(e: Dictionary) -> bool:
				var t := String(e.get("type", ""))
				return not PropModelCatalog.is_wall_mounted(t) and not PropModelCatalog.is_ceiling_mounted(t))
			var freed := reserved.duplicate()
			for e in movable:
				for cell_value in e.get("occupied_cells", []):
					freed.erase(cell_value as Vector2i)
			var keep := result.filter(func(e: Dictionary) -> bool: return not movable.has(e))
			bed = _fallback_bed(coord, room, basis, template, specs, grid, freed, keep)
			if not bed.is_empty():
				var bed_cells := {}
				for cell_value in bed.get("occupied_cells", []):
					bed_cells[cell_value as Vector2i] = true
				for e in movable:
					var hit := not _collider_clear(bed, [e]) or (e.get("occupied_cells", []) as Array).any(
						func(c: Vector2i) -> bool: return bed_cells.has(c))
					if hit:
						result.erase(e)
						for cell_value in e.get("occupied_cells", []):
							reserved.erase(cell_value as Vector2i)
				# a lamp whose nightstand made way for the bed would float: it goes too
				result = result.filter(func(e: Dictionary) -> bool:
					return not RoomCatalog.is_surface_prop(String(e.get("type", ""))) or float(e.get("mount_y", 0.0)) <= 0.0 \
						or result.any(func(other: Dictionary) -> bool: return RoomCatalog.surface_parent_covers(other, e)))
		if not bed.is_empty():
			bed["spec_index"] = specs.size()
			result.append(bed)
			for occupied_value in bed.get("occupied_cells", []):
				reserved[occupied_value as Vector2i] = true
	# back to recipe order, so everything downstream sees the same sequence as before the claim order
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["spec_index"]) < int(b["spec_index"]))
	for entry in result:
		entry.erase("spec_index")
	return result


## Things standing on furniture (a lamp on a dresser, a computer on a desk) are authored at the person-sized parent's top
## (`mount_y`). The parent is drawn at its hunter scale (PropModelCatalog.HUNTER_SCALE), so its top is that much higher:
## raise the mount with it, or the lamp sinks into the dresser (docs/PROP_SIZES.md).
static func scale_surface_mounts(props: Array) -> void:
	for prop_value in props:
		var prop: Dictionary = prop_value
		var mount := float(prop.get("mount_y", 0.0))
		if mount <= 0.0 or not RoomCatalog.is_surface_prop(String(prop.get("type", ""))) or bool(prop.get("mount_scaled", false)):
			continue
		for parent_value in props:
			var parent: Dictionary = parent_value
			if parent != prop and RoomCatalog.surface_parent_covers(parent, prop):
				prop["mount_y"] = mount * PropModelCatalog.hunter_scale(String(parent.get("type", "")))
				prop["mount_scaled"] = true
				break


## KT: "a gothic bedroom is nearly empty, no bed". A bedroom never goes without a bed: when the recipe's bed could not be
## placed (the room narrower than the bed, a door or the 3-wide opening on its wall cell, a wardrobe claiming it), the
## bed is tried along the whole back wall, then the side walls' spans, and then smaller types, before giving up.
const BED_TEMPLATES := ["bedroom", "gothic_bedroom"]
const FALLBACK_BEDS := ["singleBed", "bunkBed"]
static var guarantee_beds := true


func _fallback_bed(coord: Vector3i, room: Dictionary, basis: Dictionary, template: String, specs: Array, grid: Array,
		reserved: Dictionary, placed: Array) -> Dictionary:
	var types := []
	for spec in specs:
		if PropModelCatalog.interaction_for(String(spec.get("type", ""))) == "lay" and not types.has(spec["type"]):
			types.append(spec["type"])
	for t in FALLBACK_BEDS:
		if not types.has(t):
			types.append(t)
	var span := int(basis.get("side_span", 9)) / 2
	for type in types:
		for step in range(0, span + 1):
			for side in ([0] if step == 0 else [-step, step]):
				var spec := {"type": type, "side": side, "depth": 0, "wall_backed": true, "facing": "open"}
				var entry := _template_prop_entry(coord, room, basis, template, specs.size(), spec, grid, reserved)
				if not entry.is_empty() and _collider_clear(entry, placed):
					return entry
	return {}


## Ceiling fixtures by family (KT: "chandeliers AND ceiling fans together"). A room keeps one family: a chandelier
## wins over a fan, a fan (which has its own light kit) over a plain ceiling light; the others are dropped.
const CEILING_FIXTURE_FAMILY := {"diningChandelier": "chandelier", "ceilingFan": "fan", "ceilingLight": "light"}
const CEILING_FAMILY_ORDER := ["chandelier", "fan", "light"]


## Recipe ceiling fixtures laid out evenly (KT: "center or even with the room"): one sits at the exact centre of the
## room's interior; several form rows along the long axis (two rows in a room 12+ cells deep when there are 4 or more),
## each at the middle of an equal share, so they are symmetric about the centre with equal margins to the walls. The
## fixture keeps its cell (and room); placement_offset moves it. Leftovers that would break the grid are dropped.
static func even_ceiling_fixtures(props: Array, rect: Rect2i) -> Array:
	var fixtures := props.filter(func(prop: Dictionary) -> bool:
		return CEILING_FIXTURE_FAMILY.has(String(prop.get("type", ""))))
	if fixtures.is_empty():
		return props
	var long_x := rect.size.x >= rect.size.y
	var short_len := float(mini(rect.size.x, rect.size.y))
	var rows := 2 if fixtures.size() >= 4 and short_len >= 12.0 else 1
	var cols := fixtures.size() / rows
	var along := func(prop: Dictionary) -> float:
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		return float(cell.x if long_x else cell.y)
	fixtures.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return along.call(a) < along.call(b))
	var long_start := float(rect.position.x if long_x else rect.position.y)
	var long_len := float(rect.size.x if long_x else rect.size.y)
	var short_start := float(rect.position.y if long_x else rect.position.x)
	var dropped := {}
	for index in fixtures.size():
		var prop: Dictionary = fixtures[index]
		if index >= rows * cols:
			dropped[prop] = true
			continue
		var a := long_start + long_len * (float(index % cols) + .5) / float(cols)
		var b := short_start + short_len * (float(index / cols) + .5) / float(rows)
		var desired := Vector2(a, b) if long_x else Vector2(b, a)
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		prop["placement_offset"] = desired - (Vector2(cell) + Vector2(.5, .5))
	if dropped.is_empty():
		return props
	return props.filter(func(prop: Dictionary) -> bool: return not dropped.has(prop))


## KT: "computers facing backwards". A screen (computer, CRT console, terminal, monitor) faces whoever sits at it: the
## nearest seat within SCREEN_SEAT_REACH turns the screen toward it (gameplay -Z, which the model's screen side follows).
const SCREEN_SEAT_REACH := 2.6


static func prop_point(prop: Dictionary) -> Vector2:
	var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
	return Vector2(cell) + Vector2(.5, .5) + (prop.get("placement_offset", Vector2.ZERO) as Vector2)


## KT: "check other connected props and make sure they're rotated correctly". The pairing table, applied to every
## furnished room after placement (so new recipes follow it too). Wall-backed types first: a prop whose back is not on a
## wall but whose cell touches one turns its back to that wall (depth permitting) and slides flush. Then the facing pairs,
## child -> nearest anchor within reach (children that are wall-backed keep their wall). Word matches on the type name.
const ORIENT_PAIRS := [
	# seats face the table, desk or counter they are pulled up to
	{"child": ["Chair", "Stool"], "anchor": ["Table", "Desk", "Counter", "Island", "Workstation", "Bar", "Station", "Console"],
		"reach": 1.4},
	# sofas face the TV or the coffee table
	{"child": ["Couch", "Sofa", "Chaise"], "anchor": ["TvConsole", "CoffeeTable"], "reach": 4.5},
	# a bench faces its piano or vanity
	{"child": ["Bench"], "anchor": ["Piano", "Vanity"], "reach": 1.5},
	# screens face whoever uses them: a seat, else a bed (vitals monitors)
	{"child": ["Computer", "Monitor", "Console", "Terminal"], "anchor": ["Chair", "Stool", "Couch", "Bench"], "reach": 2.6},
	{"child": ["Monitor"], "anchor": ["Bed"], "reach": 2.0},
]
const ORIENT_EXCLUDE := ["TvConsole"]   # the TV sits against its wall; the sofa turns to it


static func _type_has(type: String, words: Array) -> bool:
	for word in words:
		if String(word) in type:
			return true
	return false


static func is_screen_type(type: String) -> bool:
	return _type_has(type, ["Computer", "Monitor", "Console", "Terminal"]) and not _type_has(type, ORIENT_EXCLUDE)


static func orient_props(props: Array, grid: Array) -> void:
	seat_in_front_of_screens(props, grid)
	for prop_value in props:
		var prop: Dictionary = prop_value
		if RoomCatalog.is_wall_backed(String(prop.get("type", ""))):
			back_to_wall(prop, grid)
	for rule_value in ORIENT_PAIRS:
		var rule: Dictionary = rule_value
		for child_value in props:
			var child: Dictionary = child_value
			var type := String(child.get("type", ""))
			if not _type_has(type, rule["child"]) or _type_has(type, ORIENT_EXCLUDE) or RoomCatalog.is_wall_backed(type) \
					or bool(child.get("oriented", false)):
				continue
			var anchor := nearest_anchor(child, props, rule["anchor"], float(rule["reach"]))
			if anchor.is_empty():
				continue
			var toward := prop_point(anchor) - prop_point(child)
			var yaw := snappedf(atan2(-toward.x, -toward.y), PI * .25)   # room props stay on 45-degree angles
			var size: Vector3 = child.get("collider_size", child.get("blocker_size", Vector3.ONE))
			var turn := absf(wrapf(yaw - float(child.get("yaw", 0.0)), -PI, PI))
			if (size.x > .95 or size.z > .95) and turn > .01 and absf(turn - PI) > .01:
				continue    # a prop wider than a cell only flips (same footprint); turning it would hit its neighbours
			child["yaw"] = yaw
			child["oriented"] = true


## A screen too wide to turn (a lab console) whose seat is off to its side: the seat moves to the open floor in front of
## the screen (the screenshot KT sent: the chair beside the desk, the screen facing away), then turns to it.
static func seat_in_front_of_screens(props: Array, grid: Array) -> void:
	for screen_value in props:
		var screen: Dictionary = screen_value
		if not is_screen_type(String(screen.get("type", ""))):
			continue
		var size: Vector3 = screen.get("collider_size", screen.get("blocker_size", Vector3.ONE))
		if size.x <= .95 and size.z <= .95:
			continue
		var seat := nearest_anchor(screen, props, ["Chair", "Stool"], 2.6)
		if seat.is_empty():
			continue
		var yaw := float(screen.get("yaw", 0.0))
		var front := Vector2(-sin(yaw), -cos(yaw))
		var at := prop_point(screen)
		if front.dot((prop_point(seat) - at).normalized()) > .7:
			continue
		var spot := at + front * (size.z * .5 + .55)
		var cell := Vector2i(floori(spot.x), floori(spot.y))
		if cell.y < 0 or cell.y >= grid.size() or cell.x < 0 or cell.x >= (grid[cell.y] as Array).size() \
				or int(grid[cell.y][cell.x]) != 0:
			continue
		var taken := false
		for other_value in props:
			var other: Dictionary = other_value
			if other != seat and other != screen and bool(other.get("solid", true)) \
					and (prop_point(other).distance_to(spot) < .6 or (other.get("occupied_cells", []) as Array).has(cell)):
				taken = true
				break
		if taken:
			continue
		seat["cell"] = cell
		seat["occupied_cells"] = [cell]    # the seat's collider moved with it; reservations and reachability follow
		seat["placement_offset"] = spot - (Vector2(cell) + Vector2(.5, .5))
		seat["yaw"] = snappedf(atan2(front.x, front.y), PI * .25)    # facing back at the screen
		seat["oriented"] = true


static func nearest_anchor(child: Dictionary, props: Array, words: Array, reach: float) -> Dictionary:
	var at := prop_point(child)
	var best := {}
	var best_distance := reach
	for other_value in props:
		var other: Dictionary = other_value
		if other == child or not _type_has(String(other.get("type", "")), words):
			continue
		var distance := at.distance_to(prop_point(other))
		if distance > .05 and distance < best_distance:
			best = other
			best_distance = distance
	return best


## Back (gameplay +Z) to a wall: keep a back already on a wall; otherwise turn to the wall the cell touches (first of the
## four sides that is a wall), when the prop's depth fits in a cell, and slide it flush.
static func back_to_wall(prop: Dictionary, grid: Array) -> void:
	if bool(prop.get("wall_mounted", false)) or not bool(prop.get("solid", true)):
		return
	var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
	if wall_behind(prop, grid):
		return
	var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
	if size.z > .95 or size.x > .95:
		return    # turning a prop wider than a cell could push it into a neighbour
	for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var wall: Vector2i = cell + dir
		if wall.y < 0 or wall.y >= grid.size() or wall.x < 0 or wall.x >= (grid[wall.y] as Array).size() \
				or int(grid[wall.y][wall.x]) == 0:
			continue
		# back = gameplay +Z toward the wall, so the front (-Z) points away from it
		prop["yaw"] = atan2(float(dir.x), float(dir.y))
		prop["placement_offset"] = Vector2(dir) * (.48 - back_extent(String(prop.get("type", "")), size))
		return


## How far the prop's collision reaches behind its point (local +Z), offset collider boxes included.
static func back_extent(type: String, size: Vector3) -> float:
	var extent := 0.0
	for box in PropColliderBoxes.boxes(type, size):
		extent = maxf(extent, (box["c"] as Vector2).y + (box["h"] as Vector2).y)
	return extent if extent > 0.0 else size.z * .5


## The prop's back face (+Z) is within 15 cm of a wall cell.
static func wall_behind(prop: Dictionary, grid: Array) -> bool:
	var yaw := float(prop.get("yaw", 0.0))
	var back := Vector2(sin(yaw), cos(yaw))
	var size: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
	var probe := prop_point(prop) + back * (back_extent(String(prop.get("type", "")), size) + .15)
	var cell := Vector2i(floori(probe.x), floori(probe.y))
	return cell.y >= 0 and cell.y < grid.size() and cell.x >= 0 and cell.x < (grid[cell.y] as Array).size() \
		and int(grid[cell.y][cell.x]) != 0


static func one_ceiling_family(props: Array) -> Array:
	var families := {}
	for prop in props:
		var family := String(CEILING_FIXTURE_FAMILY.get(String(prop.get("type", "")), ""))
		if not family.is_empty():
			families[family] = true
	if families.size() <= 1:
		return props
	var keep := ""
	for family in CEILING_FAMILY_ORDER:
		if families.has(family):
			keep = family
			break
	return props.filter(func(prop: Dictionary) -> bool:
		var family := String(CEILING_FIXTURE_FAMILY.get(String(prop.get("type", "")), ""))
		return family.is_empty() or family == keep)


## Big props claim their space first: solid specs by footprint (largest first), then the rest; ties keep recipe order, so
## a bed or counter is never dropped because a chair or crate listed earlier took its cell. Surface props come after the
## desks and tables that carry them. Deterministic (depends only on the recipe).
## `reserved` value for a cell a placed recipe prop took (doors and thresholds are `true`): only seats may share it.
const SEAT_SHAREABLE := "prop"


## An authored (person-sized) blocker size, as big as the view draws the prop (PropModelCatalog.HUNTER_SCALE).
static func hunter_sized(type: String, size: Vector3) -> Vector3:
	return size * PropModelCatalog.hunter_scale(type)


static func _claim_order(specs: Array) -> Array:
	var order := []
	for i in specs.size():
		var spec: Dictionary = specs[i]
		var type := String(spec.get("type", ""))
		var area := 0.0
		if bool(spec.get("solid", not bool(spec.get("wall_mount", false)))) and not RoomCatalog.is_surface_prop(type):
			var size: Vector3 = PropColliderSizes.SIZES.get(type, hunter_sized(type, TEMPLATE_PROP_SIZES.get(type, Vector3.ZERO)))
			area = size.x * size.z
		if bool(spec.get("claim_first", false)):
			area = INF
		order.append([area, i])
	order.sort_custom(func(a: Array, b: Array) -> bool:
		return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var out := []
	for pair in order:
		out.append(pair[1])
	return out


## A seat set around a table at fixed cells (dining sets, cafeteria rows, desks) hits its hunter-scale table: slide it
## straight back from what it faces, 15 cm at a time up to 1.2 m, until it is clear and still inside the room on open
## floor (docs/PROP_SIZES.md). Only seats move; anything else that collides is dropped as before.
static func _nudge_seat_clear(entry: Dictionary, placed: Array, grid: Array, rect: Rect2i) -> bool:
	if PropModelCatalog.interaction_for(String(entry.get("type", ""))) != "sit":
		return false
	var yaw := float(entry.get("yaw", 0.0))
	var back := Vector2(sin(yaw), cos(yaw))    # gameplay yaw: -Z faces the target, the back is +Z
	var start: Vector2 = entry.get("placement_offset", Vector2.ZERO)
	var cell: Vector2i = entry.get("cell", Vector2i.ZERO)
	for step in range(1, 9):
		var offset := start + back * .15 * float(step)
		var at := Vector2(cell) + Vector2(.5, .5) + offset
		var at_cell := Vector2i(floori(at.x), floori(at.y))
		if not rect.has_point(at_cell) or not _grid_cell_open(grid, at_cell):
			return false
		entry["placement_offset"] = offset
		if _collider_clear(entry, placed):
			return true
	entry["placement_offset"] = start
	return false


## Prop clearance as a placement rule: a solid prop's collision boxes may not interpenetrate an already placed solid's
## beyond what GeometryAudit allows (a chair tucked under its table, a stool at a counter).
static func _collider_clear(entry: Dictionary, placed: Array) -> bool:
	if not bool(entry.get("solid", true)) or bool(entry.get("wall_mounted", false)):
		return true
	var mine := _collider_rects(entry)
	for other in placed:
		if not bool(other.get("solid", true)) or bool(other.get("wall_mounted", false)):
			continue
		var allowance := GeometryAudit.tol() + GeometryAudit.pair_allowance(String(entry["type"]), String(other["type"]))
		for a in mine:
			for b in _collider_rects(other):
				if GeometryAudit.obb_depth(a["c"], a["h"], a["yaw"], b["c"], b["h"], b["yaw"]) > allowance:
					return false
	return true


static func _collider_rects(prop: Dictionary) -> Array:
	var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
	var at := Vector2(cell) + Vector2(.5, .5) + Vector2(prop.get("mount_offset", Vector2.ZERO)) + Vector2(prop.get("placement_offset", Vector2.ZERO))
	var yaw := float(prop.get("yaw", 0.0))
	var out := []
	for box in PropColliderBoxes.for_prop(prop):
		out.append({"c": PropColliderBoxes.world_centre(at, box["c"], yaw), "h": box["h"], "yaw": yaw})
	return out


## A grid of long tables for a great hall. Each table sits at (column side, row depth) with `chair_span` chairs along both
## long edges (rows at depth-1 facing the table, depth+1 facing back) and, with `heads`, one chair at each end. Rows are 5
## cells apart, columns 6, so every table is ringed by one-cell chair rows and walking lanes of at least two cells.
static func _table_grid_specs(table_type: String, chair_type: String, columns: Array, rows: Array,
		chair_span: int, heads: bool, rng: SeededRandom) -> Array:
	var specs := []
	var plain := chair_type.trim_suffix("Cushion")
	for column in columns:
		for row in rows:
			specs.append({"type": table_type, "side": column, "depth": row, "facing": "open"})
			if chair_type.is_empty():
				continue
			var half := chair_span / 2
			for offset in range(-half, half + 1):
				var pick := chair_type if rng.next_float() < .6 else plain
				specs.append({"type": pick, "side": column + offset, "depth": row - 1, "facing": "open"})
				pick = chair_type if rng.next_float() < .6 else plain
				specs.append({"type": pick, "side": column + offset, "depth": row + 1, "facing": "back"})
			if heads:
				specs.append({"type": chair_type, "side": column - half - 1, "depth": row, "facing": "right"})
				specs.append({"type": chair_type, "side": column + half + 1, "depth": row, "facing": "left"})
	return specs


## KT: "room generation seeds are too specific". Every furnished room (code or data recipe) gets its own variation, drawn
## from a stream keyed on the seed, chunk and room id (so peers agree and no code draw shifts): its lights, rugs, frames,
## signs and other non-solid or wall-mounted dressing move one or two cells, on top of the recipe's own mirror. Solid
## furniture keeps its tuned place (aisles, key props and reachability are validated on it).
static func _vary_specs(specs: Array, side_span: int, depth_span: int, rng: SeededRandom) -> Array:
	var out := []
	for spec_value in specs:
		var spec: Dictionary = (spec_value as Dictionary).duplicate()
		var mounted := bool(spec.get("wall_mount", false)) or bool(spec.get("wall_mounted", false))
		# wall pieces that are only decoration move along their wall; a working wall fixture (a headset shelf) stays
		var decor_on_wall := mounted and ["Frame", "Painting", "Sign", "Clock", "Poster"].any(
			func(word: String) -> bool: return word in String(spec.get("type", "")))
		if (decor_on_wall or (not mounted and not bool(spec.get("solid", true)))) and rng.next_float() < .75:
			var step := 1 + rng.next_index(2)
			spec["side"] = int(spec.get("side", 0)) + (step if rng.next_float() < .5 else -step)
			if not mounted and int(spec.get("depth", 0)) > 0 and rng.next_float() < .5:
				spec["depth"] = maxi(1, int(spec.get("depth", 0)) + (1 if rng.next_float() < .5 else -1))
		out.append(spec)
	# and a lamp or two of its own where the room has the floor for it (non-solid: clearance never changes)
	var half := (side_span - 3) / 2
	if not specs.is_empty() and half >= 3 and depth_span >= 7:
		for _extra in rng.next_index(3):
			out.append({"type": "ceilingLight", "side": rng.next_index(half * 2 + 1) - half,
				"depth": 1 + rng.next_index(maxi(1, depth_span - 4)), "facing": "open", "solid": false})
	return out


static func _room_template_specs(template: String, region: String,
		side_span: int, depth_span: int, mirror: int, rng: SeededRandom) -> Array:
	var mid_depth := depth_span / 2
	var frame_type := _frame_type_for_region(region, false)
	var painting_type := _frame_type_for_region(region, true)
	var rug_type := _rug_type_for_region(region)
	var specs := []
	match template:
		"bedroom":
			var bed_type := "doubleBed" if side_span >= 9 \
					and rng.next_float() < .45 else "singleBed"
			if side_span >= 11 and depth_span >= 9 and rng.next_float() < .25:
				bed_type = "bunkBed"
			specs.append({"type": bed_type, "side": -1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "bedroomNightstand", "side": 1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "tableLamp", "side": 1 * mirror,
				"depth": 0, "facing": "open", "solid": false, "mount_y": .71})
			specs.append({"type": "ceilingFan", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			if not rug_type.is_empty():
				specs.append({"type": rug_type, "side": 0,
					"depth": mid_depth, "facing": "open", "solid": false})
			if side_span >= 9:
				specs.append({"type": "bedroomWardrobe", "side": 3 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "bedroomDresser", "side": -3 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "bedroomVanity", "side": 5 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "vanityStool", "side": 5 * mirror,
					"depth": 1, "facing": "back"})
				specs.append({"type": "normalBookcase", "side": -5 * mirror,
					"depth": 2, "wall_backed": false, "facing": "center"})
			specs.append({"type": "standingMirror", "side": 2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			if not frame_type.is_empty():
				specs.append({"type": frame_type, "side": -3 * mirror,
					"depth": 0, "facing": "open", "wall_mount": true,
					"solid": false})
			if depth_span >= 9:
				specs.append({"type": "woodenTable", "side": -3 * mirror,
					"depth": mid_depth, "facing": "center"})
				specs.append({"type": "woodenChairCushion", "side": -3 * mirror,
					"depth": mid_depth + 1, "facing": "back"})
				specs.append({"type": "normalTvConsole", "side": 2 * mirror,
					"depth": mid_depth + 1, "facing": "center"})
		"gothic_bedroom":
			specs.append({"type": "gothicDoubleBed", "side": -1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "gothicNightstand", "side": 1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "tableLamp", "side": 1 * mirror,
				"depth": 0, "facing": "open", "solid": false, "mount_y": .76})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			if side_span >= 9:
				specs.append({"type": "gothicWardrobe", "side": 3 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "gothicHighbackChair", "side": -3 * mirror,
					"depth": mid_depth, "facing": "center"})
		"kitchen":
			for kitchen_spec in [
				{"type": "normalKitchenCounter", "side": -3, "depth": 0},
				{"type": "normalKitchenSink", "side": -1, "depth": 0},
				{"type": "normalKitchenStove", "side": 1, "depth": 0},
				{"type": "normalKitchenFridge", "side": 3, "depth": 0},
			]:
				kitchen_spec["side"] = int(kitchen_spec["side"]) * mirror
				kitchen_spec["wall_backed"] = true
				kitchen_spec["facing"] = "open"
				specs.append(kitchen_spec)
			if side_span >= 9 and depth_span >= 9:
				specs.append({"type": "normalKitchenIsland", "side": 0,
					"depth": mid_depth, "facing": "open"})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
		"mansion_dining":
			specs.append({"type": "diningSideboard", "side": 0, "depth": 0,
				"wall_backed": true, "facing": "open"})
			specs.append({"type": "diningTable", "side": 0,
				"depth": mid_depth, "facing": "open"})
			specs.append({"type": "diningChandelier", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			var mansion_seats := [
				{"side": -2, "depth": mid_depth, "facing": "right"},
				{"side": 2, "depth": mid_depth, "facing": "left"},
			]
			# Six side chairs plus two head chairs make the long formal table read
			# as a mansion dining composition instead of a four-seat kitchen set.
			for seat_side in [-1, 0, 1]:
				mansion_seats.append({"side": seat_side,
					"depth": mid_depth - 1, "facing": "open"})
				mansion_seats.append({"side": seat_side,
					"depth": mid_depth + 1, "facing": "back"})
			for chair_spec in mansion_seats:
				chair_spec["type"] = "diningChairCushion" \
					if rng.next_float() < .5 else "diningChair"
				specs.append(chair_spec)
		"family_dining":
			specs.append({"type": "woodenDresserSideboard", "side": 0,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "woodenTable", "side": 0,
				"depth": mid_depth, "facing": "open"})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			for chair_spec in [
				{"side": -1, "depth": mid_depth, "facing": "right"},
				{"side": 1, "depth": mid_depth, "facing": "left"},
				{"side": 0, "depth": mid_depth - 1, "facing": "open"},
				{"side": 0, "depth": mid_depth + 1, "facing": "back"},
			]:
				chair_spec["type"] = "woodenChairCushion" \
					if rng.next_float() < .45 else "woodenChair"
				specs.append(chair_spec)
		"restaurant_dining":
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			# Repeated party tables read as one deliberate restaurant floor, with
			# an aisle around each row instead of unrelated furniture scatter.
			var table_depths := [1, 4]
			if depth_span >= 12:
				table_depths.append(7)
			for row_index in table_depths.size():
				var table_depth: int = table_depths[row_index]
				specs.append({"type": "restaurantPartyTable", "side": 0,
					"depth": table_depth, "facing": "open"})
				for chair_side in [-1, 0, 1]:
					specs.append({"type": "woodenChairCushion",
						"side": chair_side, "depth": table_depth - 1,
						"facing": "open"})
					specs.append({"type": "woodenChairCushion",
						"side": chair_side, "depth": table_depth + 1,
						"facing": "back"})
		"restaurant_hall":
			specs.append_array(_table_grid_specs("restaurantPartyTable", "woodenChairCushion", [-6, 0, 6], [3, 8, 13], 3, false, rng))
			for light_side in [-6, 0, 6]:
				for light_depth in [3, 8, 13]:
					specs.append({"type": "ceilingLight", "side": light_side, "depth": light_depth, "facing": "open", "solid": false})
			# the serving counter runs along the back wall
			for counter_side in [-6, 0, 6]:
				specs.append({"type": "diningSideboard", "side": counter_side, "depth": 0, "wall_backed": true, "facing": "open"})
		"prison_mess":
			specs.append({"type": "prisonServingCounter", "side": -3 * mirror, "depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "prisonKitchenRack", "side": 4 * mirror, "depth": 0, "wall_backed": true, "facing": "open"})
			specs.append_array(_table_grid_specs("prisonCafeteriaTable", "", [-6, 0, 6], [4, 9, 14], 0, false, rng))
			for light_side in [-6, 0, 6]:
				for light_depth in [4, 9, 14]:
					specs.append({"type": "ceilingLight", "side": light_side, "depth": light_depth, "facing": "open", "solid": false})
			specs.append({"type": "prisonTrayReturn", "side": 7 * mirror, "depth": 17, "facing": "open"})
		"dining_hall":
			specs.append_array(_table_grid_specs("diningTable", "diningChairCushion", [-5, 5], [4, 9, 14], 3, true, rng))
			for light_side in [-5, 5]:
				for light_depth in [4, 9, 14]:
					specs.append({"type": "diningChandelier", "side": light_side, "depth": light_depth, "facing": "open", "solid": false})
			specs.append({"type": "diningSideboard", "side": 0, "depth": 0, "wall_backed": true, "facing": "open"})
		"prison_cafeteria":
			# Institutional serving line on the rear wall, with a clear queue
			# aisle and repeated bolted tables rather than loose room scatter.
			# 5-deep / 5-wide wings only have a 3x3 interior, so the counter
			# must be centred and side equipment stays on the front corners.
			# the serving line is the room's point: it claims before the (hunter-scale) tables
			specs.append({"type": "prisonServingCounter", "side": 0,
				"depth": 0, "wall_backed": true, "facing": "open", "claim_first": true})
			# side kit beside the table line (hunter-scale tables are 3.9 m long), at the walls where the room is wide enough
			var kit_side := 3 if side_span >= 7 else 1
			specs.append({"type": "prisonKitchenRack", "side": -kit_side * mirror,
				"depth": maxi(2, mid_depth), "facing": "open"})
			# Linear prison wings are only five cells deep. A middle-row table
			# keeps the serving line clear; wider halls can take a second row.
			var table_depths := [1]
			# hunter-scale tables are 2.6 m deep: rows stand clear of the 1.5 m serving counter and of the door row
			if depth_span >= 9:
				table_depths = [mid_depth]
			if depth_span >= 12:
				table_depths = [mid_depth - 1, mid_depth + 2]
			if depth_span >= 15:
				table_depths.append(mid_depth + 6)
			for table_depth in table_depths:
				if table_depth <= 0:
					continue
				specs.append({"type": "prisonCafeteriaTable", "side": 0,
					"depth": table_depth, "facing": "open"})
			# The tray return sits at the side of the queue, not in the aisle
			# and not on the sealed side wall of a 5-wide wing.
			specs.append({"type": "prisonTrayReturn", "side": kit_side * mirror,
				"depth": maxi(2, mid_depth), "facing": "open", "claim_first": true})
			specs.append({"type": "ceilingLight", "side": -2,
				"depth": mid_depth, "facing": "open", "solid": false})
			specs.append({"type": "ceilingLight", "side": 2,
				"depth": mid_depth, "facing": "open", "solid": false})
			specs.append({"type": "supplyCrates", "side": -1 * mirror,
				"depth": depth_span - 1, "facing": "back"})
		"thermal_chamber":
			specs.append({"type": "lavaVent", "side": -2 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "lavaVent", "side": 2 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "magmaCrystalCluster", "side": 0,
				"depth": mid_depth + 1, "facing": "center"})
			specs.append({"type": "infernoChainLantern", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
		"forge":
			specs.append({"type": "lavaPipeManifold", "side": -2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "emberBrazier", "side": 2 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "charredSupplyCrate", "side": 0,
				"depth": mid_depth + 1, "facing": "center"})
			specs.append({"type": "infernoChainLantern", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
		"altar_room":
			specs.append({"type": "infernoAltar", "side": 0,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "emberBrazier", "side": -2 * mirror,
				"depth": mid_depth + 1, "facing": "center"})
			specs.append({"type": "emberBrazier", "side": 2 * mirror,
				"depth": mid_depth + 1, "facing": "center"})
			specs.append({"type": "infernoChainLantern", "side": 0,
				"depth": mid_depth - 1, "facing": "open", "solid": false})
		"lava_gallery":
			specs.append({"type": "basaltPillar", "side": -2 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "basaltPillar", "side": 2 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "basaltRubble", "side": -1 * mirror,
				"depth": mid_depth + 2, "facing": "center"})
			specs.append({"type": "magmaCrystalCluster", "side": 1 * mirror,
				"depth": mid_depth + 2, "facing": "center"})
			specs.append({"type": "infernoChainLantern", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
		"house_bathroom", "hotel_bathroom":
			var compact := template == "hotel_bathroom" or side_span < 7
			var wet_side := -1 if compact else -2
			var toilet_side := 1 if compact else 2
			specs.append({"type": "houseShowerEnclosure" if compact \
				else ("houseBathtub" if rng.next_float() < .55 \
				else "houseShowerEnclosure"), "side": wet_side,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "houseToilet", "side": toilet_side,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "bathroomVanity", "side": 0,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "bathroomMirror", "side": 0, "depth": 0,
				"facing": "open", "wall_mount": true})
			specs.append({"type": "houseBathMat", "side": wet_side,
				"depth": 2, "facing": "open", "solid": false})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			if not compact:
				specs.append({"type": "houseTowelRack", "side": 3,
					"depth": 0, "facing": "open", "wall_mount": true})
		"luxury_bathroom":
			specs.append({"type": "houseBathtub", "side": -2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "houseShowerEnclosure", "side": 2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "bathroomVanity", "side": 0,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "houseToilet", "side": 3 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "bathroomMirror", "side": 0, "depth": 0,
				"facing": "open", "wall_mount": true})
			specs.append({"type": "houseTowelRack", "side": -3 * mirror,
				"depth": 0, "facing": "open", "wall_mount": true})
			specs.append({"type": "houseBathMat", "side": 0,
				"depth": mid_depth + 1, "facing": "open", "solid": false})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
		"public_restroom":
			for stall_side in [-2, 0]:
				specs.append({"type": "bathroomStall", "side": stall_side,
					"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "publicRestroomToilet", "side": 2,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "publicSinkBank", "side": 0,
				"depth": mid_depth, "facing": "back"})
			specs.append({"type": "bathroomMirror", "side": 0, "depth": 0,
				"facing": "open", "wall_mount": true})
			specs.append({"type": "publicHandDryer", "side": 3,
				"depth": 0, "facing": "open", "wall_mount": true})
			specs.append({"type": "publicSoapDispenser", "side": -3,
				"depth": 0, "facing": "open", "wall_mount": true})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
		"arcade":
			# Two opposing cabinet rows share their backs while both fronts retain
			# a full playable aisle, matching a real arcade floor.
			for side in [-2, 0, 2]:
				var cabinet_type := "arcadeCabinetCyanMagenta" \
					if rng.next_float() < .34 else "arcadeCabinet"
				specs.append({"type": cabinet_type, "side": side,
					"depth": mid_depth, "facing": "back"})
				specs.append({"type": "arcadeCabinet", "side": side,
					"depth": mid_depth + 1, "facing": "open"})
			if side_span >= 9:
				specs.append({"type": "vendingMachine", "side": 3 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
		"carnival_midway":
			if side_span >= 17:
				# a 21-wide midway: a row of stalls along the back wall and carts and pedestals down the middle
				var stall_types := ["ringTossStall", "shootingGallery", "whackAMole"]
				for stall_index in 3:
					specs.append({"type": stall_types[stall_index], "side": [-7, 0, 7][stall_index], "depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "carnivalTicketBooth", "side": -4, "depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "prizeClawMachine", "side": 4, "depth": 0, "wall_backed": true, "facing": "open"})
				# Backed against the SIDE walls and facing the middle: with the back wall as its backing a 1.4 m wide tester
				# stood 0.2 m into the side wall (GeometryAudit prop_in_wall) and pushing it clear hit the end stall.
				specs.append({"type": "strengthTester", "side": -9, "depth": 1, "facing": "center"})
				specs.append({"type": "strengthTester", "side": 9, "depth": 1, "facing": "center"})
				for cart_side in [-6, 6]:
					specs.append({"type": "popcornCart", "side": cart_side, "depth": mid_depth + 1, "facing": "center"})
				specs.append({"type": "circusPedestal", "side": 0, "depth": mid_depth + 1, "facing": "center"})
				for light_side in [-6, 0, 6]:
					specs.append({"type": "ceilingLight", "side": light_side, "depth": mid_depth, "facing": "open", "solid": false})
			else:
				specs.append({"type": "carnivalTicketBooth", "side": -2 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "popcornCart", "side": 2 * mirror,
					"depth": mid_depth, "facing": "center"})
				specs.append({"type": "circusPedestal", "side": -2 * mirror,
					"depth": mid_depth + 2, "facing": "center"})
		"carnival_big_top":
			specs.append({"type": "arcadeCarpetCircle", "side": 0, "depth": mid_depth, "facing": "open", "solid": false})
			# the room's centre is the working merry-go-round (CarouselRide3D); a duck pond and a pedestal either side
			if side_span >= 17 and depth_span >= 17:
				specs.append({"type": "carouselCenterpiece", "side": 0, "depth": mid_depth, "facing": "center"})
			# 2-3 cells clear round the ride on every side (validate_carousel): the pond and pedestal stand out at the flanks
			var flank := 8 if side_span >= 17 else 6
			specs.append({"type": "duckPond", "side": flank, "depth": mid_depth, "facing": "center"})
			specs.append({"type": "circusPedestal", "side": -flank, "depth": mid_depth, "facing": "center"})
			for booth_side in [-8, 8]:
				specs.append({"type": "carnivalTicketBooth", "side": booth_side, "depth": 0, "wall_backed": true, "facing": "open"})
			for cart_side in [-4, 4]:
				specs.append({"type": "popcornCart", "side": cart_side, "depth": 1, "facing": "open"})
			for light_side in [-6, 0, 6]:
				specs.append({"type": "ceilingLight", "side": light_side, "depth": mid_depth, "facing": "open", "solid": false})
		"boardwalk":
			for umbrella_side in [-7, -1, 5]:
				specs.append({"type": "beachUmbrella", "side": umbrella_side, "depth": mid_depth, "facing": "center"})
				specs.append({"type": "beachChair", "side": umbrella_side - 2, "depth": mid_depth + 1, "facing": "center"})
				specs.append({"type": "beachChair", "side": umbrella_side + 2, "depth": mid_depth + 1, "facing": "center"})
				specs.append({"type": "beachMat", "side": umbrella_side, "depth": mid_depth + 2, "facing": "open", "solid": false})
			specs.append({"type": "tikiBar", "side": -8, "depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "surfboardRack", "side": 8, "depth": 0, "wall_backed": true, "facing": "open"})
		"prison_cell":
			# a bunk on each side wall of the back, a toilet and sink between them (no loose dining furniture in prison cells)
			specs.append({"type": "prisonBunk", "side": -3, "depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "prisonBunk", "side": 3, "depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "houseToilet", "side": -1, "depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "bathroomSink", "side": 1, "depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "ceilingLight", "side": 0, "depth": mid_depth, "facing": "open", "solid": false})
		"gothic_archive":
			for shelf_side in range(-8, 9, 2):
				specs.append({"type": "gothicBookcase", "side": shelf_side, "depth": 0, "wall_backed": true, "facing": "open"})
			for desk_side in [-5, 5]:
				specs.append({"type": "gothicPedestalTable", "side": desk_side, "depth": mid_depth, "facing": "open"})
				specs.append({"type": "gothicHighbackChair", "side": desk_side, "depth": mid_depth - 1, "facing": "open"})
				specs.append({"type": "gothicHighbackChair", "side": desk_side, "depth": mid_depth + 1, "facing": "back"})
			specs.append({"type": "libraryGlobe", "side": 3, "depth": 1, "facing": "center"})
			specs.append({"type": "readingTable", "side": 0, "depth": mid_depth - 2, "facing": "open"})
			specs.append({"type": "gothicHighbackChair", "side": 0, "depth": mid_depth - 3, "facing": "open"})
			specs.append({"type": "gothicBedroomRug", "side": 0, "depth": mid_depth, "facing": "open", "solid": false})
			for light_side in [-6, 0, 6]:
				specs.append({"type": "ceilingLight", "side": light_side, "depth": mid_depth, "facing": "open", "solid": false})
		"gothic_chapel":
			specs.append({"type": "gothicPedestalTable", "side": 0, "depth": 0, "wall_backed": true, "facing": "open"})
			for candle_side in [-3, 3]:
				specs.append({"type": "gothicFloorCandelabra", "side": candle_side, "depth": 0, "wall_backed": true, "facing": "open"})
			for pew_row in [3, 5, 7]:
				for pew_side in [-6, -3, 3, 6]:
					specs.append({"type": "gothicBedroomBench", "side": pew_side, "depth": pew_row, "facing": "back"})
			specs.append({"type": "gothicBedroomRug", "side": 0, "depth": 4, "facing": "open", "solid": false})
			for light_side in [-6, 0, 6]:
				specs.append({"type": "ceilingLight", "side": light_side, "depth": mid_depth, "facing": "open", "solid": false})
		"gothic_crypt":
			for coffin_side in [-8, -4, 0, 4, 8]:
				specs.append({"type": "gothicCoffinChest", "side": coffin_side, "depth": 2, "facing": "open"})
			for coffin_side in [-6, -2, 2, 6]:
				specs.append({"type": "gothicCoffinChest", "side": coffin_side, "depth": 6, "facing": "open"})
			for candle_side in [-9, 9]:
				specs.append({"type": "gothicFloorCandelabra", "side": candle_side, "depth": 0, "wall_backed": true, "facing": "open"})
		"infirmary":
			# hunter-scale beds are 1.54 m wide: the IV stand stands two cells over, the curtains a row further in
			for bed_side in [-4, 0, 4]:
				specs.append({"type": "hospitalBed", "side": bed_side, "depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "ivStand", "side": bed_side + 2, "depth": 0, "facing": "open"})
			for curtain_side in [-2, 2]:
				specs.append({"type": "privacyCurtain", "side": curtain_side, "depth": 2, "facing": "right"})
			for cart_side in [-3, 3]:
				specs.append({"type": "medicalCart", "side": cart_side, "depth": mid_depth + 1, "facing": "back"})
			for light_side in [-3, 3]:
				specs.append({"type": "ceilingLight", "side": light_side, "depth": mid_depth, "facing": "open", "solid": false})
		"maze_storage":
			for shelf_side in range(-8, 9, 2):
				specs.append({"type": "storageShelving" if shelf_side % 4 == 0 else "normalBookcase", "side": shelf_side,
					"depth": 0, "wall_backed": true, "facing": "open"})
			for barrel_side in [-8, -7, 7, 8]:
				specs.append({"type": "storageBarrel", "side": barrel_side, "depth": mid_depth + 2, "facing": "open"})
			for crate_side in [-6, -2, 2, 6]:
				specs.append({"type": "supplyCrates", "side": crate_side, "depth": mid_depth, "facing": "open"})
			for box_side in [-4, 4]:
				specs.append({"type": "officeFileBoxes", "side": box_side, "depth": mid_depth + 2, "facing": "open"})
			for light_side in [-6, 0, 6]:
				specs.append({"type": "ceilingLight", "side": light_side, "depth": mid_depth, "facing": "open", "solid": false})
		"carnival_game_stall":
			specs.append({"type": "ringTossStall", "side": -2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "strengthTester", "side": 2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			if depth_span >= 9:
				specs.append({"type": "popcornCart", "side": 0,
					"depth": mid_depth + 2, "facing": "center"})
		"carnival_backstage":
			for side in [-2, 0, 2]:
				specs.append({"type": "arcadeCabinet", "side": side,
					"depth": 0, "wall_backed": true, "facing": "open"})
		"frozen_tideline":
			specs.append({"type": "frozenTidelinePool", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			specs.append({"type": "beachChair", "side": -3 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "beachUmbrella", "side": 3 * mirror,
				"depth": mid_depth + 2, "facing": "center"})
			if side_span >= 11:
				specs.append({"type": "tikiBar", "side": -4 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
				specs.append({"type": "surfboardRack", "side": 4 * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
		"beach_hut":
			specs.append({"type": "frozenBeachHut", "side": -2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "beachChair", "side": 2 * mirror,
				"depth": mid_depth, "facing": "center"})
		"apartment_living":
			# TV wall at the back, one big couch facing it with a coffee table and rug between, an armchair,
			# a dining set nearer the entrance; the entrance lane (side 0, door side) stays clear.
			specs.append({"type": "normalTvConsole", "side": 0, "depth": 0,
				"wall_backed": true, "facing": "open"})
			specs.append({"type": "normalBookcase", "side": -3 * mirror, "depth": 0,
				"wall_backed": true, "facing": "open"})
			specs.append({"type": "floorLamp", "side": -2 * mirror, "depth": 0,
				"wall_backed": true, "facing": "open"})
			specs.append({"type": "normalCoffeeTable", "side": 0, "depth": 3, "facing": "back"})
			specs.append({"type": "loungeCouchWide", "side": 0, "depth": 5, "facing": "back"})
			specs.append({"type": "loungeCouch", "side": 3 * mirror, "depth": 3, "facing": "center"})
			specs.append({"type": "diningTable", "side": -2 * mirror, "depth": 7, "facing": "open"})
			specs.append({"type": "woodenChairCushion", "side": -2 * mirror, "depth": 6, "facing": "center"})
			specs.append({"type": "woodenChairCushion", "side": -2 * mirror, "depth": 8, "facing": "center"})
			specs.append({"type": "ceilingLight", "side": 0, "depth": 4,
				"facing": "open", "solid": false})
			if not rug_type.is_empty():
				specs.append({"type": rug_type, "side": 0, "depth": 3,
					"facing": "open", "solid": false})
			if not painting_type.is_empty():
				specs.append({"type": painting_type, "side": 1 * mirror, "depth": 0,
					"facing": "open", "wall_mount": true, "solid": false})
		"lounge":
			specs.append({"type": "loungeCouchWide", "side": -1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			for plant_side in [-4, 4]:
				specs.append({"type": "pottedPlant", "side": plant_side,
					"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "libraryGlobe", "side": -3 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "normalCoffeeTable", "side": -1 * mirror,
				"depth": mid_depth, "facing": "back"})
			specs.append({"type": "normalTvConsole", "side": 2 * mirror,
				"depth": mid_depth, "facing": "center"})
			specs.append({"type": "floorLamp", "side": 2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "ceilingFan", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			if not rug_type.is_empty():
				specs.append({"type": rug_type, "side": -1 * mirror,
					"depth": mid_depth, "facing": "open", "solid": false})
			if not painting_type.is_empty():
				specs.append({"type": painting_type, "side": 2 * mirror,
					"depth": 0, "facing": "open", "wall_mount": true,
					"solid": false})
		"office_reception":
			# The desk sits to one side of the door aisle (PlacementClearance keeps the walk from the door open).
			specs.append({"type": "receptionDesk", "side": -1 * mirror,
				"depth": 1, "facing": "open"})
			specs.append({"type": "officeChair", "side": -1 * mirror,
				"depth": 0, "facing": "open"})
			for plant_side in [-2, 1]:
				specs.append({"type": "pottedPlant", "side": plant_side * mirror,
					"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "filingCabinet", "side": 2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "officeWaterCooler", "side": 2 * mirror,
				"depth": mid_depth + 1, "facing": "center"})
			specs.append({"type": "normalPictureFrameEmpty", "side": 0,
				"depth": 0, "facing": "open", "wall_mount": true,
				"solid": false})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth - 1, "facing": "open", "solid": false})
		"office_cubicles":
			# 7x7 amenity rooms have a 5-cell interior. A 1.65 m desk occupies
			# three cells, so side ±2 lands on the sealed walls. Stagger the
			# banks so two desks and the printer table do not share occupancy.
			for desk_spec in [
				{"side": -1, "depth": 1, "computer": "retroComputerTerminal"},
				{"side": 1, "depth": 3, "computer": "retroComputerTower"},
			]:
				specs.append({"type": "officeDesk", "side": desk_spec["side"],
					"depth": desk_spec["depth"], "facing": "open"})
				specs.append({"type": "officeChair", "side": desk_spec["side"],
					"depth": int(desk_spec["depth"]) + 1, "facing": "back"})
				specs.append({"type": String(desk_spec["computer"]),
					"side": desk_spec["side"], "depth": desk_spec["depth"],
					"facing": "open", "solid": false, "mount_y": .78})
			specs.append({"type": "filingCabinet", "side": -1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			# Centre equipment desk owns the printer so it is not desk-height air.
			specs.append({"type": "officeDesk", "side": 0,
				"depth": 2, "facing": "open"})
			specs.append({"type": "officeCubiclePartition", "side": 0,
				"depth": 0, "facing": "open"})
			specs.append({"type": "officePrinter", "side": 0,
				"depth": 2, "facing": "open", "solid": false,
				"mount_y": .78})
			specs.append({"type": "officePhotocopier", "side": -1 * mirror,
				"depth": 4, "facing": "center"})
			specs.append({"type": "officeFileBoxes", "side": 1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "normalPictureFrameEmpty", "side": 1 * mirror,
				"depth": 0, "facing": "open", "wall_mount": true,
				"solid": false})
			specs.append({"type": "ceilingLight", "side": -1,
				"depth": mid_depth, "facing": "open", "solid": false})
			specs.append({"type": "ceilingLight", "side": 1,
				"depth": mid_depth, "facing": "open", "solid": false})
		"office_meeting":
			specs.append({"type": "woodenTable", "side": 0,
				"depth": mid_depth, "facing": "open"})
			specs.append({"type": "woodenTable", "side": 0,
				"depth": mid_depth + 2, "facing": "open"})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false})
			for chair_spec in [
				{"side": -1, "depth": mid_depth, "facing": "right"},
				{"side": 1, "depth": mid_depth, "facing": "left"},
				{"side": 0, "depth": mid_depth - 1, "facing": "open"},
				{"side": 0, "depth": mid_depth + 1, "facing": "back"},
			]:
				chair_spec["type"] = "woodenChairCushion"
				specs.append(chair_spec)
			specs.append({"type": "filingCabinet", "side": -2 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "retroComputerTower", "side": 0,
				"depth": mid_depth, "facing": "open", "solid": false,
				"mount_y": .78})
			specs.append({"type": "normalTvConsole", "side": 0,
				"depth": mid_depth + 3, "facing": "center"})
			specs.append({"type": "normalPaintingFrameEmpty", "side": 2 * mirror,
				"depth": 0, "facing": "open", "wall_mount": true,
				"solid": false})
		"office_job":
			# Three 1.65 m desks cannot share one depth in a 5-cell interior.
			# Stagger them so each computer sits on a desk that actually fits.
			specs.append({"type": "officeDesk", "side": -1,
				"depth": mid_depth, "facing": "open"})
			specs.append({"type": "officeDesk", "side": 1,
				"depth": mid_depth + 1, "facing": "open"})
			specs.append({"type": "officeDesk", "side": 0,
				"depth": 1, "facing": "open"})
			for chair_spec in [
				{"type": "officeChair", "side": -1,
					"depth": mid_depth - 1, "facing": "right"},
				{"type": "officeChair", "side": 1,
					"depth": mid_depth - 1, "facing": "left"},
				{"type": "officeChair", "side": -1,
					"depth": mid_depth + 1, "facing": "left"},
				{"type": "officeChair", "side": 1,
					"depth": mid_depth + 1, "facing": "right"},
				{"type": "officeChair", "side": 0,
					"depth": 2, "facing": "back"},
			]:
				specs.append(chair_spec)
			specs.append({"type": "officePhotocopier", "side": -1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "officeFileBoxes", "side": 1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "filingCabinet", "side": 0,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "retroComputerTerminal", "side": -1,
				"depth": mid_depth, "facing": "open", "solid": false,
				"mount_y": .78})
			specs.append({"type": "retroComputerTower", "side": 1,
				"depth": mid_depth + 1, "facing": "open", "solid": false,
				"mount_y": .78})
			specs.append({"type": "retroComputerDesktop", "side": 0,
				"depth": 1, "facing": "open", "solid": false,
				"mount_y": .78})
			specs.append({"type": "normalTvConsole", "side": 0,
				"depth": mid_depth + 3, "facing": "center"})
			specs.append({"type": "officeWaterCooler", "side": 1 * mirror,
				"depth": 4, "facing": "center"})
			specs.append({"type": "officeShredder", "side": -1 * mirror,
				"depth": 4, "facing": "center"})
			specs.append({"type": "normalPaintingFrameEmpty", "side": 0,
				"depth": 0, "facing": "open", "wall_mount": true,
				"solid": false})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth - 1, "facing": "open", "solid": false})
		"private_office":
			# Place the workstation first. Its 3x3 envelope owns the back
			# interior; accessories go on the front corners so they cannot
			# steal those cells and leave the computer floating.
			specs.append({"type": "officeCornerWorkstation", "side": 0,
				"depth": 1, "facing": "open"})
			specs.append({"type": "retroComputerDesktop", "side": 0,
				"depth": 1, "facing": "open", "solid": false,
				"mount_y": .78})
			specs.append({"type": "officePhotocopier", "side": -1 * mirror,
				"depth": 4, "facing": "center"})
			specs.append({"type": "filingCabinet", "side": 1 * mirror,
				"depth": 4, "facing": "center"})
			specs.append({"type": "officeChair", "side": 0,
				"depth": 3, "facing": "back"})
			specs.append({"type": "woodenChair", "side": -1 * mirror,
				"depth": 3, "facing": "right"})
			specs.append({"type": "woodenChair", "side": 1 * mirror,
				"depth": 3, "facing": "left"})
			specs.append({"type": "normalTvConsole", "side": 0,
				"depth": 4, "facing": "center"})
			specs.append({"type": "normalPaintingFrameEmpty", "side": 0,
				"depth": 0, "facing": "open", "wall_mount": true,
				"solid": false})
			specs.append({"type": "officeWaterCooler", "side": 1 * mirror,
				"depth": 0, "wall_backed": true, "facing": "open"})
			specs.append({"type": "ceilingLight", "side": 0,
				"depth": mid_depth - 1, "facing": "open", "solid": false})
	if region in ["hospital", "lab", "greenhouse", "mall"]:
		specs.append_array(_region_room_specs(template, (side_span - 3) / 2, depth_span, mirror))
	# the music wing's rooms (docs/MUSIC_WING.md): the stage, practice rooms, store, booth, the mall music store, the carnival stage
	if MusicWing.TEMPLATES.has(template):
		specs.append_array(MusicWing.room_specs(template, (side_span - 3) / 2, depth_span, mirror))
	# 21-wide hall rooms (docs/ROOM_SIZES.md): the inferno recipes repeat across the width instead of leaving it bare
	if side_span >= 17 and depth_span <= 11 and template in ["thermal_chamber", "forge", "altar_room", "lava_gallery"]:
		var originals := specs.duplicate()
		for shift in [-7, 7]:
			for original in originals:
				var copy: Dictionary = (original as Dictionary).duplicate()
				copy["side"] = int(copy.get("side", 0)) + shift
				specs.append(copy)
	if region == "mansion":
		# no plain fans or strip lights in the mansion: its ceiling fixture is a chandelier (crystal-and-brass finish)
		for spec_value in specs:
			if String(spec_value.get("type", "")) in ["ceilingFan", "ceilingLight"]:
				spec_value["type"] = "diningChandelier"
	if region == "mansion" and template in ["bedroom", "lounge", "mansion_dining", "dining_hall"]:
		# Mansion luxury (docs/MANSION_LUXURY.md): marble columns in the back corners, porcelain vases on the back wall.
		var corner := maxi(2, side_span / 2 - 1)
		for column_side in [-corner, corner]:
			specs.append({"type": "mansionMarbleColumn", "side": column_side, "depth": 0, "wall_backed": true, "facing": "open"})
		for vase_side in [-corner + 1, corner - 1]:
			specs.append({"type": "mansionPorcelainVase", "side": vase_side, "depth": 1, "facing": "open"})
	return _keep_entrance_clear(specs, side_span, depth_span)


## The room entrance is the middle of the front interior row (depth_span - 3: the rect includes both walls and depth 0 is the
## first interior row): a solid footprint (its collider, either way round) must
## not cover that cell, or the door opens onto a prop and the room is sealed for hunters (found by hunter_real on REAL-B).
static func _keep_entrance_clear(specs: Array, _side_span: int, depth_span: int) -> Array:
	var kept := []
	for spec in specs:
		var entry: Dictionary = spec
		if bool(entry.get("wall_backed", false)) or entry.get("solid", true) == false:
			kept.append(entry)
			continue
		var size: Vector3 = PropColliderSizes.SIZES.get(String(entry.get("type", "")), Vector3.ONE)
		# its extents across the room and toward the door, by its facing (a long table set along the back wall reaches
		# sideways, not toward the door); "center" can face any way, so it keeps the long side both ways
		var across_half := maxf(size.x, size.z) * .5
		var toward_half := across_half
		match String(entry.get("facing", "open")):
			"open", "back":
				across_half = size.x * .5
				toward_half = size.z * .5
			"left", "right":
				across_half = size.z * .5
				toward_half = size.x * .5
		var covers_door := absf(float(entry.get("side", 0))) - across_half < .5 \
			and float(entry.get("depth", 0)) + toward_half > float(depth_span) - 3.5
		if not covers_door:
			kept.append(entry)
	return kept


## One template spec: `side` across the room (0 = the door's column), `depth` from the back wall (0 = first interior row).
static func _sp(type: String, side: int, depth: int, facing: String = "open", extra: Dictionary = {}) -> Dictionary:
	var spec := {"type": type, "side": side, "depth": depth, "facing": facing}
	spec.merge(extra)
	return spec


const _WALL := {"wall_backed": true}
const _MOUNT := {"wall_mount": true, "solid": false}
const _LOOSE := {"solid": false}


## Hospital, research lab and greenhouse rooms (docs/REGIONS.md). Recipes are written for the 11-wide bank room (interior
## sides -4..4, depths 0..front); REGION_REPEAT_TEMPLATES are laid twice, at sides -5 and +5, across a 21-wide hall room.
## `front` is the entrance row; nothing solid lands on its middle cell (_keep_entrance_clear) and recipes keep the
## middle column in front of the door free so the room reads from the doorway.
static func _region_room_specs(template: String, half: int, depth_span: int, mirror: int) -> Array:
	var front := depth_span - 3
	var mid := front / 2
	var specs := []
	match template:
		# ---- hospital ----
		"ward":
			# beds head-to-wall every fourth column (hunter-scale beds are 1.54 m wide) with a ceiling-track curtain midway
			# between neighbours
			var bed_sides := range(-half, half + 1, 4)
			for bed_index in bed_sides.size():
				var bed_side: int = bed_sides[bed_index]
				specs.append(_sp("hospitalBed", bed_side, 0, "open", _WALL))
				if bed_side + 2 <= half:
					specs.append(_sp("hospitalCurtain", bed_side + 2, 1, "right"))
				# drip stands and monitors stand in front of the curtain lines, so every bed foot stays open; a row past the
				# 3.2 m hunter-scale bed's foot, or the stand closes the bay's mouth (pickup_reach on REAL-B)
				var kit_side := bed_side + 1 if bed_side + 1 <= half else bed_side - 1
				specs.append(_sp("ivDripStand" if bed_index % 2 == 0 else "vitalsMonitor", kit_side, 4, "back"))
			if depth_span >= 15:
				# a great-hall ward: a facing bed row by the entrance wall and the nurses' desk in the middle
				for bed_side in range(-half, half + 1, 4):
					if absi(bed_side) <= 2:
						continue
					specs.append(_sp("hospitalBed", bed_side, front - 1, "back"))
					if bed_side + 2 <= half and absi(bed_side + 2) > 2:
						specs.append(_sp("hospitalCurtain", bed_side + 2, front - 1, "right"))
				specs.append(_sp("nursesStation", 0, mid, "open"))
				specs.append(_sp("officeChair", -1, mid - 1, "open"))
				specs.append(_sp("officeChair", 1, mid - 1, "open"))
				specs.append(_sp("medicalSupplyRack", -4, mid, "center"))
				specs.append(_sp("wheelchair", 4, mid, "center"))
			for light_side in range(-half + 2, half, 4):
				specs.append(_sp("ceilingLight", light_side, mid, "open", _LOOSE))
			specs.append(_sp("hospitalWardSign", 1, 0, "open", _MOUNT))
		"nurses_station":
			specs.append(_sp("nursesStation", 0, 2, "open"))
			specs.append(_sp("officeChair", -1, 1, "open"))
			specs.append(_sp("officeChair", 1, 1, "open"))
			specs.append(_sp("medicalSupplyRack", -3 * mirror, 0, "open", _WALL))
			specs.append(_sp("filingCabinet", 3 * mirror, 0, "open", _WALL))
			specs.append(_sp("filingCabinet", 4 * mirror, 0, "open", _WALL))
			specs.append(_sp("vitalsMonitor", -4 * mirror, 3, "center"))
			specs.append(_sp("ivDripStand", -3 * mirror, 4, "center"))
			specs.append(_sp("wheelchair", 3 * mirror, 4, "center"))
			specs.append(_sp("hospitalWardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"waiting_room":
			for row_side in [-3, 0, 3]:
				specs.append(_sp("waitingChairs", row_side, 0, "open", _WALL))
			specs.append(_sp("waitingChairs", -3, 3, "open"))
			specs.append(_sp("waitingChairs", 3, 3, "open"))
			specs.append(_sp("vendingMachine", -4 * mirror, front - 1, "center"))
			specs.append(_sp("officeWaterCooler", 4 * mirror, front - 1, "center"))
			specs.append(_sp("bananaPlant", 4 * mirror, 2, "center"))
			specs.append(_sp("magazineRack", -4 * mirror, 2, "center"))
			specs.append(_sp("hospitalWardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", -2, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 2, mid, "open", _LOOSE))
		"operating_theatre":
			specs.append(_sp("operatingTable", 0, 2, "open"))
			specs.append(_sp("surgicalLight", 0, 2, "open", _LOOSE))
			specs.append(_sp("instrumentTrolley", 2 * mirror, 2, "center"))
			specs.append(_sp("vitalsMonitor", -2 * mirror, 1, "center"))
			specs.append(_sp("ivDripStand", -2 * mirror, 3, "center"))
			specs.append(_sp("medicalSupplyRack", 3 * mirror, 0, "open", _WALL))
			specs.append(_sp("biohazardBin", -4 * mirror, 0, "open", _WALL))
			specs.append(_sp("xrayLightbox", 0, 0, "open", _MOUNT))
			specs.append(_sp("hazardSign", -2 * mirror, 0, "open", _MOUNT))
		"icu":
			# hunter-scale beds (1.54 m wide) sit two cells off the centre line: 1.7 m between each bed and its side wall and
			# 2.4 m between the beds, all wider than a hunter, so no strip beside a bed is a dead pocket
			for bay in [-2, 2]:
				specs.append(_sp("hospitalBed", bay, 0, "open", _WALL))
				specs.append(_sp("vitalsMonitor", bay * 2, 0, "open", _WALL))
				specs.append(_sp("ivDripStand", signi(bay), 0, "center"))
			# past the beds' feet (depth 3), so the strip between a bed and its side wall stays open at its foot
			specs.append(_sp("instrumentTrolley", -4 * mirror, 5, "center"))
			specs.append(_sp("medicalSupplyRack", 4 * mirror, 5, "center"))
			specs.append(_sp("hospitalWardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", -2, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 2, mid, "open", _LOOSE))
		"morgue":
			specs.append(_sp("morgueCabinet", -2, 0, "open", _WALL))
			specs.append(_sp("morgueCabinet", 2, 0, "open", _WALL))
			specs.append(_sp("autopsyTable", 0, 3, "open"))
			specs.append(_sp("instrumentTrolley", 2 * mirror, 3, "center"))
			specs.append(_sp("biohazardBin", -4 * mirror, 3, "center"))
			specs.append(_sp("hazardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"pharmacy":
			for shelf_side in [-3, 0, 3]:
				specs.append(_sp("pharmacyShelf", shelf_side, 0, "open", _WALL))
			specs.append(_sp("nursesStation", 0, 3, "open"))
			specs.append(_sp("officeChair", 0, 2, "open"))
			specs.append(_sp("medicalSupplyRack", -3 * mirror, 3, "center"))
			specs.append(_sp("filingCabinet", 4 * mirror, 3, "center"))
			specs.append(_sp("hospitalWardSign", 2 * mirror, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, 1, "open", _LOOSE))
		"imaging":
			specs.append(_sp("xrayMachine", 0, 1, "open"))
			specs.append(_sp("xrayLightbox", -3 * mirror, 0, "open", _MOUNT))
			specs.append(_sp("hazardSign", 3 * mirror, 0, "open", _MOUNT))
			specs.append(_sp("officeDesk", 3 * mirror, 3, "center"))
			specs.append(_sp("retroComputerDesktop", 3 * mirror, 3, "center", {"solid": false, "mount_y": .78}))
			specs.append(_sp("officeChair", 4 * mirror, 3, "center"))
			specs.append(_sp("wheelchair", -3 * mirror, 3, "center"))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"supply_closet":
			for rack_side in [-3, 0, 3]:
				specs.append(_sp("medicalSupplyRack", rack_side, 0, "open", _WALL))
			specs.append(_sp("supplyCrates", -3 * mirror, 3, "center"))
			specs.append(_sp("utilityCart", 3 * mirror, 3, "center"))
			specs.append(_sp("wheelchair", -4 * mirror, front - 1, "center"))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		# ---- research lab ----
		"clean_room":
			# glass airlock: two partitions across the front leave a one-door gap behind the entrance
			specs.append(_sp("labGlassPartition", -3, front - 2, "open"))
			specs.append(_sp("labGlassPartition", 3, front - 2, "open"))
			specs.append(_sp("labBench", -2, 0, "open", _WALL))
			specs.append(_sp("labBench", 2, 0, "open", _WALL))
			specs.append(_sp("labMicroscope", -2, 0, "open", {"solid": false, "mount_y": .92}))
			specs.append(_sp("labStool", -2, 1, "back"))
			specs.append(_sp("labStool", 2, 1, "back"))
			specs.append(_sp("specimenTank", 4 * mirror, 2, "center"))
			specs.append(_sp("hazardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", -2, mid - 1, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 2, mid - 1, "open", _LOOSE))
		"containment":
			var cell_sides := [-3, 3] if half < 9 else [-7, -3, 3, 7]
			var tank_sides := [0] if half < 9 else [-5, 0, 5]
			for cell_side in cell_sides:
				specs.append(_sp("containmentCell", cell_side, 0, "open", _WALL))
				specs.append(_sp("hazardSign", cell_side, 0, "open", _MOUNT))
			for tank_side in tank_sides:
				specs.append(_sp("specimenTank", tank_side, 0, "open", _WALL))
			if half >= 9 or depth_span >= 11:
				specs.append(_sp("controlConsole", 0, mid + 1, "back"))
				specs.append(_sp("officeChair", -1, mid + 2, "back"))
				specs.append(_sp("officeChair", 1, mid + 2, "back"))
			if depth_span >= 15:
				for cell_side in cell_sides:
					specs.append(_sp("containmentCell", cell_side, front - 1, "back"))
				for tank_side in [-5, 5]:
					specs.append(_sp("specimenTank", tank_side, mid, "center"))
			specs.append(_sp("biohazardBin", -half * mirror, mid, "center"))
			for light_side in range(-half + 2, half, 4):
				specs.append(_sp("ceilingLight", light_side, mid, "open", _LOOSE))
		"server_hall":
			# a rack row on the back wall and back-to-back island rows (hot/cold aisles), cooling units at the ends
			for rack_side in range(-half, half + 1):
				specs.append(_sp("serverRack", rack_side, 0, "open", _WALL))
			var island := 2
			while island + 1 <= front - 3:
				# the islands stop a rack short of each side wall: hunter-scale racks need a wider end aisle to walk round
				for rack_side in range(-half + 3, half - 2):
					specs.append(_sp("serverRack", rack_side, island, "back"))
					specs.append(_sp("serverRack", rack_side, island + 1, "open"))
				specs.append(_sp("labCoolingUnit", -half, island, "center"))
				specs.append(_sp("labCoolingUnit", half, island + 1, "center"))
				island += 6
			specs.append(_sp("hazardSign", 0, 0, "open", _MOUNT))
			for light_side in range(-half + 1, half, 3):
				specs.append(_sp("ceilingLight", light_side, 1, "open", _LOOSE))
		"pod_room":
			# the dive lab (Last Route lore): six white pods in a curved row along the far wall, lids open, heads to the
			# wall; the outer pair stands a step forward so the row bows. Two still have film on their lids, one is left
			# on (a faint glow), the rest dark. A headset on a stand beside each pod; the console with its scrolling list
			# and the shelf of headsets above it in the corner.
			var pod_sides := [-5, -3, -1, 1, 3, 5]
			for pod_index in pod_sides.size():
				var pod_side: int = pod_sides[pod_index] * mirror
				var pod_type := "divePod"
				if pod_index == 1 or pod_index == 4:
					pod_type = "divePodFilm"
				elif pod_index == 2:
					pod_type = "divePodLit"
				var outer := pod_index == 0 or pod_index == pod_sides.size() - 1
				specs.append(_sp(pod_type, pod_side, 1 if outer else 0, "open", {} if outer else _WALL))
				specs.append(_sp("diveHeadsetStand", pod_side + mirror, 0, "open", _WALL))
			specs.append(_sp("diveConsole", (half - 1) * mirror, 0, "open", _WALL))
			specs.append(_sp("diveHeadsetShelf", (half - 1) * mirror, 0, "open", {"wall_mount": true, "solid": false, "mount_y": 1.45}))
		"control_room":
			specs.append(_sp("monitorWall", 0, 0, "open", _MOUNT))
			specs.append(_sp("controlConsole", 0, 2, "back"))
			specs.append(_sp("officeChair", -1, 3, "back"))
			specs.append(_sp("officeChair", 1, 3, "back"))
			specs.append(_sp("serverRack", -4, 0, "open", _WALL))
			specs.append(_sp("serverRack", 4, 0, "open", _WALL))
			specs.append(_sp("filingCabinet", 4 * mirror, front - 1, "center"))
			specs.append(_sp("officeWaterCooler", -4 * mirror, front - 1, "center"))
			specs.append(_sp("labWhiteboard", -3 * mirror, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"decon":
			specs.append(_sp("deconShower", -2, 0, "open", _WALL))
			specs.append(_sp("deconShower", 2, 0, "open", _WALL))
			specs.append(_sp("locker", -4, 0, "open", _WALL))
			specs.append(_sp("locker", 4, 0, "open", _WALL))
			specs.append(_sp("labGlassPartition", -3, front - 2, "open"))
			specs.append(_sp("labGlassPartition", 3, front - 2, "open"))
			# no bench on the door axis: with the airlock partitions it closed the room off (WORLD lane, seed PICKUPS)
			specs.append(_sp("publicShowerBench", -3, 1, "open"))
			specs.append(_sp("biohazardBin", -4 * mirror, 3, "center"))
			specs.append(_sp("hazardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, 2, "open", _LOOSE))
		"chem_lab":
			specs.append(_sp("fumeHood", -3 * mirror, 0, "open", _WALL))
			specs.append(_sp("labBench", 1 * mirror, 0, "open", _WALL))
			specs.append(_sp("gasCylinderRack", 4 * mirror, 0, "open", _WALL))
			specs.append(_sp("labBench", 0, 3, "open"))
			specs.append(_sp("labMicroscope", 0, 3, "open", {"solid": false, "mount_y": .92}))
			specs.append(_sp("labStool", -1, 4, "back"))
			specs.append(_sp("labStool", 1, 4, "back"))
			specs.append(_sp("biohazardBin", -4 * mirror, 3, "center"))
			specs.append(_sp("hazardSign", -1 * mirror, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, mid - 1, "open", _LOOSE))
		"bio_lab":
			specs.append(_sp("specimenTank", -4 * mirror, 0, "open", _WALL))
			specs.append(_sp("specimenTank", -2 * mirror, 0, "open", _WALL))
			specs.append(_sp("labBench", 2 * mirror, 0, "open", _WALL))
			specs.append(_sp("labMicroscope", 2 * mirror, 0, "open", {"solid": false, "mount_y": .92}))
			specs.append(_sp("labBench", 0, 3, "open"))
			specs.append(_sp("labStool", 0, 4, "back"))
			specs.append(_sp("coldStorageUnit", 3 * mirror, 3, "center"))
			specs.append(_sp("biohazardBin", -4 * mirror, 3, "center"))
			specs.append(_sp("hazardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, mid - 1, "open", _LOOSE))
		"cold_storage":
			for unit_side in [-3, 0, 3]:
				specs.append(_sp("coldStorageUnit", unit_side, 0, "open", _WALL))
			specs.append(_sp("gasCylinderRack", -4 * mirror, 3, "center"))
			specs.append(_sp("supplyCrates", 3 * mirror, 3, "center"))
			specs.append(_sp("hazardSign", 2 * mirror, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"lab_office":
			for desk_side in [-2, 2]:
				specs.append(_sp("officeDesk", desk_side, 1, "open"))
				specs.append(_sp("retroComputerDesktop" if desk_side < 0 else "retroComputerTerminal", desk_side, 1,
					"open", {"solid": false, "mount_y": .78}))
				specs.append(_sp("officeChair", desk_side, 0, "open"))
			specs.append(_sp("labWhiteboard", 0, 0, "open", _MOUNT))
			specs.append(_sp("filingCabinet", -4, 0, "open", _WALL))
			specs.append(_sp("filingCabinet", 4, 0, "open", _WALL))
			specs.append(_sp("officeWaterCooler", 4 * mirror, front - 1, "center"))
			specs.append(_sp("bananaPlant", -4 * mirror, front - 1, "center"))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		# ---- greenhouse ----
		"glasshouse":
			for bed_side in [-3, 0, 3]:
				specs.append(_sp("raisedPlanter", bed_side, 0, "open", _WALL))
			specs.append(_sp("raisedPlanter", -2, 3, "open"))
			specs.append(_sp("raisedPlanter", 2, 3, "open"))
			specs.append(_sp("mistingPost", 0, 3, "open"))
			specs.append(_sp("greenhouseBench", -4 * mirror, front - 1, "center"))
			specs.append(_sp("overgrowthPatch", 3 * mirror, front - 1, "open", _LOOSE))
			specs.append(_sp("hangingVines", -2, mid, "open", _LOOSE))
			specs.append(_sp("hangingVines", 2, mid, "open", _LOOSE))
		"palm_house":
			specs.append(_sp("pottedPalm", -3, 1, "open"))
			specs.append(_sp("pottedPalm", 3, 1, "open"))
			specs.append(_sp("bananaPlant", 0, 0, "open", _WALL))
			specs.append(_sp("overgrowthPatch", 0, 2, "open", _LOOSE))
			specs.append(_sp("mistingPost", -1, 3, "open"))
			specs.append(_sp("mistingPost", 1, 3, "open"))
			specs.append(_sp("greenhouseBench", -3, 4, "center"))
			specs.append(_sp("greenhouseBench", 3, 4, "center"))
			specs.append(_sp("hangingVines", 0, mid, "open", _LOOSE))
		"cactus_room":
			specs.append(_sp("saguaroCactus", -3 * mirror, 0, "open"))
			specs.append(_sp("saguaroCactus", 1 * mirror, 1, "open"))
			specs.append(_sp("saguaroCactus", 4 * mirror, 0, "open"))
			specs.append(_sp("cactusCluster", -1 * mirror, 0, "open"))
			specs.append(_sp("cactusCluster", 3 * mirror, 2, "open"))
			specs.append(_sp("cactusCluster", -4 * mirror, 3, "open"))
			specs.append(_sp("greenhouseBench", 2 * mirror, 4, "back"))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"potting_shed":
			specs.append(_sp("pottingBench", -2, 0, "open", _WALL))
			specs.append(_sp("pottingBench", 2, 0, "open", _WALL))
			specs.append(_sp("seedlingRack", -3 * mirror, 3, "center"))
			specs.append(_sp("compostBins", 3 * mirror, 3, "center"))
			specs.append(_sp("wateringCart", -4 * mirror, front - 1, "center"))
			specs.append(_sp("supplyCrates", 4 * mirror, front - 1, "center"))
			specs.append(_sp("hangingVines", 0, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 0, 1, "open", _LOOSE))
		"irrigation_room":
			specs.append(_sp("irrigationManifold", -2 * mirror, 0, "open", _WALL))
			specs.append(_sp("irrigationManifold", 2 * mirror, 0, "open", _WALL))
			specs.append(_sp("mistingPost", 0, 1, "open"))
			specs.append(_sp("seedlingRack", -3 * mirror, 3, "center"))
			specs.append(_sp("wateringCart", 3 * mirror, 3, "center"))
			specs.append(_sp("overgrowthPatch", 0, 3, "open", _LOOSE))
			specs.append(_sp("hazardSign", 0, 0, "open", _MOUNT))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"overgrown_room":
			specs.append(_sp("pottedPalm", -3 * mirror, 1, "open"))
			specs.append(_sp("bananaPlant", 3 * mirror, 0, "open", _WALL))
			specs.append(_sp("raisedPlanter", 1 * mirror, 0, "open", _WALL))
			specs.append(_sp("compostBins", 3 * mirror, 3, "center"))
			for patch in [Vector2i(-2, 3), Vector2i(1, 2), Vector2i(3, front - 1), Vector2i(-3, front - 1)]:
				specs.append(_sp("overgrowthPatch", patch.x * mirror, patch.y, "open", _LOOSE))
			specs.append(_sp("hangingVines", -1, mid, "open", _LOOSE))
			specs.append(_sp("hangingVines", 2, 1, "open", _LOOSE))
		"dome_atrium":
			# the great glass dome: a fountain under the crown, benches facing it, palms and planters round the edge
			var centre := mid
			specs.append(_sp("domeFountain", 0, centre, "open"))
			for bench in [Vector2i(-3, 0), Vector2i(3, 0)]:
				specs.append(_sp("greenhouseBench", bench.x, centre, "center"))
			specs.append(_sp("greenhouseBench", 0, centre - 3, "open"))
			for palm in [Vector2i(-6, 3), Vector2i(6, 3), Vector2i(-6, front - 4), Vector2i(6, front - 4)]:
				specs.append(_sp("pottedPalm", palm.x, palm.y, "open"))
			for bed_side in [-6, -2, 2, 6]:
				specs.append(_sp("raisedPlanter", bed_side, 0, "open", _WALL))
			for side_index in 2:
				var edge := -half if side_index == 0 else half
				for plant_depth in range(3, front - 2, 4):
					specs.append(_sp("bananaPlant" if plant_depth % 8 == 3 else "cactusCluster", edge, plant_depth, "center"))
			for post in [Vector2i(-3, centre - 3), Vector2i(3, centre + 3), Vector2i(-3, centre + 3), Vector2i(3, centre - 3)]:
				specs.append(_sp("mistingPost", post.x, post.y, "open"))
			for vine in [Vector2i(-5, centre), Vector2i(5, centre), Vector2i(0, 3), Vector2i(0, front - 3)]:
				specs.append(_sp("hangingVines", vine.x, vine.y, "open", _LOOSE))
			for patch in [Vector2i(-7, centre + 1), Vector2i(7, centre - 1), Vector2i(-2, front - 2), Vector2i(4, 2)]:
				specs.append(_sp("overgrowthPatch", patch.x, patch.y, "open", _LOOSE))
		# ---- shopping arcade (20x9 shopfronts: sides -8..8 plus the far column, depths 0..front) ----
		"donut_shop":
			# two rooms: the back kitchen behind a counter line with two pass-throughs, the shop floor in front
			specs.append(_sp("donutFryer", -6, 0, "open", _WALL))
			specs.append(_sp("bakeryRack", -3, 0, "open", _WALL))
			specs.append(_sp("normalKitchenFridge", 3, 0, "open", _WALL))
			specs.append(_sp("shopShelf", 6, 0, "open", _WALL))
			specs.append(_sp("donutSign", 0, 0, "open", {"wall_mount": true, "solid": false, "mount_y": 1.7}))
			specs.append(_sp("menuBoard", -3, 0, "open", {"wall_mount": true, "solid": false, "mount_y": 2.05}))
			specs.append(_sp("displayCase", -5, 2, "open"))
			specs.append(_sp("displayCase", -2, 2, "open"))
			specs.append(_sp("checkoutCounter", 3, 2, "open"))
			specs.append(_sp("coffeeStation", 6, 2, "open"))
			specs.append(_sp("dinerStool", -5, 3, "back"))
			specs.append(_sp("dinerStool", -3, 3, "back"))
			specs.append(_sp("dinerBooth", -7, 5, "open"))
			specs.append(_sp("dinerBooth", 7, 5, "open"))
			for light_side in [-5, 0, 5]:
				specs.append(_sp("ceilingLight", light_side, mid, "open", _LOOSE))
		"cinema":
			# the screening room at the back, a curtain line, then the lobby with the box office and concessions
			specs.append(_sp("cinemaScreen", 0, 0, "open", {"wall_mount": true, "solid": false, "mount_y": .9}))
			for row_depth in [1, 2]:
				for seat_side in [-5, 0, 5]:
					specs.append(_sp("cinemaSeats", seat_side, row_depth, "back"))
			for curtain_side in [-7, -4, 4, 7]:
				specs.append(_sp("privacyCurtain", curtain_side, 3, "open"))
			specs.append(_sp("ticketBooth", -6, 5, "center"))
			specs.append(_sp("concessionCounter", 6, 5, "center"))
			specs.append(_sp("ceilingLight", -3, front - 1, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 3, front - 1, "open", _LOOSE))
		"bakery":
			specs.append(_sp("bakeryRack", -7, 0, "open", _WALL))
			specs.append(_sp("bakeryRack", -5, 0, "open", _WALL))
			specs.append(_sp("normalKitchenStove", -2, 0, "open", _WALL))
			specs.append(_sp("shopShelf", 4, 0, "open", _WALL))
			specs.append(_sp("shopShelf", 7, 0, "open", _WALL))
			specs.append(_sp("menuBoard", 0, 0, "open", {"wall_mount": true, "solid": false, "mount_y": 1.9}))
			specs.append(_sp("displayCase", -5, 2, "open"))
			specs.append(_sp("displayCase", -2, 2, "open"))
			specs.append(_sp("checkoutCounter", 4, 2, "open"))
			specs.append(_sp("mallBench", -6, front - 1, "open"))
			specs.append(_sp("ceilingLight", -3, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 3, mid, "open", _LOOSE))
		"laundromat":
			for machine_side in range(-8, 9):
				if absi(machine_side) <= 1:
					continue
				specs.append(_sp("dryerStack" if machine_side % 3 == 0 else "washingMachine", machine_side, 0, "open", _WALL))
			for machine_side in range(-5, 6):
				if absi(machine_side) <= 1:
					continue
				specs.append(_sp("washingMachine", machine_side, 3, "open"))
			specs.append(_sp("mallBench", -6, front - 1, "open"))
			specs.append(_sp("vendingMachine", 8, front - 1, "center"))
			specs.append(_sp("dinerStool", 6, front - 1, "open"))
			for light_side in [-5, 0, 5]:
				specs.append(_sp("ceilingLight", light_side, 2, "open", _LOOSE))
		"drugstore":
			for shelf_side in [-6, -3, 0, 3, 6]:
				specs.append(_sp("pharmacyShelf", shelf_side, 0, "open", _WALL))
			for aisle_side in [-6, -3, 3]:
				specs.append(_sp("shopShelf", aisle_side, 3, "open"))
			specs.append(_sp("checkoutCounter", 6, front - 1, "center"))
			specs.append(_sp("shopFridge", 8, 2, "center"))
			specs.append(_sp("ceilingLight", -3, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 3, mid, "open", _LOOSE))
		"corner_store":
			for fridge_side in [-7, -6, -5, -4]:
				specs.append(_sp("shopFridge", fridge_side, 0, "open", _WALL))
			for shelf_side in [1, 4, 7]:
				specs.append(_sp("shopShelf", shelf_side, 0, "open", _WALL))
			for aisle_side in [-5, -2, 2, 5]:
				specs.append(_sp("shopShelf", aisle_side, 3, "open"))
			specs.append(_sp("checkoutCounter", 6, front - 1, "center"))
			specs.append(_sp("vendingMachine", -8, front - 1, "center"))
			specs.append(_sp("ceilingLight", -3, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 3, mid, "open", _LOOSE))
		"electronics":
			for tv_side in [-6, -3, 3, 6]:
				specs.append(_sp("tvWall", tv_side, 0, "open", _WALL))
			specs.append(_sp("arcadeCabinet", -1, 0, "open", _WALL))
			specs.append(_sp("arcadeCabinetCyanMagenta", 1, 0, "open", _WALL))
			specs.append(_sp("displayCase", -5, 3, "open"))
			specs.append(_sp("displayCase", 5, 3, "open"))
			specs.append(_sp("checkoutCounter", 6, front - 1, "center"))
			specs.append(_sp("ceilingLight", -3, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 3, mid, "open", _LOOSE))
		"night_diner":
			for booth_side in [-6, -3, 3, 6]:
				specs.append(_sp("dinerBooth", booth_side, 0, "open", _WALL))
			specs.append(_sp("coffeeStation", 0, 0, "open", _WALL))
			specs.append(_sp("menuBoard", 0, 0, "open", {"wall_mount": true, "solid": false, "mount_y": 1.9}))
			# hunter-scale bodies need 1.4 m between a counter's back and the booths behind it
			specs.append(_sp("checkoutCounter", -4, 4, "open"))
			specs.append(_sp("checkoutCounter", 4, 4, "open"))
			for stool_side in [-5, -3, 3, 5]:
				specs.append(_sp("dinerStool", stool_side, 5, "back"))
			specs.append(_sp("ceilingLight", -3, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 3, mid, "open", _LOOSE))
		"florist":
			for stand_side in [-6, -3, 3, 6]:
				specs.append(_sp("flowerStand", stand_side, 0, "open", _WALL))
			specs.append(_sp("bananaPlant", 0, 0, "open", _WALL))
			specs.append(_sp("flowerStand", -4, 3, "open"))
			specs.append(_sp("flowerStand", 4, 3, "open"))
			specs.append(_sp("checkoutCounter", 6, front - 1, "center"))
			specs.append(_sp("mallPlanter", -7, front - 1, "open"))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"barber":
			for station_side in [-6, -3, 3, 6]:
				specs.append(_sp("barberStation", station_side, 0, "open", _WALL))
				specs.append(_sp("barberChair", station_side, 2, "back"))
			specs.append(_sp("mallBench", -5, front - 1, "open"))
			specs.append(_sp("checkoutCounter", 6, front - 1, "center"))
			specs.append(_sp("ceilingLight", -3, mid, "open", _LOOSE))
			specs.append(_sp("ceilingLight", 3, mid, "open", _LOOSE))
		"pawn_shop":
			for shelf_side in [-6, -3, 3, 6]:
				specs.append(_sp("shopShelf", shelf_side, 0, "open", _WALL))
			specs.append(_sp("tvWall", 0, 0, "open", _WALL))
			specs.append(_sp("displayCase", -4, 3, "open"))
			specs.append(_sp("displayCase", 4, 3, "open"))
			specs.append(_sp("checkoutCounter", -7, front - 1, "center"))
			specs.append(_sp("clothesRack", 7, front - 1, "center"))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"stationery":
			for shelf_side in [-6, -3, 3, 6]:
				specs.append(_sp("shopShelf", shelf_side, 0, "open", _WALL))
			specs.append(_sp("normalBookcase", 0, 0, "open", _WALL))
			specs.append(_sp("shopShelf", -5, 3, "open"))
			specs.append(_sp("shopShelf", 5, 3, "open"))
			specs.append(_sp("magazineRack", -1, 3, "open"))
			specs.append(_sp("checkoutCounter", 6, front - 1, "center"))
			specs.append(_sp("mallBench", -6, front - 1, "open"))
			specs.append(_sp("ceilingLight", 0, mid, "open", _LOOSE))
		"food_court":
			# the atrium: food counters along the back, tables on the floor, planters by the door
			specs.append(_sp("displayCase", -6, 0, "open", _WALL))
			specs.append(_sp("coffeeStation", -3, 0, "open", _WALL))
			specs.append(_sp("concessionCounter", 3, 0, "open", _WALL))
			specs.append(_sp("donutFryer", 6, 0, "open", _WALL))
			specs.append(_sp("menuBoard", -3, 0, "open", {"wall_mount": true, "solid": false, "mount_y": 1.9}))
			specs.append(_sp("menuBoard", 3, 0, "open", {"wall_mount": true, "solid": false, "mount_y": 1.9}))
			for table in [Vector2i(-6, 3), Vector2i(-2, 3), Vector2i(2, 3), Vector2i(6, 3)]:
				specs.append(_sp("foodCourtTable", table.x, table.y, "open"))
			specs.append(_sp("mallPlanter", -7, front - 1, "open"))
			specs.append(_sp("mallPlanter", 7, front - 1, "open"))
			for light_side in [-6, -2, 2, 6]:
				specs.append(_sp("ceilingLight", light_side, mid, "open", _LOOSE))
	if half >= 9 and REGION_REPEAT_TEMPLATES.has(template):
		var repeated := []
		for shift in [-5, 5]:
			for original in specs:
				var copy: Dictionary = (original as Dictionary).duplicate()
				copy["side"] = int(copy.get("side", 0)) + shift
				repeated.append(copy)
		specs = repeated
	return specs


static func _frame_type_for_region(region: String, wide: bool) -> String:
	match region:
		"hotel", "mansion":
			return "luxuryPaintingFrameEmpty" if wide else "luxuryPictureFrameEmpty"
		"gothic":
			return "gothicPaintingFrameEmpty" if wide else "gothicPictureFrameEmpty"
		_:
			return "normalPaintingFrameEmpty" if wide else "normalPictureFrameEmpty"


static func _rug_type_for_region(region: String) -> String:
	match region:
		"mansion":
			return "mansionAreaRug"
		"hotel":
			return "hotelCarpet"
		"apartment":
			return "apartmentCarpet"
		"gothic":
			return "gothicBedroomRug"
		_:
			return "bedroomRug"


static func _room_template_basis(room: Dictionary) -> Dictionary:
	var rect: Rect2i = room.get("rect", Rect2i())
	var center: Vector2i = room.get("center", rect.position + rect.size / 2)
	var doorway_value = room.get("doorway")
	if not doorway_value is Vector2i:
		return {}
	var doorway: Vector2i = doorway_value
	var delta := doorway - center
	var open_direction := Vector2i.ZERO
	if absi(delta.x) >= absi(delta.y):
		open_direction = Vector2i(1 if delta.x >= 0 else -1, 0)
	else:
		open_direction = Vector2i(0, 1 if delta.y >= 0 else -1)
	var side_direction := Vector2i(-open_direction.y, open_direction.x)
	var back_cell := center
	if open_direction.x > 0:
		back_cell.x = rect.position.x + 1
	elif open_direction.x < 0:
		back_cell.x = rect.end.x - 2
	elif open_direction.y > 0:
		back_cell.y = rect.position.y + 1
	else:
		back_cell.y = rect.end.y - 2
	return {"open": open_direction, "side": side_direction,
		"back_cell": back_cell,
		"side_span": rect.size.y if open_direction.x != 0 else rect.size.x,
		"depth_span": rect.size.x if open_direction.x != 0 else rect.size.y}


func _template_prop_entry(coord: Vector3i, room: Dictionary,
		basis: Dictionary, template: String, spec_index: int, spec: Dictionary,
		grid: Array, reserved: Dictionary) -> Dictionary:
	var prop_type := String(spec.get("type", ""))
	var pack_size = ContentRegistry.get_def("props", prop_type).get("size")
	if not PropModelCatalog.has_model(prop_type) \
			or not (TEMPLATE_PROP_SIZES.has(prop_type) or PropColliderSizes.SIZES.has(prop_type) or pack_size is Vector3):
		return {}
	var open_direction: Vector2i = basis["open"]
	var side_direction: Vector2i = basis["side"]
	var cell: Vector2i = basis["back_cell"] \
		+ side_direction * int(spec.get("side", 0)) \
		+ open_direction * int(spec.get("depth", 0))
	var rect: Rect2i = room.get("rect", Rect2i())
	if not rect.has_point(cell) or not _grid_cell_open(grid, cell):
		return {}
	var facing := String(spec.get("facing", "open"))
	var facing_direction := open_direction
	match facing:
		"back": facing_direction = -open_direction
		"left": facing_direction = -side_direction
		"right": facing_direction = side_direction
		"center": facing_direction = _cardinal_toward(cell,
			room.get("center", cell), open_direction)
	var blocker_size: Vector3 = TEMPLATE_PROP_SIZES.get(prop_type, PropColliderSizes.SIZES.get(prop_type,
		pack_size if pack_size is Vector3 else Vector3.ONE))
	var placement_offset := Vector2.ZERO
	var wall_mounted := bool(spec.get("wall_mount", false))
	if bool(spec.get("wall_backed", false)) and not wall_mounted:
		# flush: the back (the fitted collider's depth, what you see) 2 cm off the wall behind the cell; a shallow prop
		# moves toward the wall, a deep one out into the room (KT: backs to the wall, prop_orientation checks 15 cm)
		placement_offset = Vector2(open_direction) * (back_extent(prop_type, _collider_size(prop_type, blocker_size)) - .48)
	var backing_wall := -open_direction if (bool(spec.get("wall_backed", false)) \
		or wall_mounted) else Vector2i.ZERO
	if wall_mounted:
		var wall_cell := cell + backing_wall
		var front_cell := cell + open_direction
		if not rect.has_point(wall_cell) or not rect.has_point(front_cell) \
				or _grid_cell_open(grid, wall_cell) \
				or not _grid_cell_open(grid, front_cell):
			return {}
	var solid := bool(spec.get("solid", not wall_mounted))
	var occupied := [] if not solid else _prop_occupied_cells(cell, facing_direction,
		Vector3(blocker_size.x, blocker_size.y, minf(blocker_size.z, _collider_size(prop_type, blocker_size).z)) \
			if bool(spec.get("wall_backed", false)) else blocker_size,
		placement_offset if placement_offset.dot(Vector2(open_direction)) >= 0.0 else Vector2.ZERO)   # flush toward the wall stays in its cell
	for occupied_value in occupied:
		var at: Vector2i = occupied_value
		# Authored room recipes are placed inside a sealed room. Circulation
		# neighbourhoods around halls/doors are for random scatter so couches
		# do not pinch the shared route; applying that mask here dropped desks,
		# nightstands, and cafeteria furniture while leaving non-solid lamps
		# and computers in the same cells.
		# a seat may share a cell with its table (never a door or threshold cell): the collider check and
		# _nudge_seat_clear decide whether it fits
		var shareable := reserved.get(at) is String and String(reserved.get(at)) == SEAT_SHAREABLE \
			and PropModelCatalog.interaction_for(prop_type) == "sit"
		if not rect.has_point(at) or (reserved.has(at) and not shareable) \
				or not _grid_cell_open(grid, at):
			return {}
	var room_token := String(room.get("id", "ROOM")).replace(":", "-")
	return {
		"id": "%s:TEMPLATE:%s:%s:%d" % [chunk_id(coord), room_token,
			template, spec_index],
		"type": prop_type, "cell": cell,
		"yaw": _room_facing_yaw(cell, cell + facing_direction),
		"facing_target": cell + facing_direction,
		"placement_offset": placement_offset,
		"mount_offset": Vector2(backing_wall) * .44 \
			if wall_mounted else Vector2.ZERO,
		"backing_wall": backing_wall,
		"open_direction": facing_direction,
		"blocker_size": blocker_size, "solid": solid,
		"collider_size": _collider_size(prop_type, blocker_size),
		"occupied_cells": occupied, "corridor_clear": true,
		"wall_mounted": wall_mounted,
		"mount_y": float(spec.get("mount_y", 0.0)),
		"room_id": String(room.get("id", "")), "room_template": template,
	}


static func _cardinal_toward(from: Vector2i, to: Vector2i,
		fallback: Vector2i) -> Vector2i:
	var delta := to - from
	if delta == Vector2i.ZERO:
		return fallback
	if absi(delta.x) >= absi(delta.y):
		return Vector2i(1 if delta.x > 0 else -1, 0)
	return Vector2i(0, 1 if delta.y > 0 else -1)


static func _solid_prop_placement(rect: Rect2i, grid: Array,
		excluded: Dictionary, reserved: Dictionary, blocker_size: Vector3,
		rng: SeededRandom) -> Dictionary:
	var candidates := []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, z)
			if excluded.has(cell) or reserved.has(cell) \
					or not _grid_cell_open(grid, cell) or _wall_count(grid, cell) != 1:
				continue
			var backing_wall := _backing_wall_direction(grid, cell)
			var open_direction := -backing_wall
			if not _grid_cell_open(grid, cell + open_direction):
				continue
			# Authored prop depth is local Z. Keep its rear face five centimetres
			# clear of the wall and move any excess depth into the room.
			var depth_shift := maxf(0.0, blocker_size.z * .5 - .45)
			var placement_offset := Vector2(open_direction) * depth_shift
			var occupied := _prop_occupied_cells(cell, open_direction,
				blocker_size, placement_offset)
			var valid := not occupied.is_empty()
			for occupied_value in occupied:
				var at: Vector2i = occupied_value
				if not rect.has_point(at) or excluded.has(at) or reserved.has(at) \
						or not _grid_cell_open(grid, at):
					valid = false
					break
			if valid:
				candidates.append({"cell": cell,
					"open_direction": open_direction,
					"placement_offset": placement_offset,
					"occupied_cells": occupied})
	if candidates.is_empty():
		return {}
	return candidates[rng.next_index(candidates.size())]


## The collision box of a solid prop: derived from its model (PropColliderSizes) when it has one, else the authored size.
static func _collider_size(prop_type: String, authored: Vector3) -> Vector3:
	return PropColliderSizes.SIZES.get(prop_type, authored)


static func _prop_occupied_cells(cell: Vector2i, open_direction: Vector2i,
		blocker_size: Vector3, placement_offset: Vector2) -> Array:
	var center := Vector2(cell) + Vector2(.5, .5) + placement_offset
	var extent := Vector2(blocker_size.x, blocker_size.z) * .5
	if open_direction.x != 0:
		extent = Vector2(blocker_size.z, blocker_size.x) * .5
	var min_cell := Vector2i(floori(center.x - extent.x + .001),
		floori(center.y - extent.y + .001))
	var max_cell := Vector2i(floori(center.x + extent.x - .001),
		floori(center.y + extent.y - .001))
	var result := []
	for z in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			result.append(Vector2i(x, z))
	return result


static func _wall_mount_for_room(rect: Rect2i, grid: Array,
		reserved: Dictionary, excluded: Dictionary, rng: SeededRandom) -> Dictionary:
	var candidates := []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, z)
			if reserved.has(cell) or excluded.has(cell) \
					or not _grid_cell_open(grid, cell) or _wall_count(grid, cell) != 1:
				continue
			var backing_wall := _backing_wall_direction(grid, cell)
			var open_direction := -backing_wall
			if not _grid_cell_open(grid, cell + open_direction):
				continue
			candidates.append({"cell": cell, "backing_wall": backing_wall})
	if candidates.is_empty():
		return {}
	return candidates[rng.next_index(candidates.size())]


func _room_door_props(coord: Vector3i, region: String, rooms: Array,
		grid: Array, stairs: Array = []) -> Array:
	var door_type := String(REGION_ROOM_DOORS.get(region, ""))
	if door_type.is_empty():
		return []
	var result := []
	var stair_exclusion := _stair_door_exclusion(stairs)
	# Rooms that share a wall see the same opening: only the first room claims it.
	var claimed_doorways := {}
	for room_index in rooms.size():
		# One preset suite owns an exterior door plus four internal doors. Keep
		# enough budget for the other corridor rooms in the same chunk as well.
		if result.size() >= 20:   # dense districts have 16 rooms per chunk
			break
		var room: Dictionary = rooms[room_index]
		if String(room.get("room_type", "")) in ["lobby", "stairwell"]:
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		var suite_child := room.has("suite_id") \
			and not bool(room.get("suite_parent", false))
		# Doors are sized for the hunters (docs/DOORWAY_CLEARANCE.md): every room with a side of 4+ cells and a suite's
		# own entrance get a two-cell double door; only small rooms and the rooms inside a suite keep a single door.
		var major := _is_major_room(room, rect)
		var use_double := bool(room.get("suite_parent", false)) \
			or (not suite_child and (rect.size.x >= 4 or rect.size.y >= 4))
		# Roomy major rooms open onto the hall through a three-cell archway instead of
		# a door; a few keep a door for variety (see RefDecor for the arch itself).
		var arch := major and not room.has("suite_id") and rect.size.x >= 7 and rect.size.y >= 7 \
			and absi(String(room.get("id", "")).hash()) % 100 < 65
		var door_span := 3 if arch else (2 if use_double else 1)
		var room_center: Vector2i = room.get("center", rect.position + rect.size / 2)
		var threshold := _find_room_door_threshold(rect, room_center, grid,
			stair_exclusion, door_span)
		if threshold.is_empty():
			continue
		# A hallway is three wide; a room at the END of one gets a single door, whatever its size.
		if door_span > 1 and _door_faces_hall_end(grid, threshold):
			arch = false
			use_double = false
			door_span = 1
			threshold = _find_room_door_threshold(rect, room_center, grid,
				stair_exclusion, 1)
			if threshold.is_empty():
				continue
		var resolved_door_type: String = "roomArch" if arch else (String(
			REGION_DOUBLE_ROOM_DOORS.get(region, door_type)) if use_double else door_type)
		var cell: Vector2i = threshold["cell"]
		var doorway_cells: Array = threshold["doorway_cells"]
		if doorway_cells.any(func(c) -> bool: return claimed_doorways.has(c)):
			continue
		for claimed_cell in doorway_cells:
			claimed_doorways[claimed_cell] = true
		var wall_cells: Array = threshold["wall_cells"]
		for shoulder_value in wall_cells:
			var shoulder: Vector2i = shoulder_value
			grid[shoulder.y][shoulder.x] = 1
		for doorway_value in doorway_cells:
			var doorway_cell: Vector2i = doorway_value
			grid[doorway_cell.y][doorway_cell.x] = 0
		var across: Vector2i = threshold["across"]
		var placement_offset := Vector2(float(across.x), float(across.y)) \
			* (float(door_span - 1) * .5)
		result.append({
			# Tie persistence to the room index rather than the number of earlier
			# successful candidates. Omitting an invalid door no longer renumbers
			# every later authoritative door in the chunk.
			"id": "%s:DOOR:%d" % [chunk_id(coord), room_index],
			"type": resolved_door_type, "cell": cell,
			# Face perpendicular to the wall. A wide doorway centered between two
			# cells must not inherit a diagonal yaw from an off-center room midpoint.
			"yaw": _room_facing_yaw(cell, cell + threshold["inward"]),
			"facing_target": cell + threshold["inward"],
			"blocker_size": Vector3(3.15 if arch else (2.15 if use_double else 1.15), 2.6, .2),
			"solid": false, "door_span": door_span, "arch": arch,
			"placement_offset": placement_offset,
			"occupied_cells": doorway_cells.duplicate(),
			"room_id": String(room.get("id", "")), "room_door": true,
			"inward": threshold["inward"],
			"outward": threshold["outward"],
			"across": across,
			"doorway_cells": doorway_cells,
			"threshold_wall_cells": wall_cells,
		})
	return result


## Major rooms keep wide openings: the big named halls, greenhouses and anything very large.
static func _is_major_room(room: Dictionary, rect: Rect2i) -> bool:
	var room_type := String(room.get("room_type", ""))
	return RefLook.HALL_ROOMS.has(room_type) or RefLook.GREENHOUSE_ROOMS.has(room_type) \
		or RefLook.GLASSHOUSE_ROOMS.has(room_type) \
		or (rect.size.x >= 13 and rect.size.y >= 13)


## True when the door's outside cell is the END of a hallway: the hall arrives straight at the door
## (open run perpendicular to the wall) and does not run along it.
static func _door_faces_hall_end(grid: Array, threshold: Dictionary) -> bool:
	var cell: Vector2i = threshold["cell"]
	var outward: Vector2i = threshold["outward"]
	var across: Vector2i = threshold["across"]
	var first := cell + outward
	var run_across := 1
	for sign_value in [-1, 1]:
		var k := 1
		while k < 8 and _grid_open(grid, first + across * sign_value * k):
			run_across += 1
			k += 1
	var run_out := 0
	var j := 0
	while j < 8 and _grid_open(grid, first + outward * j):
		run_out += 1
		j += 1
	return run_across <= 3 and run_out >= 3


static func _grid_open(grid: Array, cell: Vector2i) -> bool:
	return cell.y >= 0 and cell.y < grid.size() and cell.x >= 0 \
		and cell.x < (grid[cell.y] as Array).size() and int(grid[cell.y][cell.x]) == 0


static func _stair_door_exclusion(stairs: Array) -> Dictionary:
	var excluded := {}
	for stair_value in stairs:
		var stair: Dictionary = stair_value
		var path := stair_path_cells(stair.get("cell", Vector2i.ZERO))
		for path_cell in path:
			# The generated approach is five cells wide. One additional cell of
			# clearance keeps the authored frame and its wall shoulders away from
			# both the visible flight and the open slab edge.
			_exclude_neighbourhood(excluded, path_cell, 3)
	return excluded


static func _find_room_door_threshold(rect: Rect2i, room_center: Vector2i,
		grid: Array, excluded: Dictionary, requested_span: int = 1) -> Dictionary:
	var candidates := []
	var span := clampi(requested_span, 1, 3)
	# A threshold cell belongs to the room boundary. Inward remains in the room;
	# outward must leave it and continue through at least two open corridor cells.
	var sides := [
		{"outward": Vector2i.UP, "across": Vector2i.RIGHT},
		{"outward": Vector2i.DOWN, "across": Vector2i.RIGHT},
		{"outward": Vector2i.LEFT, "across": Vector2i.DOWN},
		{"outward": Vector2i.RIGHT, "across": Vector2i.DOWN},
	]
	for side_value in sides:
		var side: Dictionary = side_value
		var outward: Vector2i = side["outward"]
		var inward := -outward
		var across: Vector2i = side["across"]
		var start := rect.position + Vector2i.ONE
		var finish := rect.end - Vector2i.ONE
		var cells := []
		if outward == Vector2i.UP:
			for x in range(start.x, finish.x):
				cells.append(Vector2i(x, rect.position.y))
		elif outward == Vector2i.DOWN:
			for x in range(start.x, finish.x):
				cells.append(Vector2i(x, rect.end.y - 1))
		elif outward == Vector2i.LEFT:
			for z in range(start.y, finish.y):
				cells.append(Vector2i(rect.position.x, z))
		else:
			for z in range(start.y, finish.y):
				cells.append(Vector2i(rect.end.x - 1, z))
		for cell_value in cells:
			var cell: Vector2i = cell_value
			var doorway_cells := []
			for doorway_index in range(span):
				doorway_cells.append(cell + across * doorway_index)
			# At least one cell must be the route's existing canonical opening.
			# The second double-door cell is allowed to still be wall here; it is
			# cleared only after both lanes have proven traversable on each side.
			var has_existing_open := doorway_cells.any(func(at):
				return _grid_cell_open(grid, at))
			if not has_existing_open:
				continue
			var footprint := []
			var lanes_clear := true
			for doorway_value in doorway_cells:
				var doorway_cell: Vector2i = doorway_value
				var inward_cell := doorway_cell + inward
				var outside_cell := doorway_cell + outward
				var corridor_cell := doorway_cell + outward * 2
				if not rect.has_point(doorway_cell) \
						or not rect.has_point(inward_cell) \
						or rect.has_point(outside_cell) \
						or not _grid_cell_open(grid, inward_cell) \
						or not _grid_cell_open(grid, outside_cell) \
						or not _grid_cell_open(grid, corridor_cell):
					lanes_clear = false
					break
				footprint.append_array([doorway_cell, inward_cell, outside_cell,
					corridor_cell])
			if not lanes_clear:
				continue
			var wall_cells := []
			for offset in range(1, 3):
				for shoulder in [cell - across * offset,
						cell + across * (span - 1 + offset)]:
					if rect.has_point(shoulder):
						wall_cells.append(shoulder)
						footprint.append(shoulder)
			# A real doorway needs a wall shoulder immediately outside both ends.
			if not wall_cells.has(cell - across) \
					or not wall_cells.has(cell + across * span):
				continue
			var blocked_by_stair := footprint.any(func(at): return excluded.has(at))
			if blocked_by_stair:
				continue
			candidates.append({
				"cell": cell, "inward": inward, "outward": outward,
				"across": across, "doorway_cells": doorway_cells,
				"wall_cells": wall_cells,
				"score": (Vector2(cell) + Vector2(across) \
					* (float(span - 1) * .5)).distance_squared_to(Vector2(room_center)),
			})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["score"]) != float(b["score"]):
			return float(a["score"]) < float(b["score"])
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		return a_cell.y < b_cell.y or (a_cell.y == b_cell.y and a_cell.x < b_cell.x))
	return candidates[0]


static func _grid_cell_open(grid: Array, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < CHUNK_SIZE \
		and cell.y < CHUNK_SIZE and int(grid[cell.y][cell.x]) == 0


static func _room_facing_yaw(cell: Vector2i, target: Vector2i) -> float:
	var direction := Vector2(target - cell)
	if direction.length_squared() < .01:
		return 0.0
	# Godot's visual forward is -Z; atan2(-x, -z) turns that axis toward target.
	return snappedf(atan2(-direction.x, -direction.y), PI * .25)


## Furniture you can hide in (docs/HIDING_PROPS.md): every bed and wardrobe a room recipe placed becomes an ordinary
## hiding_spot fixture, so the same toggle, hunter gimmicks (Loxelle's break, Javelle's reach), navigation and replication
## apply. "style" tells the view how to hide (under the bed, inside the wardrobe); the prop itself is the visual.
const HIDING_PROP_STYLES := {
	"singleBed": "bed", "doubleBed": "bed", "gothicDoubleBed": "bed",   # hospitalBed (regions lane) has a low base: not hideable
	"bedroomWardrobe": "wardrobe", "gothicWardrobe": "wardrobe",
}


func _prop_hiding_fixtures(coord: Vector3i, region_props: Array, safe: bool) -> Array:
	if safe:
		return []
	var result := []
	for prop_value in region_props:
		var prop: Dictionary = prop_value
		var style := String(HIDING_PROP_STYLES.get(String(prop.get("type", "")), ""))
		if style.is_empty() or not bool(prop.get("solid", true)) or String(prop.get("room_template", "")).is_empty():
			continue
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		var offset: Vector2 = prop.get("placement_offset", Vector2.ZERO)
		var open_direction: Vector2i = prop.get("open_direction", Vector2i(0, 1))
		var size: Vector3 = prop.get("blocker_size", Vector3.ONE)
		var local := Vector2(cell) + Vector2(.5, .5) + offset
		# The fixture's cell is the open floor in front of the furniture (where you stand to use it, what reachability and
		# hunters path to); local_position is the prop itself.
		var front := local + Vector2(open_direction) * (size.z * .5 + .45)
		var approach := Vector2i(floori(front.x), floori(front.y))
		result.append({
			"id": "%s:FIXTURE:HIDE_%s:%d" % [chunk_id(coord), style.to_upper(), result.size()],
			"kind": "hiding_spot", "style": style, "prop_type": String(prop.get("type", "")),
			"capacity": PropModelCatalog.hide_capacity(String(prop.get("type", ""))),
			"prop_id": String(prop.get("id", "")), "cell": approach, "prop_cell": cell,
			"local_position": local,
			"yaw": float(prop.get("yaw", 0.0)),
			"blocker_size": prop.get("blocker_size", Vector3.ONE),
			"backing_wall": -open_direction, "open_direction": open_direction,
		})
	return result


func _fixtures(coord: Vector3i, grid: Array, rooms: Array, stairs: Array,
		region_props: Array, safe: bool) -> Array:
	# Exclude the complete flight, not only its anchor cell. A stair spans
	# several grid cells and pickups/fixtures at the upper end otherwise appear
	# to float on the treads or block the landing.
	var excluded := _stair_door_exclusion(stairs)
	for prop in region_props:
		_exclude_neighbourhood(excluded, prop.get("cell", Vector2i.ZERO), 1)
	if safe:
		_exclude_neighbourhood(excluded,
			Vector2i(CHUNK_SIZE / 2, CHUNK_SIZE / 2), 4)
	var candidates := []
	var seen := {}
	for room_value in rooms:
		var room: Dictionary = room_value
		if bool(room.get("suite_parent", false)):
			continue
		var rect: Rect2i = room.get("rect", Rect2i())
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var cell := Vector2i(x, z)
				if seen.has(cell) or excluded.has(cell) or grid[z][x] != 0 \
						or _wall_count(grid, cell) != 1:
					continue
				seen[cell] = true
				candidates.append(cell)
	var rng := SeededRandom.new("%s:FIXTURES:%s" % [world_seed, chunk_id(coord)])
	var result := []
	var target_count := 3 if safe else 6
	while result.size() < target_count and not candidates.is_empty():
		var cell: Vector2i = candidates.pop_at(rng.next_index(candidates.size()))
		var separated := true
		for existing in result:
			if cell.distance_to(existing["cell"]) < 5.0:
				separated = false
				break
		if not separated:
			continue
		var fixture_kind := "vent" if result.size() % 3 == 2 else "hiding_spot"
		var backing_wall := _backing_wall_direction(grid, cell)
		var open_direction := -backing_wall
		result.append({
			"id": "%s:FIXTURE:%s:%d" % [chunk_id(coord),
				fixture_kind.to_upper(), result.size()],
			"kind": fixture_kind,
			"cell": cell,
			# Authored interactables face local -Z. Point that front toward open
			# floor while the opposite side remains backed against the wall.
			"yaw": _room_facing_yaw(cell, cell + open_direction),
			"backing_wall": backing_wall,
			"open_direction": open_direction,
		})
	return result


func _pickups(coord: Vector3i, grid: Array, stairs: Array, safe: bool,
		region_props: Array = [], fixtures: Array = [], sealed: Dictionary = {}) -> Array:
	if safe:
		return []
	# Use the full stair-path exclusion so collectables cannot be placed on a
	# tread, at the top landing, or immediately beside the stair opening.
	var excluded := _stair_door_exclusion(stairs)
	for prop in region_props:
		_exclude_neighbourhood(excluded, prop.get("cell", Vector2i.ZERO), 1)
	for fixture in fixtures:
		_exclude_neighbourhood(excluded, fixture.get("cell", Vector2i.ZERO), 1)
	var candidates := []
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			var cell := Vector2i(x, z)
			if grid[z][x] == 0 and not excluded.has(cell) \
					and _open_spawn_neighbourhood(grid, cell):
				candidates.append(cell)
	# Sealed wings (SealPlanner): the first relay and the tools stay on open ground, the second relay usually sits behind a
	# seal, and a deep wing may hold a bonus relay (SealRules).
	var sealed_candidates := []
	if not sealed.is_empty():
		var open_candidates := []
		for candidate in candidates:
			if sealed.has(candidate):
				sealed_candidates.append(candidate)
			else:
				open_candidates.append(candidate)
		candidates = open_candidates
	var rng := SeededRandom.new("%s:PICKUPS:%s" % [world_seed, chunk_id(coord)])
	var result := []
	var plans := ["relay", "relay", "battery"]
	if not sealed_candidates.is_empty() and rng.next_float() < SealRules.BONUS_RELAY_CHANCE:
		plans.append("relay")
	if not sealed.is_empty() and SealRules.guaranteed_tool(coord):
		plans.append("tool")
	if rng.next_float() < 0.72:
		plans.append("tool")
	if rng.next_float() < 0.38:
		plans.append("battery")
	if rng.next_float() < 0.30:
		plans.append("coin")
	if rng.next_float() < 0.16:
		plans.append("backpack")
	var kind_indices := {}
	for kind_value in plans:
		if candidates.is_empty() and sealed_candidates.is_empty():
			break
		var kind := String(kind_value)
		var index := int(kind_indices.get(kind, 0))
		var from_sealed := kind == "relay" and index >= 1 and not sealed_candidates.is_empty() \
			and (index >= 2 or rng.next_float() < SealRules.SECOND_RELAY_SEALED)
		var pool: Array = sealed_candidates if from_sealed or candidates.is_empty() else candidates
		var pick_index := rng.next_index(pool.size())
		var cell: Vector2i = pool[pick_index]
		pool.remove_at(pick_index)
		kind_indices[kind] = index + 1
		var item := ""
		if kind == "tool":
			item = pick_tool(rng)
		elif kind == "backpack":
			var depth_rank := clampi(1 + floori(maxf(0.0, -float(coord.y)) / 4.0), 1, 3)
			var rolled_rank := clampi(1 + rng.next_index(depth_rank), 1, 3)
			item = BACKPACK_TYPES[rolled_rank - 1]
		result.append({
			"id": pickup_id(coord, index, kind),
			"cell": cell,
			"kind": kind,
			"item": item,
		})
	# Stim Packs and Revive Kits (docs/REVIVE.md) roll from their own seeded stream after everything above, on the cells
	# left over, so adding them moved no older pickup.
	var extra_rng := SeededRandom.new("%s:PICKUPS-AID:%s" % [world_seed, chunk_id(coord)])
	var aid := []
	if extra_rng.next_float() < GameConfig.STIM_PACK_CHANCE:
		aid.append("stim_pack")
	if extra_rng.next_float() < (GameConfig.REVIVE_KIT_CHANCE_COOP if coop else GameConfig.REVIVE_KIT_CHANCE_SOLO):
		aid.append("revive_kit")
	for item_value in aid:
		var pool: Array = candidates if not candidates.is_empty() else sealed_candidates
		if pool.is_empty():
			break
		var pick_index := extra_rng.next_index(pool.size())
		var cell: Vector2i = pool[pick_index]
		pool.remove_at(pick_index)
		var index := int(kind_indices.get("tool", 0))
		kind_indices["tool"] = index + 1
		result.append({"id": pickup_id(coord, index, "tool"), "cell": cell, "kind": "tool", "item": String(item_value)})
	return result


## Which chunks of a 4x4 region hold one of its MUSIC_BOXES_PER_REGION music boxes: picked from the region's own seed,
## so every chunk agrees without loading its neighbours. A picked chunk that turns out to be a safe room keeps none.
func music_box_chunk(coord: Vector3i) -> bool:
	var region_x := floori(float(coord.x) / REGION_SIZE_CHUNKS)
	var region_z := floori(float(coord.z) / REGION_SIZE_CHUNKS)
	var rng := SeededRandom.new("%s:MUSICBOX:%d:%d:%d" % [world_seed, region_x, coord.y, region_z])
	var slots: Array = range(REGION_SIZE_CHUNKS * REGION_SIZE_CHUNKS)
	var local := (coord.x - region_x * REGION_SIZE_CHUNKS) + (coord.z - region_z * REGION_SIZE_CHUNKS) * REGION_SIZE_CHUNKS
	for i in GameConfig.MUSIC_BOXES_PER_REGION:
		var pick := rng.next_index(slots.size())
		if int(slots[pick]) == local:
			return true
		slots.remove_at(pick)
	return false


## A music box (Glyra's counterplay, a random route item) on open floor clear of props, fixtures and pickups. Its own
## seed, so adding it moved no other item.
func _music_boxes(coord: Vector3i, grid: Array, stairs: Array, safe: bool, region_props: Array, fixtures: Array,
		pickups: Array) -> Array:
	if safe or not music_box_chunk(coord):
		return []
	var excluded := _stair_door_exclusion(stairs)
	for entry in region_props + fixtures + pickups:
		_exclude_neighbourhood(excluded, entry.get("cell", Vector2i.ZERO), 1)
	var candidates := []
	for z in range(1, CHUNK_SIZE - 1):
		for x in range(1, CHUNK_SIZE - 1):
			var cell := Vector2i(x, z)
			if grid[z][x] == 0 and not excluded.has(cell) and _open_spawn_neighbourhood(grid, cell):
				candidates.append(cell)
	if candidates.is_empty():
		return []
	var rng := SeededRandom.new("%s:MUSICBOX-CELL:%s" % [world_seed, chunk_id(coord)])
	return [{"id": "%s:music_box" % chunk_id(coord), "cell": candidates[rng.next_index(candidates.size())]}]


## One world tool by PICKUP_WEIGHTS (one roll of the chunk's stream, like the old even pick).
static func pick_tool(rng: SeededRandom) -> String:
	var roll := rng.next_float()
	for type in PICKUP_TYPES:
		roll -= float(PICKUP_WEIGHTS[type])
		if roll < 0.0:
			return type
	return PICKUP_TYPES[0]


static func _exclude_neighbourhood(excluded: Dictionary, cell: Vector2i,
		radius: int) -> void:
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			excluded[cell + Vector2i(dx, dz)] = true


static func _wall_count(grid: Array, cell: Vector2i) -> int:
	var result := 0
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP,
			Vector2i.DOWN]:
		var at: Vector2i = cell + direction
		if at.x < 0 or at.y < 0 or at.x >= CHUNK_SIZE \
				or at.y >= CHUNK_SIZE or int(grid[at.y][at.x]) != 0:
			result += 1
	return result


static func _backing_wall_direction(grid: Array, cell: Vector2i) -> Vector2i:
	if int(grid[cell.y - 1][cell.x]) != 0:
		return Vector2i.UP
	if int(grid[cell.y][cell.x + 1]) != 0:
		return Vector2i.RIGHT
	if int(grid[cell.y + 1][cell.x]) != 0:
		return Vector2i.DOWN
	return Vector2i.LEFT


static func _wall_backed_yaw(grid: Array, cell: Vector2i) -> float:
	# Compatibility helper for callers/tests that used the old name. The return
	# value now consistently describes the usable FRONT, not the backing wall.
	var open_direction := -_backing_wall_direction(grid, cell)
	return _room_facing_yaw(cell, cell + open_direction)


func _hunter_spawns(coord: Vector3i, grid: Array, stairs: Array,
		safe: bool, region_props: Array = []) -> Array:
	# Safe rooms themselves never spawn a hunter. The east neighbour of the
	# origin owns a guaranteed primary hunter so difficulty activation rules are
	# observable immediately: Hard wakes her at run start, Standard on relay one
	# and Relaxed on relay three. Distance plus the intact origin checkpoint is
	# the arrival grace instead of deleting every hunter from the loaded window.
	if safe:
		return []
	var profile := difficulty_for_level(coord.y)
	var danger := float(profile["danger"])
	var rng := SeededRandom.new("%s:HUNTERS:%s" % [world_seed, chunk_id(coord)])
	# These are dormant deterministic candidates. Runtime admits only the
	# relay-scaled population budget, so a denser pool lets new hunters join an
	# already explored area without making every candidate active at once.
	var spawn_chance := lerpf(0.16, 0.42, danger)
	var guaranteed_primary := coord == Vector3i(1, 0, 0)
	if not guaranteed_primary and rng.next_float() >= spawn_chance:
		return []
	var excluded := {}
	for stair in stairs:
		var stair_cell: Vector2i = stair["cell"]
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				excluded[stair_cell + Vector2i(dx, dz)] = true
	for prop in region_props:
		var prop_cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				excluded[prop_cell + Vector2i(dx, dz)] = true
	var candidates: Array[Vector2i] = []
	for z in range(3, CHUNK_SIZE - 3):
		for x in range(3, CHUNK_SIZE - 3):
			var cell := Vector2i(x, z)
			if grid[z][x] == 0 and not excluded.has(cell) \
					and _open_spawn_neighbourhood(grid, cell):
				candidates.append(cell)
	if candidates.is_empty():
		return []
	var count := 2 if guaranteed_primary else 1
	if coord.y <= -6 and rng.next_float() < minf(0.22, danger * 0.18):
		count = 2
	var result := []
	for index in count:
		if candidates.is_empty():
			break
		var picked := rng.next_index(candidates.size())
		var cell: Vector2i = candidates.pop_at(picked)
		var identity: String = STREAMED_HUNTER_IDS[rng.next_index(
			STREAMED_HUNTER_IDS.size())]
		# Office Void signals are genuinely rare before the full A-Z admission
		# milestone. Runtime raises this chance after 26 durable hunters have
		# entered the world; this tiny deterministic deep-floor roll is the early
		# surprise path requested for long survival runs.
		if coord.y <= -2 and rng.next_float() < .015:
			identity = HunterRoster.office_void_for("%s:%s:%d" % [
				world_seed, chunk_id(coord), index])
		result.append({
			"id": hunter_id(coord, index),
			"hunter_id": identity,
			"cell": cell,
			"level": coord.y,
			"origin_chunk": coord,
		})
		# Multiple candidates in one chunk must not materialize shoulder-to-
		# shoulder when a later relay expands the live population.
		candidates = candidates.filter(func(other: Vector2i) -> bool:
			return other.distance_to(cell) >= 6.0)
	return result


static func _open_spawn_neighbourhood(grid: Array, cell: Vector2i) -> bool:
	for offset in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT,
			Vector2i.UP, Vector2i.DOWN]:
		var at: Vector2i = cell + (offset as Vector2i)
		if at.x < 0 or at.y < 0 or at.x >= CHUNK_SIZE or at.y >= CHUNK_SIZE \
				or int(grid[at.y][at.x]) != 0:
			return false
	return true


static func _stair_style(region: String) -> String:
	match region:
		"mansion":
			return "grand_foyer"
		"hotel":
			return "hotel_stairwell"
		"apartment":
			return "apartment_stairwell"
		_:
			return "service_stairs"
