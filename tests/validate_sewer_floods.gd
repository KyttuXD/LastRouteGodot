extends RefCounted

## Sewer pipes the Axe breaks, the floods they let out, and the valve wheels (SewerRouteGenerator._pipe_breakables,
## _flood_valve_features, _gate_features, SewerFloods, docs/BREACH.md, docs/SEWERS.md):
##  - every crawl pipe and outflow main is one Breach pipe spec ("authored": the sewer draws it), axe or crowbar, found again by
##    id, its props tagged with the id; its flood is a capped patch of walkway in spread steps; a chunk with pipes has a
##    flood valve;
##  - unresolved, the water rises to shin depth, then keeps creeping deeper (to knee height) and spreading (to
##    FULL_REACH steps) for CREEP seconds; a flood valve turned in its chunk freezes the spread and drains it in SHUT_DRAIN;
##  - hunters cannot walk through a whole pipe and can once it is broken (the navigation reads the breach);
##  - on a built chunk a burst removes the pipe's mains and collider (an outflow main leaves its stump), starts the flood,
##    and a rebuilt chunk keeps the pipe broken and the flood running;
##  - sluice gates: closed the channel is a wall, open its three cells are floor (the navigation and the collider), the
##    walkable area differs by exactly those cells and the crossing is a short cut; the leaf swings;
##  - the runner wading is slowed, splashes loud enough for hunters, is soaked, and tires at the deepest; the flood and
##    valve clocks survive a snapshot (co-op join, run save) with the same state on both sides.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- sewer_floods

const SEEDS := ["CRAWL-A", "CRAWL-B", "MAP-CHECK", "SEWER-A"]

var _failures := 0
var _gates_checked := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## Breakable pipes are a secret: no "[E] BREAK // AXE" prompt and no wrong-tool message, yet the interact key still
## reaches them; a locked seal keeps its PICK LOCK prompt.
func _check_secret_prompt() -> void:
	for locked in [false, true]:
		var item := RouteInteractable3D.new()
		item.kind = RouteInteractable3D.Kind.BREAKABLE
		item.breakable_spec = Breach.make_spec("BRK:0:-1:0:0", Breach.KIND_PIPE, "authored", Vector3i(0, -1, 0), Vector2i(3, 3), 3,
			["rescue_axe"], {}, locked)
		if locked:
			_expect(item.get_prompt().begins_with("PICK LOCK") and not item.is_secret(), "a locked breakable lost its PICK LOCK prompt")
		else:
			_expect(item.get_prompt().is_empty() and item.is_secret(), "a breakable pipe still shows \"%s\"" % item.get_prompt())
		item.free()


## Every sewer breakable is found by its id (seal ids count from 100 after the pipes, so the index is not a position), a
## locked door takes the crowbar and the lockpick the prompt names, and a crowbar press is a hit that wears only the
## crowbar ("with crowbar, doesnt work").
func _check_seal_lookup(host: Node) -> void:
	var generator := StreamedRouteGenerator.new("SEWER-FLOODS")
	var seals := 0
	var door: Dictionary = {}
	for z in range(-4, 5):
		for x in range(-4, 5):
			for level in [SewerRouteGenerator.LEVEL, SewerRouteGenerator.LOWER_LEVEL]:
				for spec in generator.chunk(Vector3i(x, level, z)).get("breakables", []):
					var found := generator.breakable_by_id(String(spec["id"]))
					_expect(found == spec, "breakable %s is not found by its id" % spec["id"])
					if String(spec["kind"]) == Breach.KIND_SEAL:
						seals += 1
						if bool(spec.get("locked", false)) and door.is_empty():
							door = spec
	_expect(seals >= 5, "only %d sewer seals to look up" % seals)
	_expect(not door.is_empty(), "no locked sewer door seal to try the tools on")
	if door.is_empty():
		return
	for tool in ["crowbar", "lockpick", "rescue_axe"]:
		_expect(Breach.damage_for(door, tool, int(door["hp"])) > 0, "the %s does nothing to a locked door" % tool)
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.inventory_enabled = true
	player.grant_inventory_item("lockpick")
	player.grant_inventory_item("crowbar")
	player.select_inventory_slot(player.inventory_order.find("crowbar"))
	var item := RouteInteractable3D.new()
	item.kind = RouteInteractable3D.Kind.BREAKABLE
	item.breakable_spec = door
	var hits := []
	item.changed.connect(func(event: Dictionary) -> void: hits.append(event))
	var pick_before := player.item_durability("lockpick")
	var bar_before := player.item_durability("crowbar")
	var message := item.activate(player)
	_expect(message == "HIT" and hits.size() == 1 and String(hits[0].get("tool", "")) == "crowbar",
		"E with the crowbar on a locked door: \"%s\", %d hits" % [message, hits.size()])
	_expect(player.item_durability("crowbar") < bar_before and player.item_durability("lockpick") == pick_before,
		"the press wore the wrong tool (crowbar %d -> %d, lockpick %d -> %d)" % [bar_before, player.item_durability("crowbar"), pick_before, player.item_durability("lockpick")])
	item.free()
	player.queue_free()


