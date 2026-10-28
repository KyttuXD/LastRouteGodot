class_name ScaleFit
extends RefCounted

## Scale-fit reference (docs/SCALE_FIT.md): what the player mannequin measures and the size range each prop category must
## keep against it. Prop sizes are the collider footprints derived from the models (PropColliderSizes: x, height, z; the
## height of tall pieces is capped at 2.2 there). Hunters are deliberately 1.5x and are NOT part of this table.

## Measured with tools/look/scale_measure.tscn on the blocky player mannequin (metres).
const PLAYER := {
	"height": 1.78, "eye": 1.51, "camera": 1.60, "shoulder": 1.45, "elbow": 1.10, "hip": 0.90, "knee": 0.48,
	"hand_hanging": 0.77, "reach_up": 2.15, "shoulder_width": 0.50,
}

## [category, name words (any), exclude words, height range, long-side range, short-side range]. First match wins.
## A range of [] is not checked.
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
	["door_opening_height", DoorwayFrames.TARGET_OPENING, 1.95, 3.0, "door frames are raised toward 2.95 m (capped at 3.15 m tall) for the 1.5x hunters (2.67 m), who duck the rest (DoorwayPose); a person needs 2.0"],
	["hall_width", 3.0, 2.0, 5.0, "StreamedRouteGenerator.CORRIDOR_WIDTH, 3 or 5 cells"],
	["capsule_standing", 1.7, 1.5, 1.85, "PlayerController3D.STANDING_COLLISION_HEIGHT vs the 1.78 m model"],
	["camera_vs_model_eye", 0.09, 0.0, 0.15, "camera 1.60 against the model's eye node at 1.51"],
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


## Outliers: [{type, category, dim, value, min, max}] across every collider-sized prop.
static func outliers() -> Array:
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
			if value < float(range_value[0]) - 0.005 or value > float(range_value[1]) + 0.005:
				out.append({"type": type, "category": cat["name"], "dim": check[0], "value": value,
					"min": range_value[0], "max": range_value[1]})
	return out
