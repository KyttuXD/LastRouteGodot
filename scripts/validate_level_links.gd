extends RefCounted

## Up/down bleed audit (KT: "can we check for other UP/DOWN bleeding spots"): every vertical connection the streamed
## world builds, on every level pair, over several seeds. For each ladder (maze <-> sewer), stairwell (sewer <-> maze;
## the storeys above once they stream), ramp (sewer <-> collector, collector <-> Inferno) and waterfall drop (sewer -> collector)
## both chunks of the link's column are built and their visible surface (RefSurfaceMesh) is checked:
##  - clear: no floor or ceiling face across the opening between the lower floor and the upper storey's floor
##    (a slab through the well, a lid of ceiling over the ladder shaft);
##  - watertight: at every height of the opening, each side is either open into a room or corridor of the storey at
##    that height, or closed by a wall face looking into the opening (a missing face is a void gap: back faces, the
##    slab's inside, sky colour or the other storey's paint showing through);
##  - no z-fighting: no two faces facing the same way overlap in one plane anywhere in the two chunks (storey seams,
##    lintels on lintels, chunk-edge doubles);
##  - contained: no face of one storey reaches into the open air of the storey above or below, away from the links;
##  - landings: both ends of a stairwell or ramp stand on a floor face at their own level's floor;
##  - light: no shadowless light lights the other storey's structure through the slab away from the opening
##    (StoreyLayers: each storey's structure on its own render layer, its lights and pool lamps blind to the other).
## Fog is the environment's distance fog (one per camera, no volumes), so it cannot leak between storeys.
##
##   godot --headless --path . res://scenes/validate.tscn -- level_links

const SEEDS := ["MAP-CHECK", "SEWER-A", "SEWER-STAIRS", "LINKS-B", "LINKS-C"]
const RADIUS := 3
## Links of one kind and level pair checked per seed (each builds two chunks).
const PER_KIND := 3
const H := StreamedFacilityView3D.LEVEL_HEIGHT
const STEP := .1
## A face this far past a storey line is a poke into the other storey.
const POKE := .02
## Overlap area (m^2) of two same-facing coplanar faces that counts as z-fighting.
const FIGHT_AREA := .01
## A light reaching the other storey with more than this (energy x falloff) lights it through the slab.
const LIGHT_LEAK := .1

var _failures := 0
var _counts := {}
var _problems := {}
var _pairs := {}
var _worst_layers_usec := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	for seed_text in SEEDS:
		await _audit_seed(host, seed_text)
	for kind in ["ladder", "stairs", "spiral", "ramp", "falls"]:
		_expect(int(_counts.get(kind, 0)) >= 2, "only %d %s links audited (want at least 2)" % [_counts.get(kind, 0), kind])
	# the storeys over the maze are not streamed yet (StreamedRouteGenerator.is_chunk_allowed stops at the maze), so
	# their stairwells are audited when they are; upper_levels checks their slabs meanwhile
	for pair in ["0/-1", "-1/-2", "-2/-3"]:
		_expect(_pairs.has(pair), "no link audited between levels %s" % pair)
	print("  level_links: StoreyLayers.apply worst %.2f ms per chunk" % (_worst_layers_usec / 1000.0))
	_expect(_worst_layers_usec < 4000, "StoreyLayers.apply took %.2f ms on one chunk (a streaming frame step)" % (_worst_layers_usec / 1000.0))
	if _failures == 0:
		print("  ok    level_links: audited %s over %d seeds, level pairs %s" % [_counts, SEEDS.size(), _pairs.keys()])
	else:
		print("  level_links: audited %s, problems %s" % [_counts, _problems])
	return _failures


func _report(kind: String, rule: String, message: String) -> void:
	_problems["%s/%s" % [kind, rule]] = int(_problems.get("%s/%s" % [kind, rule], 0)) + 1
	_expect(false, "%s %s: %s" % [kind, rule, message])


