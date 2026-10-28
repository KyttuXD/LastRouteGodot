class_name PropModelCatalog
extends RefCounted

## Presentation-only catalog for authored room dressing. FacilityGenerator
## owns deterministic placement and collision through RoomCatalog; this file
## only selects which imported model represents a mechanical prop type.
## Multiple paths are intentional visual variants and are selected from the
## stable generated prop id, so every peer sees the same couch/cabinet colour.

## Use the Minecraft-style block rebuilds (BlockyPropModels) where they exist.
const USE_BLOCKY_PROPS := true

## Read MODEL_PATHS, not this: ContentRegistry.DATA entries come from res://data/props (docs/DATA_DRIVEN_CONTENT.md).
const _CODE_MODEL_PATHS := {
	## Mansion pieces (tools/props/blocky_props_mansion.py), blocky-only.
	"mansionMarbleColumn": ContentRegistry.DATA,
	"mansionPorcelainVase": ContentRegistry.DATA,
	## Room-purpose catalog (tools/props/blocky_props_rework4.py): designed blocky-only, so the blocky GLBs are also their
	## catalogue models.
	"ivStand": ContentRegistry.DATA,
	"medicalCart": ContentRegistry.DATA,
	"readingTable": ContentRegistry.DATA,
	"libraryGlobe": ContentRegistry.DATA,
	"storageBarrel": ContentRegistry.DATA,
	"storageShelving": ContentRegistry.DATA,
	"receptionDesk": ContentRegistry.DATA,
	"pottedPlant": ContentRegistry.DATA,
	"standingMirror": ContentRegistry.DATA,
	"arcadeCabinet": ContentRegistry.DATA,
	"arcadeCabinetCyanMagenta": ContentRegistry.DATA,
	"filingCabinet": ContentRegistry.DATA,
	"officeDesk": ContentRegistry.DATA,
	"officeChair": ContentRegistry.DATA,
	"officeCrtSecurityConsole": ContentRegistry.DATA,
	"officeCubiclePartition": ContentRegistry.DATA,
	"officePrinter": ContentRegistry.DATA,
	"officeWaterCooler": ContentRegistry.DATA,
	"officePhotocopier": ContentRegistry.DATA,
	"officeShredder": ContentRegistry.DATA,
	"officeFileBoxes": ContentRegistry.DATA,
	"officeCornerWorkstation": ContentRegistry.DATA,
	"arcadeBasketballHoop": ContentRegistry.DATA,
	"arcadeCarpetCircle": ContentRegistry.DATA,
	"arcadeCarpetRunner": ContentRegistry.DATA,
	"arcadeTokenChanger": ContentRegistry.DATA,
	"backstageRepairStand": ContentRegistry.DATA,
	"breakerCabinet": ContentRegistry.DATA,
	"brokenAquarium": ContentRegistry.DATA,
	"carnivalCarousel": ContentRegistry.DATA,
	"flowerBlue": ContentRegistry.DATA,
	"flowerRose": ContentRegistry.DATA,
	"flowerSun": ContentRegistry.DATA,
	"flowerViolet": ContentRegistry.DATA,
	"gardenPlanterBench": ContentRegistry.DATA,
	"giantTree": ContentRegistry.DATA,
	"grassFern": ContentRegistry.DATA,
	"locker": ContentRegistry.DATA,
	"maintenanceCleaningCart": ContentRegistry.DATA,
	"maintenanceToolCabinet": ContentRegistry.DATA,
	"mascotStatue": ContentRegistry.DATA,
	"prizeClawMachine": ContentRegistry.DATA,
	"prizeCounter": ContentRegistry.DATA,
	"snackKiosk": ContentRegistry.DATA,
	"stagePlatform": ContentRegistry.DATA,
	"stageSpeaker": ContentRegistry.DATA,
	"utilityCart": ContentRegistry.DATA,
	"floorLamp": ContentRegistry.DATA,
	"ceilingLight": ContentRegistry.DATA,
	"ceilingFan": ContentRegistry.DATA,
	"tableLamp": ContentRegistry.DATA,
	"loungeCouch": ContentRegistry.DATA,
	"loungeCouchWide": ContentRegistry.DATA,
	"privacyCurtain": ContentRegistry.DATA,
	"serverRack": ContentRegistry.DATA,
	"supplyCrates": ContentRegistry.DATA,
	"trashBin": ContentRegistry.DATA,
	"vendingMachine": ContentRegistry.DATA,
	"woodenChair": ContentRegistry.DATA,
	"woodenChairCushion": ContentRegistry.DATA,
	"woodenTable": ContentRegistry.DATA,
	"restaurantPartyTable": ContentRegistry.DATA,
	"woodenDresserSideboard": ContentRegistry.DATA,
	"retroComputerCompact": ContentRegistry.DATA,
	"retroComputerTower": ContentRegistry.DATA,
	"retroComputerDesktop": ContentRegistry.DATA,
	"retroComputerTerminal": ContentRegistry.DATA,

	"diningTable": ContentRegistry.DATA,
	"diningChair": ContentRegistry.DATA,
	"diningChairCushion": ContentRegistry.DATA,
	"diningChandelier": ContentRegistry.DATA,
	"diningSideboard": ContentRegistry.DATA,
	"flowerCenterpiece": ContentRegistry.DATA,
	"framedWallPortrait": ContentRegistry.DATA,
	# Empty residential frames deliberately contain no canvas/image mesh. The
	# wall remains visible through their centre until authored artwork is added.
	"normalPictureFrameEmpty": ContentRegistry.DATA,
	"normalPaintingFrameEmpty": ContentRegistry.DATA,
	"luxuryPictureFrameEmpty": ContentRegistry.DATA,
	"luxuryPaintingFrameEmpty": ContentRegistry.DATA,
	"gothicPictureFrameEmpty": ContentRegistry.DATA,
	"gothicPaintingFrameEmpty": ContentRegistry.DATA,
	"normalRoomDoor": ContentRegistry.DATA,
	"luxuryRoomDoor": ContentRegistry.DATA,
	"gothicRoomDoor": ContentRegistry.DATA,
	"normalDoubleRoomDoor": ContentRegistry.DATA,
	"luxuryDoubleRoomDoor": ContentRegistry.DATA,
	"gothicDoubleRoomDoor": ContentRegistry.DATA,
	"heavyMansionDrapes": ContentRegistry.DATA,
	"mansionAreaRug": ContentRegistry.DATA,
	"corridorCarpet": ContentRegistry.DATA,
	"hotelCarpet": ContentRegistry.DATA,
	"apartmentCarpet": ContentRegistry.DATA,
	"beachMat": ContentRegistry.DATA,
	"mansionBookshelf": ContentRegistry.DATA,
	"mansionFireplace": ContentRegistry.DATA,
	"magazineRack": ContentRegistry.DATA,
	"tableCandelabra": ContentRegistry.DATA,
	"wallSconce": ContentRegistry.DATA,
	"bathroomStall": ContentRegistry.DATA,
	"bathroomSink": ContentRegistry.DATA,
	"bathroomMirror": ContentRegistry.DATA,
	"bathroomVanity": ContentRegistry.DATA,
	"publicRestroomToilet": ContentRegistry.DATA,
	"publicMensUrinal": ContentRegistry.DATA,
	"publicSinkBank": ContentRegistry.DATA,
	"publicHandDryer": ContentRegistry.DATA,
	"publicSoapDispenser": ContentRegistry.DATA,
	"publicPaperTowelDispenser": ContentRegistry.DATA,
	"publicBabyChangeStation": ContentRegistry.DATA,
	"publicSanitaryBin": ContentRegistry.DATA,
	"publicMensRoomSign": ContentRegistry.DATA,
	"publicWomensRoomSign": ContentRegistry.DATA,
	"publicMensShowerStall": ContentRegistry.DATA,
	"publicWomensShowerStall": ContentRegistry.DATA,
	"publicShowerBench": ContentRegistry.DATA,
	"houseBathtub": ContentRegistry.DATA,
	"houseToilet": ContentRegistry.DATA,
	"houseShowerEnclosure": ContentRegistry.DATA,
	"houseMedicineCabinet": ContentRegistry.DATA,
	"houseTowelRack": ContentRegistry.DATA,
	"houseBathMat": ContentRegistry.DATA,
	"houseBathroomShelf": ContentRegistry.DATA,
	"grandStaircase": ContentRegistry.DATA,
	"grandFoyerStaircase": ContentRegistry.DATA,
	"singleBed": ContentRegistry.DATA,
	"doubleBed": ContentRegistry.DATA,
	"bunkBed": ContentRegistry.DATA,
	"bedroomNightstand": ContentRegistry.DATA,
	"bedroomWardrobe": ContentRegistry.DATA,
	"bedroomDresser": ContentRegistry.DATA,
	"bedroomVanity": ContentRegistry.DATA,
	"vanityStool": ContentRegistry.DATA,
	"bedsideLamp": ContentRegistry.DATA,
	"toyChest": ContentRegistry.DATA,
	"laundryHamper": ContentRegistry.DATA,
	"bedroomRug": ContentRegistry.DATA,
	"bedroomWallClock": ContentRegistry.DATA,
	"bedroomBench": ContentRegistry.DATA,

	"gothicDoubleBed": ContentRegistry.DATA,
	"gothicNightstand": ContentRegistry.DATA,
	"gothicWardrobe": ContentRegistry.DATA,
	"gothicDresser": ContentRegistry.DATA,
	"gothicVanity": ContentRegistry.DATA,
	"gothicVanityStool": ContentRegistry.DATA,
	"gothicBedroomBench": ContentRegistry.DATA,
	"gothicBedroomRug": ContentRegistry.DATA,
	"gothicBedsideCandelabra": ContentRegistry.DATA,
	"gothicHighbackChair": ContentRegistry.DATA,
	"mansionConsoleTable": ContentRegistry.DATA,
	"mansionGrandfatherClock": ContentRegistry.DATA,
	"mansionCoatRack": ContentRegistry.DATA,
	"mansionTeaCart": ContentRegistry.DATA,
	"mansionRockingChair": ContentRegistry.DATA,
	"mansionRoomDivider": ContentRegistry.DATA,
	"gothicWritingDesk": ContentRegistry.DATA,
	"gothicBookcase": ContentRegistry.DATA,
	"gothicPedestalTable": ContentRegistry.DATA,
	"gothicFloorCandelabra": ContentRegistry.DATA,
	"gothicCoffinChest": ContentRegistry.DATA,
	"normalKitchenCounter": ContentRegistry.DATA,
	"normalKitchenSink": ContentRegistry.DATA,
	"normalKitchenStove": ContentRegistry.DATA,
	"normalKitchenFridge": ContentRegistry.DATA,
	"normalKitchenWallCabinet": ContentRegistry.DATA,
	"normalKitchenIsland": ContentRegistry.DATA,
	"luxuryKitchenCounter": ContentRegistry.DATA,
	"luxuryKitchenSink": ContentRegistry.DATA,
	"luxuryKitchenStove": ContentRegistry.DATA,
	"luxuryKitchenFridge": ContentRegistry.DATA,
	"luxuryKitchenWallCabinet": ContentRegistry.DATA,
	"luxuryKitchenIsland": ContentRegistry.DATA,
	"gothicKitchenCounter": ContentRegistry.DATA,
	"gothicKitchenSink": ContentRegistry.DATA,
	"gothicKitchenStove": ContentRegistry.DATA,
	"gothicKitchenFridge": ContentRegistry.DATA,
	"gothicKitchenWallCabinet": ContentRegistry.DATA,
	"gothicKitchenIsland": ContentRegistry.DATA,
	"normalBookcase": ContentRegistry.DATA,
	"normalCoffeeTable": ContentRegistry.DATA,
	"normalTvConsole": ContentRegistry.DATA,
	"normalEntryBench": ContentRegistry.DATA,
	"mansionDisplayCabinet": ContentRegistry.DATA,
	"mansionChaiseLounge": ContentRegistry.DATA,
	"mansionUprightPiano": ContentRegistry.DATA,
	"mansionBustPedestal": ContentRegistry.DATA,

	"sandCastle": ContentRegistry.DATA,
	"beachUmbrella": ContentRegistry.DATA,
	"tikiBar": ContentRegistry.DATA,
	"beachChair": ContentRegistry.DATA,
	"surfboardRack": ContentRegistry.DATA,
	"palmTree": ContentRegistry.DATA,
	"frozenBeachHut": ContentRegistry.DATA,
	"frozenTidelinePool": ContentRegistry.DATA,

	"carnivalTicketBooth": ContentRegistry.DATA,
	"popcornCart": ContentRegistry.DATA,
	"ringTossStall": ContentRegistry.DATA,
	"strengthTester": ContentRegistry.DATA,
	"circusPedestal": ContentRegistry.DATA,
	# the other playable booths (CarnivalBooths) reuse a stall / pedestal body; their game board is the booth node's (docs/CARNIVAL_BOOTHS.md)
	"shootingGallery": ContentRegistry.DATA,
	"whackAMole": ContentRegistry.DATA,
	"duckPond": ContentRegistry.DATA,
	"carouselCenterpiece": ContentRegistry.DATA,

	"lavaVent": ContentRegistry.DATA,
	"emberBrazier": ContentRegistry.DATA,
	"basaltPillar": ContentRegistry.DATA,
	"basaltRubble": ContentRegistry.DATA,
	"magmaCrystalCluster": ContentRegistry.DATA,
	"infernoAltar": ContentRegistry.DATA,
	"infernoChainLantern": ContentRegistry.DATA,
	"lavaPipeManifold": ContentRegistry.DATA,
	"charredSupplyCrate": ContentRegistry.DATA,
	"prisonCellGate": ContentRegistry.DATA,
	# the sewer under the maze (tools/props/rebuild_hytale_props.py SEWER_BUILDERS)
	"sewerLadder": ContentRegistry.DATA,
	"sewerLadderTop": ContentRegistry.DATA,
	"sewerManhole": ContentRegistry.DATA,
	"sewerFloorGrate": ContentRegistry.DATA,
	"sewerValveWheel": ContentRegistry.DATA,
	"sewerPump": ContentRegistry.DATA,
	"sewerPipeRun": ContentRegistry.DATA,
	"sewerOverflowGrate": ContentRegistry.DATA,
	"sewerLamp": ContentRegistry.DATA,
	"sewerBridge": ContentRegistry.DATA,
	"sewerGrateDeck": ContentRegistry.DATA,
	"prisonBunk": ContentRegistry.DATA,
	"prisonCafeteriaTable": ContentRegistry.DATA,
	"prisonServingCounter": ContentRegistry.DATA,
	"prisonTrayReturn": ContentRegistry.DATA,
	"prisonKitchenRack": ContentRegistry.DATA,
	"dungeonCage": ContentRegistry.DATA,
	"restraintChair": ContentRegistry.DATA,
	## Hospital, research lab and greenhouse region props: authored only as blocky models
	## (tools/props/blocky_props_regions.py), so their catalogue entry is the blocky GLB itself.
	"hospitalBed": ContentRegistry.DATA,
	"hospitalCurtain": ContentRegistry.DATA,
	"ivDripStand": ContentRegistry.DATA,
	"vitalsMonitor": ContentRegistry.DATA,
	"nursesStation": ContentRegistry.DATA,
	"waitingChairs": ContentRegistry.DATA,
	"operatingTable": ContentRegistry.DATA,
	"surgicalLight": ContentRegistry.DATA,
	"instrumentTrolley": ContentRegistry.DATA,
	"morgueCabinet": ContentRegistry.DATA,
	"autopsyTable": ContentRegistry.DATA,
	"pharmacyShelf": ContentRegistry.DATA,
	"xrayMachine": ContentRegistry.DATA,
	"xrayLightbox": ContentRegistry.DATA,
	"medicalSupplyRack": ContentRegistry.DATA,
	"wheelchair": ContentRegistry.DATA,
	"hospitalWardSign": ContentRegistry.DATA,
	"labBench": ContentRegistry.DATA,
	"fumeHood": ContentRegistry.DATA,
	"specimenTank": ContentRegistry.DATA,
	"containmentCell": ContentRegistry.DATA,
	"labCoolingUnit": ContentRegistry.DATA,
	"controlConsole": ContentRegistry.DATA,
	"monitorWall": ContentRegistry.DATA,
	"divePod": ContentRegistry.DATA,
	"divePodFilm": ContentRegistry.DATA,
	"divePodLit": ContentRegistry.DATA,
	"diveHeadsetStand": ContentRegistry.DATA,
	"diveHeadsetShelf": ContentRegistry.DATA,
	"diveConsole": ContentRegistry.DATA,
	"deconShower": ContentRegistry.DATA,
	"coldStorageUnit": ContentRegistry.DATA,
	"labWhiteboard": ContentRegistry.DATA,
	"hazardSign": ContentRegistry.DATA,
	"labGlassPartition": ContentRegistry.DATA,
	"labStool": ContentRegistry.DATA,
	"labMicroscope": ContentRegistry.DATA,
	"gasCylinderRack": ContentRegistry.DATA,
	"biohazardBin": ContentRegistry.DATA,
	"raisedPlanter": ContentRegistry.DATA,
	"pottingBench": ContentRegistry.DATA,
	"pottedPalm": ContentRegistry.DATA,
	"bananaPlant": ContentRegistry.DATA,
	"saguaroCactus": ContentRegistry.DATA,
	"cactusCluster": ContentRegistry.DATA,
	"seedlingRack": ContentRegistry.DATA,
	"irrigationManifold": ContentRegistry.DATA,
	"mistingPost": ContentRegistry.DATA,
	"overgrowthPatch": ContentRegistry.DATA,
	"hangingVines": ContentRegistry.DATA,
	"domeFountain": ContentRegistry.DATA,
	"wateringCart": ContentRegistry.DATA,
	"greenhouseBench": ContentRegistry.DATA,
	"compostBins": ContentRegistry.DATA,
	## Shopping arcade props (tools/props/blocky_props_mall.py), blocky-only like the region props above.
	"shopShelf": ContentRegistry.DATA,
	"shopFridge": ContentRegistry.DATA,
	"checkoutCounter": ContentRegistry.DATA,
	"displayCase": ContentRegistry.DATA,
	"coffeeStation": ContentRegistry.DATA,
	"donutFryer": ContentRegistry.DATA,
	"bakeryRack": ContentRegistry.DATA,
	"dinerStool": ContentRegistry.DATA,
	"dinerBooth": ContentRegistry.DATA,
	"menuBoard": ContentRegistry.DATA,
	"donutSign": ContentRegistry.DATA,
	"washingMachine": ContentRegistry.DATA,
	"dryerStack": ContentRegistry.DATA,
	"flowerStand": ContentRegistry.DATA,
	"barberChair": ContentRegistry.DATA,
	"barberStation": ContentRegistry.DATA,
	"clothesRack": ContentRegistry.DATA,
	"tvWall": ContentRegistry.DATA,
	"cinemaSeats": ContentRegistry.DATA,
	"cinemaScreen": ContentRegistry.DATA,
	"ticketBooth": ContentRegistry.DATA,
	"concessionCounter": ContentRegistry.DATA,
	"foodCourtTable": ContentRegistry.DATA,
	"mallPlanter": ContentRegistry.DATA,
	"mallBench": ContentRegistry.DATA,
	## Music wing (tools/props/blocky_props_music.py): models come from data/props/music.json.
	"micStand": ContentRegistry.DATA,
	"podiumMic": ContentRegistry.DATA,
	"deskMic": ContentRegistry.DATA,
	"drumKit": ContentRegistry.DATA,
	"electricGuitarStand": ContentRegistry.DATA,
	"acousticGuitarStand": ContentRegistry.DATA,
	"bassGuitarStand": ContentRegistry.DATA,
	"keyboardStand": ContentRegistry.DATA,
	"uprightPianoMusic": ContentRegistry.DATA,
	"ampStack": ContentRegistry.DATA,
	"comboAmp": ContentRegistry.DATA,
	"stageMonitor": ContentRegistry.DATA,
	"paSpeakerPole": ContentRegistry.DATA,
	"mixingDesk": ContentRegistry.DATA,
	"studioMonitors": ContentRegistry.DATA,
	"rackGear": ContentRegistry.DATA,
	"musicStand": ContentRegistry.DATA,
	"cableCoil": ContentRegistry.DATA,
	"cableRun": ContentRegistry.DATA,
	"stageLightRig": ContentRegistry.DATA,
	"acousticPanel": ContentRegistry.DATA,
	"guitarWallHanger": ContentRegistry.DATA,
	"instrumentCases": ContentRegistry.DATA,
	"onAirSign": ContentRegistry.DATA,
}

