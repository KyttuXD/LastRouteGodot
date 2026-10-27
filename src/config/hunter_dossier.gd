class_name HunterDossier
extends RefCounted

const VOID_GIMMICK_CHART := preload(
	"res://src/config/void_hunter_gimmicks/void_hunter_gimmick_chart.gd")

## Player-facing descriptions of the mechanics which are live in this port.
## Keeping these separate from HunterRoster's tuning table makes the dossier a
## readable gameplay reference instead of turning simulation data into UI copy.
## Every roster id must have one entry; the validation scene enforces that.
const ENTRIES := {
	"aki": {
		"ability": "PHANTOM EXPOSURE",
		"behavior": "Holding the flashlight beam on Aki arms three delayed exposure bursts. Each burst makes every hunter on the floor much more likely to find you.",
	},
	"briselle": {
		"ability": "RELAY SABOTEUR",
		"behavior": "Briselle can stop at a collected relay and take it offline, blocking the service lift until the relay is repaired.",
	},
	"ceryth": {
		"ability": "HIDING RIDDLE",
		"behavior": "Ceryth claims one hiding spot and watches it. Red eyes demand darkness; blue eyes demand a live flashlight. A wrong answer locks you inside.",
	},
	"dovelle": {
		"ability": "BASELINE PURSUER",
		"behavior": "Dovelle is the pure route hunter: she patrols, hears noise, follows sightings, searches your last known position and gives chase without a special rule.",
	},
	"eirys": {
		"ability": "RUNNING DATA",
		"behavior": "Every second spent moving at a sprint outside safe zones permanently fills Elise' hidden tracker. When full, she knows your position forever.",
	},
	"ferryn": {
		"ability": "ROUND STALKER",
		"behavior": "Ferryn always knows where you are and pursues without needing sight or sound. Driving her away with light creates a facility-wide noise spike.",
	},
	"glyra": {
		"ability": "MUSIC-BOX PRESSURE",
		"behavior": "Glyra stays beside the spawn-room music box. When it unwinds, facility noise rises continuously and makes every active hunter more dangerous.",
	},
	"haelith": {
		"ability": "RELAY PURSUER",
		"behavior": "Haelith ignores ordinary patrol goals and continually heads toward the nearest uncollected relay, meeting runners at their objectives.",
	},
	"ilyra": {
		"ability": "SHADOW POUNCE",
		"behavior": "Ilyra watches from room corners. If she sees you and you then look away, she tags that moment and pounces after a delay to stun you.",
	},
	"jyvra": {
		"ability": "HIDING EJECTION",
		"behavior": "A hiding spot is not permanent safety from Javelle. If she remains over your occupied spot long enough, she pulls you into the open.",
	},
	"kathy": {
		"ability": "SEARCH BEAM",
		"behavior": "Kathy sees through a long cone projected along her facing, detecting runners well beyond ordinary hunter sight range when the path is clear.",
	},
	"loxelle": {
		"ability": "PASSIVE INCINERATOR",
		"behavior": "While calm, Loxelle periodically burns a hiding spot in her current room. Empty spots recover later; occupied spots eject their runner.",
	},
	"mavrine": {
		"ability": "LATTICE MARK",
		"behavior": "Mavrine pauses to project an invisible frame elsewhere in the facility. Crossing the armed cell tells her exactly where to investigate.",
	},
	"nyxie": {
		"ability": "DARKNESS STALKER",
		"behavior": "Nyxie is a rule-summoned second hunter. Extended darkness wakes her; a fully dead lamp eventually causes an inescapable attack.",
	},
	"opalie": {
		"ability": "RELAY GUARDIAN",
		"behavior": "Opalie takes a relay station and suppresses every interaction nearby. Touching her guarded area also broadcasts your position to active hunters.",
	},
	"porcelle": {
		"ability": "RADAR TRACKED",
		"behavior": "Porcelle remains visible in the route, and her moving position is also exposed as a hunter mark on the full facility map.",
	},
	"quirith": {
		"ability": "FLASHLIGHT TRACKER",
		"behavior": "Keeping the flashlight on too long lets Quenelle lock permanently onto you. Repeated light toggles also increase her chase speed.",
	},
	"ravelle": {
		"ability": "DOORWAY TRIPWIRES",
		"behavior": "Ravelle arms invisible wires at doorway-shaped cells. Each wire crossed starts a chase and permanently compounds her speed for the floor.",
	},
	"solyth": {
		"ability": "HEAT MANIFEST",
		"behavior": "Solyth is a rule-summoned second hunter. Reaching maximum heat wakes her permanently and she begins destroying uncollected batteries over time.",
	},
	"thessine": {
		"ability": "AUDIO MIMIC",
		"behavior": "At irregular ten-second checks, Thessine can replay an amplified cue from another active hunter or emit an uncanny false signal.",
	},
	"umbriel": {
		"ability": "SHAPESHIFTER",
		"behavior": "Umbriel regularly wears another hunter's model while keeping her own movement, senses and behaviour.",
	},
	"verrine": {
		"ability": "VENT LURKER",
		"behavior": "Verrine is inert and unseen until a runner enters the vent network. Inside, she tracks perfectly and accelerates for as long as the traversal lasts.",
	},
	"wynelle": {
		"ability": "COLD MATERIALIZER",
		"behavior": "Cold builds Wynelle's hidden progress until she materialises on the runner and starts a lethal freeze countdown.",
	},
	"xivvy": {
		"ability": "CHASE ACCELERATOR",
		"behavior": "Xivvy locks on at close range without sight or hearing and becomes faster the longer the same chase continues.",
	},
	"ysolde": {
		"ability": "BATTERY THIEF",
		"behavior": "Ysolde seeks the nearest uncollected battery and removes it from the shared floor permanently before runners can reach it.",
	},
	"zephyra": {
		"ability": "COIN EXCHANGE",
		"behavior": "Zellia settles near the facility centre as a harmless merchant. Coins can buy cooling, warmth, repairs or temporary pesticide.",
	},
}


static func sorted_ids() -> Array:
	var ids: Array = []
	for hunter_id in HunterRoster.PROFILES:
		if not entry(String(hunter_id)).is_empty():
			ids.append(String(hunter_id))
	ids.sort_custom(func(a: String, b: String) -> bool:
		return String(HunterRoster.PROFILES[a]["name"]) < String(HunterRoster.PROFILES[b]["name"]))
	return ids


static func category_ids(category: String) -> Array:
	if category == "secret":
		return SecretCreatures.discovered_ids()   # listed only once met
	var ids: Array = []
	for hunter_id in HunterRoster.PROFILES:
		if entry(String(hunter_id)).is_empty():
			continue
		var profile: Dictionary = HunterRoster.PROFILES.get(hunter_id, {})
		var actual := String(profile.get("category", "az"))
		if actual == category:
			ids.append(hunter_id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return String(HunterRoster.PROFILES[a]["name"]) \
			< String(HunterRoster.PROFILES[b]["name"]))
	return ids


static func category_title(category: String) -> String:
	return "A-Z HUNTERS" if category == "az" else "VOID HUNTERS" if category == "void" else "FOUND"


static func profile(hunter_id: String) -> Dictionary:
	return HunterRoster.PROFILES.get(hunter_id, SecretCreatures.profile(hunter_id))


static func entry(hunter_id: String) -> Dictionary:
	if SecretCreatures.has(hunter_id):
		return SecretCreatures.dossier_entry(hunter_id)
	if VOID_GIMMICK_CHART.has_entry(hunter_id):
		return VOID_GIMMICK_CHART.entry(hunter_id)
	return ENTRIES.get(hunter_id, {})
