class_name NightWatchArt
extends RefCounted

## Night Watch's art helper: shaded cubes with painted pixel textures. There are no post effects, so all the shading is baked:
## every cube is built face by face with vertex colours (top lighter, bottom darker, one light direction, a darker band where it
## meets the floor or a neighbour) and carries a small hand-painted 16x16 pixel texture with a 3-4 tone ramp per material kind
## (wood, metal, plastic, fabric, concrete, glass, wall, floor, screen, label). Emissive cubes (screens, lamps, LEDs, labels) use
## the same textures unshaded. Everything is generated from code, deterministic, and only used by Night Watch's own scenes.
##
## Rules the validator checks: every texture is at most 32 x 32 with at most 8 colours, every prop group has at least a few cubes
## and at least two material looks, and emissive cubes only exist where a node name says they may (EMISSIVE_NAMES).

const TEX := 16
## metres of cube face covered by one texture tile
const TILE := 0.5
## Hazard tape is drawn at twice the density (16 px per 0.25 m = 64 px/m), its 45 degree period is 8 px = 0.125 m: a band 0.09 m tall shows
## a stripe and a half. Every hazard face counts a whole number of periods along its length, so it starts and ends on the same phase.
const HAZ_TILE := 0.25
const HAZ_PERIOD_M := HAZ_TILE * 0.5
## Names (substring match) that may be emissive.
const EMISSIVE_NAMES := ["Screen", "LampShade", "Led", "Label", "Button", "CeilingPanel", "ClockFace", "Glow", "Sign", "Feed", "Rec"]

## kind -> ramp, lightest first (3-4 tones, hand-picked)
const RAMPS := {
	"wood": [Color("c08a55"), Color("a06f40"), Color("7d5230"), Color("573820")],
	"metal": [Color("8e96a0"), Color("6c7480"), Color("4c525c"), Color("2f333a")],
	"plastic": [Color("5a5e66"), Color("42464d"), Color("2e3137"), Color("1c1e22")],
	"fabric": [Color("7a4e5e"), Color("633d4c"), Color("4d2f3b"), Color("361f29")],
	"concrete": [Color("7d8088"), Color("686b73"), Color("52555c"), Color("3d3f45")],
	"glass": [Color("b9d6d2"), Color("86aaa8"), Color("5b7c7d"), Color("3a5558")],
	"wall": [Color("6d7587"), Color("585f70"), Color("444a59"), Color("323744")],
	"floor": [Color("5f5a62"), Color("4b4650"), Color("39353f"), Color("29262f")],
	"screen": [Color("bff0d8"), Color("7fd1b0"), Color("4a9c86"), Color("2c6b60")],
	"label": [Color("f2c230"), Color("d9a21f"), Color("2b2416"), Color("14110a")],
	"paper": [Color("e8e2d0"), Color("c9c2ae"), Color("6b6455"), Color("3a352c")],
	"hazard": [Color("f2c230"), Color("d9a21f"), Color("2b2416"), Color("14110a")],
	"light": [Color("fff3c8"), Color("ffe08f"), Color("f0b954"), Color("c98a35")],
	"red": [Color("e86a5a"), Color("c44a3c"), Color("8e2f28"), Color("5a1d1a")],
	"green": [Color("8be89a"), Color("55c46a"), Color("379248"), Color("1f5a2c")],
}

static var _textures := {}
static var _materials := {}


static func _hash(x: int, y: int, salt: int) -> float:
	var h := (x * 374761393 + y * 668265263 + salt * 2246822519) & 0x7fffffff
	h = (h ^ (h >> 13)) * 1274126177 & 0x7fffffff
	return float(h & 0xffff) / 65535.0


