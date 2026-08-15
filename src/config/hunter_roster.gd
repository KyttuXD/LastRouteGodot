class_name HunterRoster
extends RefCounted

## Who every hunter is: her movement/perception tuning, her difficulty tier and
## the art/props-3d/characters/ scene ModelSlot loads for her.
##
## All 26 are in PROFILES. That is not a claim that 26 hunters are playable --
## IMPLEMENTED_IDS is the pool the game actually draws from, and it is shorter.
## The numbers are simply the numbers, transcribed from HUNTER_PROFILES in the
## original's game-config.js, and a roster that only knows two thirds of its own
## cast cannot weight a draw by tier or name whoever the disguise picked.
##
## They live here rather than as ~130 constants in GameConfig because nothing
## outside this file ever read them: GameConfig keeps the ABILITY constants (a
## gimmick's ranges, intervals and thresholds), which its gimmick script does
## read by name. One row per hunter is also what makes adding the next one a
## one-line change instead of five.
##
## Adding a hunter:
##   1. Port her gimmick as a HunterGimmick subclass in src/game/hunter_gimmicks/
##      and register it in HunterGimmick.for_id().
##   2. Add her ability constants to GameConfig.
##   3. Add her id to IMPLEMENTED_IDS below.
## Her profile and model are already here. A hunter whose difference is only
## tuning numbers -- Dovelle, Thessine -- needs step 3 alone.

const DEFAULT_ID := "dovelle"

## Every hunter, from HUNTER_PROFILES. `spawn_distance` is carried for
## completeness; place_hunter_spawn() does not read it yet.
const PROFILES := {
	"aki":      {"name": "Aki",      "tier": "easy",         "speed": 0.82, "chase": 3.55,  "prog": 0.20, "sight": 8.20, "hearing": 1.00, "spawn": 11},
	"briselle": {"name": "Briselle", "tier": "easy",         "speed": 0.84, "chase": 3.62,  "prog": 0.18, "sight": 7.70, "hearing": 1.00, "spawn": 12},
	"ceryth":   {"name": "Ceryth",   "tier": "intermediate", "speed": 0.78, "chase": 3.45,  "prog": 0.17, "sight": 8.60, "hearing": 0.88, "spawn": 12},
	"dovelle":  {"name": "Dovelle",  "tier": "easy",         "speed": 0.80, "chase": 3.55,  "prog": 0.18, "sight": 8.00, "hearing": 1.00, "spawn": 12},
	"eirys":    {"name": "Eirys",    "tier": "difficult",    "speed": 0.82, "chase": 3.58,  "prog": 0.18, "sight": 8.10, "hearing": 1.05, "spawn": 12},
	"ferryn":   {"name": "Ferryn",   "tier": "intermediate", "speed": 0.80, "chase": 2.75,  "prog": 0.17, "sight": 8.30, "hearing": 0.92, "spawn": 12},
	"glyra":    {"name": "Glyra",    "tier": "easy",         "speed": 0.81, "chase": 3.52,  "prog": 0.18, "sight": 7.90, "hearing": 1.12, "spawn": 12},
	"haelith":  {"name": "Haelith",  "tier": "easy",         "speed": 0.83, "chase": 3.60,  "prog": 0.18, "sight": 7.80, "hearing": 1.18, "spawn": 12},
	"ilyra":    {"name": "Ilyra",    "tier": "intermediate", "speed": 0.77, "chase": 3.68,  "prog": 0.17, "sight": 8.70, "hearing": 0.80, "spawn": 12},
	"jyvra":    {"name": "Jyvra",    "tier": "easy",         "speed": 0.80, "chase": 3.56,  "prog": 0.18, "sight": 8.00, "hearing": 1.00, "spawn": 12},
	"kathy":    {"name": "Kathy",    "tier": "difficult",    "speed": 0.82, "chase": 4.15,  "prog": 0.20, "sight": 8.20, "hearing": 1.00, "spawn": 16},
	"loxelle":  {"name": "Loxelle",  "tier": "easy",         "speed": 0.80, "chase": 3.555, "prog": 0.18, "sight": 7.90, "hearing": 1.12, "spawn": 13},
	"mavrine":  {"name": "Mavrine",  "tier": "intermediate", "speed": 0.80, "chase": 3.50,  "prog": 0.17, "sight": 8.20, "hearing": 0.95, "spawn": 12},
	"nyxie":    {"name": "Nyxie",    "tier": "special",      "speed": 0.90, "chase": 3.90,  "prog": 0.15, "sight": 8.40, "hearing": 0.00, "spawn": 10},
	"opalie":   {"name": "Opalie",   "tier": "easy",         "speed": 0.83, "chase": 3.47,  "prog": 0.18, "sight": 7.70, "hearing": 1.10, "spawn": 13},
	"porcelle": {"name": "Porcelle", "tier": "intermediate", "speed": 0.80, "chase": 3.55,  "prog": 0.17, "sight": 8.00, "hearing": 0.90, "spawn": 13},
	"quirith":  {"name": "Quirith",  "tier": "easy",         "speed": 0.81, "chase": 3.50,  "prog": 0.17, "sight": 8.10, "hearing": 0.85, "spawn": 12},
	"ravelle":  {"name": "Ravelle",  "tier": "difficult",    "speed": 0.81, "chase": 3.15,  "prog": 0.18, "sight": 7.70, "hearing": 1.00, "spawn": 12},
	"solyth":   {"name": "Solyth",   "tier": "special",      "speed": 0.80, "chase": 3.00,  "prog": 0.17, "sight": 7.60, "hearing": 0.95, "spawn": 12},
	"thessine": {"name": "Thessine", "tier": "intermediate", "speed": 0.78, "chase": 3.44,  "prog": 0.17, "sight": 8.40, "hearing": 0.90, "spawn": 13},
	"umbriel":  {"name": "Umbriel",  "tier": "difficult",    "speed": 0.82, "chase": 3.46,  "prog": 0.18, "sight": 8.50, "hearing": 0.86, "spawn": 12},
	"verrine":  {"name": "Verrine",  "tier": "intermediate", "speed": 0.83, "chase": 3.66,  "prog": 0.18, "sight": 7.70, "hearing": 1.10, "spawn": 13},
	"wynelle":  {"name": "Wynelle",  "tier": "difficult",    "speed": 0.81, "chase": 3.00,  "prog": 0.18, "sight": 7.80, "hearing": 1.15, "spawn": 12},
	"xivvy":    {"name": "Xivvy",    "tier": "intermediate", "speed": 0.97, "chase": 4.35,  "prog": 0.12, "sight": 6.72, "hearing": 0.84, "spawn": 13},
	"ysolde":   {"name": "Ysolde",   "tier": "easy",         "speed": 0.80, "chase": 3.54,  "prog": 0.18, "sight": 8.10, "hearing": 1.00, "spawn": 12},
	"zephyra":  {"name": "Zephyra",  "tier": "easy",         "speed": 0.83, "chase": 3.60,  "prog": 0.17, "sight": 8.00, "hearing": 0.95, "spawn": 12},
}