## Highest local point of ceiling-hung models. Their exported origins stay in
## the same floor-based convention as every other prop, so this offset seats
## that authored top exactly against the 3 m corridor ceiling.
const CEILING_MODEL_TOP := {
	"diningChandelier": .90,
	"ceilingLight": .30,
	"ceilingFan": .59,
	"infernoChainLantern": 1.59,
	"surgicalLight": .90,
	"hangingVines": 1.25,
}

## Actual light emission stays runtime-authored so the shipping GLBs remain
## lightweight and the same fixture variants can share performance limits.
## Energy/range are intentionally modest: fixtures illuminate a room without
## replacing the player's flashlight or creating one shadow map per prop.
const LIGHT_PROFILES := {
	"floorLamp": {"color": Color("ffe1a3"), "energy": .52, "range": 4.0, "height": 1.52},
	"tableLamp": {"color": Color("ffd99a"), "energy": .38, "range": 3.0, "height": .54},
	"bedsideLamp": {"color": Color("ffd5a0"), "energy": .32, "range": 2.6, "height": .54},
	"ceilingLight": {"color": Color("dff8ff"), "energy": .62, "range": 4.8, "height": .12},
	"ceilingFan": {"color": Color("fff0c2"), "energy": .54, "range": 4.4, "height": .16},
	"diningChandelier": {"color": Color("ffd58c"), "energy": .66, "range": 5.2, "height": .55},
	"wallSconce": {"color": Color("ffd292"), "energy": .36, "range": 3.2, "height": 1.62},
	# dim amber caged bulkheads, far apart: the sewer stays mostly dark
	"sewerLamp": {"color": Color("ffa24a"), "energy": .42, "range": 5.0, "height": 0.0},
	"surgicalLight": {"color": Color("f4fbff"), "energy": .85, "range": 4.6, "height": .2},
	"specimenTank": {"color": Color("5fe8d8"), "energy": .42, "range": 3.0, "height": 1.2},
	# the one dive pod left on: a faint glow, the rest of the pod room stays dark
	"divePodLit": {"color": Color("8fe6f0"), "energy": .18, "range": 2.2, "height": .6},
	"xrayLightbox": {"color": Color("e8f4ff"), "energy": .26, "range": 2.4, "height": 1.5},
	"donutSign": {"color": Color("ff8fc8"), "energy": .38, "range": 3.0, "height": .7},
	"menuBoard": {"color": Color("ffe0b0"), "energy": .24, "range": 2.4, "height": .45},
}

