extends Node

## Project-wide run state. Keep moment-to-moment simulation inside gameplay nodes.

enum GameMode {
	LAST_ROUTE,
	HIDE_AND_SEEK,
	OFFICE_SURVIVOR,
}

var current_mode: GameMode = GameMode.LAST_ROUTE
var depth: int = 1
var run_seed: int = 0
var score: int = 0


func start_new_run(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	depth = 1
	score = 0


func descend() -> void:
	depth += 1

