extends RefCounted

## Ceiling gaps ("small air gap above doors still"): builds real streamed chunks on every level and in every region
## they reach, finds every framed opening (a doorway cell between two walls with a door, gate, frame or partition
## standing in it) and casts rays through it from both sides above the frame, up to the viewer's ceiling. Every ray
## must hit drawn geometry (the frame, a header, a lintel, the wall) before it leaves the doorway: no strip of open air
## between a door or wall top and the ceiling.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- ceiling_gaps

const SEEDS := ["CEIL-GAP-A", "CEIL-GAP-B", "ENDLESS-ROUTE"]
const LEVELS := [-1, 0, 1, 2]
const PER_REGION := 2
## A mesh counts as a frame in a doorway when it stands this tall and spans this much of the opening.
const FRAME_MIN_TOP := 1.5
const FRAME_MIN_SPAN := .6

var _failures := 0
var _openings := 0
var _kinds := {}
var _regions := {}
var _chunks := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		if _failures < 40:
			print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	for seed_text in SEEDS:
		var view := StreamedFacilityView3D.new()
		host.add_child(view)
		view.generator = StreamedRouteGenerator.new(seed_text)
		view.world_state = StreamedWorldState.new()
		for coord in _pick_chunks(view.generator):
			view._load_chunk(coord)
			var root := view.get_node("Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]) as Node3D
			_chunks["%d %s" % [coord.y, view.generator.region_for(coord)]] = true
			_audit_chunk(view, root, coord, seed_text)
			root.queue_free()
			await host.get_tree().process_frame
		view.queue_free()
		await host.get_tree().process_frame
	await _sweep_sewers(host)
	_expect(_openings >= 30, "only %d framed openings found" % _openings)
	print("  ceiling_gaps  chunks swept (level region): %s" % str(_chunks.keys()))
	print("  ceiling_gaps  %d framed openings in %s; frames %s: %d gaps" % [_openings, str(_regions.keys()), str(_kinds), _failures])
	return _failures


func _pick_chunks(generator: StreamedRouteGenerator) -> Array:
	var out := []
	var taken := {}
	for level in LEVELS:
		for r in range(0, 14):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, level, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var key := "%d %s" % [level, generator.region_for(coord)]
					if int(taken.get(key, 0)) >= PER_REGION:
						continue
					taken[key] = int(taken.get(key, 0)) + 1
					out.append(coord)
	return out


## [global aabb, mesh-ish node] for every drawn mesh of the chunk (MultiMesh instances one by one).
func _drawn(root: Node3D, culled_too := false) -> Array:
	var out := []
	for node in root.find_children("*", "GeometryInstance3D", true, false):
		# culled_too: the maze-culling tiles a line of sight has not reached yet count (they are drawn once seen)
		if not (node as Node3D).is_visible_in_tree() and not (culled_too and String(node.name).begins_with("Ref_")):
			continue
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			var mesh := node as MeshInstance3D
			out.append([mesh.global_transform * mesh.get_aabb(), mesh.global_transform, mesh.mesh, mesh])
		elif node is MultiMeshInstance3D and (node as MultiMeshInstance3D).multimesh != null:
			var multi := (node as MultiMeshInstance3D).multimesh
			if multi.mesh == null or multi.transform_format != MultiMesh.TRANSFORM_3D:
				continue
			for i in multi.visible_instance_count if multi.visible_instance_count >= 0 else multi.instance_count:
				var xf := (node as Node3D).global_transform * multi.get_instance_transform(i)
				out.append([xf * multi.mesh.get_aabb(), xf, multi.mesh, node])
	return out


func _audit_chunk(view: StreamedFacilityView3D, root: Node3D, coord: Vector3i, seed_text: String) -> void:
	var data := view.generator.chunk(coord)
	var grid: Array = data.get("grid", [])
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var region := view.generator.region_for(coord)
	var drawn := _drawn(root)
	var open := func(x: int, z: int) -> bool:
		return x >= 0 and z >= 0 and z < grid.size() and x < (grid[z] as Array).size() and int(grid[z][x]) == 0
	for z in size:
		for x in size:
			if not open.call(x, z):
				continue
			for axis in [Vector2i(1, 0), Vector2i(0, 1)]:
				var perp := Vector2i(axis.y, axis.x)
				if not (open.call(x + axis.x, z + axis.y) and open.call(x - axis.x, z - axis.y)):
					continue
				var x_in := x + perp.x >= 0 and x + perp.x < size and z + perp.y >= 0 and z + perp.y < size \
					and x - perp.x >= 0 and x - perp.x < size and z - perp.y >= 0 and z - perp.y < size
				if not x_in or open.call(x + perp.x, z + perp.y) or open.call(x - perp.x, z - perp.y):
					continue
				_audit_opening(view, root, drawn, Vector2i(x, z), axis, "%s %s %s (%d,%d) %s" % [seed_text, region, coord, x, z, axis])


func _audit_opening(view: StreamedFacilityView3D, root: Node3D, drawn: Array, cell: Vector2i, axis: Vector2i, where: String) -> void:
	var centre := root.global_transform * Vector3(cell.x + .5, 0.0, cell.y + .5)
	var floor_y := centre.y
	var across := Vector3(axis.x, 0, axis.y)
	var along := Vector3(axis.y, 0, axis.x)
	var column := AABB(centre + Vector3(-.5, 0, -.5), Vector3(1.0, 6.0, 1.0)).grow(-.05)
	var frame_top := -1.0
	var frame_name := ""
	for entry in drawn:
		var box: AABB = entry[0]
		# the chunk's own surfaces (walls, floors, ceilings, headers) span the whole chunk: they are what the rays should hit
		if box.size.x > 3.0 and box.size.z > 3.0:
			continue
		if not box.intersects(column) or _is_pipe(entry[3] as Node):
			continue
		var span := box.size.x if axis.x == 0 else box.size.z
		if box.end.y - floor_y < FRAME_MIN_TOP or span < FRAME_MIN_SPAN:
			continue
		if box.end.y - floor_y > frame_top:
			frame_top = box.end.y - floor_y
			frame_name = _label(entry[3] as Node, root)
	if frame_top < 0.0:
		return
	_openings += 1
	_kinds[frame_name] = int(_kinds.get(frame_name, 0)) + 1
	_regions[where.split(" ")[1]] = true
	var faces := _faces_near(drawn, AABB(centre + Vector3(-1.6, -.2, -1.6), Vector3(3.2, 7.0, 3.2)))
	for side: int in [1, -1]:
		var viewer: Vector2i = cell + axis * side
		var ceiling := view._cell_height(root, viewer)
		var low := frame_top + .04
		var high := ceiling - .04
		if high <= low:
			continue
		for y in [low, (low + high) * .5, high]:
			for slide in [-.35, 0.0, .35]:
				var from: Vector3 = centre + across * (.9 * side) + along * float(slide) + Vector3.UP * float(y)
				_expect(_hits(faces, from, -across * side, 1.45),
					"%s: open air over the %s (top %.2f m) at %.2f m from the %s side, ceiling %.2f m" % [
						where, frame_name, frame_top, y, "+" if side > 0 else "-", ceiling])


## A sewer pipe crossing overhead is not a frame in a doorway (the crawl-under pipes span the walkway at head height).
func _is_pipe(node: Node) -> bool:
	var walk := node
	while walk != null:
		if walk is RouteInteractable3D and String((walk as RouteInteractable3D).breakable_spec.get("kind", "")) == Breach.KIND_PIPE:
			return true
		walk = walk.get_parent()
	return false


func _label(node: Node, root: Node) -> String:
	var walk := node
	while walk != null and walk.get_parent() != root:
		walk = walk.get_parent()
	var name := String(walk.name if walk != null else node.name)
	var cut := name.find("_")
	return name.substr(0, cut) if cut > 0 else name.rstrip("0123456789@")


func _faces_near(drawn: Array, box: AABB) -> PackedVector3Array:
	var out := PackedVector3Array()
	for entry in drawn:
		if not (entry[0] as AABB).intersects(box):
			continue
		var xf: Transform3D = entry[1]
		var faces := (entry[2] as Mesh).get_faces()
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			if box.has_point(a) or box.has_point(b) or box.has_point(c) \
					or AABB(a, Vector3.ZERO).expand(b).expand(c).intersects(box):
				out.append(a)
				out.append(b)
				out.append(c)
	return out


func _hits(faces: PackedVector3Array, from: Vector3, direction: Vector3, reach: float) -> bool:
	for index in range(0, faces.size(), 3):
		var hit = Geometry3D.ray_intersects_triangle(from, direction, faces[index], faces[index + 1], faces[index + 2])
		if hit != null and from.distance_to(hit) < reach:
			return true
	return false


## ---------------------------------------------------------------- sewer storeys

## The sewers ("gap in sewers, assuming upper level?"): on -1 and -2 every step in the ceiling between two neighbouring
## open cells (walkway, channel, deck, drop, room) is closed by a drawn face, and every wall beside an open cell reaches
## that cell's ceiling: no strip of open air between a wall top and the ceiling or the floor above.
const SEWER_LEVELS := [-1, -2]
const SEWER_COLUMNS := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, -1), Vector2i(2, -1)]
const SEWER_OPEN := [SewerRouteGenerator.DRY, SewerRouteGenerator.WATER, SewerRouteGenerator.BRIDGE, SewerRouteGenerator.FALL]
var _sewer_steps := 0
var _sewer_walls := 0


