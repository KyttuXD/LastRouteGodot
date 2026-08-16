class_name FacilityView3D
extends Node3D

## 3D counterpart to src/game/facility_view.gd. Renders the SAME
## facility_generator.gd grid data (unchanged, engine-agnostic) via a
## GridMap — the 3D equivalent of the 2D renderer's TileMapLayer — with
## physics collision. Floor/wall visuals and collision come from
## art/props-3d/environment/ via ModelSlot, not hardcoded geometry — see
## art/props-3d/README.md for the scale/pivot convention this mirrors:
## 1 grid cell = 1 meter, ground plane is XZ (Godot is Y-up).

const CELL_SIZE := 1.0
const FLOOR_SCENE := "res://art/props-3d/environment/floor_tile.tscn"
const WALL_SCENE := "res://art/props-3d/environment/wall_block.tscn"

## Corridor height, and the thickness of the slabs that cap it. 3 m matches the
## office rooms, so a player moving between modes reads the same scale.
const WALL_HEIGHT := 3.0
const SLAB := 0.1

const ITEM_FLOOR := 0
const ITEM_WALL := 1
const ITEM_CEILING := 2

## Per-region floor tints, keyed by the same region names CustomMapParser's
## paint palette uses. Real, bespoke floor art per theme (a mansion's own
## herringbone, a beach's own sand) is a much bigger asset pass than this
## session has scope for -- Blockbench isn't connected to author or verify
## one -- so this is a first pass that at least makes a painted region READ
## as a distinct place while a real texture is still future work: the same
## floor material, tinted. `albedo_color` multiplies the existing texture
## rather than replacing it, so the tile pattern underneath still shows
## through, just recoloured.
##
## "frozen tideline" reads as one region here, not two: it is a beach with
## the tide iced over, not a separate room type, so it gets beach's own
## entry rather than inventing a parallel one nothing places yet.
const REGION_FLOOR_TINTS := {
	"mansion": Color(0.55, 0.42, 0.30),
	"beach": Color(0.68, 0.82, 0.90),
	"office": Color(0.55, 0.62, 0.72),
	"maintenance": Color(0.80, 0.62, 0.35),
	"arcade": Color(0.85, 0.55, 0.85),
	"circus": Color(0.95, 0.55, 0.65),
	"nether": Color(0.70, 0.30, 0.30),
	"garden": Color(0.55, 0.80, 0.55),
}
## region name -> GridMap item id, filled in by _build_mesh_library().
var _region_floor_items := {}

var generator: FacilityGenerator

var _grid_map: GridMap
## The ceiling is its OWN GridMap so it can be hidden wholesale. A GridMap has
## no per-item visibility, and the top-down view has to see through it -- that
## view is the original game's primary perspective, not a debug camera.
var _ceiling_map: GridMap
var _interactables: Array = []
## The floor's single heater station, read by Wynelle's gimmick each frame.
var heater_station: RouteInteractable3D
## Glyra's counterplay, read by GlyraGimmick each frame the same way Wynelle's
## gimmick reads heater_station.
var music_box: RouteInteractable3D
var _ceiling_decor: CeilingDecor


func _ready() -> void:
	_grid_map = GridMap.new()
	_grid_map.cell_size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	var library := _build_mesh_library()
	_grid_map.mesh_library = library
	add_child(_grid_map)
	_ceiling_map = GridMap.new()
	_ceiling_map.cell_size = Vector3(CELL_SIZE, CELL_SIZE, CELL_SIZE)
	_ceiling_map.mesh_library = library
	add_child(_ceiling_map)


func generate_floor(seed_text: String) -> void:
	# Sized by the room, not by the renderer -- see
	# RoomState.generator_options().
	generator = FacilityGenerator.new(seed_text, RoomState.generator_options())
	_paint_grid()
	_spawn_interactables()
	_hang_ceiling_lights(seed_text)


## Same as generate_floor(), from a hand-painted PNG instead of procedural
## carving. Returns "" on success or an error to show the admin who asked for
## this floor, matching CustomMapParser.parse()'s own {"ok", "error"} shape.
func generate_floor_from_custom_map(image: Image, seed_text: String) -> String:
	var parsed := CustomMapParser.parse(image)
	if not parsed.get("ok", false):
		return String(parsed.get("error", "custom map failed to parse"))
	generator = FacilityGenerator.new(seed_text, RoomState.generator_options(), parsed)
	_paint_grid()
	_spawn_interactables()
	_hang_ceiling_lights(seed_text)
	for warning in parsed.get("warnings", []):
		push_warning("custom map: %s" % warning)
	return ""


