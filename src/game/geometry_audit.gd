class_name GeometryAudit
extends RefCounted

## Geometry overlap audit (docs/GEOMETRY_AUDIT.md). Collects every placed solid (props, walls, doors, building masses,
## street furniture) of the generated content as an oriented footprint plus a height span and reports
##   solid_overlap  solid-into-solid interpenetration (prop in wall / prop / hall / door zone, masses, furniture)
##   floating       a piece with no support (surface prop with no parent, wall mount with no wall, prop over a void)
##   sliver         thin gaps and orphan stub masses between buildings
##   poke           a piece reaching through the ceiling
## Intentional overlaps are NOT skipped wholesale: each one is an explicit rule in pair_allowance() / the per-category
## tolerances below. Findings are plain dictionaries {game, cat, rule, seed, at, detail, depth}; rank() orders them.
##
## Everything works on the generator data (no nodes), so host and guests agree and the sweep is fast. The Night Watch
## offices are node trees and are audited per cube by audit_office().

const TOL_DEFAULT := 0.10              ## footprint penetration (m) below which two solids merely touch
## Diagnostics: strict mode drops the allow-list and uses a 2 cm tolerance to show every interpenetration there is.
static var strict := false
const SEAT_TOL := 0.55         ## a chair/stool may tuck under a table, desk or counter by this much
## Largest share of a room's open floor its solid props may cover (the rest is the walking margin).
const CAPACITY_LIMIT := 0.45
const CEILING := 4.0
const CEILING_SLACK := 0.15
const GAME_LAST_ROUTE := "last_route"
const GAME_CITY := "city"
const GAME_NIGHT_WATCH := "night_watch"

## Category weights for the ranking (a piece clipping through a wall is worse than a tolerance-level touch).
const WEIGHTS := {"prop_in_wall": 5, "prop_in_prop": 3, "prop_in_hall": 4, "door_zone": 5, "door_frame": 4,
	"building_overlap": 8, "orphan_mass": 7, "facade_hole": 9, "sliver": 4, "decor_in_wall": 5, "decor_overlap": 2,
	"junction_floor": 6, "hall_nub": 4, "room_capacity": 3, "floating": 6, "slab_coplanar": 3, "poke_ceiling": 5, "prop_over_void": 6, "cube_overlap": 3, "cube_floating": 4}

const SEAT_WORDS := ["Chair", "Stool", "Bench", "Seat", "Armchair", "Couch", "Sofa"]
const TABLE_WORDS := ["Table", "Desk", "Counter", "Workstation", "Bar", "Bookcase", "Shelf", "Piano"]


# ------------------------------------------------------------------ geometry helpers

## Smallest axis penetration (m) of two oriented rectangles in the plane; 0 when they do not overlap.
static func obb_depth(ca: Vector2, ha: Vector2, ya: float, cb: Vector2, hb: Vector2, yb: float) -> float:
	var axes := [_axis_x(ya), _axis_y(ya), _axis_x(yb), _axis_y(yb)]
	var d := cb - ca
	var best := INF
	for n_value in axes:
		var n: Vector2 = n_value
		var ra := ha.x * absf(n.dot(_axis_x(ya))) + ha.y * absf(n.dot(_axis_y(ya)))
		var rb := hb.x * absf(n.dot(_axis_x(yb))) + hb.y * absf(n.dot(_axis_y(yb)))
		var depth := ra + rb - absf(d.dot(n))
		if depth <= 0.0:
			return 0.0
		best = minf(best, depth)
	return best


## Translation that moves rectangle A just clear of rectangle B along the axis of least penetration (zero when apart).
static func obb_push(ca: Vector2, ha: Vector2, ya: float, cb: Vector2, hb: Vector2, yb: float) -> Vector2:
	var axes := [_axis_x(ya), _axis_y(ya), _axis_x(yb), _axis_y(yb)]
	var d := ca - cb
	var best := INF
	var push := Vector2.ZERO
	for n_value in axes:
		var n: Vector2 = n_value
		var ra := ha.x * absf(n.dot(_axis_x(ya))) + ha.y * absf(n.dot(_axis_y(ya)))
		var rb := hb.x * absf(n.dot(_axis_x(yb))) + hb.y * absf(n.dot(_axis_y(yb)))
		var depth := ra + rb - absf(d.dot(n))
		if depth <= 0.0:
			return Vector2.ZERO
		if depth < best:
			best = depth
			push = n * depth * (1.0 if d.dot(n) >= 0.0 else -1.0)
	return push


static func _axis_x(yaw: float) -> Vector2:
	return Vector2(cos(yaw), -sin(yaw))


static func _axis_y(yaw: float) -> Vector2:
	return Vector2(sin(yaw), cos(yaw))


static func _word_in(type: String, words: Array) -> bool:
	for w in words:
		if type.contains(String(w)):
			return true
	return false


