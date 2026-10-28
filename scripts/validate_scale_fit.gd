extends RefCounted

## Scale-fit (ScaleFit, docs/SCALE_FIT.md): every prop category fits the hunter scale the world is built at (or, until
## the props lane is done, still the person scale), the runner follows PlayerModels.SCALE, and the architecture constants
## sit inside their ranges. KNOWN lists the outliers that still exist (type/dimension)
## and are owned by the props lane (models): it may only shrink.
##
##   godot --headless --path . res://scenes/validate.tscn -- scale_fit

## Owned by the props lane (they are model sizes). Empty since the props lane shortened the beds (2.25 m with boards, gothic
## canopy 2.31 m) and capped the vanity / serving counter colliders below the mirror and the sneeze hood.
const KNOWN := {}
## On since the props lane resized everything to hunter scale (PropModelCatalog.HUNTER_SCALE, docs/SEATING.md): a
## person-sized prop fails too.
const HUNTER_SCALE_STRICT := true

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	# The world is built at hunter scale (docs/SCALE_FIT.md): a prop fails when it is wrong at BOTH scales; one that is
	# still person-sized (inside the person range, outside the hunter one) is the props lane's resize worklist until
	# HUNTER_SCALE_STRICT is switched on.
	var at_hunter := {}
	for o in ScaleFit.outliers(ScaleFit.HUNTER_FACTOR):
		at_hunter["%s/%s" % [o["type"], o["dim"]]] = o
	var unknown := []
	var worklist := []
	var seen := {}
	for o in ScaleFit.outliers():
		var key := "%s/%s" % [o["type"], o["dim"]]
		seen[key] = true
		if at_hunter.has(key) and not KNOWN.has(key):
			unknown.append("%s %s %.2f outside [%.2f, %.2f] and the hunter-scale [%.2f, %.2f] (%s)" % [o["type"], o["dim"],
				o["value"], o["min"], o["max"], at_hunter[key]["min"], at_hunter[key]["max"], o["category"]])
	for key in at_hunter:
		if not seen.has(key):
			worklist.append(key)
	_expect(unknown.is_empty(), "%d scale outliers: %s" % [unknown.size(), unknown])
	_expect(not HUNTER_SCALE_STRICT or worklist.is_empty(), "%d props still person-sized: %s" % [worklist.size(), worklist])
	for key in KNOWN:
		_expect(seen.has(key), "%s is listed as a known outlier but is now in range: remove it from KNOWN" % key)
	for a in ScaleFit.ARCHITECTURE:
		_expect(float(a[1]) >= float(a[2]) and float(a[1]) <= float(a[3]), "%s = %.2f outside [%.2f, %.2f]" % [a[0], a[1], a[2], a[3]])
	_expect(absf(float(ScaleFit.PLAYER["height"]) - 1.78 * PlayerModels.SCALE) < .01, "player table does not follow PlayerModels.SCALE")
	_expect(float(ScaleFit.PLAYER["height"]) < float(ScaleFit.HUNTER["height"]) * .9 and float(ScaleFit.PLAYER["height"]) > float(ScaleFit.HUNTER["height"]) * .8, "the runner is not about 0.85x of a hunter (slightly smaller)")
	_expect(PlayerController3D.STANDING_COLLISION_HEIGHT < float(ScaleFit.PLAYER["height"]), "the standing capsule is taller than the runner")
	_expect(PlayerController3D.CROUCH_COLLISION_HEIGHT < PlayerController3D.STANDING_COLLISION_HEIGHT * .7, "crouch does not lower the capsule")
	var sized := 0
	for type in PropColliderSizes.SIZES:
		if not ScaleFit.category_of(String(type)).is_empty():
			sized += 1
	_expect(sized >= 60, "only %d props fall in a scale category" % sized)
	var catalog := _check_catalog()
	if _failures == 0:
		print("  scale_fit  catalog: %s" % [catalog])
		print("  scale_fit  %d props in %d categories fit person or hunter scale; %d still person-sized (props lane worklist); runner %.2f m vs hunter %.2f m" % [
			sized, ScaleFit.RULES.size(), worklist.size(), float(ScaleFit.PLAYER["height"]), float(ScaleFit.HUNTER["height"])])
	return _failures


