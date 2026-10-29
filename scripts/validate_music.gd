extends RefCounted

## Music wing props (docs/MUSIC_WING.md): every prop of the data family "music" is wired like any catalogued prop (models in
## res://data, loadable GLBs, footprint, template size, hunter scale 1.5, a collider when solid, the right mount list), the
## playable ones (MusicProps) prompt and play their cue, and with music_noise on they make a noise burst hunters hear; with
## it off they only sound. Dressing stays batchable, playable props are not.
##
##   godot --headless --path . res://scenes/validate.tscn -- music

const DRESSING_NOT_SOLID := ["deskMic", "studioMonitors", "cableCoil", "cableRun", "acousticPanel", "guitarWallHanger", "onAirSign"]
const WALL := ["acousticPanel", "guitarWallHanger", "onAirSign"]
const FLOOR_DRESSING := ["cableCoil", "cableRun"]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


class FakePlayer extends Node:
	var bursts: Array = []

	func emit_noise_burst(level: float, seconds: float) -> void:
		bursts.append([level, seconds])


func run(host: Node) -> int:
	var ids: Array = ContentRegistry.family("music")
	_expect(ids.size() == 24, "the music family has %d props, expected 24" % ids.size())
	for id in ids:
		_check_prop(String(id))
	_check_playable(host)
	_check_wing()
	_check_recipes()
	if _failures == 0:
		print("  music     %d music props wired from data (models, footprints, scale, colliders, mounts); %d playable with cues and hunter noise behind music_noise; the rehearsal wing carves its 15x13 stage and 4 rooms across both slots, reachable, both ways round; %d recipes clear"
			% [ids.size(), MusicProps.PLAYABLE.size(), MusicWing.TEMPLATES.size()])
	return _failures


func _check_prop(id: String) -> void:
	var paths: Array = PropModelCatalog.MODEL_PATHS.get(id, [])
	_expect(not paths.is_empty(), "%s has no models in PropModelCatalog.MODEL_PATHS" % id)
	_expect(paths == ContentRegistry.get_def("props", id).get("models", []), "%s models do not come from data/props/music.json" % id)
	for path in paths:
		_expect(ResourceLoader.exists(String(path)), "%s model %s is missing" % [id, path])
	_expect(RoomCatalog.FOOTPRINTS.has(id), "%s has no footprint" % id)
	_expect(StreamedRouteGenerator.TEMPLATE_PROP_SIZES.has(id), "%s has no template size" % id)
	_expect(is_equal_approx(PropModelCatalog.hunter_scale(id), 1.5), "%s is not at hunter scale 1.5" % id)
	var solid := RoomCatalog.is_solid(id)
	_expect(solid == not (id in DRESSING_NOT_SOLID), "%s solid is %s" % [id, solid])
	if solid:
		_expect(PropColliderSizes.SIZES.has(id), "%s is solid but has no collider size" % id)
	_expect(PropModelCatalog.is_wall_mounted(id) == (id in WALL), "%s wall mounting is wrong" % id)
	_expect(PropModelCatalog.is_floor_dressing(id) == (id in FLOOR_DRESSING), "%s floor dressing is wrong" % id)
	var playable := MusicProps.is_playable(id)
	_expect(PropModelCatalog.interaction_for(id) == ("music" if playable else ""), "%s interaction is \"%s\"" % [id, PropModelCatalog.interaction_for(id)])
	_expect(PropModelCatalog.is_batchable(id) == not playable, "%s batchable should be %s" % [id, not playable])


func _check_playable(host: Node) -> void:
	for type in MusicProps.PLAYABLE:
		_expect(ContentRegistry.has("props", type), "playable %s is not a music prop" % type)
		var cue := "music_" + String(MusicProps.PLAYABLE[type]["cue"])
		var stream := Sound.render_cue(cue)
		_expect(stream != null and stream.get_length() > 0.2, "%s cue %s is silent or too short" % [type, cue])
		var item := RouteInteractable3D.new()
		item.kind = RouteInteractable3D.Kind.FURNITURE
		item.configure_furniture("music")
		item.set_meta("prop_type", type)
		_expect(item.get_prompt() == MusicProps.prompt_for(type), "%s prompt is \"%s\"" % [type, item.get_prompt()])
		item.free()
	var player := FakePlayer.new()
	host.add_child(player)
	var saved := MusicProps.noise_enabled
	MusicProps.noise_enabled = true
	var level := MusicProps.play("drumKit", player)
	_expect(level > 0.0 and player.bursts.size() == 1, "music_noise on: the drum kit made no noise burst")
	MusicProps.noise_enabled = false
	_expect(MusicProps.play("drumKit", player) == 0.0 and player.bursts.size() == 1, "music_noise off: the drum kit still alerted hunters")
	MusicProps.noise_enabled = saved
	_expect(MusicProps.play("cableRun", player) == 0.0, "a dressing prop played a sound")
	player.free()


