extends RefCounted

## The Beach district's daylight-seaside look: the beach is laid in sand, damp sand and bleached
## boardwalk planks, walled in seawall stone, whitewash and turquoise panels under a sky ceiling, lit by steady sun-white
## lanterns, and dressed without the old ivy-and-flower garden. Locks:
##   * FloorSets / the theme data name only the beach kinds, every one painted, footstep-mapped and deterministic;
##   * the painted beach surfaces are warm and bright (so they read at a glance) and carry no purple or magenta pixel;
##   * the beach decor has no canopy, vines, hanging pots, shrubs, trees, crystal chandeliers or petals, and its planter
##     and roof materials are not purple;
##   * the old shared kinds are untouched (gothic / greenhouse / sewer still use their stone, hedge and glass).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- beach_look

const BEACH_FLOORS := ["sand0", "sand1", "wetsand0", "driftwood0", "driftwood1"]
const BEACH_WALLS := ["seawall0", "seawall1", "whitewash0", "whitewash1", "tealpanel0", "tealpanel1"]
const BEACH_CEILINGS := ["skylight0"]
const BEACH_ROOMS := ["cove", "tide_pool", "beach_hut", "boardwalk_room"]
const GONE_FROM_BEACH := ["canopy0", "canopy1", "vine_s", "vine_m", "vine_l", "hang_pot", "shrub", "tree0", "tree1",
	"chandelier_grand", "chandelier", "petal"]
## What a beach surface shows with no lamp near it (linear luma of the painted texels x the vertex-colour glow of
## RefTextures.params), measured against these floors. Without them cove / tide_pool / beach_hut came out near black
## in the windowed captures (only the walls next to a lantern showed).
const DAYLIGHT_MIN_KIND := .06
const DAYLIGHT_MIN_ROOM := .09
const SEEDS := ["BEACH-A", "BEACH-B", "BEACH-C", "BEACH-D"]

