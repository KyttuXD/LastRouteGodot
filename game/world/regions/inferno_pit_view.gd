class_name InfernoPitView
extends RefCounted

## Draws one chunk's cage-pit district (InfernoCaverns pits): a glowing lava channel under rails with a chain bridge
## across it, iron cages hanging on chains from the ceiling at three heights (some swaying, some with the door ajar),
## a row of cages against a wall, cracks of light in the floor, an orange underglow, rising embers and a low rumble.
## Lava is never walkable: invisible blockers stand on it (and the walk grid already calls it rock).

const LAVA_Y := -0.7
const BASIN_Y := -1.6
const LAVA_SOUND_SPACING := 6.0
const RAIL_H := 1.0
const POST_STEP := 1.0
const LAVA_SHADER_CODE := """
shader_type spatial;
render_mode unshaded;
varying vec2 w;
void vertex() { w = VERTEX.xz; }
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float n(vec2 p) { vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h(i), h(i + vec2(1, 0)), f.x), mix(h(i + vec2(0, 1)), h(i + vec2(1, 1)), f.x), f.y); }
void fragment() {
	float t = TIME * .25;
	float a = n(w * 1.3 + vec2(t, -t * .6)) * .6 + n(w * 3.1 - vec2(t * .8, t)) * .4;
	vec3 crust = vec3(.30, .05, .02);
	vec3 glow = mix(vec3(.95, .25, .03), vec3(1.0, .8, .25), smoothstep(.55, .9, a));
	ALBEDO = mix(glow, crust, smoothstep(.45, .75, 1.0 - a) * .7);
}
"""

static var _lava_material: ShaderMaterial
static var _iron: StandardMaterial3D
static var _glow: StandardMaterial3D
static var _cage_meshes := {}


static func build(root: Node3D, data: Dictionary) -> void:
	var pits := InfernoCaverns.pits_in(data)
	if pits.is_empty():
		return
	var pit_root := Node3D.new()
	pit_root.name = "InfernoPits"
	root.add_child(pit_root)
	var blockers := StaticBody3D.new()
	blockers.name = "PitBlockers"
	pit_root.add_child(blockers)
	for pit in pits:
		_build_pit(pit_root, blockers, pit as Dictionary)


