extends Node3D

## Proof-of-concept viewer for an LRCM1 OSM City map (docs/CITY_OSM_MAPS.md). It is NOT the game loader: it reads a
## converted map from a directory given on the command line (never from res://, the data is never bundled), draws every
## chunk as one vertex-coloured mesh (ground runs plus building boxes), flies an aerial camera, logs the frame rate and
## optionally saves a capture.
##
##   godot --path . res://scenes/osm_city_preview.tscn -- --osm-dir=/abs/out_lm [--capture=/abs/shot.png]

const CELL_COLORS := {
	0: Color(0.08, 0.08, 0.1), 1: Color(0.18, 0.18, 0.2), 2: Color(0.42, 0.41, 0.4), 3: Color(0.55, 0.5, 0.45),
	4: Color(0.25, 0.45, 0.22), 5: Color(0.6, 0.55, 0.42), 6: Color(0.15, 0.3, 0.5), 7: Color(0.36, 0.3, 0.32),
	9: Color(0.95, 0.65, 0.25), 13: Color(0.8, 0.8, 0.8), 14: Color(0.8, 0.8, 0.8), 17: Color(0.45, 0.35, 0.3),
	19: Color(0.3, 0.29, 0.3),
}
const WALL := 7
const DOOR := 9

var _manifest := {}
var _camera: Camera3D
var _size := Vector2.ONE
var _time := 0.0
var _frames := 0
var _capture_path := ""
var _material := StandardMaterial3D.new()


func _ready() -> void:
	var dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--osm-dir="):
			dir = arg.trim_prefix("--osm-dir=")
		elif arg.begins_with("--capture="):
			_capture_path = arg.trim_prefix("--capture=")
	_material.vertex_color_use_as_albedo = true
	_add_environment()
	if dir.is_empty() or not _load(dir):
		push_error("osm_city_preview: no map loaded (pass --osm-dir=/path/to/converted/map)")
		get_tree().quit(1)
		return
	_camera = Camera3D.new()
	_camera.far = 4000.0
	add_child(_camera)
	_add_attribution()


func _load(dir: String) -> bool:
	var text := FileAccess.get_file_as_string(dir.path_join("manifest.json"))
	if text.is_empty():
		return false
	_manifest = JSON.parse_string(text)
	if _manifest == null or String(_manifest.get("format", "")) != "LRCM1":
		return false
	var chunk := int(_manifest["chunk"])
	var counts: Array = _manifest["chunks_xz"]
	_size = Vector2(int(counts[0]) * chunk, int(counts[1]) * chunk)
	var started := Time.get_ticks_msec()
	for cz in int(counts[1]):
		for cx in int(counts[0]):
			var bytes := FileAccess.get_file_as_bytes(dir.path_join("c_%d_%d.bin" % [cx, cz]))
			var raw := bytes.decompress_dynamic(-1, FileAccess.COMPRESSION_GZIP)
			if raw.size() < 8 or raw.slice(0, 4).get_string_from_ascii() != "LRC1":
				return false
			_add_chunk(raw, cx * chunk, cz * chunk, chunk)
	print("osm_city_preview: %s v%d, %d chunks, %s, built in %d ms" % [_manifest["name"], int(_manifest["version"]),
		int(counts[0]) * int(counts[1]), str(_manifest["stats"]), Time.get_ticks_msec() - started])
	return true


func _add_chunk(raw: PackedByteArray, ox: int, oz: int, size: int) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := size * size
	for z in size:
		var x := 0
		while x < size:
			var kind := raw[8 + z * size + x]
			var height := raw[8 + cells + z * size + x]
			var end := x + 1
			while end < size and raw[8 + z * size + end] == kind and raw[8 + cells + z * size + end] == height:
				end += 1
			var color: Color = CELL_COLORS.get(kind, Color(0.4, 0.4, 0.4))
			if (kind == WALL or kind == DOOR) and height > 0:
				var tone := 0.75 + 0.25 * float(height % 7) / 6.0
				_box(st, Vector3(ox + x, 0, oz + z), Vector3(ox + end, height, oz + z + 1), color * tone)
			else:
				_quad(st, Vector3(ox + x, 0, oz + z), Vector3(ox + end, 0, oz + z + 1), color)
			x = end
	st.generate_normals()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = st.commit()
	mesh_instance.material_override = _material
	add_child(mesh_instance)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, color: Color) -> void:
	st.set_color(color)
	for v in [Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, a.z), Vector3(b.x, a.y, b.z),
			Vector3(a.x, a.y, a.z), Vector3(b.x, a.y, b.z), Vector3(a.x, a.y, b.z)]:
		st.add_vertex(v)


func _box(st: SurfaceTool, a: Vector3, b: Vector3, color: Color) -> void:
	_quad(st, Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, b.z), color)
	st.set_color(color * 0.8)
	# four sides, wound to face outwards
	var faces := [
		[Vector3(a.x, a.y, a.z), Vector3(a.x, b.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, a.y, a.z)],
		[Vector3(b.x, a.y, b.z), Vector3(b.x, b.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, a.y, b.z)],
		[Vector3(a.x, a.y, b.z), Vector3(a.x, b.y, b.z), Vector3(a.x, b.y, a.z), Vector3(a.x, a.y, a.z)],
		[Vector3(b.x, a.y, a.z), Vector3(b.x, b.y, a.z), Vector3(b.x, b.y, b.z), Vector3(b.x, a.y, b.z)],
	]
	for f in faces:
		for i in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(f[i])


func _add_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.65, 0.8)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.65)
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	add_child(sun)


func _add_attribution() -> void:
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "%s  |  %s" % [_manifest["name"], _manifest["attribution"]]
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 13)
	layer.add_child(label)
	add_child(layer)


func _process(delta: float) -> void:
	if _camera == null:
		return
	_time += delta
	_frames += 1
	var center := Vector3(_size.x * 0.5, 0, _size.y * 0.5)
	var angle := 0.6 + _time * 0.15
	_camera.position = center + Vector3(sin(angle), 0, cos(angle)) * _size.x * 0.75 + Vector3(0, _size.x * 0.45, 0)
	_camera.look_at(center, Vector3.UP)
	if _frames == 240:
		print("osm_city_preview: %d frames in %.2f s = %.1f fps (Engine %.1f)" % [_frames, _time, _frames / _time,
			Engine.get_frames_per_second()])
		if not _capture_path.is_empty():
			get_viewport().get_texture().get_image().save_png(_capture_path)
			print("osm_city_preview: capture saved to ", _capture_path)
		get_tree().quit(0)