var _failures := 0
var metrics := {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(_host: Node) -> int:
	_check_tables()
	_check_painters()
	_check_footsteps()
	_check_shared_kinds_untouched()
	_check_materials()
	_check_decor()
	_check_daylight()
	if _failures == 0:
		print("  beach_look  %s" % [metrics])
	return _failures


func _check_tables() -> void:
	for kind in FloorSets.hall("beach"):
		_expect(BEACH_FLOORS.has(kind), "beach hall floor %s is not a beach kind" % kind)
	for kind in FloorSets.ROOM_DEFAULT["beach"]:
		_expect(BEACH_FLOORS.has(kind), "beach default room floor %s is not a beach kind" % kind)
	_expect(not FloorSets.hall_runner("beach"), "the beach has a carpet runner down its halls")
	for room in BEACH_ROOMS:
		_expect(FloorSets.has_room(room), "%s has no floor entry" % room)
		for kind in FloorSets.room("beach", room):
			_expect(BEACH_FLOORS.has(kind), "%s floor %s is not a beach kind" % [room, kind])
		var walls: Array = RefLook.ROOM_STYLE.get(room, {}).get("wall", RefLook.REGION_STYLE["beach"]["wall"])
		for kind in walls:
			_expect(BEACH_WALLS.has(kind), "%s wall %s is not a beach kind" % [room, kind])
	var style: Dictionary = RefLook.REGION_STYLE["beach"]
	for kind in style["wall"]:
		_expect(BEACH_WALLS.has(kind), "beach wall %s is not a beach kind" % kind)
	_expect(BEACH_CEILINGS.has(style["ceiling"]), "beach ceiling %s is not a beach kind" % style["ceiling"])
	var accent: Array = RefLook.arch_accent("beach")
	_expect(accent[0] == "floor" and BEACH_FLOORS.has(accent[1]), "beach arch trim %s is not a beach kind" % [accent])
	for kind in BEACH_FLOORS:
		_expect(RefTextures.FLOOR_PAINTERS.has(kind), "floor kind %s is not painted" % kind)
	for kind in BEACH_WALLS:
		_expect(RefTextures.WALL_PAINTERS.has(kind), "wall kind %s is not painted" % kind)
	for kind in BEACH_CEILINGS:
		_expect(RefTextures.CEILING_PAINTERS.has(kind), "ceiling kind %s is not painted" % kind)
	# rooms still pick one kind per room, from the beach list
	for room in BEACH_ROOMS:
		var kind := FloorSets.room_kind("beach", room, Vector2i(12, -7))
		_expect(kind == FloorSets.room_kind("beach", room, Vector2i(12, -7)), "%s floor is not deterministic" % room)
	# the lamps: steady warm light, every room lit, and nothing purple in the tint
	var decor: Dictionary = RefDecor.STYLE["beach"]
	_expect(decor.has("tint") and int(decor.get("stutter", -1)) == 0, "beach lamps are not steady and tinted")
	_expect(float(decor["lit_rooms"]) >= .99, "not every beach room is lit")
	if decor.has("tint"):
		var tint: Color = decor["tint"]
		_expect(tint.r > tint.g and tint.g > tint.b, "the beach lamp tint %s is not warm" % tint.to_html(false))


func _painted(group: String, kind: String) -> Image:
	var table: Dictionary = {"floor": RefTextures.FLOOR_PAINTERS, "wall": RefTextures.WALL_PAINTERS, "ceiling": RefTextures.CEILING_PAINTERS}[group]
	var entry: Array = table[kind]
	return Callable(RefTextures, entry[0]).call(entry[1])


## Mean colour and the count of purple/magenta texels of a painted image (rows y0..y1 only when given).
func _stats(img: Image, y0: int = 0, y1: int = -1) -> Dictionary:
	var rows := img.get_height() if y1 < 0 else y1
	var sum := Color(0, 0, 0, 0)
	var n := 0
	var purple := 0
	for y in range(y0, rows):
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			sum += c
			n += 1
			if is_purple(c):
				purple += 1
	var mean := Color(sum.r / n, sum.g / n, sum.b / n)
	return {"mean": mean, "purple": purple, "luma": mean.r * .3 + mean.g * .59 + mean.b * .11}


## Violet through magenta to pink-red: hue .70-.97, enough saturation and brightness to read as a colour.
static func is_purple(c: Color) -> bool:
	return c.s > .18 and c.v > .12 and c.h >= .70 and c.h <= .97


func _check_painters() -> void:
	var means := {}
	for group in [["floor", BEACH_FLOORS], ["wall", BEACH_WALLS], ["ceiling", BEACH_CEILINGS]]:
		for kind in group[1]:
			var img := _painted(group[0], kind)
			var again := _painted(group[0], kind)
			_expect(img.get_data() == again.get_data(), "%s/%s paints differently twice" % [group[0], kind])
			var want_h := RefTextures.WALL_H if group[0] == "wall" else RefTextures.PX
			_expect(img.get_width() == RefTextures.PX and img.get_height() == want_h, "%s/%s is %dx%d" % [group[0], kind, img.get_width(), img.get_height()])
			var stats := _stats(img)
			means["%s/%s" % [group[0], kind]] = stats["mean"].to_html(false)
			_expect(int(stats["purple"]) == 0, "%s/%s has %d purple or magenta texels" % [group[0], kind, stats["purple"]])
			# bright after the draw-time lift, but never clipped to white
			var lifted := float(stats["luma"]) * 1.25
			_expect(lifted > .3 and lifted < .95, "%s/%s mean brightness %.2f after the lift is off" % [group[0], kind, lifted])
	# the sands are warm (red > green > blue), the damp sand a little cooler and darker than the dry
	for kind in ["sand0", "sand1", "wetsand0", "driftwood0", "driftwood1"]:
		var mean: Color = _stats(_painted("floor", kind))["mean"]
		_expect(mean.r > mean.g and mean.g > mean.b, "%s is not warm (mean %s)" % [kind, mean.to_html(false)])
	_expect(_stats(_painted("floor", "wetsand0"))["luma"] < _stats(_painted("floor", "sand0"))["luma"], "damp sand is not darker than dry sand")
	# well above the stone the beach used to be laid in
	var stone: float = _stats(_painted("floor", "stone2"))["luma"]
	for kind in ["sand0", "sand1", "wetsand0", "driftwood0", "driftwood1"]:
		_expect(float(_stats(_painted("floor", kind))["luma"]) > stone * 1.8, "%s is not clearly brighter than the old flagstone" % kind)
	# the sky is blue, the turquoise panels teal (blue and green over red), the seawall pale
	var sky: Color = _stats(_painted("ceiling", "skylight0"))["mean"]
	_expect(sky.b > sky.g and sky.g > sky.r, "the skylight is not sky-blue (%s)" % sky.to_html(false))
	for kind in ["tealpanel0", "tealpanel1"]:
		var teal: Color = _stats(_painted("wall", kind), RefTextures.RAIL_Y)["mean"]
		_expect(teal.g > teal.r and teal.b > teal.r, "%s dado is not teal (%s)" % [kind, teal.to_html(false)])
	var old_wall: float = _stats(_painted("wall", "hedge0"))["luma"]
	for kind in BEACH_WALLS:
		_expect(float(_stats(_painted("wall", kind))["luma"]) > old_wall * 1.8, "%s is not clearly brighter than the old ivy wall" % kind)
	# floors repeat per cell: ripple lines wrap, so the left and right edge columns agree in brightness
	var sand := _painted("floor", "sand0")
	var edge := 0.0
	for y in RefTextures.PX:
		edge += absf(sand.get_pixel(0, y).v - sand.get_pixel(RefTextures.PX - 1, y).v)
	_expect(edge / RefTextures.PX < .12, "sand0 shows a seam where the tile repeats (%.3f)" % (edge / RefTextures.PX))
	metrics["mean_colours"] = means


func _check_footsteps() -> void:
	for kind in BEACH_FLOORS:
		_expect(SurfaceSounds.has_floor(kind), "%s has no footstep surface" % kind)
	for kind in ["sand0", "sand1", "wetsand0"]:
		_expect(SurfaceSounds.for_floor(kind) == "grass", "%s should step soft (grass profile)" % kind)
	for kind in ["driftwood0", "driftwood1"]:
		_expect(SurfaceSounds.for_floor(kind) == "wood", "%s should step on wood" % kind)
	# matte, like every floor
	for kind in BEACH_FLOORS:
		var response := MaterialLook.floor_response(kind)
		_expect(response.x >= MaterialLook.MIN_ROUGHNESS and response.y <= MaterialLook.MAX_METALLIC, "%s is not matte" % kind)


## The shared kinds the beach left behind must still be what the other districts paint.
func _check_shared_kinds_untouched() -> void:
	_expect(FloorSets.hall("gothic") == ["stone0", "stone1"], "gothic halls changed")
	_expect(FloorSets.hall("greenhouse").has("stone2"), "greenhouse halls lost stone2")
	_expect(FloorSets.room("greenhouse", "overgrown_room").has("stone2"), "overgrown_room lost stone2")
	_expect(RefLook.ROOM_STYLE["overgrown_room"]["wall"].has("hedge1"), "overgrown_room lost hedge1")
	_expect(RefLook.REGION_STYLE["greenhouse"]["ceiling"] == "glass", "the greenhouse lost its glass roof")
	_expect(RefLook.REGION_STYLE["gothic"]["wall"].size() > 0 and not RefLook.REGION_STYLE["gothic"]["wall"].has("seawall0"), "gothic walls picked up beach kinds")
	# the old garden walls are still painted (the greenhouse needs them), only no longer used by the beach
	_expect(RefTextures.WALL_PAINTERS.has("hedge0") and RefTextures.WALL_PAINTERS.has("hedge1"), "hedge walls were removed")


func _check_materials() -> void:
	for key in ["bloom_sun", "bloom_pale", "leaf_light", "driftwood", "sandstone", "vault_sky", "amber"]:
		var material := RefDecor.material(key)
		_expect(material is BaseMaterial3D, "decor material %s is missing" % key)
		if material is BaseMaterial3D:
			var colour := (material as BaseMaterial3D).albedo_color
			_expect(not is_purple(colour), "decor material %s is purple (%s)" % [key, colour.to_html(false)])
	# the shared magenta bloom is still the greenhouse's own; the beach must not use it
	_expect(is_purple((RefDecor.material("bloom") as BaseMaterial3D).albedo_color), "the shared bloom material changed (the beach should keep its own)")
	_expect(RefDecor.mesh_for("beach_pendant") is ArrayMesh, "the beach pendant has no mesh")
	for part in [RefDecor.mesh_for("planter"), RefDecor.mesh_for("pedestal"), RefDecor.mesh_for("beach_pendant")]:
		var mesh := part as ArrayMesh
		for surface in mesh.get_surface_count():
			var material := mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null:
				_expect(not is_purple(material.albedo_color), "a beach fixture surface is purple (%s)" % material.albedo_color.to_html(false))
				_expect(material != RefDecor.material("bloom") and material != RefDecor.material("rust") and material != RefDecor.material("stone"),
					"a beach fixture still uses the old garden materials")


func _check_decor() -> void:
	var counts := {"chunks": 0, "glass_rooms": 0, "beach_pendant": 0, "planter": 0, "pedestal": 0, "fern": 0}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-7, 8):
			for dx in range(-7, 8):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				if String(data.get("region", "")) != "beach":
					continue
				counts["chunks"] += 1
				var root := Node3D.new()
				var room_map: Dictionary = StreamedFacilityView3D._room_type_map(data)
				var decor := RefDecor.new(root, data, room_map, RefLook.chunk_heights(data), RefLook.corridor_height("beach", coord))
				var guard := 0
				while not decor.step() and guard < 200:
					guard += 1
				for key in GONE_FROM_BEACH:
					_expect((decor._transforms.get(key, []) as Array).is_empty(),
						"beach chunk %s %s still places %d x %s" % [seed_text, coord, (decor._transforms.get(key, []) as Array).size(), key])
				for key in ["beach_pendant", "planter", "pedestal", "fern"]:
					counts[key] += (decor._transforms.get(key, []) as Array).size()
				for room_value in data.get("rooms", []):
					if RefLook.is_glasshouse("beach", String((room_value as Dictionary).get("room_type", ""))):
						counts["glass_rooms"] += 1
				# the vault is the sky one
				for key in decor._transforms:
					if String(key).begins_with("vault_"):
						_expect(String(key).ends_with("_sky"), "beach vault %s is not the daylight roof" % key)
				# no lamp of this chunk is purple
				for lamp_value in decor.lamps:
					var colour: Color = (lamp_value as Array)[1]
					_expect(not is_purple(colour), "a beach lamp is purple (%s)" % colour.to_html(false))
				root.free()
	_expect(counts["chunks"] >= 3, "only %d beach chunks in the sample" % counts["chunks"])
	_expect(counts["glass_rooms"] >= 2, "only %d beach conservatory rooms in the sample" % counts["glass_rooms"])
	_expect(counts["beach_pendant"] > 0, "no beach pendant lanterns in the sample %s" % [counts])
	metrics["decor"] = counts


