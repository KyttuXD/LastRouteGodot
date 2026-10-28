extends RefCounted

## Sealed wings on level -3 (SealPlanner, Breach): deterministic; every gate is open ground across a tunnel, never on a seam
## opening or a ramp landing; with every seal closed all entries still meet; each gate really shuts ground in; ids round-trip;
## relays, tools and hunters follow the wings; the seal count and open share follow the ring.
##
##   godot --headless --path . res://scenes/validate.tscn -- seals

const SEEDS := ["SEAL-A", "SEAL-B"]
const NEAR := 2
const FAR_FROM := 5
const FAR_TO := 8

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	for seed_text in SEEDS:
		_check_seed(seed_text)
	_check_breach_api()
	return _failures


func _check_seed(seed_text: String) -> void:
	var generator := StreamedRouteGenerator.new(seed_text)
	var other := StreamedRouteGenerator.new(seed_text)
	var level := StreamedRouteGenerator.INFERNO_LEVEL
	var stats := {"near_seals": 0, "near_chunks": 0, "far_seals": 0, "far_chunks": 0, "near_open": 0.0, "far_open": 0.0,
		"wings": 0, "sealed_relays": 0, "relay_chunks": 0}
	var coords: Array[Vector3i] = []
	for cz in range(-NEAR, NEAR + 1):
		for cx in range(-NEAR, NEAR + 1):
			coords.append(Vector3i(cx, level, cz))
	for k in range(FAR_FROM, FAR_TO + 1):
		for cz in [-k, k]:
			for cx in range(-2, 3):
				coords.append(Vector3i(cx, level, cz))
	var all_ids := {}
	for coord in coords:
		var data := generator.chunk(coord)
		var specs: Array = data.get("breakables", [])
		_expect(JSON.stringify(_ids(specs)) == JSON.stringify(_ids(other.chunk(coord).get("breakables", []))),
			"%s %s: seal plan differs between two generators" % [seed_text, coord])
		var near := SealRules.ring(coord) <= NEAR
		stats["near_chunks" if near else "far_chunks"] += 1
		stats["near_seals" if near else "far_seals"] += specs.size()
		_check_chunk(seed_text, coord, data, specs, generator, all_ids, stats)
	var near_avg := float(stats["near_seals"]) / maxf(1.0, float(stats["near_chunks"]))
	var far_avg := float(stats["far_seals"]) / maxf(1.0, float(stats["far_chunks"]))
	print("  seals %s: %.2f seals per chunk within ring %d, %.2f from ring %d out; open share %.2f near, %.2f far; %d of %d chunks sealed a relay" % [
		seed_text, near_avg, NEAR, far_avg, FAR_FROM, float(stats["near_open"]) / maxf(1.0, float(stats["near_chunks"])),
		float(stats["far_open"]) / maxf(1.0, float(stats["far_chunks"])), stats["sealed_relays"], stats["relay_chunks"]])
	_expect(stats["near_seals"] > 0 and stats["far_seals"] > 0, "%s: no seals at all" % seed_text)
	_expect(far_avg >= near_avg, "%s: seals do not thicken going out (%.2f near, %.2f far)" % [seed_text, near_avg, far_avg])
	_expect(float(stats["far_open"]) / maxf(1.0, float(stats["far_chunks"])) <= float(stats["near_open"]) / maxf(1.0, float(stats["near_chunks"])) + .02,
		"%s: open share does not shrink going out" % seed_text)


func _ids(specs: Array) -> Array:
	var out := []
	for spec in specs:
		out.append([spec["id"], spec["variant"], var_to_str((spec["extras"] as Dictionary)["cells"])])
	return out


