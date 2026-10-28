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
## Read PROFILES, not this: entries marked ContentRegistry.DATA live in res://data/hunters/<id>.json
## (docs/DATA_DRIVEN_CONTENT.md) and PROFILES is this table with them filled in, in this order.
const _CODE_PROFILES := {
	"aki":      ContentRegistry.DATA,
	"briselle": ContentRegistry.DATA,
	"ceryth":   ContentRegistry.DATA,
	"dovelle":  ContentRegistry.DATA,
	"elise":    ContentRegistry.DATA,
	"ferryn":   ContentRegistry.DATA,
	"glyra":    ContentRegistry.DATA,
	"haelith":  {"name": "Haelith",  "tier": "easy",         "speed": 0.83, "chase": 3.60,  "prog": 0.18, "sight": 7.80, "hearing": 1.18, "spawn": 12},
	"ilyra":    {"name": "Ilyra",    "tier": "intermediate", "speed": 0.77, "chase": 3.68,  "prog": 0.17, "sight": 8.70, "hearing": 0.80, "spawn": 12},
	"javelle":    {"name": "Javelle",    "tier": "easy",         "speed": 0.80, "chase": 3.56,  "prog": 0.18, "sight": 8.00, "hearing": 1.00, "spawn": 12},
	"kathy":    {"name": "Kathy",    "tier": "difficult",    "speed": 0.82, "chase": 4.15,  "prog": 0.20, "sight": 8.20, "hearing": 1.00, "spawn": 16},
	"loxelle":  {"name": "Loxelle",  "tier": "easy",         "speed": 0.80, "chase": 3.555, "prog": 0.18, "sight": 7.90, "hearing": 1.12, "spawn": 13},
	"mavrine":  {"name": "Mavrine",  "tier": "intermediate", "speed": 0.80, "chase": 3.50,  "prog": 0.17, "sight": 8.20, "hearing": 0.95, "spawn": 12},
	"nyxie":    {"name": "Nyxie",    "tier": "special",      "speed": 0.90, "chase": 3.90,  "prog": 0.15, "sight": 8.40, "hearing": 0.00, "spawn": 10},
	"opalie":   {"name": "Opalie",   "tier": "easy",         "speed": 0.83, "chase": 3.47,  "prog": 0.18, "sight": 7.70, "hearing": 1.10, "spawn": 13},
	"porcelle": {"name": "Porcelle", "tier": "intermediate", "speed": 0.80, "chase": 3.55,  "prog": 0.17, "sight": 8.00, "hearing": 0.90, "spawn": 13},
	"quenelle":  {"name": "Quenelle",  "tier": "easy",         "speed": 0.81, "chase": 3.50,  "prog": 0.17, "sight": 8.10, "hearing": 0.85, "spawn": 12},
	"ravelle":  {"name": "Ravelle",  "tier": "difficult",    "speed": 0.81, "chase": 3.15,  "prog": 0.18, "sight": 7.70, "hearing": 1.00, "spawn": 12},
	"solyth":   {"name": "Solyth",   "tier": "special",      "speed": 0.80, "chase": 3.00,  "prog": 0.17, "sight": 7.60, "hearing": 0.95, "spawn": 12},
	"thessine": {"name": "Thessine", "tier": "intermediate", "speed": 0.78, "chase": 3.44,  "prog": 0.17, "sight": 8.40, "hearing": 0.90, "spawn": 13},
	"umbriel":  {"name": "Umbriel",  "tier": "difficult",    "speed": 0.82, "chase": 3.46,  "prog": 0.18, "sight": 8.50, "hearing": 0.86, "spawn": 12},
	"verrine":  {"name": "Verrine",  "tier": "intermediate", "speed": 0.83, "chase": 3.66,  "prog": 0.18, "sight": 7.70, "hearing": 1.10, "spawn": 13},
	"wynelle":  {"name": "Wynelle",  "tier": "difficult",    "speed": 0.81, "chase": 3.00,  "prog": 0.18, "sight": 7.80, "hearing": 1.15, "spawn": 12},
	"xivvy":    {"name": "Xivvy",    "tier": "intermediate", "speed": 0.97, "chase": 4.35,  "prog": 0.12, "sight": 6.72, "hearing": 0.84, "spawn": 13},
	"ysolde":   {"name": "Ysolde",   "tier": "easy",         "speed": 0.80, "chase": 3.54,  "prog": 0.18, "sight": 8.10, "hearing": 1.00, "spawn": 12},
	"zellia":  {"name": "Zellia",  "tier": "easy",         "speed": 0.83, "chase": 3.60,  "prog": 0.17, "sight": 8.00, "hearing": 0.95, "spawn": 12},
	# Void incursions are an extra category, not letters appended to the A-Z
	# roster. Their source skins are deliberately larger in presentation and
	# their baseline tuning is more aggressive even before colour-specific
	# mechanics are promoted from the design notes into code.
	"void_black":  {"name": "Black",  "tier": "void", "category": "void", "speed": 0.94, "chase": 4.55, "prog": 0.24, "sight": 9.4, "hearing": 1.22, "spawn": 15, "model": "res://art/props-3d/characters/void_black.tscn"},
	"void_blue":   {"name": "Blue",   "tier": "void", "category": "void", "speed": 0.92, "chase": 4.48, "prog": 0.25, "sight": 9.6, "hearing": 1.18, "spawn": 15, "model": "res://art/props-3d/characters/void_blue.tscn"},
	"void_brown":  {"name": "Brown",  "tier": "void", "category": "void", "speed": 0.96, "chase": 4.62, "prog": 0.23, "sight": 9.0, "hearing": 1.30, "spawn": 14, "model": "res://art/props-3d/characters/void_brown.tscn"},
	"void_cyan":   {"name": "Cyan",   "tier": "void", "category": "void", "speed": 0.95, "chase": 4.70, "prog": 0.26, "sight": 9.8, "hearing": 1.16, "spawn": 16, "model": "res://art/props-3d/characters/void_cyan.tscn"},
	"void_gray":   {"name": "Gray",   "tier": "void", "category": "void", "speed": 0.91, "chase": 4.42, "prog": 0.27, "sight": 10.0, "hearing": 1.12, "spawn": 17, "model": "res://art/props-3d/characters/void_gray.tscn"},
	"void_green":  {"name": "Green",  "tier": "void", "category": "void", "speed": 0.97, "chase": 4.68, "prog": 0.25, "sight": 9.1, "hearing": 1.28, "spawn": 14, "model": "res://art/props-3d/characters/void_green.tscn"},
	"void_orange": {"name": "Orange", "tier": "void", "category": "void", "speed": 1.00, "chase": 4.82, "prog": 0.28, "sight": 9.2, "hearing": 1.24, "spawn": 14, "model": "res://art/props-3d/characters/void_orange.tscn"},
	"void_pink":   {"name": "Pink",   "tier": "void", "category": "void", "speed": 0.93, "chase": 4.50, "prog": 0.26, "sight": 9.7, "hearing": 1.20, "spawn": 16, "model": "res://art/props-3d/characters/void_pink.tscn"},
	"void_purple": {"name": "Purple", "tier": "void", "category": "void", "speed": 0.98, "chase": 4.75, "prog": 0.29, "sight": 9.5, "hearing": 1.15, "spawn": 16, "model": "res://art/props-3d/characters/void_purple.tscn"},
	"void_red":    {"name": "Red",    "tier": "void", "category": "void", "speed": 1.02, "chase": 4.90, "prog": 0.30, "sight": 9.3, "hearing": 1.30, "spawn": 14, "model": "res://art/props-3d/characters/void_red.tscn"},
	"void_white":  {"name": "White",  "tier": "void", "category": "void", "speed": 0.90, "chase": 4.45, "prog": 0.24, "sight": 8.8, "hearing": 1.38, "spawn": 17, "model": "res://art/props-3d/characters/void_white.tscn"},
	"void_yellow": {"name": "Yellow", "tier": "void", "category": "void", "speed": 0.99, "chase": 4.78, "prog": 0.27, "sight": 9.8, "hearing": 1.20, "spawn": 15, "model": "res://art/props-3d/characters/void_yellow.tscn"},
}

