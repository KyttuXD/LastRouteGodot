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
		"front_office":
			_mask(office)
		"child_bedroom":
			_bedroom(office)
		"control_room":
			_facility(office)
		"lift_landing":
			_descent(office)
		"cargo_bay":
			_dayshift(office)
		"watch_post":
			_openair(office)


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
	NightWatchArt.box(root, Vector3(0.5, 0.3, 0.4), Vector3(-1.9, 0.15, -half_d + 0.25), {"name": "LowBox", "kind": "metal", "tint": Color(0.4, 0.45, 0.5)})


## Masked Hours: the 2D picture is a purple corridor with dark vent grilles on both walls, orange dashes along them and a checkered floor:
## dashes on the side walls (the palette lays the checker floor, the room already has the vents; the front wall stays plain).
static func _mask(office: Node3D) -> void:
	var hw: float = MaskOffice.HALF_W
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	for side in [-1.0, 1.0]:
		for z in [-1.2, -0.7, 1.4, 1.8]:
			NightWatchArt.box(root, Vector3(0.03, 0.07, 0.35), Vector3(side * (hw - 0.04), 1.05, z), {"name": "OrangeDash", "kind": "wall", "tint": ORANGE})


## Bedtime: the 2D picture's far wall is moon wallpaper: rows of small pale stars, a big crescent and a small framed one, under a warm yellow ceiling panel. One painted 44 x 20 pixel quad on the far wall (z = -half) and the lamp panel.
static func _bedroom(office: Node3D) -> void:
	var half: float = BedroomOffice.HALF
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	var w := 44
	var h := 20
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var star := Color8(214, 214, 236)
	var moon := Color8(246, 226, 140)
	for row in 4:
		for col in 11:
			img.set_pixel(2 + col * 4, 2 + row * 4, star)
	for y in range(3, 15):   # the big crescent: a disc less a shifted disc
		for x in range(14, 28):
			var d1 := Vector2(x - 20.0, y - 9.0).length()
			var d2 := Vector2(x - 22.5, y - 8.0).length()
			if d1 <= 6.0 and d2 > 5.0:
				img.set_pixel(x, y, moon)
	for y in range(5, 12):   # the small framed crescent
		for x in range(33, 40):
			img.set_pixel(x, y, Color8(70, 50, 100))
			if Vector2(x - 36.0, y - 8.0).length() <= 2.6 and Vector2(x - 37.2, y - 7.4).length() > 2.2:
				img.set_pixel(x, y, moon)
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(img)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.emission_enabled = true
	m.emission_texture = m.albedo_texture
	m.emission_energy_multiplier = 0.5
	m.roughness = 1.0
	m.set_meta("nw_kind", "fabric")
	var quad := QuadMesh.new()
	quad.size = Vector2(3.6, 3.6 * float(h) / float(w))
	var wall := MeshInstance3D.new()
	wall.name = "MoonWallpaper"
	wall.mesh = quad
	wall.material_override = m
	wall.position = Vector3(0, 2.0, -half + 0.04)
	wall.set_meta("nw_name", "MoonWallpaper")
	wall.set_meta("nw_palette", "poster")
	root.add_child(wall)
	NightWatchArt.box(root, Vector3(1.2, 0.04, 0.4), Vector3(0, BedroomOffice.HEIGHT - 0.03, 0.0), {"name": "CeilingPanelWarm", "kind": "light", "tint": Color(1.6, 1.35, 0.6)})


## The Facility (story): the 2D picture is a steel-blue corridor with yellow and black hazard tape along the top of the side walls, a panelled far wall with the lift (a red lamp over its door) and a cold white ceiling lamp:
## hazard tape over both side walls, panel lines on the far wall, the red lift lamp and the white ceiling panel.
static func _facility(office: Node3D) -> void:
	var w: float = ControlRoomOffice.ROOM_W
	var d: float = ControlRoomOffice.ROOM_D
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	var gap := 1.0   # the door slabs are at z 0 on both side walls
	var seg: float = d * 0.5 - gap - 0.15
	for side in [-1.0, 1.0]:
		for zs in [-1.0, 1.0]:
			NightWatchArt.box(root, Vector3(0.03, 0.18, seg), Vector3(side * (w * 0.5 - 0.05), 2.7, zs * (gap + seg * 0.5)), {"name": "HazardTape", "kind": "hazard"})
	var z: float = -d * 0.5 + 0.04
	for y in [0.8, 1.6, 2.4]:
		NightWatchArt.box(root, Vector3(w - 0.3, 0.03, 0.02), Vector3(0, y, z), {"name": "PanelLineH", "kind": "metal", "tint": Color(0.1, 0.16, 0.26)})
	for i in range(-3, 4):
		if absf(float(i) * 0.8) > 1.0:
			NightWatchArt.box(root, Vector3(0.03, 2.5, 0.02), Vector3(float(i) * 0.8, 1.5, z), {"name": "PanelLineV", "kind": "metal", "tint": Color(0.1, 0.16, 0.26)})
	NightWatchArt.box(root, Vector3(0.14, 0.08, 0.04), Vector3(0, 2.55, z + 0.02), {"name": "LiftLampRed", "kind": "light", "tint": Color(2.0, 0.25, 0.2)})
	NightWatchArt.box(root, Vector3(1.4, 0.04, 0.4), Vector3(0, ControlRoomOffice.HEIGHT - 0.03, 0.0), {"name": "CeilingPanelCool", "kind": "light", "tint": Color(1.4, 1.6, 1.8)})