## The flood sheet (tilted, floating over the tiles, into the brick): a level surface at the holder's height
## scale, a side face down to the floor on every open edge (the channel, unflooded floor) and none against brick, the faces
## toward the next spread step only in that step's front.
func _check_water_sheet() -> void:
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var grid := []
	for z in size:
		var row := []
		row.resize(size)
		row.fill(SewerRouteGenerator.SOLID)
		grid.append(row)
	# a 1 x 3 strip of walkway: brick north and south, the channel west, more (unflooded) walkway east
	for x in range(4, 9):
		grid[5][x] = SewerRouteGenerator.DRY
	grid[5][3] = SewerRouteGenerator.WATER
	var meshes := SewerFloods.water_meshes([Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5)], [0, 1, 1], grid)
	var counts := func(mesh: ArrayMesh) -> Array:
		var tops := 0
		var sides := 0
		var low := INF
		var high := -INF
		if mesh.get_surface_count() > 0:
			var arrays := mesh.surface_get_arrays(0)
			var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(0, verts.size(), 6):
				if normals[i].y > .5:
					tops += 1
				else:
					sides += 1
			for v in verts:
				low = minf(low, v.y)
				high = maxf(high, v.y)
		return [tops, sides, low, high]
	var ring0: Array = counts.call(meshes["rings"][0])
	var front0: Array = counts.call(meshes["fronts"][0])
	var ring1: Array = counts.call(meshes["rings"][1])
	_expect(ring0[0] == 1 and ring0[1] == 1, "step 0's sheet has %d tops and %d side faces (want 1 and the channel edge)" % [ring0[0], ring0[1]])
	_expect(front0[0] == 0 and front0[1] == 1, "step 0's front has %d tops and %d faces (want the face toward step 1)" % [front0[0], front0[1]])
	_expect(ring1[0] == 2 and ring1[1] == 1, "step 1's sheet has %d tops and %d side faces (want 2 and the unflooded walkway edge)" % [ring1[0], ring1[1]])
	_expect(is_equal_approx(ring1[2], 0.0) and is_equal_approx(ring1[3], 1.0), "the sheet does not run from the floor (0) to the surface (1)")


## A sewer pipe is aimed at where it is ("pipe hitboxes"): the crawl mains' box from the crawl clearance up
## (a standing runner aims at the pipe, not the floor under it), the outflow barrel's from its underside to its top.
func _check_pipe_aim() -> void:
	var crawl := BreakableView.authored_aim_box({"extras": {"pipe": "crawl"}}, 3.0)
	_expect(crawl.position.y <= SewerRouteGenerator.CRAWL_CLEARANCE and crawl.end.y >= SewerRouteGenerator.CRAWL_CLEARANCE + SewerRouteGenerator.CRAWL_PIPE_SIZE.y
		and crawl.position.y > SewerRouteGenerator.CRAWL_CLEARANCE - .2 and crawl.size.x >= 3.0,
		"the crawl pipe's aim box %s is not the pipe" % crawl)
	var outflow := BreakableView.authored_aim_box({"extras": {"pipe": "outflow"}}, 3.0)
	_expect(outflow.position.y <= SewerRouteGenerator.CRAWL_CLEARANCE and outflow.end.y >= SewerRouteGenerator.CRAWL_CLEARANCE + SewerRouteGenerator.OUTFLOW_SIZE.y
		and outflow.size.x >= SewerRouteGenerator.OUTFLOW_SIZE.z and outflow.size.z >= SewerRouteGenerator.OUTFLOW_SIZE.x,
		"the outflow main's aim box %s is not the barrel" % outflow)


