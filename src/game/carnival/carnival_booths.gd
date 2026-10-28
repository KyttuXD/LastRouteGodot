class_name CarnivalBooths
extends RefCounted

## The carnival district's playable booths: which prop types are games, how long they run, how loud they are, what they pay and how long the booth rests afterwards. Pure data and rules
## (no nodes), so the host can judge a result and the validators can run a game in a loop. The game itself is a CarnivalGame subclass (src/game/carnival/*_game.gd); the booth node
## (src/game_3d/carnival_booth_3d.gd) shows it; the route scene routes the request through the host (docs/CARNIVAL_BOOTHS.md).

## prop type -> {game, title, seconds, noise [level, seconds] per kind of event, win_cooldown, lose_cooldown, reward}
const BOOTHS := {
	"ringTossStall": {"game": "ring_toss", "title": "RING TOSS", "seconds": 24.0, "win_cooldown": 300.0, "lose_cooldown": 60.0,
		"noise": {"throw": [0.18, 0.8], "win": [0.35, 1.5]}, "reward": "battery"},
	"strengthTester": {"game": "strength", "title": "STRENGTH TESTER", "seconds": 20.0, "win_cooldown": 420.0, "lose_cooldown": 75.0,
		"noise": {"swing": [0.45, 1.5], "bell": [1.0, 4.0]}, "reward": "hint"},
	"prizeClawMachine": {"game": "claw", "title": "CLAW MACHINE", "seconds": 30.0, "win_cooldown": 360.0, "lose_cooldown": 60.0,
		"noise": {"motor": [0.12, 0.6], "grip": [0.2, 1.0], "win": [0.3, 1.5]}, "reward": "tool"},
	"shootingGallery": {"game": "shooting", "title": "SHOOTING GALLERY", "seconds": 22.0, "win_cooldown": 360.0, "lose_cooldown": 75.0,
		"noise": {"shot": [0.8, 2.5], "clang": [0.8, 2.5]}, "reward": "tool"},
	"whackAMole": {"game": "mole", "title": "WHACK-A-MOLE", "seconds": 20.0, "win_cooldown": 300.0, "lose_cooldown": 60.0,
		"noise": {"hit": [0.45, 1.2], "miss_swing": [0.3, 0.8]}, "reward": "battery"},
	"duckPond": {"game": "duck", "title": "DUCK POND", "seconds": 24.0, "win_cooldown": 300.0, "lose_cooldown": 45.0,
		"noise": {"hook": [0.1, 0.6], "splash": [0.2, 0.8]}, "reward": "battery"},
}
## the longest a host lets a booth stay occupied before it frees the booth itself (a player who left or disconnected), on top of the game's own length
const OCCUPANCY_GRACE := 12.0
## a finish that comes sooner than this after the start cannot have been played
const MIN_PLAY_SECONDS := 1.0
## a cancelled game rests the booth briefly so it cannot be spammed
const CANCEL_COOLDOWN := 10.0
## how far from the booth a player may start or finish
const INTERACT_DISTANCE := 3.6
const TOOL_PRIZES := ["lockpick", "crowbar"]


static func is_booth(prop_type: String) -> bool:
	return BOOTHS.has(prop_type)


static func spec(prop_type: String) -> Dictionary:
	return BOOTHS.get(prop_type, {})


static func game_for(prop_type: String) -> String:
	return String(spec(prop_type).get("game", ""))


static func title_for(prop_type: String) -> String:
	return String(spec(prop_type).get("title", ""))


## The prop type of a game id.
static func prop_for_game(game_id: String) -> String:
	for type in BOOTHS:
		if String(BOOTHS[type]["game"]) == game_id:
			return String(type)
	return ""


## A fresh game of this prop type's kind, or null.
static func make_game(prop_type: String, seed_value: int) -> CarnivalGame:
	match game_for(prop_type):
		"ring_toss":
			return RingTossGame.new(seed_value)
		"strength":
			return StrengthGame.new(seed_value)
		"claw":
			return ClawGame.new(seed_value)
		"shooting":
			return ShootingGame.new(seed_value)
		"mole":
			return MoleGame.new(seed_value)
		"duck":
			return DuckGame.new(seed_value)
	return null


## What the host accepts as a finished game: a booth that exists, a score the game can reach, and time that fits (not instant, not long after the occupancy ran out).
static func plausible(prop_type: String, booth_score: int, elapsed: float) -> bool:
	var s := spec(prop_type)
	if s.is_empty():
		return false
	var game := make_game(prop_type, 0)
	if game == null:
		return false
	return booth_score >= 0 and booth_score <= game.max_score() and elapsed >= MIN_PLAY_SECONDS \
		and elapsed <= float(s["seconds"]) + OCCUPANCY_GRACE


## Whether this score wins at this booth.
static func is_win(prop_type: String, booth_score: int) -> bool:
	var game := make_game(prop_type, 0)
	if game == null:
		return false
	game.booth_score = booth_score
	return game.won()


static func cooldown_for(prop_type: String, won: bool) -> float:
	var s := spec(prop_type)
	return float(s.get("win_cooldown", 300.0)) if won else float(s.get("lose_cooldown", 60.0))


## The noise event (level 0..1, seconds) a kind of event makes, for the hunters' ears. Empty when the booth has none for it.
static func noise_for(prop_type: String, kind: String) -> Array:
	return (spec(prop_type).get("noise", {}) as Dictionary).get(kind, [])


## The prize of a win, decided by the host from the booth and the seed so a replayed event gives the same one:
## {"kind": "battery"} | {"kind": "tool", "item": id} | {"kind": "hint"}.
static func reward_for(prop_type: String, seed_value: int) -> Dictionary:
	match String(spec(prop_type).get("reward", "battery")):
		"tool":
			return {"kind": "tool", "item": TOOL_PRIZES[absi(seed_value) % TOOL_PRIZES.size()]}
		"hint":
			return {"kind": "hint"}
	return {"kind": "battery"}
