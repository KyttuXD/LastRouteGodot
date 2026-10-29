class_name SewerFloods
extends Node3D

## Floods from sewer pipes broken with the Axe (KT: "a broken pipe floods the area", and an unresolved one gets worse).
## A burst pipe (Breach "breached", KIND_PIPE, on every machine) gushes out of its break, and the water fills its
## walkway to ankle-shin depth over RISE seconds. Until somebody turns a flood valve in that chunk it keeps getting
## worse: over CREEP seconds the depth climbs to knee height (DEEP_DEPTH) and the water spreads step by step along the
## connected walkway (the spec's extras.flood_cells/flood_steps, capped by the generator), with the spray and the gush
## growing. A valve (StreamedWorldState.flood_shut) stops it: the spread freezes and the water drains in SHUT_DRAIN.
##
## One water mesh per spread step, built once at the burst; the height of their shared holder and which steps show are
## all that change (no per-frame mesh work). The burst and shut times live in the world state, so every machine's water
## follows the same clock and a reloaded run carries on mid-flood. The local runner wading in it is slowed, splashes
## loudly (hunters hear it), stays soaked and, at the deepest, tires; hunters wade at their normal pace.

const RISE := 8.0
## Ankle to shin, where a fresh flood settles.
const MAX_DEPTH := .35
## Knee-high, where an unresolved one ends up after CREEP seconds.
const DEEP_DEPTH := .9
const CREEP := 360.0
## The spread: steps from the pipe when it settles, and when it is at its worst.
const START_REACH := 4
const FULL_REACH := 12
## Below this the water is a film: not drawn, no slowing.
const MIN_DEPTH := .03
const GUSH_RANGE := 22.0
## A flood valve turned in the pipe's chunk stops the gush and drains the water this fast.
const SHUT_DRAIN := 15.0

var view: StreamedFacilityView3D
## flood id -> {"holder": Node3D (one MeshInstance3D per spread step), "rings": Array, "spray": GPUParticles3D,
## "gush": AudioStreamPlayer3D, "chunk": Vector3i, "cells": Array (world)}
var _active := {}
## world cell -> [[flood id, spread step]]
var _cells := {}


## How far a creeping flood is to its worst, 0..1, `age` seconds after the burst.
static func worsening(age: float) -> float:
	if age <= RISE:
		return 0.0
	var k := clampf((age - RISE) / CREEP, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)


## Water depth `age` seconds after the burst while nobody has shut it: a smooth rise, then the slow creep upward.
static func depth_at(age: float) -> float:
	if age <= 0.0:
		return 0.0
	if age < RISE:
		var k := age / RISE
		return MAX_DEPTH * k * k * (3.0 - 2.0 * k)
	return lerpf(MAX_DEPTH, DEEP_DEPTH, worsening(age))


## Spread steps the water reaches `age` seconds after the burst.
static func reach_at(age: float) -> int:
	if age <= 0.0:
		return 0
	if age < RISE:
		return ceili(START_REACH * age / RISE)
	return START_REACH + floori((FULL_REACH - START_REACH) * worsening(age))


## Depth when a valve shut the pipe `shut` seconds after the burst (-1: never): from then it drains in SHUT_DRAIN.
static func depth_shut(age: float, shut: float) -> float:
	if shut < 0.0 or age < shut:
		return depth_at(age)
	return depth_at(shut) * maxf(0.0, 1.0 - (age - shut) / SHUT_DRAIN)


## The spread a shut flood keeps (frozen at the turn).
static func reach_shut(age: float, shut: float) -> int:
	return reach_at(age) if shut < 0.0 or age < shut else reach_at(shut)


## Whether a flood is over: shut and drained.
static func spent(age: float, shut: float) -> bool:
	return shut >= 0.0 and age >= shut + SHUT_DRAIN


func _state(id: String) -> Vector2:
	return Vector2(view.world_state.flood_age(id), view.world_state.flood_shut_at(id))


## A chunk was built: bring back any flood of its pipes that is still running.
func chunk_built(coord: Vector3i, root: Node3D, data: Dictionary) -> void:
	for spec_value in data.get("breakables", []):
		var spec: Dictionary = spec_value
		var id := String(spec["id"])
		if String(spec.get("kind", "")) != Breach.KIND_PIPE or _active.has(id):
			continue
		var state := _state(id)
		if state.x >= 0.0 and not spent(state.x, state.y):
			_spawn(id, spec, coord, root)