## Holding the use button keeps chopping a pipe ("left-clicking a pipe should slowly break it"): no repeat
## mid-swing or with a tool that cannot work it.
func _check_hold_break() -> void:
	_expect(PlayerController3D.TOOL_HOLD_PAUSE > 0.0 and PlayerController3D.TOOL_HOLD_PAUSE < 1.0,
		"the hold-to-break pause is %.2f s" % PlayerController3D.TOOL_HOLD_PAUSE)


func run(host: Node) -> int:
	_check_timeline()
	_check_secret_prompt()
	_check_seal_lookup(host)
	_check_valve_state()
	var pipes := _check_specs()
	_check_wading(host)
	_check_water_sheet()
	_check_pipe_aim()
	_check_hold_break()
	await _check_live(host)
	if _failures == 0:
		print("  sewer_floods  %d breakable pipes, %d sluice gates; %.2f m in %.0f s, worsening to %.2f m over %.0f s, shut drains in %.0f s; burst, rebuild, gates, wade and snapshot OK" % [
			pipes, _gates_checked, SewerFloods.MAX_DEPTH, SewerFloods.RISE, SewerFloods.DEEP_DEPTH, SewerFloods.CREEP, SewerFloods.SHUT_DRAIN])
	return _failures


func _check_timeline() -> void:
	_expect(SewerFloods.RISE >= 2.0 and SewerFloods.RISE <= 8.0, "a burst fills to shin depth in %.1f s (want a few seconds)" % SewerFloods.RISE)
	_expect(SewerFloods.MAX_DEPTH >= .2 and SewerFloods.MAX_DEPTH <= .4, "a fresh flood is %.2f m, not ankle to shin" % SewerFloods.MAX_DEPTH)
	_expect(SewerFloods.DEEP_DEPTH >= .7 and SewerFloods.DEEP_DEPTH <= 1.0, "the worst flood is %.2f m, not knee-high" % SewerFloods.DEEP_DEPTH)
	_expect(SewerFloods.CREEP >= 120.0 and SewerFloods.CREEP <= 600.0, "a flood worsens over %.0f s (want a few minutes)" % SewerFloods.CREEP)
	_expect(SewerFloods.depth_at(-1.0) == 0.0 and SewerFloods.depth_at(0.0) == 0.0 and SewerFloods.reach_at(0.0) == 0, "water before the burst")
	var last := 0.0
	var last_reach := 0
	var t := 0.0
	while t <= SewerFloods.RISE + SewerFloods.CREEP + 60.0:
		var depth := SewerFloods.depth_at(t)
		var reach := SewerFloods.reach_at(t)
		_expect(depth >= last - .0001 and reach >= last_reach, "an unresolved flood recedes at %.1f s" % t)
		last = depth
		last_reach = reach
		t += 2.5
	_expect(is_equal_approx(SewerFloods.depth_at(SewerFloods.RISE + .01), SewerFloods.MAX_DEPTH), "the flood is not at shin depth after the rise")
	_expect(SewerFloods.depth_at(SewerFloods.RISE + SewerFloods.CREEP * .5) > SewerFloods.MAX_DEPTH + .1, "the flood does not worsen")
	_expect(is_equal_approx(SewerFloods.depth_at(SewerFloods.RISE + SewerFloods.CREEP + 600.0), SewerFloods.DEEP_DEPTH)
		and SewerFloods.reach_at(SewerFloods.RISE + SewerFloods.CREEP + 600.0) == SewerFloods.FULL_REACH, "the flood is not capped")
	_expect(SewerFloods.FULL_REACH == SewerRouteGenerator.FLOOD_REACH, "the spread cap and the generated steps disagree")