static var PROFILES: Dictionary = ContentRegistry.resolve(_CODE_PROFILES, "hunters")


static var _watching: bool = ContentRegistry.watch(rebuild_from_registry)


## Packs changed (ContentRegistry.load_packs / unload_packs): recompute everything derived from the registry.
static func rebuild_from_registry() -> void:
	PROFILES = ContentRegistry.resolve(_CODE_PROFILES, "hunters")
	DRAW_IDS = _draw_ids()
	_eye_glow_color_cache.clear()

## The hunters the game actually draws. Grows as gimmicks are ported; a hunter
## with a profile and a model but no gimmick is NOT in here, because shipping
## her would be a Dovelle reskin wearing someone else's name.
##
## Thessine is the exception that proves it: her whole gimmick is playing fake
## sound cues, which changes no state whatsoever. Without an audio system she
## is not a degraded Thessine, she is a complete one -- so she is in the pool
## on her own tuning, and gains her cues later without a behaviour change.
const IMPLEMENTED_IDS := [
	"dovelle", "quenelle", "elise", "xivvy", "kathy", "ravelle", "mavrine",
	"umbriel", "wynelle", "thessine", "haelith", "ysolde", "opalie", "aki", "porcelle", "javelle", "loxelle", "ceryth", "briselle", "ferryn", "glyra", "ilyra", "verrine", "zellia",
]

