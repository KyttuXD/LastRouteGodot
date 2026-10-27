class_name MaskMap
extends RefCounted

## Masked Hours' MAP (NightWatchMapRegistry): the FNAF 2 floor plan of MaskWorld as data: the show floor with the Game Area at its heart (Show Stage north, Prize Corner west, Parts / Service
## east), the Main Hall running south into the door-less office with four Party Rooms off it, the Left and Right Halls down the outer sides to the Vent Hub behind the office and the two air
## vent ducts to the office's side vents. Not a reskin of Classic's 3 x 3 building: a hall-and-plaza plan with a back-of-house loop. Centres are in building space (office at the origin, +z south).

static func map_layout() -> Dictionary:
	return {
		"rooms": {
			"ballroom": Vector3(0, 0, -24), "music": Vector3(-14.5, 0, -25), "costume": Vector3(14.5, 0, -25), "gallery": Vector3(0, 0, -34),
			"hall": Vector3(0, 0, -9), "party1": Vector3(-5, 0, -7.2), "party2": Vector3(-5, 0, -12.8), "party3": Vector3(5, 0, -7.2), "party4": Vector3(5, 0, -12.8),
			"lefthall": Vector3(-12.5, 0, -8), "righthall": Vector3(12.5, 0, -8),
			"crawl": Vector3(0, 0, 6.8), "ductL": Vector3(-5.2, 0, 0.6), "ductR": Vector3(5.2, 0, 0.6),
		},
		"edges": [
			["ballroom", "music"], ["ballroom", "costume"], ["ballroom", "gallery"], ["ballroom", "hall"],
			["hall", "party1"], ["hall", "party2"], ["hall", "party3"], ["hall", "party4"],
			["music", "lefthall"], ["costume", "righthall"], ["lefthall", "crawl"], ["righthall", "crawl"],
			["crawl", "ductL"], ["crawl", "ductR"],
		],
		"entrances": ["hall", "ductL", "ductR"],
		"theme": "FNAF 2 style show floor: a door-less office at the end of a 15 m main hall, open-plan game area / show stage / prize corner / parts room, four party rooms off the hall, side halls to a vent hub and two air vents",
	}
