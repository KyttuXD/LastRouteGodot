class_name NightWatchDescentData
extends RefCounted

## The Descent's constants, copied from the 2D descent-data.js: the stages of each descent, how big each puzzle is, Elise's level and
## Zellia's script. Pure data; the rules are in descent_logic.gd.
##
## You ride an elevator down a shaft and repair it as you go. Each descent is a run of stages: wires (follow a lit fuse box's wire to its
## button), the signal panel (watch four pads light in turn and repeat the order) and pipes (turn the pieces until the line runs through).
## Elise waits outside the car and edges closer the longer you take, and every wrong attempt counts.

const CAST := ["elise"]
const NAMES := {"elise": "Elise"}
const PAN := {"elise": 0.4}
const DESCENTS := 5

## Her AI level per descent (0 keeps her away: the first descent is a walk-through).
const LEVELS := {"elise": [0, 5, 8, 11, 14]}

## Which stages each descent has (the order is drawn each time, the door hold stays last).
const RUNS := {
	1: ["wires"],
	2: ["wires", "memory"],
	3: ["wires", "memory", "pipes"],
	4: ["wires", "memory", "pipes", "hold"],
	5: ["wires", "memory", "pipes", "wires", "hold"],
}

## Per descent (index 0 to 4): wires lit / buttons, how long the signal sequence is, the pipe grid size, the most steps the hidden path
## may take up or left, and the most clicks any of its pieces needs.
const WIRES_LIT := [3, 3, 4, 4, 5]
const WIRES_BUTTONS := [4, 4, 5, 6, 6]
const MEMORY_LENGTH := [3, 3, 4, 4, 5]
const PIPES_GRID := [4, 4, 4, 5, 5]
const PIPES_DETOURS := [0, 0, 0, 1, 1]
const PIPES_TURNS := [2, 2, 2, 2, 2]

const STAGE_NAMES := {"wires": "FUSE BOXES", "memory": "SIGNAL PANEL", "pipes": "PIPEWORK", "hold": "DOOR"}

const CALLS := {
	1: {"at": 5, "lines": [
		"Zellia. The elevator needs its service run, and you'll be doing it from the car.",
		"Each stage has its own panel. The first is the fuse boxes: when one lights up, follow its wire to the button it ends at and press it.",
		"Nothing is out there tonight. Take your time.",
	]},
	2: {"at": 5, "lines": [
		"There's something outside the car this time. She comes closer the longer you take, and every wrong attempt makes it quicker.",
		"A new stage this run: the signal panel. Four pads light up one at a time. When they stop, press them in the same order.",
	]},
	3: {"at": 5, "lines": [
		"This run has pipes as well. Turn each piece until there's one clear line from IN to OUT. She slows down while you work the pipes, but she doesn't stop.",
		"Finish a stage and she drops back for a while. Get through them one at a time and don't linger.",
	]},
	4: {"at": 5, "lines": [
		"At the bottom she may try to get on. Hold the door shut until the car stops.",
		"Keep your wrong attempts down. They count for more now.",
	]},
	5: {"at": 5, "lines": [
		"This is the longest run. Everything's on it, and the wires have to be done twice.",
		"Stay steady. You've done each of these already.",
	]},
}


static func call_lines(descent: int) -> Array:
	return (CALLS[descent]["lines"] as Array).duplicate() if CALLS.has(descent) else []