## Coordinated furniture families share the same room id. Hash that room id,
## rather than each prop index independently, so wood furniture, computers,
## and themed bedroom sets never receive mismatched finishes inside one room.
const _CODE_COORDINATED_SET_TYPES := [
	ContentRegistry.DATA + ":p03",
	ContentRegistry.DATA + ":office",
	ContentRegistry.DATA + ":p06",
	ContentRegistry.DATA + ":p07",
]

## Variant labels are kept beside their ordered paths so validators and future
## UI can reason about a room's actual finish instead of filename substrings.
## Families with the same four/six labels deliberately share ordering: hashing
## one room id therefore gives every member of a given four- or six-variant
## family the same indexed finish even when their individual prop ids differ.
const _CODE_VARIANT_THEMES := {
	"woodenChair": ContentRegistry.DATA,
	"woodenChairCushion": ContentRegistry.DATA,
	"woodenTable": ContentRegistry.DATA,
	"woodenDresserSideboard": ContentRegistry.DATA,
	"retroComputerCompact": ContentRegistry.DATA,
	"retroComputerTower": ContentRegistry.DATA,
	"retroComputerDesktop": ContentRegistry.DATA,
	"retroComputerTerminal": ContentRegistry.DATA,
	"officeDesk": ContentRegistry.DATA,
	"officeChair": ContentRegistry.DATA,
	"officeCrtSecurityConsole": ContentRegistry.DATA,
	"officeCubiclePartition": ContentRegistry.DATA,
	"officePrinter": ContentRegistry.DATA,
	"officeWaterCooler": ContentRegistry.DATA,
	"officePhotocopier": ContentRegistry.DATA,
	"officeShredder": ContentRegistry.DATA,
	"officeFileBoxes": ContentRegistry.DATA,
	"officeCornerWorkstation": ContentRegistry.DATA,
	"singleBed": ContentRegistry.DATA,
	"doubleBed": ContentRegistry.DATA,
	"bedroomNightstand": ContentRegistry.DATA,
	"bedroomWardrobe": ContentRegistry.DATA,
	"bedroomDresser": ContentRegistry.DATA,
	"bedroomVanity": ContentRegistry.DATA,
	"vanityStool": ContentRegistry.DATA,
	"bedsideLamp": ContentRegistry.DATA,
	"toyChest": ContentRegistry.DATA,
	"laundryHamper": ContentRegistry.DATA,
	"bedroomRug": ContentRegistry.DATA,
	"bedroomWallClock": ContentRegistry.DATA,
	"bedroomBench": ContentRegistry.DATA,
}

