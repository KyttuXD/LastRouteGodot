extends RefCounted

## Maze culling (StreamedFacilityView3D._update_maze_culling): at sampled positions along a route, every prop whose cell
## a straight line of sight reaches through open cells (closed doors block) must be visible -- no popping -- and the
## culling must actually hide something. Prints how many prop visuals were culled.
##
##   godot --headless --path . res://scenes/validate.tscn -- maze_culling

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


func run(host: Node) -> int:
	var was := PlatformProfile.maze_culling
	PlatformProfile.maze_culling = true   # before the scene: chunks build their surfaces as cullable tiles
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.seed_text = "STREAM-BENCH"
	var scene: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
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
