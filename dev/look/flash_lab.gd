extends Node3D

## Flashlight lab: a tiny corridor lit by a camera-side light, to find what a GPU/driver gets wrong without the rest of the
## game. For each wall/floor material (a plain StandardMaterial3D, then the game's own ref_surface.gdshader fed three solid
## colour layers: red, green, blue, the mesh asks for layer 0) and each light (none, SpotLight3D, OmniLight3D, spot at low
## energy) it saves OUTDIR/lab_<material>_<light>.png and prints LAB lines with the mean brightness of four screen regions.
##
##   Godot --path . res://dev/look/flash_lab.tscn -- OUTDIR
##
## Expected on a correct driver: "std" and "ref" walls brighten identically when a light is on, "ref" walls are RED (layer 0),
## the viewmodel box is lit but not clipped to white.

const SHADER := preload("res://game/look/ref_surface.gdshader")
const LAYER_COLORS := [Color(.8, .15, .15), Color(.15, .8, .15), Color(.15, .15, .8)]

var _out := "/tmp"
var _walls: Array[MeshInstance3D] = []
var _spot: SpotLight3D
var _omni: OmniLight3D
var _box: MeshInstance3D


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else "/tmp"
	DirAccess.make_dir_recursive_absolute(_out)
	_build()
	await _run()
	get_tree().quit(0)


func _build() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.035
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	var cam := Camera3D.new()
	cam.current = true
	cam.fov = 75.0
	add_child(cam)
	# left wall, right wall, floor, ceiling of a 3 m corridor, 20 m long, running away along -Z
	for spec in [[Vector3(-1.5, 0, -10), -90.0, Vector2(3, 20)], [Vector3(1.5, 0, -10), 90.0, Vector2(3, 20)],
			[Vector3(0, -1.5, -10), 0.0, Vector2(3, 20)], [Vector3(0, 1.5, -10), 180.0, Vector2(3, 20)]]:
		var m := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = spec[2]
		m.mesh = plane if OS.get_environment("LAB_PLAIN") != "" else _with_array_attributes(plane)
		m.position = spec[0]
		if abs(float(spec[1])) == 90.0:
			m.rotation_degrees = Vector3(0, 0, spec[1])
		elif float(spec[1]) == 180.0:
			m.rotation_degrees = Vector3(180, 0, 0)
		add_child(m)
		_walls.append(m)
	var end := MeshInstance3D.new()   # a wall across the corridor 12 m away: where the spot's cone lands
	var end_plane := PlaneMesh.new()
	end_plane.size = Vector2(3, 3)
	end.mesh = _with_array_attributes(end_plane)
	end.position = Vector3(0, 0, -12)
	end.rotation_degrees = Vector3(90, 0, 0)
	add_child(end)
	_walls.append(end)
	_box = MeshInstance3D.new()   # a stand-in for the held flashlight: close to the camera and to the light
	var box := BoxMesh.new()
	box.size = Vector3(.1, .1, .4)
	_box.mesh = box
	_box.position = Vector3(.25, -.2, -.6)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(.6, .6, .7)
	bm.roughness = .8
	_box.material_override = bm
	add_child(_box)
	_spot = SpotLight3D.new()
	_spot.light_energy = 7.5
	_spot.spot_range = 16.0
	_spot.spot_angle = 30.0
	_spot.spot_angle_attenuation = 1.4
	_spot.position = Vector3(.08, -.05, -.12)
	_spot.visible = false
	add_child(_spot)
	_omni = OmniLight3D.new()
	_omni.light_energy = 7.5
	_omni.omni_range = 16.0
	_omni.position = Vector3(.08, -.05, -.12)
	_omni.visible = false
	add_child(_omni)


## The plane's own arrays plus what ref_surface.gdshader reads: UV2.x = array layer (0), COLOR = roughness/metallic/emission.
func _with_array_attributes(plane: PlaneMesh) -> ArrayMesh:
	var arrays := plane.get_mesh_arrays()
	var count := (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var uv2 := PackedVector2Array()
	var col := PackedColorArray()
	for i in count:
		uv2.append(Vector2(float(OS.get_environment("LAB_LAYER").to_int()), 0.0))
		col.append(Color(.8, 0.0, 0.0))
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_COLOR] = col
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _std_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = LAYER_COLORS[0]
	m.roughness = .8
	return m