static func _build_pit(parent: Node3D, blockers: StaticBody3D, pit: Dictionary) -> void:
	var lava: Array = pit["lava"]
	var lava_set := {}
	for cell in lava:
		lava_set[cell] = true
	# the lava itself and the dark basin under it
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var basin := SurfaceTool.new()
	basin.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell_value in lava:
		var cell: Vector2i = cell_value
		_quad(surface, cell, LAVA_Y)
		_quad(basin, cell, BASIN_Y)
	var lava_mesh := MeshInstance3D.new()
	lava_mesh.name = "Lava"
	lava_mesh.mesh = surface.commit()
	lava_mesh.material_override = _lava()
	lava_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(lava_mesh)
	# the lava's bubbling: a positional source of the level layer every LAVA_SOUND_SPACING metres along the channel
	var sounded: Array[Vector2i] = []
	for cell_value in lava:
		var cell: Vector2i = cell_value
		if sounded.all(func(other: Vector2i) -> bool: return Vector2(other).distance_to(Vector2(cell)) >= LAVA_SOUND_SPACING):
			sounded.append(cell)
			LevelAmbience.add(parent, "lava", Vector3(cell.x + .5, .3, cell.y + .5))
	var basin_mesh := MeshInstance3D.new()
	basin_mesh.name = "LavaBasin"
	basin_mesh.mesh = basin.commit()
	basin_mesh.material_override = _iron_material()
	parent.add_child(basin_mesh)
	# rails along every lava edge that meets floor, posts at each metre
	var iron := SurfaceTool.new()
	iron.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cell_value in lava:
		var cell: Vector2i = cell_value
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if lava_set.has(next):
				continue
			var mid := Vector3(cell.x + .5 + step.x * .5, 0, cell.y + .5 + step.y * .5)
			var along := Vector3(absf(step.y), 0, absf(step.x))
			iron_box(iron, mid + Vector3(0, RAIL_H, 0), Vector3(.06 + along.x * 1.0, .06, .06 + along.z * 1.0))
			iron_box(iron, mid + Vector3(0, RAIL_H * .5, 0), Vector3(.06 + along.x * 1.0, .04, .06 + along.z * 1.0))
			iron_box(iron, mid + Vector3(0, RAIL_H * .5, 0), Vector3(.07, RAIL_H, .07))
	# the span: chain posts and rope-rails along its two sides
	var span: Rect2i = pit["bridge"]
	for side in [span.position.x, span.end.x]:
		for z in range(span.position.y, span.end.y + 1):
			iron_box(iron, Vector3(side, RAIL_H * .5, z), Vector3(.08, RAIL_H, .08))
		iron_box(iron, Vector3(side, RAIL_H, span.position.y + span.size.y * .5), Vector3(.05, .05, span.size.y))
		iron_box(iron, Vector3(side, RAIL_H * .55, span.position.y + span.size.y * .5), Vector3(.03, .03, span.size.y))
	var iron_mesh := MeshInstance3D.new()
	iron_mesh.name = "PitIron"
	iron_mesh.mesh = iron.commit()
	iron_mesh.material_override = _iron_material()
	parent.add_child(iron_mesh)
	# invisible walls on the lava, a row at a time
	var rows := {}
	for cell_value in lava:
		var cell: Vector2i = cell_value
		if not rows.has(cell.y):
			rows[cell.y] = []
		(rows[cell.y] as Array).append(cell.x)
	for z in rows:
		var xs: Array = rows[z]
		xs.sort()
		var start: int = xs[0]
		var previous: int = xs[0]
		for index in range(1, xs.size() + 1):
			var x: int = xs[index] if index < xs.size() else -999
			if x != previous + 1:
				_blocker(blockers, Vector3(start + (previous - start + 1) * .5, .8, z + .5), Vector3(previous - start + 1, 1.6, 1.0))
				start = x
			previous = x
	# cracks of light in the floor
	var cracks := SurfaceTool.new()
	cracks.begin(Mesh.PRIMITIVE_TRIANGLES)
	for crack in pit["cracks"]:
		var cell: Vector2i = crack["cell"]
		var yaw: float = crack["yaw"]
		var length: float = crack["length"]
		var dir := Vector3(cos(yaw), 0, sin(yaw))
		var side := Vector3(-dir.z, 0, dir.x) * .05
		var centre := Vector3(cell.x + .5, .012, cell.y + .5)
		var a := centre - dir * length * .5
		var b := centre + dir * length * .5
		for v in [a - side, a + side, b + side, a - side, b + side, b - side]:
			cracks.set_normal(Vector3.UP)
			cracks.add_vertex(v)
	var crack_mesh := MeshInstance3D.new()
	crack_mesh.name = "FloorCracks"
	crack_mesh.mesh = cracks.commit()
	crack_mesh.material_override = _glow_material()
	crack_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(crack_mesh)
	# hanging cages
	for cage in pit["cages"]:
		_hanging_cage(parent, blockers, cage as Dictionary)
	# the row against the wall
	for entry in pit["row"]:
		var cell: Vector2i = entry["cell"]
		var mesh_node := MeshInstance3D.new()
		mesh_node.mesh = _cage_mesh(bool(entry["open"]))
		mesh_node.position = Vector3(cell.x + .5, 0, cell.y + .5)
		mesh_node.material_override = _iron_material()
		parent.add_child(mesh_node)
		_blocker(blockers, Vector3(cell.x + .5, CAGE_H * .5, cell.y + .5), Vector3(.9, CAGE_H, .9))
	# underglow, embers, rumble
	var centre_cell: Vector2i = lava[lava.size() / 2]
	var light := OmniLight3D.new()
	light.name = "LavaGlow"
	light.position = Vector3(centre_cell.x + .5, .6, centre_cell.y + .5)
	light.light_color = Color("ff6a1c")
	light.light_energy = 2.4
	light.omni_range = 11.0
	light.shadow_enabled = false
	parent.add_child(light)
	parent.add_child(_embers(lava, centre_cell))
	var rumble := Node3D.new()
	rumble.name = "PitRumble"
	rumble.set_script(preload("res://game/world/regions/inferno_pit_rumble.gd"))
	rumble.position = Vector3(centre_cell.x + .5, 0, centre_cell.y + .5)
	parent.add_child(rumble)


const CAGE_H := InfernoCaverns.CAGE_HEIGHT