## World-space size of the facility footprint on the XZ ground plane.
func facility_extent() -> Vector3:
	return Vector3(generator.cols, 0.0, generator.rows) * CELL_SIZE


func cell_to_world(cell: Vector2i) -> Vector3:
	return Vector3((cell.x + 0.5) * CELL_SIZE, 0.0, (cell.y + 0.5) * CELL_SIZE)


func start_world_position() -> Vector3:
	return cell_to_world(generator.start)


func _paint_grid() -> void:
	_grid_map.clear()
	_ceiling_map.clear()
	# Procedural rooms carry no "region" -- only a custom map's flood-filled
	# ones do (see CustomMapParser) -- so this is a no-op lookup, always
	# falling through to the ordinary floor, for every floor that isn't one.
	var has_regions := not _region_floor_items.is_empty() and generator.rooms.any(
		func(r): return not String(r.get("region", "")).is_empty())
	for y in generator.rows:
		for x in generator.cols:
			var open: bool = generator.grid[y][x] == 0
			var floor_item := ITEM_FLOOR
			if open and has_regions:
				var room := generator.room_at(x + 0.5, y + 0.5)
				var region := String(room.get("region", ""))
				if _region_floor_items.has(region):
					floor_item = _region_floor_items[region]
			_grid_map.set_cell_item(Vector3i(x, 0, y),
				floor_item if open else ITEM_WALL)
			# The maze had no lid at all, so corridors opened onto the void and
			# lost every bounce of light. Only open cells need one -- a wall
			# already fills its cell to the ceiling. A GridMap cell holds one
			# item, so the lid lives a layer up.
			if open:
				_ceiling_map.set_cell_item(Vector3i(x, 1, y), ITEM_CEILING)


## Lift the lid for the top-down view.
##
## Looking down from 12 m at a sealed corridor shows a ceiling, which is why
## switching to that view went completely black. Hiding it is not a hack around
## the ceiling -- a plan view of a building never draws the floor above the one
## you are reading.
func set_ceiling_visible(shown: bool) -> void:
	if _ceiling_map != null:
		_ceiling_map.visible = shown


func _spawn_interactables() -> void:
	for node in _interactables:
		node.queue_free()
	_interactables.clear()

	for relay in generator.relays:
		_spawn_interactable(RouteInteractable3D.Kind.RELAY, Vector2i(relay["x"], relay["y"]), "RECOVER SIGNAL RELAY")
	for battery in generator.batteries:
		_spawn_interactable(RouteInteractable3D.Kind.BATTERY, Vector2i(battery["x"], battery["y"]), "COLLECT BATTERY")
	for zone in generator.safe_zones:
		_spawn_interactable(RouteInteractable3D.Kind.SAFE_ZONE, Vector2i(zone["x"], zone["y"]), "REST AT SAFE ZONE")
	_spawn_interactable(RouteInteractable3D.Kind.LIFT, generator.exit_cell, "USE SERVICE LIFT")
	for spot in generator.place_hiding_spots():
		_spawn_interactable(RouteInteractable3D.Kind.HIDING_SPOT,
			Vector2i(spot["x"], spot["y"]), "HIDE")
	# One heater station per floor — Wynelle's counterplay. NEAR the start so
	# it's findable without hunting for it, matching the original's "single
	# station, known location" role, but not ON it: placed on the spawn cell
	# it was the first thing the player saw, at arm's length, blocking the way
	# out of their own spawn.
	heater_station = _spawn_interactable(RouteInteractable3D.Kind.HEATER_STATION,
		_near_start(), "USE HEATER STATION")
	# Glyra's music box: in the spawn room specifically, and Glyra herself
	# never leaves that room either -- she is stationary infrastructure, not
	# a hunter who has to be found.
	music_box = _spawn_interactable(RouteInteractable3D.Kind.MUSIC_BOX,
		_near_start(MUSIC_BOX_MIN_DISTANCE, MUSIC_BOX_MAX_DISTANCE), "WIND MUSIC BOX")
	# Verrine's vent network: one grate per generator.vents entry, at the exact
	# positions VerrineGimmick itself reads -- see FacilityGenerator.place_vents.
	for vent in generator.place_vents(GameConfig.VERRINE_VENT_COUNT):
		var node := _spawn_interactable(RouteInteractable3D.Kind.VENT,
			Vector2i(vent["x"], vent["y"]), "ENTER VENT")
		node.vent_id = String(vent["id"])
	# Zephyra's economy. Placed last so it reads generator.vents (already
	# built above) and avoids landing on a vent grate, the same collision
	# avoidance relays/batteries/safe_zones/hiding_spots already get.
	for coin in generator.place_coins(GameConfig.COIN_PICKUP_COUNT):
		_spawn_interactable(RouteInteractable3D.Kind.COIN,
			Vector2i(coin["x"], coin["y"]), "COLLECT COINS")