## A chunk went away: its floods' nodes went with it (the clock keeps running in the world state).
func chunk_unloaded(coord: Vector3i) -> void:
	for id in _active.keys():
		if (_active[id] as Dictionary)["chunk"] == coord:
			_forget(id)


## Breach "breached" for a pipe, on every machine: start the clock (once) and the water, spray and gush if loaded.
func on_pipe_breached(event: Dictionary) -> void:
	var id := String(event.get("id", ""))
	if view == null or view.world_state == null:
		return
	view.world_state.start_flood(id)
	var spec := view.generator.breakable_by_id(id)
	var coord: Vector3i = event.get("chunk", spec.get("chunk", Vector3i.ZERO))
	var root := view._loaded.get(coord) as Node3D
	if spec.is_empty() or root == null or _active.has(id):
		return
	_spawn(id, spec, coord, root)
	if DisplayServer.get_name() != "headless":
		Sound.splash_big(0.0, .8)


func _spawn(id: String, spec: Dictionary, coord: Vector3i, root: Node3D) -> void:
	var extras: Dictionary = spec.get("extras", {})
	var base := Vector2i(coord.x, coord.z) * StreamedRouteGenerator.CHUNK_SIZE
	var cells: Array = extras.get("flood_cells", [])
	var steps: Array = extras.get("flood_steps", [])
	var tools := []
	for _step in FULL_REACH + 1:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		tool.set_normal(Vector3.UP)
		tools.append(tool)
	var world_cells := []
	for index in cells.size():
		var cell: Vector2i = cells[index]
		var step := clampi(int(steps[index]) if index < steps.size() else 0, 0, FULL_REACH)
		var tool: SurfaceTool = tools[step]
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			var c: Vector2 = corner
			tool.set_uv(Vector2(cell.x + c.x, cell.y + c.y) * .5)
			tool.add_vertex(Vector3(cell.x + c.x, 0.0, cell.y + c.y))
		world_cells.append(base + cell)
		if not _cells.has(base + cell):
			_cells[base + cell] = []
		(_cells[base + cell] as Array).append([id, step])
	var holder := Node3D.new()
	holder.name = "Flood_%s" % id.replace(":", "_")
	root.add_child(holder)
	var rings := []
	for step in tools.size():
		var ring := MeshInstance3D.new()
		ring.name = "Step%d" % step
		ring.mesh = (tools[step] as SurfaceTool).commit()
		ring.material_override = _water_material()
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ring.visible = false
		holder.add_child(ring)
		rings.append(ring)
	var centre: Vector2 = extras.get("centre", Vector2(spec["cell"]) + Vector2(.5, .5))
	var wall: Vector2 = extras.get("wall", Vector2.ZERO)
	# an outflow main gushes out of its torn stub at the wall, along the old run; a crawl pipe sprays up where it split
	var spray := _spray(Vector3(centre.x, SewerRouteGenerator.CRAWL_CLEARANCE + .4, centre.y), Vector3.UP, 70.0)
	if wall != Vector2.ZERO:
		var axis_y := SewerRouteGenerator.CRAWL_CLEARANCE + SewerRouteGenerator.OUTFLOW_SIZE.y * .5
		spray = _spray(Vector3(centre.x + wall.x * .9, axis_y, centre.y + wall.y * .9), Vector3(-wall.x, -.15, -wall.y), 18.0)
	root.add_child(spray)
	var gush: AudioStreamPlayer3D = null
	if DisplayServer.get_name() != "headless":
		gush = AudioStreamPlayer3D.new()
		gush.name = "FloodGush"
		gush.stream = FallsLoop.stream()
		gush.bus = &"SFX"
		gush.pitch_scale = 1.35
		gush.unit_size = 5.0
		gush.max_distance = GUSH_RANGE
		gush.position = spray.position
		root.add_child(gush)
		gush.play()
	_active[id] = {"holder": holder, "rings": rings, "spray": spray, "gush": gush, "chunk": coord, "cells": world_cells}