## Every link in the seed's window, PER_KIND of each kind: {kind, x, z, lo, hi, cells, landings, label}.
func _links(generator: StreamedRouteGenerator) -> Array:
	var picked := {}
	var out := []
	var add := func(entry: Dictionary) -> void:
		var key := "%s:%d" % [entry["kind"], entry["lo"]]
		if int(picked.get(key, 0)) >= PER_KIND:
			return
		picked[key] = int(picked.get(key, 0)) + 1
		out.append(entry)
	for z in range(-RADIUS, RADIUS + 1):
		for x in range(-RADIUS, RADIUS + 1):
			var sewer_coord := Vector3i(x, SewerRouteGenerator.LEVEL, z)
			if generator.is_chunk_allowed(sewer_coord) and generator.is_chunk_allowed(Vector3i(x, 0, z)):
				for link_value in generator.sewer().links_for(sewer_coord):
					var link: Dictionary = link_value
					add.call({"kind": "ladder", "x": x, "z": z, "lo": SewerRouteGenerator.LEVEL, "hi": 0,
						"cells": [LevelLink.cell_on(link, SewerRouteGenerator.LEVEL)], "landings": [], "label": link["id"]})
			for upper in [0, 1, 2, 3]:
				if not generator.is_chunk_allowed(Vector3i(x, upper, z)) or not generator.is_chunk_allowed(Vector3i(x, upper - 1, z)):
					continue
				var well: Dictionary = generator.stairwell_between(x, z, upper)
				if well.is_empty():
					continue
				add.call({"kind": String(well["kind"]), "x": x, "z": z, "lo": upper - 1, "hi": upper,
					"cells": (well["shaft"] as Dictionary).keys(),
					"landings": [[upper - 1, well["lower_landing"]], [upper, well["upper_landing"]]], "label": well["link"]["id"]})
			for upper in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
				if not generator.is_chunk_allowed(Vector3i(x, upper, z)) or not generator.is_chunk_allowed(Vector3i(x, upper - 1, z)):
					continue
				var ramp: Dictionary = generator.sewer().ramp_between(x, z, upper)
				if ramp.is_empty():
					continue
				add.call({"kind": "ramp", "x": x, "z": z, "lo": upper - 1, "hi": upper, "cells": _rect_cells(ramp["ramp"]),
					"landings": [[upper - 1, _rect_cells(ramp["bottom"])], [upper, _rect_cells(ramp["top"])]],
					"label": ramp["link"]["id"], "ramp": ramp})
			if generator.is_chunk_allowed(sewer_coord):
				var falls: Dictionary = generator.sewer().falls_between(x, z)
				if not falls.is_empty():
					add.call({"kind": "falls", "x": x, "z": z, "lo": SewerRouteGenerator.LOWER_LEVEL,
						"hi": SewerRouteGenerator.LEVEL, "cells": _rect_cells(falls["void"]), "landings": [],
						"label": "FALLS:%d:%d" % [x, z]})
	return out


static func _rect_cells(rect: Rect2i) -> Array:
	var out := []
	for z in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			out.append(Vector2i(x, z))
	return out