## An open cell within reach of the spawn, but not touching it: the spawn's
## safe zone sits ON the start cell, and a heater one step away from that put
## its interaction prompt fighting the safe zone's the moment the player
## turned around -- two "[E]" prompts within arm's reach of each other and no
## room to pick one without the other stealing focus. A short walk apart is
## still "findable without hunting for it" (the design goal in the comment
## this replaces) without the two treading on each other.
const HEATER_MIN_DISTANCE := 3
const HEATER_MAX_DISTANCE := 7
## Glyra's music box: the original keeps it in the spawn room specifically
## ("spawn-room music-box timer"), so its band sits inside the lobby rather
## than the walk-a-bit-further band the heater uses.
const MUSIC_BOX_MIN_DISTANCE := 1
const MUSIC_BOX_MAX_DISTANCE := 4

## Every already-placed interactable's cell, gathered fresh each call so two
## calls in the same floor build (heater, then the music box) cannot land on
## the same cell -- generator.relays/batteries/etc alone would not catch that,
## since neither knows about the OTHER call's pick.
func _taken_cells() -> Dictionary:
	var taken := {}
	for relay in generator.relays:
		taken[Vector2i(relay["x"], relay["y"])] = true
	for battery in generator.batteries:
		taken[Vector2i(battery["x"], battery["y"])] = true
	for zone in generator.safe_zones:
		taken[Vector2i(zone["x"], zone["y"])] = true
	for spot in generator.hiding_spots:
		taken[Vector2i(spot["x"], spot["y"])] = true
	taken[generator.exit_cell] = true
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item:
			taken[item.source_cell] = true
	return taken


func _near_start(min_distance: int = HEATER_MIN_DISTANCE, max_distance: int = HEATER_MAX_DISTANCE) -> Vector2i:
	var taken := _taken_cells()

	# BFS out from the start along actual walkable cells, not straight-line
	# distance -- a cell three tiles away as the crow flies can be on the far
	# side of a wall and a much longer walk, which would defeat the point.
	var visited := {generator.start: true}
	var distance_of := {generator.start: 0}
	var queue: Array = [generator.start]
	var by_distance: Array = []  # [[cell, distance], ...] in BFS (walking) order
	var qi := 0
	while qi < queue.size():
		var cell: Vector2i = queue[qi]
		qi += 1
		var distance: int = distance_of[cell]
		for step in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var next: Vector2i = cell + step
			if next.x < 0 or next.y < 0 or next.x >= generator.cols or next.y >= generator.rows:
				continue
			if generator.grid[next.y][next.x] != 0 or visited.has(next):
				continue
			visited[next] = true
			distance_of[next] = distance + 1
			queue.append(next)
			by_distance.append([next, distance + 1])

	for entry in by_distance:
		var cell: Vector2i = entry[0]
		var distance: int = entry[1]
		if distance < min_distance or distance > max_distance:
			continue
		if taken.has(cell):
			continue
		return cell
	# A facility too small for the preferred band: take the first open cell at
	# or past the minimum distance, whatever it is, rather than fail outright.
	for entry in by_distance:
		if int(entry[1]) >= min_distance and not taken.has(entry[0]):
			return entry[0]
	return generator.start


## Fairy-light strands hung across the ceiling: sparse, and spread out rather
## than clustered, so they read as scattered decoration and not as a landing
## strip. An absolute cap, not a fraction of the floor -- a fixed fraction of
## open cells scales with facility AREA, and the largest scale has thousands
## of them; that turned "a few strands here and there" into well over a
## hundred, spending most of a frame building small meshes and lights nothing
## was ever meant to see all at once.
const LIGHT_COUNT_MIN := 8
const LIGHT_COUNT_MAX := 18
const LIGHT_MIN_SPACING := 6.0