## The tables above with their res://data/props entries filled in (`"@data:<family>"` splices a family's coordinated ids).
static var MODEL_PATHS: Dictionary = ContentRegistry.resolve(_CODE_MODEL_PATHS, "props", "models")
static var COORDINATED_SET_TYPES: Array = ContentRegistry.splice(_CODE_COORDINATED_SET_TYPES, "coordinated")
static var VARIANT_THEMES: Dictionary = ContentRegistry.resolve(_CODE_VARIANT_THEMES, "props", "themes")


static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


## Packs changed (ContentRegistry.load_packs / unload_packs): recompute the tables read from the registry.
static func rebuild_from_registry() -> void:
	MODEL_PATHS = ContentRegistry.resolve(_CODE_MODEL_PATHS, "props", "models")
	COORDINATED_SET_TYPES = ContentRegistry.splice(_CODE_COORDINATED_SET_TYPES, "coordinated")
	VARIANT_THEMES = ContentRegistry.resolve(_CODE_VARIANT_THEMES, "props", "themes")


static func has_model(type: String) -> bool:
	return MODEL_PATHS.has(type) and not (MODEL_PATHS[type] as Array).is_empty()


## Thin rugs/mats are visual overlays rather than structural floor. Keeping
## their visible plane one centimetre above the GridMap slab prevents depth
## precision from alternating between both surfaces as the camera moves.
const FLOOR_DRESSING_Y := 0.012
const FLOOR_DRESSING_TYPES := [
	"mansionAreaRug", "corridorCarpet", "hotelCarpet",
	"apartmentCarpet", "beachMat", "bedroomRug", "gothicBedroomRug",
	"houseBathMat", "arcadeCarpetCircle", "arcadeCarpetRunner",
	"frozenTidelinePool", "overgrowthPatch", "cableCoil", "cableRun",
]
const EMPTY_FRAME_TYPES := [
	"normalPictureFrameEmpty", "normalPaintingFrameEmpty",
	"luxuryPictureFrameEmpty", "luxuryPaintingFrameEmpty",
	"gothicPictureFrameEmpty", "gothicPaintingFrameEmpty",
]
const ROOM_DOOR_TYPES := [
	"normalRoomDoor", "luxuryRoomDoor", "gothicRoomDoor",
	"normalDoubleRoomDoor", "luxuryDoubleRoomDoor", "gothicDoubleRoomDoor",
]
const WALL_MOUNTED_TYPES := EMPTY_FRAME_TYPES + [
	"bathroomMirror", "framedWallPortrait", "bedroomWallClock",
	"publicHandDryer", "publicSoapDispenser", "publicPaperTowelDispenser",
	"publicBabyChangeStation", "publicMensRoomSign", "publicWomensRoomSign",
	"houseMedicineCabinet", "houseTowelRack", "houseBathroomShelf",
	"xrayLightbox", "hospitalWardSign", "monitorWall", "labWhiteboard", "diveHeadsetShelf",
	"hazardSign", "menuBoard", "donutSign", "cinemaScreen", "acousticPanel", "guitarWallHanger", "onAirSign",
]


