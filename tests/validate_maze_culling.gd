extends RefCounted

## Maze culling (StreamedFacilityView3D._update_maze_culling): at sampled positions along a route, every prop whose cell
## a straight line of sight reaches through open cells (closed doors block) must be visible -- no popping -- and the
## culling must actually hide something. Prints how many prop visuals were culled. The culled surface tiles must hold
## exactly the geometry of the single surface mesh (a bug once built every tile empty: no walls, floors or ceilings), and
## on the sewer levels and the Mezzanine the tile under the runner must be drawn with geometry in it.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- maze_culling

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _open(facility: StreamedFacilityView3D, cell: Vector2i, level: int) -> bool:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var coord := Vector3i(floori(float(cell.x) / size), level, floori(float(cell.y) / size))
	var data: Dictionary = facility._chunk_data.get(coord, {})
	var grid: Array = data.get("grid", [])
	var lx := posmod(cell.x, size)
	var lz := posmod(cell.y, size)
	return not grid.is_empty() and int(grid[lz][lx]) == 0


## Line of sight between cell centres through open cells (sampled every 0.25 m; any wall cell on the way blocks).
static func _sight(facility: StreamedFacilityView3D, from: Vector2, to: Vector2, level: int) -> bool:
	var steps := int(from.distance_to(to) / .25) + 1
	for i in range(1, steps):
		var p := from.lerp(to, float(i) / steps)
		var c := Vector2i(floori(p.x), floori(p.y))
		if c == Vector2i(floori(to.x), floori(to.y)):
			return true
		if not _open(facility, c, level):
			return false
	return true


## build_tiles() splits build()'s geometry by tile: same vertex count per surface, nothing lost, nothing empty.
func _tile_geometry() -> void:
	var surface := RefSurfaceMesh.new()
	for x in range(0, 45, 7):
		for z in range(0, 45, 11):
			surface.add_floor(x, z, 1.0, Color.WHITE)
			surface.add_ceiling(x, z, 3.5, 2.0, Color.WHITE)
			surface.add_wall(x, z, Vector2i(1, 0), 3.0, Color.WHITE, 3.5)
	var whole := surface.build(null, null)
	var tiles := surface.build_tiles(null, null)
	var empty := 0
	for t in tiles:
		var mesh: ArrayMesh = tiles[t]
		if mesh.get_surface_count() == 0:
			empty += 1
	# surfaces per tile: floors (incl. ceilings) first, then walls, as in build()
	var floor_vertices := 0
	var wall_vertices := 0
	for t in tiles:
		var mesh: ArrayMesh = tiles[t]
		for i in mesh.get_surface_count():
			var n := mesh.surface_get_array_len(i)
			var is_wall := (mesh.surface_get_arrays(i)[Mesh.ARRAY_NORMAL] as PackedVector3Array)[0].y == 0.0
			if is_wall:
				wall_vertices += n
			else:
				floor_vertices += n
	_expect(empty == 0, "%d surface tiles were built with no geometry" % empty)
	_expect(tiles.size() == 9, "expected 9 tiles over a 45 x 45 chunk, got %d" % tiles.size())
	_expect(floor_vertices == whole.surface_get_array_len(0) and wall_vertices == whole.surface_get_array_len(1),
		"tiles hold %d floor / %d wall vertices, the single mesh %d / %d" % [floor_vertices, wall_vertices,
		whole.surface_get_array_len(0), whole.surface_get_array_len(1)])


## Every loaded surface tile has geometry (an empty tile draws nothing: missing walls, floors, ceilings).
func _tiles_have_geometry(host: Node, where: String) -> Vector2i:
	var empty := 0
	var total := 0
	for node in host.get_tree().get_nodes_in_group("cull_tile"):
		var mesh := (node as MeshInstance3D).mesh
		total += 1
		if mesh == null or mesh.get_surface_count() == 0 or mesh.surface_get_array_len(0) == 0:
			empty += 1
	_expect(total > 0, "%s: no surface tiles loaded" % where)
	_expect(empty == 0, "%s: %d of %d surface tiles have no geometry (walls/floors/ceilings missing)" % [where, empty, total])
	return Vector2i(total, empty)


## On another storey (the sewers, the Mezzanine): stand on an open cell and require the tile under the runner to be
## drawn and to hold geometry, i.e. the walls round the spawn view are there with culling on.
func _storey_check(host: Node, facility: StreamedFacilityView3D, player: PlayerController3D, level: int, label: String) -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var start := player.global_position - facility.global_position
	var base := Vector2i(floori(start.x / size), floori(start.z / size))
	var spot := Vector2i(999999, 999999)
	for ring in 4:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				var coord := Vector3i(base.x + dx, level, base.y + dz)
				if spot.x != 999999 or not facility.generator.is_chunk_allowed(coord):
					continue
				var grid: Array = facility.generator.chunk(coord).get("grid", [])
				for z in range(2, size - 2):
					for x in range(2, size - 2):
						if spot.x == 999999 and int(grid[z][x]) == 0 and int(grid[z][x + 1]) == 0 and int(grid[z + 1][x]) == 0:
							spot = Vector2i(coord.x * size + x, coord.z * size + z)
	if spot.x == 999999:
		print("  maze_culling  %s: no open cell near the start, skipped" % label)
		return
	player.global_position = facility.global_position + Vector3(spot.x + .5, level * StreamedFacilityView3D.LEVEL_HEIGHT + .05, spot.y + .5)
	for _i in 600:
		await host.get_tree().process_frame
		if facility.current_level() == level and facility._cull_task == -1 and facility._cull_cell == spot \
				and not facility.is_streaming():
			break
	await host.get_tree().process_frame
	_expect(facility.current_level() == level, "%s: the runner is on level %d, not %d" % [label, facility.current_level(), level])
	var key := Vector2i(floori(float(spot.x) / RefSurfaceMesh.TILE), floori(float(spot.y) / RefSurfaceMesh.TILE))
	var found := false
	for node in host.get_tree().get_nodes_in_group("cull_tile"):
		var tile := node as MeshInstance3D
		if tile.get_meta("cull_tile") != key or roundi((tile.get_parent() as Node3D).position.y / StreamedFacilityView3D.LEVEL_HEIGHT) != level:
			continue
		found = true
		_expect(tile.is_visible_in_tree(), "%s: the surface tile under the runner (%s) is hidden" % [label, key])
		_expect(tile.mesh != null and tile.mesh.get_surface_count() > 0, "%s: the surface tile under the runner is empty" % label)
	_expect(found, "%s: no surface tile under the runner at %s" % [label, spot])
	var tiles := _tiles_have_geometry(host, label)
	print("  maze_culling  %s: %d surface tiles loaded, %d empty; %d of %d on this storey hidden" % [label, tiles.x, tiles.y,
		facility.maze_cull_tiles_hidden, facility.maze_cull_tiles])