func _hang_ceiling_lights(seed_text: String) -> void:
	if _ceiling_decor != null:
		_ceiling_decor.queue_free()
	_ceiling_decor = CeilingDecor.new()
	add_child(_ceiling_decor)

	var rng := SeededRandom.new("%s:CEILING-LIGHTS" % seed_text)
	var candidates: Array[Vector2i] = []
	for y in generator.rows:
		for x in generator.cols:
			if generator.grid[y][x] == 0:
				candidates.append(Vector2i(x, y))
	if candidates.is_empty():
		return

	var target := clampi(candidates.size() / 60, LIGHT_COUNT_MIN, LIGHT_COUNT_MAX)
	var chosen: Array[Vector2i] = []
	# Shuffled draw-without-replacement rather than a scan with a spacing
	# reject loop: wanting only a handful out of a floor that can run to
	# thousands of open cells, a reject loop over all of them to find those
	# few is the expensive way to do it.
	var pool := candidates.duplicate()
	while chosen.size() < target and not pool.is_empty():
		var pick: Vector2i = pool[rng.next_index(pool.size())]
		pool.erase(pick)
		var clear := true
		for other in chosen:
			if Vector2(pick).distance_to(Vector2(other)) < LIGHT_MIN_SPACING:
				clear = false
				break
		if clear:
			chosen.append(pick)

	var anchors: Array = []
	for cell in chosen:
		var at := cell_to_world(cell)
		# Just under the ceiling slab, not touching it -- a bulb flush with the
		# ceiling reads as embedded in it rather than hanging from it.
		at.y = WALL_HEIGHT - 0.22
		anchors.append(at)
	_ceiling_decor.build(anchors, rng)


func _spawn_interactable(kind: RouteInteractable3D.Kind, cell: Vector2i, prompt_text: String) -> RouteInteractable3D:
	var node := RouteInteractable3D.new()
	node.position = cell_to_world(cell)
	node.kind = kind
	node.prompt_text = prompt_text
	node.source_cell = cell
	node.generator = generator
	node.changed.connect(world_changed.emit)
	add_child(node)
	_interactables.append(node)
	return node


## Anything on this floor the rest of the room has to hear about. Re-emitted
## from the interactables so the scene above has one thing to listen to instead
## of a subscription per relay.
signal world_changed(event: Dictionary)


## Apply an event another peer raised. Cell-addressed, because both peers built
## this floor from the same seed and therefore have an object on that cell.
func apply_event(event: Dictionary) -> void:
	var cell: Vector2i = event.get("cell", Vector2i(-1, -1))
	match String(event.get("what", "")):
		"pickup":
			var node := _at(cell, event.get("kind", -1))
			if node:
				node.adopt(event)
		"heater":
			if heater_station:
				heater_station.adopt(event)
		"hiding_disabled":
			var spot := hiding_spot_at(cell)
			if spot:
				spot.set_disabled(bool(event.get("disabled", false)))
		"sabotage":
			var relay := _at(cell, RouteInteractable3D.Kind.RELAY)
			if relay:
				relay.adopt(event)


func hiding_spot_at(cell: Vector2i) -> RouteInteractable3D:
	return _at(cell, RouteInteractable3D.Kind.HIDING_SPOT)


func _at(cell: Vector2i, kind: int) -> RouteInteractable3D:
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item and item.source_cell == cell and int(item.kind) == kind:
			return item
	return null


## Zephyra's repair offer: whichever relay is currently offline, or null if
## none is. Scans the same _interactables list shared_state() already reads
## sabotage off of, rather than generator.relays -- sabotage is presentation-
## node state (see route_interactable_3d.gd's own note on why), not the
## generator's.
func find_sabotaged_relay() -> RouteInteractable3D:
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item and item.kind == RouteInteractable3D.Kind.RELAY and item.sabotaged:
			return item
	return null


## Everything about this floor that a peer joining halfway through would
## otherwise get wrong.
func shared_state() -> Dictionary:
	var taken := []
	var sabotaged := []
	for node in _interactables:
		var item := node as RouteInteractable3D
		if item == null:
			continue
		if item.completed and RouteInteractable3D.PICKUPS.has(item.kind):
			taken.append({"cell": item.source_cell, "kind": int(item.kind)})
		if item.kind == RouteInteractable3D.Kind.RELAY and item.sabotaged:
			sabotaged.append(item.source_cell)
	return {
		"taken": taken,
		"heater": int(heater_station.heater_state) if heater_station else 0,
		"sabotaged": sabotaged,
	}