## A valve turned in a pipe's chunk while it floods: that flood stops rising and drains in SHUT_DRAIN; others are left;
## the shut time travels in the snapshot.
func _check_valve_state() -> void:
	var shut := SewerFloods.RISE + 5.0
	_expect(is_equal_approx(SewerFloods.depth_shut(shut, shut), SewerFloods.depth_at(shut)), "a shut flood jumps at the turn")
	_expect(SewerFloods.reach_shut(shut + 300.0, shut) == SewerFloods.reach_at(shut), "a shut flood keeps spreading")
	_expect(SewerFloods.spent(shut + SewerFloods.SHUT_DRAIN, shut) and not SewerFloods.spent(shut + 300.0, -1.0), "spent floods are wrong")
	_expect(SewerFloods.depth_shut(shut + SewerFloods.SHUT_DRAIN, shut) == 0.0, "a shut flood is not gone after %.0f s" % SewerFloods.SHUT_DRAIN)
	_expect(SewerFloods.depth_shut(shut + 3.0, shut) < SewerFloods.depth_at(shut + 3.0), "a shut flood does not drain faster")
	_expect(SewerFloods.SHUT_DRAIN >= 8.0 and SewerFloods.SHUT_DRAIN <= 25.0, "a valve drains in %.0f s (want about 15)" % SewerFloods.SHUT_DRAIN)
	var state := StreamedWorldState.new()
	var now := Time.get_unix_time_from_system()
	var here := Breach.make_id(Vector3i(2, -1, 3), 0)
	var there := Breach.make_id(Vector3i(5, -1, 3), 0)
	state.floods[here] = now - 10.0
	state.floods[there] = now - 10.0
	_expect(state.shut_floods(Vector3i(2, -1, 3)) == [here], "a valve shut the wrong floods")
	_expect(absf(state.flood_shut_at(here) - 10.0) < .5 and state.flood_shut_at(there) < 0.0, "the shut times are wrong")
	_expect(state.shut_floods(Vector3i(2, -1, 3)).is_empty(), "a second turn shut the same flood again")
	var other := StreamedWorldState.new()
	other.adopt(state.snapshot())
	_expect(absf(other.flood_shut_at(here) - state.flood_shut_at(here)) < .5 and other.flood_shut_at(there) < 0.0,
		"the snapshot lost a valve's shut")


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
					var flood_valves := (data["region_props"] as Array).filter(func(prop: Dictionary) -> bool:
						return String(prop["type"]) == "sewerValveWheel" and String(prop.get("valve_effect", "")) == "flood")
					_expect(pipe_props.is_empty() or not flood_valves.is_empty(), "%s: pipes but no flood valve to shut them" % where)
					for gate in data.get("gates", []):
						_check_gate(surface, coord, data, gate, where)
					for index in specs.size():
						var spec: Dictionary = specs[index]
						if String(spec["kind"]) != Breach.KIND_PIPE:
							continue
						pipes += 1
						var extras: Dictionary = spec["extras"]
						_expect(spec["id"] == Breach.make_id(coord, index), "%s: pipe spec %d has id %s" % [where, index, spec["id"]])
						_expect(surface.breakable_by_id(spec["id"]) == spec, "%s: %s is not found again by id" % [where, spec["id"]])
						_expect(spec["variant"] == "authored" and spec["tools"].has("rescue_axe") and spec["tools"].has("crowbar"), "%s: %s is not an authored pipe both break tools open" % [where, spec["id"]])
						for prop_id in extras["props"]:
							var tagged := pipe_props.filter(func(prop: Dictionary) -> bool: return prop["id"] == prop_id and prop.get("breakable_id") == spec["id"])
							_expect(tagged.size() == 1, "%s: prop %s does not point back at %s" % [where, prop_id, spec["id"]])
						var flood: Array = extras["flood_cells"]
						var steps: Array = extras["flood_steps"]
						_expect(steps.size() == flood.size() and steps.all(func(k: int) -> bool: return k >= 0 and k <= SewerRouteGenerator.FLOOD_REACH),
							"%s: %s has bad spread steps" % [where, spec["id"]])
						_expect(flood.size() >= 6 and flood.size() <= SewerRouteGenerator.FLOOD_MAX_CELLS,
							"%s: %s floods %d cells (want a bounded patch)" % [where, spec["id"], flood.size()])
						var grid: Array = data["sewer_grid"]
						for cell in flood:
							var c: Vector2i = cell
							_expect(int(grid[c.y][c.x]) == SewerRouteGenerator.DRY, "%s: %s floods %s, a bridge deck (the water runs on to the far bank)" % [where, spec["id"], c])
							_expect(SewerRouteGenerator.is_walkable(int(grid[c.y][c.x])), "%s: %s floods %s, not walkway" % [where, spec["id"], c])
							var near := (extras["cells"] as Array).any(func(p: Vector2i) -> bool:
								return absi(p.x - c.x) + absi(p.y - c.y) <= SewerRouteGenerator.FLOOD_REACH)
							_expect(near, "%s: %s floods %s, more than %d steps away" % [where, spec["id"], c, SewerRouteGenerator.FLOOD_REACH])
						_check_navigation(surface, coord, spec, where)
	_expect(pipes >= 30, "only %d breakable pipes in the sampled chunks" % pipes)
	_expect(_gates_checked >= 10, "only %d sluice gates in the sampled chunks" % _gates_checked)
	return pipes


