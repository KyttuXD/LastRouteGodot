class_name NightWatchPalette
extends RefCounted

## The 2D game's office COLOURS on the 3D offices. Each 2D office has its own wall, floor and ceiling colours (Classic and Dead Air teal, Masked Hours purple, Bedtime
## violet, the Facility steel blue, the Descent slate, the day shift warm cream, Open Air a night-blue rooftop); the table below is those colours (sampled from the images), applied to the walls, floors and ceilings
## of the 3D office after it is built by tinting the shell's materials (NightWatchArt keeps one material per kind and tint, so this costs nothing). Props, screens, doors and lamps keep their own colours.

## office id -> {"wall", "floor", "ceiling": the 2D colour (0..1); "trim": the stripe colour (Classic's orange band); "gain": how much brighter the tint is than the colour (the stone texture is dark)}
const PALETTES := {
	"classic_security": {"wall": Color8(32, 62, 78), "floor": Color8(24, 34, 50), "ceiling": Color8(50, 79, 92), "trim": Color8(224, 122, 48)},
	"front_office": {"wall": Color8(50, 38, 104), "floor": Color8(28, 22, 73), "ceiling": Color8(13, 10, 41), "trim": Color8(210, 70, 120)},
	"broadcast_booth": {"wall": Color8(20, 54, 78), "floor": Color8(16, 34, 52), "ceiling": Color8(41, 78, 91), "trim": Color8(224, 122, 48)},
	"child_bedroom": {"wall": Color8(38, 30, 82), "floor": Color8(47, 31, 67), "ceiling": Color8(66, 54, 68), "trim": Color8(240, 220, 120)},
	"control_room": {"wall": Color8(33, 50, 77), "floor": Color8(23, 37, 59), "ceiling": Color8(52, 75, 103), "trim": Color8(232, 190, 40)},
	"lift_landing": {"wall": Color8(36, 39, 51), "floor": Color8(29, 31, 40), "ceiling": Color8(77, 69, 61), "trim": Color8(232, 190, 40)},
	"cargo_bay": {"wall": Color8(190, 135, 92), "floor": Color8(86, 90, 72), "ceiling": Color8(240, 205, 150), "trim": Color8(190, 60, 50)},
	"watch_post": {"wall": Color8(25, 31, 50), "floor": Color8(24, 29, 45), "ceiling": Color8(34, 41, 79), "trim": Color8(110, 130, 200)},
	"hub_office": {"wall": Color8(40, 52, 62), "floor": Color8(24, 35, 51), "ceiling": Color8(59, 70, 78), "trim": Color8(224, 122, 48)},
}
const GAIN := 3.0
const MAX_TINT := 1.5
const WALL_KINDS := ["wall"]
const FLOOR_KINDS := ["floor"]
const CEILING_KINDS := ["concrete"]


static func tint_for(office_id: String, part: String) -> Color:
	var p: Dictionary = PALETTES.get(office_id, {})
	if p.is_empty() or not p.has(part):
		return Color.WHITE
	var c: Color = p[part]
	return Color(minf(c.r * GAIN, MAX_TINT), minf(c.g * GAIN, MAX_TINT), minf(c.b * GAIN, MAX_TINT))


## Tint the shell of a built office. Idempotent (a mesh is tinted once).
## false in the before / after capture tool
static var enabled := true


static func apply(root: Node, office_id: String) -> int:
	if not enabled or not PALETTES.has(office_id):
		return 0
	var changed := 0
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.has_meta("nw_palette") or not mi.material_override is StandardMaterial3D:
			continue
		var mat := mi.material_override as StandardMaterial3D
		var kind := String(mat.get_meta("nw_kind", ""))
		var part := ""
		var own_name := String(mi.get_meta("nw_name", mi.name))
		if own_name == "Floor":
			part = "floor"   # every office's floor slab, whatever its material kind (Dead Air's is carpet)
		elif WALL_KINDS.has(kind):
			part = "wall"
		elif FLOOR_KINDS.has(kind) and own_name != "Floor":
			part = "floor"
		elif CEILING_KINDS.has(kind) and String(mi.get_meta("nw_name", mi.name)).to_lower().contains("ceiling"):
			part = "ceiling"
		if part.is_empty():
			continue
		mi.material_override = NightWatchArt.material(kind, mat.albedo_color * tint_for(office_id, part))
		mi.set_meta("nw_palette", part)
		changed += 1
		if part == "floor" and String(mi.get_meta("nw_name", mi.name)) == "Floor":
			_checker(mi, office_id)
	return changed


## The 2D floors are checkerboards: a thin checkered plane on the top of the floor slab, the floor colour and a darker one, a metre a square.
static func _checker(floor_mesh: MeshInstance3D, office_id: String) -> void:
	var box := floor_mesh.get_aabb()
	var base: Color = (PALETTES[office_id] as Dictionary)["floor"]
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	var light := Color(minf(base.r * 1.9, 1.0), minf(base.g * 1.9, 1.0), minf(base.b * 1.9, 1.0))
	var dark := Color(base.r * 1.1, base.g * 1.1, base.b * 1.1)
	img.set_pixel(0, 0, light)
	img.set_pixel(1, 1, light)
	img.set_pixel(1, 0, dark)
	img.set_pixel(0, 1, dark)
	var plane := MeshInstance3D.new()
	plane.name = "FloorChecker"
	var pm := PlaneMesh.new()
	pm.size = Vector2(box.size.x, box.size.z)
	plane.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(box.size.x / 2.0, box.size.z / 2.0, 1.0)
	m.roughness = 1.0
	plane.material_override = m
	plane.position = box.get_center() + Vector3(0, box.size.y * 0.5 + 0.004, 0)
	floor_mesh.add_child(plane)