func _ref_material() -> ShaderMaterial:
	var images: Array[Image] = []
	for c in LAYER_COLORS:
		var img := Image.create(32, 32, true, Image.FORMAT_RGBA8)
		img.fill(c)
		img.generate_mipmaps()
		images.append(img)
	var arr := Texture2DArray.new()
	arr.create_from_images(images)
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("tex", arr)
	m.set_shader_parameter("tint", Vector3(1.25, 1.22, 1.3))
	m.set_shader_parameter("specular_base", .18)
	m.set_shader_parameter("specular_metal", .32)
	return m


func _run() -> void:
	if OS.get_environment("LAB_SWEEP") == "6":
		await _sweep6()
		return
	if OS.get_environment("LAB_SWEEP") == "5":
		await _sweep5()
		return
	if OS.get_environment("LAB_SWEEP") == "4":
		await _sweep4()
		return
	if OS.get_environment("LAB_SWEEP") == "3":
		await _sweep3()
		return
	if OS.get_environment("LAB_SWEEP") == "2":
		await _sweep2()
		return
	if OS.get_environment("LAB_SWEEP") != "":
		await _sweep()
		return
	for mat_name in ["std", "ref"]:
		var mat: Material = _std_material() if mat_name == "std" else _ref_material()
		for w in _walls:
			w.material_override = mat
		for light_name in ["none", "spot", "omni", "spot_e1"]:
			_spot.visible = light_name == "spot" or light_name == "spot_e1"
			_spot.light_energy = 1.0 if light_name == "spot_e1" else 7.5
			_omni.visible = light_name == "omni"
			for _i in 6:
				await get_tree().process_frame
			_shot("%s_%s" % [mat_name, light_name])


## LAB_SWEEP=6: the flashlight as shader math (no engine light): Godot's own spot formulas added as EMISSION on the surface.
const BEAM_SHADER := """
shader_type spatial;
uniform vec3 albedo_c = vec3(0.8, 0.15, 0.15);
uniform vec3 flash_pos = vec3(0.08, -0.05, -0.12);
uniform vec3 flash_dir = vec3(0.0, 0.0, -1.0);
uniform vec4 flash_color_energy = vec4(1.0, 1.0, 1.0, 7.5);
uniform float flash_range = 16.0;
uniform float flash_cos_cut = 0.8660254;
uniform float flash_angle_att = 1.4;
uniform float flash_k = 1.0;
void fragment() {
	ALBEDO = albedo_c;
	ROUGHNESS = 0.8;
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wnor = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 rel = flash_pos - wpos;
	float d = length(rel);
	vec3 L = rel / max(d, 0.0001);
	float scos = max(dot(-L, flash_dir), flash_cos_cut);
	float rim = max(1e-4, (1.0 - scos) / (1.0 - flash_cos_cut));
	float a = (1.0 - pow(rim, flash_angle_att)) * clamp(1.0 - d / flash_range, 0.0, 1.0);
	float ndl = max(dot(wnor, L), 0.0);
	EMISSION = albedo_c * flash_color_energy.rgb * flash_color_energy.a * a * ndl * flash_k;
}
"""


func _sweep6() -> void:
	var sh := Shader.new()
	sh.code = BEAM_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	for w in _walls:
		w.material_override = mat
	_spot.visible = false
	_omni.visible = false
	for k in [1.0, 0.3183]:
		for e in [0.0, 1.0, 3.0, 7.5]:
			mat.set_shader_parameter("flash_color_energy", Vector4(1, 1, 1, e))
			mat.set_shader_parameter("flash_k", k)
			for _i in 6:
				await get_tree().process_frame
			_shot("sweep6_k%s_e%s" % [str(k).replace(".", "_"), str(e).replace(".", "_")])