static func _hanging_cage(parent: Node3D, blockers: StaticBody3D, cage: Dictionary) -> void:
	var cell: Vector2i = cage["cell"]
	var bottom: float = cage["bottom"]
	var top := bottom + CAGE_H
	var cap := InfernoCaverns.CAGE_CAP
	var pivot := Node3D.new()
	pivot.name = "HangingCage"
	pivot.set_meta("hanging_cage", true)
	pivot.position = Vector3(cell.x + .5, cap, cell.y + .5)
	parent.add_child(pivot)
	var chain := SurfaceTool.new()
	chain.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := cap - top
	var links := maxi(1, int(length / .12))
	for i in links:
		iron_box(chain, Vector3(0, -.06 - i * .12, 0), Vector3(.03 if i % 2 == 0 else .09, .1, .09 if i % 2 == 0 else .03))
	var chain_node := MeshInstance3D.new()
	chain_node.mesh = chain.commit()
	chain_node.material_override = _iron_material()
	pivot.add_child(chain_node)
	var cage_node := MeshInstance3D.new()
	cage_node.mesh = _cage_mesh(bool(cage["open"]))
	cage_node.position = Vector3(0, bottom - cap, 0)
	cage_node.material_override = _iron_material()
	pivot.add_child(cage_node)
	if bool(cage["sway"]):
		var swing := absi(hash(cell) % 7) * .004 + .035
		pivot.rotation.z = -swing
		var tween := pivot.create_tween().set_loops()
		tween.tween_property(pivot, "rotation:z", swing, 2.0 + (absi(hash(cell)) % 5) * .35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.tween_property(pivot, "rotation:z", -swing, 2.0 + (absi(hash(cell)) % 5) * .35).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if bottom < 1.9:
		_blocker(blockers, Vector3(cell.x + .5, bottom + CAGE_H * .5, cell.y + .5), Vector3(.9, CAGE_H, .9))


static func _blocker(body: StaticBody3D, centre: Vector3, size: Vector3) -> void:
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position = centre
	body.add_child(shape)


static func _embers(lava: Array, centre_cell: Vector2i) -> GPUParticles3D:
	var embers := GPUParticles3D.new()
	embers.name = "LavaEmbers"
	embers.position = Vector3(centre_cell.x + .5, LAVA_Y + .1, centre_cell.y + .5)
	# fewer rising embers (was 36 @ 3.2s over a 32m AABB)
	embers.amount = 16
	embers.lifetime = 2.2
	embers.local_coords = true
	embers.visibility_aabb = AABB(Vector3(-8, -1, -8), Vector3(16, 6, 16))
	var process := ParticleProcessMaterial.new()
	process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	process.emission_box_extents = Vector3(minf(6.0, lava.size() * .25), .1, 1.4)
	process.direction = Vector3.UP
	process.spread = 25.0
	process.initial_velocity_min = .5
	process.initial_velocity_max = 1.4
	process.gravity = Vector3(0, .25, 0)
	process.scale_min = .4
	process.scale_max = 1.0
	embers.process_material = process
	var quad := QuadMesh.new()
	quad.size = Vector2(.05, .05)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color("ff9a3a")
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = material
	embers.draw_pass_1 = quad
	return embers


static func _quad(tool: SurfaceTool, cell: Vector2i, y: float) -> void:
	for corner in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		var c: Vector2 = corner
		tool.set_normal(Vector3.UP)
		tool.set_uv(Vector2(cell.x + c.x, cell.y + c.y))
		tool.add_vertex(Vector3(cell.x + c.x, y, cell.y + c.y))


## Appends an axis-aligned box (centre, size) to `tool`.
static func iron_box(tool: SurfaceTool, centre: Vector3, size: Vector3) -> void:
	var h := size * .5
	var faces := [
		[Vector3.UP, Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.DOWN, Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
		[Vector3.RIGHT, Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)],
		[Vector3.LEFT, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z)],
		[Vector3.BACK, Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)],
		[Vector3.FORWARD, Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)],
	]
	for face in faces:
		tool.set_normal(face[0])
		for index in [1, 2, 3, 1, 3, 4]:
			tool.add_vertex(centre + (face[index] as Vector3))


## A cage with its origin at the middle of its floor: corner posts, a top and bottom frame, bars all round, a door.
static func _cage_mesh(open: bool) -> ArrayMesh:
	if _cage_meshes.has(open):
		return _cage_meshes[open]
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := .9
	var hw := w * .5
	for sx in [-1, 1]:
		for sz in [-1, 1]:
			iron_box(tool, Vector3(sx * hw, CAGE_H * .5, sz * hw), Vector3(.07, CAGE_H, .07))
	for y in [.04, CAGE_H - .04]:
		iron_box(tool, Vector3(0, y, hw), Vector3(w, .06, .06))
		iron_box(tool, Vector3(0, y, -hw), Vector3(w, .06, .06))
		iron_box(tool, Vector3(hw, y, 0), Vector3(.06, .06, w))
		iron_box(tool, Vector3(-hw, y, 0), Vector3(.06, .06, w))
	for i in range(1, 6):
		var o := -hw + i * w / 6.0
		iron_box(tool, Vector3(o, CAGE_H * .5, -hw), Vector3(.03, CAGE_H, .03))
		iron_box(tool, Vector3(hw, CAGE_H * .5, o), Vector3(.03, CAGE_H, .03))
		iron_box(tool, Vector3(-hw, CAGE_H * .5, o), Vector3(.03, CAGE_H, .03))
		if not open or i < 2 or i > 3:
			iron_box(tool, Vector3(o, CAGE_H * .5, hw), Vector3(.03, CAGE_H, .03))
	if open:
		# the door swung out on its hinge
		iron_box(tool, Vector3(-hw - .3, CAGE_H * .5, hw + .38), Vector3(.03, CAGE_H * .9, .5))
	var mesh := tool.commit()
	_cage_meshes[open] = mesh
	return mesh


static func _lava() -> ShaderMaterial:
	if _lava_material == null:
		var shader := Shader.new()
		shader.code = LAVA_SHADER_CODE
		_lava_material = ShaderMaterial.new()
		_lava_material.shader = shader
	return _lava_material


static func _iron_material() -> StandardMaterial3D:
	if _iron == null:
		_iron = StandardMaterial3D.new()
		_iron.albedo_color = Color(.13, .12, .12)
		_iron.roughness = .85
		_iron.metallic = .4
	return _iron


static func _glow_material() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.albedo_color = Color("ff7a22")
		_glow.emission_enabled = true
		_glow.emission = Color("ff5a10")
	return _glow