## The explicit allow-list. Returns the penetration (m) the pair may have before it counts, 0 = no allowance beyond tol().
static func pair_allowance(a_type: String, b_type: String) -> float:
	if strict:
		return 0.0
	var seat_a := _word_in(a_type, SEAT_WORDS)
	var seat_b := _word_in(b_type, SEAT_WORDS)
	# a chair tucked under a table / desk / counter (or two seats side by side in a row)
	if (seat_a and _word_in(b_type, TABLE_WORDS)) or (seat_b and _word_in(a_type, TABLE_WORDS)):
		return SEAT_TOL
	if seat_a and seat_b:
		return 0.2
	return 0.0


static func tol() -> float:
	return 0.02 if strict else TOL_DEFAULT


static func finding(game: String, cat: String, rule: String, seed_text: String, at: String, detail: String, depth: float = 0.0) -> Dictionary:
	return {"game": game, "cat": cat, "rule": rule, "seed": seed_text, "at": at, "detail": detail, "depth": depth}


## Ranked: weight x depth-ish severity first. Same order every run.
static func rank(findings: Array) -> Array:
	var out := findings.duplicate()
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var wa := float(WEIGHTS.get(String(a["rule"]), 1)) * (1.0 + float(a.get("depth", 0.0)))
		var wb := float(WEIGHTS.get(String(b["rule"]), 1)) * (1.0 + float(b.get("depth", 0.0)))
		if not is_equal_approx(wa, wb):
			return wa > wb
		return String(a["at"]) < String(b["at"]))
	return out


## {game: {cat/rule: count}}
static func counts(findings: Array) -> Dictionary:
	var out := {}
	for f_value in findings:
		var f: Dictionary = f_value
		var g: Dictionary = out.get(f["game"], {})
		g[f["rule"]] = int(g.get(f["rule"], 0)) + 1
		out[f["game"]] = g
	return out


# ------------------------------------------------------------------ Last Route

