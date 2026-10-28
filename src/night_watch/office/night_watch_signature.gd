class_name NightWatchSignature
extends RefCounted

## The 2D offices' SIGNATURE pieces on the 3D offices (docs/night_watch_ui/NIGHT_WATCH_OFFICE_PORT.md): per office, the things that make its 2D picture itself, built from NightWatchArt cubes and a few painted pixel textures.
## Classic (and Mixed Shift, which is Classic's office): the orange band over a navy-and-white checker band round the walls, the five posters (purple star, red balloons, the big red triangle, the green face, amber star)
## and warm yellow ceiling lamps. One function per office; `apply(office, office_id)` is called by the office base after the shell is built.

const ORANGE := Color(1.5, 0.62, 0.2)


## false in the before / after capture tool
static var enabled := true


static func apply(office: Node3D, office_id: String) -> void:
	if not enabled:
		return
	match office_id:
		"classic_security", "hub_office":
			_classic(office)
		"broadcast_booth":
			_broadcast(office)


static func _classic(office: Node3D) -> void:
	var hw: float = NightWatchOffice.HALF_W
	var hd: float = NightWatchOffice.HALF_D
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	var door_half: float = NightWatchOffice.DOOR_W * 0.5
	# the bands on the front wall and on the side walls either side of the doors (the back wall has the desk wall's own dressing)
	var segments := [
		[Vector3(0, 0, hd - 0.05), Vector3(hw * 2.0 - 0.2, 0.0, 0.0), "z"],
		[Vector3(-hw + 0.05, 0, -(hd + door_half) * 0.5), Vector3(0.0, 0.0, hd - door_half - 0.1), "x"],
		[Vector3(-hw + 0.05, 0, (hd + door_half) * 0.5), Vector3(0.0, 0.0, hd - door_half - 0.1), "x"],
		[Vector3(hw - 0.05, 0, -(hd + door_half) * 0.5), Vector3(0.0, 0.0, hd - door_half - 0.1), "x"],
		[Vector3(hw - 0.05, 0, (hd + door_half) * 0.5), Vector3(0.0, 0.0, hd - door_half - 0.1), "x"],
	]
	for seg in segments:
		var at: Vector3 = seg[0]
		var length: float = (seg[1] as Vector3).x if String(seg[2]) == "z" else (seg[1] as Vector3).z
		var along_x := String(seg[2]) == "z"
		var size_band := Vector3(length, 0.1, 0.03) if along_x else Vector3(0.03, 0.1, length)
		var size_check := Vector3(length, 0.2, 0.03) if along_x else Vector3(0.03, 0.2, length)
		var band := NightWatchArt.box(root, size_band, Vector3(at.x, 1.3, at.z), {"name": "OrangeBand", "kind": "wall", "tint": ORANGE})
		band.set_meta("nw_palette", "band")
		var check := NightWatchArt.box(root, size_check, Vector3(at.x, 1.12, at.z), {"name": "CheckerBand", "kind": "wall"})
		check.material_override = _checker_material(length, along_x)
		check.set_meta("nw_palette", "band")
	# the five posters on the front wall, over the bands
	var specs := [[-1.7, 0.5, 0.68, "star", Color8(110, 60, 160)], [-0.95, 0.52, 0.72, "balloons", Color8(190, 50, 50)], [0.0, 0.8, 1.0, "triangle", Color8(190, 50, 60)],
		[0.95, 0.52, 0.72, "face", Color8(60, 130, 80)], [1.7, 0.5, 0.68, "star2", Color8(190, 120, 40)]]
	for s in specs:
		NightWatchArt.box(root, Vector3(float(s[1]) + 0.06, float(s[2]) + 0.06, 0.03), Vector3(float(s[0]), 1.85, hd - 0.05), {"name": "PosterFrame%s" % s[3], "kind": "wall", "tint": Color(0.4, 0.3, 0.2)})
		var poster := MeshInstance3D.new()   # one quad: the picture is painted once, not tiled
		poster.name = "Poster%s" % s[3]
		var quad := QuadMesh.new()
		quad.size = Vector2(float(s[1]), float(s[2]))
		poster.mesh = quad
		poster.material_override = _poster_material(String(s[3]), s[4] as Color)
		poster.position = Vector3(float(s[0]), 1.85, hd - 0.075)
		poster.rotation.y = PI
		poster.set_meta("nw_name", "Poster%s" % s[3])
		poster.set_meta("nw_palette", "poster")
		root.add_child(poster)
	# warm yellow ceiling lamps
	for node in office.find_children("CeilingLens*", "MeshInstance3D", true, false):
		(node as MeshInstance3D).material_override = NightWatchArt.material("light", Color(1.5, 1.3, 0.6))
		node.set_meta("nw_palette", "lamp")


