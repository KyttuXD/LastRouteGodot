class_name PropModelCatalog
extends RefCounted

## Presentation-only catalog for authored room dressing. FacilityGenerator
## owns deterministic placement and collision through RoomCatalog; this file
## only selects which imported model represents a mechanical prop type.
## Multiple paths are intentional visual variants and are selected from the
## stable generated prop id, so every peer sees the same couch/cabinet colour.

## Use the Minecraft-style block rebuilds (BlockyPropModels) where they exist.
const USE_BLOCKY_PROPS := true
## Within that, DRAW the detailed original models (assets/props/{maze,mansion,beach,nether,prison,carnival,sewer}) wherever a
## type has one and it passes the screen below (ORIGINAL_DENY). Flip to false for the old all-blocky look. This is
## presentation only: collider_model_path() keeps picking exactly what model_path() picked before the switch, and the
## gameplay colliders, footprints and placement tables (PropColliderBoxes, PropColliderSizes) are read from the blocky models
## whatever this is. See docs/ORIGINAL_PROPS.md.
const PREFER_ORIGINAL_PROPS := true
## An original heavier than this many triangles (its heaviest variant) in a type where it is also heavier than the blocky
## model stays blocky. The median original is ~430 triangles against ~140 blocky, so the cap keeps the Intel HD 6000 budget
## (tests/validate_original_props.gd measures it, docs/ORIGINAL_PROPS.md has the numbers).
const MAX_ORIGINAL_TRIS := 520
## The switch at run time (starts at PREFER_ORIGINAL_PROPS). Tests and the benchmark flip it to compare the two looks in one
## process; nothing in the game does.
static var prefer_original_props: bool = PREFER_ORIGINAL_PROPS

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
	"sewerOutflowPipe": ContentRegistry.DATA,
	"sewerSluiceGate": ContentRegistry.DATA,
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
	## Mansion finish of bedroomWardrobe (BlockyPropModels "bedroomWardrobeMansion"). Same hide_capacity as the
	## other wardrobes; the GLBs already exist, this row only publishes them as prop data.
	"bedroomWardrobeMansion": ContentRegistry.DATA,
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
## Read LIGHT_PROFILES, not this: the values are each prop's `light` in res://data/props (ContentRegistry.PROP_FIELDS),
## so a pack can retune a built-in lamp or ship a new one that glows. Order is the old constant's.
const _CODE_LIGHT_PROFILES := {
	"floorLamp": ContentRegistry.DATA,
	"tableLamp": ContentRegistry.DATA,
	"bedsideLamp": ContentRegistry.DATA,
	"ceilingLight": ContentRegistry.DATA,
	"ceilingFan": ContentRegistry.DATA,
	"diningChandelier": ContentRegistry.DATA,
	"wallSconce": ContentRegistry.DATA,
	# dim amber caged bulkheads, far apart: the sewer stays mostly dark
	"sewerLamp": ContentRegistry.DATA,
	"surgicalLight": ContentRegistry.DATA,
	"specimenTank": ContentRegistry.DATA,
	# the one dive pod left on: a faint glow, the rest of the pod room stays dark
	"divePodLit": ContentRegistry.DATA,
	"xrayLightbox": ContentRegistry.DATA,
	"donutSign": ContentRegistry.DATA,
	"menuBoard": ContentRegistry.DATA,
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
static var COORDINATED_SET_TYPES: Array = _coordinated_set_types()
static var VARIANT_THEMES: Dictionary = ContentRegistry.resolve(_CODE_VARIANT_THEMES, "props", "themes")
## type -> {type, color, energy, range, offset, height, shadows}; props without a `light` are absent (no light).
static var LIGHT_PROFILES: Dictionary = ContentRegistry.resolve(_CODE_LIGHT_PROFILES, "props", "light")


static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


## Packs changed (ContentRegistry.load_packs / unload_packs): recompute the tables read from the registry.
static func rebuild_from_registry() -> void:
	MODEL_PATHS = ContentRegistry.resolve(_CODE_MODEL_PATHS, "props", "models")
	COORDINATED_SET_TYPES = _coordinated_set_types()
	VARIANT_THEMES = ContentRegistry.resolve(_CODE_VARIANT_THEMES, "props", "themes")
	REGION_FINISHES = _build_region_finishes()
	LIGHT_PROFILES = ContentRegistry.resolve(_CODE_LIGHT_PROFILES, "props", "light")


## The built-in coordinated families (spliced, old order), then props packs add in families of their own that set
## `coordinated` (a pack's prop in a built-in family is already in its family's splice), sorted: a pack's own furniture
## set takes one finish per room like the built-in ones. With no pack loaded this is exactly the old list.
static func _coordinated_set_types() -> Array:
	var out := ContentRegistry.splice(_CODE_COORDINATED_SET_TYPES, "coordinated").duplicate()
	for id in ContentRegistry.added_ids("props"):
		if not out.has(id) and bool(ContentRegistry.get_def("props", id).get("coordinated", false)):
			out.append(id)
	out.make_read_only()
	return out


## How many runners hide in this prop at once (HideOccupancy, docs/HIDING_PROPS.md): its lr.prop/1 `hide_capacity`, else 1.
static func hide_capacity(type: String) -> int:
	return HideOccupancy.clamp_capacity(int(ContentRegistry.get_def("props", type).get("hide_capacity", 1)))


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


## Pieces authored at their own height, not seated on their lowest point: the sewer's outflow main hangs at the crawl
## clearance on its vault straps (seating it on its underside dropped it to the floor), and the sluice gate's leaf lies
## flush with the walkway with its ribs below it.
const AUTHORED_HEIGHT_TYPES := ["sewerOutflowPipe", "sewerSluiceGate"]


static func keeps_authored_pivot(type: String) -> bool:
	return DECK_TYPES.has(type) or AUTHORED_HEIGHT_TYPES.has(type)


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


## The fixture light a prop type gives off (its lr.prop/1 `light`), {} for none. A copy: callers may change it.
static func light_profile(type: String) -> Dictionary:
	return (LIGHT_PROFILES.get(type, {}) as Dictionary).duplicate()


## Authored Blender props present their usable/front side along local +Z after
## glTF conversion. Gameplay uses -Z as forward, so the visual root needs a
## half turn to face into the room instead of back into its supporting wall.
static func authored_visual_yaw(gameplay_yaw: float) -> float:
	return gameplay_yaw + PI


## Region finishes: the mansion gets its own looks of the ordinary furniture types (lacquer,
## marble tops, velvet, gilt), built as "<type>Mansion" model sets with the same footprints. The type names stay the
## same, so sizes, colliders, surfaces, hiding spots and room rules all apply unchanged.
## Data: each district theme's `finish` (data/themes/regions/<id>.json, game/look/theme_data.gd), so a pack can give a
## district another existing finish or take it away.
static var REGION_FINISHES: Dictionary = _build_region_finishes()
## Switch for before/after captures (dev/look/mansion_rooms.gd).
static var use_region_finishes := true


static func _build_region_finishes() -> Dictionary:
	var out := {}
	for id in ContentRegistry.ids("region_themes"):
		var finish := String(RefLook.theme_field("region_themes", id, "finish", ""))
		if not finish.is_empty():
			out[id] = finish
	out.make_read_only()
	return out


static func region_finish(region: String) -> String:
	return String(REGION_FINISHES.get(region, ""))


## Types that keep their blocky model although an original exists, and why (one of ORIGINAL_DENY_REASONS).
## tests/validate_original_props.gd keeps every row honest against the measured fit and triangle counts
## (tools/props/original_fit_report.tscn prints them). Types with no original at all (the 115 blocky-only ones, the
## "<type>Mansion" finish sets) are not listed: there is nothing to prefer.
const ORIGINAL_DENY_REASONS := {
	"hiding": "StreamedRouteGenerator.HIDING_PROP_STYLES: the hiding-spot validator measures the blocky model (under-bed clearance, wardrobe interior)",
	"collider_variants": "PropColliderSizes.VARIANT_BOXES is indexed by the blocky variant and the 3D view looks the index up from the drawn path",
	"seats": "multi-seat layout and sit points are fitted to the blocky model's width",
	"door_frames": "room doors: header walls (DoorwayFrames.header_y), the widened double doors and the hunters' doorway clearance are measured on the blocky frames (ceiling_gaps, door_clearance)",
	"interaction": "booth, ride and computer anchors, cameras and screens are tuned to the blocky model",
	"facing": "front/back of the original could not be confirmed from its mesh; needs a windowed look before it is switched",
	"fit": "the original's footprint (solid: against the gameplay collider) or height is outside the tolerance in docs/ORIGINAL_PROPS.md",
	"heavy": "more than MAX_ORIGINAL_TRIS triangles and heavier than the blocky model",
}
const ORIGINAL_DENY := {
	# hiding (5)
	"bedroomWardrobe": "hiding",
	"doubleBed": "hiding",
	"gothicDoubleBed": "hiding",
	"gothicWardrobe": "hiding",
	"singleBed": "hiding",
	# collider_variants (3)
	"diningChair": "collider_variants",
	"diningChairCushion": "collider_variants",
	"officeChair": "collider_variants",
	# seats (4)
	"gothicBedroomBench": "seats",
	"loungeCouch": "seats",
	"loungeCouchWide": "seats",
	"publicShowerBench": "seats",
	# door_frames (6)
	"gothicDoubleRoomDoor": "door_frames",
	"gothicRoomDoor": "door_frames",
	"luxuryDoubleRoomDoor": "door_frames",
	"luxuryRoomDoor": "door_frames",
	"normalDoubleRoomDoor": "door_frames",
	"normalRoomDoor": "door_frames",
	# interaction (8)
	"carouselCenterpiece": "interaction",
	"prizeClawMachine": "interaction",
	"retroComputerCompact": "interaction",
	"retroComputerDesktop": "interaction",
	"retroComputerTerminal": "interaction",
	"retroComputerTower": "interaction",
	"ringTossStall": "interaction",
	"strengthTester": "interaction",
	# facing (10)
	"bedroomVanity": "facing",
	"gothicVanity": "facing",
	"mansionUprightPiano": "facing",
	"officeCornerWorkstation": "facing",
	"officeCrtSecurityConsole": "facing",
	"prizeCounter": "facing",
	"publicBabyChangeStation": "facing",
	"snackKiosk": "facing",
	"stageSpeaker": "facing",
	"tikiBar": "facing",
	# fit (10)
	"beachChair": "fit",
	"beachUmbrella": "fit",
	"bunkBed": "fit",
	"floorLamp": "fit",
	"giantTree": "fit",
	"gothicHighbackChair": "fit",
	"mansionRockingChair": "fit",
	"normalEntryBench": "fit",
	"officeFileBoxes": "fit",
	"prisonBunk": "fit",
	# heavy (40)
	"apartmentCarpet": "heavy",
	"backstageRepairStand": "heavy",
	"bedroomDresser": "heavy",
	"carnivalCarousel": "heavy",
	"diningChandelier": "heavy",
	"diningSideboard": "heavy",
	"dungeonCage": "heavy",
	"flowerCenterpiece": "heavy",
	"frozenBeachHut": "heavy",
	"frozenTidelinePool": "heavy",
	"gothicBookcase": "heavy",
	"gothicDresser": "heavy",
	"gothicFloorCandelabra": "heavy",
	"gothicKitchenSink": "heavy",
	"gothicKitchenStove": "heavy",
	"gothicWritingDesk": "heavy",
	"infernoChainLantern": "heavy",
	"luxuryKitchenSink": "heavy",
	"luxuryPaintingFrameEmpty": "heavy",
	"luxuryPictureFrameEmpty": "heavy",
	"maintenanceCleaningCart": "heavy",
	"mansionBookshelf": "heavy",
	"mansionFireplace": "heavy",
	"mansionTeaCart": "heavy",
	"normalBookcase": "heavy",
	"normalKitchenSink": "heavy",
	"palmTree": "heavy",
	"prisonCellGate": "heavy",
	"prisonKitchenRack": "heavy",
	"privacyCurtain": "heavy",
	"publicMensShowerStall": "heavy",
	"publicSinkBank": "heavy",
	"publicWomensShowerStall": "heavy",
	"restaurantPartyTable": "heavy",
	"sandCastle": "heavy",
	"serverRack": "heavy",
	"supplyCrates": "heavy",
	"surfboardRack": "heavy",
	"utilityCart": "heavy",
	"woodenDresserSideboard": "heavy",
}

## Footprint tolerance of an original against what gameplay uses (solid: the collider box; decor: the blocky model), per side
## in metres at hunter scale. Enforced by tests/validate_original_props.gd for every type that draws the original.
const ORIGINAL_FIT_SOLID := 0.12
const ORIGINAL_FIT_DECOR := 0.20


## The original (non-blocky) models of , in variant order; empty when the type has none (blocky-only and pack types).
static func original_paths(type: String) -> Array:
	var out := []
	for path in MODEL_PATHS.get(type, []):
		if String(path).begins_with("res://assets/props/blocky/") or String(path).begins_with("user://"):
			return []
		out.append(path)
	return out


## Whether  draws its original model: a preference is on, a blocky twin exists (else the original is all there is),
## the type passed the screen, it is not a pack prop, and (in a region with a finish) it is neither one that has a finished
## set (blocky-only: "<type>Mansion") nor one of the coordinated furniture families: the room keeps one palette.
static func prefers_original(type: String, finish: String = "") -> bool:
	if not prefer_original_props or not USE_BLOCKY_PROPS or ORIGINAL_DENY.has(type):
		return false
	if not BlockyPropModels.MODELS.has(type) or not ContentRegistry.pack_of("props", type).is_empty():
		return false
	if use_region_finishes and not finish.is_empty() 			and (BlockyPropModels.MODELS.has(type + finish) or COORDINATED_SET_TYPES.has(type)):
		return false
	return not original_paths(type).is_empty()


## What the player sees. Deterministic from (type, instance id, room id, finish) like it always was.
static func model_path(type: String, instance_id: String,
		room_id: String = "", finish: String = "") -> String:
	return _model_path(type, instance_id, room_id, finish, prefer_original_props)


## The model gameplay is derived from: exactly what model_path() returned before PREFER_ORIGINAL_PROPS existed. Colliders,
## footprints and variant boxes (PropColliderBoxes.variant_of) read this, so they are identical with the switch on or off.
static func collider_model_path(type: String, instance_id: String,
		room_id: String = "", finish: String = "") -> String:
	return _model_path(type, instance_id, room_id, finish, false)


static func _model_path(type: String, instance_id: String, room_id: String, finish: String, prefer_original: bool) -> String:
	var paths: Array = MODEL_PATHS.get(type, [])
	if paths.is_empty():
		return ""
	if not ContentRegistry.pack_of("props", type).is_empty():
		return String(paths[_variant_index(type, instance_id, room_id, paths.size())])
	if USE_BLOCKY_PROPS and use_region_finishes and not finish.is_empty() and BlockyPropModels.MODELS.has(type + finish):
		var finished: Array = BlockyPropModels.MODELS[type + finish]
		return String(finished[_variant_index(type, instance_id, room_id, finished.size())])
	if USE_BLOCKY_PROPS and BlockyPropModels.MODELS.has(type):
		if prefer_original and prefers_original(type, finish):
			# the originals of a coordinated family are the same length in the same order (VARIANT_THEMES), so one room id
			# picks one finish for the whole family
			return String(paths[_variant_index(type, instance_id, room_id, paths.size())])
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
## Hunter-scale rescale (docs/SCALE_FIT.md): the world is built for a 2.67 m hunter, and these models were
## authored person-sized. ModelSlot.instantiate_prop scales their children by this factor, so the view, the collider
## emitter (PropColliderSizes) and every audit see the same scaled model. Seats, benches, sofas and stools all scale.
const HUNTER_SCALE := {
	# every person-sized prop people use (data/scale/prop_size_ranges.json): seats, beds, tables,
	# counters, storage, machines, carts, bathrooms and their mansion-finish copies; a few take less than 1.5 to land in range.
	# The "...Mansion" finish copies spawn under their base type (model_path picks the model, the hint stays the base
	# type), so they already take the base's scale; their own entries keep the catalog audits (scale_fit) consistent.
	# Not lockers: you hide inside one and look out of its slats at the runner's eye height (data/scale/prop_size_ranges.json "keep_person_size").
	"arcadeCabinet": 1.5, "arcadeCabinetCyanMagenta": 1.5, "arcadeTokenChanger": 1.5, "autopsyTable": 1.5,
	"backstageRepairStand": 1.25, "bakeryRack": 1.5, "barberChair": 1.5, "bathroomSink": 1.5, "bathroomStall": 1.5,
	"bathroomVanity": 1.5, "bathroomVanityMansion": 1.5, "beachChair": 1.5, "bedroomBench": 1.5,
	"bedroomBenchMansion": 1.5, "bedroomDresser": 1.5, "bedroomDresserMansion": 1.5, "bedroomNightstand": 1.5,
	"bedroomNightstandMansion": 1.5, "bedroomVanity": 1.5, "bedroomVanityMansion": 1.5, "bedroomWardrobe": 1.5,
	"bedroomWardrobeMansion": 1.5, "breakerCabinet": 1.5, "bunkBed": 1.5, "checkoutCounter": 1.5, "cinemaSeats": 1.5,
	"circusPedestal": 1.5, "clothesRack": 1.5, "coldStorageUnit": 1.5, "concessionCounter": 1.5, "deconShower": 1.5,
	"dinerBooth": 1.5, "dinerStool": 1.5, "diningChair": 1.5, "diningChairCushion": 1.5,
	"diningChairCushionMansion": 1.5, "diningChairMansion": 1.5, "diningSideboard": 1.5, "diningSideboardMansion": 1.5,
	"diningTable": 1.5, "diningTableMansion": 1.5, "diveHeadsetShelf": 1.5, "donutFryer": 1.25, "doubleBed": 1.5,
	"doubleBedMansion": 1.5, "dryerStack": 1.5, "duckPond": 1.5, "filingCabinet": 1.5, "floorLamp": 1.5,
	"floorLampMansion": 1.5, "foodCourtTable": 1.5, "fumeHood": 1.2, "gardenPlanterBench": 1.5, "gasCylinderRack": 1.5,
	"gothicBedroomBench": 1.5, "gothicDoubleBed": 1.48, "gothicDresser": 1.5, "gothicFloorCandelabra": 1.5,
	"gothicHighbackChair": 1.5, "gothicKitchenCounter": 1.5, "gothicKitchenFridge": 1.5, "gothicKitchenIsland": 1.5,
	"gothicKitchenSink": 1.5, "gothicKitchenStove": 1.5, "gothicPedestalTable": 1.5, "gothicPedestalTableMansion": 1.5,
	"gothicVanityStool": 1.5, "gothicWritingDesk": 1.5, "greenhouseBench": 1.5, "hospitalBed": 1.5, "houseBathtub": 1.4,
	"houseShowerEnclosure": 1.5, "houseToilet": 1.5, "instrumentTrolley": 1.5, "ivDripStand": 1.5, "ivStand": 1.5,
	"labCoolingUnit": 1.5, "labStool": 1.5, "lavaPipeManifold": 1.5, "loungeCouch": 1.5,
	"loungeCouchMansion": 1.5, "loungeCouchWide": 1.5, "loungeCouchWideMansion": 1.5, "luxuryKitchenCounter": 1.5,
	"luxuryKitchenFridge": 1.5, "luxuryKitchenIsland": 1.5, "luxuryKitchenSink": 1.5, "luxuryKitchenStove": 1.5,
	"maintenanceToolCabinet": 1.5, "mallBench": 1.5, "mansionBookshelf": 1.5, "mansionBookshelfMansion": 1.5,
	"mansionChaiseLounge": 1.5, "mansionChaiseLoungeMansion": 1.5, "mansionCoatRack": 1.5, "mansionConsoleTable": 1.5,
	"mansionConsoleTableMansion": 1.5, "mansionDisplayCabinet": 1.25, "mansionDisplayCabinetMansion": 1.25,
	"mansionGrandfatherClock": 1.5, "mansionRockingChair": 1.5, "mansionTeaCart": 1.5, "mansionTeaCartMansion": 1.5,
	"medicalCart": 1.5, "medicalSupplyRack": 1.5, "morgueCabinet": 1.5, "normalBookcase": 1.5,
	"normalBookcaseMansion": 1.5, "normalCoffeeTable": 1.5, "normalCoffeeTableMansion": 1.5, "normalEntryBench": 1.5,
	"normalKitchenCounter": 1.5, "normalKitchenFridge": 1.5, "normalKitchenIsland": 1.5, "normalKitchenSink": 1.5,
	"normalKitchenStove": 1.5, "officeChair": 1.5, "officeCornerWorkstation": 1.5, "officeDesk": 1.5,
	"officePhotocopier": 1.5, "operatingTable": 1.5, "pharmacyShelf": 1.5, "prisonBunk": 1.5,
	"prisonCafeteriaTable": 1.5, "prisonKitchenRack": 1.5, "prisonServingCounter": 1.5, "prizeClawMachine": 1.5,
	"publicMensShowerStall": 1.5, "publicMensUrinal": 1.5, "publicRestroomToilet": 1.5, "publicShowerBench": 1.5,
	"publicWomensShowerStall": 1.5, "readingTable": 1.5, "receptionDesk": 1.5, "seedlingRack": 1.5, "serverRack": 1.5,
	"shopFridge": 1.5, "shopShelf": 1.5, "singleBed": 1.5, "singleBedMansion": 1.5, "storageShelving": 1.5,
	"surfboardRack": 1.5, "utilityCart": 1.25, "vanityStool": 1.5, "vanityStoolMansion": 1.5, "vendingMachine": 1.5,
	"vitalsMonitor": 1.5, "waitingChairs": 1.5, "washingMachine": 1.5, "wateringCart": 1.5, "wheelchair": 1.5,
	"woodenChair": 1.5, "woodenChairCushion": 1.5, "woodenChairCushionMansion": 1.5, "woodenChairMansion": 1.5,
	"woodenDresserSideboard": 1.5, "woodenDresserSideboardMansion": 1.5, "woodenTable": 1.5, "woodenTableMansion": 1.5,
	# music wing: authored at real size like the counters
	"micStand": 1.5, "podiumMic": 1.5, "deskMic": 1.5, "drumKit": 1.5, "electricGuitarStand": 1.5, "acousticGuitarStand": 1.5, "bassGuitarStand": 1.5, "keyboardStand": 1.5, "uprightPianoMusic": 1.5, "ampStack": 1.5, "comboAmp": 1.5, "stageMonitor": 1.5, "paSpeakerPole": 1.5, "mixingDesk": 1.5, "studioMonitors": 1.5, "rackGear": 1.5, "musicStand": 1.5, "cableCoil": 1.5, "cableRun": 1.5, "stageLightRig": 1.5, "acousticPanel": 1.5, "guitarWallHanger": 1.5, "instrumentCases": 1.5, "onAirSign": 1.5
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