## LAB_SWEEP=5: does the Environment's tonemap or the glow/adjustment stage change what a light does? (omni 7.5 and dir 1.0)
func _sweep5() -> void:
	var mat := _std_material()
	for w in _walls:
		w.material_override = mat
	var dir := DirectionalLight3D.new()
	dir.rotation_degrees = Vector3(0, 90, 0)
	dir.visible = false
	add_child(dir)
	var env: Environment = (get_child(0) as WorldEnvironment).environment
	for tm in [["linear", Environment.TONE_MAPPER_LINEAR], ["reinhard", Environment.TONE_MAPPER_REINHARDT],
			["filmic", Environment.TONE_MAPPER_FILMIC], ["aces", Environment.TONE_MAPPER_ACES]]:
		env.tonemap_mode = tm[1]
		for lt in [["omni7_5", "omni", 7.5], ["dir1", "dir", 1.0]]:
			_omni.visible = lt[1] == "omni"
			_omni.light_energy = lt[2]
			dir.visible = lt[1] == "dir"
			dir.light_energy = lt[2]
			for _i in 6:
				await get_tree().process_frame
			_shot("sweep5_%s_%s" % [tm[0], lt[0]])


## LAB_SWEEP=4: which light paths survive: shadows on, a directional light (along -X, onto the left wall), lights of every kind at one energy.
func _sweep4() -> void:
	var mat := _std_material()
	for w in _walls:
		w.material_override = mat
	_omni.visible = false
	_spot.visible = false
	var dir := DirectionalLight3D.new()
	dir.rotation_degrees = Vector3(0, 90, 0)
	dir.visible = false
	add_child(dir)
	var cases := [
		["omni_e7_5", "omni", 7.5, false], ["omni_shadow_e7_5", "omni", 7.5, true], ["omni_shadow_e0_4", "omni", 0.4, true],
		["spot_shadow_e7_5", "spot", 7.5, true], ["spot_shadow_e0_4", "spot", 0.4, true],
		["dir_e0_2", "dir", 0.2, false], ["dir_e1", "dir", 1.0, false], ["dir_e3", "dir", 3.0, false], ["dir_e7_5", "dir", 7.5, false]]
	for c in cases:
		_omni.visible = c[1] == "omni"
		_spot.visible = c[1] == "spot"
		dir.visible = c[1] == "dir"
		_omni.light_energy = c[2]
		_spot.light_energy = c[2]
		dir.light_energy = c[2]
		_omni.shadow_enabled = c[3]
		_spot.shadow_enabled = c[3]
		_omni.omni_range = 16.0
		_omni.omni_attenuation = 1.0
		for _i in 6:
			await get_tree().process_frame
		_shot("sweep4_%s" % c[0])


## LAB_SWEEP=3: the real flashlight shape (SpotLight3D 30 deg, range 16) at several energies, and N weak lights instead of one strong
## one. "far" is the end wall 12 m away, i.e. what the cone reaches.
func _sweep3() -> void:
	var mat := _std_material()
	for w in _walls:
		w.material_override = mat
	_omni.visible = false
	_spot.visible = false
	var extra: Array[SpotLight3D] = []
	for i in 8:
		var l := SpotLight3D.new()
		l.spot_range = 16.0
		l.spot_angle = 30.0
		l.spot_angle_attenuation = 1.4
		l.position = _spot.position
		l.visible = false
		add_child(l)
		extra.append(l)
	var cases := []
	for e in [0.2, 0.4, 1.0, 3.0, 7.5]:
		cases.append(["spot_e%s" % str(e).replace(".", "_"), 1, e])
	for n in [2, 3, 5, 8]:
		cases.append(["spot_%dx0_4" % n, n, 0.4])
	cases.append(["spot_3x0_25", 3, 0.25])
	cases.append(["spot_8x0_25", 8, 0.25])
	for c in cases:
		for i in extra.size():
			extra[i].visible = i < int(c[1])
			extra[i].light_energy = float(c[2])
		for _i in 6:
			await get_tree().process_frame
		_shot("sweep3_%s" % c[0])