## One generated chunk. `data` is StreamedRouteGenerator.chunk().
static func audit_chunk(data: Dictionary, seed_text: String, biome: String, out: Array) -> void:
	var coord: Vector3i = data.get("coord", Vector3i.ZERO)
	var where_prefix := "%s chunk %s" % [biome, coord]
	var grid: Array = data.get("grid", [])
	var size := grid.size()
	var props: Array = []
	var doors: Array = []
	for prop_value in data.get("region_props", []):
		var prop: Dictionary = prop_value
		if bool(prop.get("room_door", false)):
			doors.append(prop)
		else:
			props.append(prop)
	var rooms: Array = data.get("rooms", [])
	var room_rects: Array = []
	for room in rooms:
		room_rects.append(room.get("rect", Rect2i()))
	var voids := {}
	for key in ["floor_voids", "structural_voids"]:
		for cell in data.get(key, []):
			voids[cell] = true

	var solids: Array = []
	for prop in props:
		var type := String(prop.get("type", ""))
		var cell: Vector2i = prop.get("cell", Vector2i.ZERO)
		var at := "%s %s %s cell %s" % [where_prefix, type, str(prop.get("id", "")), cell]
		var solid := bool(prop.get("solid", true))
		var wall_mounted := bool(prop.get("wall_mounted", false))
		var mount_y := float(prop.get("mount_y", 0.0))
		# floating: a surface prop needs a legal parent, a wall mount needs a wall behind it, nothing hangs over a void
		if RoomCatalog.is_surface_prop(type) and mount_y > 0.0 and not wall_mounted:
			var seated := false
			for other in props:
				if RoomCatalog.surface_parent_covers(other, prop):
					seated = true
					break
			if not seated:
				out.append(finding(GAME_LAST_ROUTE, "floating", "floating", seed_text, at, "surface prop with no legal parent in its cell"))
		if wall_mounted:
			var back: Vector2i = prop.get("backing_wall", Vector2i.ZERO)
			var wall_cell := cell + back
			if back != Vector2i.ZERO and is_open_cell(grid, size, wall_cell):
				out.append(finding(GAME_LAST_ROUTE, "floating", "floating", seed_text, at, "wall-mounted but the backing cell %s is open" % wall_cell))
		if voids.has(cell) and not PropModelCatalog.is_ceiling_mounted(type):
			out.append(finding(GAME_LAST_ROUTE, "floating", "prop_over_void", seed_text, at, "placed on a floor/structural void cell"))
		if not solid:
			continue
		var collider: Vector3 = prop.get("collider_size", prop.get("blocker_size", Vector3.ONE))
		if collider.y > CEILING - CEILING_SLACK and not PropModelCatalog.is_ceiling_mounted(type) \
				and not RoomCatalog.is_walkable_structure(type):
			out.append(finding(GAME_LAST_ROUTE, "poke", "poke_ceiling", seed_text, at,
				"collider %.2f m tall against a %.1f m ceiling" % [collider.y, CEILING], collider.y - CEILING))
		var offset := Vector2(prop.get("mount_offset", Vector2.ZERO)) + Vector2(prop.get("placement_offset", Vector2.ZERO))
		var centre := Vector2(cell) + Vector2(.5, .5) + offset
		var half := Vector2(collider.x, collider.z) * .5
		var yaw := float(prop.get("yaw", 0.0))
		var base_centre := centre
		var shapes := PropColliderBoxes.boxes(type, collider, PropColliderBoxes.variant_of(prop))
		if shapes.size() == 1:
			centre = PropColliderBoxes.world_centre(centre, shapes[0]["c"], yaw)
		for box in shapes:
			solids.append({"id": String(prop.get("id", "")), "type": type, "centre": PropColliderBoxes.world_centre(base_centre, box["c"], yaw),
				"half": box["h"], "yaw": yaw, "y0": 0.0, "y1": collider.y, "at": at, "wall_mounted": wall_mounted})
		# prop into wall: every closed cell around the box
		if wall_mounted:
			continue
		var reach := int(ceil(half.length())) + 1
		var cx := floori(centre.x)
		var cz := floori(centre.y)
		var worst := 0.0
		var worst_cell := Vector2i.ZERO
		for dz in range(-reach, reach + 1):
			for dx in range(-reach, reach + 1):
				var wc := Vector2i(cx + dx, cz + dz)
				if is_open_cell(grid, size, wc):
					continue
				var depth := obb_depth(centre, half, yaw, Vector2(wc) + Vector2(.5, .5), Vector2(.5, .5), 0.0)
				if depth > worst:
					worst = depth
					worst_cell = wc
		if worst > tol():
			out.append(finding(GAME_LAST_ROUTE, "solid_overlap", "prop_in_wall", seed_text, at,
				"penetrates wall cell %s by %.2f m" % [worst_cell, worst], worst))

	_audit_junctions(data, seed_text, biome, where_prefix, room_rects, out)

	# room capacity: the solid footprints of a room's props against its open floor; above the limit the room is squeezed
	for room in rooms:
		var rect: Rect2i = room.get("rect", Rect2i())
		var area := 0
		for z in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if is_open_cell(grid, size, Vector2i(x, z)):
					area += 1
		var used := 0.0
		for s_value in solids:
			var sp: Dictionary = s_value
			if not bool(sp["wall_mounted"]) and rect.has_point(Vector2i(floori((sp["centre"] as Vector2).x), floori((sp["centre"] as Vector2).y))):
				used += (sp["half"] as Vector2).x * (sp["half"] as Vector2).y * 4.0
		if area > 0 and used / float(area) > CAPACITY_LIMIT:
			out.append(finding(GAME_LAST_ROUTE, "capacity", "room_capacity", seed_text,
				"%s room %s (%s %s)" % [where_prefix, room.get("id", ""), room.get("room_type", ""), rect.size],
				"props fill %.0f%% of %d open m2 (limit %.0f%%)" % [used / float(area) * 100.0, area, CAPACITY_LIMIT * 100.0], used / float(area)))

	# prop vs prop
	for i in solids.size():
		var a: Dictionary = solids[i]
		if bool(a["wall_mounted"]):
			continue
		for j in range(i + 1, solids.size()):
			var b: Dictionary = solids[j]
			if bool(b["wall_mounted"]):
				continue
			if (a["centre"] as Vector2).distance_to(b["centre"]) > (a["half"] as Vector2).length() + (b["half"] as Vector2).length():
				continue
			var depth := obb_depth(a["centre"], a["half"], float(a["yaw"]), b["centre"], b["half"], float(b["yaw"]))
			var allowance := tol() + pair_allowance(String(a["type"]), String(b["type"]))
			if depth > allowance:
				out.append(finding(GAME_LAST_ROUTE, "solid_overlap", "prop_in_prop", seed_text, String(a["at"]),
					"%s (%s) interpenetrates %s by %.2f m" % [a["type"], a["id"], b["type"], depth], depth))

	# solid prop in a hall (open cell outside every room rectangle = circulation)
	for s in solids:
		if bool(s["wall_mounted"]):
			continue
		var centre: Vector2 = s["centre"]
		var half: Vector2 = s["half"]
		var reach := int(ceil(half.length())) + 1
		var hit := false
		for dz in range(-reach, reach + 1):
			if hit:
				break
			for dx in range(-reach, reach + 1):
				var hc := Vector2i(floori(centre.x) + dx, floori(centre.y) + dz)
				if not is_open_cell(grid, size, hc) or _in_any_room(room_rects, hc):
					continue
				var depth := obb_depth(centre, half, float(s["yaw"]), Vector2(hc) + Vector2(.5, .5), Vector2(.5, .5), 0.0)
				if depth > tol():
					out.append(finding(GAME_LAST_ROUTE, "solid_overlap", "prop_in_hall", seed_text, String(s["at"]),
						"%s reaches %.2f m into hall cell %s" % [s["type"], depth, hc], depth))
					hit = true
					break

	# doors: keep-clear zones and the frame (wall shoulders beside the opening)
	var world := CollisionWorld.from_chunk(data)
	for v in world.zone_violations():
		out.append(finding(GAME_LAST_ROUTE, "solid_overlap", "door_zone", seed_text, "%s door %s" % [where_prefix, v["door"]],
			"%s blocks the door keep-clear zone" % v["prop"]))
	for door in doors:
		var cell: Vector2i = door.get("cell", Vector2i.ZERO)
		var inward: Vector2i = door.get("inward", Vector2i(0, -1))
		var across: Vector2i = door.get("across", Vector2i(1, 0))
		var span := int(door.get("door_span", 1))
		var at := "%s %s %s cell %s" % [where_prefix, door.get("type", ""), door.get("id", ""), cell]
		for cc in door.get("doorway_cells", []):
			if not is_open_cell(grid, size, cc):
				out.append(finding(GAME_LAST_ROUTE, "solid_overlap", "door_frame", seed_text, at, "doorway cell %s is closed: the leaf sits inside a wall" % cc))
		# the cells either side of the doorway along the wall must be wall, or the frame stands in the open
		var cells: Array = door.get("doorway_cells", [])
		if cells.is_empty():
			continue
		var lo: Vector2i = cells[0]
		var hi: Vector2i = cells[0]
		for cc in cells:
			if (cc as Vector2i).x * across.x + (cc as Vector2i).y * across.y < lo.x * across.x + lo.y * across.y:
				lo = cc
			if (cc as Vector2i).x * across.x + (cc as Vector2i).y * across.y > hi.x * across.x + hi.y * across.y:
				hi = cc
		for shoulder in [lo - across, hi + across]:
			if is_open_cell(grid, size, shoulder) and shoulder != cell:
				out.append(finding(GAME_LAST_ROUTE, "solid_overlap", "door_frame", seed_text, at,
					"span %d: the cell %s beside the frame is open, the jamb stands in the room" % [span, shoulder]))
				break