static func _checker_material(length: float, along_x: bool) -> StandardMaterial3D:
	var img := Image.create(2, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color8(24, 38, 62))
	img.set_pixel(1, 0, Color8(190, 205, 215))
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_scale = Vector3(length / 0.2 * 0.5, 1.0, 1.0)
	m.roughness = 1.0
	m.set_meta("nw_kind", "wall")
	return m


## A poster's painted 16 x 20 pixel picture.
static func _poster_material(kind: String, base: Color) -> StandardMaterial3D:
	var img := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	img.fill(base)
	var cream := Color8(240, 225, 170)
	var gold := Color8(235, 190, 60)
	match kind:
		"star", "star2":
			for i in range(3, 13):
				img.set_pixel(8, i + 2, gold)
				img.set_pixel(i, 10, gold)
			for i in range(5, 11):
				img.set_pixel(i, 8, gold)
				img.set_pixel(i, 12, gold)
		"balloons":
			for c in [Vector2i(5, 6), Vector2i(10, 6), Vector2i(8, 9)]:
				for dx in range(-2, 3):
					for dy in range(-2, 3):
						if absi(dx) + absi(dy) <= 3:
							img.set_pixel(c.x + dx, c.y + dy, cream if c.y == 6 else gold)
			for y in range(12, 19):
				img.set_pixel(8, y, Color8(60, 40, 30))
		"triangle":
			for y in range(4, 16):
				var half := int((y - 4) * 0.55)
				for x in range(8 - half, 9 + half):
					img.set_pixel(clampi(x, 0, 15), y, cream)
			for x in range(5, 11):
				img.set_pixel(x, 17, Color8(30, 20, 20))
		"face":
			for dx in range(-4, 5):
				for dy in range(-4, 5):
					if dx * dx + dy * dy <= 17:
						img.set_pixel(8 + dx, 9 + dy, Color8(150, 220, 130))
			img.set_pixel(6, 8, Color8(30, 50, 30))
			img.set_pixel(10, 8, Color8(30, 50, 30))
			for x in range(6, 11):
				img.set_pixel(x, 11, Color8(30, 50, 30))
	for x in 16:
		img.set_pixel(x, 0, cream * 0.5)
		img.set_pixel(x, 19, cream * 0.5)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 1.0
	m.set_meta("nw_kind", "fabric")
	return m


## Dead Air: the 2D picture is a teal booth with a barred window on the far wall, vent grilles at the sides and a cold cyan ceiling lamp: dark bars across the studio window (every 0.35 m, over the mullions), a cyan lamp panel,
## and a low grey box under the window.
static func _broadcast(office: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	var half_d: float = 2.5
	# the acoustic foam wall is the 2D teal panelling
	var n := 0
	for node in office.find_children("*", "MeshInstance3D", true, false):
		if not String(node.get_meta("nw_name", node.name)).begins_with("FoamWedge"):
			continue
		var shade := 0.75 + 0.1 * float(n % 3)
		(node as MeshInstance3D).material_override = NightWatchArt.material("wall", Color(0.35 * shade, 1.0 * shade, 1.25 * shade))
		n += 1
	for i in range(-4, 5):
		NightWatchArt.box(root, Vector3(0.1, 1.55, 0.07), Vector3(float(i) * 0.35, 1.75, -half_d + 0.05), {"name": "WindowBar", "kind": "metal", "tint": Color(0.12, 0.14, 0.17)})
	NightWatchArt.box(root, Vector3(0.9, 0.04, 0.4), Vector3(0, 2.96, 0.2), {"name": "CeilingPanelCyan", "kind": "light", "tint": Color(0.8, 1.5, 1.6)})
	NightWatchArt.box(root, Vector3(0.5, 0.3, 0.4), Vector3(-1.9, 0.15, -half_d + 0.4), {"name": "FloorBox", "kind": "metal", "tint": Color(0.4, 0.45, 0.5)})
