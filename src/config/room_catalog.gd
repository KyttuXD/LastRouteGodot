class_name RoomCatalog
extends RefCounted

## Mechanical room-content catalog ported from the original web build's
## game-config.js ROOM_TYPES and maze.js PROP_COLLIDERS. Art remains swappable:
## the generator consumes only ids, half-cell footprints, regions and labels.

const CENTERPIECE_TYPES := ["circusTent", "garden", "diningRoom",
	"ballroom", "beachCove", "netherChamber", "grandStairHall"]

## These are traversable architecture rather than furniture. They reserve a
## room from objectives/hiding spots but must not become solid to the 2D hunter
## pathfinder; the 3D view supplies their ramp and landing collision instead.
const WALKABLE_STRUCTURE_TYPES := ["grandStaircase", "grandFoyerStaircase"]

const TYPES := [
	{"id": "stage", "label": "ANIMATRONIC STAGE", "region": "arcade",
		"special": 1, "landmark": true,
		"props": ["stagePlatform", "stagePlatform", "stageSpeaker",
			"stageSpeaker", "privacyCurtain", "backstageRepairStand"]},
	{"id": "arcade", "label": "ARCADE FLOOR", "region": "arcade",
		"special": 2, "landmark": true,
		"props": ["arcadeCabinet", "arcadeCabinet", "arcadeCabinetCyanMagenta",
			"arcadeCabinet", "arcadeBasketballHoop", "arcadeCarpetCircle",
			"arcadeCarpetRunner", "prizeCounter", "vendingMachine",
			"arcadeTokenChanger", "snackKiosk", "privacyCurtain"]},
	{"id": "serviceBay", "label": "ANIMATRONIC SERVICE BAY",
		"region": "maintenance", "special": 5, "landmark": true,
		"props": ["privacyCurtain", "privacyCurtain", "utilityCart",
			"breakerCabinet", "maintenanceToolCabinet", "maintenanceCleaningCart",
			"backstageRepairStand", "locker", "supplyCrates", "serverRack"]},
	{"id": "prizeGallery", "label": "PRIZE GALLERY", "region": "arcade",
		"special": 6, "landmark": true,
		"props": ["prizeCounter", "prizeCounter", "arcadeCabinet",
			"arcadeCabinet", "arcadeCarpetCircle", "vendingMachine",
			"prizeClawMachine", "arcadeTokenChanger", "mascotStatue",
			"loungeCouch", "brokenAquarium"]},
	{"id": "arcadeHallway", "label": "ARCADE HALLWAY", "region": "arcade",
		"special": 8, "landmark": true,
		"props": ["arcadeCabinet", "arcadeCabinetCyanMagenta",
			"arcadeCarpetRunner", "arcadeCarpetRunner", "stageSpeaker",
			"privacyCurtain"]},
	{"id": "relayControl", "label": "RELAY CONTROL", "region": "office",
		"special": 10, "landmark": true,
		"props": ["serverRack", "serverRack", "breakerCabinet",
			"breakerCabinet", "officeDesk", "officeChair",
			"officeCrtSecurityConsole", "retroComputerDesktop",
			"filingCabinet"]},
	{"id": "grandStairHall", "label": "GRAND STAIR HALL", "region": "mansion",
		"special": 9, "landmark": true,
		"props": ["grandFoyerStaircase"]},
	{"id": "diningRoom", "label": "GRAND DINING ROOM", "region": "mansion",
		"special": 10, "landmark": true,
		"props": ["diningTable", "diningChair", "diningChair",
			"diningChairCushion", "diningChairCushion", "diningChair",
			"diningChair", "diningChandelier", "diningSideboard", "trashBin",
			"flowerCenterpiece", "tableCandelabra", "framedWallPortrait",
			"luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty", "wallSconce"]},
	{"id": "kitchen", "label": "HOUSE KITCHEN", "region": "mansion",
		"props": ["normalKitchenCounter", "normalKitchenCounter",
			"normalKitchenSink", "normalKitchenStove", "normalKitchenFridge",
			"normalKitchenWallCabinet", "normalKitchenWallCabinet",
			"normalKitchenIsland", "normalEntryBench", "ceilingLight",
			"normalPictureFrameEmpty"]},
	{"id": "luxuryKitchen", "label": "MANSION KITCHEN", "region": "mansion",
		"large_only": true,
		"props": ["luxuryKitchenCounter", "luxuryKitchenCounter",
			"luxuryKitchenSink", "luxuryKitchenStove", "luxuryKitchenFridge",
			"luxuryKitchenWallCabinet", "luxuryKitchenWallCabinet",
			"luxuryKitchenIsland", "mansionDisplayCabinet", "mansionTeaCart",
			"ceilingFan",
			"luxuryPictureFrameEmpty"]},
	{"id": "gothicKitchen", "label": "GOTHIC KITCHEN", "region": "mansion",
		"large_only": true,
		"props": ["gothicKitchenCounter", "gothicKitchenCounter",
			"gothicKitchenSink", "gothicKitchenStove", "gothicKitchenFridge",
			"gothicKitchenWallCabinet", "gothicKitchenWallCabinet",
			"gothicKitchenIsland", "gothicFloorCandelabra", "ceilingLight",
			"gothicCoffinChest", "gothicPictureFrameEmpty"]},
	{"id": "bathroomMale", "label": "MANSION BATHROOM // MEN",
		"region": "mansion", "special": 11, "landmark": true,
		"props": ["bathroomStall", "bathroomStall", "publicRestroomToilet",
			"publicRestroomToilet", "publicMensUrinal", "publicMensUrinal",
			"publicMensUrinal", "publicSinkBank", "bathroomMirror",
			"publicHandDryer", "publicSoapDispenser",
			"publicPaperTowelDispenser", "publicMensRoomSign", "trashBin",
			"ceilingLight"]},
	{"id": "bathroomFemale", "label": "MANSION BATHROOM // WOMEN",
		"region": "mansion", "special": 12, "landmark": true,
		"props": ["bathroomStall", "bathroomStall", "bathroomStall",
			"publicRestroomToilet", "publicRestroomToilet",
			"publicRestroomToilet", "publicSinkBank", "bathroomMirror",
			"publicHandDryer", "publicSoapDispenser",
			"publicPaperTowelDispenser", "publicSanitaryBin",
			"publicSanitaryBin", "publicBabyChangeStation",
			"publicWomensRoomSign", "trashBin", "ceilingLight"]},
	{"id": "publicShowersMale", "label": "PUBLIC SHOWERS // MEN",
		"region": "mansion",
		"props": ["publicMensShowerStall", "publicMensShowerStall",
			"publicMensShowerStall", "publicShowerBench", "publicSoapDispenser",
			"publicSoapDispenser", "houseTowelRack", "publicMensRoomSign",
			"houseBathMat"]},
	{"id": "publicShowersFemale", "label": "PUBLIC SHOWERS // WOMEN",
		"region": "mansion",
		"props": ["publicWomensShowerStall", "publicWomensShowerStall",
			"publicWomensShowerStall", "publicShowerBench", "publicSoapDispenser",
			"publicSoapDispenser", "houseTowelRack", "publicWomensRoomSign",
			"houseBathMat"]},
	{"id": "houseBathroom", "label": "HOUSE BATHROOM", "region": "mansion",
		"props": ["houseBathtub", "houseToilet", "houseShowerEnclosure",
			"bathroomVanity", "houseMedicineCabinet", "houseTowelRack",
			"houseBathMat", "houseBathroomShelf", "laundryHamper", "trashBin",
			"ceilingLight"]},
	{"id": "netherChamber", "label": "THERMAL INFERNO", "region": "nether",
		"special": 13, "large_only": true, "landmark": true,
		"props": ["lavaVent", "lavaVent", "emberBrazier", "emberBrazier",
			"basaltPillar", "basaltPillar", "basaltPillar", "basaltRubble",
			"magmaCrystalCluster", "infernoAltar", "infernoChainLantern",
			"lavaPipeManifold", "charredSupplyCrate"]},
	{"id": "prisonCellBlock", "label": "LOWER CELL BLOCK", "region": "prison",
		"streamed_only": true, "landmark": true,
		"props": ["prisonCellGate", "prisonCellGate", "prisonBunk",
			"prisonBunk", "dungeonCage", "restraintChair", "supplyCrates",
			"infernoChainLantern"]},
	{"id": "prisonCafeteria", "label": "PRISON CAFETERIA", "region": "prison",
		"streamed_only": true, "landmark": true,
		"props": ["prisonServingCounter", "prisonServingCounter",
			"prisonCafeteriaTable", "prisonCafeteriaTable",
			"prisonTrayReturn", "prisonKitchenRack", "normalKitchenFridge",
			"normalKitchenStove", "normalPictureFrameEmpty", "ceilingLight",
			"ceilingLight"]},
	{"id": "beachCove", "label": "FROZEN TIDELINE", "region": "beach",
		"special": 13, "large_only": true, "landmark": true,
		"props": ["tikiBar", "beachUmbrella", "beachUmbrella", "sandCastle",
			"sandCastle", "beachChair", "beachChair", "surfboardRack",
			"palmTree", "palmTree", "frozenBeachHut"]},
	{"id": "cargoDepot", "label": "CARGO DEPOT", "region": "maintenance",
		"special": 14, "large_only": true, "landmark": true,
		"props": ["supplyCrates", "supplyCrates", "supplyCrates",
			"utilityCart", "utilityCart", "locker", "breakerCabinet"]},
	{"id": "ballroom", "label": "MANSION BALLROOM", "region": "mansion",
		"special": 15, "large_only": true, "landmark": true,
		"props": ["diningTable", "diningTable", "diningChair", "diningChair",
			"diningChairCushion", "diningChairCushion", "diningChairCushion",
			"diningChairCushion", "diningChandelier", "floorLamp",
			"mansionAreaRug", "loungeCouchWide", "heavyMansionDrapes",
			"wallSconce", "framedWallPortrait", "flowerCenterpiece",
			"luxuryPaintingFrameEmpty",
			"tableCandelabra", "mansionUprightPiano", "mansionBustPedestal",
			"mansionChaiseLounge"]},
	{"id": "garden", "label": "INDOOR GARDEN", "region": "garden",
		"special": 16, "large_only": true, "landmark": true,
		"props": ["giantTree", "gardenPlanterBench", "gardenPlanterBench",
			"grassFern", "grassFern", "grassFern", "grassFern", "flowerRose",
			"flowerSun", "flowerBlue", "flowerViolet", "flowerRose",
			"flowerSun", "flowerBlue", "flowerViolet"]},
	{"id": "library", "label": "MANSION LIBRARY", "region": "mansion",
		"special": 17, "large_only": true, "landmark": true,
		"props": ["mansionBookshelf", "mansionBookshelf", "magazineRack",
			"woodenTable", "woodenChair", "woodenChairCushion", "floorLamp",
			"mansionFireplace", "loungeCouchWide", "mansionAreaRug",
			"framedWallPortrait", "wallSconce", "heavyMansionDrapes",
			"luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty",
			"mansionDisplayCabinet", "mansionBustPedestal"]},
	{"id": "circusTent", "label": "CIRCUS TENT", "region": "circus",
		"special": 18, "large_only": true, "landmark": true,
		"props": ["carnivalCarousel", "arcadeCarpetCircle", "privacyCurtain",
			"privacyCurtain", "stageSpeaker"]},
	{"id": "masterBedroom", "label": "MANSION MASTER BEDROOM",
		"region": "mansion", "special": 19, "large_only": true,
		"landmark": true,
		"props": ["doubleBed", "bedroomNightstand", "bedroomNightstand",
			"bedsideLamp", "tableLamp", "ceilingFan", "bedroomWardrobe", "bedroomDresser",
			"bedroomVanity", "vanityStool", "bedroomBench", "bedroomRug",
			"laundryHamper", "toyChest", "bedroomWallClock", "wallSconce",
			"mansionConsoleTable", "mansionRockingChair", "mansionRoomDivider",
			"bunkBed"]},
	{"id": "gothicBedroom", "label": "GOTHIC MASTER BEDROOM",
		"region": "mansion", "special": 20, "large_only": true,
		"landmark": true,
		"props": ["gothicDoubleBed", "gothicNightstand", "gothicNightstand",
			"gothicBedsideCandelabra", "gothicWardrobe", "gothicDresser",
			"gothicVanity", "gothicVanityStool", "gothicBedroomBench",
			"gothicBedroomRug", "gothicHighbackChair", "gothicWritingDesk",
			"gothicBookcase", "gothicPedestalTable", "gothicFloorCandelabra",
			"gothicCoffinChest", "gothicPictureFrameEmpty",
			"gothicPaintingFrameEmpty"]},
	{"id": "bedroom", "label": "MANSION BEDROOM", "region": "mansion",
		"props": ["singleBed", "bedroomNightstand", "bedsideLamp",
			"tableLamp", "ceilingFan", "bedroomWardrobe", "bedroomDresser", "bedroomVanity",
			"vanityStool", "bedroomBench", "bedroomRug", "laundryHamper",
			"toyChest", "bedroomWallClock", "mansionCoatRack", "bunkBed",
			"mansionRockingChair", "normalBookcase", "normalEntryBench",
			"normalPictureFrameEmpty", "normalPaintingFrameEmpty"]},
	{"id": "office", "label": "OFFICE WING", "region": "office",
		"props": ["officeDesk", "officeChair", "officeDesk", "officeChair",
			"officeCrtSecurityConsole", "retroComputerCompact",
			"retroComputerTower", "retroComputerDesktop",
			"retroComputerTerminal", "filingCabinet", "filingCabinet",
			"officeCubiclePartition", "officeCubiclePartition",
			"officePrinter", "officePhotocopier", "officeShredder",
			"officeFileBoxes", "officeCornerWorkstation",
			"officeWaterCooler", "tableLamp",
			"ceilingLight", "normalTvConsole"]},
	{"id": "maintenance", "label": "MAINTENANCE", "region": "maintenance",
		"props": ["locker", "serverRack", "supplyCrates", "utilityCart",
			"breakerCabinet", "maintenanceToolCabinet",
			"maintenanceCleaningCart", "backstageRepairStand"]},
	{"id": "storage", "label": "STORAGE", "region": "maintenance",
		"props": ["supplyCrates", "filingCabinet", "locker", "utilityCart"]},
	{"id": "server", "label": "SERVER ROOM", "region": "maintenance",
		"props": ["serverRack", "serverRack", "locker", "breakerCabinet"]},
	{"id": "breakroom", "label": "STAFF BREAKROOM", "region": "mansion",
		"props": ["loungeCouchWide", "officeDesk", "woodenTable", "woodenChair",
			"woodenChairCushion", "floorLamp", "trashBin", "privacyCurtain",
			"normalTvConsole", "normalCoffeeTable", "ceilingFan", "tableLamp"]},
	{"id": "lounge", "label": "STAFF LOUNGE", "region": "mansion",
		"props": ["loungeCouchWide", "officeDesk", "woodenChair",
			"woodenChairCushion", "woodenTable", "floorLamp", "magazineRack",
			"privacyCurtain", "mansionAreaRug", "mansionGrandfatherClock",
			"mansionTeaCart", "mansionConsoleTable", "normalBookcase",
			"normalTvConsole", "normalCoffeeTable", "normalEntryBench",
			"mansionChaiseLounge", "mansionUprightPiano", "ceilingFan", "tableLamp"]},
]

