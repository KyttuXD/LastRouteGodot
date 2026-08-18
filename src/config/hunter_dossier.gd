class_name HunterDossier
extends RefCounted

## Player-facing descriptions of the mechanics which are live in this port.
## Keeping these separate from HunterRoster's tuning table makes the dossier a
## readable gameplay reference instead of turning simulation data into UI copy.
## Every roster id must have one entry; the validation scene enforces that.
const ENTRIES := {
	"aki": {
		"ability": "PHANTOM EXPOSURE",
		"behavior": "Holding the flashlight beam on Aki arms three delayed exposure bursts. Each burst makes every hunter on the floor much more likely to find you.",
		"counter": "Do not hold the beam on her unless you are ready for the delayed exposure spikes. Break sight and reach a safe zone while they pass.",
	},
	"briselle": {
		"ability": "RELAY SABOTEUR",
		"behavior": "Briselle can stop at a collected relay and take it offline, blocking the service lift until the relay is repaired.",
		"counter": "A sustained flashlight beam interrupts her sabotage. If she finishes, hold interact at the dark relay to restore it.",
	},
	"ceryth": {
		"ability": "HIDING RIDDLE",
		"behavior": "Ceryth claims one hiding spot and watches it. Red eyes demand darkness; blue eyes demand a live flashlight. A wrong answer locks you inside.",
		"counter": "Check her eye colour before entering the marked spot, then set the flashlight to the matching state. A correct answer disperses her.",
	},
	"dovelle": {
		"ability": "BASELINE PURSUER",
		"behavior": "Dovelle is the pure route hunter: she patrols, hears noise, follows sightings, searches your last known position and gives chase without a special rule.",
		"counter": "Control your noise, break line of sight, use safe zones and change direction after she loses you.",
	},
	"eirys": {
		"ability": "RUNNING DATA",
		"behavior": "Every second spent moving at a sprint outside safe zones permanently fills Eirys' hidden tracker. When full, she knows your position forever.",
		"counter": "Walk whenever the route is calm. Save sprinting for short escapes and use safe zones before the permanent lock is earned.",
	},
	"ferryn": {
		"ability": "ROUND STALKER",
		"behavior": "Ferryn always knows where you are and pursues without needing sight or sound. Driving her away with light creates a facility-wide noise spike.",
		"counter": "A hiding spot, safe zone or sustained beam sends her back to her origin. Be ready for other hunters to react when light repels her.",
	},
	"glyra": {
		"ability": "MUSIC-BOX PRESSURE",
		"behavior": "Glyra stays beside the spawn-room music box. When it unwinds, facility noise rises continuously and makes every active hunter more dangerous.",
		"counter": "Return to the music box and wind it before the timer expires. Winding also removes the noise Glyra added.",
	},
	"haelith": {
		"ability": "RELAY PURSUER",
		"behavior": "Haelith ignores ordinary patrol goals and continually heads toward the nearest uncollected relay, meeting runners at their objectives.",
		"counter": "Listen for her directional footsteps. Approach relays carefully, draw her away, then double back to collect them.",
	},
	"ilyra": {
		"ability": "SHADOW POUNCE",
		"behavior": "Ilyra watches from room corners. If she sees you and you then look away, she tags that moment and pounces after a delay to stun you.",
		"counter": "Sweep corners before committing to a room. A sustained flashlight beam banishes her temporarily instead of merely interrupting her.",
	},
	"jyvra": {
		"ability": "HIDING EJECTION",
		"behavior": "A hiding spot is not permanent safety from Jyvra. If she remains over your occupied spot long enough, she pulls you into the open.",
		"counter": "Leave after she loses the trail instead of waiting indefinitely. Use her brief post-ejection stall to create distance.",
	},
	"kathy": {
		"ability": "SEARCH BEAM",
		"behavior": "Kathy sees through a long cone projected along her facing, detecting runners well beyond ordinary hunter sight range when the path is clear.",
		"counter": "Stay behind walls and out of her forward cone. Safe zones and hiding spots still block the beam.",
	},
	"loxelle": {
		"ability": "PASSIVE INCINERATOR",
		"behavior": "While calm, Loxelle periodically burns a hiding spot in her current room. Empty spots recover later; occupied spots eject their runner.",
		"counter": "Do not depend on one locker. Keep her moving or chasing so her passive cannot settle into a burn cycle.",
	},
	"mavrine": {
		"ability": "LATTICE MARK",
		"behavior": "Mavrine pauses to project an invisible frame elsewhere in the facility. Crossing the armed cell tells her exactly where to investigate.",
		"counter": "Watch for her survey pause and avoid predictable central routes. A direct chase interrupts her setup cycle.",
	},
	"nyxie": {
		"ability": "DARKNESS STALKER",
		"behavior": "Nyxie is a rule-summoned second hunter. Extended darkness wakes her; a fully dead lamp eventually causes an inescapable attack.",
		"counter": "Keep the lamp charged and use it regularly. A live beam aimed directly at a timer-summoned Nyxie dispels her.",
	},
	"opalie": {
		"ability": "RELAY GUARDIAN",
		"behavior": "Opalie takes a relay station and suppresses every interaction nearby. Touching her guarded area also broadcasts your position to active hunters.",
		"counter": "Draw her away from the station before attempting the relay or nearby supplies. Do not repeatedly test the blocked interaction.",
	},
	"porcelle": {
		"ability": "RADAR-ONLY",
		"behavior": "Porcelle is invisible in the 3D route but remains fully active. Her moving position is visible as a hunter mark on the full facility map.",
		"counter": "Open the map often enough to track her, then move using that information. The minimap deliberately does not reveal hunters.",
	},
	"quirith": {
		"ability": "FLASHLIGHT TRACKER",
		"behavior": "Keeping the flashlight on too long lets Quirith lock permanently onto you. Repeated light toggles also increase her chase speed.",
		"counter": "Use short, deliberate bursts of light. Avoid panic-flicking the flashlight and retreat through safe zones if she locks on.",
	},
	"ravelle": {
		"ability": "DOORWAY TRIPWIRES",
		"behavior": "Ravelle arms invisible wires at doorway-shaped cells. Each wire crossed starts a chase and permanently compounds her speed for the floor.",
		"counter": "Change routes when a doorway triggers her. Repeatedly crossing the same trapped choke points makes later chases much worse.",
	},
	"solyth": {
		"ability": "HEAT MANIFEST",
		"behavior": "Solyth is a rule-summoned second hunter. Reaching maximum heat wakes her permanently and she begins destroying uncollected batteries over time.",
		"counter": "Manage temperature before it reaches the hard limit. Once summoned she cannot be cooled away, so preserve remaining batteries.",
	},
	"thessine": {
		"ability": "AUDIO MIMIC",
		"behavior": "At irregular ten-second checks, Thessine can replay an amplified cue from another active hunter or emit an uncanny false signal.",
		"counter": "Confirm sounds with the map and the room itself. Do not spend stamina or abandon an objective because of one isolated cue.",
	},
	"umbriel": {
		"ability": "SHAPESHIFTER",
		"behavior": "Umbriel regularly wears another hunter's model while keeping her own movement, senses and behaviour.",
		"counter": "Treat appearance as unreliable. Identify her by the way she moves and reacts rather than the model she is currently using.",
	},
	"verrine": {
		"ability": "VENT LURKER",
		"behavior": "Verrine is inert and unseen until a runner enters the vent network. Inside, she tracks perfectly and accelerates for as long as the traversal lasts.",
		"counter": "Use vents only with a clear exit plan. Move through quickly and leave the network before her speed ramp becomes overwhelming.",
	},
	"wynelle": {
		"ability": "COLD MATERIALIZER",
		"behavior": "Cold builds Wynelle's hidden progress until she materialises on the runner and starts a lethal freeze countdown.",
		"counter": "Use the heater station early. Thawing drives a manifested Wynelle away; fully powering the heater prevents her progress entirely.",
	},
	"xivvy": {
		"ability": "CHASE ACCELERATOR",
		"behavior": "Xivvy locks on at close range without sight or hearing and becomes faster the longer the same chase continues.",
		"counter": "Keep distance, break pursuit early and use safe zones. A long straight chase gives her exactly the advantage she wants.",
	},
	"ysolde": {
		"ability": "BATTERY THIEF",
		"behavior": "Ysolde seeks the nearest uncollected battery and removes it from the shared floor permanently before runners can reach it.",
		"counter": "Collect visible batteries promptly. Zephyra's pesticide temporarily stops Ysolde from pursuing supplies.",
	},
	"zephyra": {
		"ability": "COIN EXCHANGE",
		"behavior": "Zephyra settles near the facility centre as a harmless merchant. Coins can buy cooling, warmth, repairs or temporary pesticide.",
		"counter": "She cannot capture you. Bank coins and use the numbered offers when a temperature or hunter problem justifies the cost.",
	},
	"void_black": {"ability": "VOID INCURSION", "behavior": "Black Void can enter as an additional high-speed pursuer alongside the route's A-Z hunter.", "counter": "Treat the second chase signal as a separate hunter. Break sight early and do not assume losing one threat ended the pursuit."},
	"void_blue": {"ability": "VOID INCURSION", "behavior": "Blue Void can enter as an additional high-speed pursuer alongside the route's A-Z hunter.", "counter": "Preserve stamina for overlapping pursuit paths and use safe rooms to separate the hunters."},
	"void_brown": {"ability": "VOID INCURSION", "behavior": "Brown Void can enter as an additional high-speed pursuer alongside the route's A-Z hunter.", "counter": "Avoid narrow dead ends; its aggressive hearing makes noisy tool use especially dangerous."},
	"void_cyan": {"ability": "VOID INCURSION", "behavior": "Cyan Void can enter as an additional high-speed pursuer alongside the route's A-Z hunter.", "counter": "Move before the chase becomes a straight sprint; Void chase progression compounds quickly."},
	"void_gray": {"ability": "VOID INCURSION", "behavior": "Gray Void can enter as an additional long-sighted pursuer alongside the route's A-Z hunter.", "counter": "Use hard corners and region transitions; distance alone is unreliable against its sight range."},
	"void_green": {"ability": "VOID INCURSION", "behavior": "Green Void can enter as an additional high-speed pursuer alongside the route's A-Z hunter.", "counter": "Keep a quiet alternate route ready before committing to an objective or locked cache."},
	"void_orange": {"ability": "VOID INCURSION", "behavior": "Orange Void can enter as an additional extremely fast pursuer alongside the route's A-Z hunter.", "counter": "Do not race it down a straight hall. Turn, break sight and force a new path calculation."},
	"void_pink": {"ability": "VOID INCURSION", "behavior": "Pink Void can enter as an additional high-speed pursuer alongside the route's A-Z hunter.", "counter": "Confirm which hunter owns each sound and map mark before choosing an escape route."},
	"void_purple": {"ability": "VOID INCURSION", "behavior": "Purple Void can enter as an additional rapidly accelerating pursuer alongside the route's A-Z hunter.", "counter": "End pursuit quickly; a prolonged chase gives its progression scale the advantage."},
	"void_red": {"ability": "VOID INCURSION", "behavior": "Red Void can enter as the most aggressive baseline Void pursuer alongside the route's A-Z hunter.", "counter": "Use the environment immediately. It is intentionally too fast for a long open-footrace."},
	"void_white": {"ability": "VOID INCURSION", "behavior": "White Void can enter as an additional hearing-focused pursuer alongside the route's A-Z hunter.", "counter": "Walk and avoid unnecessary tool impacts until you know where the incursion spawned."},
	"void_yellow": {"ability": "VOID INCURSION", "behavior": "Yellow Void can enter as an additional fast, far-sighted pursuer alongside the route's A-Z hunter.", "counter": "Limit exposed crossings and reach a safe room before spending time on inventory management."},
}


static func sorted_ids() -> Array:
	var ids: Array = ENTRIES.keys()
	ids.sort_custom(func(a: String, b: String) -> bool:
		return String(HunterRoster.PROFILES[a]["name"]) < String(HunterRoster.PROFILES[b]["name"]))
	return ids


static func category_ids(category: String) -> Array:
	var ids: Array = []
	for hunter_id in ENTRIES:
		var profile: Dictionary = HunterRoster.PROFILES.get(hunter_id, {})
		var actual := String(profile.get("category", "az"))
		if actual == category:
			ids.append(hunter_id)
	ids.sort_custom(func(a: String, b: String) -> bool:
		return String(HunterRoster.PROFILES[a]["name"]) \
			< String(HunterRoster.PROFILES[b]["name"]))
	return ids


static func entry(hunter_id: String) -> Dictionary:
	return ENTRIES.get(hunter_id, {})
