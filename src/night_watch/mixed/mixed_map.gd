class_name MixedMap
extends RefCounted

## Mixed Shift's MAP (NightWatchMapRegistry): its own TRANSIT HUB, not Classic's building: a concourse at the heart of a station with the platform and the ticket hall to the north, the west and
## east arcades running down either side of the concourse to the security office (the two door halls open into them), a cafe between the concourse and the office, and the lost-property office and the
## newsstand at the far south ends of the arcades; the vent run (CAM 9) is the ninth camera. The golden-tested Mixed rules keep Classic's room ids (stage, dining, ...): SIM_TO_MAP names the map room
## each of them is played in, and CAMS lists the nine cameras in order (camera n = CAMS[n-1]). Each night one of three DRESSINGS (SETS) is drawn from the seed: the station as it is, a party-floor
## dressing (balloons, tables, streamers, arcade cabinets: Masked Hours' props) or a salvage-yard dressing (containers, scrap, barrels, a crane arm: Salvage Run's props) on this same layout. The
## rotation is of dressings, not of the other modes' maps (their worlds have their own graphs): see docs/NIGHT_WATCH_OFFICES.md.

const SIM_TO_MAP := {"stage": "platform", "dining": "concourse", "backstage": "ticket_hall", "westhall": "west_arcade", "closet": "lost_property", "kitchen": "cafe",
	"easthall": "east_arcade", "corner": "newsstand", "vent": "duct"}
const SETS := ["transit", "party", "yard"]
const CAMS := ["platform", "concourse", "ticket_hall", "west_arcade", "lost_property", "cafe", "east_arcade", "newsstand", "duct"]
const LABELS := {"platform": "PLATFORM", "concourse": "CONCOURSE", "ticket_hall": "TICKET HALL", "west_arcade": "WEST ARCADE", "lost_property": "LOST PROPERTY", "cafe": "CAFE",
	"east_arcade": "EAST ARCADE", "newsstand": "NEWSSTAND", "duct": "VENT RUN"}


static func map_for(sim_room: String) -> String:
	return String(SIM_TO_MAP.get(sim_room, sim_room))


static func sim_for(map_room: String) -> String:
	for k in SIM_TO_MAP:
		if String(SIM_TO_MAP[k]) == map_room:
			return String(k)
	return map_room


## The dressing a night uses (drawn from its seed).
static func set_for_seed(seed_number: int) -> int:
	return absi(seed_number) % SETS.size()


static func map_layout() -> Dictionary:
	return {
		"rooms": {
			"platform": Vector3(0, 0, -38), "ticket_hall": Vector3(-18, 0, -38), "concourse": Vector3(0, 0, -22), "west_arcade": Vector3(-15, 0, -10), "east_arcade": Vector3(15, 0, -10),
			"cafe": Vector3(0, 0, -9), "lost_property": Vector3(-15, 0, 11), "newsstand": Vector3(15, 0, 11), "duct": Vector3(0, 0, 11),
		},
		"edges": [
			["platform", "concourse"], ["platform", "ticket_hall"], ["ticket_hall", "west_arcade"], ["concourse", "west_arcade"], ["concourse", "east_arcade"], ["concourse", "cafe"],
			["west_arcade", "lost_property"], ["east_arcade", "newsstand"], ["lost_property", "duct"], ["newsstand", "duct"],
		],
		"entrances": ["west_arcade", "east_arcade", "duct"],
		"cams": CAMS,
		"labels": LABELS,
		"vents": ["duct"],
		"office": Vector3(0, 0, 0),
		"theme": "a transit hub: a concourse with the platform and ticket hall to the north, two arcades down the sides to the security office, a cafe and the vent run; three dressings (station, party floor, salvage yard) drawn per night",
	}