## The hunters the game actually draws. Grows as gimmicks are ported; a hunter
## with a profile and a model but no gimmick is NOT in here, because shipping
## her would be a Dovelle reskin wearing someone else's name.
##
## Thessine is the exception that proves it: her whole gimmick is playing fake
## sound cues, which changes no state whatsoever. Without an audio system she
## is not a degraded Thessine, she is a complete one -- so she is in the pool
## on her own tuning, and gains her cues later without a behaviour change.
const IMPLEMENTED_IDS := [
	"dovelle", "quirith", "eirys", "xivvy", "kathy", "ravelle", "mavrine",
	"umbriel", "wynelle", "thessine", "haelith", "ysolde", "opalie", "aki", "porcelle", "jyvra", "loxelle", "ceryth", "briselle", "ferryn", "glyra",
]

## Never entered into the random draw. These are always present on a floor but
## inert, woken by their own rule instead of the relay schedule — Nyxie by
## sustained darkness, Solyth by a sustained heat extreme. They hunt alongside
## whichever route hunter was drawn, which is why main_3d.gd keeps a
## collection of hunters rather than one.
const SPECIAL_IDS := ["nyxie", "solyth"]

## NORMAL_ROUTE_HUNTER_TIERS' Standard weights. The original varies these by
## difficulty; only Standard's are recorded in HUNTER_ROSTER.md, so Relaxed and
## Nightmare use them too rather than have numbers invented for them.
const TIER_WEIGHTS := {"easy": 0.35, "intermediate": 0.50, "difficult": 0.15}


static func get_identity(id: String) -> Dictionary:
	var profile: Dictionary = PROFILES.get(id, PROFILES[DEFAULT_ID])
	var key: String = id if PROFILES.has(id) else DEFAULT_ID
	return {
		"display_name": profile["name"],
		"base_speed": profile["speed"],
		"chase_speed": profile["chase"],
		"chase_progression_scale": profile["prog"],
		"sight_range": profile["sight"],
		"hearing_scale": profile["hearing"],
		"model_scene": "res://art/props-3d/characters/%s.tscn" % key,
	}


## Mirrors selectRouteHunters(): a tier-weighted seeded draw, keyed by
## seed+depth so a replayed run or descent draws the same hunter while a new
## one reshuffles, independently of the AI and facility RNG streams.
##
## The weights are over TIERS, and a tier with nobody implemented in it cannot
## be drawn -- so its weight is dropped and the rest renormalised, rather than
## the draw silently falling through to whoever happens to be first. That
## matters right now: the pool is a third of the roster, and unrenormalised
## weights would hand "difficult" a share of the draw far above its 0.15.
static func pick_for_floor(seed_text: String, depth: int) -> String:
	var rng := SeededRandom.new("%s:HUNTER-LINEUP:D%d" % [seed_text, maxi(1, depth)])
	var by_tier := {}
	for id in IMPLEMENTED_IDS:
		var tier: String = PROFILES[id]["tier"]
		by_tier.get_or_add(tier, []).append(id)

	var total := 0.0
	for tier in by_tier:
		total += float(TIER_WEIGHTS.get(tier, 0.0))
	if total <= 0.0:
		return IMPLEMENTED_IDS[rng.next_index(IMPLEMENTED_IDS.size())]

	# Walk the tiers in a fixed order: a Dictionary's iteration order follows
	# insertion, which follows IMPLEMENTED_IDS, so it is stable -- but only by
	# accident. Sorting makes the draw depend on the seed alone.
	var tiers: Array = by_tier.keys()
	tiers.sort()
	var roll := rng.next_float() * total
	for tier in tiers:
		roll -= float(TIER_WEIGHTS.get(tier, 0.0))
		if roll <= 0.0:
			var pool: Array = by_tier[tier]
			return pool[rng.next_index(pool.size())]
	var last: Array = by_tier[tiers[-1]]
	return last[rng.next_index(last.size())]


## Everyone Umbriel may disguise as: the whole roster minus the specials, minus
## whoever she is copying from, minus the original's own exclusion list. Reads
## PROFILES rather than IMPLEMENTED_IDS on purpose -- a disguise is a model and
## a name, not an AI, so she can wear a hunter whose gimmick is not ported.
static func disguise_ids(exclude: Array) -> Array:
	var out := []
	for id in PROFILES:
		if id == "umbriel" or SPECIAL_IDS.has(id) or exclude.has(id):
			continue
		out.append(id)
	out.sort()
	return out
