extends SceneTree

## Why does a hunter stand still? Prints the navigation path between two world points and the open/blocked cells around the first.
##   godot --headless --path . -s dev/look/stuck_probe.gd -- SEED fromX fromZ toX toZ

func _init() -> void:
	# autoloads exist only from the first frame; the navigation classes depend on them
	process_frame.connect(_probe, CONNECT_ONE_SHOT)


func _probe() -> void:
	var a := OS.get_cmdline_user_args()
	var generator := StreamedRouteGenerator.new(a[0])
	var from := Vector2i(int(floor(float(a[1]))), int(floor(float(a[2]))))
	var to := Vector2i(int(floor(float(a[3]))), int(floor(float(a[4]))))
	var cc := Vector3i(floori(from.x / 45.0), 0, floori(from.y / 45.0))
	var coords := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			coords.append(Vector3i(cc.x + dx, 0, cc.z + dz))
	var navigation = load("res://game/hunters/ai/streamed_hunter_navigation.gd").new(generator, 0)
	navigation.refresh(0, coords)
	var path: Array = navigation.find_path(from, to)
	print("chunk ", cc, " region ", generator.region_for(cc), " plan ", generator.large_plan(cc))
	print("path ", from, " -> ", to, " size ", path.size())
	for z in range(from.y - 4, from.y + 5):
		var row := ""
		for x in range(from.x - 8, from.x + 9):
			var c := Vector2i(x, z)
			row += "@" if c == from else ("o" if navigation.is_floor(x + .5, z + .5) else "#")
		print(row)
	# 4-neighbour flood over cells a hunter can stand in
	var seen := {from: true}
	var frontier := [from]
	while not frontier.is_empty():
		var cur: Vector2i = frontier.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = cur + d
			if not seen.has(n) and navigation.can_occupy(n.x + .5, n.y + .5) and absi(n.x - from.x) < 70 and absi(n.y - from.y) < 70:
				seen[n] = true
				frontier.append(n)
	var lo := from
	var hi := from
	for c in seen:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	for z in range(lo.y - 2, hi.y + 3):
		var line := ""
		for x in range(lo.x - 2, hi.x + 3):
			var c := Vector2i(x, z)
			line += "@" if c == from else ("o" if seen.has(c) else ("." if navigation.is_floor(x + .5, z + .5) else "#"))
		print(line)
	var data: Dictionary = generator.chunk(cc)
	var base := Vector2i(cc.x, cc.z) * 45
	for prop in data.get("region_props", []):
		if not bool(prop.get("solid", true)) or bool(prop.get("room_door", false)):
			continue
		for oc in prop.get("occupied_cells", [prop.get("cell", Vector2i.ZERO)]):
			var cell: Vector2i = base + (oc as Vector2i)
			if cell.x >= lo.x - 1 and cell.x <= hi.x + 1 and cell.y >= lo.y - 1 and cell.y <= hi.y + 1:
				print("PROP ", prop.get("type"), " tmpl ", prop.get("room_template", ""), " cell ", prop.get("cell"), " occ ", prop.get("occupied_cells"), " size ", prop.get("collider_size", ""))
				break
	print("from can_occupy ", navigation.can_occupy(from.x + .5, from.y + .5), " to can_occupy ", navigation.can_occupy(to.x + .5, to.y + .5), " flood ", seen.size(), " reaches to: ", seen.has(to))
	quit()
