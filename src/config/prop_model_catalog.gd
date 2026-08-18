class_name PropModelCatalog
extends RefCounted

## Presentation-only catalog for authored room dressing. FacilityGenerator
## owns deterministic placement and collision through RoomCatalog; this file
## only selects which imported model represents a mechanical prop type.
## Multiple paths are intentional visual variants and are selected from the
## stable generated prop id, so every peer sees the same couch/cabinet colour.

const MODEL_PATHS := {
	"arcadeCabinet": [
		"res://art/props-3d/props/maze/arcade_cabinet_default.glb",
		"res://art/props-3d/props/maze/arcade_cabinet_amber.glb",
		"res://art/props-3d/props/maze/arcade_cabinet_burgundy.glb",
		"res://art/props-3d/props/maze/arcade_cabinet_teal.glb",
		"res://art/props-3d/props/maze/arcade_cabinet_ultraviolet.glb",
	],
	"arcadeCabinetCyanMagenta": [
		"res://art/props-3d/props/maze/arcade_cabinet_cyan_magenta.glb",
	],
	"filingCabinet": ["res://art/props-3d/props/maze/filing_cabinet.glb"],
	"floorLamp": ["res://art/props-3d/props/maze/floor_lamp.glb"],
	"loungeCouch": [
		"res://art/props-3d/props/maze/lounge_couch_red.glb",
		"res://art/props-3d/props/mansion/lounge_couch_black.glb",
		"res://art/props-3d/props/mansion/lounge_couch_brown.glb",
		"res://art/props-3d/props/mansion/lounge_couch_ivory.glb",
		"res://art/props-3d/props/mansion/lounge_couch_navy.glb",
		"res://art/props-3d/props/mansion/lounge_couch_olive.glb",
		"res://art/props-3d/props/mansion/lounge_couch_violet.glb",
	],
	"loungeCouchWide": [
		"res://art/props-3d/props/mansion/lounge_couch_red_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_black_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_brown_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_ivory_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_navy_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_olive_wide.glb",
		"res://art/props-3d/props/mansion/lounge_couch_violet_wide.glb",
	],
	"privacyCurtain": ["res://art/props-3d/props/maze/privacy_curtain.glb"],
	"serverRack": ["res://art/props-3d/props/maze/server_rack.glb"],
	"supplyCrates": ["res://art/props-3d/props/maze/supply_crates.glb"],
	"trashBin": ["res://art/props-3d/props/maze/trash_bin.glb"],
	"vendingMachine": ["res://art/props-3d/props/maze/vending_machine.glb"],
	"woodenChair": ["res://art/props-3d/props/maze/wooden_chair_oak.glb"],
	"woodenChairCushion": ["res://art/props-3d/props/maze/wooden_chair_cushion.glb"],
	"woodenTable": ["res://art/props-3d/props/maze/wooden_table.glb"],
	"woodenDresserSideboard": [
		"res://art/props-3d/props/maze/wooden_dresser_sideboard.glb",
	],

	"diningTable": ["res://art/props-3d/props/mansion/grand_dining_table.glb"],
	"diningChair": [
		"res://art/props-3d/props/mansion/dining_chair_burgundy.glb",
		"res://art/props-3d/props/mansion/dining_chair_ivory.glb",
	],
	"diningChairCushion": [
		"res://art/props-3d/props/mansion/dining_chair_cushion_burgundy.glb",
	],
	"diningChandelier": [
		"res://art/props-3d/props/mansion/dining_chandelier.glb",
	],
	"diningSideboard": ["res://art/props-3d/props/mansion/ornate_sideboard.glb"],
	"flowerCenterpiece": [
		"res://art/props-3d/props/mansion/flower_centerpiece.glb",
	],
	"framedWallPortrait": [
		"res://art/props-3d/props/mansion/framed_wall_portrait.glb",
	],
	"heavyMansionDrapes": [
		"res://art/props-3d/props/mansion/heavy_mansion_drapes.glb",
	],
	"mansionAreaRug": ["res://art/props-3d/props/mansion/mansion_area_rug.glb"],
	"mansionBookshelf": [
		"res://art/props-3d/props/mansion/mansion_bookshelf.glb",
	],
	"mansionFireplace": [
		"res://art/props-3d/props/mansion/mansion_fireplace.glb",
	],
	"magazineRack": ["res://art/props-3d/props/mansion/magazine_rack.glb"],
	"tableCandelabra": [
		"res://art/props-3d/props/mansion/table_candelabra.glb",
	],
	"wallSconce": ["res://art/props-3d/props/mansion/wall_sconce.glb"],
	"bathroomStall": ["res://art/props-3d/props/mansion/bathroom_stall.glb"],
	"bathroomSink": ["res://art/props-3d/props/mansion/bathroom_sink.glb"],
	"bathroomMirror": ["res://art/props-3d/props/mansion/bathroom_mirror.glb"],
	"bathroomVanity": ["res://art/props-3d/props/mansion/bathroom_vanity.glb"],
	"publicRestroomToilet": ["res://art/props-3d/props/mansion/public_restroom_toilet.glb"],
	"publicMensUrinal": ["res://art/props-3d/props/mansion/public_mens_urinal.glb"],
	"publicSinkBank": ["res://art/props-3d/props/mansion/public_sink_bank.glb"],
	"publicHandDryer": ["res://art/props-3d/props/mansion/public_hand_dryer.glb"],
	"publicSoapDispenser": ["res://art/props-3d/props/mansion/public_soap_dispenser.glb"],
	"publicPaperTowelDispenser": ["res://art/props-3d/props/mansion/public_paper_towel_dispenser.glb"],
	"publicBabyChangeStation": ["res://art/props-3d/props/mansion/public_baby_change_station.glb"],
	"publicSanitaryBin": ["res://art/props-3d/props/mansion/public_sanitary_bin.glb"],
	"publicMensRoomSign": ["res://art/props-3d/props/mansion/public_mens_room_sign.glb"],
	"publicWomensRoomSign": ["res://art/props-3d/props/mansion/public_womens_room_sign.glb"],
	"publicMensShowerStall": ["res://art/props-3d/props/mansion/public_mens_shower_stall.glb"],
	"publicWomensShowerStall": ["res://art/props-3d/props/mansion/public_womens_shower_stall.glb"],
	"publicShowerBench": ["res://art/props-3d/props/mansion/public_shower_bench.glb"],
	"houseBathtub": ["res://art/props-3d/props/mansion/house_bathtub.glb"],
	"houseToilet": ["res://art/props-3d/props/mansion/house_toilet.glb"],
	"houseShowerEnclosure": ["res://art/props-3d/props/mansion/house_shower_enclosure.glb"],
	"houseMedicineCabinet": ["res://art/props-3d/props/mansion/house_medicine_cabinet.glb"],
	"houseTowelRack": ["res://art/props-3d/props/mansion/house_towel_rack.glb"],
	"houseBathMat": ["res://art/props-3d/props/mansion/house_bath_mat.glb"],
	"houseBathroomShelf": ["res://art/props-3d/props/mansion/house_bathroom_shelf.glb"],
	"grandStaircase": ["res://art/props-3d/props/mansion/grand_staircase.glb"],
	"grandFoyerStaircase": ["res://art/props-3d/props/mansion/grand_foyer_staircase.glb"],
	"singleBed": [
		"res://art/props-3d/props/mansion/single_bed_burgundy.glb",
		"res://art/props-3d/props/mansion/single_bed_navy.glb",
		"res://art/props-3d/props/mansion/single_bed_violet.glb",
		"res://art/props-3d/props/mansion/single_bed_olive.glb",
		"res://art/props-3d/props/mansion/single_bed_ivory.glb",
		"res://art/props-3d/props/mansion/single_bed_charcoal.glb",
	],
	"doubleBed": [
		"res://art/props-3d/props/mansion/double_bed_burgundy.glb",
		"res://art/props-3d/props/mansion/double_bed_navy.glb",
		"res://art/props-3d/props/mansion/double_bed_violet.glb",
		"res://art/props-3d/props/mansion/double_bed_olive.glb",
		"res://art/props-3d/props/mansion/double_bed_ivory.glb",
		"res://art/props-3d/props/mansion/double_bed_charcoal.glb",
	],
	"bedroomNightstand": [
		"res://art/props-3d/props/mansion/bedroom_nightstand.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_nightstand_charcoal.glb",
	],
	"bedroomWardrobe": [
		"res://art/props-3d/props/mansion/bedroom_wardrobe.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_wardrobe_charcoal.glb",
	],
	"bedroomDresser": [
		"res://art/props-3d/props/mansion/bedroom_dresser.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_dresser_charcoal.glb",
	],
	"bedroomVanity": [
		"res://art/props-3d/props/mansion/bedroom_vanity.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_vanity_charcoal.glb",
	],
	"vanityStool": [
		"res://art/props-3d/props/mansion/vanity_stool.glb",
		"res://art/props-3d/props/mansion/vanity_stool_navy.glb",
		"res://art/props-3d/props/mansion/vanity_stool_violet.glb",
		"res://art/props-3d/props/mansion/vanity_stool_olive.glb",
		"res://art/props-3d/props/mansion/vanity_stool_ivory.glb",
		"res://art/props-3d/props/mansion/vanity_stool_charcoal.glb",
	],
	"bedsideLamp": [
		"res://art/props-3d/props/mansion/bedside_lamp.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_navy.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_violet.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_olive.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_ivory.glb",
		"res://art/props-3d/props/mansion/bedside_lamp_charcoal.glb",
	],
	"toyChest": [
		"res://art/props-3d/props/mansion/toy_chest.glb",
		"res://art/props-3d/props/mansion/toy_chest_navy.glb",
		"res://art/props-3d/props/mansion/toy_chest_violet.glb",
		"res://art/props-3d/props/mansion/toy_chest_olive.glb",
		"res://art/props-3d/props/mansion/toy_chest_ivory.glb",
		"res://art/props-3d/props/mansion/toy_chest_charcoal.glb",
	],
	"laundryHamper": [
		"res://art/props-3d/props/mansion/laundry_hamper.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_navy.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_violet.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_olive.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_ivory.glb",
		"res://art/props-3d/props/mansion/laundry_hamper_charcoal.glb",
	],
	"bedroomRug": [
		"res://art/props-3d/props/mansion/bedroom_rug.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_rug_charcoal.glb",
	],
	"bedroomWallClock": [
		"res://art/props-3d/props/mansion/bedroom_wall_clock.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_wall_clock_charcoal.glb",
	],
	"bedroomBench": [
		"res://art/props-3d/props/mansion/bedroom_bench.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_navy.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_violet.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_olive.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_ivory.glb",
		"res://art/props-3d/props/mansion/bedroom_bench_charcoal.glb",
	],

	"gothicDoubleBed": [
		"res://art/props-3d/props/mansion/gothic_double_bed_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_violet.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_forest.glb",
		"res://art/props-3d/props/mansion/gothic_double_bed_ivory.glb",
	],
	"gothicNightstand": [
		"res://art/props-3d/props/mansion/gothic_nightstand_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_violet.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_forest.glb",
		"res://art/props-3d/props/mansion/gothic_nightstand_ivory.glb",
	],
	"gothicWardrobe": [
		"res://art/props-3d/props/mansion/gothic_wardrobe_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_violet.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_forest.glb",
		"res://art/props-3d/props/mansion/gothic_wardrobe_ivory.glb",
	],
	"gothicDresser": [
		"res://art/props-3d/props/mansion/gothic_dresser_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_violet.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_forest.glb",
		"res://art/props-3d/props/mansion/gothic_dresser_ivory.glb",
	],
	"gothicVanity": [
		"res://art/props-3d/props/mansion/gothic_vanity_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_violet.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_forest.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_ivory.glb",
	],
	"gothicVanityStool": [
		"res://art/props-3d/props/mansion/gothic_vanity_stool_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_violet.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_forest.glb",
		"res://art/props-3d/props/mansion/gothic_vanity_stool_ivory.glb",
	],
	"gothicBedroomBench": [
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_violet.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_forest.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_bench_ivory.glb",
	],
	"gothicBedroomRug": [
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_violet.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_forest.glb",
		"res://art/props-3d/props/mansion/gothic_bedroom_rug_ivory.glb",
	],
	"gothicBedsideCandelabra": [
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_violet.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_forest.glb",
		"res://art/props-3d/props/mansion/gothic_bedside_candelabra_ivory.glb",
	],
	"gothicHighbackChair": [
		"res://art/props-3d/props/mansion/gothic_highback_chair_crimson.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_violet.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_midnight.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_forest.glb",
		"res://art/props-3d/props/mansion/gothic_highback_chair_ivory.glb",
	],
	"mansionConsoleTable": ["res://art/props-3d/props/mansion/mansion_console_table.glb"],
	"mansionGrandfatherClock": ["res://art/props-3d/props/mansion/mansion_grandfather_clock.glb"],
	"mansionCoatRack": ["res://art/props-3d/props/mansion/mansion_coat_rack.glb"],
	"mansionTeaCart": ["res://art/props-3d/props/mansion/mansion_tea_cart.glb"],
	"mansionRockingChair": ["res://art/props-3d/props/mansion/mansion_rocking_chair.glb"],
	"mansionRoomDivider": ["res://art/props-3d/props/mansion/mansion_room_divider.glb"],
	"gothicWritingDesk": ["res://art/props-3d/props/mansion/gothic_writing_desk.glb"],
	"gothicBookcase": ["res://art/props-3d/props/mansion/gothic_bookcase.glb"],
	"gothicPedestalTable": ["res://art/props-3d/props/mansion/gothic_pedestal_table.glb"],
	"gothicFloorCandelabra": ["res://art/props-3d/props/mansion/gothic_floor_candelabra.glb"],
	"gothicCoffinChest": ["res://art/props-3d/props/mansion/gothic_coffin_chest.glb"],
	"normalKitchenCounter": ["res://art/props-3d/props/mansion/normal_kitchen_counter.glb"],
	"normalKitchenSink": ["res://art/props-3d/props/mansion/normal_kitchen_sink.glb"],
	"normalKitchenStove": ["res://art/props-3d/props/mansion/normal_kitchen_stove.glb"],
	"normalKitchenFridge": ["res://art/props-3d/props/mansion/normal_kitchen_fridge.glb"],
	"normalKitchenWallCabinet": ["res://art/props-3d/props/mansion/normal_kitchen_wall_cabinet.glb"],
	"normalKitchenIsland": ["res://art/props-3d/props/mansion/normal_kitchen_island.glb"],
	"luxuryKitchenCounter": ["res://art/props-3d/props/mansion/luxury_kitchen_counter.glb"],
	"luxuryKitchenSink": ["res://art/props-3d/props/mansion/luxury_kitchen_sink.glb"],
	"luxuryKitchenStove": ["res://art/props-3d/props/mansion/luxury_kitchen_stove.glb"],
	"luxuryKitchenFridge": ["res://art/props-3d/props/mansion/luxury_kitchen_fridge.glb"],
	"luxuryKitchenWallCabinet": ["res://art/props-3d/props/mansion/luxury_kitchen_wall_cabinet.glb"],
	"luxuryKitchenIsland": ["res://art/props-3d/props/mansion/luxury_kitchen_island.glb"],
	"gothicKitchenCounter": ["res://art/props-3d/props/mansion/gothic_kitchen_counter.glb"],
	"gothicKitchenSink": ["res://art/props-3d/props/mansion/gothic_kitchen_sink.glb"],
	"gothicKitchenStove": ["res://art/props-3d/props/mansion/gothic_kitchen_stove.glb"],
	"gothicKitchenFridge": ["res://art/props-3d/props/mansion/gothic_kitchen_fridge.glb"],
	"gothicKitchenWallCabinet": ["res://art/props-3d/props/mansion/gothic_kitchen_wall_cabinet.glb"],
	"gothicKitchenIsland": ["res://art/props-3d/props/mansion/gothic_kitchen_island.glb"],
	"normalBookcase": ["res://art/props-3d/props/mansion/normal_bookcase.glb"],
	"normalCoffeeTable": ["res://art/props-3d/props/mansion/normal_coffee_table.glb"],
	"normalTvConsole": ["res://art/props-3d/props/mansion/normal_tv_console.glb"],
	"normalEntryBench": ["res://art/props-3d/props/mansion/normal_entry_bench.glb"],
	"mansionDisplayCabinet": ["res://art/props-3d/props/mansion/mansion_display_cabinet.glb"],
	"mansionChaiseLounge": ["res://art/props-3d/props/mansion/mansion_chaise_lounge.glb"],
	"mansionUprightPiano": ["res://art/props-3d/props/mansion/mansion_upright_piano.glb"],
	"mansionBustPedestal": ["res://art/props-3d/props/mansion/mansion_bust_pedestal.glb"],

	"sandCastle": ["res://art/props-3d/props/beach/sand_castle.glb"],
	"beachUmbrella": ["res://art/props-3d/props/beach/beach_umbrella.glb"],
	"tikiBar": ["res://art/props-3d/props/beach/tiki_bar.glb"],
	"beachChair": ["res://art/props-3d/props/beach/beach_chair.glb"],
	"surfboardRack": ["res://art/props-3d/props/beach/surfboard_rack.glb"],
	"palmTree": ["res://art/props-3d/props/beach/palm_tree.glb"],
	"frozenBeachHut": ["res://art/props-3d/props/beach/frozen_beach_hut.glb"],

	"lavaVent": ["res://art/props-3d/props/nether/lava_vent.glb"],
	"emberBrazier": ["res://art/props-3d/props/nether/ember_brazier.glb"],
	"basaltPillar": ["res://art/props-3d/props/nether/basalt_pillar.glb"],
	"basaltRubble": ["res://art/props-3d/props/nether/basalt_rubble.glb"],
	"magmaCrystalCluster": [
		"res://art/props-3d/props/nether/magma_crystal_cluster.glb",
	],
	"infernoAltar": ["res://art/props-3d/props/nether/inferno_altar.glb"],
	"infernoChainLantern": [
		"res://art/props-3d/props/nether/inferno_chain_lantern.glb",
	],
	"lavaPipeManifold": [
		"res://art/props-3d/props/nether/lava_pipe_manifold.glb",
	],
	"charredSupplyCrate": [
		"res://art/props-3d/props/nether/charred_supply_crate.glb",
	],
	"prisonCellGate": ["res://art/props-3d/props/prison/prison_cell_gate.glb"],
	"prisonBunk": ["res://art/props-3d/props/prison/prison_bunk.glb"],
	"dungeonCage": ["res://art/props-3d/props/prison/dungeon_cage.glb"],
	"restraintChair": ["res://art/props-3d/props/prison/restraint_chair.glb"],
}

