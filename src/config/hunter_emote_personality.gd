class_name HunterEmotePersonality
extends RefCounted

## Which emotes a hunter prefers. A multiplier on the base chance of every emote of that kind (1 = default, 0 = never).
## Chosen from the hunter's dossier ability (HunterDossier): a stalker that always knows where you are does not taunt, a
## shy one fidgets, the music-box hunter hums. Hunters not listed use 1 for everything; Void hunters use VOID.
## `clip_overrides` lets a hunter play one of its personal emote clips (assets/hunters_blocky/emotes.json) for an emote.

const WEIGHTS := {
	# Kathy (persona sheet): a warm, protective big sister who watches everyone and speaks in short, calm, final lines. No mocking
	# (taunt/smug/dance 0), a rare quiet laugh, she watches (look around) and calls people to her (beckon), a warm wave.
	"kathy": {"taunt": 0.0, "smug": 0.0, "dance": 0.0, "laugh": .3, "stretch": .3, "yawn": .2, "hum": .4, "wave": 1.5,
		"beckon": 1.8, "point": 1.2, "look_around": 2.0, "shrug": .5, "victory": .3},
	"aki": {"stretch": 1.5, "wave": 1.5, "taunt": .2, "laugh": .3, "smug": .3},                    # shy
	# Ferryn (persona sheet): shy and jumpy, screams then apologises, stammers, never commanding or gloating. Startles hard (flinch),
	# shrugs apologetically, glances round nervously, a timid little wave; no taunt/laugh/smug/dance/hum, hardly points or beckons.
	"ferryn": {"taunt": 0.0, "laugh": 0.0, "hum": 0.0, "smug": 0.0, "dance": 0.0, "victory": 0.0, "stretch": .2, "yawn": .3,
		"point": .4, "beckon": .3, "look_around": 2.0, "shrug": 2.5, "wave": 1.0, "flinch": 2.5},
	"glyra": {"hum": 3.0, "dance": 2.0, "wave": .5},                                               # MUSIC-BOX PRESSURE
	"xivvy": {"dance": 2.0, "laugh": 2.0, "wave": 1.5, "shrug": .5},                               # playful flyer
	"loxelle": {"taunt": 1.5, "laugh": 1.5, "yawn": .5},                                           # PASSIVE INCINERATOR
	"ilyra": {"point": 0.0, "beckon": 0.0, "look_around": 1.5, "stretch": 0.0},                    # SHADOW POUNCE: still, watching
	"haelith": {"point": 2.0},                                                                     # RELAY PURSUER
	"jyvra": {"smug": 2.0, "taunt": 1.5},                                                          # HIDING EJECTION
	"briselle": {"laugh": 2.0, "smug": 1.5, "wave": .5},                                           # RELAY SABOTEUR
	"ceryth": {"look_around": 2.0, "taunt": 0.0},                                                  # HIDING RIDDLE
	"eirys": {"hum": 1.5, "stretch": 1.5},                                                         # RUNNING DATA
}
const VOID := {"laugh": 0.0, "hum": 0.0, "dance": 0.0, "wave": 0.0, "yawn": 0.0, "stretch": 0.0, "smug": .5}

## hunter id -> {emote id: personal clip}. Empty until the animation session adds clips worth wiring.
const CLIP_OVERRIDES := {
	"aki": {"stretch": "emote_shy"},
}


static func weight(hunter_id: String, emote_index: int) -> float:
	var id := String(HunterEmoteCatalog.entry(emote_index).get("id", ""))
	if id.is_empty():
		return 0.0
	var table: Dictionary = VOID if hunter_id.begins_with("void_") else WEIGHTS.get(hunter_id, {})
	return float(table.get(id, 1.0))


static func clip_override(hunter_id: String, emote_index: int) -> String:
	var id := String(HunterEmoteCatalog.entry(emote_index).get("id", ""))
	return String((CLIP_OVERRIDES.get(hunter_id, {}) as Dictionary).get(id, ""))