## Walkable decks authored with their walking surface at the model origin
## (z = 0 in the builder) and structure hanging below it: spawned at the cell's
## floor height as authored, never seated on their lowest point, so the deck
## top is flush with the floor collider under it (girders reach down into the
## channel trench). Seating the sewer bridge on its bearings raised the deck
## 0.6 m above the walkway and runners walked through it.
const DECK_TYPES := ["sewerBridge", "sewerGrateDeck"]


static func keeps_authored_pivot(type: String) -> bool:
	return DECK_TYPES.has(type)


static func is_floor_dressing(type: String) -> bool:
	return FLOOR_DRESSING_TYPES.has(type)


static func is_empty_frame(type: String) -> bool:
	return EMPTY_FRAME_TYPES.has(type)


static func is_wall_mounted(type: String) -> bool:
	return WALL_MOUNTED_TYPES.has(type)


static func is_room_door(type: String) -> bool:
	return ROOM_DOOR_TYPES.has(type)


static func is_ceiling_mounted(type: String) -> bool:
	return CEILING_MODEL_TOP.has(type)


static func light_profile(type: String) -> Dictionary:
	return (LIGHT_PROFILES.get(type, {}) as Dictionary).duplicate()


## Authored Blender props present their usable/front side along local +Z after
## glTF conversion. Gameplay uses -Z as forward, so the visual root needs a
## half turn to face into the room instead of back into its supporting wall.
static func authored_visual_yaw(gameplay_yaw: float) -> float:
	return gameplay_yaw + PI


