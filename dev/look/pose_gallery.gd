extends Node

## Night Watch pose gallery: every hunter x every pose from NightWatchPoses, frozen at the pose's preview time, in a
## front-on orthographic row view. Writes one PNG per pose (all hunters) plus an overview sheet (a few hunters per pose).
##   godot --path . res://dev/look/pose_gallery.tscn -- OUT_DIR
## Env: HUNTERS=a,b,c to restrict the roster, POSES=door_lurk,wave to restrict the poses, OVERVIEW=kathy,dovelle,aki,void_red.

const COLUMNS := 8
const CELL := 200          # pixels per hunter in the per-pose sheets
const CELL_H := 330
const SPACING := 1.6

var _out_dir := "user://nw_gallery"
var _sub: SubViewport
var _rows: Array = []      # Array of Node3D, one per row of COLUMNS hunters
var _players: Array = []   # [{player, hunter}] per hunter
var _ids: Array = []


func _ready() -> void:
	if OS.get_cmdline_user_args().size() > 0:
		_out_dir = OS.get_cmdline_user_args()[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir) if _out_dir.begins_with("user://") else _out_dir)
	_ids = OS.get_environment("HUNTERS").split(",") if OS.get_environment("HUNTERS") != "" else _roster()
	_build()
	await _run()
	get_tree().quit()


func _roster() -> Array:
	var ids: Array = []
	ids.append_array(HunterRoster.A_Z_IDS)
	ids.append_array(HunterRoster.VOID_IDS)
	return ids.filter(func(id): return ResourceLoader.exists("res://assets/hunters_blocky/%s/%s.glb" % [id, id]))


func _build() -> void:
	_sub = SubViewport.new()
	_sub.size = Vector2i(COLUMNS * CELL, CELL_H)
	_sub.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sub.transparent_bg = false
	add_child(_sub)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.16, .15, .19)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(.8, .78, .82)
	env.environment.ambient_light_energy = .8
	_sub.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-30, 20, 0)
	sun.light_energy = .7
	_sub.add_child(sun)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = CELL_H / float(CELL) * SPACING
	cam.position = Vector3((COLUMNS - 1) * SPACING * .5, cam.size * .5 - .12, 8.0)
	cam.current = true
	_sub.add_child(cam)
	var rows := int(ceil(_ids.size() / float(COLUMNS)))
	for r in rows:
		var row := Node3D.new()
		row.visible = false
		_sub.add_child(row)
		_rows.append(row)
	for i in _ids.size():
		var id: String = _ids[i]
		var model := (load("res://assets/hunters_blocky/%s/%s.glb" % [id, id]) as PackedScene).instantiate() as Node3D
		model.position = Vector3((i % COLUMNS) * SPACING, 0, 0)
		model.rotation.y = PI
		_rows[i / COLUMNS].add_child(model)
		var player := ModelSlot.find_animation_player(model)
		NightWatchPoses.install(model, player, id)
		_players.append(player)


func _freeze(pose_id: String) -> void:
	var spec := NightWatchPoses.pose(pose_id)
	var at := float(spec.get("preview", float(spec["length"]) * .3))
	for player in _players:
		player.play(NightWatchPoses.clip_name(pose_id))
		player.seek(at, true)
		player.pause()


func _grab(row: int) -> Image:
	for r in _rows.size():
		(_rows[r] as Node3D).visible = r == row
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var image := _sub.get_texture().get_image()
	image.convert(Image.FORMAT_RGB8)
	return image


func _run() -> void:
	var poses: Array = OS.get_environment("POSES").split(",") if OS.get_environment("POSES") != "" else NightWatchPoses.pose_ids()
	var overview_ids: Array = (OS.get_environment("OVERVIEW") if OS.get_environment("OVERVIEW") != "" else "kathy,dovelle,aki,void_red").split(",")
	var tiles := {}          # pose -> {hunter id -> Image}
	for pose_id in poses:
		_freeze(pose_id)
		await get_tree().process_frame
		var sheet := Image.create(COLUMNS * CELL, _rows.size() * CELL_H, false, Image.FORMAT_RGB8)
		tiles[pose_id] = {}
		for r in _rows.size():
			var row_image := await _grab(r)
			sheet.blit_rect(row_image, Rect2i(0, 0, COLUMNS * CELL, CELL_H), Vector2i(0, r * CELL_H))
			for c in COLUMNS:
				var index := r * COLUMNS + c
				if index < _ids.size() and overview_ids.has(_ids[index]):
					var tile := Image.create(CELL, CELL_H, false, Image.FORMAT_RGB8)
					tile.blit_rect(row_image, Rect2i(c * CELL, 0, CELL, CELL_H), Vector2i.ZERO)
					tiles[pose_id][_ids[index]] = tile
		sheet.save_png("%s/%s.png" % [_out_dir, pose_id])
		print("pose ", pose_id)
	var hunters_shown: Array = overview_ids.filter(func(id): return _ids.has(id))
	var overview := Image.create(poses.size() * CELL, hunters_shown.size() * CELL_H, false, Image.FORMAT_RGB8)
	for p in poses.size():
		for h in hunters_shown.size():
			if tiles[poses[p]].has(hunters_shown[h]):
				overview.blit_rect(tiles[poses[p]][hunters_shown[h]], Rect2i(0, 0, CELL, CELL_H), Vector2i(p * CELL, h * CELL_H))
	overview.save_png("%s/overview.png" % _out_dir)
	print("saved ", _out_dir)