## Linear luma of the painted image, averaged over its texels.
func _linear_luma(img: Image) -> float:
	var sum := 0.0
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y).srgb_to_linear()
			sum += c.r * .2126 + c.g * .7152 + c.b * .0722
	return sum / float(img.get_width() * img.get_height())


## Lamp-free brightness of one surface kind, which is what the room shows between lanterns.
func _daylight(group: String, kind: String) -> float:
	return _linear_luma(_painted(group, kind)) * RefTextures.params(group, kind).b


func _check_daylight() -> void:
	# every beach kind glows; no other region's kind does (the sewer vault keeps its own .16)
	for kind in BEACH_FLOORS:
		_expect(RefTextures.params("floor", kind).b > 0.0, "floor %s has no daylight glow" % kind)
	for kind in BEACH_WALLS:
		_expect(RefTextures.params("wall", kind).b > 0.0, "wall %s has no daylight glow" % kind)
	_expect(RefTextures.params("ceiling", "skylight0").b > .5, "the skylight does not glow like a sky")
	for pair in [["floor", "stone0"], ["floor", "stone2"], ["floor", "parquet0"], ["wall", "hedge0"], ["wall", "stone0"], ["ceiling", "glass"]]:
		_expect(RefTextures.params(pair[0], pair[1]).b == 0.0, "%s/%s (not a beach kind) glows" % pair)
	_expect(is_equal_approx(RefTextures.params("ceiling", "vault").b, .16), "the sewer vault glow changed")
	# the roof panes are a bright, blue, unshaded sky
	var roof := RefDecor.material("vault_sky") as StandardMaterial3D
	var sky := roof.albedo_color
	_expect(roof.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED, "the beach roof is not unshaded")
	_expect(sky.b > sky.g and sky.g > sky.r, "the beach roof is not sky-blue (%s)" % sky.to_html(false))
	_expect(sky.b >= .85 and sky.get_luminance() >= .7 and sky.s >= .25, "the beach roof is not a bright sky (%s)" % sky.to_html(false))
	_expect(not is_purple(sky), "the beach roof is purple")
	_expect(RefDecor.material("vault_glass") != roof and not (RefDecor.material("vault_glass") as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
		"the night glass roof of the other regions changed")
	# each beach room type: every floor and wall kind it can draw shows enough with the lamps off, and so does the average
	var report := {}
	for room in BEACH_ROOMS:
		var floors: Array = FloorSets.room("beach", room)
		var walls: Array = RefLook.ROOM_STYLE.get(room, {}).get("wall", RefLook.REGION_STYLE["beach"]["wall"])
		var total := 0.0
		var count := 0
		var least := 9.0
		for kind in floors:
			var v := _daylight("floor", kind)
			least = minf(least, v)
			total += v
			count += 1
		for kind in walls:
			var v := _daylight("wall", kind)
			least = minf(least, v)
			total += v
			count += 1
		_expect(least >= DAYLIGHT_MIN_KIND, "%s has a surface that shows only %.3f with the lamps off (< %.2f)" % [room, least, DAYLIGHT_MIN_KIND])
		_expect(total / count >= DAYLIGHT_MIN_ROOM, "%s shows %.3f on average with the lamps off (< %.2f)" % [room, total / count, DAYLIGHT_MIN_ROOM])
		report[room] = "%.3f/%.3f" % [least, total / count]
	metrics["daylight_min_mean"] = report
	# lanterns: every beach room (not 40 percent of them) carries its lamps, and a glasshouse has several
	var decor_style: Dictionary = RefDecor.STYLE["beach"]
	var lit := {}
	var rooms := {}
	var lamps := {}
	for seed_text in SEEDS:
		var generator := StreamedRouteGenerator.new(seed_text)
		for dz in range(-7, 8):
			for dx in range(-7, 8):
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord):
					continue
				var data := generator.chunk(coord)
				if String(data.get("region", "")) != "beach":
					continue
				var root := Node3D.new()
				var room_map: Dictionary = StreamedFacilityView3D._room_type_map(data)
				var decor := RefDecor.new(root, data, room_map, RefLook.chunk_heights(data), RefLook.corridor_height("beach", coord))
				_expect(decor._lit_percent(decor_style) == 100, "beach lit share is %d percent" % decor._lit_percent(decor_style))
				var guard := 0
				while not decor.step() and guard < 200:
					guard += 1
				for room_value in data.get("rooms", []):
					var room_data: Dictionary = room_value
					var type := String(room_data.get("room_type", ""))
					if not BEACH_ROOMS.has(type) or bool(room_data.get("suite_parent", false)):
						continue
					var rect: Rect2i = room_data.get("rect", Rect2i())
					if mini(rect.size.x, rect.size.y) < 4:
						continue
					rooms[type] = int(rooms.get(type, 0)) + 1
					if decor._room_lit(String(room_data.get("id", "")), decor_style):
						lit[type] = int(lit.get(type, 0)) + 1
					var area := Rect2(Vector2(rect.position) - Vector2.ONE, Vector2(rect.size) + Vector2.ONE * 2.0)
					for lamp_value in decor.lamps:
						var at: Vector3 = (lamp_value as Array)[0] - root.position
						if area.has_point(Vector2(at.x, at.z)):
							lamps[type] = int(lamps.get(type, 0)) + 1
				root.free()
	for room in BEACH_ROOMS:
		_expect(int(rooms.get(room, 0)) > 0, "no %s in the beach sample" % room)
		_expect(int(lit.get(room, 0)) == int(rooms.get(room, 0)), "%s: %d of %d rooms carry lamps" % [room, lit.get(room, 0), rooms.get(room, 0)])
		_expect(int(lamps.get(room, 0)) >= 4 * int(rooms.get(room, 0)), "%s: only %d lamps over %d rooms" % [room, lamps.get(room, 0), rooms.get(room, 0)])
	metrics["lit_rooms"] = {"rooms": rooms, "lit": lit, "lamps": lamps}