## Region finishes (docs/MANSION_LUXURY.md): the mansion gets its own looks of the ordinary furniture types (lacquer,
## marble tops, velvet, gilt), built as "<type>Mansion" model sets with the same footprints. The type names stay the
## same, so sizes, colliders, surfaces, hiding spots and room rules all apply unchanged.
const REGION_FINISHES := {"mansion": "Mansion"}
## Switch for before/after captures (tools/look/mansion_rooms.gd).
static var use_region_finishes := true


static func region_finish(region: String) -> String:
	return String(REGION_FINISHES.get(region, ""))


static func model_path(type: String, instance_id: String,
		room_id: String = "", finish: String = "") -> String:
	var paths: Array = MODEL_PATHS.get(type, [])
	if paths.is_empty():
		return ""
	if not ContentRegistry.pack_of("props", type).is_empty():
		return String(paths[_variant_index(type, instance_id, room_id, paths.size())])
	if USE_BLOCKY_PROPS and use_region_finishes and not finish.is_empty() and BlockyPropModels.MODELS.has(type + finish):
		var finished: Array = BlockyPropModels.MODELS[type + finish]
		return String(finished[_variant_index(type, instance_id, room_id, finished.size())])
	if USE_BLOCKY_PROPS and BlockyPropModels.MODELS.has(type):
		var blocky: Array = BlockyPropModels.MODELS[type]
		return String(blocky[_variant_index(type, instance_id, room_id, blocky.size())])
	return String(paths[_variant_index(type, instance_id, room_id, paths.size())])