func run(host: Node) -> int:
	_tile_geometry()
	var was := PlatformProfile.maze_culling
	PlatformProfile.maze_culling = true   # before the scene: chunks build their surfaces as cullable tiles
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "STREAM-BENCH"
	var scene: Node = (load("res://game/infinite_route/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(scene)
	var facility: StreamedFacilityView3D = scene.get_node("%StreamedFacility")
	var player: PlayerController3D = scene.get_node("%Player")
	for _i in 20:
		await host.get_tree().process_frame
	player.admin_god_mode = true
	player.set_physics_process(false)
	var start := player.global_position
	var checked := 0
	var popped := 0
	var hidden_total := 0
	var props_total := 0
	var tiles_hidden := 0
	var tiles_total := 0
	var tiles_popped := 0
	for sample in 16:
		var target := start + Vector3(sample * 6.0, 0, (sample % 4) * 3.0)
		player.global_position = target
		for _i in 240:
			await host.get_tree().process_frame
			if facility._cull_task == -1 and facility._cull_cell == Vector2i(floori(target.x), floori(target.z)) \
					and not facility.is_streaming():
				break
		await host.get_tree().process_frame
		var eye := Vector2(floori(target.x) + .5, floori(target.z) + .5)
		var level := facility.current_level()
		for node in host.get_tree().get_nodes_in_group("cull_prop"):
			var prop := node as Node3D
			var root := prop.get_parent() as Node3D
			if root == null or not root.visible or roundi(root.position.y / StreamedFacilityView3D.LEVEL_HEIGHT) != level:
				continue
			var cell: Vector2i = prop.get_meta("cull_cell", Vector2i.ZERO)
			var at := Vector2(cell.x + .5, cell.y + .5)
			if at.distance_to(eye) > StreamedFacilityView3D.MAZE_CULL_RADIUS - 2:
				continue
			if _sight(facility, eye, at, level):
				checked += 1
				if not prop.visible:
					popped += 1
					if popped <= 5:
						print("  popped: %s at %s seen from %s" % [prop.get_meta("streamed_prop_type", "?"), cell, eye])
		hidden_total += facility.maze_cull_hidden
		props_total += facility.maze_cull_props
		tiles_hidden += facility.maze_cull_tiles_hidden
		tiles_total += facility.maze_cull_tiles
		# every surface tile holding a cell in line of sight must be drawn
		for node in host.get_tree().get_nodes_in_group("cull_tile"):
			var tile := node as Node3D
			if tile.visible or roundi((tile.get_parent() as Node3D).position.y / StreamedFacilityView3D.LEVEL_HEIGHT) != level:
				continue
			var key: Vector2i = tile.get_meta("cull_tile")
			var size := RefSurfaceMesh.TILE
			for dz in size:
				for dx in size:
					var at := Vector2(key.x * size + dx + .5, key.y * size + dz + .5)
					if at.distance_to(eye) < StreamedFacilityView3D.MAZE_CULL_RADIUS - 2 and _open(facility, Vector2i(floori(at.x), floori(at.y)), level) \
							and _sight(facility, eye, at, level):
						tiles_popped += 1
						break
	_tiles_have_geometry(host, "route")
	await _storey_check(host, facility, player, StreamedRouteGenerator.SEWER_LEVEL, "sewer")
	await _storey_check(host, facility, player, StreamedRouteGenerator.LOWER_SEWER_LEVEL, "lower sewer")
	await _storey_check(host, facility, player, StreamedRouteGenerator.MEZZANINE_LEVEL, "Mezzanine")
	PlatformProfile.maze_culling = was
	_expect(checked > 50, "only %d visible props were checked" % checked)
	_expect(popped == 0, "%d props in line of sight were hidden (popping)" % popped)
	_expect(hidden_total > 0, "maze culling hid nothing")
	_expect(tiles_popped == 0, "%d surface tiles with an open cell in line of sight were hidden (walls/floors popping)" % tiles_popped)
	_expect(tiles_hidden > 0, "no wall/floor tile was culled")
	print("  maze_culling  %d props in sight all visible; culled %.0f%% of prop visuals and %.0f%% of wall/floor tiles (%d of %d) over 16 spots" % [
		checked, 100.0 * hidden_total / maxf(props_total, 1), 100.0 * tiles_hidden / maxf(tiles_total, 1), tiles_hidden, tiles_total])
	scene.queue_free()
	await host.get_tree().process_frame
	return _failures
