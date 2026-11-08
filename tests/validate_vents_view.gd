extends RefCounted

## The vents are real and run between the levels: in a streamed level-0 chunk every duct line is built in the plenum
## (the Ducts body: floor, roof, sides), above every ordinary ceiling and under the storey above, never under a mezzanine
## deck or in the void; a crawling hunter's capsule (VentNetwork.HUNTER_CRAWL_HEIGHT) fits inside the duct all along each
## line, through the walls it crosses. Links carry duct_level and duct_y for WORLD's VentCrawl.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- vents_view

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	# the plenum: the duct's underside clears every ordinary ceiling (hidden over corridors and rooms), its top stays under
	# the offices' floor two storeys up
	var underside := VentNetwork.DUCT_FLOOR - StreamedFacilityView3D.DUCT_SKIN
	var top := VentNetwork.DUCT_FLOOR + VentNetwork.DUCT_HEIGHT + StreamedFacilityView3D.DUCT_SKIN
	for ordinary in [RefLook.CORRIDOR_RANGE.y, RefLook.ROOM_RANGE.y, RefLook.room_range("gothic", "bedroom").y]:
		_expect(ordinary <= VentNetwork.PLENUM_CLEARANCE, "an ordinary ceiling (%.1f m) rises past the plenum clearance" % ordinary)
	_expect(underside > VentNetwork.PLENUM_CLEARANCE, "the duct's underside (%.2f m) hangs into ordinary rooms" % underside)
	_expect(top < 2.0 * VentNetwork.LEVEL_HEIGHT - VentNetwork.SLAB, "the duct (top %.2f m) runs into the storey above the plenum" % top)
	_expect(VentNetwork.DUCT_FLOOR >= 1.8 * HunterRoster.MODEL_SCALE, "a duct leaves only %.2f m of headroom, under a hunter" % VentNetwork.DUCT_FLOOR)
	var generator := StreamedRouteGenerator.new("VENTS-A")
	var links := 0
	var decks := 0
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			var column := Vector3i(dx, StreamedRouteGenerator.MEZZANINE_LEVEL, dz)
			if generator.is_chunk_allowed(column) or generator.is_void_column(column):
				decks += 1
				var vent_chunk: Dictionary = generator.vents().chunk(Vector3i(dx, 0, dz))
				var storey_grates: Array = vent_chunk["links"].filter(func(link: Dictionary) -> bool: return int(link["from_level"]) == 0)
				_expect(not bool(vent_chunk["ducted"]) and storey_grates.is_empty()
					and not generator.vents().crawlable(Vector2i(dx * StreamedRouteGenerator.CHUNK_SIZE + VentNetwork.LINES[0], dz * StreamedRouteGenerator.CHUNK_SIZE + 10)),
					"a storey-0 duct or grate under the mezzanine deck / void at chunk %s" % column)
	# the mezzanine decks and the void are removed, so every maze chunk is ducted: none may be skipped
	_expect(decks == 0 and not StreamedRouteGenerator.MEZZANINE_ENABLED, "%d +1 decks / void columns near the spawn (removed)" % decks)
	for dz in range(-6, 7):
		for dx in range(-6, 7):
			_expect(bool(generator.vents().chunk(Vector3i(dx, 0, dz))["ducted"]), "maze chunk (%d, %d) has no storey-0 duct" % [dx, dz])
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for link in generator.vents().grates_for(Vector3i(dx, 0, dz), 0):
				links += 1
				_expect(link.has("duct_level") and link.has("duct_y") and is_equal_approx(float(link["duct_y"]), VentNetwork.duct_floor_y(0)),
					"vent link without duct_level / duct_y: %s" % link)
	_expect(links > 0, "no vent grates near the spawn")
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.global_position = Vector3(22.5, .1, 22.5)
	view.begin("VENTS-A", player)
	for _i in 30:
		await host.get_tree().physics_frame
	var root: Node3D = view._loaded.get(Vector3i(0, 0, 0))
	_expect(root != null and root.get_node_or_null("Ducts") != null, "the spawn chunk has no ducts")
	# the skin: textured sheet (with UVs) plus the joint rings, and a grille under every hatch
	var skin := root.get_node_or_null("DuctSkin") as MeshInstance3D if root != null else null
	_expect(skin != null and skin.mesh.get_surface_count() == 2, "the duct skin is not sheet + joint rings")
	if skin != null and skin.mesh.get_surface_count() > 0:
		_expect(skin.mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] != null, "the duct sheet has no UVs for its texture")
		_expect((skin.mesh.surface_get_material(0) as StandardMaterial3D).albedo_texture != null, "the duct sheet is untextured")
	if root != null:
		var hatches := root.find_children("VentHatch*", "MeshInstance3D", false, false).size()
		var grilles := root.find_children("VentGrille*", "MeshInstance3D", false, false).size()
		_expect(hatches == grilles, "%d duct hatches but %d grilles seen from below" % [hatches, grilles])
	var space := player.get_world_3d().direct_space_state
	var capsule := CapsuleShape3D.new()
	capsule.radius = .3
	capsule.height = VentNetwork.HUNTER_CRAWL_HEIGHT
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = capsule
	query.collision_mask = 1
	var blocked := []
	var checked := 0
	for line in VentNetwork.LINES:
		for i in range(2, StreamedRouteGenerator.CHUNK_SIZE - 2):
			for at in [Vector2(i + .5, line + .5), Vector2(line + .5, i + .5)]:
				checked += 1
				query.transform = Transform3D(Basis.IDENTITY, Vector3(at.x, VentNetwork.DUCT_FLOOR + VentNetwork.HUNTER_CRAWL_HEIGHT * .5 + .02, at.y))
				var hits := space.intersect_shape(query, 4)
				var solid := hits.filter(func(hit: Dictionary) -> bool: return not (hit["collider"] is Area3D))
				if not solid.is_empty():
					blocked.append(at)
	_expect(blocked.is_empty(), "a crawling hunter is blocked in the duct at %d of %d points (e.g. %s)" % [blocked.size(), checked, blocked.slice(0, 4)])
	view.clear()
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  vents_view  %d duct points clear for a crawling hunter, %d grates with duct_level/duct_y, ducts built" % [checked, links])
	return _failures
