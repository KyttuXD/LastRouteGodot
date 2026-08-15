class_name HunterRoster
extends RefCounted

## Per-hunter identity data: movement/perception tuning (kept in GameConfig,
## its established home for constants — this registry just points
## HunterBrain/HunterView3D at the right ones by id) plus the
## art/props-3d/characters/ scene ModelSlot loads for her. One entry per
## hunter whose AI is actually implemented — see MIGRATION.md's "Roster"
## milestone for the other 24.
##
## Adding a hunter: port her gimmick (a hook in hunter_brain.gd, following
## Quirith's `if hunter_id == "quirith":` pattern there — no plugin/subclass
## system exists, and with two wildly different gimmicks in the full roster
## it's premature to guess one), add her tuning consts to GameConfig, add
## her placeholder scene under art/props-3d/characters/, then add one entry
## to _identities() and her id to IMPLEMENTED_IDS below.

const DEFAULT_ID := "dovelle"

## Grows as more hunters are ported. The original's selectRouteHunters()
## weights a seeded draw across all 26 by difficulty tier; with only two
## implemented, a seeded uniform pick across just these two (see
## pick_for_floor below) is the honest equivalent for now — same spirit
## (seeded, replay-stable, reshuffles per descent), scaled to how much of
## the roster actually exists rather than faking tier weights for a
## two-hunter pool.
const IMPLEMENTED_IDS := [
	"dovelle", "quirith", "eirys", "xivvy", "kathy", "ravelle", "mavrine", "umbriel",
]


static func get_identity(id: String) -> Dictionary:
	var identities := _identities()
	return identities.get(id, identities[DEFAULT_ID])


## Mirrors selectRouteHunters()'s seeding: keyed by seed+depth so a replayed
## run/descent draws the same hunter, while a new run or a new depth
## reshuffles independently of the AI/facility RNG streams.
static func pick_for_floor(seed_text: String, depth: int) -> String:
	var rng := SeededRandom.new("%s:HUNTER-LINEUP:D%d" % [seed_text, maxi(1, depth)])
	return IMPLEMENTED_IDS[rng.next_index(IMPLEMENTED_IDS.size())]


static func _identities() -> Dictionary:
	return {
		"dovelle": {
			"display_name": "Dovelle",
			"base_speed": GameConfig.DOVELLE_BASE_SPEED,
			"chase_speed": GameConfig.DOVELLE_CHASE_SPEED,
			"chase_progression_scale": GameConfig.DOVELLE_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.DOVELLE_SIGHT_RANGE,
			"hearing_scale": GameConfig.DOVELLE_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/dovelle.tscn",
		},
		"quirith": {
			"display_name": "Quirith",
			"base_speed": GameConfig.QUIRITH_BASE_SPEED,
			"chase_speed": GameConfig.QUIRITH_CHASE_SPEED,
			"chase_progression_scale": GameConfig.QUIRITH_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.QUIRITH_SIGHT_RANGE,
			"hearing_scale": GameConfig.QUIRITH_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/quirith.tscn",
		},
		"eirys": {
			"display_name": "Eirys",
			"base_speed": GameConfig.EIRYS_BASE_SPEED,
			"chase_speed": GameConfig.EIRYS_CHASE_SPEED,
			"chase_progression_scale": GameConfig.EIRYS_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.EIRYS_SIGHT_RANGE,
			"hearing_scale": GameConfig.EIRYS_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/eirys.tscn",
		},
		"xivvy": {
			"display_name": "Xivvy",
			"base_speed": GameConfig.XIVVY_BASE_SPEED,
			"chase_speed": GameConfig.XIVVY_CHASE_SPEED,
			"chase_progression_scale": GameConfig.XIVVY_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.XIVVY_SIGHT_RANGE,
			"hearing_scale": GameConfig.XIVVY_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/xivvy.tscn",
		},
		"kathy": {
			"display_name": "Kathy",
			"base_speed": GameConfig.KATHY_BASE_SPEED,
			"chase_speed": GameConfig.KATHY_CHASE_SPEED,
			"chase_progression_scale": GameConfig.KATHY_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.KATHY_SIGHT_RANGE,
			"hearing_scale": GameConfig.KATHY_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/kathy.tscn",
		},
		"ravelle": {
			"display_name": "Ravelle",
			"base_speed": GameConfig.RAVELLE_BASE_SPEED,
			"chase_speed": GameConfig.RAVELLE_CHASE_SPEED,
			"chase_progression_scale": GameConfig.RAVELLE_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.RAVELLE_SIGHT_RANGE,
			"hearing_scale": GameConfig.RAVELLE_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/ravelle.tscn",
		},
		"mavrine": {
			"display_name": "Mavrine",
			"base_speed": GameConfig.MAVRINE_BASE_SPEED,
			"chase_speed": GameConfig.MAVRINE_CHASE_SPEED,
			"chase_progression_scale": GameConfig.MAVRINE_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.MAVRINE_SIGHT_RANGE,
			"hearing_scale": GameConfig.MAVRINE_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/mavrine.tscn",
		},
		"umbriel": {
			"display_name": "Umbriel",
			"base_speed": GameConfig.UMBRIEL_BASE_SPEED,
			"chase_speed": GameConfig.UMBRIEL_CHASE_SPEED,
			"chase_progression_scale": GameConfig.UMBRIEL_CHASE_PROGRESSION_SCALE,
			"sight_range": GameConfig.UMBRIEL_SIGHT_RANGE,
			"hearing_scale": GameConfig.UMBRIEL_HEARING_SCALE,
			"model_scene": "res://art/props-3d/characters/umbriel.tscn",
		},
	}
