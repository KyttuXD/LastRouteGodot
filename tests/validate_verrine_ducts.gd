extends RefCounted

## Verrine lives in the storey-0 ducts (docs/VENTS.md). With the real duct view built (StreamedFacilityView3D "Ducts"), a real
## HunterView3D drives her brain (VerrineGimmick._physical_tick) and checks what a player would see:
##   - inside: her body stands on the duct floor (DUCT_FLOOR, 4.8 m), over a duct cell, in the crawl pose, with her body
##     collider off, drawn (visible, not ghosted below the visibility floor), and every bone of the crawl pose stays inside the
##     1.2 m duct (nothing of her pokes out of the sheet metal: outside = the ceiling, the room below);
##   - her view is never found outside the duct while her brain says she is in it (view y vs the crawl's duct_y);
##   - once she climbs out at a grate she is on the floor of her level, back on the ordinary body (collider on).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- verrine_ducts

const STEP := 1.0 / 60.0
const SEED := "VENTS-A"

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.global_position = Vector3(22.5, .1, 22.5)
	view.begin(SEED, player)
	for _i in 30:
		await host.get_tree().physics_frame
	var vents: VentNetwork = view.generator.vents()
	var nav := VentNav.new(vents)
	var grates := nav.grates_around(Vector2(22.5, 22.5), 0, 40.0)
	_expect(not grates.is_empty(), "no storey-0 grate near the spawn")
	if grates.is_empty():
		view.queue_free()
		player.queue_free()
		return _failures
	# Verrine, as the route loads her (InfiniteRouteTest._load_hunter)
	var spawn := VentCrawl.grate_centre(grates[0]) + Vector2(2.0, 0.0)
	var brain := HunterBrain.new(spawn, "%s:VERRINE" % SEED, "verrine", "standard")
	var gimmick := brain.gimmick as VerrineGimmick
	_expect(gimmick != null, "Verrine has no VerrineGimmick")
	if gimmick == null:
		view.queue_free()
		player.queue_free()
		return _failures
	gimmick.vents = vents
	gimmick.level = 0
	brain.vent_nav = nav
	brain.active = true
	var hv := HunterView3D.new()
	hv.brain = brain
	hv.surface_height_provider = view.streamed_surface_height.bind(0)
	host.add_child(hv)
	await host.get_tree().process_frame
	# the runner stands far away in the open: she patrols the ducts
	var far := {"position": Vector2(300.0, 300.0), "depth": 0, "duct": false, "hidden": false, "in_safe_zone": false}
	var in_duct_frames := 0
	var out_of_duct := 0
	var tallest := 0.0
	var widest := 0.0
	var worst_y := 0.0
	var not_crawl_pose := 0
	var collider_on := 0
	var ghosted := 0
	var invisible := 0
	for frame in 600:
		brain.update(STEP, view.generator, far, 0, 0)
		hv.sync_from_brain()
		await host.get_tree().physics_frame
		if brain.active_crawl() == null or brain.active_crawl().phase != VentCrawl.Phase.DUCT:
			continue
		in_duct_frames += 1
		var feet := hv.global_position.y
		var duct_y := VentNetwork.duct_floor_y(0)
		worst_y = maxf(worst_y, absf(feet - duct_y))
		if absf(feet - duct_y) > .15:
			out_of_duct += 1
		if frame > 90:
			var top := _model_top(hv) - feet
			tallest = maxf(tallest, top)
			widest = maxf(widest, _model_half_width(hv))
			if hv.nw_pose.is_empty():
				not_crawl_pose += 1
			if hv._collider != null and not hv._collider.disabled:
				collider_on += 1
			if hv._model == null or not hv._model.visible:
				invisible += 1
			if HunterView3D.model_alpha(brain) < HunterView3D.MIN_VISIBLE_ALPHA - .001:
				ghosted += 1
	print("  verrine_ducts  highest part: %s; model scale %.2f" % [_top_part, hv._model.scale.y if hv._model != null else 0.0])
	print("  verrine_ducts  %d frames in the duct: view height off the duct floor by at most %.2f m, tallest bone %.2f m over her feet (duct %.2f m), crawl pose missing %d, collider on %d, hidden %d, ghosted %d"
		% [in_duct_frames, worst_y, tallest, VentNetwork.DUCT_HEIGHT, not_crawl_pose, collider_on, invisible, ghosted])
	_expect(in_duct_frames > 300, "Verrine spent only %d frames in the ducts" % in_duct_frames)
	_expect(out_of_duct == 0, "Verrine's body was %d frames away from the duct floor (worst %.2f m)" % [out_of_duct, worst_y])
	_expect(not_crawl_pose == 0, "Verrine crawled %d frames without the vent crawl pose" % not_crawl_pose)
	_expect(collider_on == 0, "Verrine's body collider stayed on in the duct for %d frames" % collider_on)
	_expect(invisible == 0, "Verrine's model was hidden for %d frames in the duct" % invisible)
	_expect(ghosted == 0, "Verrine was ghosted below the visibility floor for %d frames" % ghosted)
	print("  verrine_ducts  widest part %.2f m either side of her (duct interior half width %.2f m)" % [widest, .5 - .06])
	_expect(widest <= .5 - .06 + .05,
		"Verrine's crawl pose reaches %.2f m to the side of her; the duct is 1.0 m wide (0.88 inside): her arms stick through the walls" % widest)
	_expect(tallest <= VentNetwork.DUCT_HEIGHT + .05,
		"Verrine's crawl pose reaches %.2f m over her feet; the duct is %.2f m tall: she sticks out of it" % [tallest, VentNetwork.DUCT_HEIGHT])
	# the runner walks up beside a grate: she climbs out and stands on the floor
	var grate: Dictionary = nav.grates_around(brain.position, 0, 40.0)[0]
	var runner := VentCrawl.grate_centre(grate) + Vector2(3.0, 0.0)
	var near := {"position": runner, "depth": 0, "duct": false, "hidden": false, "in_safe_zone": false}
	var came_out := false
	for _i in 60 * 90:
		brain.update(STEP, view.generator, near, 0, 0)
		hv.sync_from_brain()
		await host.get_tree().physics_frame
		if brain.active_crawl() == null and gimmick.crawl != null and gimmick.crawl.phase == VentCrawl.Phase.OUT:
			came_out = true
			break
	_expect(came_out, "Verrine never climbed out beside a runner")
	for _i in 120:
		hv.sync_from_brain()
		await host.get_tree().physics_frame
	if came_out:
		_expect(absf(hv.global_position.y) < .3, "Verrine climbed out but her view is %.2f m up" % hv.global_position.y)
		_expect(hv._collider != null and not hv._collider.disabled, "Verrine's collider stayed off after she climbed out")
	hv.queue_free()
	await _reload_in_duct(host, view, vents, nav, grates[0])
	view.clear()
	view.queue_free()
	player.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  ok    verrine_ducts: Verrine stays inside the duct (pose, height, collider, visibility) and stands on the floor after climbing out")
	return _failures


