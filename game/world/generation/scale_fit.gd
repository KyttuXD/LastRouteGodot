class_name ScaleFit
extends RefCounted

## Scale-fit reference (docs/SCALE_FIT.md). The world is built at HUNTER scale: a normal hunter (2.67 m) is the "human"
## the rooms, doors and furniture are judged against, and the runners are smaller (PlayerModels.SCALE, 1.90 m). Prop sizes
## are the collider footprints derived from the models (PropColliderSizes: x, height, z).

## Measured with dev/look/scale_measure.tscn on the blocky mannequin (1.78 m as authored), times PlayerModels.SCALE.
const PLAYER := {
	"height": 1.90, "eye": 1.61, "camera": 1.71, "shoulder": 1.55, "elbow": 1.17, "hip": 0.96, "knee": 0.51,
	"hand_hanging": 0.82, "reach_up": 2.30, "shoulder_width": 0.53,
}
## A normal (1.5x) hunter, measured by the door_clearance validator: the human the world is sized for.
const HUNTER := {"height": 2.67, "eye": 2.27, "shoulder_width": 1.38}
## Prop ranges below are person ranges (as for a 1.78 m human); against the hunters they are this much bigger.
const HUNTER_FACTOR := 1.5

## [category, name words (any), exclude words, height range, long-side range, short-side range] for a person; first match
## wins, a range of [] is not checked. outliers(HUNTER_FACTOR) judges the props at hunter scale.
const RULES := [
	["bed", ["Bed", "Bunk"], ["Bedroom", "Bench", "Nightstand"], [0.35, 2.25], [1.8, 2.35], [0.8, 2.1]],
	["seat", ["Chair", "Stool"], ["Cushion"], [0.70, 1.45], [], [0.35, 0.85]],
	["couch", ["Couch", "Sofa"], [], [0.70, 1.10], [1.4, 2.8], []],
	["table", ["Table", "Desk", "Workstation"], ["reception"], [0.40, 1.0], [], []],
	["counter", ["Counter", "Island", "Stove", "Sideboard", "Dresser", "reception"], [], [0.85, 1.20], [], []],
	["sink", ["Sink", "Vanity"], [], [0.85, 1.35], [], []],
	["tall_storage", ["Fridge", "Wardrobe", "Bookcase", "Bookshelf", "Cabinet", "Rack", "Vending", "Locker"], ["Counter", "Wall"], [1.2, 2.25], [], []],
	["lamp", ["Lamp", "Candelabra"], [], [1.3, 2.0], [], [0.3, 0.9]],
	["toilet", ["Toilet", "Urinal"], [], [0.7, 1.05], [], []],
	["bath", ["Bathtub"], [], [0.45, 0.85], [], []],
	["shower", ["Shower"], ["Bench"], [1.8, 2.25], [], []],
	["crate", ["Crate", "Boxes"], [], [0.3, 1.2], [], []],
	["nightstand", ["Nightstand"], [], [0.45, 0.95], [], []],
]

## Architecture against the player: [name, value, min, max, note].
const ARCHITECTURE := [
	["ceiling_height", 4.0, 2.6, 4.5, "StreamedFacilityView3D.WALL_HEIGHT; high on purpose (hunters are 1.5x)"],
	["door_opening_height", DoorwayFrames.TARGET_OPENING, 2.9, 3.2, "doors open 3.07 m: a normal hunter (2.67 m) + 40 cm; two-cell doors for every room with a side of 4+ cells"],
	["hall_width", 3.0, 2.0, 5.0, "StreamedRouteGenerator.CORRIDOR_WIDTH, 3 or 5 cells"],
	["capsule_standing", PlayerController3D.STANDING_COLLISION_HEIGHT, 1.6, 2.0, "PlayerController3D.STANDING_COLLISION_HEIGHT vs the 1.9 m runner"],
	["camera_vs_model_eye", 0.08, 0.0, 0.15, "camera 1.71 against the model's eye node at 1.61"],
	["light_switch_height", 1.45, 0.9, 2.66, "StreamedFacilityView3D.SWITCH_HEIGHT: within the runner's reach (2.30), below a hunter's shoulder"],
]


static func category_of(type: String) -> Dictionary:
	for rule_value in RULES:
		var rule: Array = rule_value
		var hit := false
		for word in rule[1]:
			if type.contains(String(word)):
				hit = true
		for word in rule[2]:
			if type.contains(String(word)):
				hit = false
		if hit:
			return {"name": rule[0], "height": rule[3], "long": rule[4], "short": rule[5]}
	return {}


## Outliers: [{type, category, dim, value, min, max}] across every collider-sized prop, with the ranges times `factor`
## (1 = person scale, HUNTER_FACTOR = the hunters' scale the world is built at).
static func outliers(factor: float = 1.0) -> Array:
	var out := []
	for type_value in PropColliderSizes.SIZES:
		var type := String(type_value)
		var cat := category_of(type)
		if cat.is_empty():
			continue
		var size: Vector3 = PropColliderSizes.SIZES[type]
		var long_side := maxf(size.x, size.z)
		var short_side := minf(size.x, size.z)
		for check in [["height", size.y], ["long", long_side], ["short", short_side]]:
			var range_value: Array = cat[check[0]]
			if range_value.is_empty():
				continue
			var value := float(check[1])
			var low := float(range_value[0]) * factor
			var high := float(range_value[1]) * factor
			if value < low - 0.005 or value > high + 0.005:
				out.append({"type": type, "category": cat["name"], "dim": check[0], "value": value,
					"min": low, "max": high})
	return out