## The wing in a chunk's two great-hall slots, doors facing across the vertical hall: the stage in the west slot, four
## rooms off a wing hall in the east slot, all of their declared sizes with open doorways, and every open cell of both
## slots reachable from the vertical hall. Also mirrored (stage east), so either side assignment carves cleanly.
func _check_wing() -> void:
	for swap in [false, true]:
		var size := 45
		var grid := []
		for z in size:
			var row := []
			row.resize(size)
			row.fill(1)
			grid.append(row)
		var hall := Rect2i(21, 0, 3, size)
		StreamedRouteGenerator._carve_rect(grid, hall)
		var rooms := []
		var slots := []
		for side in 2:
			var slot := Rect2i(0 if side == 0 else 24, 12, MusicWing.SLOT, MusicWing.SLOT)
			var door := Vector2i(slot.end.x - 1 if side == 0 else slot.position.x, 22)
			StreamedRouteGenerator._carve_rect(grid, slot)
			StreamedRouteGenerator._seal_room_perimeter_except(grid, slot, door)
			var part := MusicWing.part_for_side(1 - side if swap else side)
			var wing := MusicWing.carve(grid, slot, door, null, part)
			rooms.append_array(wing["rooms"])
			slots.append(slot)
		_expect(rooms.size() == 5, "the wing has %d rooms" % rooms.size())
		var counts := {}
		for room in rooms:
			var r: Rect2i = room["rect"]
			counts[room["room_type"]] = int(counts.get(room["room_type"], 0)) + 1
			_expect(slots.any(func(slot: Rect2i) -> bool: return slot.encloses(r)), "%s leaves its slot" % room["room_type"])
			var p: Dictionary = MusicWing.SIZE_PROFILES[room["room_type"]]
			var lo: Vector2i = p["min"]
			var hi: Vector2i = p["max"]
			var short := mini(r.size.x, r.size.y)
			var long := maxi(r.size.x, r.size.y)
			_expect(short >= mini(lo.x, lo.y) and long >= maxi(lo.x, lo.y) and short <= mini(hi.x, hi.y) and long <= maxi(hi.x, hi.y),
				"%s is %s, outside its profile" % [room["room_type"], r.size])
			var doorway: Vector2i = room["doorway"]
			_expect(int(grid[doorway.y][doorway.x]) == 0, "%s doorway is walled" % room["room_type"])
		_expect(counts == {"music_stage": 1, "practice_room": 2, "instrument_storage": 1, "recording_booth": 1},
			"the wing's rooms are %s" % [counts])
		var stage: Array = rooms.filter(func(room: Dictionary) -> bool: return room["room_type"] == "music_stage")
		_expect(not stage.is_empty() and (stage[0]["rect"] as Rect2i).size in [Vector2i(15, 13), Vector2i(13, 15)],
			"the stage is not 15x13")
		var reach := _flood(grid, Vector2i(22, 22))
		for slot in slots:
			for z in range(slot.position.y, slot.end.y):
				for x in range(slot.position.x, slot.end.x):
					if int(grid[z][x]) == 0 and not reach.has(Vector2i(x, z)):
						_expect(false, "cell %s of the wing is cut off (swap %s)" % [Vector2i(x, z), swap])
						return


static func _flood(grid: Array, start: Vector2i) -> Dictionary:
	var seen := {start: true}
	var todo := [start]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.y < 0 or n.y >= grid.size() or n.x < 0 or n.x >= (grid[0] as Array).size():
				continue
			if int(grid[n.y][n.x]) == 0 and not seen.has(n):
				seen[n] = true
				todo.append(n)
	return seen


## Every recipe at its usual sizes: only catalogued props, inside the room, no two solid props on one cell, the entrance
## column kept clear, and the defining props present.
func _check_recipes() -> void:
	var sizes := {"music_stage": [Vector2i(13, 15), Vector2i(21, 21)], "carnival_stage": [Vector2i(21, 9)],
		"practice_room": [Vector2i(11, 9), Vector2i(9, 9)], "instrument_storage": [Vector2i(11, 9), Vector2i(9, 9)],
		"recording_booth": [Vector2i(11, 9)], "music_store": [Vector2i(20, 9)]}
	var key := {"music_stage": ["drumKit", "micStand", "stageLightRig"], "carnival_stage": ["drumKit", "ampStack"],
		"practice_room": ["drumKit", "acousticPanel"], "instrument_storage": ["guitarWallHanger", "instrumentCases"],
		"recording_booth": ["mixingDesk", "labGlassPartition", "micStand"], "music_store": ["guitarWallHanger", "checkoutCounter"]}
	for template in MusicWing.TEMPLATES:
		for room_size in sizes[template]:
			var half := (int(room_size.x) - 3) / 2
			var front := int(room_size.y) - 3
			for mirror in [1, -1]:
				var specs := MusicWing.room_specs(template, half, int(room_size.y), mirror)
				var where := "%s %s mirror %d" % [template, room_size, mirror]
				var types := {}
				var cells := {}
				for spec in specs:
					var type := String(spec["type"])
					types[type] = true
					_expect(PropModelCatalog.MODEL_PATHS.has(type), "%s uses uncatalogued %s" % [where, type])
					var side := int(spec["side"])
					var depth := int(spec["depth"])
					_expect(absi(side) <= half and depth >= 0 and depth <= front, "%s puts %s outside the room at %d,%d" % [where, type, side, depth])
					var solid := bool(spec.get("solid", RoomCatalog.is_solid(type))) and not bool(spec.get("wall_mount", false))
					if solid:
						var cell := Vector2i(side, depth)
						_expect(not cells.has(cell), "%s stacks %s on %s at %s" % [where, type, cells.get(cell, ""), cell])
						cells[cell] = type
						_expect(not (side == 0 and depth >= front - 1), "%s blocks the entrance with %s" % [where, type])
				for wanted in key[template]:
					_expect(types.has(wanted), "%s has no %s" % [where, wanted])