## The Descent: the 2D picture is a slate lift landing: a big dark grid panel in an amber frame on the far wall, a small amber lamp above it and a warm amber ceiling lamp:
## the framed grid panel, the round lamp and the amber ceiling panel.
static func _descent(office: Node3D) -> void:
	var hd: float = NightWatchDescentOffice.W.HALF_D
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	var z: float = -hd + 0.04
	var amber := Color(1.9, 1.35, 0.45)
	var cx := 0.0
	var cy := 1.45
	var pw := 1.9
	var ph := 1.25
	for e in [[Vector3(pw + 0.08, 0.04, 0.03), Vector3(cx, cy + ph * 0.5, z)], [Vector3(pw + 0.08, 0.04, 0.03), Vector3(cx, cy - ph * 0.5, z)],
			[Vector3(0.04, ph, 0.03), Vector3(cx - pw * 0.5, cy, z)], [Vector3(0.04, ph, 0.03), Vector3(cx + pw * 0.5, cy, z)]]:
		NightWatchArt.box(root, e[0], e[1], {"name": "PanelFrame", "kind": "metal", "tint": amber})
	NightWatchArt.box(root, Vector3(pw - 0.04, ph - 0.04, 0.02), Vector3(cx, cy, z - 0.005), {"name": "PanelGlass", "kind": "metal", "tint": Color(0.05, 0.06, 0.09)})
	for i in range(1, 8):
		NightWatchArt.box(root, Vector3(0.015, ph - 0.06, 0.012), Vector3(cx - pw * 0.5 + pw * float(i) / 8.0, cy, z + 0.01), {"name": "PanelGridV", "kind": "metal", "tint": Color(0.3, 0.33, 0.45)})
	for i in range(1, 5):
		NightWatchArt.box(root, Vector3(pw - 0.06, 0.015, 0.012), Vector3(cx, cy - ph * 0.5 + ph * float(i) / 5.0, z + 0.01), {"name": "PanelGridH", "kind": "metal", "tint": Color(0.3, 0.33, 0.45)})
	NightWatchArt.box(root, Vector3(0.14, 0.09, 0.04), Vector3(0, cy + ph * 0.5 + 0.3, z + 0.01), {"name": "LampAmber", "kind": "light", "tint": Color(2.0, 1.4, 0.3)})
	NightWatchArt.box(root, Vector3(1.0, 0.04, 0.3), Vector3(0, NightWatchDescentOffice.W.HEIGHT - 0.03, 0.0), {"name": "CeilingPanelAmber", "kind": "light", "tint": Color(1.9, 1.4, 0.4)})


