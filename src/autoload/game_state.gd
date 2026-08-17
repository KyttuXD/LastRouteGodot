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
## Collected relays currently knocked offline by Briselle -- taken offline
## without being un-collected, matching the original's own split: hunter
## activation and chase speed stay driven by relays_collected (never
## decreases), while the lift gate reads "collected AND not sabotaged".
var relays_sabotaged: int = 0

## Zephyra's economy. Per-RUN, not per-floor -- mirrors inventory.js's own
## coins field, which survives a descent the same way score does.
var coins: int = 0

## Capture/escape struggle, ported from hunter-ai.js's triggerGameOver/
## beginEscape/breakFree/finish. The room supplies the run's difficulty when it
## starts, so this whole-run pool does not refill on a floor descent.
var lives_remaining: int = GameConfig.RESPAWN_LIVES_STANDARD
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


func start_new_run(seed_value: int = 0, difficulty_id: String = "standard") -> void:
	run_seed = seed_value if seed_value != 0 else randi()
	depth = 1
	score = 0
	coins = 0
	lives_remaining = GameConfig.respawn_lives_for(difficulty_id)
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


## Deterministic per-floor seed text, mirroring LastRoute's `${seed}-D${depth}`
## levelSeed (game.js's buildLevel) so each depth of a run gets its own layout.
func level_seed_text() -> String:
	return "%d-D%d" % [run_seed, depth]


## True while a hunter's grip prevents a new capture from starting a second
## struggle (the post-escape immunity window) — mirrors triggerGameOver's
## escapeState.grace check.
func is_capture_immune() -> bool:
	return escape_grace > 0.0


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


## Mirrors breakFree(): a successful struggle still costs a life (it just
## skips the respawn walk) and shortens the reuse cooldown by 5% each time.
func resolve_escape_success() -> void:
	escape_active = false
	lives_remaining = maxi(0, lives_remaining - 1)
	escape_cooldown_scale *= 0.95
	escape_cooldown = GameConfig.ESCAPE_COOLDOWN * escape_cooldown_scale
	escape_grace = GameConfig.ESCAPE_GRACE


## Mirrors finish(): with lives left, spend one and respawn; otherwise the
## run is over. Returns true if the run continues.
func resolve_escape_failure() -> bool:
	escape_active = false
	if lives_remaining > 0:
		lives_remaining -= 1
		return true
	game_over = true
	return false