func _audit_seed(host: Node, seed_text: String) -> void:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	view.generator = StreamedRouteGenerator.new(seed_text)
	view.world_state = StreamedWorldState.new()
	var built := {}
	for entry_value in _links(view.generator):
		var entry: Dictionary = entry_value
		var roots := {}
		for level in [int(entry["lo"]), int(entry["hi"])]:
			var coord := Vector3i(int(entry["x"]), level, int(entry["z"]))
			if not built.has(coord):
				view._load_chunk(coord)
				built[coord] = view.get_node("Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z])
			roots[level] = built[coord]
		_counts[entry["kind"]] = int(_counts.get(entry["kind"], 0)) + 1
		_pairs["%d/%d" % [entry["hi"], entry["lo"]]] = true
		_audit_link(view, seed_text, entry, roots)
		await host.get_tree().process_frame
	# the per-chunk layer pass is one build step: keep it well inside a streaming frame
	for coord in built:
		var started := Time.get_ticks_usec()
		StoreyLayers.apply(built[coord], coord.y)
		_worst_layers_usec = maxi(_worst_layers_usec, Time.get_ticks_usec() - started)
	# storey seams and doubles across every chunk built for the seed
	for coord in built:
		_check_z_fighting(seed_text, coord, built[coord])
	for coord in built:
		var above := Vector3i(coord.x, coord.y + 1, coord.z)
		if built.has(above):
			_check_contained(view, seed_text, coord, built[coord], built[above])
	view.clear()
	view.queue_free()
	await host.get_tree().process_frame


## Quads of a chunk's RefSurfaceMesh in chunk-local coordinates: [a, c, normal, surface] (a and c opposite corners).
static func _quads(root: Node) -> Array:
	var out := []
	for node in root.find_children("Surface", "MeshInstance3D", true, false):
		var mesh := (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			for q in range(0, verts.size(), 4):
				out.append([verts[q], verts[q + 2], normals[q], surface])
	return out


static func _heights(root: Node) -> Dictionary:
	return root.get_meta("ref_heights", {})


static func _height(root: Node, cell: Vector2i) -> float:
	return float(_heights(root).get(cell, float(root.get_meta("ref_corridor_h", 3.0))))


## Air at a chunk cell on its own level: walkable floor, a channel, the falls, a stairwell or a ramp tunnel.
static func _open(data: Dictionary, cell: Vector2i) -> bool:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	if cell.x < 0 or cell.y < 0 or cell.x >= size or cell.y >= size:
		return false
	if int((data["grid"] as Array)[cell.y][cell.x]) == 0:
		return true
	if (data.get("shaft_cells", {}) as Dictionary).has(cell) or (data.get("ramp_cells", {}) as Dictionary).has(cell):
		return true
	var sewer_grid: Array = data.get("sewer_grid", [])
	return not sewer_grid.is_empty() \
		and int(sewer_grid[cell.y][cell.x]) in [SewerRouteGenerator.WATER, SewerRouteGenerator.FALL]


func _audit_link(view: StreamedFacilityView3D, seed_text: String, entry: Dictionary, roots: Dictionary) -> void:
	var kind := String(entry["kind"])
	var lo := int(entry["lo"])
	var hi := int(entry["hi"])
	var where := "%s %s" % [seed_text, entry["label"]]
	var inside := {}
	for cell in entry["cells"]:
		inside[cell] = true
	# quads of both storeys, y measured from the lower storey's floor
	var quads := []
	for level in [lo, hi]:
		for quad_value in _quads(roots[level]):
			var quad: Array = quad_value
			var lift := Vector3(0, (level - lo) * H, 0)
			quads.append([(quad[0] as Vector3) + lift, (quad[1] as Vector3) + lift, quad[2], quad[3]])
	if kind != "ramp":
		_check_clear(where, kind, inside, roots[hi], quads)
		_check_watertight(view, where, kind, entry, inside, roots, quads)
	for landing_value in entry["landings"]:
		var level := int((landing_value as Array)[0])
		_check_landing(where, kind, level - lo, (landing_value as Array)[1], quads,
			view.generator.chunk(Vector3i(int(entry["x"]), level, int(entry["z"]))))
	_check_light(where, kind, entry, inside, roots)
	var layers := {}
	for level in [lo, hi]:
		var surface := (roots[level] as Node).get_node_or_null("Surface") as VisualInstance3D
		layers[level] = surface.layers if surface != null else 0
	if int(layers[lo]) & int(layers[hi]) != 0:
		_report(kind, "light", "%s: both storeys' structure on one render layer (%s), so their lights cannot be kept apart" % [
			where, layers])


## No flat face over the opening between just above the lower floor and the upper storey's floor (inclusive).
func _check_clear(where: String, kind: String, inside: Dictionary, upper: Node, quads: Array) -> void:
	var bad := []
	for quad_value in quads:
		var quad: Array = quad_value
		var a: Vector3 = quad[0]
		var c: Vector3 = quad[1]
		if absf(a.y - c.y) > .001 or a.y < .3 or a.y > H + .05:
			continue
		var cell := Vector2i(floori((a.x + c.x) * .5), floori((a.z + c.z) * .5))
		if inside.has(cell):
			bad.append("%s y %.2f" % [cell, a.y])
	if not bad.is_empty():
		_report(kind, "slab", "%s: %d floor/ceiling faces across the opening (%s)" % [where, bad.size(), ", ".join(bad.slice(0, 5))])


## Each side of the opening, at every height from the lower floor to the upper storey's ceiling over it, is open into
## a room of the storey at that height or closed by a wall face looking into the opening.
func _check_watertight(view: StreamedFacilityView3D, where: String, kind: String, entry: Dictionary, inside: Dictionary,
		roots: Dictionary, quads: Array) -> void:
	var lo := int(entry["lo"])
	var hi := int(entry["hi"])
	var data := {lo: view.generator.chunk(Vector3i(int(entry["x"]), lo, int(entry["z"]))),
		hi: view.generator.chunk(Vector3i(int(entry["x"]), hi, int(entry["z"])))}
	# wall faces by plane: "x|z:coord*1000:sign" -> [[lo_along, hi_along, y0, y1]]
	var walls := {}
	for quad_value in quads:
		var quad: Array = quad_value
		var n: Vector3 = quad[2]
		if int(quad[3]) != 1 or absf(n.y) > .5:
			continue
		var a: Vector3 = quad[0]
		var c: Vector3 = quad[1]
		var key := ""
		var along := Vector2.ZERO
		if absf(n.x) > .5 and absf(a.x - c.x) < .001:
			key = "x:%d:%d" % [roundi(a.x * 1000), signi(roundi(n.x))]
			along = Vector2(minf(a.z, c.z), maxf(a.z, c.z))
		elif absf(n.z) > .5 and absf(a.z - c.z) < .001:
			key = "z:%d:%d" % [roundi(a.z * 1000), signi(roundi(n.z))]
			along = Vector2(minf(a.x, c.x), maxf(a.x, c.x))
		else:
			continue
		if not walls.has(key):
			walls[key] = []
		(walls[key] as Array).append([along.x, along.y, minf(a.y, c.y), maxf(a.y, c.y)])
	var gaps := []
	var backs := 0
	for cell_value in inside:
		var cell: Vector2i = cell_value
		var top := H + _height(roots[hi], cell)
		for step_value in RefDecor.DIRS:
			var step: Vector2i = step_value
			var n := cell + step
			if inside.has(n):
				continue
			# the plane between the two cells and the facing a wall looking into the opening has
			var axis := "x" if step.x != 0 else "z"
			var plane := float(cell.x + maxi(step.x, 0)) if step.x != 0 else float(cell.y + maxi(step.y, 0))
			var along := (float(cell.y) if step.x != 0 else float(cell.x)) + .5
			var face_sign := -(step.x + step.y)
			var front: Array = walls.get("%s:%d:%d" % [axis, roundi(plane * 1000), face_sign], [])
			var back: Array = walls.get("%s:%d:%d" % [axis, roundi(plane * 1000), -face_sign], [])
			var missing := []
			var y := STEP * .5
			while y < top - .05:
				var level := lo if y < H else hi
				var local := y - (H if level == hi else 0.0)
				var air := _open(data[level], n) and local <= _height(roots[level], n) + .001
				if not air and not _covered(front, along, y):
					missing.append(y)
					if _covered(back, along, y):
						backs += 1
				y += STEP
			if not missing.is_empty():
				gaps.append("%s->%s y %.1f-%.1f" % [cell, n, missing[0], missing[missing.size() - 1]])
	if not gaps.is_empty():
		_report(kind, "gap", "%s: %d open sides into the void (%d samples show a back face): %s" % [
			where, gaps.size(), backs, ", ".join(gaps.slice(0, 5))])


static func _covered(faces: Array, along: float, y: float) -> bool:
	for face_value in faces:
		var face: Array = face_value
		if float(face[0]) <= along and along <= float(face[1]) and float(face[2]) - .001 <= y and y <= float(face[3]) + .001:
			return true
	return false


## A landing cell has a floor face at its own storey's floor (y measured from the lower storey's floor).
func _check_landing(where: String, kind: String, offset: int, cells_value: Variant, quads: Array, data: Dictionary) -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cells: Array = (cells_value as Dictionary).keys() if cells_value is Dictionary else cells_value
	# a landing running on over the chunk edge is the next chunk's to floor
	cells = cells.filter(func(cell: Vector2i) -> bool: return cell.x >= 0 and cell.y >= 0 and cell.x < size and cell.y < size)
	var floors := {}
	for quad_value in quads:
		var quad: Array = quad_value
		var a: Vector3 = quad[0]
		var c: Vector3 = quad[1]
		if int(quad[3]) == 0 and (quad[2] as Vector3).y > .5 and absf(a.y - c.y) < .001 and absf(a.y - offset * H) < .05:
			floors[Vector2i(floori((a.x + c.x) * .5), floori((a.z + c.z) * .5))] = true
	# a landing cell the level keeps as brick (the Inferno's edge column beside a ramp's foot) is no hole
	var bare := cells.filter(func(cell: Vector2i) -> bool:
		return not floors.has(cell) and int((data["grid"] as Array)[cell.y][cell.x]) == 0)
	if not bare.is_empty():
		var codes := bare.slice(0, 5).map(func(cell: Vector2i) -> String:
			var sewer_grid: Array = data.get("sewer_grid", [])
			return "%s grid %d%s" % [cell, int((data["grid"] as Array)[cell.y][cell.x]),
				"" if sewer_grid.is_empty() else " sewer %d" % int(sewer_grid[cell.y][cell.x])])
		_report(kind, "landing", "%s: %d landing cells on %+d have no floor at their storey's floor (%s)" % [
			where, bare.size(), offset, ", ".join(codes)])


## Same-facing faces sharing a plane and overlapping: they z-fight wherever both are drawn.
func _check_z_fighting(seed_text: String, coord: Vector3i, root: Node) -> void:
	var planes := {}
	for quad_value in _quads(root):
		var quad: Array = quad_value
		var a: Vector3 = quad[0]
		var c: Vector3 = quad[1]
		var n: Vector3 = quad[2]
		var key := ""
		var rect := Rect2()
		if absf(n.y) > .5 and absf(a.y - c.y) < .001:
			key = "y:%d:%d" % [roundi(a.y * 200), signi(roundi(n.y))]
			rect = Rect2(Vector2(minf(a.x, c.x), minf(a.z, c.z)), Vector2(absf(a.x - c.x), absf(a.z - c.z)))
		elif absf(n.x) > .5 and absf(a.x - c.x) < .001:
			key = "x:%d:%d" % [roundi(a.x * 200), signi(roundi(n.x))]
			rect = Rect2(Vector2(minf(a.z, c.z), minf(a.y, c.y)), Vector2(absf(a.z - c.z), absf(a.y - c.y)))
		elif absf(n.z) > .5 and absf(a.z - c.z) < .001:
			key = "z:%d:%d" % [roundi(a.z * 200), signi(roundi(n.z))]
			rect = Rect2(Vector2(minf(a.x, c.x), minf(a.y, c.y)), Vector2(absf(a.x - c.x), absf(a.y - c.y)))
		else:
			continue
		if not planes.has(key):
			planes[key] = []
		(planes[key] as Array).append(rect)
	var fights := []
	for key in planes:
		var rects: Array = planes[key]
		if rects.size() < 2:
			continue
		# bucket by the integer cell of each rect's corner so the pair test stays near-linear
		var buckets := {}
		for i in rects.size():
			var r: Rect2 = rects[i]
			for bx in range(floori(r.position.x), floori(r.end.x - .001) + 1):
				var bucket := Vector2i(bx, floori(r.position.y))
				if not buckets.has(bucket):
					buckets[bucket] = []
				(buckets[bucket] as Array).append(i)
		var seen := {}
		for bucket in buckets:
			var list: Array = buckets[bucket]
			for i in list.size():
				for j in range(i + 1, list.size()):
					var pair := Vector2i(int(list[i]), int(list[j]))
					if seen.has(pair):
						continue
					seen[pair] = true
					var overlap := (rects[pair.x] as Rect2).intersection(rects[pair.y])
					if overlap.get_area() > FIGHT_AREA:
						fights.append("%s at %s" % [key, overlap.position])
	if not fights.is_empty():
		_report("chunk", "z_fight", "%s %s: %d coplanar same-facing face pairs (%s)" % [
			seed_text, coord, fights.size(), ", ".join(fights.slice(0, 5))])


## No face of one storey reaches into the open air of the next one up or down, except in a link's opening.
func _check_contained(view: StreamedFacilityView3D, seed_text: String, coord: Vector3i, lower: Node, upper: Node) -> void:
	var lower_data := view.generator.chunk(coord)
	var upper_data := view.generator.chunk(Vector3i(coord.x, coord.y + 1, coord.z))
	var links := _link_cells(view.generator, coord)
	var pokes := []
	for quad_value in _quads(lower):
		var quad: Array = quad_value
		var top := maxf((quad[0] as Vector3).y, (quad[1] as Vector3).y)
		if top <= H + POKE:
			continue
		var cell := _quad_cell(quad)
		if links.has(cell) or not _open(upper_data, cell):
			continue
		if top - H > 0.0:
			pokes.append("level %d up %s to %.2f" % [coord.y, cell, top])
	for quad_value in _quads(upper):
		var quad: Array = quad_value
		var bottom := minf((quad[0] as Vector3).y, (quad[1] as Vector3).y)
		if bottom >= -POKE:
			continue
		var cell := _quad_cell(quad)
		if links.has(cell) or not _open(lower_data, cell):
			continue
		if H + bottom < _height(lower, cell) - POKE:
			pokes.append("level %d down %s to %.2f" % [coord.y + 1, cell, bottom])
	if not pokes.is_empty():
		_report("storey", "poke", "%s %s: %d faces reach into the other storey's air (%s)" % [
			seed_text, coord, pokes.size(), ", ".join(pokes.slice(0, 5))])


## Cells of a column's links between `coord`'s level and the one above, with a ring around each (their linings).
static func _link_cells(generator: StreamedRouteGenerator, coord: Vector3i) -> Dictionary:
	var cells := []
	if coord.y == SewerRouteGenerator.LEVEL:
		for link in generator.sewer().links_for(coord):
			cells.append(LevelLink.cell_on(link, coord.y))
	var well := generator.stairwell_between(coord.x, coord.z, coord.y + 1)
	if not well.is_empty():
		cells.append_array((well["shaft"] as Dictionary).keys())
	if coord.y + 1 in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
		var ramp := generator.sewer().ramp_between(coord.x, coord.z, coord.y + 1)
		if not ramp.is_empty():
			cells.append_array(_rect_cells(ramp["ramp"]))
	if coord.y == SewerRouteGenerator.LOWER_LEVEL:
		var falls := generator.sewer().falls_between(coord.x, coord.z)
		if not falls.is_empty():
			cells.append_array(_rect_cells(falls["void"]))
	var out := {}
	for cell_value in cells:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				out[(cell_value as Vector2i) + Vector2i(dx, dz)] = true
	return out


static func _quad_cell(quad: Array) -> Vector2i:
	var a: Vector3 = quad[0]
	var c: Vector3 = quad[1]
	var n: Vector3 = quad[2]
	# a wall's cell is the one it faces into
	var centre := (a + c) * .5 + Vector3(n.x, 0, n.z) * .5
	return Vector2i(floori(centre.x), floori(centre.z))


## Real lights in the link's chunks cast no shadows: one whose sphere crosses the slab away from the opening lights
## the other storey's walls straight through the floor.
func _check_light(where: String, kind: String, entry: Dictionary, inside: Dictionary, roots: Dictionary) -> void:
	var lo := int(entry["lo"])
	var leaks := []
	# the pool lamps follow the same rule (LampField._home)
	for level in [lo, lo + 1]:
		if StoreyLayers.light_mask(level) & StoreyLayers.structure_layer(level + 1 if level == lo else lo) != 0:
			leaks.append("lamp pool on %d lights the neighbouring storey's layer" % level)
	for level in roots:
		var root := roots[level] as Node3D
		for light_value in root.find_children("*", "OmniLight3D", true, false):
			var light := light_value as OmniLight3D
			var other := int(level) + 1 if int(level) == lo else int(level) - 1
			var other_root := roots[lo if int(level) != lo else int(entry["hi"])] as Node3D
			var other_surface := other_root.get_node_or_null("Surface") as VisualInstance3D
			if light.shadow_enabled or (other_surface != null and light.light_cull_mask & other_surface.layers == 0):
				continue
			var at := light.global_position - root.global_position
			var cell := Vector2i(floori(at.x), floori(at.z))
			var near_opening := false
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if inside.has(cell + Vector2i(dx, dz)):
						near_opening = true
			if near_opening:
				continue
			# how strongly it lights the nearest air of the other storey, straight through the slab (Godot's omni
			# falloff: (1 - (d / range)^4)^2 * d^-attenuation)
			var d := H - at.y if int(level) == lo else at.y + H - _height(roots[lo], cell)
			if d <= 0.0 or d >= light.omni_range:
				continue
			var falloff := pow(maxf(1.0 - pow(d / light.omni_range, 4.0), 0.0), 2.0) * pow(maxf(d, .0001), -light.omni_attenuation)
			if light.light_energy * falloff > LIGHT_LEAK:
				leaks.append("%s on %d at %s (range %.1f, %.2f through)" % [light.name, level, at.snapped(Vector3.ONE * .1),
					light.omni_range, light.light_energy * falloff])
	if not leaks.is_empty():
		_report(kind, "light", "%s: %d shadowless lights reach the other storey through the slab (%s)" % [
			where, leaks.size(), ", ".join(leaks.slice(0, 4))])