## The painted 16 x 16 tile for a material kind (cached).
static func texture(kind: String) -> ImageTexture:
	if _textures.has(kind):
		return _textures[kind]
	var ramp: Array = RAMPS.get(kind, RAMPS["concrete"])
	var salt := kind.hash() & 0xffff
	var img := Image.create(TEX, TEX, false, Image.FORMAT_RGBA8)
	for y in TEX:
		for x in TEX:
			var n := _hash(x, y, salt)
			var tone := 1
			match kind:
				"wood":
					tone = 1
					if y % 5 == 0:
						tone = 2
					elif n < 0.12:
						tone = 0
					elif n > 0.9:
						tone = 3
					if x % 8 == 0:
						tone = 3
				"metal":
					tone = 1 + int(_hash(0, y, salt) * 2.0) - 0
					if x == 0 or y == 0:
						tone = 0
					elif x == TEX - 1 or y == TEX - 1:
						tone = 3
					if (x == 3 and y == 3) or (x == 12 and y == 12) or (x == 3 and y == 12) or (x == 12 and y == 3):
						tone = 0 if (x + y) % 2 == 0 else 3
				"plastic":
					tone = 1
					if n < 0.08:
						tone = 0
					elif n > 0.92:
						tone = 2
					if x == 0 or y == 0:
						tone = 0
					elif x == TEX - 1 or y == TEX - 1:
						tone = 3
				"fabric":
					tone = 1 + ((x + y) % 2) + (1 if n > 0.93 else 0)
					tone = mini(tone, 3)
					if n < 0.05:
						tone = 0
				"concrete":
					tone = clampi(int(n * 4.0), 0, 3)
					if n > 0.5 and n < 0.8:
						tone = 1
				"glass":
					tone = clampi(int(float(y) / float(TEX) * 3.0) + 0, 0, 3)
					if absi(x - y) <= 1 and y > 3 and y < 12:
						tone = 0
				"wall":
					tone = 1
					if y == 8:
						tone = 3
					elif y == 9:
						tone = 0
					elif n < 0.1:
						tone = 2
					elif n > 0.95:
						tone = 0
					if (x == 1 or x == 14) and (y == 1 or y == 14):
						tone = 0
				"floor":
					tone = 1 if ((x / 8) + (y / 8)) % 2 == 0 else 2
					if x % 8 == 0 or y % 8 == 0:
						tone = 3
					elif n < 0.1:
						tone = 3
					elif n > 0.93:
						tone = 0
				"screen":
					tone = 1 if y % 2 == 0 else 2
					if y < 2:
						tone = 0
					elif y > TEX - 3:
						tone = 3
				"label", "paper":
					# a plain plate: a dark border, two rows of "text"; no diagonal pattern (only hazard tape has stripes)
					tone = 0
					if (y == 5 or y == 6 or y == 9 or y == 10) and x >= 2 and x <= 13:
						tone = 2
					if y == 0 or y == TEX - 1 or x == 0 or x == TEX - 1:
						tone = 1
				"hazard":
					# 45 degree tape: stripes 4 px wide, period 8 px along u and along v, so the tile repeats seamlessly
					var d := (x + y) % 8
					tone = 0 if d < 4 else 2
					if d == 0:
						tone = 1      # the lit edge of a yellow stripe
					elif d == 4:
						tone = 3      # the dark edge of a black stripe
				"light":
					tone = clampi(int(float(maxi(absi(x - 8), absi(y - 8))) / 3.0), 0, 3)
				_:
					tone = clampi(int(n * 4.0), 0, 3)
			img.set_pixel(x, y, ramp[clampi(tone, 0, ramp.size() - 1)])
	var tex := ImageTexture.create_from_image(img)
	_textures[kind] = tex
	return tex