func _check_chunk(seed_text: String, coord: Vector3i, data: Dictionary, specs: Array, generator: StreamedRouteGenerator,
		all_ids: Dictionary, stats: Dictionary) -> void:
	var tag := "%s %s" % [seed_text, coord]
	var grid: Array = data["grid"]
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var seam := {}
	for side in ["west", "east", "north", "south"]:
		for offset in (data["edges"] as Dictionary)[side]:
			for spread in range(-1, 2):
				var at := Vector2i(0 if side == "west" else size - 1 if side == "east" else int(offset) + spread,
					0 if side == "north" else size - 1 if side == "south" else int(offset) + spread)
				if side == "west" or side == "east":
					at.y = int(offset) + spread
				seam[at] = true
	var entries: Array[Vector2i] = []
	for side in ["west", "east", "north", "south"]:
		for offset in (data["edges"] as Dictionary)[side]:
			if int(offset) != size / 2:
				continue                    # the side lanes of a dense seam may be sealed
			entries.append(Vector2i(3 if side == "west" else size - 4 if side == "east" else int(offset),
				3 if side == "north" else size - 4 if side == "south" else int(offset)))
			if side == "west" or side == "east":
				entries[entries.size() - 1].y = int(offset)
	for ramp in data.get("ramps", []):
		var bottom: Rect2i = ramp["bottom"]
		entries.append(bottom.position + bottom.size / 2)
	entries = entries.filter(func(e: Vector2i) -> bool: return int(grid[e.y][e.x]) == 0)
	var blocked := {}
	for spec in specs:
		_expect(not all_ids.has(spec["id"]), "%s: duplicate breakable id %s" % [tag, spec["id"]])
		all_ids[spec["id"]] = true
		_expect(generator.breakable_by_id(String(spec["id"])) == spec, "%s: %s does not round-trip through breakable_by_id" % [tag, spec["id"]])
		_expect(String(spec["kind"]) == Breach.KIND_SEAL and int(spec["hp"]) > 0 and not (spec["tools"] as Array).is_empty(),
			"%s: malformed seal spec %s" % [tag, spec["id"]])
		for tool in spec["tools"]:
			_expect(PlayerController3D.BREACH_TOOLS.has(tool) or PlayerController3D.LOCK_TOOLS.has(tool), "%s: seal wants unknown tool %s" % [tag, tool])
		for cell in (spec["extras"] as Dictionary)["cells"]:
			_expect(int(grid[cell.y][cell.x]) == 0, "%s: gate cell %s is not open ground" % [tag, cell])
			_expect(not seam.has(cell), "%s: gate cell %s sits on a seam opening" % [tag, cell])
			blocked[cell] = true
			for ramp in data.get("ramps", []):
				for part in ["ramp", "bottom", "connector"]:
					_expect(not (ramp[part] as Rect2i).has_point(cell), "%s: gate cell %s sits on a ramp %s" % [tag, cell, part])
	var total_open := 0
	for z in size:
		for x in size:
			total_open += 1 if int(grid[z][x]) == 0 else 0
	var reach := SealPlanner._reach(grid, entries, blocked)
	var lost := []
	for entry in entries:
		if reach[entry.y * size + entry.x] == 0:
			lost.append("%s(grid %d)" % [entry, int(grid[entry.y][entry.x])])
	_expect(lost.is_empty(), "%s: closed seals cut a seam opening or ramp landing off: %s of %d gates %d" % [tag, lost, entries.size(), specs.size()])
	var reached := SealPlanner._reach_count(reach)
	var sealed: Array = data.get("sealed_cells", [])
	if not specs.is_empty():
		_expect(not sealed.is_empty(), "%s: seals shut nothing in" % tag)
		_expect(reached + sealed.size() + blocked.size() == total_open, "%s: sealed ground does not add up (%d + %d + %d vs %d)" % [
			tag, reached, sealed.size(), blocked.size(), total_open])
		stats["wings"] += 1
	stats["near_open" if SealRules.ring(coord) <= NEAR else "far_open"] += float(reached) / maxf(1.0, float(total_open - blocked.size()))
	# relays and tools
	var sealed_set := {}
	for cell in sealed:
		sealed_set[cell] = true
	var relays := 0
	var open_relays := 0
	var open_tool := false
	for pickup in data.get("pickups", []):
		var kind := String(pickup["kind"])
		if kind == "relay":
			relays += 1
			if not sealed_set.has(pickup["cell"]):
				open_relays += 1
		if kind == "tool" and not sealed_set.has(pickup["cell"]):
			open_tool = true
	if relays > 0:
		stats["relay_chunks"] += 1
		if open_relays < relays:
			stats["sealed_relays"] += 1
		_expect(open_relays >= 1, "%s: every relay is behind a seal" % tag)
	if not sealed.is_empty() and SealRules.guaranteed_tool(coord):
		_expect(open_tool, "%s: no tool on open ground (ring %d)" % [tag, SealRules.ring(coord)])
	# hunters see a closed gate as a wall until it is broken
	if not specs.is_empty():
		var state := StreamedWorldState.new()
		var navigation := StreamedHunterNavigation.new(generator, coord.y, state)
		navigation.refresh(coord.y, [coord])
		var spec: Dictionary = specs[0]
		var cell: Vector2i = (spec["extras"] as Dictionary)["cells"][0]
		var world := Vector2(coord.x * size + cell.x + .5, coord.z * size + cell.y + .5)
		_expect(not navigation.is_floor(world.x, world.y), "%s: a closed gate is walkable for hunters" % tag)
		state.set_breach(String(spec["id"]), 0, true)
		navigation.refresh(coord.y, [coord])
		_expect(navigation.is_floor(world.x, world.y), "%s: a broken gate stays a wall for hunters" % tag)


