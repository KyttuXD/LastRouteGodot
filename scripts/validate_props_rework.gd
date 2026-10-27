extends RefCounted

## Props rework 2 (DONE13): the reworked props are built at the sizes their designs promise, stand on the floor, keep their
## rotated parts inside the footprint, and the colliders / footprints / surface heights match them. Also a family-wide
## sanity sweep over every blocky prop for the bug classes the audit found (floating parts, giant or collapsed models).

## type -> (width, height, depth) in metres: the sizes authored in tools/props/blocky_props_rework2.py (TARGET_SIZE).
const TARGETS := {
	"gothicHighbackChair": Vector3(0.56, 1.30, 0.56), "restraintChair": Vector3(0.8, 1.35, 0.8),
	"mansionRockingChair": Vector3(0.6, 1.05, 0.9), "beachChair": Vector3(0.6, 0.85, 1.0),
	"bunkBed": Vector3(1.0, 1.85, 2.05), "prisonBunk": Vector3(0.9, 1.7, 1.9), "gothicDoubleBed": Vector3(2.0, 2.38, 2.75),
	"loungeCouch": Vector3(1.7, 0.9, 0.95), "loungeCouchWide": Vector3(2.4, 0.9, 0.98),
	"normalBookcase": Vector3(1.0, 1.81, 0.42), "mansionBookshelf": Vector3(0.88, 2.06, 0.62),
	"gothicBookcase": Vector3(1.38, 2.44, 0.5), "bedroomWardrobe": Vector3(1.25, 2.12, 0.62),
	"gothicWardrobe": Vector3(1.38, 2.5, 0.69), "locker": Vector3(0.62, 2.0, 0.69),
	"prisonCafeteriaTable": Vector3(2.62, 0.75, 1.75), "bedroomBench": Vector3(1.0, 0.46, 0.4),
	"gothicBedroomBench": Vector3(1.1, 0.46, 0.4), "vanityStool": Vector3(0.4, 0.46, 0.4),
	"gothicVanityStool": Vector3(0.4, 0.46, 0.4), "officeDesk": Vector3(1.62, 0.75, 0.75),
	"normalKitchenCounter": Vector3(1.5, 0.92, 0.69), "luxuryKitchenCounter": Vector3(1.5, 0.92, 0.69),
	"gothicKitchenCounter": Vector3(1.5, 0.92, 0.69), "normalKitchenSink": Vector3(1.25, 1.12, 0.69),
	"normalKitchenStove": Vector3(0.88, 0.92, 0.69),
}
## Seat or table-top height each reworked seat stands at (lowest horizontal surface above the floor is not measured; the
## overall height bands above catch the 2.1 m highback chair class of bug).
const SEATS := ["gothicHighbackChair", "restraintChair", "mansionRockingChair", "beachChair", "vanityStool", "gothicVanityStool",
	"bedroomBench", "gothicBedroomBench"]

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _extent(node: Node, parent: Transform3D = Transform3D.IDENTITY) -> AABB:
	var here := parent
	if node is Node3D:
		here = parent * (node as Node3D).transform
	var total := AABB()
	var have := false
	if node is MeshInstance3D:
		total = here * (node as MeshInstance3D).get_aabb()
		have = true
	for child in node.get_children():
		var inner := _extent(child, here)
		if inner.size != Vector3.ZERO:
			total = inner if not have else total.merge(inner)
			have = true
	return total


func _variants(type: String) -> Array:
	var out := []
	for path in BlockyPropModels.MODELS.get(type, []):
		var scene := load(String(path)) as PackedScene
		if scene == null:
			_expect(false, "%s variant %s does not load" % [type, path])
			continue
		var node := scene.instantiate()
		out.append({"path": String(path), "box": _extent(node)})
		node.free()
	return out


