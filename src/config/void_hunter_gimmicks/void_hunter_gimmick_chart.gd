class_name VoidHunterGimmickChart
extends RefCounted

## Player-facing text for the Void roster's powers, as the dossier / lobby / pause menu show it. Each entry describes what the
## matching `src/game/hunter_gimmicks/void_*_gimmick.gd` actually does (numbers copied from those files): the game's Void
## abilities are canon, this chart follows them. Every Void now has its power.
const ENTRIES := {
	"void_black": {
		"behavior": "Black can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "This stalker moves 50% faster while you are not watching her. Facing her within 11 cells and with a clear line of sight stops her completely. Check behind you regularly, then use the pause to create distance.",
	},
	"void_blue": {
		"behavior": "Blue can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "This anomaly is invisible in the game view and on radar. Hitting her with the flashlight beam reveals her for 3.5 seconds and pushes her about six cells away. Flash likely approach routes frequently.",
	},
	"void_brown": {
		"behavior": "Brown can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "Every 18 seconds, this entity jams up to two hiding spots within nine cells of you. A jam lasts 20 seconds and never targets the spot you currently occupy. Change rooms if nearby hiding spots are unavailable.",
	},
	"void_cyan": {
		"behavior": "Cyan can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "If this hunter keeps clear line of sight to you for 2.5 seconds, she sends your exact position to every other active hunter. After a successful ping she has a 30-second cooldown. Break sight before the lock completes.",
	},
	"void_gray": {
		"behavior": "Gray can enter as an additional long-sighted pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "This entity stays dormant for 180 seconds after activation or collecting a relay, reduced to 120 seconds on Nightmare. When that grace ends, standing still in the open for 45 seconds starts five E-key prompts; Nightmare reduces the idle limit to 30 seconds. Each prompt allows 2.5 seconds, or 1.8 seconds on Nightmare. Completing all five keeps them dormant. Missing one makes her visible and starts a normal chase until another relay resets her.",
	},
	"void_green": {
		"behavior": "Green can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "Every 22 seconds, this hunter can enter the vent network and reappear about nine cells from you after a two-second delay. This relocation only occurs when she has enough distance to move through the network. Keep moving after she disappears.",
	},
	"void_orange": {
		"behavior": "Orange can enter as an additional fast pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "Every 26 seconds, this saboteur disables either the flashlight, climate controls, or radar for nine seconds. The selected system returns automatically. Move to a safe position and wait for the outage to end.",
	},
	"void_pink": {
		"behavior": "Pink can enter as an additional high-speed pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "She never attacks and cannot catch you. Every 11 seconds she has a 60% chance to send a FOOTSTEPS // SOMEWHERE CLOSE cue.",
	},
	"void_purple": {
		"behavior": "Purple can enter as an additional fast-ramping pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "Every 21 seconds, this entity adds radar static for eight seconds. Each corruption has a 35% chance to make the radar completely black for 11 seconds. Radar returns automatically; use the game view until it does.",
	},
	"void_red": {
		"behavior": "Red can enter as the fastest baseline Void pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "This speedster moves at 155% speed in corridors and 78% speed inside rooms. Leave long hallways and cut through rooms whenever she begins chasing.",
	},
	"void_white": {
		"behavior": "White can enter as an additional hearing-focused pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "This hunter moves 35% faster unless your flashlight beam is directly hitting her. A beam within 10 cells stops her completely. Hold the beam long enough to create distance, but watch your remaining battery charge.",
	},
	"void_yellow": {
		"behavior": "Yellow can enter as an additional fast, far-sighted pursuer alongside the route's A-Z hunter.",
		"gimmick_behavior": "This hunter gains 6% movement speed for every second the full-screen map remains open, up to 70% faster. The increase lasts for the run. Use the map only in short checks.",
	},
}


static func has_entry(hunter_id: String) -> bool:
	return ENTRIES.has(hunter_id)


static func entry(hunter_id: String) -> Dictionary:
	if not ENTRIES.has(hunter_id):
		return {}
	return (ENTRIES[hunter_id] as Dictionary).duplicate(true)
