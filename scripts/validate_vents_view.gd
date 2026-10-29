extends RefCounted

## The vents are real (KT): in a streamed level-0 chunk every duct line is built (the Ducts body: floor, roof, sides),
## a crawling hunter's capsule (VentNetwork.HUNTER_CRAWL_HEIGHT) fits inside the duct all along each line, through the
## walls it crosses, and a standing runner under a duct has VentNetwork.DUCT_FLOOR of headroom. Links carry duct_level
## and duct_y for WORLD's VentCrawl.
##
##   godot --headless --path . res://scenes/validate.tscn -- vents_view

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_expect(is_equal_approx(VentNetwork.DUCT_FLOOR + VentNetwork.DUCT_HEIGHT, VentNetwork.LEVEL_HEIGHT - VentNetwork.SLAB), "the duct does not reach the slab")
	_expect(VentNetwork.DUCT_FLOOR >= 1.8 * HunterRoster.MODEL_SCALE, "a duct leaves only %.2f m of headroom, under a hunter" % VentNetwork.DUCT_FLOOR)
	var generator := StreamedRouteGenerator.new("VENTS-A")
	var links := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			for link in generator.vents().grates_for(Vector3i(dx, 0, dz), 0):
				links += 1
				_expect(link.has("duct_level") and link.has("duct_y") and is_equal_approx(float(link["duct_y"]), VentNetwork.DUCT_FLOOR),
					"vent link without duct_level / duct_y: %s" % link)
	_expect(links > 0, "no vent grates near the spawn")
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.global_position = Vector3(22.5, .1, 22.5)
	view.begin("VENTS-A", player)
	for _i in 30:
		await host.get_tree().physics_frame
	var root: Node3D = view._loaded.get(Vector3i(0, 0, 0))
	_expect(root != null and root.get_node_or_null("Ducts") != null, "the spawn chunk has no ducts")
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