## Never entered into the random draw. These are always present on a floor but
## inert, woken by their own rule instead of the relay schedule — Nyxie by
## sustained darkness, Solyth by a sustained heat extreme. They hunt alongside
## whichever route hunter was drawn, which is why main_3d.gd keeps a
## collection of hunters rather than one.
const SPECIAL_IDS := ["nyxie", "solyth"]
## What pick_for_floor draws from: IMPLEMENTED_IDS plus hunters added by loaded packs (exactly IMPLEMENTED_IDS without
## packs, so vanilla draws are unchanged). Pack hunters run the default chase behaviour on their own tuning.
static var DRAW_IDS: Array = _draw_ids()


static func _draw_ids() -> Array:
	var ids := IMPLEMENTED_IDS.duplicate()
	ids.append_array(ContentRegistry.added_ids("hunters"))
	ids.make_read_only()
	return ids

## Complete letter roster in display/alphabet order. Keeping this explicit
## gives debug/admin tooling one canonical source rather than reconstructing
## A-Z from the weighted random pool (which intentionally excludes specials).
const A_Z_IDS := [
	"aki", "briselle", "ceryth", "dovelle", "elise", "ferryn", "glyra",
	"haelith", "ilyra", "javelle", "kathy", "loxelle", "mavrine", "nyxie",
	"opalie", "porcelle", "quenelle", "ravelle", "solyth", "thessine",
	"umbriel", "verrine", "wynelle", "xivvy", "ysolde", "zellia",
]
const VOID_IDS := [
	"void_black", "void_blue", "void_brown", "void_cyan", "void_gray",
	"void_green", "void_orange", "void_pink", "void_purple", "void_red",
	"void_white", "void_yellow",
]
## Office Mode's ten named signals mapped onto their maze hunter models. They
## join Infinite as rare incursions; after the route has durably admitted one
## hunter for every A-Z slot, later admissions raise their chance rather than
## replacing the ordinary roster wholesale.
const OFFICE_VOID_IDS := [
	"void_red", "void_blue", "void_yellow", "void_green", "void_pink",
	"void_orange", "void_purple", "void_white", "void_gray", "void_black",
]
const A_Z_ROSTER_SIZE := 26

## The glow attachment samples the same iris pixel displayed on the authored
## 8x8 Minecraft face (front-face UV x=10, y=14). Keeping this derived from the
## imported skin means palette edits in Blockbench automatically reach gameplay
## and avoids maintaining a second, easily stale list of 26 eye colours.
static var _eye_glow_color_cache := {}


