class_name SecretCreatures
extends RefCounted

## The Inferno's secret creatures: two variants of one species, a white and a black wolf spider. Deliberately NOT in HunterRoster.PROFILES: everything that walks PROFILES (dossier
## counters, undiscovered-signal rows, random draws, validators' "38 hunters") must never learn this id exists, so
## it lives here and is reached through three narrow fallbacks (get_identity, gimmick lookup, death lines) plus the
## admin hunter picker. Design and tuning knobs: docs/SECRET_WOLF_SPIDER.md.

const WHITE_WOLF_SPIDER := "white_wolf_spider"
const BLACK_WOLF_SPIDER := "black_wolf_spider"
const IDS := [WHITE_WOLF_SPIDER, BLACK_WOLF_SPIDER]

## Working name: no canon identity exists for it in the lore notes (checked), so it can be renamed.
const PROFILES := {
	WHITE_WOLF_SPIDER: {
		"name": "White Wolf Spider", "tier": "secret", "category": "secret",
		# a fast ambusher: slow stalk, very fast burst, poor eyes, excellent ears (stats are config, tune freely)
		"speed": 0.95, "chase": 4.9, "prog": 0.0, "sight": 7.0, "hearing": 1.9, "spawn": 20,
		"model": "res://assets/city/white_wolf_spider/white_wolf_spider.glb", "rig": "creature",
	},
	# the rarer, more dangerous variant: faster, hears and sees further, hunts longer, ignores flashlights (see its gimmick)
	BLACK_WOLF_SPIDER: {
		"name": "Black Wolf Spider", "tier": "secret", "category": "secret",
		"speed": 1.0, "chase": 5.4, "prog": 0.0, "sight": 8.5, "hearing": 2.1, "spawn": 22,
		"model": "res://assets/city/black_wolf_spider/black_wolf_spider.glb", "rig": "creature",
	},
}

## Collision capsule of the creature body (radius, height in metres): deliberately slim, like every hunter's, so the
## presentation body is never held up by a doorway the grid navigation already let it through (its legs sprawl wider).
const BODY_RADIUS := 0.36
const BODY_HEIGHT := 1.2
## The home level: the Inferno (level -3, SewerRouteGenerator.INFERNO_LEVEL). They spawn there, roam and hunt there, and never take a ramp
## or a ladder off it (stays_home); the City they were first made for is archived.
const HOME_LEVEL := -3
## In-world trigger: "inferno" (the runner has spent InfernoSecrets.DWELL_SECONDS on level -3) or "off" (nothing ever spawns by itself: the
## creatures are fully built but only the admin hunter picker can summon them, on -3, for testing).
const TRIGGER := "inferno"
## How the two relate once the trigger fires: "difficulty" (the default choice: SOLO or PAIR depending on the game
## difficulty, see DIFFICULTY below) or one of the older fixed options, kept selectable behind this constant: "black_follows_white"
## (the first trigger brings the white one; the black one only comes for a runner who has met the white one, on a second trigger),
## "black_rare" (every trigger brings one creature: the black one 1 time in 4) or "pair" (both at once).
const RELATIONSHIP := "difficulty"
const BLACK_CHANCE := 0.25
## Admin picker entry that summons both at once (testing); never a real hunter id.
const PAIR_ID := "wolf_spider_pair"

## Solo or pair by difficulty (the real ids: GameConfig.DIFFICULTY_PROFILES / HunterRoster.TIER_WEIGHTS_BY_DIFFICULTY; "nightmare" exists
## in the table but cannot be selected yet). There is no separate "easy" / "intermediate": relaxed is the easy end, standard the middle.
## mode:
##   white_solo      always the white one alone
##   solo_or_pair    `pair` chance of the pair (spawned together); otherwise one creature, the black one with chance `black_solo`
##   pair_likely     `pair` chance of the pair, where the BLACK ONE JOINS after the white one has noticed the runner (join_delay s later,
##                   from another side); otherwise solo as above
##   pair_always     always the pair, spawned together and COORDINATED: from opposite sides, the white one tells first (bark), the black one's
##                   hiss follows `stagger` s later, so it flanks while the white one barks
## knobs (multipliers on the creatures' own numbers): notice = sight range, chase = chase speed, rest = rest time after a hunt,
## alert = the distance at which a lurking creature marks a runner.
const DIFFICULTY := {
	"relaxed": {"mode": "white_solo", "pair": 0.0, "black_solo": 0.0, "join_delay": 0.0, "stagger": 0.0,
		"knobs": {"notice": 0.85, "chase": 0.92, "rest": 1.4, "alert": 0.85}},
	"standard": {"mode": "solo_or_pair", "pair": 0.10, "black_solo": 0.25, "join_delay": 0.0, "stagger": 1.8,
		"knobs": {"notice": 1.0, "chase": 1.0, "rest": 1.0, "alert": 1.0}},
	"hard": {"mode": "pair_likely", "pair": 0.70, "black_solo": 0.30, "join_delay": 3.0, "stagger": 1.8,
		"knobs": {"notice": 1.1, "chase": 1.05, "rest": 0.85, "alert": 1.1}},
	"nightmare": {"mode": "pair_always", "pair": 1.0, "black_solo": 0.0, "join_delay": 0.0, "stagger": 1.8,
		"knobs": {"notice": 1.2, "chase": 1.1, "rest": 0.7, "alert": 1.2}},
}
## A pair is never spawned on top of the runner: both creatures start at least SPAWN_MIN_DISTANCE away and
## the second one at least PAIR_MIN_GAP cells from the first, on another side for coordinated pairs.
const PAIR_MIN_GAP := 10.0
const PAIR_FLANK_DEGREES := 100.0