## A material: the kind's texture times a tint, vertex colours as albedo (that is where the baked shading lives), nearest filtering.
static func material(kind: String, tint := Color.WHITE, emissive := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [kind, tint.to_html(), emissive]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture(kind)
	m.albedo_color = tint
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = MaterialLook.SPECULAR_DEFAULT
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	if emissive:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.set_meta("nw_kind", kind)
	_materials[key] = m
	return m


## Which material kind a node name asks for (the builders name every cube).
static func kind_for(node_name: String) -> String:
	var n := node_name.to_lower()
	for pair in [["screen", "screen"], ["led", "green"], ["label", "label"], ["sign", "label"], ["hazard", "hazard"], ["lampshade", "light"],
			["ceilingpanel", "light"], ["clockface", "light"], ["glow", "light"], ["feed", "screen"],
			["desk", "wood"], ["frame", "wood"], ["shelf", "wood"], ["crate", "wood"], ["table", "wood"], ["platform", "wood"],
			["box", "wood"], ["bench", "wood"], ["counter", "metal"], ["fridge", "metal"], ["locker", "metal"], ["slab", "metal"],
			["panel", "metal"], ["breaker", "metal"], ["vent", "metal"], ["pipe", "metal"], ["conduit", "metal"], ["lamp", "metal"],
			["bolt", "metal"], ["handle", "metal"], ["rail", "metal"], ["hatch", "metal"], ["door", "metal"],
			["chair", "fabric"], ["poster", "fabric"], ["curtain", "fabric"], ["mat", "fabric"], ["cushion", "fabric"],
			["floor", "floor"], ["runner", "floor"], ["stripe", "floor"], ["ceiling", "concrete"], ["pillar", "concrete"],
			["monitor", "plastic"], ["keyboard", "plastic"], ["cup", "plastic"], ["bin", "plastic"], ["paper", "paper"],
			["glass", "glass"], ["wall", "wall"], ["trim", "wall"], ["baseboard", "wall"], ["hall", "wall"]]:
		if n.contains(pair[0]):
			return pair[1]
	return "concrete"


static func is_emissive_name(node_name: String) -> bool:
	for part in EMISSIVE_NAMES:
		if node_name.contains(part):
			return true
	return false


## A shaded cube mesh: 24 vertices with per-face UVs (one texture tile per TILE metres) and baked vertex colours.
## `ao` darkens the bottom edge of the side faces (contact shadow), `shade` is the overall level.
static func box_mesh(size: Vector3, ao := 0.72, shade := 1.0, hazard := "") -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size * 0.5
	# face: normal, face brightness, corner positions (counter-clockwise seen from outside), size along u, v
	var faces := [
		[Vector3(0, 1, 0), 1.20, [Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z), Vector3(-h.x, h.y, -h.z)], size.x, size.z, "y"],
		[Vector3(0, -1, 0), 0.50, [Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z)], size.x, size.z, "y"],
		[Vector3(0, 0, 1), 1.00, [Vector3(-h.x, -h.y, h.z), Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z)], size.x, size.y, "z"],
		[Vector3(0, 0, -1), 0.70, [Vector3(h.x, -h.y, -h.z), Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z)], size.x, size.y, "z"],
		[Vector3(1, 0, 0), 0.88, [Vector3(h.x, -h.y, h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z)], size.z, size.y, "x"],
		[Vector3(-1, 0, 0), 0.80, [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z)], size.z, size.y, "x"],
	]
	for f in faces:
		var normal: Vector3 = f[0]
		var level: float = float(f[1]) * shade
		var corners: Array = f[2]
		var striped: bool = hazard.contains(String(f[5]))
		var su: float
		var sv: float
		if striped:
			# tape face: a whole number of stripe periods along u (never fewer than one), the same density along v; no clamping
			su = float(maxi(1, int(round(float(f[3]) / HAZ_PERIOD_M)))) * 0.5
			sv = float(f[4]) / HAZ_TILE
		else:
			su = float(f[3]) / TILE
			sv = float(f[4]) / TILE
		var uvs := [Vector2(0, sv), Vector2(su, sv), Vector2(su, 0), Vector2(0, 0)]
		if not hazard.is_empty() and not striped:
			# an end or thickness face of a tape piece: its own tile, one dark texel of the stripe texture (never a stretched copy of the stripes)
			var dark := Vector2(0.5 / float(TEX), 5.5 / float(TEX))
			uvs = [dark, dark, dark, dark]
		# Godot's front faces are wound clockwise: the corners are listed counter-clockwise seen from outside, so the triangles run 0,2,1 / 0,3,2
		# (the other way round the box was drawn inside out: the near faces were culled and the far faces' insides showed, mirrored)
		var order := [0, 2, 1, 0, 3, 2]
		var target: SurfaceTool = st
		for i in order:
			var p: Vector3 = corners[i]
			var c := level
			# a darker band at the bottom of the side faces and a slight lift at the top edge
			if absf(normal.y) < 0.5:
				c *= lerpf(ao, 1.0, clampf((p.y + h.y) / maxf(0.001, size.y) * 2.2, 0.0, 1.0))
			target.set_normal(normal)
			target.set_uv(uvs[i])
			target.set_color(Color(c, c, c, 1.0))
			target.add_vertex(p)
	return st.commit()