static func eye_glow_color(id: String) -> Color:
	if not A_Z_IDS.has(id):
		return Color.WHITE
	if _eye_glow_color_cache.has(id):
		return _eye_glow_color_cache[id]
	var texture := load("res://art/props-3d/characters/%s_0.png" % id) as Texture2D
	var color := Color("d9f7ff")
	if texture != null:
		var image := texture.get_image()
		if image != null and image.get_width() > 10 and image.get_height() > 14:
			if image.is_compressed():
				image.decompress()
			color = image.get_pixel(10, 14)
			color.a = 1.0
	_eye_glow_color_cache[id] = color
	return color

## NORMAL_ROUTE_HUNTER_WEIGHTS from the original, plus Hard at the exact
## Standard/Nightmare midpoint. Nightmare's row is retained for its future
## implementation but cannot currently be selected in RoomState.
const TIER_WEIGHTS_BY_DIFFICULTY := {
	"relaxed": {"easy": 0.70, "intermediate": 0.25, "difficult": 0.05},
	"standard": {"easy": 0.35, "intermediate": 0.50, "difficult": 0.15},
	"hard": {"easy": 0.2625, "intermediate": 0.5125, "difficult": 0.225},
	"nightmare": {"easy": 0.175, "intermediate": 0.525, "difficult": 0.30},
}
## Kept as the Standard shorthand for callers/tests which only need a baseline.
const TIER_WEIGHTS := TIER_WEIGHTS_BY_DIFFICULTY["standard"]


## Hunter presentation. The cube ("blocky") models in assets/hunters_blocky/ (A-Z and Void, one
## shared rig, clips idle/walk/chase/sprint/crouch/stun/charge/flight/jumpscare) are what the game
## shows. Flip USE_BLOCKY to fall back to the older rigged models, and USE_SPRITES to show the flat
## 2D cutouts (A-Z only) instead of any 3D model.
const USE_BLOCKY := true
## Every humanoid hunter's model is drawn at this scale (1.5 = +50%): the body, the hit radius (GameConfig.HUNTER_RADIUS), the
## view collider and the stride reference speeds all follow it. The tall model variants are gone: this is the one size knob.
const MODEL_SCALE := 1.5
const BLOCKY_DIR := "res://assets/hunters_blocky/"
const USE_SPRITES := false
const SPRITE_DIR := "res://assets/sprites/hunters/"

## Chance that a given Kathy (or Umbriel disguised as her) carries the scythe: a rare, per-spawn
## roll, seeded by the hunter's own spawn seed so every peer of a route agrees. Otherwise she is
## unarmed and uses the normal clips.
const SCYTHE_CARRY_CHANCE := 0.125


## How a hunter treats the sewer under the maze (docs/SEWERS.md). "prefer": stalkers and ambushers who like the dark
## and the noise of the water -- they follow a runner down, drift down on their own and do not climb back up unless
## chasing. "avoid": hunters who will not go below -- they follow a runner to the ladder and wait at the top for them
## to come back up. Everyone not listed (the Void hunters included) "follow"s: down or up after a runner, never on her
## own. KT tunes these two lists.
const SEWER_PREFER := ["verrine", "umbriel", "wynelle", "glyra", "loxelle", "ravelle"]
const SEWER_AVOID := ["kathy", "ferryn", "solyth", "porcelle"]


static func sewer_affinity(id: String) -> String:
	if SEWER_PREFER.has(id):
		return "prefer"
	if SEWER_AVOID.has(id):
		return "avoid"
	return "follow"


## Scale for one hunter's presentation: humanoid hunters take MODEL_SCALE, secret creature rigs keep their authored size.
static func scale_for(id: String) -> float:
	return 1.0 if SecretCreatures.uses_creature_rig(id) else MODEL_SCALE


static func carries_scythe(spawn_seed_text: String) -> bool:
	if spawn_seed_text.is_empty():
		return false
	return SeededRandom.new("%s:SCYTHE" % spawn_seed_text).next_float() < SCYTHE_CARRY_CHANCE