const REGION_DEFAULT_TYPE := {
	"office": "office", "maintenance": "maintenance", "arcade": "arcade",
	"circus": "circusTent", "nether": "netherChamber", "beach": "beachCove",
	"mansion": "diningRoom", "bedroom": "bedroom", "garden": "garden",
	"prison": "prisonCellBlock",
}

## Pieces that need their back oriented toward the nearest room edge. The
## generator writes that rotation into its deterministic prop entry so visual
## geometry and rectangular collision agree on every co-op peer.
const WALL_BACKED_TYPES := [
	"arcadeCabinet", "arcadeCabinetCyanMagenta", "vendingMachine",
	"filingCabinet", "serverRack", "privacyCurtain", "loungeCouch",
	"loungeCouchWide", "diningSideboard", "mansionBookshelf",
	"mansionFireplace", "bathroomStall", "bathroomSink", "bathroomMirror",
	"bathroomVanity", "grandStaircase", "surfboardRack", "heavyMansionDrapes",
	"publicRestroomToilet", "publicMensUrinal", "publicSinkBank",
	"publicHandDryer", "publicSoapDispenser", "publicPaperTowelDispenser",
	"publicBabyChangeStation", "publicMensRoomSign", "publicWomensRoomSign",
	"publicMensShowerStall", "publicWomensShowerStall",
	"houseBathtub", "houseToilet", "houseShowerEnclosure",
	"houseMedicineCabinet", "houseTowelRack", "houseBathroomShelf",
	"framedWallPortrait", "normalPictureFrameEmpty", "normalPaintingFrameEmpty",
	"luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty",
	"gothicPictureFrameEmpty", "gothicPaintingFrameEmpty",
	"wallSconce", "lavaPipeManifold",
	"singleBed", "doubleBed", "bedroomNightstand", "bedroomWardrobe",
	"bedroomDresser", "bedroomVanity", "bedroomWallClock",
	"mansionConsoleTable", "mansionGrandfatherClock", "mansionRoomDivider",
	"gothicDoubleBed", "gothicNightstand", "gothicWardrobe",
	"gothicDresser", "gothicVanity", "gothicWritingDesk", "gothicBookcase",
	"normalKitchenCounter", "normalKitchenSink", "normalKitchenStove",
	"normalKitchenFridge", "normalKitchenWallCabinet",
	"luxuryKitchenCounter", "luxuryKitchenSink", "luxuryKitchenStove",
	"luxuryKitchenFridge", "luxuryKitchenWallCabinet",
	"gothicKitchenCounter", "gothicKitchenSink", "gothicKitchenStove",
	"gothicKitchenFridge", "gothicKitchenWallCabinet",
	"normalBookcase", "normalTvConsole", "normalEntryBench",
	"mansionDisplayCabinet", "mansionChaiseLounge", "mansionUprightPiano",
	"prisonCellGate", "prisonBunk",
]