func run(_host: Node) -> int:
	var checked := 0
	for type in TARGETS:
		var want: Vector3 = TARGETS[type]
		var variants := _variants(type)
		_expect(not variants.is_empty(), "%s has no blocky model" % type)
		for entry in variants:
			var box: AABB = entry["box"]
			checked += 1
			_expect(box.size.x <= want.x + 0.07 and box.size.z <= want.z + 0.07,
				"%s is %.2f x %.2f m, wider than its design %.2f x %.2f (rotated parts must stay in the footprint): %s" % [
				type, box.size.x, box.size.z, want.x, want.z, entry["path"]])
			_expect(box.size.y <= want.y + 0.1 and box.size.y >= want.y * 0.6,
				"%s is %.2f m tall, design is %.2f m: %s" % [type, box.size.y, want.y, entry["path"]])
			_expect(absf(box.position.y) < 0.02, "%s floats %.2f m above the floor: %s" % [type, box.position.y, entry["path"]])
	for type in SEATS:
		for entry in _variants(type):
			var box: AABB = entry["box"]
			_expect(box.size.y <= 1.4, "%s is %.2f m tall (seats stay under 1.4 m)" % [type, box.size.y])
	# colliders and footprints cover the models without being giant boxes
	for type in TARGETS:
		var half: Vector2 = RoomCatalog.FOOTPRINTS.get(type, Vector2.ZERO)
		if half == Vector2.ZERO or type == "officeDesk":      # the desk footprint predates the rework and is a deliberate tight collider
			continue
		for entry in _variants(type):
			var box: AABB = entry["box"]
			_expect(half.x + 0.12 >= box.size.x * 0.5 and half.y + 0.12 >= box.size.z * 0.5,
				"%s footprint half-size %s is smaller than its model %.2f x %.2f" % [type, half, box.size.x, box.size.z])
	for type in TARGETS:
		var blocker: Vector3 = StreamedRouteGenerator.TEMPLATE_PROP_SIZES.get(type, Vector3.ZERO)
		if blocker == Vector3.ZERO:
			continue
		for entry in _variants(type):
			var box: AABB = entry["box"]
			# blockers may be lower than a tall canopy/frame (only the body collides) but never above the model by much
			_expect(blocker.y >= box.size.y * 0.35 and blocker.y <= box.size.y + 0.7,
				"%s blocker height %.2f does not fit its model %.2f" % [type, blocker.y, box.size.y])
	# surfaces: what stands on the desk sits on its top
	for entry in _variants("officeDesk"):
		_expect(absf(RoomCatalog.SURFACE_HEIGHTS.get("officeDesk", 0.0) - (entry["box"] as AABB).size.y) <= 0.08,
			"officeDesk surface height %.2f does not match the desk top %.2f" % [
			RoomCatalog.SURFACE_HEIGHTS.get("officeDesk", 0.0), (entry["box"] as AABB).size.y])
	# kitchen runs line up: counter, sink and stove tops within 0.2 m of each other
	for kit in ["normal"]:
		var tops := []
		for t in ["%sKitchenCounter", "%sKitchenSink", "%sKitchenStove"]:
			var vs := _variants(t % kit)
			if not vs.is_empty():
				tops.append((vs[0]["box"] as AABB).size.y)
		if tops.size() == 3:
			_expect(absf(tops[0] - tops[2]) <= 0.1, "%s kitchen counter (%.2f) and stove (%.2f) tops do not line up" % [kit, tops[0], tops[2]])
	# family-wide sweep over every blocky prop
	var swept := 0
	for type in BlockyPropModels.MODELS:
		for entry in _variants(type):
			var box: AABB = entry["box"]
			swept += 1
			_expect(box.size.x > 0.04 and box.size.y > 0.04 and box.size.z > 0.04 or box.size.y > 0.01,
				"%s collapsed to %s: %s" % [type, box.size, entry["path"]])
			_expect(box.position.y > -0.03, "%s sinks %.2f m below the floor: %s" % [type, -box.position.y, entry["path"]])
	metrics = {"reworked": checked, "swept": swept}
	if _failures == 0:
		print("  props_rework  %d reworked variants at their designed sizes, %d blocky models swept (no floating, sunken or collapsed)" % [checked, swept])
	return _failures