## A whole pipe is a wall to the hunters; a broken one is not.
## A sluice gate: three channel cells with dry walkway at both ends and a wall-backed gate valve; closed they are a wall
## to the hunters, open they are floor, the walkable area grows by exactly those cells, and the crossing is a short cut.
func _check_gate(surface: StreamedRouteGenerator, coord: Vector3i, data: Dictionary, gate: Dictionary, where: String) -> void:
	_gates_checked += 1
	var grid: Array = data["sewer_grid"]
	var cells: Array = gate["cells"]
	_expect(cells.size() == 3 and cells.all(func(c: Vector2i) -> bool: return int(grid[c.y][c.x]) == SewerRouteGenerator.WATER),
		"%s: gate %s does not span the channel" % [where, gate["id"]])
	var valve := (data["region_props"] as Array).filter(func(prop: Dictionary) -> bool: return prop["id"] == gate["valve"])
	_expect(valve.size() == 1 and String(valve[0]["valve_effect"]) == "gate" and valve[0]["gate"] == gate["id"],
		"%s: gate %s has no gate valve" % [where, gate["id"]])
	var a: Vector2i = cells[0]
	var b: Vector2i = cells[2]
	var step: Vector2i = (a - b) / 2
	var end_a: Vector2i = a + step
	var end_b: Vector2i = b - step
	_expect(SewerRouteGenerator.is_walkable(int(grid[end_a.y][end_a.x])) and SewerRouteGenerator.is_walkable(int(grid[end_b.y][end_b.x])),
		"%s: gate %s does not land on walkway" % [where, gate["id"]])
	var state := StreamedWorldState.new()
	var navigation := StreamedHunterNavigation.new(surface, coord.y, state)
	navigation.refresh(coord.y, [coord])
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var base := Vector2i(coord.x, coord.z) * size
	var closed_floor := navigation.floor_cells().size()
	var closed_path := navigation.find_path(base + end_a, base + end_b)
	_expect(not navigation.is_floor(base.x + a.x + .5, base.y + a.y + .5), "%s: hunters cross the shut gate %s" % [where, gate["id"]])
	state.set_valve_turns(String(gate["valve"]), 1)
	navigation.refresh(coord.y, [coord])
	var open_path := navigation.find_path(base + end_a, base + end_b)
	_expect(navigation.floor_cells().size() == closed_floor + 3, "%s: opening gate %s changed %d floor cells" % [
		where, gate["id"], navigation.floor_cells().size() - closed_floor])
	_expect(not open_path.is_empty() and open_path.size() <= 6, "%s: hunters do not take the open gate %s (path %d)" % [
		where, gate["id"], open_path.size()])
	_expect(closed_path.is_empty() or closed_path.size() > open_path.size() + 4, "%s: gate %s is no short cut (shut %d, open %d)" % [
		where, gate["id"], closed_path.size(), open_path.size()])


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
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
	host.add_child(player)
	player.soaked_left = 0.0
	player.noise = 0.0
	player.wading_depth = SewerFloods.MAX_DEPTH
	player._update_wading(1.0 / 60.0, true)
	_expect(player.noise >= PlayerController3D.WADE_NOISE - .01 and PlayerController3D.WADE_NOISE > GameConfig.NOISE_SPRINT,
		"a wading step makes %.1f noise (want louder than a sprint)" % player.noise)
	_expect(player.soaked_left > 0.0, "wading does not soak the runner")
	_expect(PlayerController3D.WADE_SPEED_SCALE < .8, "wading barely slows (x%.2f)" % PlayerController3D.WADE_SPEED_SCALE)
	player.wading_depth = SewerFloods.DEEP_DEPTH
	player.noise = 0.0
	player.stamina = 50.0
	player._update_wading(.5, true)
	_expect(player.noise >= PlayerController3D.WADE_DEEP_NOISE - .01, "a knee-deep step makes only %.1f noise" % player.noise)
	_expect(player.stamina < 50.0, "knee-deep wading does not tire")
	player.wading_depth = 0.0
	player.noise = 0.0
	player._update_wading(1.0 / 60.0, true)
	_expect(player.noise == 0.0, "dry steps splash")
	player.queue_free()


