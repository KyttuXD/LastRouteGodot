class_name BotAdapter
extends RefCounted

## One bot adapter per game (registered through GameRegistry's "playtest_bot" key, see PlaytestAdapters).
## The harness owns the loop: observe() -> decide() -> inject the returned act -> next physics frame.
## Coroutines (start_run, leave_run) may await the SceneTree; everything else is synchronous.

var game_id := ""
var tree: SceneTree
var rng := RandomNumberGenerator.new()
## Counters a scenario can read at the end (adapters add their own).
var stats := {}
## Notable events with time/position for the report ({"kind", "t", ...}).
var events: Array = []


func available() -> bool:
	return false


func describe() -> Dictionary:
	return {"game": game_id, "available": available()}


## Start a fresh run: params = {seed, difficulty, mode, debug}. Returns {"ok": bool, "error": String}.
func start_run(_params: Dictionary) -> Dictionary:
	return {"ok": false, "error": "%s has no playtest bot yet" % game_id}


## Add game fields to `obs` (already holding the base observation).
func observe(_scene: Node, _obs: Dictionary) -> void:
	pass


## Return the act dictionary for this frame (see PlaytestInput).
func decide(_obs: Dictionary, _delta: float) -> Dictionary:
	return {}


func run_over(_obs: Dictionary) -> bool:
	return false


## Leave the current run back to the game's menu / hub the way a player would.
func leave_run() -> void:
	pass


## Bring a finished run's end screen to the next state (restart); returns true when something was pressed.
func after_run_over(_obs: Dictionary) -> bool:
	return false


## Debug-run helpers (god mode, teleport...). Only reachable through the bridge when the run is a DEBUG RUN.
func admin(_name: String, _args: Dictionary) -> Dictionary:
	return {"ok": false, "error": "no admin helpers for %s" % game_id}


func add_event(kind: String, data: Dictionary = {}) -> void:
	var entry := {"kind": kind, "frame": Engine.get_physics_frames()}
	entry.merge(data, true)
	events.append(entry)