func _sweep_sewers(host: Node) -> void:
	for seed_text in SEEDS:
		var view := StreamedFacilityView3D.new()
		host.add_child(view)
		view.generator = StreamedRouteGenerator.new(seed_text)
		view.world_state = StreamedWorldState.new()
		for level in SEWER_LEVELS:
			for column in SEWER_COLUMNS:
				var coord := Vector3i(column.x, level, column.y)
				if not view.generator.is_chunk_allowed(coord):
					continue
				view._load_chunk(coord)
				var root := view.get_node_or_null("Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]) as Node3D
				if root == null:
					continue
				_audit_sewer_chunk(view, root, coord, seed_text)
				root.queue_free()
				await host.get_tree().process_frame
		view.queue_free()
		await host.get_tree().process_frame
	_expect(_sewer_steps >= 50 and _sewer_walls >= 500, "the sewer sweep checked only %d ceiling steps and %d wall tops" % [_sewer_steps, _sewer_walls])
	print("  ceiling_gaps  sewers: %d ceiling steps and %d wall tops closed" % [_sewer_steps, _sewer_walls])


func _audit_sewer_chunk(view: StreamedFacilityView3D, root: Node3D, coord: Vector3i, seed_text: String) -> void:
	var data := view.generator.chunk(coord)
	var codes: Array = data.get("sewer_grid", [])
	if codes.is_empty():
		return
	var size := StreamedRouteGenerator.CHUNK_SIZE
	# every drawn triangle of the chunk, bucketed by the cells its footprint covers
	var buckets := {}
	for entry in _drawn(root, true):
		var xf: Transform3D = entry[1]
		var faces := _triangles(entry[2] as Mesh)
		for i in range(0, faces.size(), 3):
			var a := root.global_transform.affine_inverse() * (xf * faces[i])
			var b := root.global_transform.affine_inverse() * (xf * faces[i + 1])
			var c := root.global_transform.affine_inverse() * (xf * faces[i + 2])
			for bz in range(floori(minf(a.z, minf(b.z, c.z)) - .01), floori(maxf(a.z, maxf(b.z, c.z)) + .01) + 1):
				for bx in range(floori(minf(a.x, minf(b.x, c.x)) - .01), floori(maxf(a.x, maxf(b.x, c.x)) + .01) + 1):
					var key := Vector2i(bx, bz)
					var bucket: PackedVector3Array = buckets.get(key, PackedVector3Array())   # packed arrays copy: store it back
					bucket.append_array(PackedVector3Array([a, b, c]))
					buckets[key] = bucket
	var is_open := func(cell: Vector2i) -> bool:
		return int(codes[cell.y][cell.x]) in SEWER_OPEN
	var reported := 0
	# three cells in from the seams: the band along a chunk edge is closed by the neighbour chunk, built on its own here
	for z in range(3, size - 3):
		for x in range(3, size - 3):
			var cell := Vector2i(x, z)
			if not is_open.call(cell):
				continue
			var h := view._cell_height(root, cell)
			for step in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
				var n: Vector2i = cell + step
				var near := PackedVector3Array()
				near.append_array(buckets.get(cell, PackedVector3Array()))
				near.append_array(buckets.get(n, PackedVector3Array()))
				var dir := Vector3(step.x, 0, step.y)
				var centre := Vector3(x + .5, 0, z + .5)
				var problem := ""
				if is_open.call(n):
					var hn := view._cell_height(root, n)
					if hn >= h - .02:
						continue
					# a lower ceiling next door: the step between hn and h must be faced
					_sewer_steps += 1
					for y in [hn + .04, (hn + h) * .5, h - .04]:
						if not _hits(near, centre + Vector3.UP * float(y), dir, .75):
							problem = "open ceiling step %.2f -> %.2f m at %.2f m toward %s" % [h, hn, y, n]
							break
				elif int(codes[n.y][n.x]) == SewerRouteGenerator.SOLID:
					_sewer_walls += 1
					for y in [h - .3, h - .04]:
						if not _hits(near, centre + Vector3.UP * float(y), dir, .75):
							problem = "the wall toward %s stops below the %.2f m ceiling (open at %.2f m)" % [n, h, y]
							break
				if not problem.is_empty() and reported < 4:
					reported += 1
					_expect(false, "%s sewer %s cell %s: %s" % [seed_text, coord, cell, problem])
				elif not problem.is_empty():
					_failures += 1


## The mesh's triangles from its surface arrays (Mesh.get_faces() came back empty for the chunk's Surface ArrayMesh).
static func _triangles(mesh: Mesh) -> PackedVector3Array:
	var out := PackedVector3Array()
	for surface_index in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_index)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if arrays[Mesh.ARRAY_INDEX] == null or (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).is_empty():
			out.append_array(verts)
			continue
		for index in (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array):
			out.append(verts[index])
	return out