## LAB_SWEEP=2: finer energy series, and which light/material term breaks (light specular, material specular, roughness).
func _sweep2() -> void:
	var mat := _std_material()
	for w in _walls:
		w.material_override = mat
	_spot.visible = false
	_omni.visible = true
	_omni.omni_range = 16.0
	_omni.omni_attenuation = 1.0
	_omni.position = Vector3(.08, -.05, -.12)
	var cases := []
	for e in [0.05, 0.1, 0.2, 0.3, 0.5, 0.7, 1.0, 1.5, 2.0, 3.0, 5.0, 7.5]:
		cases.append(["e%s" % str(e).replace(".", "_"), e, 0.5, StandardMaterial3D.SPECULAR_SCHLICK_GGX, .8])
	cases.append(["spec0_e7_5", 7.5, 0.0, StandardMaterial3D.SPECULAR_SCHLICK_GGX, .8])
	cases.append(["matspecoff_e7_5", 7.5, 0.5, StandardMaterial3D.SPECULAR_DISABLED, .8])
	cases.append(["bothoff_e7_5", 7.5, 0.0, StandardMaterial3D.SPECULAR_DISABLED, .8])
	cases.append(["rough1_e7_5", 7.5, 0.5, StandardMaterial3D.SPECULAR_SCHLICK_GGX, 1.0])
	cases.append(["bothoff_e100", 100.0, 0.0, StandardMaterial3D.SPECULAR_DISABLED, .8])
	for c in cases:
		_omni.light_energy = c[1]
		_omni.light_specular = c[2]
		mat.specular_mode = c[3]
		mat.roughness = c[4]
		for _i in 6:
			await get_tree().process_frame
		_shot("sweep2_%s" % c[0])


## LAB_SWEEP=1: one omni light on the plain material, varying range, attenuation, energy and position, to map what a driver does.
func _sweep() -> void:
	var mat := _std_material()
	for w in _walls:
		w.material_override = mat
	_spot.visible = false
	_omni.visible = true
	var cases := [
		["r2", 2.0, 1.0, 7.5, Vector3(.08, -.05, -.12)], ["r4", 4.0, 1.0, 7.5, Vector3(.08, -.05, -.12)],
		["r8", 8.0, 1.0, 7.5, Vector3(.08, -.05, -.12)], ["r16", 16.0, 1.0, 7.5, Vector3(.08, -.05, -.12)],
		["r64", 64.0, 1.0, 7.5, Vector3(.08, -.05, -.12)], ["r256", 256.0, 1.0, 7.5, Vector3(.08, -.05, -.12)],
		["att0", 16.0, 0.0, 7.5, Vector3(.08, -.05, -.12)], ["att2", 16.0, 2.0, 7.5, Vector3(.08, -.05, -.12)],
		["att05", 16.0, 0.5, 7.5, Vector3(.08, -.05, -.12)], ["e100", 16.0, 1.0, 100.0, Vector3(.08, -.05, -.12)],
		["e0_1", 16.0, 1.0, 0.1, Vector3(.08, -.05, -.12)],
		["far_light", 16.0, 1.0, 7.5, Vector3(0, 0, -4)], ["behind_light", 16.0, 1.0, 7.5, Vector3(0, 0, 3)]]
	for c in cases:
		_omni.omni_range = c[1]
		_omni.omni_attenuation = c[2]
		_omni.light_energy = c[3]
		_omni.position = c[4]
		for _i in 6:
			await get_tree().process_frame
		_shot("sweep_%s" % c[0])


func _shot(label: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(_out.path_join("lab_%s.png" % label))
	var w := img.get_width()
	var h := img.get_height()
	print("LAB %s size=%s left_wall=%.3f floor=%.3f far=%.3f box=%.3f rgb_leftwall=%s" % [label, str(img.get_size()),
		_luma(img, Rect2(w * .05, h * .30, w * .20, h * .40)), _luma(img, Rect2(w * .40, h * .78, w * .20, h * .18)),
		_luma(img, Rect2(w * .46, h * .42, w * .08, h * .16)), _luma(img, Rect2(w * .62, h * .62, w * .12, h * .20)),
		_mean_rgb(img, Rect2(w * .05, h * .30, w * .20, h * .40))])


func _luma(img: Image, r: Rect2) -> float:
	var c := _mean_color(img, r)
	return c.get_luminance()


func _mean_rgb(img: Image, r: Rect2) -> String:
	var c := _mean_color(img, r)
	return "(%.2f,%.2f,%.2f)" % [c.r, c.g, c.b]


func _mean_color(img: Image, r: Rect2) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	var step := 4
	var x := int(r.position.x)
	while x < int(r.end.x):
		var y := int(r.position.y)
		while y < int(r.end.y):
			sum += img.get_pixel(clampi(x, 0, img.get_width() - 1), clampi(y, 0, img.get_height() - 1))
			n += 1
			y += step
		x += step
	return sum / float(maxi(n, 1))
