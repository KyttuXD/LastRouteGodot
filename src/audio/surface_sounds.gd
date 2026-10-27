class_name SurfaceSounds
extends RefCounted

## Floor material -> footstep sound (docs/AMBIENCE.md). Every RefTextures floor kind (the kinds FloorSets uses) maps to one
## surface; the Sound system shapes the step from the surface profile below. Explicit table so a new floor kind without a
## mapping fails the `ambience` validator instead of silently stepping like concrete.

const SURFACES := ["carpet", "wood", "tile", "concrete", "metal", "stone", "grass", "water"]

const FLOOR_KINDS := {
	"metal0": "metal", "metal1": "metal", "metal2": "metal", "metal3": "metal", "grate": "metal", "hazard": "metal",
	"floral0": "carpet", "floral1": "carpet", "star0": "carpet", "star1": "carpet",
	"carpet_red": "carpet", "carpet_teal": "carpet", "carpet_green": "carpet", "carpet_plum": "carpet",
	"carpet_tile0": "carpet", "carpet_tile1": "carpet",
	"runner": "carpet", "runnerz": "carpet", "runner_l": "carpet", "runner_c": "carpet", "runner_r": "carpet",
	"runnerz_l": "carpet", "runnerz_c": "carpet", "runnerz_r": "carpet",
	"parquet0": "wood", "parquet1": "wood",
	"check0": "tile", "check1": "tile", "vinyl0": "tile", "vinyl1": "tile",
	"stone0": "stone", "stone1": "stone", "stone2": "stone",
	"concrete0": "concrete", "concrete1": "concrete",
	"sewer_water": "water",   # the sewer channel: wading (docs/SEWERS.md)
	"epoxy0": "tile", "epoxy1": "tile", "terracotta0": "stone", "terracotta1": "stone",
	"terrazzo0": "tile", "terrazzo1": "tile",
	"safe": "metal", "safe_plain": "metal", "safe_mark": "metal",
}

## Step shape per surface: noise colour (Hz) and level, body thump (Hz) and level, optional click / splash.
const PROFILES := {
	"carpet": {"noise_hz": 240.0, "noise": .55, "thump_hz": 48.0, "thump": .7, "click": 0.0},
	"wood": {"noise_hz": 330.0, "noise": .55, "thump_hz": 92.0, "thump": 1.25, "click": 0.0},
	"tile": {"noise_hz": 900.0, "noise": .7, "thump_hz": 60.0, "thump": .6, "click": 1.0},
	"concrete": {"noise_hz": 560.0, "noise": 1.15, "thump_hz": 55.0, "thump": .9, "click": 0.0},
	"metal": {"noise_hz": 760.0, "noise": .8, "thump_hz": 110.0, "thump": .8, "click": .7, "ring": 1.0},
	"stone": {"noise_hz": 480.0, "noise": .95, "thump_hz": 58.0, "thump": .85, "click": .4},
	"grass": {"noise_hz": 1400.0, "noise": .6, "thump_hz": 40.0, "thump": .45, "click": 0.0},
	"water": {"noise_hz": 1100.0, "noise": 1.2, "thump_hz": 70.0, "thump": .5, "click": 0.0, "splash": 1.0},
}


static func for_floor(kind: String) -> String:
	return String(FLOOR_KINDS.get(kind, "concrete"))


static func has_floor(kind: String) -> bool:
	return FLOOR_KINDS.has(kind)
