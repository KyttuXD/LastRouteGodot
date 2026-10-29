class_name HunterDossier
extends RefCounted

const VOID_GIMMICK_CHART := preload(
	"res://src/config/void_hunter_gimmicks/void_hunter_gimmick_chart.gd")

## Player-facing descriptions of the mechanics which are live in this port.
## Keeping these separate from HunterRoster's tuning table makes the dossier a
## readable gameplay reference instead of turning simulation data into UI copy.
##
## ENTRIES is the 26 A-Z hunters only. The 12 Void hunters belong in the same
## dossier UI (lobby and pause, category "void"): their text is
## VoidHunterGimmickChart, and entry() returns that chart. Do not copy Void
## rows into this table. Every roster id must have one entry(); the roster
## suite enforces that, including the Void chart.
const ENTRIES := {
	"aki": {
		"behavior": "Flashing Aki with your flashlight triggers three delayed exposure surges. These attacks hit 10, 15, and 20 seconds after the flash, with each surge filling your exposure meter. Stun them only when necessary, and note that additional flashes will not trigger another attack sequence until the active cycle finishes.",
	},
	"briselle": {
		"behavior": "Briselle can stop at a collected relay and take it offline, blocking the service lift until the relay is repaired.",
	},
	"ceryth": {
		"behavior": "Ceryth ambushes from inside a hiding locker, marked by a dim red or blue light glowing around the frame. Match your flashlight state to enter safely: turn it OFF if the light is red, or keep it ON if the light is blue. Guessing correctly forces them to run off to another hiding spot without pursuing you; an incorrect entry locks you trapped inside for 30 seconds.",
	},
	"dovelle": {
		"behavior": "Dovelle follows standard hunter rules: patrolling hallways, investigating loud noises, and relentlessly chasing anyone in sight. When pursued, break line of sight around corners and duck into a hiding spot to lose their attention.",
	},
	"elise": {
		"behavior": "Elise tracks runner movement whenever you sprint. Accumulating a total of 50 seconds of running completely fills their tracker; once full, they permanently track your location and can reach you inside hiding spots. Walk or crouch to navigate without adding progress to the tracker.",
	},
	"ferryn": {
		"behavior": "Ferryn is completely cloaked except for glowing amber eyes that slowly follow you through the corridors. Ducking into hiding or stepping into a safe zone banishes them back to their origin room. Shining a flashlight beam into their eyes also forces a retreat, but their piercing shriek maxes out the noise meter and alerts every other active hunter to your position.",
	},
	"glyra": {
		"behavior": "Glyra follows the nearest music box. While it plays she wanders close by, humming, and leaves you alone unless you walk right up to her. When the tune slows and goes off-key she grows restless, stalks the halls and peeks round corners. When it stops, the humming stops too: she hunts fast until someone holds [E] to wind the box again.",
	},
	"haelith": {
		"behavior": "Rather than wandering aimlessly, Haelith marches directly toward the nearest uncollected relay on the floor. Heavy rhythmic footsteps echo loudly within nine cells. Rush to finish objectives before they arrive, or duck into nearby lockers to let them pass by safely.",
	},
	"ilyra": {
		"behavior": "Ilyra lurks motionless in dark room corners. If they spot you and subsequently lose visual contact, your position is marked and you will be stunned after 15 seconds; on Nightmare difficulty this stun triggers immediately. Hit them with a direct flashlight beam while spotted to banish them from the facility for 30 seconds.",
	},
	"javelle": {
		"behavior": "Javelle is an aggressive hunter who pursues runners on sight. If you duck into a locker while being chased and they camp outside for eight seconds, Javelle forcefully pulls you out and suffers a brief self-stun. Never overstay in a single hiding spot while they pace outside.",
	},
	"kathy": {
		"behavior": "Kathy sees through a long cone projected along her facing, detecting runners well beyond ordinary hunter sight range when the path is clear.",
	},
	"loxelle": {
		"behavior": "While calm, Loxelle scans their surroundings every five seconds and may smash nearby hiding spots. Broken lockers reconstruct after 30 seconds, or 60 on Nightmare. If they strike a hiding spot you currently occupy, it is instantly demolished, forcing you out, raising the room temperature by 30 degrees Fahrenheit, and leaving the hunter winded and stunned for 10 seconds.",
	},
	"mavrine": {
		"behavior": "Mavrine deploys glowing trip-scanner frames onto open floor tiles. A scanner frame is never placed on a safe zone, relay, hiding spot, or starting area. Stepping across a frame triggers an alert directly to your coordinates and disarms the sensor. Watch the floor tiles closely when navigating corridors.",
	},
	"nyxie": {
		"behavior": "Nyxie is a rule-summoned second hunter. Extended darkness wakes her; a fully dead lamp eventually brings a catch she can't miss.",
	},
	"opalie": {
		"behavior": "Opalie singles out an uncollected relay and establishes a defensive perimeter around it. You cannot collect that terminal while this guardian stands watch nearby. Attempting to tamper with the guarded objective sounds an alarm alerting every active hunter across the facility, so draw their guard away before attempting collection.",
	},
	"porcelle": {
		"behavior": "Porcelle stalks under optical camouflage, appearing almost invisible in direct view. However, their active trace is fully revealed on the full-screen map whenever facility radar remains functional. Consult your navigation map frequently to track their movement, then break line of sight and take cover.",
	},
	"quenelle": {
		"behavior": "Quenelle is hypersensitive to light sources. Leaving your flashlight on continuously for eight seconds grants them a permanent tracking lock on your position; this threshold drops to five seconds on Nightmare. After a lock is established, each time your lamp is turned on they surge with speed, moving up to 45% faster while illuminated. Pulse your light briefly rather than keeping it on.",
	},
	"ravelle": {
		"behavior": "Ravelle arms invisible wires at doorway-shaped cells. Each wire crossed starts a chase and permanently compounds her speed for the floor.",
	},
	"solyth": {
		"behavior": "Solyth is a rule-summoned second hunter. Reaching maximum heat wakes her permanently and she begins destroying uncollected batteries over time.",
	},
	"thessine": {
		"behavior": "Thessine deceives runners using audio acoustic playback. Every 10 seconds, there is a 50% chance they will replicate the signature audio cue of another active hunter, alongside an 8% chance to project a ghost auditory cue. They follow standard patrol and chase rules, so confirm acoustic contacts with visual sightings or radar before redirecting your path.",
	},
	"umbriel": {
		"behavior": "Umbriel regularly wears another hunter's model while keeping her own movement, senses and behaviour.",
	},
	"verrine": {
		"behavior": "When active, Verrine uses a connected maintenance shaft that links across four rooms. This stalker stays concealed until someone enters the shafts. Inside the ducts, they begin prowling at 40% movement speed and accelerate by 2.5% for every second spent inside, capping out at a frantic 240% maximum speed. Navigate swiftly through the duct network to escape back out into open hallways.",
	},
	"wynelle": {
		"behavior": "Cold builds Wynelle's hidden progress until she materialises on the runner and starts a lethal freeze countdown.",
	},
	"xivvy": {
		"behavior": "Xivvy locks on at close range without sight or hearing and becomes faster the longer the same chase continues.",
	},
	"ysolde": {
		"behavior": "Ysolde seeks the nearest uncollected battery and removes it from the shared floor permanently before runners can reach it.",
	},
	"zellia": {
		"behavior": "Stationed in the facility's central chamber, Zellia operates an interactive merchant stall. Players can trade collected coins for thermal regulation, equipment repairs, or temporary protection against passive threats. However, striking a deal carries a fatal risk: 2% on Relaxed, 5% on Standard, 7.5% on Hard, and 12% on Nightmare.",
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


static func entry(requested_id: String) -> Dictionary:
	var hunter_id := HunterIdAliases.canonical(requested_id)
	if SecretCreatures.has(hunter_id):
		return SecretCreatures.dossier_entry(hunter_id)
	if VOID_GIMMICK_CHART.has_entry(hunter_id):
		return VOID_GIMMICK_CHART.entry(hunter_id)
	return ENTRIES.get(hunter_id, {})


## The dossier text with the hunter's own name blanked, as the 2D file screen shows a locked entry.
static func redacted(hunter_id: String, text: String) -> String:
	var hunter_name := String(profile(HunterIdAliases.canonical(hunter_id)).get("name", ""))
	if hunter_name.is_empty():
		return text
	var out := text
	for form in [hunter_name, hunter_name.to_upper(), hunter_name.to_lower()]:
		out = out.replace(form, "\u2588".repeat(hunter_name.length()))
	return out


const PORTRAIT_DIR := "res://assets/ui/hunter_portraits/"
const SILHOUETTE := Color(0.02, 0.015, 0.03, 1.0)


## The dossier tile: the 2D Last Route portrait (96x96 pixel art), <PORTRAIT_DIR><id>.png. A hunter data file may name its own
## "portrait". (tools/look/hunter_portraits.tscn bakes 3D-model renders into assets/ui/hunter_portraits_3d/ as an unused alternative.) Null when the hunter has none.
static func portrait(hunter_id: String) -> Texture2D:
	var id := HunterIdAliases.canonical(hunter_id)
	var path := PORTRAIT_DIR + id + ".png"
	if ContentRegistry.has("hunters", id):
		path = String(ContentRegistry.get_def("hunters", id).get("portrait", path))
	if path.begins_with("user://"):
		return ContentRegistry.pack_texture(path)
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