static func get_identity(requested_id: String) -> Dictionary:
	var id := HunterIdAliases.canonical(requested_id)
	if not PROFILES.has(id) and SecretCreatures.has(id):
		return SecretCreatures.identity(id)
	var profile: Dictionary = PROFILES.get(id, PROFILES[DEFAULT_ID])
	var key: String = id if PROFILES.has(id) else DEFAULT_ID
	return {
		"id": key,
		"display_name": profile["name"],
		"base_speed": profile["speed"],
		"chase_speed": profile["chase"],
		"chase_progression_scale": profile["prog"],
		"sight_range": profile["sight"],
		"hearing_scale": profile["hearing"],
		"model_scene": _model_path(key, profile),
		"category": String(profile.get("category", "az")),
		"sprite_front": _sprite_path(key, "front"),
		"sprite_back": _sprite_path(key, "back"),
	}


## The blocky model when it exists for this hunter (and USE_BLOCKY is on), else the profile's own model.
static func _model_path(key: String, profile: Dictionary) -> String:
	if USE_BLOCKY:
		var blocky := "%s%s/%s.glb" % [BLOCKY_DIR, key, key]
		if ResourceLoader.exists(blocky):
			return blocky
	return String(profile.get("model", "res://art/props-3d/characters/%s.tscn" % key))


## "" when this hunter has no cutout (Void hunters) or sprites are switched off.
static func _sprite_path(key: String, side: String) -> String:
	if not USE_SPRITES or not A_Z_IDS.has(key):
		return ""
	var path := "%s%s-%s.png" % [SPRITE_DIR, key, side]
	return path if ResourceLoader.exists(path) else ""


static func office_void_for(seed_text: String) -> String:
	var rng := SeededRandom.new("%s:OFFICE-VOID" % seed_text)
	return OFFICE_VOID_IDS[rng.next_index(OFFICE_VOID_IDS.size())]


## A Void is an occasional additional pressure hunter, never a replacement for
## the ordinary route draw. Incursion probability rises slowly with depth and
## is capped so the mode remains a maze game rather than a permanent mob rush.
static func void_for_floor(seed_text: String, depth: int) -> String:
	var rng := SeededRandom.new("%s:VOID-IDENTITY:D%d" % [seed_text, maxi(1, depth)])
	return VOID_IDS[rng.next_index(VOID_IDS.size())]


static func has_void_incursion(seed_text: String, depth: int) -> bool:
	if depth < 2:
		return false
	var chance := minf(0.40, 0.08 + float(depth - 2) * 0.025)
	var rng := SeededRandom.new("%s:VOID-INCURSION:D%d" % [seed_text, depth])
	return rng.next_float() < chance


## Mirrors selectRouteHunters(): a tier-weighted seeded draw, keyed by
## seed+depth so a replayed run or descent draws the same hunter while a new
## one reshuffles, independently of the AI and facility RNG streams.
##
## The weights are over TIERS, and a tier with nobody implemented in it cannot
## be drawn -- so its weight is dropped and the rest renormalised, rather than
## the draw silently falling through to whoever happens to be first. That
## matters right now: the pool is a third of the roster, and unrenormalised
## weights would hand "difficult" a share of the draw far above its 0.15.
static func pick_for_floor(seed_text: String, depth: int,
		difficulty_id: String = "standard") -> String:
	var rng := SeededRandom.new("%s:HUNTER-LINEUP:D%d" % [seed_text, maxi(1, depth)])
	var weights: Dictionary = TIER_WEIGHTS_BY_DIFFICULTY.get(difficulty_id,
		TIER_WEIGHTS_BY_DIFFICULTY["standard"])
	var by_tier := {}
	for id in DRAW_IDS:
		var tier: String = PROFILES[id]["tier"]
		by_tier.get_or_add(tier, []).append(id)

	var total := 0.0
	for tier in by_tier:
		total += float(weights.get(tier, 0.0))
	if total <= 0.0:
		return DRAW_IDS[rng.next_index(DRAW_IDS.size())]

	# Walk the tiers in a fixed order: a Dictionary's iteration order follows
	# insertion, which follows DRAW_IDS, so it is stable -- but only by
	# accident. Sorting makes the draw depend on the seed alone.
	var tiers: Array = by_tier.keys()
	tiers.sort()
	var roll := rng.next_float() * total
	for tier in tiers:
		roll -= float(weights.get(tier, 0.0))
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