## Day shift: the 2D picture is the one office that reads as day: cream ceiling tiles, warm wood walls, a red rail round the room, two green and cream posters and a bright daylight lamp (the yard window is the room's own):
## a red rail on the side walls and the window wall, tile lines on the ceiling, a green star poster and a balloon poster by the window, and a very bright ceiling panel.
static func _dayshift(office: Node3D) -> void:
	var hw: float = CargoBay.HALF_W
	var hd: float = CargoBay.HALF_D
	var height: float = CargoBay.HEIGHT
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	var red := Color(1.8, 0.28, 0.25)
	for side in [-1.0, 1.0]:
		NightWatchArt.box(root, Vector3(0.03, 0.1, hd * 2.0 - 0.2), Vector3(side * (hw - 0.04), 1.0, 0.0), {"name": "RedRail", "kind": "wall", "tint": red})
	NightWatchArt.box(root, Vector3(hw * 2.0 - 0.2, 0.1, 0.03), Vector3(0, 1.0, hd - 0.04), {"name": "RedRail", "kind": "wall", "tint": red})
	NightWatchArt.box(root, Vector3(hw * 2.0 - 0.2, 0.1, 0.03), Vector3(0, 1.0, -hd + 0.04), {"name": "RedRail", "kind": "wall", "tint": red})
	var tile := Color(1.6, 1.5, 1.25)
	for i in range(-int(hw), int(hw) + 1):
		NightWatchArt.box(root, Vector3(0.03, 0.02, hd * 2.0 - 0.2), Vector3(float(i), height - 0.03, 0.0), {"name": "CeilingTileLine", "kind": "wall", "tint": tile * 0.6})
	for i in range(-int(hd), int(hd) + 1):
		NightWatchArt.box(root, Vector3(hw * 2.0 - 0.2, 0.02, 0.03), Vector3(0, height - 0.03, float(i)), {"name": "CeilingTileLine", "kind": "wall", "tint": tile * 0.6})
	NightWatchArt.box(root, Vector3(1.6, 0.04, 0.5), Vector3(0, height - 0.03, 0.0), {"name": "CeilingPanelDay", "kind": "light", "tint": Color(2.2, 2.0, 1.5)})
	# two posters either side of the window wall
	for p in [[-0.5, Color8(60, 130, 80)], [0.5, Color8(235, 200, 150)]]:
		var x: float = float(p[0]) + (hw - 0.6) * (1.0 if float(p[0]) > 0.0 else -1.0)
		NightWatchArt.box(root, Vector3(0.5, 0.7, 0.03), Vector3(x, 1.9, hd - 0.05), {"name": "PosterFrameDay", "kind": "wall", "tint": Color(0.45, 0.3, 0.2)})
		var q := NightWatchArt.box(root, Vector3(0.42, 0.62, 0.02), Vector3(x, 1.9, hd - 0.07), {"name": "PosterDay", "kind": "fabric", "tint": p[1] as Color})
		q.set_meta("nw_palette", "poster")


## Open Air: the three watches are outdoors under the 2D picture's night sky: a pale full moon with a halo, scattered stars, and (at the campfire) a dark ring of fir trees:
## a far dome of stars, the moon, and for watch 2 the tree ring (all well outside every footprint).
static func _openair(office: Node3D) -> void:
	var root := Node3D.new()
	root.name = "Signature"
	office.add_child(root)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261028
	for i in 160:
		var yaw := rng.randf() * TAU
		var pitch := lerpf(0.12, 1.3, rng.randf())
		var dir := Vector3(cos(pitch) * sin(yaw), sin(pitch), -cos(pitch) * cos(yaw))
		var size := 0.25 + rng.randf() * 0.35
		var star := _sky_piece(root, "StarLight", Vector3(size, size, 0.1), dir * 70.0, Color(0.9, 0.92, 1.0))
		star.look_at(Vector3.ZERO, Vector3.UP)
	var moon_dir := Vector3(0.2, 0.38, -0.9).normalized()
	var moon := _sky_piece(root, "MoonLight", Vector3(5.0, 5.0, 0.1), moon_dir * 68.0, Color(1.0, 0.92, 0.6))
	moon.look_at(Vector3.ZERO, Vector3.UP)
	var halo := _sky_piece(root, "MoonHaloLight", Vector3(8.0, 8.0, 0.1), moon_dir * 69.0, Color(0.22, 0.27, 0.55))
	halo.look_at(Vector3.ZERO, Vector3.UP)
	if int((office as NightWatchOpenAirOffice).watch) != 2:
		return
	for i in 28:
		var a := TAU * float(i) / 28.0 + rng.randf() * 0.2
		var r := 15.5 + rng.randf() * 3.0
		var base := Vector3(cos(a) * r, 0.0, sin(a) * r)
		var h := 5.0 + rng.randf() * 3.0
		for tier in 4:
			var w := 3.0 - float(tier) * 0.7
			NightWatchArt.box(root, Vector3(w, h * 0.22, w), base + Vector3(0, h * (0.2 + 0.2 * float(tier)), 0), {"name": "FirTier", "kind": "wall", "tint": Color(0.05, 0.1, 0.07)})
		NightWatchArt.box(root, Vector3(0.5, h * 0.3, 0.5), base + Vector3(0, h * 0.15, 0), {"name": "FirTrunk", "kind": "wall", "tint": Color(0.1, 0.07, 0.05)})


## A flat unshaded sky piece (stars, moon): lit by nothing, so the night's ambient cannot dull it.
static func _sky_piece(parent: Node3D, piece_name: String, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = piece_name
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.position = pos
	mesh.set_meta("nw_name", piece_name)
	parent.add_child(mesh)
	return mesh