static func variant_theme(type: String, instance_id: String,
		room_id: String = "") -> String:
	var labels: Array = VARIANT_THEMES.get(type, [])
	if labels.is_empty():
		return ""
	return String(labels[_variant_index(type, instance_id, room_id, labels.size())])


static func _variant_index(type: String, instance_id: String,
		room_id: String, size: int) -> int:
	var variant_key := room_id if not room_id.is_empty() else instance_id
	if room_id.is_empty() and COORDINATED_SET_TYPES.has(type) \
			and instance_id.contains("-prop-"):
		variant_key = instance_id.get_slice("-prop-", 0)
	return _stable_index(variant_key, size)


static func visual_y(type: String, wall_height: float, mount_y: float = 0.0) -> float:
	if mount_y > 0.0:
		return mount_y
	if is_floor_dressing(type):
		return FLOOR_DRESSING_Y
	if is_wall_mounted(type):
		return wall_height * .42
	if CEILING_MODEL_TOP.has(type):
		return wall_height - float(CEILING_MODEL_TOP[type])
	return 0.0



## Whether the view may batch repeated placements of `type` into one MultiMesh (docs/DATA_DRIVEN_CONTENT.md).
## A prop's data `batchable` wins; otherwise pure dressing is batchable, doors and anything with an interaction are not.
static func is_batchable(type: String) -> bool:
	var def := ContentRegistry.get_def("props", type)
	if def.has("batchable"):
		return bool(def["batchable"])
	return interaction_for(type).is_empty() and not is_room_door(type)


## Turn decorative furniture into a gameplay surface without coupling the
## generator to model filenames. An empty result remains ordinary dressing.
## Hunter-scale rescale (docs/SEATING.md, docs/SCALE_FIT.md): the world is built for a 2.67 m hunter, and these models were
## authored person-sized. ModelSlot.instantiate_prop scales their children by this factor, so the view, the collider
## emitter (PropColliderSizes) and every audit see the same scaled model. Seats, benches, sofas and stools all scale.
const HUNTER_SCALE := {
	# seats (every chair, stool, bench and sofa you can sit on): seat pans end up about 0.45 m x 1.5
	"barberChair": 1.5, "beachChair": 1.5, "dinerStool": 1.5, "diningChair": 1.5, "diningChairCushion": 1.5,
	"gothicBedroomBench": 1.5, "gothicHighbackChair": 1.5, "greenhouseBench": 1.5, "labStool": 1.5, "loungeCouch": 1.5,
	"loungeCouchWide": 1.5, "mallBench": 1.5, "officeChair": 1.5, "publicShowerBench": 1.5, "waitingChairs": 1.5,
	"wheelchair": 1.5, "woodenChair": 1.5, "woodenChairCushion": 1.5, "dinerBooth": 1.5,
	# beds (the gothic canopy stops at 1.48 so it stays under the hunter-scale bed length)
	"bunkBed": 1.5, "doubleBed": 1.5, "gothicDoubleBed": 1.48, "hospitalBed": 1.5, "prisonBunk": 1.5, "singleBed": 1.5,
	# counters, kitchens, sinks
	"bathroomSink": 1.5, "bathroomVanity": 1.5, "bedroomDresser": 1.5, "checkoutCounter": 1.5, "concessionCounter": 1.5,
	"diningSideboard": 1.5, "luxuryKitchenCounter": 1.5, "luxuryKitchenIsland": 1.5, "luxuryKitchenSink": 1.5,
	"luxuryKitchenStove": 1.5, "normalKitchenCounter": 1.5, "normalKitchenIsland": 1.5, "normalKitchenSink": 1.5,
	"normalKitchenStove": 1.5, "prisonServingCounter": 1.5, "receptionDesk": 1.5, "woodenDresserSideboard": 1.5,
	"normalCoffeeTable": 1.5,
	# storage, lamps, bathrooms
	"clothesRack": 1.5, "filingCabinet": 1.5, "gasCylinderRack": 1.5, "surfboardRack": 1.5, "floorLamp": 1.5,
	"gothicFloorCandelabra": 1.5, "deconShower": 1.5, "houseShowerEnclosure": 1.5, "publicMensShowerStall": 1.5,
	"publicWomensShowerStall": 1.5, "houseToilet": 1.5, "publicRestroomToilet": 1.5, "publicMensUrinal": 1.5,
	# music wing: authored at real size like the counters
	"micStand": 1.5, "podiumMic": 1.5, "deskMic": 1.5, "drumKit": 1.5, "electricGuitarStand": 1.5, "acousticGuitarStand": 1.5, "bassGuitarStand": 1.5, "keyboardStand": 1.5, "uprightPianoMusic": 1.5, "ampStack": 1.5, "comboAmp": 1.5, "stageMonitor": 1.5, "paSpeakerPole": 1.5, "mixingDesk": 1.5, "studioMonitors": 1.5, "rackGear": 1.5, "musicStand": 1.5, "cableCoil": 1.5, "cableRun": 1.5, "stageLightRig": 1.5, "acousticPanel": 1.5, "guitarWallHanger": 1.5, "instrumentCases": 1.5, "onAirSign": 1.5,
}
## Multi-seat furniture: this many separate sit points side by side along the prop's width, each its own interactable
## (its own prompt and camera, picked by aim), and each a seat a hunter can take. Anything not listed is one seat.
const SEAT_COUNTS := {"dinerBooth": 4, "waitingChairs": 3, "loungeCouch": 2, "loungeCouchWide": 3, "mallBench": 2, "greenhouseBench": 2,
	"gothicBedroomBench": 2, "publicShowerBench": 2}


