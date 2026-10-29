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

## Zellia's calls are the shared table (NightWatchCallsData, mode `descent`), verbatim from the 2D descent-data.js.