## Small dining dressing shares the cell of a real table and is lifted to its
## authored tabletop instead of being scattered across the floor.
const SURFACE_PARENT_TYPES := {
	"flowerCenterpiece": ["diningTable", "woodenTable"],
	"tableCandelabra": ["diningTable", "woodenTable"],
	"bedsideLamp": ["bedroomNightstand", "bedroomDresser"],
	"tableLamp": ["bedroomNightstand", "bedroomDresser", "woodenTable",
		"diningSideboard", "officeDesk", "normalCoffeeTable"],
	"retroComputerCompact": ["officeDesk", "woodenTable",
		"officeCornerWorkstation"],
	"retroComputerTower": ["officeDesk", "woodenTable",
		"officeCornerWorkstation"],
	"retroComputerDesktop": ["officeDesk", "woodenTable",
		"officeCornerWorkstation"],
	"retroComputerTerminal": ["officeDesk", "woodenTable",
		"officeCornerWorkstation"],
	"officePrinter": ["officeDesk", "woodenTable"],
	"gothicBedsideCandelabra": ["gothicNightstand", "gothicDresser",
		"gothicPedestalTable"],
}

const SURFACE_HEIGHTS := {
	# The dining model reaches 1.03 m only at its goblets. Dressing belongs on
	# the 0.86 m runner/tabletop, not floating above those place settings.
	"diningTable": .86,
	"woodenTable": .79,
	"bedroomNightstand": .71,
	"bedroomDresser": 1.04,
	"gothicNightstand": .79,
	"gothicDresser": 1.10,
	"gothicPedestalTable": .90,
	"diningSideboard": 1.02,
	"officeDesk": .78,
	"officeCornerWorkstation": .78,
	"normalCoffeeTable": .49,
}

