extends RefCounted

## Z-fighting guard: loads the streamed route around the origin and scans every mesh (CoplanarScan) for same-facing,
## axis-aligned faces of different meshes that share a plane (within 2 mm) and overlap by at least 5 dm2. Looks only at the
## surface, props and doors against each other; decor (MultiMesh dressing) overlaps are exempt (same-kind modules and
## additive decals). Parts of one prop and a locker's hidden seal are ignored.
##
## KNOWN is the ratchet for pairs that still exist; it is zero now (the prison cafeteria furniture that butted together in
## 5-wide wings no longer does in 9x9 rooms) and may only stay there. Smaller overlaps (tool: tools/look/coplanar_scan)
## remain in door frames/leaves and wall-mounted decor at chunk seams; they are listed in docs/Z_FIGHTING.md.
##
##   godot --headless --path . res://scenes/validate.tscn -- coplanar

const MIN_OVERLAP := 0.05
const KNOWN := 0

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "COPLANAR-SCAN"
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 200:
		await host.get_tree().physics_frame
	var scan := CoplanarScan.new()
	scan.ignore_siblings = true
	scan.min_overlap = MIN_OVERLAP
	var pairs := scan.scan(route.get_node("World/StreamedFacility"))
	var counted := []
	for pair in pairs:
		var a := CoplanarScan.kind_of(String(pair["a"]))
		var b := CoplanarScan.kind_of(String(pair["b"]))
		if a.begins_with("decor:") or b.begins_with("decor:"):
			continue
		counted.append("%s <-> %s @ %s (%.2f m2)" % [a, b, pair["at"], pair["overlap"]])
	_expect(counted.size() <= KNOWN, "%d coplanar prop/door/surface pairs (allowed %d), e.g. %s" % [
		counted.size(), KNOWN, counted.slice(0, 4)])
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  coplanar  %d faces scanned, %d known prop pairs (ratchet %d), no new z-fighting" % [
			scan.faces.size(), counted.size(), KNOWN])
	return _failures
