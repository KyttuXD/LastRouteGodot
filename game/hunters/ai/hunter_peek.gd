class_name HunterPeek
extends RefCounted

## Corner peeking ("make them peek from a corner, and either run/chase if they see something"). A searching or
## investigating hunter whose route turns at a real corner may stop in the cell before the turn, lean out past the edge
## and look down the hall. Sight during the lean is taken from the leaned-out head (HunterBrain._update_perception), so
## she can only see what that head could see, and the runner can see her head and shoulders round the edge.
##
## Geometry, in grid cells (1 cell = 1 m). The route goes A -> C -> C + d2, turning from d1 = C - A to d2 at C, and the
## inner corner A + d2 is solid. She stands at body() (behind the edge plane between A and C by more than her radius)
## and her eye is at head() (HEAD_PAST m past that plane). Nothing about the corner reads geometry the host and guests
## could disagree on: the host picks it and the brain state carries it.
##
## Styles: "burst" charges once the reaction time has passed; "ambush" ducks back behind the corner, waits for the runner
## to come round (a chase the moment she sees them from cover) and then investigates where she saw them.

const BODY_BEHIND := 0.42   # body centre to the edge plane (HUNTER_RADIUS is 0.33)
const HEAD_PAST := 0.28     # leaned head past the edge plane
const LOOKAHEAD := 4        # route cells ahead checked for a turn
const COOLDOWN := 6.0       # seconds before the same hunter considers another corner
const SETTLE := 0.25        # seconds to slide into the lean spot before the look starts

## Per hunter: chance a qualifying corner gets a peek, look seconds, style. Hunters missing here use DEFAULT; the ones
## whose own rules drive their movement (objective, dormant, stationary) never peek.
const DEFAULT := {"chance": 0.35, "look": 1.4, "style": "burst"}
const TUNING := {
	"nyxie": {"chance": 0.9, "look": 2.0, "style": "ambush"},
	"thessine": {"chance": 0.7, "look": 1.8, "style": "ambush"},
	"glyra": {"chance": 0.8, "look": 1.8, "style": "ambush"},   # only once her music is running down (GlyraGimmick.peek_chance)
	"ilyra": {"chance": 0.65, "look": 1.5, "style": "burst"},
	"quenelle": {"chance": 0.55, "look": 1.6, "style": "ambush"},
	"umbriel": {"chance": 0.55, "look": 1.8, "style": "ambush"},
	"dovelle": {"chance": 0.45, "look": 1.4, "style": "burst"},
	"porcelle": {"chance": 0.45, "look": 2.0, "style": "ambush"},
	"xivvy": {"chance": 0.3, "look": 1.0, "style": "burst"},
	"ravelle": {"chance": 0.3, "look": 1.2, "style": "burst"},
	"kathy": {"chance": 0.15, "look": 1.0, "style": "burst"},
	"elise": {"chance": 0.12, "look": 1.0, "style": "burst"},
	"loxelle": {"chance": 0.1, "look": 1.0, "style": "burst"},
	"solyth": {"chance": 0.1, "look": 1.0, "style": "burst"},
	"void_black": {"chance": 0.5, "look": 1.6, "style": "ambush"},
	"void_purple": {"chance": 0.45, "look": 1.5, "style": "ambush"},
	"void_red": {"chance": 0.2, "look": 1.0, "style": "burst"},
	"void_orange": {"chance": 0.2, "look": 1.0, "style": "burst"},
}
const NEVER := ["wynelle", "haelith", "ysolde", "opalie", "verrine", "zellia", "void_gray", "mavrine", "ceryth",
	"briselle", "ferryn", "javelle", "aki"]

## Difficulty: chance scale, seconds from first sight to the burst, and how long an ambusher waits in cover.
const DIFFICULTY := {
	"standard": {"chance": 1.0, "react": 0.45, "ambush": 2.5},
	"hard": {"chance": 1.15, "react": 0.25, "ambush": 2.0},
	"nightmare": {"chance": 1.3, "react": 0.12, "ambush": 1.6},
}


static func tuning(hunter_id: String) -> Dictionary:
	if hunter_id in NEVER:
		return {"chance": 0.0, "look": 0.0, "style": "burst"}
	return TUNING.get(hunter_id, DEFAULT)


static func difficulty(difficulty_id: String) -> Dictionary:
	return DIFFICULTY.get(difficulty_id, DIFFICULTY["standard"])


static func chance(hunter_id: String, difficulty_id: String) -> float:
	return clampf(float(tuning(hunter_id)["chance"]) * float(difficulty(difficulty_id)["chance"]), 0.0, 1.0)


static func _centre(cell: Vector2i) -> Vector2:
	return Vector2(cell.x + .5, cell.y + .5)


## The first real corner on `route` (cells, starting at the hunter's own cell) within LOOKAHEAD, as
## {"a", "c", "d1", "d2"}; {} when there is none. A real corner: the route turns 90 degrees at C, the inner corner cell
## A + d2 blocks sight (hides_hall: a wall, never a see-through railing or grate), and the hall cell C + d2 is open.
static func find_corner(route: Array, generator) -> Dictionary:
	# The brain's smoothed route drops cells on a straight run, so a leg may be several cells long; only its axis matters.
	for i in range(1, mini(route.size() - 1, LOOKAHEAD + 1)):
		var c: Vector2i = route[i]
		var d1 := _axis(c - (route[i - 1] as Vector2i))
		var d2 := _axis((route[i + 1] as Vector2i) - c)
		if d1 == Vector2i.ZERO or d2 == Vector2i.ZERO or d1 == d2 or d1 == -d2:
			continue
		var a := c - d1
		var inner := a + d2
		if not hides_hall(generator, inner):
			continue
		return {"a": a, "c": c, "d1": d1, "d2": d2}
	return {}


## True when `cell` is a corner that hides the hall beyond it (a wall or an opaque prop). A railing, grate or fence
## the runner sees through is not a corner to peek round: sight goes straight through it. Navigations
## without a sight grid (validator stubs) fall back to "not floor".
static func hides_hall(generator, cell: Vector2i) -> bool:
	if generator.has_method("blocks_sight"):
		return generator.blocks_sight(cell.x + .5, cell.y + .5)
	return not generator.is_floor(cell.x + .5, cell.y + .5)


## The unit step of an axis-aligned offset; ZERO for a diagonal or no offset.
static func _axis(offset: Vector2i) -> Vector2i:
	if offset.x != 0 and offset.y != 0:
		return Vector2i.ZERO
	return Vector2i(signi(offset.x), signi(offset.y))


static func body(corner: Dictionary) -> Vector2:
	return _centre(corner["a"]) + Vector2(corner["d1"]) * (.5 - BODY_BEHIND)


static func head(corner: Dictionary) -> Vector2:
	return _centre(corner["a"]) + Vector2(corner["d1"]) * (.5 + HEAD_PAST)


## +1 when the corner edge is on her left as she faces down the hall (d2), -1 on her right. Picks the lean pose.
static func side(corner: Dictionary) -> int:
	var d2 := Vector2(corner["d2"])
	return 1 if Vector2(corner["d1"]).dot(Vector2(d2.y, -d2.x)) > 0.0 else -1