func _check_breach_api() -> void:
	var spec := Breach.make_spec(Breach.make_id(Vector3i(1, -3, 2), 4), Breach.KIND_PIPE, "pipe", Vector3i(1, -3, 2), Vector2i(5, 6), 3,
		["rescue_axe", "crowbar"], {"flood": 4.0})
	_expect(Breach.parse_id(spec["id"]) == {"chunk": Vector3i(1, -3, 2), "index": 4}, "breach ids do not parse")
	_expect(Breach.damage_for(spec, "rescue_axe", 3) == 2 and Breach.damage_for(spec, "crowbar", 3) == 1, "tool damage is not axe 2 / crowbar 1")
	_expect(Breach.damage_for(spec, "lockpick", 3) == 0, "a lockpick works a plain pipe")
	var locked := Breach.make_spec("BRK:0:0:0:0", Breach.KIND_SEAL, "lockedFurnaceDoor", Vector3i.ZERO, Vector2i.ZERO, 3, ["lockpick", "crowbar"], {}, true)
	_expect(Breach.damage_for(locked, "lockpick", 3) == 3, "a lockpick does not open a locked door outright")
	var heard := []
	Breach.connect_hook("breached", Breach.KIND_PIPE, func(event: Dictionary) -> void: heard.append(event["id"]))
	Breach.connect_hook("breached", "", func(event: Dictionary) -> void: heard.append("any"))
	Breach.dispatch("breached", {"id": "x", "kind": Breach.KIND_PIPE})
	Breach.dispatch("breached", {"id": "y", "kind": Breach.KIND_SEAL})
	Breach.clear_hooks()
	Breach.dispatch("breached", {"id": "z", "kind": Breach.KIND_PIPE})
	_expect(heard == ["any", "x", "any"] or heard == ["x", "any", "any"], "hook dispatch is wrong: %s" % [heard])
	var state := StreamedWorldState.new()
	_expect(state.breach_hp(spec) == 3, "an untouched breakable is not at its spec hp")
	_expect(state.set_breach(spec["id"], 1, false) and not state.set_breach(spec["id"], 1, false), "set_breach is not idempotent")
	var copy := StreamedWorldState.new()
	copy.adopt(state.snapshot())
	_expect(copy.breach_hp(spec) == 1, "breach state does not survive a snapshot")
