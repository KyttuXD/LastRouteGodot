class_name VoidHunterGimmickChart
extends RefCounted

## Design-chart entries for the Void roster. These are not claims that each
## colour's bespoke mechanic is already authoritative in gameplay; they are the
## intended identities surfaced in the in-game dossier so the chart is no
## longer trapped in HUNTER_ROSTER.md alone.
const ENTRIES := {
	"void_black": {
		"ability": "VOID INCURSION",
		"behavior": "Black can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"counter": "Treat the second chase signal as a separate hunter. Break sight early and do not assume losing one threat ended the pursuit.",
		"gimmick_title": "LIGHT EATER",
		"gimmick_behavior": "Eats nearby light and creates moving dark pockets.",
		"gimmick_counter": "Carry reserve light and leave the drained region.",
	},
	"void_blue": {
		"ability": "VOID INCURSION",
		"behavior": "Blue can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"counter": "Preserve stamina for overlapping pursuit paths and use safe rooms to separate the hunters.",
		"gimmick_title": "COLD TRAIL",
		"gimmick_behavior": "Leaves a cold trail which slows prolonged pursuit.",
		"gimmick_counter": "Take warmer biome routes and avoid retracing it.",
	},
	"void_brown": {
		"ability": "VOID INCURSION",
		"behavior": "Brown can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"counter": "Avoid narrow dead ends; its aggressive hearing makes noisy tool use especially dangerous.",
		"gimmick_title": "BARRIER BREAKER",
		"gimmick_behavior": "Specializes in boards and damaged barriers.",
		"gimmick_counter": "Do not rely on a single barricaded choke point.",
	},
	"void_cyan": {
		"ability": "VOID INCURSION",
		"behavior": "Cyan can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"counter": "Move before the chase becomes a straight sprint; Void chase progression compounds quickly.",
		"gimmick_title": "POWER INTERFERENCE",
		"gimmick_behavior": "Interferes with taser charge and powered tools.",
		"gimmick_counter": "Use mechanical tools or fire the taser early.",
	},
	"void_gray": {
		"ability": "VOID INCURSION",
		"behavior": "Gray can enter as an additional long-sighted pursuer alongside the route's A-Z hunter.",
		"counter": "Use hard corners and region transitions; distance alone is unreliable against its sight range.",
		"gimmick_title": "UNOBSERVED PURSUIT",
		"gimmick_behavior": "Moves while unobserved and holds still under scrutiny.",
		"gimmick_counter": "Coordinate sightlines instead of fleeing alone.",
	},
	"void_green": {
		"ability": "VOID INCURSION",
		"behavior": "Green can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"counter": "Keep a quiet alternate route ready before committing to an objective or locked cache.",
		"gimmick_title": "TOXIC DENIAL",
		"gimmick_behavior": "Creates temporary toxic area denial.",
		"gimmick_counter": "Rotate objectives before safe paths close.",
	},
	"void_orange": {
		"ability": "VOID INCURSION",
		"behavior": "Orange can enter as an additional extremely fast pursuer alongside the route's A-Z hunter.",
		"counter": "Do not race it down a straight hall. Turn, break sight and force a new path calculation.",
		"gimmick_title": "BURST CHARGE",
		"gimmick_behavior": "Telegraphs a short, violent burst charge.",
		"gimmick_counter": "Sidestep at the cue and force a wall impact.",
	},
	"void_pink": {
		"ability": "VOID INCURSION",
		"behavior": "Pink can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"counter": "Confirm which hunter owns each sound and map mark before choosing an escape route.",
		"gimmick_title": "FALSE COMFORT",
		"gimmick_behavior": "Mimics safe-room light and comfort audio.",
		"gimmick_counter": "Verify a safe-room marker before committing.",
	},
	"void_purple": {
		"ability": "VOID INCURSION",
		"behavior": "Purple can enter as an additional rapidly accelerating pursuer alongside the route's A-Z hunter.",
		"counter": "End pursuit quickly; a prolonged chase gives its progression scale the advantage.",
		"gimmick_title": "DARK PHASE",
		"gimmick_behavior": "Short-phases between connected dark cells.",
		"gimmick_counter": "Keep multiple exits and avoid isolated rooms.",
	},
	"void_red": {
		"ability": "VOID INCURSION",
		"behavior": "Red can enter as the most aggressive baseline Void pursuer alongside the route's A-Z hunter.",
		"counter": "Use the environment immediately. It is intentionally too fast for a long open-footrace.",
		"gimmick_title": "BERSERK RESPONSE",
		"gimmick_behavior": "Berserks after taking tool damage.",
		"gimmick_counter": "Stun to escape, not to start a long fight.",
	},
	"void_white": {
		"ability": "VOID INCURSION",
		"behavior": "White can enter as an additional hearing-focused pursuer alongside the route's A-Z hunter.",
		"counter": "Walk and avoid unnecessary tool impacts until you know where the incursion spawned.",
		"gimmick_title": "SOUND HUNTER",
		"gimmick_behavior": "Nearly blind but exceptionally sensitive to noise.",
		"gimmick_counter": "Walk, close interactions quietly, avoid impacts.",
	},
	"void_yellow": {
		"ability": "VOID INCURSION",
		"behavior": "Yellow can enter as an additional fast, far-sighted pursuer alongside the route's A-Z hunter.",
		"counter": "Limit exposed crossings and reach a safe room before spending time on inventory management.",
		"gimmick_title": "POWER CUT",
		"gimmick_behavior": "Disrupts powered lights and nearby switches.",
		"gimmick_counter": "Carry a flashlight and restore circuits behind it.",
	},
}


static func has_entry(hunter_id: String) -> bool:
	return ENTRIES.has(hunter_id)


static func entry(hunter_id: String) -> Dictionary:
	if not ENTRIES.has(hunter_id):
		return {}
	return (ENTRIES[hunter_id] as Dictionary).duplicate(true)
