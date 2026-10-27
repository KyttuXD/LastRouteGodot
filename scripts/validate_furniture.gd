extends RefCounted

## Chairs and tables stay believable next to the player mannequin (DONE11): seats about 0.45 m, table tops 0.75 m,
## colliders that match the model instead of a giant box, and no solid furniture footprints overlapping in generated rooms.

const CHAIR_TYPES := ["woodenChair", "woodenChairCushion", "diningChair", "diningChairCushion"]
const TABLE_TYPES := ["woodenTable", "diningTable"]

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
	for type in CHAIR_TYPES:
		for entry in _variants(type):
			var box: AABB = entry["box"]
			_expect(box.size.y >= 0.45 and box.size.y <= 1.0,
				"%s is %.2f m tall (chairs 0.45-1.0 m, seat about 0.44): %s" % [type, box.size.y, entry["path"]])
			_expect(box.size.x <= 0.56 and box.size.z <= 0.56, "%s footprint %.2f x %.2f is wider than a chair" % [type, box.size.x, box.size.z])
			_expect(absf(box.position.y) < 0.02, "%s floats %.2f m above the floor: %s" % [type, box.position.y, entry["path"]])
	for type in TABLE_TYPES:
		for entry in _variants(type):
			var box: AABB = entry["box"]
			_expect(absf(box.size.y - 0.75) <= 0.02, "%s top is %.2f m (tables are 0.75 m): %s" % [type, box.size.y, entry["path"]])
	for entry in _variants("restaurantPartyTable"):
		var box: AABB = entry["box"]
		_expect(box.size.y >= 2.0 and box.size.y <= 2.3, "restaurantPartyTable lost its balloon cluster (%.2f m)" % box.size.y)
	for entry in _variants("gothicPedestalTable"):
		_expect(absf((entry["box"] as AABB).size.y - 0.75) <= 0.02, "gothicPedestalTable is not 0.75 m")
	for entry in _variants("normalEntryBench"):
		_expect((entry["box"] as AABB).size.y <= 1.0, "normalEntryBench is taller than 1.0 m")
	# colliders: the footprint table must cover the model without being a giant box
	for type in CHAIR_TYPES + TABLE_TYPES + ["restaurantPartyTable"]:
		var half: Vector2 = RoomCatalog.FOOTPRINTS.get(type, Vector2.ZERO)
		_expect(half != Vector2.ZERO, "%s has no collider footprint" % type)
		for entry in _variants(type):
			var box: AABB = entry["box"]
			_expect(half.x + 0.06 >= box.size.x * 0.5 and half.y + 0.06 >= box.size.z * 0.5,
				"%s collider half-size %s is smaller than its model %.2f x %.2f" % [type, half, box.size.x, box.size.z])
			_expect(half.x <= box.size.x * 0.5 + 0.3 and half.y <= box.size.z * 0.5 + 0.3,
				"%s collider half-size %s is a giant box for a %.2f x %.2f model" % [type, half, box.size.x, box.size.z])
	for type in CHAIR_TYPES + TABLE_TYPES + ["restaurantPartyTable"]:
		var blocker: Vector3 = StreamedRouteGenerator.TEMPLATE_PROP_SIZES.get(type, Vector3.ZERO)
		for entry in _variants(type):
			_expect(blocker.y >= (entry["box"] as AABB).size.y - 0.05 and blocker.y <= (entry["box"] as AABB).size.y + 0.6,
				"%s blocker height %.2f does not cover its model %.2f" % [type, blocker.y, (entry["box"] as AABB).size.y])
	if _failures == 0:
		print("  furniture  chairs 0.45-1.0 m, tables 0.75 m, colliders match the models")
	return _failures
