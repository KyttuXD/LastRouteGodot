extends RefCounted

## Headless check on the 3D maze's fabric.
##
## Three things were wrong in a live build and none of them are visible to a
## script that only reads the generator: the walls were imported models dropped
## into a cube grid and landed rotated, there was no ceiling at all, and the
## heater station spawned on the player's own spawn cell -- at arm's length,
## in the way.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- maze

var _host: Node
var _failures := 0


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func run(host: Node) -> int:
	_host = host
	var scene: Node = load("res://scenes/main_3d.tscn").instantiate()
	host.get_tree().root.add_child(scene)
	await host.get_tree().process_frame
	await host.get_tree().process_frame

	var view: FacilityView3D = scene.facility_view
	var grid: GridMap = view.get_child(0) as GridMap
	if grid == null:
		_fail("no GridMap under the facility view")
		scene.queue_free()
		return _failures

	# Cubes, not imported models: an item whose mesh is not a box can be
	# rotated wrongly by its own baked transform, which is the bug this fixes.
	var floors := 0
	var walls := 0
	var lids := 0
	for cell in grid.get_used_cells():
		match grid.get_cell_item(cell):
			FacilityView3D.ITEM_FLOOR: floors += 1
			FacilityView3D.ITEM_WALL: walls += 1
			FacilityView3D.ITEM_CEILING: lids += 1
	for id in [FacilityView3D.ITEM_FLOOR, FacilityView3D.ITEM_WALL,
			FacilityView3D.ITEM_CEILING]:
		if not grid.mesh_library.get_item_mesh(id) is BoxMesh:
			_fail("grid item %d is not a box, so it can carry a rotation" % id)
		# A cell is square to the grid, so an item that fills it must be too.
		if grid.mesh_library.get_item_mesh_transform(id).basis != Basis.IDENTITY:
			_fail("grid item %d is placed with a rotation" % id)
	if lids == 0:
		_fail("the maze still has no ceiling")
	elif lids != floors:
		_fail("%d ceiling cells over %d floor cells" % [lids, floors])

	# Nothing may spawn on the cell the player stands up in.
	var start: Vector2i = view.generator.start
	if view.heater_station != null and view.heater_station.source_cell == start:
		_fail("the heater station is still on the spawn cell")

	# The maze is lit almost entirely by the lamp; starting dark reads as a
	# broken build rather than as atmosphere.
	if not scene.player.flashlight_enabled:
		_fail("the player spawns with the flashlight off")

	if _failures == 0:
		print("  fabric    %d floors, %d walls, %d ceiling cells, all boxes"
			% [floors, walls, lids])
		print("  spawn     heater at %s, start at %s, lamp on"
			% [view.heater_station.source_cell, start])
		print("maze OK")
	scene.queue_free()
	await host.get_tree().process_frame
	return _failures