## Half-width/half-depth in grid metres, matching the original collider table.
## Unknown future props retain a conservative one-cell footprint.
const FOOTPRINTS := {
	"arcadeCabinet": Vector2(.27, .30), "arcadeCabinetCyanMagenta": Vector2(.27, .30),
	"arcadeBasketballHoop": Vector2(.42, .50), "arcadeCarpetCircle": Vector2(.48, .48),
	"arcadeCarpetRunner": Vector2(.42, .20), "loungeCouch": Vector2(.51, .30),
	"loungeCouchWide": Vector2(.91, .30),
	"locker": Vector2(.30, .36), "officeDesk": Vector2(.42, .28),
	"securityDesk": Vector2(.54, .34), "officeChair": Vector2(.21, .21),
	"officeCameraConsole": Vector2(.40, .30), "officeSignalScanner": Vector2(.28, .32),
	"mascotStatue": Vector2(.34, .36), "snackKiosk": Vector2(.48, .30),
	"filingCabinet": Vector2(.29, .33), "supplyCrates": Vector2(.37, .29),
	"serverRack": Vector2(.32, .37), "privacyCurtain": Vector2(.40, .18),
	"stagePlatform": Vector2(.46, .38), "stageSpeaker": Vector2(.33, .37),
	"prizeCounter": Vector2(.44, .27), "vendingMachine": Vector2(.31, .37),
	"utilityCart": Vector2(.40, .28), "breakerCabinet": Vector2(.29, .36),
	"maintenanceToolCabinet": Vector2(.31, .37), "arcadeTokenChanger": Vector2(.30, .35),
	"officeCrtSecurityConsole": Vector2(.43, .30), "prizeClawMachine": Vector2(.34, .36),
	"maintenanceCleaningCart": Vector2(.40, .28), "backstageRepairStand": Vector2(.42, .36),
	"brokenAquarium": Vector2(.46, .32), "carnivalCarousel": Vector2(2.20, 1.80),
	"woodenChair": Vector2(.25, .25), "woodenChairCushion": Vector2(.25, .25),
	"woodenTable": Vector2(.60, .38), "diningTable": Vector2(1.10, .42),
	"diningChair": Vector2(.25, .25), "diningChairCushion": Vector2(.25, .25),
	"diningChandelier": Vector2(.47, .47), "diningSideboard": Vector2(.72, .35),
	"flowerCenterpiece": Vector2(.25, .20), "tableCandelabra": Vector2(.32, .16),
	"framedWallPortrait": Vector2(.44, .12), "wallSconce": Vector2(.12, .18),
	"ceilingLight": Vector2(.37, .37), "ceilingFan": Vector2(.74, .74),
	"tableLamp": Vector2(.25, .18),
	"retroComputerCompact": Vector2(.55, .33),
	"retroComputerTower": Vector2(.62, .33),
	"retroComputerDesktop": Vector2(.55, .33),
	"retroComputerTerminal": Vector2(.55, .33),
	"officeCubiclePartition": Vector2(.90, .12),
	"officePrinter": Vector2(.36, .29),
	"officeWaterCooler": Vector2(.28, .25),
	"officePhotocopier": Vector2(.46, .40),
	"officeShredder": Vector2(.27, .22),
	"officeFileBoxes": Vector2(.45, .31),
	"officeCornerWorkstation": Vector2(.78, .60),
	"prisonCafeteriaTable": Vector2(1.33, .89),
	"prisonServingCounter": Vector2(1.23, .44),
	"prisonTrayReturn": Vector2(.50, .36),
	"prisonKitchenRack": Vector2(.68, .32),
	"normalPictureFrameEmpty": Vector2(.36, .08),
	"normalPaintingFrameEmpty": Vector2(.61, .08),
	"luxuryPictureFrameEmpty": Vector2(.40, .09),
	"luxuryPaintingFrameEmpty": Vector2(.66, .09),
	"gothicPictureFrameEmpty": Vector2(.40, .09),
	"gothicPaintingFrameEmpty": Vector2(.66, .09),
	"heavyMansionDrapes": Vector2(.78, .11), "mansionAreaRug": Vector2(1.30, .80),
	"floorLamp": Vector2(.22, .22), "magazineRack": Vector2(.30, .25),
	"trashBin": Vector2(.25, .25), "giantTree": Vector2(1.25, 1.25),
	"gardenPlanterBench": Vector2(.58, .30), "mansionBookshelf": Vector2(.39, .31),
	"grassFern": Vector2(.22, .22), "flowerRose": Vector2(.16, .16),
	"flowerSun": Vector2(.16, .16), "flowerBlue": Vector2(.16, .16),
	"flowerViolet": Vector2(.16, .16), "bathroomStall": Vector2(.34, .28),
	"bathroomSink": Vector2(.40, .22), "bathroomMirror": Vector2(.35, .16),
	"bathroomVanity": Vector2(.41, .25), "mansionFireplace": Vector2(.51, .36),
	"publicRestroomToilet": Vector2(.25, .38),
	"publicMensUrinal": Vector2(.25, .24),
	"publicSinkBank": Vector2(.83, .24),
	"publicHandDryer": Vector2(.20, .13),
	"publicSoapDispenser": Vector2(.11, .13),
	"publicPaperTowelDispenser": Vector2(.20, .13),
	"publicBabyChangeStation": Vector2(.46, .52),
	"publicSanitaryBin": Vector2(.18, .20),
	"publicMensRoomSign": Vector2(.26, .06),
	"publicWomensRoomSign": Vector2(.26, .06),
	"publicMensShowerStall": Vector2(.43, .43),
	"publicWomensShowerStall": Vector2(.43, .43),
	"publicShowerBench": Vector2(.61, .18),
	"houseBathtub": Vector2(.89, .40),
	"houseToilet": Vector2(.25, .38),
	"houseShowerEnclosure": Vector2(.47, .47),
	"houseMedicineCabinet": Vector2(.35, .12),
	"houseTowelRack": Vector2(.39, .13),
	"houseBathMat": Vector2(.46, .29),
	"corridorCarpet": Vector2(1.20, 1.70),
	"hotelCarpet": Vector2(1.10, .70),
	"apartmentCarpet": Vector2(1.00, .77),
	"beachMat": Vector2(.70, .43),
	"houseBathroomShelf": Vector2(.43, .13),
	"grandStaircase": Vector2(.90, 3.25),
	"grandFoyerStaircase": Vector2(2.35, 3.35),
	"lavaVent": Vector2(.34, .30), "emberBrazier": Vector2(.25, .25),
	"basaltPillar": Vector2(.32, .32), "sandCastle": Vector2(.40, .34),
	"basaltRubble": Vector2(.61, .58), "magmaCrystalCluster": Vector2(.34, .34),
	"infernoAltar": Vector2(.60, .41), "infernoChainLantern": Vector2(.21, .21),
	"lavaPipeManifold": Vector2(.60, .32), "charredSupplyCrate": Vector2(.37, .34),
	"beachUmbrella": Vector2(1.15, 1.15), "tikiBar": Vector2(.77, .52),
	"beachChair": Vector2(.36, .25), "surfboardRack": Vector2(.68, .30),
	"palmTree": Vector2(.52, .52), "frozenBeachHut": Vector2(1.10, .92),
	"singleBed": Vector2(.54, 1.33), "doubleBed": Vector2(.91, 1.33),
	"bedroomNightstand": Vector2(.29, .25),
	"bedroomWardrobe": Vector2(.60, .31),
	"bedroomDresser": Vector2(.62, .28),
	"bedroomVanity": Vector2(.51, .24), "vanityStool": Vector2(.20, .18),
	"bedsideLamp": Vector2(.18, .16), "toyChest": Vector2(.41, .26),
	"laundryHamper": Vector2(.27, .25), "bedroomRug": Vector2(.86, .59),
	"bedroomWallClock": Vector2(.26, .08), "bedroomBench": Vector2(.51, .19),
	"mansionConsoleTable": Vector2(.61, .22),
	"mansionGrandfatherClock": Vector2(.35, .23),
	"mansionCoatRack": Vector2(.26, .26), "mansionTeaCart": Vector2(.53, .25),
	"mansionRockingChair": Vector2(.34, .47),
	"mansionRoomDivider": Vector2(.82, .14),
	"gothicDoubleBed": Vector2(1.00, 1.40),
	"gothicNightstand": Vector2(.33, .27),
	"gothicWardrobe": Vector2(.66, .33),
	"gothicDresser": Vector2(.68, .31), "gothicVanity": Vector2(.55, .25),
	"gothicVanityStool": Vector2(.22, .19),
	"gothicBedroomBench": Vector2(.55, .21),
	"gothicBedroomRug": Vector2(1.10, .71),
	"gothicBedsideCandelabra": Vector2(.20, .15),
	"gothicHighbackChair": Vector2(.35, .31),
	"gothicWritingDesk": Vector2(.69, .31), "gothicBookcase": Vector2(.61, .27),
	"gothicPedestalTable": Vector2(.38, .38),
	"gothicFloorCandelabra": Vector2(.27, .23),
	"gothicCoffinChest": Vector2(.52, .28),
	"normalKitchenCounter": Vector2(.73, .33),
	"normalKitchenSink": Vector2(.61, .33),
	"normalKitchenStove": Vector2(.41, .33),
	"normalKitchenFridge": Vector2(.41, .35),
	"normalKitchenWallCabinet": Vector2(.60, .21),
	"normalKitchenIsland": Vector2(.81, .44),
	"luxuryKitchenCounter": Vector2(.73, .33),
	"luxuryKitchenSink": Vector2(.61, .33),
	"luxuryKitchenStove": Vector2(.41, .33),
	"luxuryKitchenFridge": Vector2(.41, .35),
	"luxuryKitchenWallCabinet": Vector2(.60, .21),
	"luxuryKitchenIsland": Vector2(.81, .44),
	"gothicKitchenCounter": Vector2(.73, .33),
	"gothicKitchenSink": Vector2(.61, .33),
	"gothicKitchenStove": Vector2(.41, .33),
	"gothicKitchenFridge": Vector2(.41, .35),
	"gothicKitchenWallCabinet": Vector2(.60, .21),
	"gothicKitchenIsland": Vector2(.81, .44),
	"normalBookcase": Vector2(.48, .19),
	"normalCoffeeTable": Vector2(.61, .35),
	"normalTvConsole": Vector2(.70, .24),
	"normalEntryBench": Vector2(.60, .22),
	"mansionDisplayCabinet": Vector2(.61, .23),
	"mansionChaiseLounge": Vector2(.88, .35),
	"mansionUprightPiano": Vector2(.77, .45),
	"mansionBustPedestal": Vector2(.27, .27),
	"prisonCellGate": Vector2(1.48, .18), "prisonBunk": Vector2(.55, .98),
	"dungeonCage": Vector2(1.25, 1.25), "restraintChair": Vector2(.55, .55),
}