func adopt_state(state: Dictionary) -> void:
	for entry in state.get("taken", []):
		apply_event({"what": "pickup", "cell": entry["cell"], "kind": entry["kind"]})
	if heater_station:
		heater_station.adopt({"what": "heater", "state": state.get("heater", 0)})
	for cell in state.get("sabotaged", []):
		apply_event({"what": "sabotage", "cell": cell, "sabotaged": true})


## Floor, wall and ceiling as plain boxes.
##
## The wall used to be the imported wall_block model dropped straight into the
## GridMap, and it landed at the wrong orientation -- a cell is a cube and the
## model is not, so every wall carried whatever rotation the export happened to
## bake in. Chasing that per-cell is a losing game when the thing being drawn is
## a 1 m cube: a box is unambiguously square to the grid and cannot be rotated
## wrongly, which is the whole point.
##
## The art is not thrown away. Each box takes the imported model's own material
## and samples the same patch of its atlas, so the pixel art survives -- see
## _cube_material for why the UVs have to be remapped to keep it.
func _build_mesh_library() -> MeshLibrary:
	var library := MeshLibrary.new()
	# The floor is read from above and the wall from the side, so each takes
	# the patch its own model used on that face.
	var floor_material := _cube_material(FLOOR_SCENE, Vector3.UP)
	var wall_material := _cube_material(WALL_SCENE, Vector3.FORWARD)
	_widen_wall_crop(wall_material)
	# A ceiling is a floor seen from underneath.
	var ceiling_material := _cube_material(FLOOR_SCENE, Vector3.UP)
	# A cell's origin is centred in X and Z but sits at its FLOOR in Y, which
	# is why every offset below is measured up from zero rather than from a
	# centre.
	# The floor carries NO collider, and that is deliberate.
	#
	# Giving it one looked like an obvious fix -- a floor should be solid --
	# and it made the player climb: the capsule rests with its base exactly on
	# y=0, the slab's top is exactly y=0, and depenetration pushed the body up
	# half a metre in the first few frames and kept going, because velocity.y
	# is pinned to zero so nothing ever brings it back down.
	#
	# Nothing falls through because nothing pulls down. When gravity arrives,
	# the floor needs a collider AND the capsule needs to rest above it rather
	# than flush with it; one without the other is worse than neither.
	_add_box(library, ITEM_FLOOR, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
		Vector3(0.0, -SLAB * 0.5, 0.0), floor_material, false)
	_add_box(library, ITEM_WALL, Vector3(CELL_SIZE, WALL_HEIGHT, CELL_SIZE),
		Vector3(0.0, WALL_HEIGHT * 0.5, 0.0), wall_material, true)
	# Painted a layer up, so subtract that layer back out of the offset.
	_add_box(library, ITEM_CEILING, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
		Vector3(0.0, WALL_HEIGHT - CELL_SIZE - SLAB * 0.5, 0.0),
		ceiling_material, false)

	_region_floor_items.clear()
	var next_id := ITEM_CEILING + 1
	for region in REGION_FLOOR_TINTS:
		var tinted: Material = floor_material.duplicate() if floor_material else null
		if tinted is StandardMaterial3D:
			(tinted as StandardMaterial3D).albedo_color = REGION_FLOOR_TINTS[region]
		_add_box(library, next_id, Vector3(CELL_SIZE, SLAB, CELL_SIZE),
			Vector3(0.0, -SLAB * 0.5, 0.0), tinted, false)
		_region_floor_items[region] = next_id
		next_id += 1
	return library


static func _add_box(library: MeshLibrary, id: int, size: Vector3,
		offset: Vector3, material: Material, solid: bool) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	if material != null:
		mesh.material = material
	library.create_item(id)
	library.set_item_mesh(id, mesh)
	var placement := Transform3D(Basis.IDENTITY, offset)
	library.set_item_mesh_transform(id, placement)
	# Floors and ceilings are scenery; only walls need to stop anyone. Giving
	# the lid a collider would also give the player a head to bump.
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		library.set_item_shapes(id, [shape, placement])


