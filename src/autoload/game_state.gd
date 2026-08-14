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
var relays_collected: int = 0
var relay_target: int = 1


func start_new_run(seed_value: int = 0) -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	depth = 1
	score = 0
	start_floor()


func start_floor() -> void:
	relays_collected = 0


func descend() -> void:
	depth += 1
	start_floor()
