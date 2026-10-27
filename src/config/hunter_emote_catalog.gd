class_name HunterEmoteCatalog
extends RefCounted

## In-world hunter emotes: short personality moments (taunt after a sighting, a shrug after losing you, a yawn
## while patrolling...). Purely presentation: the host decides when one happens (HunterEmoter), the id travels in the
## ordinary hunter state, every peer plays it. The hunter keeps simulating; nothing here pauses pathing.
##
## The array index is the wire value (hunter state `emote`), so only ever APPEND. `clip` is the body clip the blocky
## rigs should carry (see docs/HUNTER_EMOTES.md for the spec the animation session builds); when a model lacks it the
## `fallbacks` (existing shared clips) are tried, then the emote is face-only (`face` is a BlockyFace expression).

const NONE := -1
## A hunter never starts two emotes closer together than this.
const GLOBAL_COOLDOWN := 8.0

const TAUNT := 0
const LAUGH := 1
const POINT := 2
const BECKON := 3
const SHRUG := 4
const LOOK_AROUND := 5
const SMUG := 6
const DANCE := 7
const FLINCH := 8
const STRETCH := 9
const YAWN := 10
const HUM := 11
const WAVE := 12
const VICTORY := 13

## id, label, clip (wanted), fallbacks (existing shared clips), face, seconds, noise (audio radius in metres, 0 = silent),
## moving: the clip may play while the hunter is walking/running (otherwise face-only while it moves).
const ENTRIES: Array[Dictionary] = [
	{"id": "taunt", "label": "Taunt", "clip": "emote_taunt", "fallbacks": [], "face": "scream", "seconds": 1.0,
		"noise": 0.0, "moving": true},
	{"id": "laugh", "label": "Laugh", "clip": "emote_laugh", "fallbacks": ["emote_cheer"], "face": "happy",
		"seconds": 1.6, "noise": 7.0, "moving": false},
	{"id": "point", "label": "Point", "clip": "emote_point", "fallbacks": [], "face": "chase", "seconds": 1.2,
		"noise": 0.0, "moving": true},
	{"id": "beckon", "label": "Beckon", "clip": "emote_beckon", "fallbacks": [], "face": "happy", "seconds": 1.4,
		"noise": 0.0, "moving": true},
	{"id": "shrug", "label": "Shrug", "clip": "emote_shrug", "fallbacks": [], "face": "blank", "seconds": 1.4,
		"noise": 0.0, "moving": false},
	{"id": "look_around", "label": "Look around", "clip": "emote_look_around", "fallbacks": [], "face": "derp",
		"seconds": 2.2, "noise": 0.0, "moving": false},
	{"id": "smug", "label": "Smug", "clip": "emote_smug", "fallbacks": ["emote_bow"], "face": "happy",
		"seconds": 2.2, "noise": 0.0, "moving": false},
	{"id": "dance", "label": "Dance", "clip": "emote_dance", "fallbacks": ["emote_cheer"], "face": "happy",
		"seconds": 3.0, "noise": 5.0, "moving": false},
	{"id": "flinch", "label": "Flinch", "clip": "emote_flinch", "fallbacks": [], "face": "stun", "seconds": 0.7,
		"noise": 0.0, "moving": false},
	{"id": "stretch", "label": "Stretch", "clip": "emote_stretch", "fallbacks": [], "face": "blink", "seconds": 2.0,
		"noise": 0.0, "moving": false},
	{"id": "yawn", "label": "Yawn", "clip": "emote_yawn", "fallbacks": [], "face": "blink", "seconds": 1.8,
		"noise": 0.0, "moving": false},
	{"id": "hum", "label": "Hum", "clip": "emote_hum", "fallbacks": [], "face": "happy", "seconds": 2.4,
		"noise": 4.0, "moving": false},
	{"id": "wave", "label": "Wave", "clip": "emote_wave", "fallbacks": [], "face": "happy", "seconds": 1.6,
		"noise": 0.0, "moving": false},
	{"id": "victory", "label": "Victory", "clip": "emote_victory", "fallbacks": ["emote_cheer"], "face": "happy",
		"seconds": 3.5, "noise": 0.0, "moving": false},
]

## Void hunters have no mouth or hands to speak of: the shared Void clips stand in.
const VOID_FALLBACKS := {
	"taunt": "emote_loom", "point": "emote_stare", "beckon": "emote_stare", "shrug": "emote_tilt",
	"look_around": "emote_tilt", "smug": "emote_loom", "flinch": "emote_twitch", "victory": "emote_loom",
}

## Trigger groups (see HunterEmoter for the rules and probabilities).
const GROUPS := {
	"spot": [TAUNT, LAUGH],
	"lose": [SHRUG],
	"search": [LOOK_AROUND],
	"chase": [POINT, BECKON],
	"catch": [SMUG, DANCE, LAUGH],
	"idle": [STRETCH, YAWN, HUM, WAVE],
	"wipe": [VICTORY],
	"stun": [FLINCH],
}


static func count() -> int:
	return ENTRIES.size()


static func valid(index: int) -> bool:
	return index >= 0 and index < ENTRIES.size()


static func index_of(id: String) -> int:
	for i in ENTRIES.size():
		if String(ENTRIES[i]["id"]) == id:
			return i
	return NONE


static func entry(index: int) -> Dictionary:
	return ENTRIES[index] if valid(index) else {}


static func label(index: int) -> String:
	return String(entry(index).get("label", ""))


static func face(index: int) -> String:
	return String(entry(index).get("face", "neutral"))


static func seconds(index: int) -> float:
	return float(entry(index).get("seconds", 1.5))


static func noise(index: int) -> float:
	return float(entry(index).get("noise", 0.0))


static func moving_ok(index: int) -> bool:
	return bool(entry(index).get("moving", false))


## The clip to play on this model for this emote, or "" when it has none (face-only).
## `player` is the model's AnimationPlayer; `personal_clip` an optional hunter-specific clip tried first.
static func resolve_clip(index: int, hunter_id: String, player: AnimationPlayer, personal_clip: String = "") -> String:
	if not valid(index) or player == null:
		return ""
	var candidates: Array = []
	if not personal_clip.is_empty():
		candidates.append(personal_clip)
	candidates.append(String(ENTRIES[index]["clip"]))
	if hunter_id.begins_with("void_") and VOID_FALLBACKS.has(String(ENTRIES[index]["id"])):
		candidates.append(String(VOID_FALLBACKS[String(ENTRIES[index]["id"])]))
	else:
		candidates.append_array(ENTRIES[index]["fallbacks"])
	for clip_name in candidates:
		if player.has_animation(String(clip_name)):
			return String(clip_name)
	return ""