static func type_by_id(id: String) -> Dictionary:
	for entry in TYPES:
		if String(entry["id"]) == id:
			return entry
	return {}


static func type_for_region(region: String) -> Dictionary:
	return type_by_id(String(REGION_DEFAULT_TYPE.get(region, "")))


static func footprint(type: String, rotation: int = 0) -> Vector2:
	var value: Vector2 = FOOTPRINTS.get(type, Vector2(.32, .32))
	return Vector2(value.y, value.x) if absi(rotation) % 2 == 1 else value


static func color_for_region(region: String) -> Color:
	return {
		"arcade": Color("a755b2"), "maintenance": Color("9b7438"),
		"office": Color("586b86"), "mansion": Color("73503f"),
		"bedroom": Color("77546f"),
		"nether": Color("8d302d"), "beach": Color("87b8c8"),
		"prison": Color("35424a"),
		"garden": Color("527b4c"), "circus": Color("bd536e"),
	}.get(region, Color("68616b"))


static func is_wall_backed(type: String) -> bool:
	return WALL_BACKED_TYPES.has(type)


static func is_surface_prop(type: String) -> bool:
	return SURFACE_PARENT_TYPES.has(type)


static func surface_parent_types(type: String) -> Array:
	return SURFACE_PARENT_TYPES.get(type, [])