## The imported model's material, retargeted at ONE patch of its atlas.
##
## A BoxMesh generates its own 0..1 UVs, so an atlas material dropped on one
## stretches the whole sheet across every face. Two narrowings are needed and
## neither alone is enough.
##
## First by FACING: only triangles pointing the way this surface will be seen
## from count, since the source model draws its top and its sides from
## different patches.
##
## Then by AREA, because facing still is not enough -- the floor model draws
## tile, trim and grate all on its top, so the bounds of every up-facing
## triangle enclosed all three and the cube came out a collage. Grouping those
## triangles by which patch they sample and keeping the one covering the most
## surface gives the material that tile actually reads as.
static func _cube_material(scene_path: String, facing: Vector3) -> Material:
	var loaded := ModelSlot.load_gridmap_item(scene_path)
	var mesh: Mesh = loaded["mesh"]
	if mesh == null or mesh.get_surface_count() == 0:
		return null
	var source := mesh.surface_get_material(0)
	if not source is StandardMaterial3D:
		return source
	var material: StandardMaterial3D = (source as StandardMaterial3D).duplicate()

	var arrays := mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if uvs.is_empty() or indices.is_empty() or verts.is_empty():
		return material

	var patches := {}
	for i in range(0, indices.size() - 2, 3):
		var a: int = indices[i]
		var b: int = indices[i + 1]
		var c: int = indices[i + 2]
		# 0.7 is a little over 45 degrees, so a triangle lands on exactly one
		# of the six box facings and none are counted twice.
		if a < normals.size() and normals[a].dot(facing) < 0.7:
			continue
		var corner: Vector2 = uvs[a].min(uvs[b]).min(uvs[c])
		var far: Vector2 = uvs[a].max(uvs[b]).max(uvs[c])
		# Snapped so the same patch keyed from different triangles buckets
		# together rather than splitting on float noise.
		var key := "%.3f,%.3f" % [snappedf(corner.x, 0.002), snappedf(corner.y, 0.002)]
		var area: float = (verts[b] - verts[a]).cross(verts[c] - verts[a]).length() * 0.5
		if patches.has(key):
			var seen: Dictionary = patches[key]
			seen["lo"] = (seen["lo"] as Vector2).min(corner)
			seen["hi"] = (seen["hi"] as Vector2).max(far)
			seen["area"] = float(seen["area"]) + area
		else:
			patches[key] = {"lo": corner, "hi": far, "area": area}

	var best := {}
	for key in patches:
		var patch: Dictionary = patches[key]
		if best.is_empty() or float(patch["area"]) > float(best["area"]):
			best = patch
	if best.is_empty():
		return material
	var origin: Vector2 = best["lo"]
	var span: Vector2 = (best["hi"] as Vector2) - origin
	if span.x <= 0.0 or span.y <= 0.0:
		return material
	material.uv1_scale = Vector3(span.x, span.y, 1.0)
	material.uv1_offset = Vector3(origin.x, origin.y, 0.0)
	return material


## _cube_material's own patch, for the wall specifically, turned out to be a
## narrow 12x27px trim seam -- correctly the LARGEST single triangle group on
## that face (the heuristic did its job right), but a sliver, stretched once
## across a full 1m x 3m face with nothing else to sample from. That is what
## "walls look bland" actually was: not the wrong patch, just one 12-pixel-wide
## crop blown up 8x with no repeat.
##
## Retiles the SAME patch instead of replacing it with a different one. Wider
## regions of this atlas look more detailed at a glance (a brick field, a
## checker floor, ribbed panelling), but this model is ONE mesh shared with
## other environment props across ONE atlas, and nothing here can confirm
## which of those regions actually belongs to this piece rather than the door
## frame or the floor tile it sits beside -- guessing wrong would trade a bland
## wall for a wrong one, and there is no renderer in this session to catch
## that before it ships. Repeating the patch this model's own geometry already
## points at is the improvement this method can actually stand behind: the
## same seam-and-trim line repeating every ~15cm reads as panelled wall
## segments, and Godot's default 3D sampler wraps a >1 uv1_scale without
## needing any texture-import change.
const WALL_REPEAT_X := 6.0
const WALL_REPEAT_Y := 6.0

static func _widen_wall_crop(material: Material) -> void:
	if material == null or not material is StandardMaterial3D:
		return
	var std: StandardMaterial3D = material
	std.uv1_scale = Vector3(std.uv1_scale.x * WALL_REPEAT_X, std.uv1_scale.y * WALL_REPEAT_Y, 1.0)