## Shown in the dossier only AFTER the player has met it. Placeholder wording.
const DOSSIER := {
	BLACK_WOLF_SPIDER: {
		"behavior": "[PLACEHOLDER] The darker kin of the white one: hisses instead of barking, ignores your light, and only a shelter or a hiding place stops it.",
	},
	WHITE_WOLF_SPIDER: {
		"behavior": "[PLACEHOLDER] It lurks where the city is quiet, barks once to mark you, then runs you down. Shelters stop it.",
	},
}

## Death-moment lines (DeathLines reads these for a hunter id that is not in the JSON catalog). [PLACEHOLDER] lines only
## render in debug builds; a release build falls back to the generic copy until real ones are written. Style caption: it
## does not speak.
const DEATH := {
	"blackwolfspider": {
		"style": "caption",
		"lines": [
			"[PLACEHOLDER] (a long dry hiss, very close, then the light goes out)",
			"[PLACEHOLDER] (legs on stone, quick and many, and then none)",
		],
	},
	"whitewolfspider": {
		"style": "caption",
		"lines": [
			"[PLACEHOLDER] (a dry clicking of legs, very close, then nothing)",
			"[PLACEHOLDER] (a single low bark echoes down the street)",
		],
	},
}


static func has(id: String) -> bool:
	return PROFILES.has(id) or id == PAIR_ID


static func pair_members() -> Array:
	return [WHITE_WOLF_SPIDER, BLACK_WOLF_SPIDER]


static func is_pair(id: String) -> bool:
	return id == PAIR_ID


static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, {})


static func uses_creature_rig(id: String) -> bool:
	return String(profile(id).get("rig", "")) == "creature"


## Same shape as HunterRoster.get_identity().
static func identity(id: String) -> Dictionary:
	if id == PAIR_ID:         # admin picker label only: it is never a brain
		return {"display_name": "Wolf Spider Pair (white + black)", "base_speed": 0.0, "chase_speed": 0.0, "chase_progression_scale": 0.0,
			"sight_range": 0.0, "hearing_scale": 0.0, "model_scene": "", "category": "secret"}
	var p := profile(id)
	return {
		"display_name": p["name"], "base_speed": p["speed"], "chase_speed": p["chase"],
		"chase_progression_scale": p["prog"], "sight_range": p["sight"], "hearing_scale": p["hearing"],
		"model_scene": String(p["model"]), "category": "secret",
	}


static func death_entry(file_id: String) -> Dictionary:
	return DEATH.get(file_id, {})


## The admin hunter picker lists these (admin tools only; nothing else enumerates them).
static func admin_ids() -> Array:
	var ids := IDS.duplicate()
	ids.append(PAIR_ID)
	return ids


## Which creatures, how they join and the tuning knobs for a route (deterministic from seed + difficulty; host-authoritative).
## -> {"ids": [white and/or black], "join": "now" | "after_bark", "join_delay": s, "stagger": s, "flank": bool, "knobs": {...}}
static func plan_for(difficulty_id: String, seed_text: String) -> Dictionary:
	var row: Dictionary = DIFFICULTY.get(difficulty_id, DIFFICULTY["standard"])
	var rng := SeededRandom.new("%s:SECRET-PLAN:%s" % [seed_text, difficulty_id])
	var roll_pair := rng.next_float()
	var roll_black := rng.next_float()
	var mode := String(row["mode"])
	var knobs: Dictionary = row["knobs"]
	var pair_roll := mode == "pair_always" or (mode in ["solo_or_pair", "pair_likely"] and roll_pair < float(row["pair"]))
	if pair_roll:
		return {"ids": [WHITE_WOLF_SPIDER, BLACK_WOLF_SPIDER], "knobs": knobs, "stagger": float(row["stagger"]),
			"join": "after_bark" if mode == "pair_likely" else "now", "join_delay": float(row["join_delay"]),
			"flank": mode in ["pair_always", "pair_likely"]}
	var solo_black := mode in ["solo_or_pair", "pair_likely"] and roll_black < float(row["black_solo"])
	return {"ids": [BLACK_WOLF_SPIDER] if solo_black else [WHITE_WOLF_SPIDER], "knobs": knobs, "stagger": 0.0, "join": "now",
		"join_delay": 0.0, "flank": false}


## Dossier categories to append to ["az", "void"]: "secret" only once something has been met.
static func dossier_categories() -> Array:
	return ["secret"] if not discovered_ids().is_empty() else []


static func discovered_ids() -> Array:
	var result := []
	for id in IDS:
		if Backend.hunter_discovered(String(id)):
			result.append(id)
	return result


static func dossier_entry(id: String) -> Dictionary:
	return DOSSIER.get(id, {})


## True for a secret creature that must never leave HOME_LEVEL (the route's ramp/ladder traffic skips it).
static func stays_home(id: String) -> bool:
	return IDS.has(id)


## Admin "pair" spawn: link the two creatures already on the route into one pack with the difficulty's knobs .
static func link_admin_pair(route, difficulty_id: String) -> void:
	var row: Dictionary = DIFFICULTY.get(difficulty_id, DIFFICULTY["standard"])
	var views := {}
	for view_value in (route._hunter_views as Dictionary).values():
		var view = view_value
		if view != null and view.brain != null and IDS.has(view.brain.hunter_id):
			views[view.brain.hunter_id] = view
	if views.size() < 2:
		return
	var pack := SpiderPack.new()
	for id in [WHITE_WOLF_SPIDER, BLACK_WOLF_SPIDER]:
		var gimmick := views[id].brain.gimmick as WhiteWolfSpiderGimmick
		if gimmick != null:
			gimmick.apply_knobs(views[id].brain, row["knobs"])
			pack.join(gimmick)
