class_name InfernoLandingPile
extends RefCounted

## Where things dumped into the Inferno come to rest (StreamedRouteGenerator.dump_landing): a low mound of crates, torn
## sacks, scrap and basalt rubble in the open middle of a chamber, with a faint ember glow in its gaps. A chunk shows one
## when its data has "landing_pile" (a chunk-local cell); the generator sets it for dump-hole chunks and for a share of the
## others, so the cave is not all empty floor. Not walkable through: a small blocker stands in the mound.

const BOXES := 18


static func build(root: Node3D, data: Dictionary) -> void:
	var cell: Vector2i = data.get("landing_pile", Vector2i(-1, -1))
	if cell.x < 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%s:PILE" % String(data.get("chunk_id", "")))
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(cell.x + .5, 0.0, cell.y + .5)
	for i in BOXES:
		var angle := rng.randf() * TAU
		var radius := rng.randf() * .95
		var height := maxf(0.0, .55 - radius * .5)
		var size := Vector3(rng.randf_range(.25, .6), rng.randf_range(.15, .4), rng.randf_range(.25, .6))
		var at := centre + Vector3(cos(angle) * radius, height + size.y * .5, sin(angle) * radius)
		var tone := [Color("3a2c20"), Color("4a3a2a"), Color("2c2a2c"), Color("1e1a1c"), Color("55483a")][rng.randi() % 5]
		_box(tool, at, size, rng.randf() * PI, tone)
	var mesh := MeshInstance3D.new()
	mesh.name = "LandingPile"
	mesh.mesh = tool.commit()
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = .95
	mesh.material_override = material
	root.add_child(mesh)
	var glow := OmniLight3D.new()
	glow.name = "LandingPileGlow"
	glow.position = centre + Vector3(0, .35, 0)
	glow.light_color = Color("ff7a30")
	glow.light_energy = .7
	glow.omni_range = 4.5
	glow.shadow_enabled = false
	root.add_child(glow)
	var body := StaticBody3D.new()
	body.name = "LandingPileBody"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.3, .6, 1.3)
	shape.shape = box
	shape.position = centre + Vector3(0, .3, 0)
	body.add_child(shape)
	root.add_child(body)


static func _box(tool: SurfaceTool, centre: Vector3, size: Vector3, yaw: float, color: Color) -> void:
	var basis := Basis(Vector3.UP, yaw)
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
		tool.set_normal(basis * (face[0] as Vector3))
		tool.set_color(color)
		for index in [1, 2, 3, 1, 3, 4]:
			tool.add_vertex(centre + basis * (face[index] as Vector3))