## Streaming her in (InfiniteRouteTest._load_hunter): a fresh brain restored over a duct cell, primed, then her view synced for the first time.
## She must be on the duct floor from that very first frame (not on the hall floor under the duct, then jumping up) and not move.
func _reload_in_duct(host: Node, view: StreamedFacilityView3D, vents: VentNetwork, nav: VentNav, grate: Dictionary) -> void:
	var cell := Vector2i(-1, -1)
	var centre := VentCrawl.grate_centre(grate)
	for dx in range(-8, 9):
		var candidate := Vector2i(floori(centre.x) + dx, floori(centre.y))
		if dx != 0 and vents.crawlable(candidate):
			cell = candidate
			break
	_expect(cell != Vector2i(-1, -1), "no duct cell beside the grate to reload her over")
	if cell == Vector2i(-1, -1):
		return
	var saved := Vector2(cell.x + .5, cell.y + .5)
	var brain := HunterBrain.new(saved, "%s:VERRINE-RELOAD" % SEED, "verrine", "standard")
	var gimmick := brain.gimmick as VerrineGimmick
	gimmick.vents = vents
	gimmick.level = 0
	brain.vent_nav = nav
	brain.active = true
	gimmick.prime(brain)
	var hv := HunterView3D.new()
	hv.brain = brain
	hv.surface_height_provider = view.streamed_surface_height.bind(0)
	host.add_child(hv)
	hv.sync_from_brain()
	print("  verrine_ducts  reloaded over a duct cell: first view height %.2f m (duct floor %.2f m), moved %.2f m" % [hv.global_position.y, VentNetwork.duct_floor_y(0), brain.position.distance_to(saved)])
	_expect(absf(hv.global_position.y - VentNetwork.duct_floor_y(0)) < .15, "a Verrine streamed in over a duct cell is first drawn %.2f m up, not on the duct floor" % hv.global_position.y)
	_expect(brain.position.distance_to(saved) < .01, "a Verrine streamed in over a duct cell was moved %.2f m" % brain.position.distance_to(saved))
	hv.queue_free()
	await host.get_tree().process_frame


## Highest world y of her drawn parts (the blocky rig is rigid parts under bones; a mesh counts by its transformed box), i.e. how far she
## reaches over the duct floor in the pose she is in. `_top_part` names the part that reaches highest.
static var _top_part := ""


static func _model_half_width(hv: HunterView3D) -> float:
	var side := 0.0
	if hv._model == null:
		return side
	var across := hv.global_transform.basis.x.normalized()
	for node in hv._model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var box := mesh.get_aabb()
		for corner in 8:
			var point := mesh.global_transform * (box.position + box.size * Vector3(corner & 1, (corner >> 1) & 1, (corner >> 2) & 1))
			side = maxf(side, absf((point - hv.global_position).dot(across)))
	return side


static func _model_top(hv: HunterView3D) -> float:
	var top := -INF
	if hv._model == null:
		return top
	for node in hv._model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null or not mesh.is_visible_in_tree():
			continue
		var y := (mesh.global_transform * mesh.get_aabb()).end.y
		if y > top:
			top = y
			_top_part = "%s (skinned: %s)" % [mesh.name, str(mesh.skin != null)]
	for node in hv._model.find_children("*", "Skeleton3D", true, false):
		var skeleton := node as Skeleton3D
		for bone in skeleton.get_bone_count():
			var y := (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin.y
			if y > top:
				top = y
				_top_part = "bone " + skeleton.get_bone_name(bone)
	return top