func _forget(id: String) -> void:
	var entry: Dictionary = _active.get(id, {})
	for key in ["holder", "spray", "gush"]:
		# the chunk root may have taken them with it already (an unloaded chunk): never cast a freed node
		var node: Variant = entry.get(key)
		if is_instance_valid(node):
			(node as Node).queue_free()
	for cell in entry.get("cells", []):
		var marks: Array = _cells.get(cell, [])
		for mark in marks.duplicate():
			if String((mark as Array)[0]) == id:
				marks.erase(mark)
		if marks.is_empty():
			_cells.erase(cell)
	_active.erase(id)


func _process(_delta: float) -> void:
	if view == null or view.world_state == null:
		return
	for id in _active.keys():
		var entry: Dictionary = _active[id]
		var state := _state(String(id))
		if state.x < 0.0 or spent(state.x, state.y) or not is_instance_valid(entry["holder"]) or not is_instance_valid(entry["spray"]):
			_forget(String(id))
			continue
		var depth := depth_shut(state.x, state.y)
		var reach := reach_shut(state.x, state.y)
		var running := state.y < 0.0
		(entry["holder"] as Node3D).position.y = depth
		var rings: Array = entry["rings"]
		for step in rings.size():
			(rings[step] as MeshInstance3D).visible = depth > MIN_DEPTH and step <= reach
		# the break gushes harder as the flood worsens
		var harder := worsening(state.x) if running else 0.0
		var spray := entry["spray"] as GPUParticles3D
		spray.emitting = running
		spray.amount_ratio = lerpf(.45, 1.0, harder)
		spray.speed_scale = lerpf(1.0, 1.5, harder)
		var gush: Variant = entry["gush"]
		if is_instance_valid(gush):
			(gush as AudioStreamPlayer3D).volume_db = lerpf(-4.0, 4.0, harder) if running else -60.0
			(gush as AudioStreamPlayer3D).pitch_scale = lerpf(1.35, 1.1, harder)
	var player := view.tracked_player
	if player != null and is_instance_valid(player):
		player.wading_depth = depth_under(player.global_position)


## Water depth over the floor at a world position on its level (0 outside every flood and beyond its spread).
func depth_under(at: Vector3) -> float:
	var cell := Vector2i(floori(at.x), floori(at.z))
	var deepest := 0.0
	for mark_value in _cells.get(cell, []):
		var mark: Array = mark_value
		var entry: Dictionary = _active.get(mark[0], {})
		if entry.is_empty() or int((entry["chunk"] as Vector3i).y) != StreamedFacilityView3D.snapped_level_for_world_y(at.y):
			continue
		var state := _state(String(mark[0]))
		if int(mark[1]) <= reach_shut(state.x, state.y):
			deepest = maxf(deepest, depth_shut(state.x, state.y))
	return deepest if deepest > MIN_DEPTH else 0.0


## Running (unshut) floods of a chunk's pipes: their ids.
func running_in(coord: Vector3i) -> Array:
	return _active.keys().filter(func(id: String) -> bool:
		return (_active[id] as Dictionary)["chunk"] == coord and view.world_state.flood_shut_at(id) < 0.0)


func forget_all() -> void:
	for id in _active.keys():
		_forget(String(id))


func flood_count() -> int:
	return _active.size()


static var _material: StandardMaterial3D


static func _water_material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(.16, .2, .15, .78)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.roughness = .12
		_material.metallic_specular = .8
		MaterialLook.tame(_material)
	return _material


## White water out of the break while it runs: a fan (up from a split crawl pipe, along the run from a torn main).
static func _spray(at: Vector3, direction: Vector3, spread: float) -> GPUParticles3D:
	var spray := GPUParticles3D.new()
	spray.name = "FloodSpray"
	spray.position = at
	spray.amount = 48 if spread > 30.0 else 90
	spray.lifetime = .7
	spray.emitting = false
	spray.visibility_aabb = AABB(Vector3(-3, -2, -3), Vector3(6, 3, 6))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(.5, .2, .5) if spread > 30.0 else Vector3(.35, .35, .35)
	process.direction = direction.normalized()
	process.spread = spread
	process.initial_velocity_min = 1.5 if spread > 30.0 else 2.6
	process.initial_velocity_max = 3.2 if spread > 30.0 else 4.4
	process.gravity = Vector3(0, -9.8, 0)
	spray.process_material = process
	var mesh := BoxMesh.new()
	mesh.size = Vector3(.05, .09, .05)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(.75, .85, .9)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = material
	spray.draw_pass_1 = mesh
	return spray