static func hunter_scale(type: String) -> float:
	return float(HUNTER_SCALE.get(type, 1.0))


## Props whose seats sit in rows facing each other instead of one row facing out: per row, its centre along the prop's
## local z as a fraction of the depth (gameplay frame: -Z is the prop's front) and the turn from the prop's yaw it faces
## (0 = out of the front, PI = toward the back). The diner booth's two benches face each other across its table.
const SEAT_ROWS := {"dinerBooth": [{"z": .36, "turn": 0.0}, {"z": -.36, "turn": PI}]}


static func seat_count(type: String) -> int:
	return int(SEAT_COUNTS.get(type, 1)) if interaction_for(type) == "sit" else 1


## Sit points of a sit prop `size` big, in its gameplay-local frame: [{"x", "z", "turn", "width", "exit"}]. One row of
## seat_count seats across the width by default, each `width` wide, facing out (turn 0); SEAT_ROWS props split them over
## their rows. "exit" is the local direction you get up toward: out of the front, or out of the nearer open end of a
## booth bench.
static func seat_points(type: String, size: Vector3) -> Array:
	var rows: Array = SEAT_ROWS.get(type, [{"z": 0.0, "turn": 0.0}])
	var per_row := maxi(1, seat_count(type) / rows.size())
	var out := []
	for row_value in rows:
		var row: Dictionary = row_value
		for i in per_row:
			var x := (float(i) + .5) / float(per_row) * size.x - size.x * .5
			var exit := Vector2(0, -1).rotated(-float(row["turn"])) if rows.size() == 1 else Vector2(signf(x) if x != 0.0 else 1.0, 0)
			out.append({"x": x, "z": float(row["z"]) * size.z, "turn": float(row["turn"]), "width": size.x / float(per_row), "exit": exit})
	return out


## Seat centres along a single-row sit prop's local x (kept for callers that only need the row).
static func seat_offsets(type: String, width: float) -> Array:
	var out := []
	for point in seat_points(type, Vector3(width, 1.0, 1.0)):
		out.append(float(point["x"]))
	return out


static func interaction_for(type: String) -> String:
	var lowered := type.to_lower()
	if MusicProps.is_playable(type):
		return "music"   # mics and instruments (MusicProps)
	if type == "carouselCenterpiece":
		return "ride"
	if CarnivalBooths.is_booth(type):
		return "play"
	if type.begins_with("retroComputer"):
		return "use"
	if "mirror" in lowered and type != "standingMirror":   # the working-mirror surface is sized for wall mirrors
		return "mirror"
	if type == "dinerBooth":
		return "sit"    # two benches facing across the table, two seats each (SEAT_ROWS)
	if type in ["labBench", "pottingBench"]:
		return ""   # work benches, not seats
	if type in ["controlConsole", "nursesStation", "diveConsole"]:
		return "use"
	# beds are the types that end in "Bed" (and bunks); "bedroomNightstand", "bedroomWardrobe" and "bedroomBench" are not
	if lowered.ends_with("bed") or "bunk" in lowered:
		return "lay"
	for word in ["chair", "couch", "bench", "stool", "sofa"]:
		if word in lowered:
			return "sit"
	return ""


static func _stable_index(value: String, size: int) -> int:
	var result := 0
	for byte in value.to_utf8_buffer():
		result = (result * 31 + int(byte)) & 0x7fffffff
	return result % maxi(1, size)