## A live burst on a built chunk, its rebuild, the runner's wading depth and a snapshot hand-over.
func _check_live(host: Node) -> void:
	var view := StreamedFacilityView3D.new()
	host.add_child(view)
	var player := (load("res://game/night_watch/night_watch_player.tscn") as PackedScene).instantiate() as PlayerController3D
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
	var holder := (view._floods._active.get(id, {}) as Dictionary).get("holder") as Node3D
	_expect(holder != null and is_equal_approx(holder.position.y, 0.0) and absf(holder.scale.y - SewerFloods.MAX_DEPTH) < .01,
		"the flood sheet is not on the floor at its depth (y %.2f, scale %.2f)" % [holder.position.y if holder else -1.0, holder.scale.y if holder else -1.0])
	_expect(LevelAmbience.emitters_of("flood").any(func(e: Dictionary) -> bool: return String(e["id"]) == "flood:" + id),
		"the running flood %s has no level-layer gush" % id)
	# unresolved it worsens: a walkway cell beyond the first spread is dry at first, then knee-deep
	var spec_extras: Dictionary = spec["extras"]
	var far := Vector2i(-1, -1)
	for index in (spec_extras["flood_steps"] as Array).size():
		if int(spec_extras["flood_steps"][index]) == SewerFloods.FULL_REACH - 1:
			far = spec_extras["flood_cells"][index]
	_expect(far != Vector2i(-1, -1), "flood %s never spreads %d steps" % [id, SewerFloods.FULL_REACH - 1])
	var far_at := Vector3(coord.x * size + far.x + .5, at.y, coord.z * size + far.y + .5)
	_expect(view._floods.depth_under(far_at) == 0.0, "the flood reaches %s at once" % far)
	view.world_state.floods[id] = Time.get_unix_time_from_system() - SewerFloods.RISE - SewerFloods.CREEP - 30.0
	await host.get_tree().process_frame
	_expect(absf(view._floods.depth_under(far_at) - SewerFloods.DEEP_DEPTH) < .01, "the worsened flood is %.2f m at %s" % [
		view._floods.depth_under(far_at), far])
	# a snapshot (co-op join, run save): the other side's water is at the same depth, a drained flood is dropped
	view.world_state.floods[id] = Time.get_unix_time_from_system() - SewerFloods.RISE - SewerFloods.CREEP * .5
	var other := StreamedWorldState.new()
	other.adopt(view.world_state.snapshot())
	_expect(other.breach_open(id), "the snapshot lost the broken pipe")
	_expect(absf(SewerFloods.depth_at(other.flood_age(id)) - SewerFloods.depth_at(view.world_state.flood_age(id))) < .01,
		"the joiner's flood is at %.2f m, the host's at %.2f m" % [SewerFloods.depth_at(other.flood_age(id)),
			SewerFloods.depth_at(view.world_state.flood_age(id))])
	_check_frame_cost(view, id, coord)
	# a valve wheel in a loaded sewer chunk: its wheel is rigged on a pivot and spins when turned
	var valve_id := ""
	for key in view._valve_nodes:
		if valve_id.is_empty() and is_instance_valid(view._valve_nodes[key]):
			valve_id = String(key)
	_expect(not valve_id.is_empty(), "no valve wheel rigged in the loaded sewer chunks")
	if not valve_id.is_empty():
		var pivot := view._valve_nodes[valve_id] as Node3D
		_expect(pivot.get_children().filter(func(n: Node) -> bool: return String(n.name).begins_with("Rim")).size() >= 8,
			"valve %s: the rim is not on its pivot" % valve_id)
		var before := pivot.rotation.z
		view.apply_valve(valve_id)
		# the spin is a timed tween (VALVE_TURN_SECONDS, sine ease-in): wait real time, not a frame count -- fast headless
		# frames (fewer prop draws after perf tip 122) finished 20 frames before the wheel had eased past the threshold
		var spin_started := Time.get_ticks_msec()
		var spin_frames := 0
		while spin_frames < 20 or Time.get_ticks_msec() - spin_started < 400:
			await host.get_tree().process_frame
			spin_frames += 1
		_expect(absf(pivot.rotation.z - before) > .2, "valve %s did not turn" % valve_id)
	# the flood valve turned (the route's "stream_valve" with shut): it drains in SHUT_DRAIN and is gone
	_expect(view.world_state.shut_floods(coord) == [id], "the chunk's flood valve did not shut flood %s" % id)
	view.world_state.flood_shut[id] = Time.get_unix_time_from_system() - SewerFloods.SHUT_DRAIN - 1.0
	_expect(not (view.world_state.snapshot()["floods"] as Dictionary).has(id), "a drained flood is still in the snapshot")
	await host.get_tree().process_frame
	_expect(view._floods.flood_count() == 0 and player.wading_depth == 0.0, "the drained flood stayed")
	await _check_live_gate(host, view, surface)
	view.clear()
	view.queue_free()
	player.queue_free()