## Every catalog prop as spawned (hunter scale included) against its category's typical real-world range x the hunter
## factor, from data/scale/prop_size_ranges.json (docs/PROP_SIZES.md). Strict: any prop out of range fails, so a new
## prop (or a mod pack's) has to come in at hunter scale. Exempt categories and keep_person_size are skipped.
const RANGES_PATH := "res://data/scale/prop_size_ranges.json"


func _check_catalog() -> Dictionary:
	var file := FileAccess.open(RANGES_PATH, FileAccess.READ)
	_expect(file != null, "%s is missing" % RANGES_PATH)
	if file == null:
		return {}
	var ranges: Dictionary = JSON.parse_string(file.get_as_text())
	var factor := float(ranges.get("hunter_factor", 1.5))
	var keep: Dictionary = ranges.get("keep_person_size", {})
	var types := {}
	for type in PropModelCatalog.MODEL_PATHS:
		types[String(type)] = true
	for type in BlockyPropModels.MODELS:
		types[String(type)] = true
	var counts := {"ok": 0, "exempt": 0, "out": 0, "uncategorised": 0}
	var bad := []
	for type in types:
		if keep.has(type):
			counts["exempt"] += 1
			continue
		var cat := _category(ranges["categories"], type)
		if cat.is_empty():
			counts["uncategorised"] += 1
			bad.append("%s has no size category in %s" % [type, RANGES_PATH])
			continue
		if cat.has("exempt"):
			counts["exempt"] += 1
			continue
		var size := _spawned_size(type)
		if size == Vector3.ZERO:
			continue
		var dims := {"height": size.y, "long": maxf(size.x, size.z), "short": minf(size.x, size.z)}
		var wrong := []
		for key in ["height", "long", "short"]:
			if not cat.has(key):
				continue
			var lo := float(cat[key][0]) * factor
			var hi := float(cat[key][1]) * factor
			if float(dims[key]) < lo - .005 or float(dims[key]) > hi + .005:
				wrong.append("%s %.2f (%.2f-%.2f)" % [key, dims[key], lo, hi])
		if wrong.is_empty():
			counts["ok"] += 1
		else:
			counts["out"] += 1
			bad.append("%s (%s): %s" % [type, cat["id"], ", ".join(wrong)])
	_expect(bad.is_empty(), "%d props out of their hunter-scale range (docs/PROP_SIZES.md): %s" % [bad.size(), bad.slice(0, 8)])
	_expect(int(counts["ok"]) > 200, "only %d catalog props measured in range" % counts["ok"])
	return counts


static func _category(categories: Array, type: String) -> Dictionary:
	for cat_value in categories:
		var cat: Dictionary = cat_value
		var hit := false
		for word in cat.get("words", []):
			if type.contains(String(word)):
				hit = true
		for word in cat.get("not", []):
			if type.contains(String(word)):
				hit = false
		if hit:
			return cat
	return {}


static func _spawned_size(type: String) -> Vector3:
	var paths: Array = BlockyPropModels.MODELS.get(type, [])
	if paths.is_empty():
		paths = PropModelCatalog.MODEL_PATHS.get(type, [])
	var total := AABB()
	var have := false
	for path in paths:
		if not ResourceLoader.exists(String(path)):
			continue
		var node := ModelSlot.instantiate_prop(String(path), type)
		if node == null:
			continue
		var box := ModelSlot.combined_local_bounds(node)
		node.free()
		if box.size == Vector3.ZERO:
			continue
		total = box if not have else total.merge(box)
		have = true
	return total.size if have else Vector3.ZERO