static func surface_height(parent_type: String) -> float:
	return float(SURFACE_HEIGHTS.get(parent_type, 0.8))


static func display_height(type: String) -> float:
	if type in ["arcadeCarpetCircle", "arcadeCarpetRunner"]:
		return .025
	if type in ["diningChandelier", "ceilingLight", "ceilingFan",
			"infernoChainLantern"]:
		return .16
	if type in ["bedroomRug", "gothicBedroomRug"]:
		return .09
	if type == "houseBathMat":
		return .07
	if type in ["grandStaircase", "grandFoyerStaircase"]:
		return 2.80 if type == "grandFoyerStaircase" else 1.10
	if type in ["flowerRose", "flowerSun", "flowerBlue", "flowerViolet",
			"grassFern", "sandCastle", "lavaVent", "basaltRubble"]:
		return .45
	if type in ["woodenChair", "woodenChairCushion", "diningChair",
			"diningChairCushion", "beachChair", "officeChair", "vanityStool",
			"bedroomBench", "toyChest", "laundryHamper", "gothicVanityStool",
			"gothicBedroomBench", "gothicHighbackChair", "gothicCoffinChest"]:
		return .78
	if type in ["singleBed", "doubleBed", "gothicDoubleBed"]:
		return 1.34
	if type in ["publicMensShowerStall", "publicWomensShowerStall",
			"houseShowerEnclosure"]:
		return 2.16
	if type in ["prisonCellGate", "dungeonCage"]:
		return 2.8
	if type == "prisonBunk":
		return 1.55
	if type == "restraintChair":
		return 1.95
	if type in ["publicRestroomToilet", "houseToilet"]:
		return 1.21
	if type in ["bedroomWardrobe", "gothicWardrobe", "gothicBookcase"]:
		return 2.11
	if type in ["bedroomDresser", "bedroomNightstand", "gothicDresser",
			"gothicNightstand"]:
		return 1.04 if type in ["bedroomDresser", "gothicDresser"] else .71
	if type in ["bedroomVanity", "gothicVanity"]:
		return 1.82
	if type in ["diningTable", "woodenTable", "utilityCart", "tikiBar",
			"gardenPlanterBench", "loungeCouch", "loungeCouchWide",
			"stagePlatform", "charredSupplyCrate"]:
		return .9
	if type in ["giantTree", "palmTree", "carnivalCarousel", "frozenBeachHut"]:
		return 2.45
	return 1.55


