extends RefCounted

## Sewer pipes the Axe breaks, and the floods they let out (SewerRouteGenerator._pipe_breakables, SewerFloods, docs/BREACH.md):
##  - every crawl pipe and outflow main is one Breach pipe spec ("authored": the sewer draws it), Axe only, found again by
##    id, its props tagged with the id; its flood is a bounded patch of dry walkway around it;
##  - the water rises to shin depth, holds, then drains to nothing (never deep enough to swim or muffle);
##  - hunters cannot walk through a whole pipe and can once it is broken (the navigation reads the breach);
##  - on a built chunk a burst removes the pipe's mains and collider, starts one flood plane, and a rebuilt chunk keeps
##    the pipe gone and the flood running;
##  - the runner wading in it is slowed, splashes loud enough for hunters and is soaked; the flood clock survives a
##    snapshot (co-op join, run save) with the same depth on both sides.
##
##   godot --headless --path . res://scenes/validate.tscn -- sewer_floods

const SEEDS := ["CRAWL-A", "CRAWL-B", "MAP-CHECK", "SEWER-A"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	_check_timeline()
	var pipes := _check_specs()
	_check_wading(host)
	await _check_live(host)
	if _failures == 0:
		print("  sewer_floods  %d breakable pipes; rise %.0f s, hold %.0f s, drain %.0f s to %.2f m; burst, rebuild, wade and snapshot OK" % [
			pipes, SewerFloods.RISE, SewerFloods.HOLD, SewerFloods.DRAIN, SewerFloods.MAX_DEPTH])
	return _failures


func _check_timeline() -> void:
	_expect(SewerFloods.MAX_DEPTH >= .2 and SewerFloods.MAX_DEPTH <= .4, "flood depth %.2f is not ankle to shin" % SewerFloods.MAX_DEPTH)
	_expect(SewerFloods.depth_at(-1.0) == 0.0 and SewerFloods.depth_at(0.0) == 0.0, "water before the burst")
	var last := 0.0
	var t := 0.0
	while t <= SewerFloods.RISE:
		var depth := SewerFloods.depth_at(t)
		_expect(depth >= last - .0001, "the flood falls while rising at %.1f s" % t)
		last = depth
		t += .5
	_expect(is_equal_approx(SewerFloods.depth_at(SewerFloods.RISE + 1.0), SewerFloods.MAX_DEPTH), "the flood does not hold at full depth")
	last = SewerFloods.MAX_DEPTH
	t = SewerFloods.RISE + SewerFloods.HOLD
	while t < SewerFloods.DURATION:
		var depth := SewerFloods.depth_at(t)
		_expect(depth <= last + .0001, "the flood rises while draining at %.1f s" % t)
		last = depth
		t += 2.0
	_expect(SewerFloods.depth_at(SewerFloods.DURATION) == 0.0 and SewerFloods.depth_at(SewerFloods.DURATION + 60.0) == 0.0,
		"the flood never drains away")
	_expect(SewerFloods.DRAIN >= 60.0 and SewerFloods.DRAIN <= 120.0, "the flood drains in %.0f s (want a minute or two)" % SewerFloods.DRAIN)


func _check_specs() -> int:
	var pipes := 0
	for seed_text in SEEDS:
		var surface := StreamedRouteGenerator.new(seed_text)
		for level in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
			for dz in range(-3, 4):
				for dx in range(-3, 4):
					var coord := Vector3i(dx, level, dz)
					var data := surface.chunk(coord)
					var where := "%s %s" % [seed_text, coord]
					var specs: Array = data.get("breakables", [])
					var pipe_props := (data["region_props"] as Array).filter(func(prop: Dictionary) -> bool:
						return bool(prop.get("outflow", false)) or bool(prop.get("crawl_under", false)))
					for prop in pipe_props:
						_expect(prop.has("breakable_id"), "%s: pipe %s has no breakable" % [where, prop["id"]])
					for index in specs.size():
						var spec: Dictionary = specs[index]
						if String(spec["kind"]) != Breach.KIND_PIPE:
							continue
						pipes += 1
						var extras: Dictionary = spec["extras"]
						_expect(spec["id"] == Breach.make_id(coord, index), "%s: pipe spec %d has id %s" % [where, index, spec["id"]])
						_expect(surface.breakable_by_id(spec["id"]) == spec, "%s: %s is not found again by id" % [where, spec["id"]])
						_expect(spec["variant"] == "authored" and spec["tools"] == ["rescue_axe"], "%s: %s is not an authored Axe-only pipe" % [where, spec["id"]])
						for prop_id in extras["props"]:
							var tagged := pipe_props.filter(func(prop: Dictionary) -> bool: return prop["id"] == prop_id and prop.get("breakable_id") == spec["id"])
							_expect(tagged.size() == 1, "%s: prop %s does not point back at %s" % [where, prop_id, spec["id"]])
						var flood: Array = extras["flood_cells"]
						_expect(flood.size() >= 6 and flood.size() <= SewerRouteGenerator.FLOOD_MAX_CELLS,
							"%s: %s floods %d cells (want a bounded patch)" % [where, spec["id"], flood.size()])
						var grid: Array = data["sewer_grid"]
						for cell in flood:
							var c: Vector2i = cell
							_expect(SewerRouteGenerator.is_walkable(int(grid[c.y][c.x])), "%s: %s floods %s, not walkway" % [where, spec["id"], c])
							var near := (extras["cells"] as Array).any(func(p: Vector2i) -> bool:
								return absi(p.x - c.x) + absi(p.y - c.y) <= SewerRouteGenerator.FLOOD_REACH)
							_expect(near, "%s: %s floods %s, more than %d steps away" % [where, spec["id"], c, SewerRouteGenerator.FLOOD_REACH])
						_check_navigation(surface, coord, spec, where)
	_expect(pipes >= 30, "only %d breakable pipes in the sampled chunks" % pipes)
	return pipes


## A whole pipe is a wall to the hunters; a broken one is not.
func _check_navigation(surface: StreamedRouteGenerator, coord: Vector3i, spec: Dictionary, where: String) -> void:
	var state := StreamedWorldState.new()
	var navigation := StreamedHunterNavigation.new(surface, coord.y, state)
	navigation.refresh(coord.y, [coord])
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cell: Vector2i = spec["cell"]
	var at := Vector2(coord.x * size + cell.x + .5, coord.z * size + cell.y + .5)
	_expect(not navigation.is_floor(at.x, at.y), "%s: hunters walk through the whole pipe %s" % [where, spec["id"]])
	state.set_breach(spec["id"], 0, true)
	navigation.refresh(coord.y, [coord])
	_expect(navigation.is_floor(at.x, at.y), "%s: hunters cannot cross where %s was broken" % [where, spec["id"]])


func _check_wading(host: Node) -> void:
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.soaked_left = 0.0
	player.noise = 0.0
	player.wading_depth = SewerFloods.MAX_DEPTH
	player._update_wading(1.0 / 60.0, true)
	_expect(player.noise >= PlayerController3D.WADE_NOISE - .01 and PlayerController3D.WADE_NOISE > GameConfig.NOISE_SPRINT,
		"a wading step makes %.1f noise (want louder than a sprint)" % player.noise)
	_expect(player.soaked_left > 0.0, "wading does not soak the runner")
	_expect(PlayerController3D.WADE_SPEED_SCALE < .8, "wading barely slows (x%.2f)" % PlayerController3D.WADE_SPEED_SCALE)
	player.wading_depth = 0.0
	player.noise = 0.0
	player._update_wading(1.0 / 60.0, true)
	_expect(player.noise == 0.0, "dry steps splash")
	player.queue_free()


## A live burst on a built chunk, its rebuild, the runner's wading depth and a snapshot hand-over.
func _check_live(host: Node) -> void:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://scenes/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	var surface := StreamedRouteGenerator.new("CRAWL-A")
	var coord := Vector3i.ZERO
	var spec := {}
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			for spec_value in surface.chunk(Vector3i(dx, SewerRouteGenerator.LEVEL, dz)).get("breakables", []):
				# an outflow main: it leaves its torn stump at the wall
				if spec.is_empty() and String((spec_value as Dictionary)["kind"]) == Breach.KIND_PIPE \
						and String((spec_value as Dictionary)["extras"]["pipe"]) == "outflow":
					spec = spec_value
					coord = Vector3i(dx, SewerRouteGenerator.LEVEL, dz)
	_expect(not spec.is_empty(), "no pipe near the origin to burst")
	if spec.is_empty():
		return
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var cell: Vector2i = spec["cell"]
	var at := Vector3(coord.x * size + cell.x + .5, coord.y * StreamedFacilityView3D.LEVEL_HEIGHT + .05, coord.z * size + cell.y + .5)
	player.global_position = at
	view.begin("CRAWL-A", player)
	for _frame in 30:
		await host.get_tree().process_frame
	var root := view._loaded.get(coord) as Node3D
	_expect(root != null, "the pipe's chunk %s was not built" % coord)
	if root == null:
		return
	var id := String(spec["id"])
	var kept: Array = (view._pipe_nodes.get(id, {}) as Dictionary).get("nodes", [])
	_expect(not kept.is_empty(), "the view kept no nodes for pipe %s" % id)
	# the host's stream_breach on this machine: the state, the piece, the hook
	var event := {"id": id, "kind": spec["kind"], "variant": spec["variant"], "level": coord.y, "chunk": coord,
		"cell": cell, "hp": 0, "max": spec["hp"], "opened": true, "tool": "rescue_axe", "by": 1, "position": at}
	view.world_state.set_breach(id, 0, true)
	view.apply_breach(id, 0, true)
	Breach.dispatch("breached", event)
	await host.get_tree().process_frame
	_expect(not view._pipe_nodes.has(id) and kept.all(func(node: Variant) -> bool: return not is_instance_valid(node) or (node as Node).is_queued_for_deletion()),
		"the burst pipe %s is still drawn" % id)
	_expect(_stumps(view._loaded.get(coord)) == 1, "the burst main left %d torn stumps at its wall" % _stumps(view._loaded.get(coord)))
	_expect(view._floods.flood_count() == 1 and view.world_state.flood_age(id) >= 0.0, "the burst started %d floods" % view._floods.flood_count())
	# full depth after the rise: the runner standing in it wades
	view.world_state.floods[id] = Time.get_unix_time_from_system() - SewerFloods.RISE - 2.0
	await host.get_tree().process_frame
	_expect(absf(player.wading_depth - SewerFloods.MAX_DEPTH) < .01, "the runner in the flood wades %.2f m deep" % player.wading_depth)
	# a rebuilt chunk: no pipe, the flood back at the same depth
	view._unload_chunk(coord)
	view._load_chunk(coord)
	await host.get_tree().process_frame
	_expect(not view._pipe_nodes.has(id) and view._floods.flood_count() == 1, "a rebuilt chunk brought the pipe back or lost the flood")
	_expect(_stumps(view._loaded.get(coord)) == 1, "the rebuilt chunk has %d torn stumps" % _stumps(view._loaded.get(coord)))
	_expect(absf(view._floods.depth_under(at) - SewerFloods.MAX_DEPTH) < .01, "the rebuilt flood is %.2f m deep" % view._floods.depth_under(at))
	# a snapshot (co-op join, run save): the other side's water is at the same depth, a drained flood is dropped
	view.world_state.floods[id] = Time.get_unix_time_from_system() - SewerFloods.RISE - SewerFloods.HOLD - 30.0
	var other := StreamedWorldState.new()
	other.adopt(view.world_state.snapshot())
	_expect(other.breach_open(id), "the snapshot lost the broken pipe")
	_expect(absf(SewerFloods.depth_at(other.flood_age(id)) - SewerFloods.depth_at(view.world_state.flood_age(id))) < .01,
		"the joiner's flood is at %.2f m, the host's at %.2f m" % [SewerFloods.depth_at(other.flood_age(id)),
			SewerFloods.depth_at(view.world_state.flood_age(id))])
	view.world_state.floods[id] = Time.get_unix_time_from_system() - SewerFloods.DURATION - 1.0
	_expect(not (view.world_state.snapshot()["floods"] as Dictionary).has(id), "a drained flood is still in the snapshot")
	await host.get_tree().process_frame
	_expect(view._floods.flood_count() == 0 and player.wading_depth == 0.0, "the drained flood stayed")
	view.clear()
	view.queue_free()
	player.queue_free()


## Torn outflow stumps standing in a chunk (the broken model, sewer_outflow_pipe_broken).
static func _stumps(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	for node in root.get_children():
		if not node.is_queued_for_deletion() and String(node.scene_file_path) == StreamedFacilityView3D.OUTFLOW_STUMP:
			count += 1
	return count
