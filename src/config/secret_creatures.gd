class_name SecretCreatures
extends RefCounted

## The City's secret creature(s). Deliberately NOT in HunterRoster.PROFILES: everything that walks PROFILES (dossier
## counters, undiscovered-signal rows, random draws, validators' "38 hunters") must never learn this id exists, so
## it lives here and is reached through three narrow fallbacks (get_identity, gimmick lookup, death lines) plus the
## admin hunter picker. Design and tuning knobs: docs/SECRET_WOLF_SPIDER.md.

const WHITE_WOLF_SPIDER := "white_wolf_spider"
const IDS := [WHITE_WOLF_SPIDER]

## Working name: no canon identity exists for it in the lore repo or the archives (checked), so this is KT's to rename.
const PROFILES := {
	WHITE_WOLF_SPIDER: {
		"name": "White Wolf Spider", "tier": "secret", "category": "secret",
		# a fast ambusher: slow stalk, very fast burst, poor eyes, excellent ears (stats are config, tune freely)
		"speed": 0.95, "chase": 4.9, "prog": 0.0, "sight": 7.0, "hearing": 1.9, "spawn": 20,
		"model": "res://assets/city/white_wolf_spider/white_wolf_spider.glb", "rig": "creature",
	},
}

## Collision capsule of the creature body (radius, height in metres): deliberately slim, like every hunter's, so the
## presentation body is never held up by a doorway the grid navigation already let it through (its legs sprawl wider).
const BODY_RADIUS := 0.36
const BODY_HEIGHT := 1.2
## Chance-free, in-world trigger (see CitySecrets): "garden_vigil" or "fountains". "off" disables the spawn entirely.
const TRIGGER := "garden_vigil"

## Shown in the dossier only AFTER the player has met it. Placeholder wording for KT.
const DOSSIER := {
	WHITE_WOLF_SPIDER: {
		"ability": "[PLACEHOLDER] AMBUSH STALKER",
		"behavior": "[PLACEHOLDER] It lurks where the city is quiet, barks once to mark you, then runs you down. Shelters stop it.",
	},
}

## Death-moment lines (DeathLines reads these for a hunter id that is not in the JSON catalog). [PLACEHOLDER] lines only
## render in debug builds; a release build falls back to the generic copy until KT writes real ones. Style caption: it
## does not speak.
const DEATH := {
	"whitewolfspider": {
		"style": "caption",
		"lines": [
			"[PLACEHOLDER] (a dry clicking of legs, very close, then nothing)",
			"[PLACEHOLDER] (a single low bark echoes down the street)",
		],
	},
}


static func has(id: String) -> bool:
	return PROFILES.has(id)


static func profile(id: String) -> Dictionary:
	return PROFILES.get(id, {})


static func uses_creature_rig(id: String) -> bool:
	return String(profile(id).get("rig", "")) == "creature"


## Same shape as HunterRoster.get_identity().
static func identity(id: String) -> Dictionary:
	var p := profile(id)
	return {
		"display_name": p["name"], "base_speed": p["speed"], "chase_speed": p["chase"],
		"chase_progression_scale": p["prog"], "sight_range": p["sight"], "hearing_scale": p["hearing"],
		"model_scene": String(p["model"]), "category": "secret", "sprite_front": "", "sprite_back": "",
	}


static func death_entry(file_id: String) -> Dictionary:
	return DEATH.get(file_id, {})


## The admin hunter picker lists these (admin tools only; nothing else enumerates them).
static func admin_ids() -> Array:
	return IDS.duplicate()


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


## True when the route's generator is the City (duck-typed: the City generator reports biome "city").
static func is_city_generator(generator) -> bool:
	if generator == null or not generator.has_method("biome_for"):
		return false
	return String(generator.biome_for(Vector3i.ZERO)) == "city"