static func is_solid(type: String) -> bool:
	return type not in ["arcadeCarpetCircle", "arcadeCarpetRunner",
		"diningChandelier", "ceilingLight", "ceilingFan",
		"infernoChainLantern", "bathroomMirror",
		"mansionAreaRug", "framedWallPortrait", "normalPictureFrameEmpty",
		"normalPaintingFrameEmpty", "luxuryPictureFrameEmpty",
		"luxuryPaintingFrameEmpty", "gothicPictureFrameEmpty",
		"gothicPaintingFrameEmpty", "wallSconce",
		"heavyMansionDrapes", "flowerCenterpiece", "tableCandelabra",
		"bedroomRug", "bedroomWallClock", "bedsideLamp", "tableLamp",
		"retroComputerCompact", "retroComputerTower",
		"retroComputerDesktop", "retroComputerTerminal",
		"gothicBedroomRug",
		"gothicBedsideCandelabra", "publicHandDryer",
		"publicSoapDispenser", "publicPaperTowelDispenser",
		"publicMensRoomSign", "publicWomensRoomSign", "houseMedicineCabinet",
		"houseTowelRack", "houseBathMat", "houseBathroomShelf",
		"grandStaircase", "grandFoyerStaircase"]


static func is_walkable_structure(type: String) -> bool:
	return WALKABLE_STRUCTURE_TYPES.has(type)


static func room_has_walkable_structure(type: String) -> bool:
	var entry := type_by_id(type)
	for prop_type in entry.get("props", []):
		if is_walkable_structure(String(prop_type)):
			return true
	return false
