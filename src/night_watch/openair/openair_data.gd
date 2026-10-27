class_name NightWatchOpenAirData
extends RefCounted

## Open Air's constants, copied from the 2D openair-data.js: the three outdoor watches, who keeps each, the weather and Zellia's script.
## Pure data; the rules are in openair_logic.gd. Each level is its own watch with its own hunter and its own way of keeping the dark off:
##   1. ROOFTOP   Verrine walks the edge. A lantern the wind keeps blowing out, a torch to hold her still, a stair door and a hatch to bar.
##   2. BUS STOP  Wynelle waits on the road. It is cold; keep warm with the heat lamp, and find fuel for it.
##   3. CAMPFIRE  Verrine from the trees on the left, Quenelle on the right; a tent to hide in, and Ysolde at the log pile while you do.

const MODE_ID := "extra"      # the 2D id (the registry key); the code is `openair`
const CAST := ["ysolde", "verrine", "wynelle", "quenelle"]
const NAMES := {"verrine": "Verrine", "wynelle": "Wynelle", "ysolde": "Ysolde", "quenelle": "Quenelle"}
const PAN := {"verrine": -0.6, "wynelle": -0.8, "ysolde": 0.3, "quenelle": 0.6}
const SIDES := {"verrine": "L", "quenelle": "R"}   # the campfire: who comes out of which side of the trees
## The 3D roster's model for each 2D name (they all have their own now).
const MODELS := {"verrine": "verrine", "wynelle": "wynelle", "ysolde": "ysolde", "quenelle": "quenelle"}

const WATCHES := [
	{"id": "rooftop", "label": "ROOFTOP", "hunter": "verrine"},
	{"id": "busstop", "label": "BUS STOP", "hunter": "wynelle"},
	{"id": "campfire", "label": "CAMPFIRE", "hunter": "ysolde"},
]
## AI level of each watch's hunter (a Custom Night sets its own, one slider each).
const LEVELS := {"verrine": 9, "wynelle": 8, "ysolde": 8, "quenelle": 13}
## Weather per watch index: a squall or shower comes every so often (a random gap, +/-25%) and lasts a while.
const WEATHER := {
	1: {"kind": "snow", "everyMs": 34000.0, "lastsMs": 9000.0, "mult": 1.8, "first": 20000.0},
	2: {"kind": "rain", "everyMs": 40000.0, "lastsMs": 10000.0, "mult": 2.2, "first": 25000.0},
}
const BUS_MS := 18000.0
const WATCH_MS := NightWatchData.NIGHT_MS   # as long as any night

## Zellia's calls are the shared table (NightWatchCallsData, mode `extra`), verbatim from the 2D openair-data.js.


## Where a step is heard: on the side she is coming from ("L" the stair door, "R" the hatch), at her own distance from centre.
static func side_pan(id: String, side: String) -> float:
	if side == "L":
		return -absf(float(PAN[id]))
	if side == "R":
		return absf(float(PAN[id]))
	return float(PAN[id])


## A Custom Night's watches, in order: each whose hunter has a level above 0 (the campfire runs when Ysolde or Quenelle is on).
static func custom_watches(ai: Dictionary) -> Array:
	var out := []
	for i in 3:
		var on := false
		if i == 2:
			on = int(ai.get("ysolde", 0)) > 0 or int(ai.get("quenelle", 0)) > 0
		else:
			on = int(ai.get(String(WATCHES[i]["hunter"]), 0)) > 0
		if on:
			out.append(i)
	return out


## Who is on the floor on a watch: that watch's hunter (and, at the campfire, Ysolde, Verrine on the left and Quenelle on the right).
static func active_hunters(watch_index: int) -> Array:
	if mini(watch_index, 2) == 2:
		return ["ysolde", "verrine", "quenelle"]
	return [String(WATCHES[mini(watch_index, 2)]["hunter"])]
