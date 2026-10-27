class_name VoidHunterGimmickChart
extends RefCounted

## Player-facing text for the Void roster's powers, as the dossier / lobby / pause menu show it. Each entry describes what the
## matching `src/game/hunter_gimmicks/void_*_gimmick.gd` actually does (numbers copied from those files): the game's Void
## abilities are canon, this chart follows them. Every Void now has its power.
const ENTRIES := {
	"void_black": {
		"ability": "VOID INCURSION",
		"behavior": "Black can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "REAR STALKER",
		"gimmick_behavior": "Freezes while you are looking at her (within 11 cells, in your view, clear line) and moves 1.5x faster whenever you are not watching.",
	},
	"void_blue": {
		"ability": "VOID INCURSION",
		"behavior": "Blue can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "SILENT STALKER",
		"gimmick_behavior": "Invisible and off the maps unless revealed. Shining your torch on her (12 cells) shoves her back 6 cells and shows her for 3.5 seconds.",
	},
	"void_brown": {
		"ability": "VOID INCURSION",
		"behavior": "Brown can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "SPOT JAMMER",
		"gimmick_behavior": "Every 18 seconds she jams up to two hiding spots within 9 cells of you shut for 20 seconds. The spot you are hiding in is never jammed.",
	},
	"void_cyan": {
		"ability": "VOID INCURSION",
		"behavior": "Cyan can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "SIGNAL PING",
		"gimmick_behavior": "If she keeps you in sight for 2.5 seconds she broadcasts your exact position, so every other active hunter investigates it, then she waits 30 seconds.",
	},
	"void_gray": {
		"ability": "VOID INCURSION",
		"behavior": "Gray can enter as an additional long-sighted pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "SIGNAL ROUTE",
		"gimmick_behavior": "Dormant (unseen and uncatchable) while relays keep coming: her grace window is 180 seconds (120 on Nightmare) and restarts at every relay. After that, standing still in the open for 45 seconds (30 on Nightmare) opens a signal route: press E five times, 2.5 seconds per press (1.8 on Nightmare). Missing one shows her and starts a normal chase, light or no light, until the next relay resets her.",
	},
	"void_green": {
		"ability": "VOID INCURSION",
		"behavior": "Green can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "VENT RELOCATE",
		"gimmick_behavior": "Every 22 seconds, if she is at least 14 cells away, she sinks out of sight for 2 seconds (still, unable to grab), then climbs out 9 cells from you and investigates.",
	},
	"void_orange": {
		"ability": "VOID INCURSION",
		"behavior": "Orange can enter as an additional fast pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "SYSTEM SABOTEUR",
		"gimmick_behavior": "Every 26 seconds she takes one of your systems offline for 9 seconds, chosen at random: the flashlight (forced off), the climate control (the heater goes off) or the radar (the minimap and map go black). It comes back by itself.",
	},
	"void_pink": {
		"ability": "VOID INCURSION",
		"behavior": "Pink can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "FALSE SIGNAL",
		"gimmick_behavior": "She never attacks and cannot catch you. Every 11 seconds she has a 60% chance to send a FOOTSTEPS // SOMEWHERE CLOSE cue.",
	},
	"void_purple": {
		"ability": "VOID INCURSION",
		"behavior": "Purple can enter as an additional fast-ramping pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "RADAR CORRUPTER",
		"gimmick_behavior": "Every 21 seconds she dusts your radar with static for 8 seconds. Each corruption has a 35% chance to black the radar out completely for 11 seconds instead. Use the game view until it returns.",
	},
	"void_red": {
		"ability": "VOID INCURSION",
		"behavior": "Red can enter as the fastest baseline Void pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "HALL RUNNER",
		"gimmick_behavior": "1.55x faster in hallways and 0.78x slower inside rooms.",
	},
	"void_white": {
		"ability": "VOID INCURSION",
		"behavior": "White can enter as an additional hearing-focused pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "LIGHT FROZEN",
		"gimmick_behavior": "Freezes while your lit torch is on her (within 10 cells) and moves 1.35x faster in the dark. Her hearing is the sharpest of the Voids.",
	},
	"void_yellow": {
		"ability": "VOID INCURSION",
		"behavior": "Yellow can enter as an additional fast, far-sighted pursuer alongside the route's A-Z hunter.",
		"gimmick_title": "MAP PRESSURE",
		"gimmick_behavior": "While your full-screen map is open her speed grows 0.06 per second up to 1.7x, and it stays for the rest of the route.",
	},
}


static func has_entry(hunter_id: String) -> bool:
	return ENTRIES.has(hunter_id)


static func entry(hunter_id: String) -> Dictionary:
	if not ENTRIES.has(hunter_id):
		return {}
	return (ENTRIES[hunter_id] as Dictionary).duplicate(true)
