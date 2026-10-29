class_name SewerFloods
extends Node3D

## Floods from sewer pipes broken with the Axe (KT: "a broken pipe floods the area"). A burst pipe (Breach "breached",
## KIND_PIPE, on every machine) sprays and gushes, and its walkway cells (the spec's extras.flood_cells, a bounded
## patch) fill to shin depth over RISE seconds, stay HOLD seconds and drain over DRAIN seconds. One flat water plane per
## flood, built once; only its height moves (no per-frame mesh work). The burst time lives in
## StreamedWorldState.floods, so every machine's water follows the same clock and a reloaded run carries on mid-flood.
## While the local runner stands in it they are slowed, their steps splash (loud to hunters) and they get soaked;
## hunters wade through at their normal pace.

const RISE := 8.0
const HOLD := 25.0
const DRAIN := 90.0
const DURATION := RISE + HOLD + DRAIN
## Ankle to shin: deep enough to slow and splash, never enough to swim or muffle.
const MAX_DEPTH := .35
## Below this the water is a film: not drawn, no slowing.
const MIN_DEPTH := .03
const GUSH_RANGE := 22.0

var view: StreamedFacilityView3D
## flood id -> {"water": MeshInstance3D, "spray": GPUParticles3D, "gush": AudioStreamPlayer3D, "chunk": Vector3i, "cells": Array (world)}
var _active := {}
## world cell -> flood ids covering it
var _cells := {}


## Water depth `age` seconds after the burst: a smooth rise, a hold, a linear drain.
static func depth_at(age: float) -> float:
	if age < 0.0 or age >= DURATION:
		return 0.0
	if age < RISE:
		var k := age / RISE
		return MAX_DEPTH * k * k * (3.0 - 2.0 * k)
	if age < RISE + HOLD:
		return MAX_DEPTH
	return MAX_DEPTH * (1.0 - (age - RISE - HOLD) / DRAIN)


## Whether the pipe is still spraying (rise and hold).
static func gushing(age: float) -> bool:
	return age >= 0.0 and age < RISE + HOLD


## A chunk was built: bring back any flood of its pipes that is still running.
func chunk_built(coord: Vector3i, root: Node3D, data: Dictionary) -> void:
	for spec_value in data.get("breakables", []):
		var spec: Dictionary = spec_value
		var id := String(spec["id"])
		if String(spec.get("kind", "")) != Breach.KIND_PIPE or _active.has(id):
			continue
		var age := view.world_state.flood_age(id)
		if age >= 0.0 and age < DURATION:
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
	var size := StreamedRouteGenerator.CHUNK_SIZE
	var base := Vector2i(coord.x, coord.z) * size
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	tool.set_normal(Vector3.UP)
	var world_cells := []
	for cell_value in extras.get("flood_cells", []):
		var cell: Vector2i = cell_value
		for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
			var c: Vector2 = corner
			tool.set_uv(Vector2(cell.x + c.x, cell.y + c.y) * .5)
			tool.add_vertex(Vector3(cell.x + c.x, 0.0, cell.y + c.y))
		world_cells.append(base + cell)
		if not _cells.has(base + cell):
			_cells[base + cell] = []
		(_cells[base + cell] as Array).append(id)
	var water := MeshInstance3D.new()
	water.name = "Flood_%s" % id.replace(":", "_")
	water.mesh = tool.commit()
	water.material_override = _water_material()
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	water.visible = false
	root.add_child(water)
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
	_active[id] = {"water": water, "spray": spray, "gush": gush, "chunk": coord, "cells": world_cells}


func _forget(id: String) -> void:
	var entry: Dictionary = _active.get(id, {})
	for key in ["water", "spray", "gush"]:
		# the chunk root may have taken them with it already (an unloaded chunk): never cast a freed node
		var node: Variant = entry.get(key)
		if is_instance_valid(node):
			(node as Node).queue_free()
	for cell in entry.get("cells", []):
		var ids: Array = _cells.get(cell, [])
		ids.erase(id)
		if ids.is_empty():
			_cells.erase(cell)
	_active.erase(id)


func _process(_delta: float) -> void:
	if view == null or view.world_state == null:
		return
	for id in _active.keys():
		var entry: Dictionary = _active[id]
		var age := view.world_state.flood_age(String(id))
		if age < 0.0 or age >= DURATION or not is_instance_valid(entry["water"]) or not is_instance_valid(entry["spray"]):
			_forget(String(id))
			continue
		var depth := depth_at(age)
		var water := entry["water"] as MeshInstance3D
		water.position.y = depth
		water.visible = depth > MIN_DEPTH
		(entry["spray"] as GPUParticles3D).emitting = gushing(age)
		var gush := entry["gush"] as AudioStreamPlayer3D
		if gush != null:
			gush.volume_db = linear_to_db(maxf(.02, depth / MAX_DEPTH)) if gushing(age) else -60.0
	var player := view.tracked_player
	if player != null and is_instance_valid(player):
		player.wading_depth = depth_under(player.global_position)


## Water depth over the floor at a world position on the tracked level (0 outside every flood).
func depth_under(at: Vector3) -> float:
	var cell := Vector2i(floori(at.x), floori(at.z))
	var deepest := 0.0
	for id in _cells.get(cell, []):
		var entry: Dictionary = _active.get(id, {})
		if entry.is_empty() or int((entry["chunk"] as Vector3i).y) != StreamedFacilityView3D.snapped_level_for_world_y(at.y):
			continue
		deepest = maxf(deepest, depth_at(view.world_state.flood_age(String(id))))
	return deepest if deepest > MIN_DEPTH else 0.0


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


## White water bursting out of the break while it gushes: a short, wide fan falling to the walkway.
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