## Highest local point of ceiling-hung models. Their exported origins stay in
## the same floor-based convention as every other prop, so this offset seats
## that authored top exactly against the 3 m corridor ceiling.
const CEILING_MODEL_TOP := {
	"diningChandelier": 1.59,
	"infernoChainLantern": 1.59,
}

## All members of a bedroom share the same room-id prefix. Hash that prefix
## for coordinated sets, rather than hashing each prop index independently,
## so the bed, storage, seating and dressing never receive mismatched themes.
const COORDINATED_SET_TYPES := [
	"singleBed", "doubleBed", "bedroomNightstand", "bedroomWardrobe",
	"bedroomDresser", "bedroomVanity", "vanityStool", "bedsideLamp",
	"toyChest", "laundryHamper", "bedroomRug", "bedroomWallClock",
	"bedroomBench", "gothicDoubleBed", "gothicNightstand",
	"gothicWardrobe", "gothicDresser", "gothicVanity",
	"gothicVanityStool", "gothicBedroomBench", "gothicBedroomRug",
	"gothicBedsideCandelabra", "gothicHighbackChair",
]


static func has_model(type: String) -> bool:
	return MODEL_PATHS.has(type) and not (MODEL_PATHS[type] as Array).is_empty()


static func model_path(type: String, instance_id: String) -> String:
	var paths: Array = MODEL_PATHS.get(type, [])
	if paths.is_empty():
		return ""
	var variant_key := instance_id
	if COORDINATED_SET_TYPES.has(type) and instance_id.contains("-prop-"):
		variant_key = instance_id.get_slice("-prop-", 0)
	return String(paths[_stable_index(variant_key, paths.size())])


static func visual_y(type: String, wall_height: float, mount_y: float = 0.0) -> float:
	if mount_y > 0.0:
		return mount_y
	if CEILING_MODEL_TOP.has(type):
		return wall_height - float(CEILING_MODEL_TOP[type])
	return 0.0


static func _stable_index(value: String, size: int) -> int:
	var result := 0
	for byte in value.to_utf8_buffer():
		result = (result * 31 + int(byte)) & 0x7fffffff
	return result % maxi(1, size)