## Hall junctions (T, cross, corner) of one chunk: a runner-carpet biome gives every junction cell the hall's own carpet (no
## stray stone tile patch), and no single wall cell juts into the circulation.
static func _audit_junctions(data: Dictionary, seed_text: String, biome: String, where_prefix: String, room_rects: Array, out: Array) -> void:
	var grid: Array = data.get("grid", [])
	var size := grid.size()
	var runner: bool = bool((RefLook.REGION_STYLE.get(biome, {}) as Dictionary).get("runner", false))
	for z in range(1, size - 1):
		for x in range(1, size - 1):
			var cell := Vector2i(x, z)
			if _in_any_room(room_rects, cell):
				continue
			if not is_open_cell(grid, size, cell):
				var open_n := 0
				var room_n := false
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = cell + (step as Vector2i)
					if is_open_cell(grid, size, n):
						open_n += 1
						if _in_any_room(room_rects, n):
							room_n = true
				if open_n >= 3 and not room_n:
					out.append(finding(GAME_LAST_ROUTE, "junction", "hall_nub", seed_text, "%s cell %s" % [where_prefix, cell],
						"a single wall cell juts into the hall on %d sides" % open_n))
				continue
			var run_x := _run_len(grid, size, cell, Vector2i(1, 0))
			var run_z := _run_len(grid, size, cell, Vector2i(0, 1))
			if run_x < 3 or run_z < 3:
				continue
			# the floor: a carpet biome must lay the hall's runner through the junction (a cell crossed by two halls)
			if runner and (run_x != 3 or run_z != 3) and _touches_exact_hall(grid, size, cell):
				if String(StreamedFacilityView3D._runner_kind(grid, x, z)) == "":
					out.append(finding(GAME_LAST_ROUTE, "junction", "junction_floor", seed_text, "%s cell %s" % [where_prefix, cell],
						"junction cell falls back to the stone corridor tiles instead of the hall carpet"))


static func _run_len(grid: Array, size: int, cell: Vector2i, dir: Vector2i) -> int:
	var run := 1
	for sign in [-1, 1]:
		var k := 1
		while k < 8 and is_open_cell(grid, size, cell + dir * k * int(sign)):
			run += 1
			k += 1
	return run


## True when an open cell within two steps along an axis lies in a run of exactly one hall width across the other axis.
static func _touches_exact_hall(grid: Array, size: int, cell: Vector2i) -> bool:
	for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		for reach in [1, 2]:
			var n: Vector2i = cell + (step as Vector2i) * int(reach)
			if not is_open_cell(grid, size, n):
				break
			if _run_len(grid, size, n, Vector2i(1, 0)) == 3 or _run_len(grid, size, n, Vector2i(0, 1)) == 3:
				return true
	return false