## Add a shaded cube to `parent`. opts: name, kind (default from the name), tint, emissive, solid (a layer-1 collision body),
## ao, shade. Returns the MeshInstance3D.
static func box(parent: Node3D, size: Vector3, pos: Vector3, opts := {}) -> MeshInstance3D:
	var node_name := String(opts.get("name", "Cube"))
	var emissive := bool(opts.get("emissive", false)) or is_emissive_name(node_name)
	var kind := String(opts.get("kind", kind_for(node_name)))
	var mesh := MeshInstance3D.new()
	mesh.name = node_name
	mesh.set_meta("nw_name", node_name)   # Godot renames duplicate siblings, the validator reads this
	var hazard := String(opts.get("hazard", ""))
	mesh.mesh = box_mesh(size, float(opts.get("ao", 0.72)), 1.0 if emissive else float(opts.get("shade", 1.0)), hazard)
	if hazard.is_empty():
		mesh.material_override = material(kind, opts.get("tint", Color.WHITE), emissive)
	else:
		# hazard tape: one material; the tape faces carry the stripes, every other face (ends, thickness) is one dark texel of the same texture
		mesh.set_meta("nw_hazard", hazard)
		mesh.material_override = material("hazard", opts.get("tint", Color.WHITE), false)
	mesh.position = pos
	if opts.has("rotation"):
		mesh.rotation = opts["rotation"]
	parent.add_child(mesh)
	if bool(opts.get("solid", false)):
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		shape.shape = bs
		body.add_child(shape)
		mesh.add_child(body)
	return mesh


## A named prop: a Node3D that groups cubes so the validator can count them (meta nw_prop).
static func prop(parent: Node3D, prop_name: String, pos := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = prop_name
	node.position = pos
	node.set_meta("nw_prop", true)
	parent.add_child(node)
	return node


## Stats of a prop for the validator: cubes, distinct material looks, emissive cubes that are not allowed to be.
static func prop_stats(node: Node) -> Dictionary:
	var cubes := 0
	var looks := {}
	var bad_emissive: Array = []
	var untextured := 0
	for m in node.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		cubes += 1
		var mat := mi.material_override as StandardMaterial3D
		if mat == null or mat.albedo_texture == null:
			untextured += 1
			continue
		looks["%s|%s" % [String(mat.get_meta("nw_kind", "?")), mat.albedo_color.to_html()]] = true
		var own_name := String(mi.get_meta("nw_name", mi.name))
		if mat.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and not is_emissive_name(own_name):
			bad_emissive.append(own_name)
	return {"cubes": cubes, "looks": looks.size(), "untextured": untextured, "bad_emissive": bad_emissive}


static func texture_stats(kind: String) -> Dictionary:
	var img := texture(kind).get_image()
	var colors := {}
	for y in img.get_height():
		for x in img.get_width():
			colors[img.get_pixel(x, y).to_html()] = true
	return {"size": Vector2i(img.get_width(), img.get_height()), "colors": colors.size()}