## A sluice gate on a built chunk: its leaf hinges down to lie flat and the channel collider under it becomes floor.
## What a flood costs a frame (perf, the water and pipe sim must not hitch): the per-frame update of a creeping
## flood (its clock moving every frame, the way it does in play), rebuilding its water and spray when its chunk comes back,
## and the whole chunk rebuild around it. Timed in microseconds and printed (PERF lines); the update must stay far under a
## frame and, while nothing visible changed, touch no node.
func _check_frame_cost(view: StreamedFacilityView3D, id: String, coord: Vector3i) -> void:
	var floods := view._floods
	var start_age := SewerFloods.RISE + SewerFloods.CREEP * .25
	const FRAMES := 600
	var t := Time.get_ticks_usec()
	for frame in FRAMES:
		view.world_state.floods[id] = Time.get_unix_time_from_system() - start_age - frame / 60.0
		floods._process(1.0 / 60.0)
	var per_frame := float(Time.get_ticks_usec() - t) / FRAMES
	var entry: Dictionary = floods._active.get(id, {})
	# the gated update still follows the water: the surface within a step of the true depth, the right steps showing
	var age := view.world_state.flood_age(id)
	var holder := entry.get("holder") as Node3D
	_expect(holder != null and absf(holder.scale.y - SewerFloods.depth_at(age)) <= SewerFloods.DEPTH_STEP + .001,
		"the gated flood surface lags: %.3f m shown, %.3f m deep" % [holder.scale.y if holder else -1.0, SewerFloods.depth_at(age)])
	var reach := SewerFloods.reach_at(age)
	var rings: Array = entry.get("rings", [])
	for step in rings.size():
		if rings[step] != null:
			_expect((rings[step] as MeshInstance3D).visible == (step <= reach), "flood step %d shows %s at reach %d" % [step, (rings[step] as MeshInstance3D).visible, reach])
	_expect(rings.any(func(r: Variant) -> bool: return r == null) or rings.size() == SewerFloods.FULL_REACH + 1, "the flood lost its steps")
	var root := view._loaded.get(coord) as Node3D
	var spawn_us := 0.0
	if not entry.is_empty() and root != null:
		var spec := view.generator.breakable_by_id(id)
		floods._forget(id)
		t = Time.get_ticks_usec()
		floods._spawn(id, spec, coord, root)
		spawn_us = float(Time.get_ticks_usec() - t)
	t = Time.get_ticks_usec()
	view._unload_chunk(coord)
	view._load_chunk(coord)
	var rebuild_ms := float(Time.get_ticks_usec() - t) / 1000.0
	var nodes := 0
	var rebuilt := view._loaded.get(coord) as Node3D
	if rebuilt != null:
		nodes = rebuilt.find_children("*", "", true, false).size()
	print("  PERF  sewer flood update %.1f us/frame, flood spawn %.0f us, chunk rebuild %.1f ms (%d nodes)" % [per_frame, spawn_us, rebuild_ms, nodes])
	_expect(per_frame < 250.0, "a creeping flood costs %.1f us a frame" % per_frame)
	_expect(floods.flood_count() == 1, "the timed rebuild lost the flood")