static func is_open_cell(grid: Array, size: int, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size and cell.y < size and int(grid[cell.y][cell.x]) == 0


static func _in_any_room(rects: Array, cell: Vector2i) -> bool:
	for r in rects:
		if (r as Rect2i).has_point(cell):
			return true
	return false


# ------------------------------------------------------------------ City

static func audit_city(layout: CityLayout, seed_text: String, out: Array) -> void:
	var buildings := layout.buildings
	var g := GAME_CITY
	# building masses overlapping each other
	for i in buildings.size():
		var ra: Rect2i = buildings[i]["rect"]
		for j in range(i + 1, buildings.size()):
			var rb: Rect2i = buildings[j]["rect"]
			if ra.intersects(rb):
				var clip := ra.intersection(rb)
				out.append(finding(g, "solid_overlap", "building_overlap", seed_text,
					"%s %s overlaps %s %s" % [buildings[i]["id"], ra, buildings[j]["id"], rb],
					"%d cells shared at %s" % [clip.size.x * clip.size.y, clip], float(mini(clip.size.x, clip.size.y))))
	# orphan masses: solid WALL cells with no building (drawn as a default 6 m brick stub next to 12-28 m towers)
	var seen := {}
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			var cell := Vector2i(gx, gz)
			if layout.kind_at(gx, gz) != CityLayout.WALL or layout.building_index[CityLayout.index_of(gx, gz)] != 0 or seen.has(cell):
				continue
			var cluster := [cell]
			seen[cell] = true
			var cursor := 0
			while cursor < cluster.size():
				var c: Vector2i = cluster[cursor]
				cursor += 1
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = c + (step as Vector2i)
					if not seen.has(n) and CityLayout.in_bounds(n.x, n.y) and layout.kind_at(n.x, n.y) == CityLayout.WALL \
							and layout.building_index[CityLayout.index_of(n.x, n.y)] == 0:
						seen[n] = true
						cluster.append(n)
			var tallest := 0.0
			for c_value in cluster:
				var c: Vector2i = c_value
				for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var nb := layout.building_at(c.x + (step as Vector2i).x, c.y + (step as Vector2i).y)
					tallest = maxf(tallest, float(nb.get("height", 0.0)))
			out.append(finding(g, "solid_overlap", "orphan_mass", seed_text, "city cell %s (%d cells)" % [cell, cluster.size()],
				"stub mass drawn at the default 6 m beside buildings up to %.1f m" % tallest, maxf(0.0, tallest - 6.0) / 6.0))
	# slivers: a 1-2 cell open strip squeezed between two different building masses
	for gz in CityLayout.HEIGHT:
		for gx in CityLayout.WIDTH:
			_sliver_run(layout, Vector2i(gx, gz), Vector2i(1, 0), seed_text, out)
			_sliver_run(layout, Vector2i(gx, gz), Vector2i(0, 1), seed_text, out)
	# street furniture vs facades and vs each other: each piece is a few vertical parts (a tree is a thin trunk under a wide
	# canopy), so a bench under a canopy is fine and a canopy through a facade is not
	var items: Array = []
	for cell_value in layout.decor.keys():
		var cell: Vector2i = cell_value
		var entry: Dictionary = layout.decor[cell]
		var type := String(entry["type"])
		var yaw := float(entry["yaw"])
		var centre := Vector2(cell) + Vector2(.5, .5)
		var worst := 0.0
		var worst_cell := Vector2i.ZERO
		for part_value in CityLayout.decor_parts(type, yaw):
			var part: Dictionary = part_value
			var half: Vector2 = part["half"]
			items.append({"type": type, "cell": cell, "centre": centre, "half": half, "y0": part["y0"], "y1": part["y1"]})
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					var wc := cell + Vector2i(dx, dz)
					if layout.kind_at(wc.x, wc.y) not in [CityLayout.WALL, CityLayout.KIOSK_WALL, CityLayout.GATE, CityLayout.RIM]:
						continue
					var depth := obb_depth(centre, half, 0.0, Vector2(wc) + Vector2(.5, .5), Vector2(.5, .5), 0.0)
					if depth > worst:
						worst = depth
						worst_cell = wc
		if worst > tol():
			out.append(finding(g, "solid_overlap", "decor_in_wall", seed_text, "city %s at %s" % [type, cell],
				"visible %s reaches %.2f m into wall cell %s" % [type, worst, worst_cell], worst))
	for i in items.size():
		var a: Dictionary = items[i]
		for j in range(i + 1, items.size()):
			var b: Dictionary = items[j]
			if a["cell"] == b["cell"] or (a["centre"] as Vector2).distance_to(b["centre"]) > 3.0:
				continue
			if float(a["y1"]) <= float(b["y0"]) or float(b["y1"]) <= float(a["y0"]):
				continue
			var depth := obb_depth(a["centre"], a["half"], 0.0, b["centre"], b["half"], 0.0)
			# same-kind canopies (tree/tree, cypress/cypress) may blend by a hand's width: an explicit allowance
			var allowance := tol() + (0.3 if a["type"] == b["type"] and a["type"] in ["tree", "cypress"] else 0.0)
			if depth > allowance:
				out.append(finding(g, "solid_overlap", "decor_overlap", seed_text, "city %s at %s" % [a["type"], a["cell"]],
					"overlaps %s at %s by %.2f m" % [b["type"], b["cell"], depth], depth))
	# facade faces: every edge of a building wall that is exposed (not against an equally tall mass or an interior) must be drawn,
	# otherwise the tower is open there and its inside shows through. GEO_LEGACY=1 models the old OUTDOOR-only drawing.
	var legacy := OS.get_environment("GEO_LEGACY") != ""
	var holes := 0
	var first_hole := ""
	for building in buildings:
		var rect: Rect2i = building["rect"]
		var top := int(float(building["height"]))
		for gz in range(rect.position.y, rect.end.y):
			for gx in range(rect.position.x, rect.end.x):
				if layout.kind_at(gx, gz) != CityLayout.WALL or layout.building_index[CityLayout.index_of(gx, gz)] != layout.buildings.find(building) + 1:
					continue
				for step in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
					var dir: Vector2i = step
					var nk := layout.kind_at(gx + dir.x, gz + dir.y)
					if [CityLayout.FLOOR, CityLayout.DOOR, CityLayout.KIOSK_FLOOR].has(nk):
						continue
					var covered := 0
					if nk == CityLayout.WALL:
						covered = int(float(layout.building_at(gx + dir.x, gz + dir.y).get("height", 6.0)))
					elif nk == CityLayout.KIOSK_WALL:
						covered = 4
					elif nk == CityLayout.GATE:
						covered = 7
					elif nk == CityLayout.RIM:
						covered = 11
					if covered >= top:
						continue
					var drawn: bool
					if legacy:
						drawn = CityLayout.OUTDOOR_KINDS.has(nk)
					else:
						var span: Vector2i = CityFacilityView3D.facade_span(layout, gx, gz, dir, top)
						drawn = span.y > span.x and span.x <= covered
					if not drawn:
						holes += 1
						if first_hole == "":
							first_hole = "%s cell (%d,%d) side %s against %s" % [building["id"], gx, gz, dir, CityLayout.KIND_NAMES[nk]]
	if holes > 0:
		out.append(finding(g, "solid_overlap", "facade_hole", seed_text, "city " + first_hole,
			"%d facade edges are left undrawn (the tower is open there and shows its inside)" % holes, float(holes)))
	# interior props
	for building in buildings:
		_audit_city_building(layout, building, seed_text, out)


static func _sliver_run(layout: CityLayout, start: Vector2i, step: Vector2i, seed_text: String, out: Array) -> void:
	# start is a building wall; look across 1 or 2 non-solid cells to a different building wall
	var a := layout.building_index[CityLayout.index_of(start.x, start.y)] if CityLayout.in_bounds(start.x, start.y) else 0
	if a == 0 or layout.kind_at(start.x, start.y) != CityLayout.WALL:
		return
	for gap in [1, 2]:
		var far: Vector2i = start + step * (int(gap) + 1)
		if not CityLayout.in_bounds(far.x, far.y):
			return
		var b := layout.building_index[CityLayout.index_of(far.x, far.y)]
		if b == 0 or b == a or layout.kind_at(far.x, far.y) != CityLayout.WALL:
			continue
		var all_open := true
		for k in range(1, int(gap) + 1):
			var m: Vector2i = start + step * k
			if layout.kind_at(m.x, m.y) in [CityLayout.WALL, CityLayout.DOOR, CityLayout.FLOOR]:
				all_open = false
		if all_open:
			out.append(finding(GAME_CITY, "sliver", "sliver", seed_text, "city cell %s -> %s" % [start, far],
				"%d-cell gap between %s and %s" % [gap, layout.buildings[a - 1]["id"], layout.buildings[b - 1]["id"]], float(gap)))
		return


static func _audit_city_building(layout: CityLayout, building: Dictionary, seed_text: String, out: Array) -> void:
	var props := layout.building_props(building)
	var rects: Array = []
	for prop in props:
		var type := String(prop["type"])
		var size: Vector3 = prop["size"]
		var cell: Vector2i = prop["cell"]
		var centre := Vector2(cell) + Vector2(.5, .5)
		var half := Vector2(size.x, size.z) * .5
		var yaw := float(prop["yaw"])
		var at := "city %s %s %s cell %s" % [building["id"], type, prop["id"], cell]
		rects.append({"type": type, "centre": centre, "half": half, "yaw": yaw, "at": at, "id": prop["id"]})
		if size.y > CEILING - CEILING_SLACK:
			out.append(finding(GAME_CITY, "poke", "poke_ceiling", seed_text, at, "%.2f m tall" % size.y, size.y - CEILING))
		var worst := 0.0
		var worst_cell := Vector2i.ZERO
		for dz in range(-2, 3):
			for dx in range(-2, 3):
				var wc := cell + Vector2i(dx, dz)
				if layout.kind_at(wc.x, wc.y) in [CityLayout.FLOOR]:
					continue
				var depth := obb_depth(centre, half, yaw, Vector2(wc) + Vector2(.5, .5), Vector2(.5, .5), 0.0)
				if depth > worst:
					worst = depth
					worst_cell = wc
		if worst > tol():
			out.append(finding(GAME_CITY, "solid_overlap", "prop_in_wall", seed_text, at,
				"penetrates %s cell %s by %.2f m" % [CityLayout.KIND_NAMES[layout.kind_at(worst_cell.x, worst_cell.y)], worst_cell, worst], worst))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var a: Dictionary = rects[i]
			var b: Dictionary = rects[j]
			if (a["centre"] as Vector2).distance_to(b["centre"]) > 3.0:
				continue
			var depth := obb_depth(a["centre"], a["half"], float(a["yaw"]), b["centre"], b["half"], float(b["yaw"]))
			if depth > tol() + pair_allowance(String(a["type"]), String(b["type"])):
				out.append(finding(GAME_CITY, "solid_overlap", "prop_in_prop", seed_text, String(a["at"]),
					"%s interpenetrates %s by %.2f m" % [a["type"], b["type"], depth], depth))


# ------------------------------------------------------------------ Night Watch offices

const NW_STRUCTURE_WORDS := ["wall", "floor", "ceiling", "room", "shell", "frame_outer", "carpet", "rug"]
const NW_HANGING_WORDS := ["light", "lamp", "sign", "poster", "clock", "camera", "vent", "window", "pipe", "cable", "wire",
	"hang", "banner", "map", "board", "frame", "fan", "sconce", "shelf", "rail", "duct", "panel", "fixture", "monitor",
	"ceiling", "grille", "screen", "tv", "speaker", "mic", "curtain", "blind", "door", "picture", "calendar", "note", "tape", "bulb", "glow"]

## Cube-level overlap of different prop groups in one built office, in world space. `props` is NightWatchOfficeBase.props.
static func audit_office(label: String, props: Dictionary, out: Array) -> void:
	var cubes: Array = []
	for prop_name in props:
		var node: Node3D = props[prop_name]
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			if mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var box := mi.global_transform * mi.get_aabb()
			cubes.append({"group": String(prop_name), "aabb": box, "name": String(mi.get_meta("nw_name", mi.name))})
	for i in cubes.size():
		var a: Dictionary = cubes[i]
		for j in range(i + 1, cubes.size()):
			var b: Dictionary = cubes[j]
			if a["group"] == b["group"]:
				continue
			var ba: AABB = a["aabb"]
			var bb: AABB = b["aabb"]
			if not ba.intersects(bb):
				continue
			var clip := ba.intersection(bb)
			var depth := minf(clip.size.x, minf(clip.size.y, clip.size.z))
			if depth <= 0.05:
				continue
			# explicit allowances: a thing resting on another (the thin overlap is vertical), structure touching props
			var a_struct := _word_in(String(a["group"]).to_lower(), NW_STRUCTURE_WORDS)
			var b_struct := _word_in(String(b["group"]).to_lower(), NW_STRUCTURE_WORDS)
			if clip.size.y <= 0.08 and clip.size.y <= minf(clip.size.x, clip.size.z):
				continue
			if (a_struct or b_struct) and depth <= 0.12:
				continue
			var ga := String(a["group"]).to_lower()
			var gb := String(b["group"]).to_lower()
			# allowance 1: a door/vent/window frame set into the aperture of a wall (frame post inside the wall's thickness)
			if (ga.begins_with("wall") and gb.contains("frame")) or (gb.begins_with("wall") and ga.contains("frame")):
				continue
			# allowance 2: wall-to-wall joints of adjoining rooms (a corner column of wall thickness)
			if ga != "" and clip.size.x <= 0.21 and clip.size.z <= 0.21 and clip.size.y > 1.0:
				continue
			# allowance 4: a cable end plugged into the thing it hangs from (a few centimetres)
			var cable := String(a["name"]).to_lower().contains("cable") or String(b["name"]).to_lower().contains("cable")
			if cable and depth <= 0.06:
				continue
			# a slab laid over another slab at the same height is coplanar on top and bottom: a z-fight, not a joint
			var coplanar := clip.size.y >= minf(ba.size.y, bb.size.y) - 0.01 and maxf(ba.size.y, bb.size.y) <= 0.25
			# allowance 3: a tall piece (door leaf, post) ending inside the thickness of a floor/ceiling slab is buried there
			var thin_a := ba.size.y <= 0.25 and bb.size.y > 0.5
			var thin_b := bb.size.y <= 0.25 and ba.size.y > 0.5
			if (thin_a or thin_b) and clip.size.y >= (ba.size.y if thin_a else bb.size.y) - 0.01 and clip.size.y <= 0.25:
				continue
			var rule := "slab_coplanar" if coplanar else "cube_overlap"
			out.append(finding(GAME_NIGHT_WATCH, "solid_overlap", rule, label,
				"%s: %s/%s x %s/%s" % [label, a["group"], a["name"], b["group"], b["name"]],
				"%s overlap %s at %s" % ["cubes", str(clip.size), str(clip.position)], depth))
	# floating groups: bottom above the floor with nothing under it
	for prop_name in props:
		var node: Node3D = props[prop_name]
		var low := INF
		var box := AABB()
		var first := true
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var mi := mesh as MeshInstance3D
			if mi.mesh == null:
				continue
			var ab := mi.global_transform * mi.get_aabb()
			box = ab if first else box.merge(ab)
			first = false
		if first:
			continue
		low = box.position.y
		var lname := String(prop_name).to_lower()
		if low < 0.12 or _word_in(lname, NW_HANGING_WORDS):
			continue
		var supported := false
		var reach := box.grow(0.06)
		for other_name in props:
			if other_name == prop_name:
				continue
			for mesh in (props[other_name] as Node3D).find_children("*", "MeshInstance3D", true, false):
				var mi := mesh as MeshInstance3D
				if mi.mesh == null:
					continue
				# attached = any other group's cube touches this one within 6 cm in every axis (resting on it, or mounted on a wall)
				if reach.intersects(mi.global_transform * mi.get_aabb()):
					supported = true
					break
			if supported:
				break
		if not supported:
			out.append(finding(GAME_NIGHT_WATCH, "floating", "cube_floating", label, "%s: %s" % [label, prop_name],
				"group bottom at y %.2f with nothing within 6 cm of it" % low, low))


# ------------------------------------------------------------------ sweeps

## Last Route: chunks around the origin of every seed, at most `per_biome` chunks of each biome per seed.
static func sweep_last_route(seeds: Array, per_biome: int, out: Array) -> Dictionary:
	var stats := {"chunks": 0, "props": 0, "biomes": {}}
	for seed_value in seeds:
		var seed_text := String(seed_value)
		var generator := StreamedRouteGenerator.new(seed_text)
		var taken := {}
		for r in range(0, 14):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if maxi(absi(dx), absi(dz)) != r:
						continue
					var coord := Vector3i(dx, 0, dz)
					if not generator.is_chunk_allowed(coord):
						continue
					var biome := generator.biome_for(coord)
					if int(taken.get(biome, 0)) >= per_biome:
						continue
					taken[biome] = int(taken.get(biome, 0)) + 1
					var data := generator.chunk(coord)
					stats["chunks"] += 1
					stats["props"] += (data.get("region_props", []) as Array).size()
					stats["biomes"][biome] = int(stats["biomes"].get(biome, 0)) + 1
					audit_chunk(data, seed_text, biome, out)
	return stats


static func sweep_city(seeds: Array, out: Array) -> Dictionary:
	var stats := {"cities": 0, "buildings": 0, "decor": 0}
	for seed_value in seeds:
		var layout := CityLayout.build(String(seed_value))
		stats["cities"] += 1
		stats["buildings"] += layout.buildings.size()
		stats["decor"] += layout.decor.size()
		audit_city(layout, String(seed_value), out)
	return stats


## Plain-text counts table + the top `limit` ranked findings.
static func report_text(findings: Array, limit: int = 40) -> String:
	var lines := PackedStringArray()
	var table := counts(findings)
	for game in table:
		var parts := PackedStringArray()
		var total := 0
		for rule in (table[game] as Dictionary):
			parts.append("%s %d" % [rule, table[game][rule]])
			total += int(table[game][rule])
		lines.append("%s: %d  (%s)" % [game, total, ", ".join(parts)])
	var ranked := rank(findings)
	for i in mini(limit, ranked.size()):
		var f: Dictionary = ranked[i]
		lines.append("  #%d [%s/%s] seed %s | %s | %s" % [i + 1, f["game"], f["rule"], f["seed"], f["at"], f["detail"]])
	return "\n".join(lines)

## One T and one cross hall junction of `biome` from `generator`, as CAP_AT entries (world x, z, yaw): the camera stands
## 5 m down an arm looking at the centre. Used by tools/look/capture.gd (CAP_JUNCTION=biome).
static func junction_spots(generator: StreamedRouteGenerator, biome: String) -> Array:
	var found := {}
	for r in range(0, 12):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r or found.size() >= 2:
					continue
				var coord := Vector3i(dx, 0, dz)
				if not generator.is_chunk_allowed(coord) or generator.biome_for(coord) != biome:
					continue
				var data := generator.chunk(coord)
				var grid: Array = data["grid"]
				var size := grid.size()
				var rooms := []
				for room in data["rooms"]:
					rooms.append(room["rect"])
				for z in range(6, size - 6):
					for x in range(6, size - 6):
						var cell := Vector2i(x, z)
						if not is_open_cell(grid, size, cell) or _in_any_room(rooms, cell):
							continue
						var arms := []
						for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
							var ok := true
							for k in range(1, 6):
								var c: Vector2i = cell + (step as Vector2i) * k
								if not is_open_cell(grid, size, c) or _in_any_room(rooms, c):
									ok = false
							if ok:
								arms.append(step)
						if arms.size() < 3:
							continue
						# the centre of a 3 x 3 crossing: all eight neighbours open too
						var all_open := true
						for ddz in range(-1, 2):
							for ddx in range(-1, 2):
								if not is_open_cell(grid, size, cell + Vector2i(ddx, ddz)):
									all_open = false
						if not all_open:
							continue
						var kind := "cross" if arms.size() == 4 else "T"
						if found.has(kind):
							continue
						var arm: Vector2i = arms[0]
						var eye := Vector2(cell) + Vector2(.5, .5) + Vector2(arm) * 5.0
						found[kind] = "%.1f,%.1f,%.0f" % [coord.x * 45 + eye.x, coord.z * 45 + eye.y, rad_to_deg(atan2(float(arm.x), float(arm.y)))]
	return found.values()
