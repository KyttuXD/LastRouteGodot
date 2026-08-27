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
		"gimmick_title": "LIGHT EATER",
		"gimmick_behavior": "Eats nearby light and creates moving dark pockets.",
	},
	"void_blue": {
		"ability": "VOID INCURSION",
		"behavior": "Blue can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "COLD TRAIL",
		"gimmick_behavior": "Leaves a cold trail which slows prolonged pursuit.",
	},
	"void_brown": {
		"ability": "VOID INCURSION",
		"behavior": "Brown can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "BARRIER BREAKER",
		"gimmick_behavior": "Specializes in boards and damaged barriers.",
	},
	"void_cyan": {
		"ability": "VOID INCURSION",
		"behavior": "Cyan can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "POWER INTERFERENCE",
		"gimmick_behavior": "Interferes with taser charge and powered tools.",
	},
	"void_gray": {
		"ability": "VOID INCURSION",
		"behavior": "Gray can enter as an additional long-sighted pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "UNOBSERVED PURSUIT",
		"gimmick_behavior": "Moves while unobserved and holds still under scrutiny.",
	},
	"void_green": {
		"ability": "VOID INCURSION",
		"behavior": "Green can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "TOXIC DENIAL",
		"gimmick_behavior": "Creates temporary toxic area denial.",
	},
	"void_orange": {
		"ability": "VOID INCURSION",
		"behavior": "Orange can enter as an additional extremely fast pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "BURST CHARGE",
		"gimmick_behavior": "Telegraphs a short, violent burst charge.",
	},
	"void_pink": {
		"ability": "VOID INCURSION",
		"behavior": "Pink can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "FALSE COMFORT",
		"gimmick_behavior": "Mimics safe-room light and comfort audio.",
	},
	"void_purple": {
		"ability": "VOID INCURSION",
		"behavior": "Purple can enter as an additional rapidly accelerating pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "DARK PHASE",
		"gimmick_behavior": "Short-phases between connected dark cells.",
	},
	"void_red": {
		"ability": "VOID INCURSION",
		"behavior": "Red can enter as the most aggressive baseline Void pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "BERSERK RESPONSE",
		"gimmick_behavior": "Berserks after taking tool damage.",
	},
	"void_white": {
		"ability": "VOID INCURSION",
		"behavior": "White can enter as an additional hearing-focused pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "SOUND HUNTER",
		"gimmick_behavior": "Nearly blind but exceptionally sensitive to noise.",
	},
	"void_yellow": {
		"ability": "VOID INCURSION",
		"behavior": "Yellow can enter as an additional fast, far-sighted pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "POWER CUT",
		"gimmick_behavior": "Disrupts powered lights and nearby switches.",
	},
}


static func has_entry(hunter_id: String) -> bool:
	return ENTRIES.has(hunter_id)


static func entry(hunter_id: String) -> Dictionary:
	if not ENTRIES.has(hunter_id):
		return {}
	return (ENTRIES[hunter_id] as Dictionary).duplicate(true)
