class_name NightWatchOpenAirMap
extends RefCounted

## Open Air's MAP (docs/NIGHT_WATCH_OFFICES.md, "Maps"): open grounds, one layout covering the three watches, none of it a building. A guard roof with its
## catwalks, a yard and a service road that runs east to the bus stop, and a trail through the pines to the campfire clearing. Each watch is one cluster of this
## map (the world builds the cluster; `NightWatchOpenAirPaths` holds the same places as the hunters' waypoints):
##   ROOFTOP   roof (the office), catwalk_w and catwalk_e (the gantries to the stair door L0..L3 and the hatch R0..R3), back_catwalk (the walk round the back that joins them)
##   BUS STOP  bus_shelter (the office), road_stop and road_far (the road Wynelle walks, W0..W4)
##   CAMPFIRE  clearing (the office), trees_w / trees_e (Verrine's V3..V0 and Quenelle's Q3..Q0), log_pile and pines (Ysolde's Y2..Y0)
## Paths join the clusters (roof to yard to road to trail) so the grounds are one connected map; the three offices are the entrances. Metres, building space.

static func map_layout() -> Dictionary:
	var rooms := {
		"roof": Vector3(0, 0, 0),
		"catwalk_w": Vector3(-9, 0, -6),
		"catwalk_e": Vector3(9, 0, -6),
		"back_catwalk": Vector3(0, 0, -8.7),
		"yard": Vector3(0, -6, -24),
		"service_road": Vector3(26, -6, -24),
		"road_far": Vector3(52, -6, -24),
		"bus_shelter": Vector3(30, -6, -17),
		"road_stop": Vector3(30, -6, -22),
		"pine_trail": Vector3(30, -6, -40),
		"clearing": Vector3(30, -6, -56),
		"trees_w": Vector3(16, -6, -64),
		"trees_e": Vector3(44, -6, -64),
		"pines": Vector3(34, -6, -72),
		"log_pile": Vector3(34, -6, -53),
	}
	var edges := [
		["roof", "catwalk_w"], ["roof", "catwalk_e"], ["catwalk_w", "back_catwalk"], ["catwalk_e", "back_catwalk"],
		["catwalk_w", "yard"], ["catwalk_e", "yard"],
		["yard", "service_road"], ["service_road", "road_stop"], ["service_road", "road_far"], ["road_stop", "bus_shelter"],
		["service_road", "pine_trail"], ["pine_trail", "clearing"],
		["clearing", "trees_w"], ["clearing", "trees_e"], ["clearing", "log_pile"], ["log_pile", "pines"], ["trees_e", "pines"],
	]
	return {"rooms": rooms, "edges": edges, "entrances": ["roof", "bus_shelter", "clearing"],
		"theme": "open grounds: a guard roof with catwalks, a yard and service road to a bus stop, a pine trail to a campfire clearing"}