func _check_live_gate(host: Node, view: StreamedFacilityView3D, surface: StreamedRouteGenerator) -> void:
	var gate := {}
	var gate_coord := Vector3i.ZERO
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var coord := Vector3i(dx, SewerRouteGenerator.LEVEL, dz)
			for gate_value in surface.chunk(coord).get("gates", []):
				if gate.is_empty():
					gate = gate_value
					gate_coord = coord
	_expect(not gate.is_empty(), "no sluice gate near the origin")
	if gate.is_empty():
		return
	if not view._loaded.has(gate_coord):
		view._load_chunk(gate_coord)
	await host.get_tree().process_frame
	var entry: Dictionary = view._gate_nodes.get(gate["id"], {})
	_expect(not entry.is_empty(), "gate %s was not rigged" % gate["id"])
	if entry.is_empty():
		return
	var pivot := entry["pivot"] as Node3D
	var grid := entry["grid"] as GridMap
	var cell: Vector2i = (gate["cells"] as Array)[1]
	_expect(absf(pivot.rotation.x + PI / 2.0) < .01 and grid.get_cell_item(Vector3i(cell.x, 0, cell.y)) == view._col_channel_item,
		"gate %s does not start raised over the channel" % gate["id"])
	view.world_state.set_valve_turns(String(gate["valve"]), 1)
	view.apply_valve(String(gate["valve"]), {"chunk": gate_coord, "effect": "gate", "turns": 1, "gate": gate["id"]})
	await host.get_tree().create_timer(StreamedFacilityView3D.GATE_SWING_SECONDS + .4).timeout
	_expect(absf(pivot.rotation.x) < .02, "gate %s did not lower (%.2f rad)" % [gate["id"], pivot.rotation.x])
	_expect(grid.get_cell_item(Vector3i(cell.x, 0, cell.y)) == view._col_floor_item, "gate %s gives no floor to walk on" % gate["id"])


## Torn outflow stumps standing in a chunk (the broken model, sewer_outflow_pipe_broken).
static func _stumps(root: Node) -> int:
	if root == null:
		return 0
	var count := 0
	for node in root.get_children():
		if not node.is_queued_for_deletion() and String(node.scene_file_path) == StreamedFacilityView3D.OUTFLOW_STUMP:
			count += 1
	return count
