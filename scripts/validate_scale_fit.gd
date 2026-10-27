extends RefCounted

## Scale-fit (ScaleFit, docs/SCALE_FIT.md): every prop category stays inside its size range against the 1.78 m player
## mannequin, and the architecture constants sit inside theirs. KNOWN lists the outliers that still exist (type/dimension)
## and are owned by the props lane (models): it may only shrink.
##
##   godot --headless --path . res://scenes/validate.tscn -- scale_fit

## Owned by the props lane (they are model sizes). Empty since the props lane shortened the beds (2.25 m with boards, gothic
## canopy 2.31 m) and capped the vanity / serving counter colliders below the mirror and the sneeze hood.
const KNOWN := {}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	var found := ScaleFit.outliers()
	var unknown := []
	var seen := {}
	for o in found:
		var key := "%s/%s" % [o["type"], o["dim"]]
		seen[key] = true
		if not KNOWN.has(key):
			unknown.append("%s %s %.2f outside [%.2f, %.2f] (%s)" % [o["type"], o["dim"], o["value"], o["min"], o["max"], o["category"]])
	_expect(unknown.is_empty(), "%d scale outliers: %s" % [unknown.size(), unknown])
	for key in KNOWN:
		_expect(seen.has(key), "%s is listed as a known outlier but is now in range: remove it from KNOWN" % key)
	for a in ScaleFit.ARCHITECTURE:
		_expect(float(a[1]) >= float(a[2]) and float(a[1]) <= float(a[3]), "%s = %.2f outside [%.2f, %.2f]" % [a[0], a[1], a[2], a[3]])
	_expect(is_equal_approx(float(ScaleFit.PLAYER["camera"]) - float(ScaleFit.PLAYER["eye"]), 0.09), "player table camera/eye changed")
	var sized := 0
	for type in PropColliderSizes.SIZES:
		if not ScaleFit.category_of(String(type)).is_empty():
			sized += 1
	_expect(sized >= 60, "only %d props fall in a scale category" % sized)
	if _failures == 0:
		print("  scale_fit  %d props in %d categories inside their ranges against the %.2f m player (%d known outliers)" % [
			sized, ScaleFit.RULES.size(), float(ScaleFit.PLAYER["height"]), KNOWN.size()])
	return _failures
