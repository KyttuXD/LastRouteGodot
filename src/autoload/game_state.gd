extends Node

## Project-wide run state. Keep moment-to-moment simulation inside gameplay nodes.

enum GameMode {
	LAST_ROUTE,
	HIDE_AND_SEEK,
	OFFICE_SURVIVOR,
}

const ROUTE_CHECKPOINT_SCHEMA := 1
const MAX_CHECKPOINT_DEPTH := 100_000
const MAX_CHECKPOINT_TOTAL := 2_000_000_000

var current_mode: GameMode = GameMode.LAST_ROUTE
var depth: int = 1
## Set the moment any admin tool is used: the run is a DEBUG RUN and records nothing (account progress,
## hunter discoveries). Cleared by a new run.
var debug_run := false
var run_seed: int = 0
var score: int = 0
var relays_collected: int = 0
var relay_target: int = 1
## Collected relays currently knocked offline by Briselle -- taken offline
## without being un-collected, matching the original's own split: hunter
## activation and chase speed stay driven by relays_collected (never
## decreases), while the lift gate reads "collected AND not sabotaged".
var relays_sabotaged: int = 0

## Zellia's economy. Per-RUN, not per-floor -- mirrors inventory.js's own
## coins field, which survives a descent the same way score does.
var coins: int = 0

## Capture/escape struggle. A successful struggle continues the run; a failed
## or inescapable capture ends it. The old difficulty-sized life/respawn pool
## was removed because it made captures and co-op runner state unreliable.
var game_over := false

var escape_active := false
var escape_hunter_id := ""
var escape_remaining := 0.0
var escape_duration := 0.0
var escape_progress := 0
var escape_required := 0
var escape_cooldown := 0.0
var escape_grace := 0.0
var escape_cooldown_scale := 1.0

## A checkpoint is queued from the account screen, then consumed exactly once
## by the next solo Last Route scene. Merely signing in never changes the run
## under a player, and co-op scenes never consume account progress.
var _pending_route_checkpoint: Dictionary = {}


func start_new_run(seed_value: int = 0, _difficulty_id: String = "standard") -> void:
	debug_run = false
	run_seed = seed_value if seed_value != 0 else randi()
	depth = 1
	score = 0
	coins = 0
	game_over = false
	escape_active = false
	escape_cooldown = 0.0
	escape_grace = 0.0
	escape_cooldown_scale = 1.0
	start_floor()


func start_floor() -> void:
	relays_collected = 0
	relays_sabotaged = 0


func descend() -> void:
	depth += 1
	start_floor()


func route_checkpoint(room_seed_text: String, map_scale: int,
		difficulty: int, difficulty_id: String) -> Dictionary:
	return {
		"schema": ROUTE_CHECKPOINT_SCHEMA,
		"kind": "last_route",
		"room_seed_text": room_seed_text,
		"run_seed": run_seed,
		"map_scale": map_scale,
		"difficulty": difficulty,
		"difficulty_id": difficulty_id,
		"depth": depth,
		"score": score,
		"coins": coins,
	}


func route_checkpoint_valid(value: Dictionary) -> bool:
	var seed_text := String(value.get("room_seed_text", ""))
	var difficulty_id := String(value.get("difficulty_id", ""))
	var saved_depth := int(value.get("depth", 0))
	var saved_score := int(value.get("score", -1))
	var saved_coins := int(value.get("coins", -1))
	return int(value.get("schema", 0)) == ROUTE_CHECKPOINT_SCHEMA \
		and String(value.get("kind", "")) == "last_route" \
		and not seed_text.is_empty() and seed_text.length() <= 128 \
		and int(value.get("run_seed", 0)) > 0 \
		and saved_depth >= 1 and saved_depth <= MAX_CHECKPOINT_DEPTH \
		and saved_score >= 0 and saved_score <= MAX_CHECKPOINT_TOTAL \
		and saved_coins >= 0 and saved_coins <= MAX_CHECKPOINT_TOTAL \
		and difficulty_id in ["relaxed", "standard", "hard"]


func queue_route_checkpoint(value: Dictionary) -> bool:
	if not route_checkpoint_valid(value):
		return false
	_pending_route_checkpoint = value.duplicate(true)
	return true


func clear_pending_route_checkpoint() -> void:
	_pending_route_checkpoint.clear()


func restore_queued_route_checkpoint() -> bool:
	if not route_checkpoint_valid(_pending_route_checkpoint):
		_pending_route_checkpoint.clear()
		return false
	var value := _pending_route_checkpoint.duplicate(true)
	_pending_route_checkpoint.clear()
	current_mode = GameMode.LAST_ROUTE
	run_seed = int(value["run_seed"])
	depth = int(value["depth"])
	score = int(value["score"])
	coins = int(value["coins"])
	game_over = false
	cancel_escape()
	escape_cooldown = 0.0
	escape_grace = 0.0
	escape_cooldown_scale = 1.0
	start_floor()
	return true


## Deterministic per-floor seed text, mirroring LastRoute's `${seed}-D${depth}`
## levelSeed (game.js's buildLevel) so each depth of a run gets its own layout.
func level_seed_text() -> String:
	return "%d-D%d" % [run_seed, depth]


## True while a hunter's grip prevents a new capture from starting a second
## struggle (the post-escape immunity window) — mirrors triggerGameOver's
## escapeState.grace check.
func is_capture_immune() -> bool:
	# PUBLIC route: a short grace period after joining or rejoining.
	return escape_grace > 0.0 or PublicRoute.in_join_grace()


## True while a captured player has no struggle chance at all and is
## immediately finished — mirrors triggerGameOver's cooldown-skip branch.
func escape_on_cooldown() -> bool:
	return escape_cooldown > 0.0


func begin_escape(hunter_id: String) -> void:
	escape_active = true
	escape_hunter_id = hunter_id
	escape_duration = GameConfig.ESCAPE_DURATION
	escape_remaining = escape_duration
	escape_progress = 0
	escape_required = GameConfig.ESCAPE_PRESSES


## Abort an in-progress grab without spending a life or starting cooldowns.
## Used when a developer enables god mode during the struggle.
func cancel_escape() -> void:
	escape_active = false
	escape_hunter_id = ""
	escape_remaining = 0.0
	escape_duration = 0.0
	escape_progress = 0
	escape_required = 0


func register_escape_press() -> void:
	if escape_active:
		escape_progress += 1


func tick_escape_cooldowns(delta: float) -> void:
	escape_cooldown = maxf(0.0, escape_cooldown - delta)
	escape_grace = maxf(0.0, escape_grace - delta)


## A successful struggle knocks the hunter back and shortens the reuse
## cooldown by 5% each time. There is no hidden life cost.
func resolve_escape_success() -> void:
	escape_active = false
	escape_cooldown_scale *= 0.95
	escape_cooldown = GameConfig.ESCAPE_COOLDOWN * escape_cooldown_scale
	escape_grace = GameConfig.ESCAPE_GRACE


## A failed struggle ends this runner's route. Kept as a bool-returning method
## so the orchestrator's old call boundary remains explicit; it now always
## returns false.
func resolve_escape_failure() -> bool:
	escape_active = false
	game_over = true
	return false
