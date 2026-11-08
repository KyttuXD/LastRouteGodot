extends RefCounted

## Shader lights: the Intel-Mac workaround that computes the flashlight cone and the lamp pool in the
## surface shader. Headless, so these prove the maths, the wiring and that a working GPU is left alone; they do NOT compile
## the GLSL or render anything (that is the windowed merge gate in the docs).
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- shader_lights

const PROBE_SCRIPT := "res://game/look/light_probe.gd"
const TEST_CACHE := "user://light_probe_test.json"
const LAB_FLASH := Vector3(0.08, -0.05, -0.12)
const V := ShaderLights.Verdict

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _near(a: float, b: float, tolerance: float, message: String) -> void:
	_expect(absf(a - b) <= tolerance, "%s (got %.4f, want %.4f +- %.4f)" % [message, a, b, tolerance])


func run(host: Node) -> int:
	_clean()
	_check_shader_text()
	_check_maths()
	_check_calibration()
	_check_band_and_clip()
	_check_probe_logic()
	await _check_probe_flow(host)
	await _check_occluder(host)
	await _check_push_and_lamps(host)
	_check_off_path(host)
	_clean()
	if _failures == 0:
		print("  shader_lights  ok")
	return _failures


## Boot state in and out: a failed check must not leak the enabled flag into the next suite.
func _clean() -> void:
	ShaderLights.reset()
	if FileAccess.file_exists(TEST_CACHE):
		DirAccess.remove_absolute(TEST_CACHE)
	if FileAccess.file_exists(TEST_CACHE + ".tmp"):
		DirAccess.remove_absolute(TEST_CACHE + ".tmp")


# -- (a) the shader text ------------------------------------------------------------------------------------------------------------

func _code_lines(text: String) -> Array[String]:
	var out: Array[String] = []
	for line in text.split("\n"):
		var t := line.strip_edges()
		if not t.is_empty() and not t.begins_with("//"):
			out.append(t)
	return out


func _check_shader_text() -> void:
	var plain_text := FileAccess.get_file_as_string(ShaderLights.PLAIN_SHADER_PATH)
	var lit_text := FileAccess.get_file_as_string(ShaderLights.LIT_SHADER_PATH)
	var inc_text := FileAccess.get_file_as_string(ShaderLights.INCLUDE_PATH)
	_expect(not plain_text.is_empty() and not lit_text.is_empty() and not inc_text.is_empty(), "a shader file is missing or empty")
	_expect(not plain_text.contains("sl_") and not plain_text.contains("#include"),
		"ref_surface.gdshader must stay untouched (working GPUs run it)")
	var lit_lines := _code_lines(lit_text)
	for line in _code_lines(plain_text):
		if line.begins_with("EMISSION"):
			continue
		_expect(lit_lines.has(line), "ref_surface_lit.gdshader lost this line of ref_surface.gdshader: %s" % line)
	_expect(lit_lines.has("#include \"%s\"" % ShaderLights.INCLUDE_PATH), "the lit shader does not include the lights")
	_expect(lit_lines.has("EMISSION = c * v_params.z + sl_emission((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, "
			+ "normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), ALBEDO * (1.0 - METALLIC));"),
		"the lit EMISSION line is not the vault glow plus sl_emission(world position, world normal, albedo * (1 - metallic))")
	_expect(lit_lines.has("ALBEDO = c * tint;") and lit_lines.find("ALBEDO = c * tint;") < lit_lines.find(
		"EMISSION = c * v_params.z + sl_emission((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), ALBEDO * (1.0 - METALLIC));"),
		"ALBEDO and METALLIC must be set before the EMISSION line reads them")
	# braces and parentheses balance (a stray one is a GLSL parse error the headless run cannot see)
	for text in [lit_text, inc_text]:
		var code := "\n".join(_code_lines(text))
		_expect(code.count("{") == code.count("}"), "unbalanced braces")
		_expect(code.count("(") == code.count(")"), "unbalanced parentheses")
	# every constant in the include equals its GDScript twin
	var twins := {"SL_FLASH_DECAY": ShaderLights.FLASH_DECAY, "SL_LAMP_DECAY": ShaderLights.LAMP_DECAY,
		"SL_STOREY": ShaderLights.STOREY, "SL_BAND_OFFSET": ShaderLights.BAND_OFFSET, "SL_CLIP_R": ShaderLights.CLIP_R,
		"SL_CLIP_FADE": ShaderLights.CLIP_FADE, "SL_CLIP_LO": ShaderLights.CLIP_LO, "SL_CLIP_HI": ShaderLights.CLIP_HI}
	var const_re := RegEx.create_from_string("const float (SL_[A-Z_]+)\\s*=\\s*(-?[0-9.]+);")
	var seen := {}
	for m in const_re.search_all(inc_text):
		seen[m.get_string(1)] = m.get_string(2).to_float()
	for key in twins:
		_expect(seen.has(key), "%s is missing from shader_lights.gdshaderinc" % key)
		if seen.has(key):
			_near(float(seen[key]), float(twins[key]), 1e-6, "%s differs from its ShaderLights twin" % key)
	_expect(seen.size() == twins.size(), "the include has a constant ShaderLights does not know: %s" % str(seen.keys()))
	_expect(float(twins["SL_STOREY"]) == StoreyLayers.STOREY, "STOREY differs from StoreyLayers.STOREY")
	var gain_re := RegEx.create_from_string("uniform vec2 sl_gain = vec2\\(([0-9.]+), ([0-9.]+)\\);")
	var gain := gain_re.search(inc_text)
	_expect(gain != null, "sl_gain uniform default not found")
	if gain != null:
		_near(gain.get_string(1).to_float(), ShaderLights.FLASH_GAIN, 1e-6, "flash gain default")
		_near(gain.get_string(2).to_float(), ShaderLights.LAMP_GAIN, 1e-6, "lamp gain default")
	_expect(inc_text.contains("vec4(0.0, 0.0, 0.0, 16.0)") and inc_text.contains("vec4(0.0, 0.0, -1.0, 0.8660254)")
		and _near_cos30(), "sl_flash_a / sl_flash_b defaults are not the flashlight's range 16 and cos(30 degrees)")
	# the exact formulas (the maths of ShaderLights.spot_factor / lamp_factor / plane_clip / in_band, line for line)
	for formula in [
			"nd = max(1.0 - nd, 0.0);", "return nd * pow(max(d, 0.0001), -decay);",
			"float ds = floor((y + SL_BAND_OFFSET) / SL_STOREY) - floor(src_y / SL_STOREY);", "return mod(ds, 2.0) < 0.5;",
			"float scos = max(dot(-L, sl_flash_b.xyz), sl_flash_b.w);",
			"float rim = max(0.0001, (1.0 - scos) / (1.0 - sl_flash_b.w));",
			"float cone = 1.0 - pow(rim, sl_flash_c.w);",
			"float clip = smoothstep(SL_CLIP_LO, SL_CLIP_HI, s);",
			"clip = mix(1.0, clip, sl_flash_hit.w * (1.0 - smoothstep(SL_CLIP_R, SL_CLIP_R + SL_CLIP_FADE, distance(wpos, sl_flash_hit.xyz))));",
			"return fc * (sl_gain.x * cone * clip * sl_att(d, sl_flash_a.w, SL_FLASH_DECAY) * max(dot(wnor, L), 0.0));",
			"return col.rgb * (sl_gain.y * sl_att(d, pos.w, SL_LAMP_DECAY) * max(dot(wnor, rel / max(d, 0.0001)), 0.0));",
			"return alb * lit;"]:
		_expect(inc_text.contains(formula), "formula missing from the include: %s" % formula)
	# attenuation is Godot's quartic window: nd = (d / range)^4
	_expect(inc_text.contains("float nd = d / range;") and inc_text.count("nd *= nd;") == 3,
		"sl_att is not the quartic window (d / range squared twice, then the window squared)")
	# uniforms: every one push() writes is declared, with the slot count the pool uses; nothing is an array or a global
	for name in ShaderLights.BEAM_UNIFORMS + ShaderLights.LAMP_POS_NAMES + ShaderLights.LAMP_COL_NAMES:
		_expect(inc_text.contains("uniform vec") and RegEx.create_from_string("uniform vec[24] %s\\b" % name).search(inc_text) != null,
			"uniform %s is not declared in the include" % name)
	_expect(ShaderLights.SLOTS == 8 and ShaderLights.LAMP_POS_NAMES.size() == 8 and ShaderLights.LAMP_COL_NAMES.size() == 8,
		"the pool is 8 lamps")
	_expect(not inc_text.contains("sl_lamp_pos8") and not inc_text.contains("global uniform") and not inc_text.contains("["),
		"the include must have exactly 8 lamp slots and no array or global uniform")
	for i in 8:
		_expect(inc_text.contains("sl_lamp(sl_lamp_pos%d, sl_lamp_col%d, wpos, wnor)" % [i, i]), "slot %d is not summed" % i)
	# the files load as resources and the lit variant would be picked up
	var include := load(ShaderLights.INCLUDE_PATH) as ShaderInclude
	var lit := load(ShaderLights.LIT_SHADER_PATH) as Shader
	_expect(include != null and include.code.contains("sl_emission"), "the include does not load as a ShaderInclude")
	_expect(lit != null and lit.code.contains("sl_emission"), "the lit shader does not load as a Shader")
	if lit != null:
		var names := []
		for u in lit.get_shader_uniform_list():
			names.append(String((u as Dictionary).get("name", "")))
		# The shader language front end runs under the dummy renderer too: a parse or type error in the lit shader or its
		# include (a typo, a bad include path) leaves this list empty. The GPU's own GLSL compile is the windowed gate.
		_expect(not names.is_empty(), "the lit shader did not parse (no uniforms came back): see the SHADER ERROR above")
		for name in ShaderLights.BEAM_UNIFORMS + ShaderLights.LAMP_POS_NAMES + ShaderLights.LAMP_COL_NAMES + ShaderLights.BASE_PARAMETERS:
			_expect(names.has(String(name)), "compiled lit shader lacks uniform %s" % name)


func _near_cos30() -> bool:
	return absf(0.8660254 - cos(deg_to_rad(30.0))) < 1e-6


# -- (b) the maths against an independently computed table ---------------------------------------------------------------------------

func _check_maths() -> void:
	var dir := Vector3(0, 0, -1)
	var cos_cut := cos(deg_to_rad(30.0))
	var e := 7.5
	# energy x spot_factor at the lab's spot (position LAB_FLASH, range 16, 30 degrees, cone attenuation 1.4)
	var spot_rows := [
		[Vector3(0, 0, -12), Vector3(0, 0, 1), 0.3058, "end wall centre"],
		[Vector3(1, 0, -12), Vector3(0, 0, 1), 0.2994, "end wall 1 m off axis"],
		[Vector3(0, -1.5, -2.68), Vector3(0, 1, 0), 0.0491, "floor, near edge of the cone"],
		[Vector3(0, -1.5, -5), Vector3(0, 1, 0), 0.3312, "floor 5 m"],
		[Vector3(0, -1.5, -8), Vector3(0, 1, 0), 0.1408, "floor 8 m"],
		[Vector3(0, -1.5, -12), Vector3(0, 1, 0), 0.0352, "floor 12 m"],
		[Vector3(-1.5, 0, -3), Vector3(1, 0, 0), 0.1193, "left wall 3 m"]]
	for row in spot_rows:
		var got := e * ShaderLights.spot_factor(row[0], row[1], LAB_FLASH, dir, 16.0, cos_cut, 1.4)
		_near(got, float(row[2]), maxf(1e-3, 0.005 * float(row[2])), "spot at %s" % row[3])
	_near(ShaderLights.spot_factor(Vector3(0, 0, 3), Vector3(0, 0, 1), LAB_FLASH, dir, 16.0, cos_cut, 1.4), 0.0, 1e-9,
		"nothing behind the light is lit")
	_near(ShaderLights.spot_factor(Vector3(0, 0, -17), Vector3(0, 0, 1), LAB_FLASH, dir, 16.0, cos_cut, 1.4), 0.0, 1e-9,
		"nothing beyond the range is lit")
	_near(ShaderLights.spot_factor(Vector3(12, 0, -3), Vector3(-1, 0, 0), LAB_FLASH, dir, 16.0, cos_cut, 1.4), 0.0, 1e-9,
		"nothing outside the cone is lit")
	# a lamp: energy 3 x LAMP_ENERGY_SCALE = 2.1, range 9 x LAMP_RANGE_SCALE = 7.2, decay 1.6
	var lamp_energy := 3.0 * RefLook.LAMP_ENERGY_SCALE
	var lamp_range := 9.0 * RefLook.LAMP_RANGE_SCALE
	_near(lamp_energy, 2.1, 1e-6, "lamp energy")
	_near(lamp_range, 7.2, 1e-6, "lamp range")
	_expect(LampField.LIGHT_ATTENUATION == ShaderLights.LAMP_DECAY, "LampField.LIGHT_ATTENUATION and ShaderLights.LAMP_DECAY differ")
	_expect(LampField.LIGHT_RANGE == lamp_range and LampField.BASE_ENERGY == lamp_energy, "LampField constants changed under the table")
	var lamp_rows := [[1.0, 2.098], [2.0, 0.685], [3.0, 0.341], [4.0, 0.187], [5.0, 0.094], [6.0, 0.032], [7.0, 0.001], [8.0, 0.0]]
	for row in lamp_rows:
		var d := float(row[0])
		var got := lamp_energy * ShaderLights.lamp_factor(Vector3(0, 0, -d), Vector3(0, 0, 1), Vector3.ZERO, lamp_range)
		_near(got, float(row[1]), maxf(1e-3, 0.005 * float(row[1])), "lamp at %.0f m" % d)
	_near(lamp_energy * ShaderLights.lamp_factor(Vector3(0, 0, -2), Vector3(0, 0, -1), Vector3.ZERO, lamp_range), 0.0, 1e-9,
		"a surface facing away from the lamp is dark")


## Gating calibration: the lab corridor (dev/look/flash_lab.gd: camera at the origin, fov 75, 480 x 270, the spot at 7.5)
## re-rendered in GDScript with the shader's formulas and gain, against what the PC's REAL SpotLight3D measured there
## (floor 0.069, end wall 0.189; the same maths with the prototype's linear ramp reproduces the lab's 0.091 / 0.435).
## A gross error in the gain or the falloff fails here; the fine match is the windowed merge gate (specular is omitted).
func _check_calibration() -> void:
	var floor_luma := _lab_region(Rect2(480 * 0.40, 270 * 0.78, 480 * 0.20, 270 * 0.18))
	var far_luma := _lab_region(Rect2(480 * 0.46, 270 * 0.42, 480 * 0.08, 270 * 0.16))
	print("  note  lab corridor with shader lights: floor %.3f (PC engine 0.069) end wall %.3f (PC engine 0.189)" % [floor_luma, far_luma])
	_near(floor_luma, 0.069, 0.012, "lab floor luma vs the PC engine spot")
	_near(far_luma, 0.189, 0.025, "lab end-wall luma vs the PC engine spot")


func _lab_region(rect: Rect2) -> float:
	var width := 480.0
	var height := 270.0
	var th := tan(deg_to_rad(75.0) / 2.0)
	var aspect := width / height
	var albedo := Color(0.8, 0.15, 0.15)
	var sum := Color(0, 0, 0)
	var n := 0
	var x := int(rect.position.x)
	while x < int(rect.end.x):
		var y := int(rect.position.y)
		while y < int(rect.end.y):
			var u := (2.0 * (x + 0.5) / width - 1.0) * th * aspect
			var v := (1.0 - 2.0 * (y + 0.5) / height) * th
			sum += _lab_pixel(Vector3(u, v, -1.0), albedo)
			n += 1
			y += 4
		x += 4
	var mean := sum / float(maxi(n, 1))
	return mean.get_luminance()


func _lab_pixel(ray: Vector3, albedo: Color) -> Color:
	var best_t := INF
	var at := Vector3.ZERO
	var normal := Vector3.UP
	if ray.y < 0.0:   # floor
		var t := -1.5 / ray.y
		var p := ray * t
		if absf(p.x) <= 1.5 and p.z >= -20.0 and p.z <= 0.0 and t < best_t:
			best_t = t
			at = p
			normal = Vector3.UP
	var t_end := 12.0   # end wall
	var p_end := ray * t_end
	if absf(p_end.x) <= 1.5 and absf(p_end.y) <= 1.5 and t_end < best_t:
		best_t = t_end
		at = p_end
		normal = Vector3(0, 0, 1)
	if best_t == INF:
		return Color(0, 0, 0)
	var e := 7.5 * ShaderLights.FLASH_GAIN * ShaderLights.spot_factor(at, normal, LAB_FLASH, Vector3(0, 0, -1), 16.0,
		cos(deg_to_rad(30.0)), 1.4)
	var ambient := 0.035
	return Color(minf(ambient * albedo.r + albedo.r * e, 1.0), minf(ambient * albedo.g + albedo.g * e, 1.0),
		minf(ambient * albedo.b + albedo.b * e, 1.0))


# -- (c) storey band and the wall-behind clip ------------------------------------------------------------------------------------------

func _check_band_and_clip() -> void:
	# the band is StoreyLayers' own rule: a light reaches the structure of storeys with its parity and no neighbour's
	var lamp_ys := [0.5, 2.5, 3.9, 4.0, 5.5, 7.9, -0.5, -3.9, -4.0, 8.2]
	var surface_ys := [-8.0, -4.0, -3.88, -0.5, -0.12, 0.0, 0.01, 1.5, 3.88, 3.95, 4.0, 4.5, 7.88, 8.0, 11.88, 12.0]
	for lamp_y in lamp_ys:
		var level := StoreyLayers.level_at(float(lamp_y))
		var mask := StoreyLayers.light_mask(level)
		for surface_y in surface_ys:
			var surface_level := StoreyLayers.level_at(float(surface_y) + ShaderLights.BAND_OFFSET)
			var engine_lights_it := (mask & StoreyLayers.structure_layer(surface_level)) != 0
			_expect(ShaderLights.in_band(float(surface_y), float(lamp_y)) == engine_lights_it,
				"band disagrees with StoreyLayers: lamp y %.2f surface y %.2f (engine says %s)" % [lamp_y, surface_y, str(engine_lights_it)])
	_expect(ShaderLights.in_band(0.0, 2.0) and ShaderLights.in_band(3.88, 2.0), "a level-0 lamp lights its floor and ceiling")
	_expect(not ShaderLights.in_band(4.0, 2.0) and not ShaderLights.in_band(4.5, 2.0) and not ShaderLights.in_band(4.7, 2.0),
		"a level-0 lamp must not light the next storey (its floor top or its walls)")
	_expect(not ShaderLights.in_band(-0.5, 2.0) and not ShaderLights.in_band(-0.12, 2.0),
		"a level-0 lamp must not light the storey below (walls or its ceiling)")
	# the clip
	var plane := ShaderLights.plane_from_hit(Vector3(0, 0, -1), Vector3(0, 0, -7), Vector3(0, 0, -1))
	_expect(plane.z > 0.99 and absf(plane.x) < 1e-6 and absf(plane.w - (-7.0)) < 1e-5,
		"plane_from_hit must face the light: normal (0,0,+1), w = n . point = -7 (got %s)" % str(plane))
	var plane2 := ShaderLights.plane_from_hit(Vector3(0, 0, -1), Vector3(0, 0, -7), Vector3(0, 0, 1))
	_expect(plane2.is_equal_approx(plane), "a collider normal pointing away is turned to face the light")
	var hit := Vector4(0, 0, -7, 1)
	_near(ShaderLights.plane_clip(Vector3(0, 0, -7), plane, hit), 1.0, 1e-6, "the hit surface itself is not clipped")
	_near(ShaderLights.plane_clip(Vector3(0, 0, -6.9), plane, hit), 1.0, 1e-6, "in front of the wall is not clipped")
	_near(ShaderLights.plane_clip(Vector3(0, 0, -7.2), plane, hit), 1.0, 1e-6, "0.2 m behind the wall is still lit (the clip starts there)")
	_near(ShaderLights.plane_clip(Vector3(0, 0, -7.5), plane, hit), 0.0, 1e-6, "0.5 m behind the wall is fully clipped")
	_near(ShaderLights.plane_clip(Vector3(0, 0, -7.35), plane, hit), 0.5, 0.01, "half way through the clip")
	_near(ShaderLights.plane_clip(Vector3(0, 0, -15.5), plane, hit), 1.0, 1e-6, "far behind the wall: clip faded out (no black-out of far geometry)")
	_near(ShaderLights.plane_clip(Vector3(8.5, 0, -7.6), plane, hit), 1.0, 1e-6, "8.0+ m from the hit point is not clipped")
	_near(ShaderLights.plane_clip(Vector3(0, 0, -9.0), plane, Vector4(0, 0, -7, 0)), 1.0, 1e-6, "no hit (w = 0): no clip at all")
	_expect(ShaderLights.plane_clip(Vector3(0, 0, -7.6), plane, hit) < 0.01, "a point right behind the wall is clipped")


# -- (e) the self-test's decisions, mode table and cache ----------------------------------------------------------------------------------

func _check_probe_logic() -> void:
	# measured: PC wall 0.033 ambient, 0.448 omni, 0.189 spot; Intel Macs 0.033 for all three
	_expect(ShaderLights.decide(0.033, 0.448, 0.189) == V.OK, "the PC must pass")
	_expect(ShaderLights.decide(0.033, 0.033, 0.033) == V.BROKEN, "the Intel Mac must fail")
	_expect(ShaderLights.decide(0.033, 0.033, 0.189) == V.OK and ShaderLights.decide(0.033, 0.448, 0.033) == V.OK,
		"either light working is a pass")
	_expect(ShaderLights.decide(0.0, 0.4, 0.2) == V.INCONCLUSIVE and ShaderLights.decide(-1.0, -1.0, -1.0) == V.INCONCLUSIVE,
		"a black or unreadable ambient frame is inconclusive")
	_expect(ShaderLights.decide(0.5, 0.9, 0.9) == V.INCONCLUSIVE, "a bright ambient frame is inconclusive")
	# the thresholds sit well between the recorded numbers
	_expect(ShaderLights.PASS_OMNI * 4.0 < 0.448 - 0.033, "omni threshold has under 4x margin below the PC reading")
	_expect(ShaderLights.PASS_SPOT * 4.0 < 0.189 - 0.033, "spot threshold has under 4x margin below the PC reading")
	_expect(ShaderLights.PASS_OMNI > 0.0 and ShaderLights.PASS_SPOT > 0.0 and 0.033 > ShaderLights.AMB_MIN and 0.033 < ShaderLights.AMB_MAX,
		"the thresholds must be above noise and the Intel ambient must be a valid reading")
	# the retry rule
	_expect(ShaderLights.next_step([V.OK]) == "done_ok", "OK stops")
	_expect(ShaderLights.next_step([V.INCONCLUSIVE]) == "done_inconclusive", "inconclusive stops without a verdict")
	_expect(ShaderLights.next_step([V.BROKEN]) == "need_another", "one BROKEN is measured again")
	_expect(ShaderLights.next_step([V.BROKEN, V.BROKEN]) == "done_broken", "two BROKEN in a row confirm")
	_expect(ShaderLights.next_step([V.BROKEN, V.OK]) == "done_ok", "BROKEN then OK is a pass")
	_expect(ShaderLights.next_step([V.BROKEN, V.INCONCLUSIVE]) == "done_inconclusive", "BROKEN then inconclusive is not a fail")
	_expect(ShaderLights.next_step([V.INCONCLUSIVE, V.BROKEN]) == "need_another", "a BROKEN after an inconclusive run is the first one")
	# modes: headless, web, XR and phone builds are OFF whatever is forced
	var desktop := {"macos": true}
	var args_none := PackedStringArray()
	_expect(ShaderLights.resolve_mode("", args_none, desktop) == "auto", "a Mac defaults to auto")
	_expect(ShaderLights.resolve_mode("", args_none, {"macos": false}) == "off", "other desktops default to off")
	_expect(ShaderLights.resolve_mode("1", args_none, {"macos": false}) == "on", "LR_SHADER_LIGHTS=1 forces on anywhere")
	_expect(ShaderLights.resolve_mode("0", args_none, desktop) == "off", "LR_SHADER_LIGHTS=0 forces off")
	_expect(ShaderLights.resolve_mode("probe", args_none, {"macos": false}) == "probe", "LR_SHADER_LIGHTS=probe runs the self-test anywhere")
	_expect(ShaderLights.resolve_mode("", PackedStringArray(["--shader-lights"]), {}) == "on", "--shader-lights forces on")
	_expect(ShaderLights.resolve_mode("1", PackedStringArray(["--no-shader-lights"]), desktop) == "off", "--no-shader-lights beats the env var")
	_expect(ShaderLights.resolve_mode("", PackedStringArray(["--no-light-probe"]), desktop) == "off", "--no-light-probe keeps a Mac off")
	_expect(ShaderLights.resolve_mode("", PackedStringArray(["--light-probe"]), {}) == "probe", "--light-probe runs the self-test")
	for gate in ["headless", "web", "xr", "phone"]:
		var ctx := {"macos": true, gate: true}
		_expect(ShaderLights.resolve_mode("1", PackedStringArray(["--shader-lights"]), ctx) == "off", "%s must stay off even when forced on" % gate)
		_expect(ShaderLights.resolve_mode("probe", args_none, ctx) == "off", "%s must not run the self-test even when forced" % gate)
		_expect(ShaderLights.resolve_mode("", args_none, ctx) == "off", "%s defaults to off" % gate)
	_expect(not ShaderLights.auto_probe_allowed("", "") and not ShaderLights.auto_probe_allowed("Apple M4", "Apple")
		and not ShaderLights.auto_probe_allowed("Apple A18 Pro GPU", "") and ShaderLights.auto_probe_allowed("Intel(R) HD Graphics 6000", "Intel Inc.")
		and ShaderLights.auto_probe_allowed("Intel(R) Iris(TM) Pro Graphics 5200", "Intel Inc."),
		"auto probing: empty and Apple GPUs skip, Intel Macs probe")
	# the cache
	var key := ShaderLights.cache_key("Intel(R) HD Graphics 6000", "Intel Inc.", "4.1 INTEL-18.1.4", "4.7.dev")
	var now := 1_800_000_000
	var pass_entry := ShaderLights.cache_entry(key, true, 0, now)
	_expect(ShaderLights.cache_valid(pass_entry, key, now + 400 * 86400), "a pass stays valid until the key changes")
	for field in ["adapter", "vendor", "api", "engine"]:
		var other := key.duplicate()
		other[field] = String(other[field]) + "x"
		_expect(not ShaderLights.cache_valid(pass_entry, other, now), "a changed %s must re-run the self-test" % field)
	var strike1 := ShaderLights.cache_entry(key, false, 1, now)
	var strike2 := ShaderLights.cache_entry(key, false, 2, now)
	_expect(not ShaderLights.cache_valid(strike1, key, now), "one strike is not trusted: the next launch measures again")
	_expect(ShaderLights.cache_strikes(strike1, key, now + 3600) == 1, "the strike is remembered")
	_expect(ShaderLights.cache_valid(strike2, key, now + 3600), "a confirmed fail is trusted")
	_expect(not ShaderLights.cache_valid(strike2, key, now + ShaderLights.FAIL_EXPIRY_SECONDS + 1), "a confirmed fail expires")
	_expect(ShaderLights.cache_strikes(strike1, key, now + ShaderLights.FAIL_EXPIRY_SECONDS + 1) == 0, "an old strike is forgotten")
	_expect(ShaderLights.cache_strikes(pass_entry, key, now) == 0 and ShaderLights.cache_strikes({}, key, now) == 0, "no strikes without a fail")
	_expect(ShaderLights.write_cache(TEST_CACHE, strike2) and ShaderLights.write_cache(TEST_CACHE, pass_entry), "cache write (twice: rename over an existing file)")
	var read := ShaderLights.read_cache(TEST_CACHE)
	_expect(ShaderLights.cache_valid(read, key, now) and bool(read.get("ok", false)), "cache round trip")
	_expect(not FileAccess.file_exists(TEST_CACHE + ".tmp"), "the temp file is gone after the write")
	var file := FileAccess.open(TEST_CACHE, FileAccess.WRITE)
	file.store_string("{not json")
	file.close()
	_expect(ShaderLights.read_cache(TEST_CACHE).is_empty() and not ShaderLights.cache_valid(ShaderLights.read_cache(TEST_CACHE), key, now),
		"a corrupt cache is a miss")
	DirAccess.remove_absolute(TEST_CACHE)
	_expect(ShaderLights.read_cache(TEST_CACHE).is_empty(), "a missing cache is a miss")


## The real control loop and the finish step, driven with injected readings (the SubViewport render is the windowed gate).
func _check_probe_flow(host: Node) -> void:
	var probe: Node = (load(PROBE_SCRIPT) as GDScript).new()
	probe.cache_path = TEST_CACHE
	var key := ShaderLights.cache_key("TEST GPU", "TEST", "4.1", "4.7")
	var good := {"amb": 0.033, "a": 0.448, "b": 0.189}
	var bad := {"amb": 0.033, "a": 0.033, "b": 0.033}
	var dark := {"amb": 0.0, "a": 0.0, "b": 0.0}
	var cases := [
		["PC: OK", [good], "done_ok", 1, 0],
		["Intel: BROKEN, BROKEN", [bad, bad], "done_broken", 2, 1],
		["flaky: BROKEN, OK", [bad, good], "done_ok", 2, 1],
		["unreadable: inconclusive", [dark], "done_inconclusive", 1, 0],
		["BROKEN, unreadable", [bad, dark], "done_inconclusive", 2, 1]]
	for case in cases:
		var feed: Array = case[1]
		var calls := [0, 0]
		var measure := func(cycle: int) -> Dictionary:
			calls[0] += 1
			return feed[mini(cycle, feed.size() - 1)]
		var pause := func() -> void:
			calls[1] += 1
		var run: Dictionary = await probe.run_cycles(measure, pause)
		_expect(String(run["step"]) == String(case[2]), "%s: step %s, want %s" % [case[0], run["step"], case[2]])
		_expect(calls[0] == int(case[3]), "%s: %d measurements, want %d" % [case[0], calls[0], case[3]])
		_expect(calls[1] == int(case[4]), "%s: %d pauses before the confirmation, want %d" % [case[0], calls[1], case[4]])
	# finish: what is cached and whether the mode switches on
	_clean()
	var no_pause := func() -> void:
		pass
	var feed_good := func(_c: int) -> Dictionary:
		return good
	var feed_bad := func(_c: int) -> Dictionary:
		return bad
	var feed_dark := func(_c: int) -> Dictionary:
		return dark
	var ok_run: Dictionary = await probe.run_cycles(feed_good, no_pause)
	var result: Dictionary = probe.finish(ok_run, key, 0)
	_expect(bool(result["wrote"]) and not ShaderLights.enabled, "a pass is cached and leaves the mode off")
	_expect(bool(ShaderLights.read_cache(TEST_CACHE).get("ok", false)), "the cached pass says ok")
	DirAccess.remove_absolute(TEST_CACHE)
	var bad_run: Dictionary = await probe.run_cycles(feed_bad, no_pause)
	result = probe.finish(bad_run, key, 0)
	var entry := ShaderLights.read_cache(TEST_CACHE)
	_expect(ShaderLights.enabled, "two failed measurements switch the shader lights on for this session")
	_expect(not bool(entry.get("ok", true)) and int(entry.get("strikes", 0)) == 1 and not bool(entry.get("confirmed", true)),
		"the first failing launch is only one strike, not a trusted fail")
	_expect(not ShaderLights.cache_valid(entry, key, int(entry.get("checked_unix", 0))), "so the next launch measures again")
	ShaderLights.set_enabled(false)
	result = probe.finish(bad_run, key, ShaderLights.cache_strikes(entry, key, int(entry.get("checked_unix", 0))))
	entry = ShaderLights.read_cache(TEST_CACHE)
	_expect(int(entry.get("strikes", 0)) == 2 and bool(entry.get("confirmed", false)), "the second failing launch confirms")
	_expect(ShaderLights.cache_valid(entry, key, int(entry.get("checked_unix", 0))), "a confirmed fail is then trusted")
	ShaderLights.set_enabled(false)
	DirAccess.remove_absolute(TEST_CACHE)
	var dark_run: Dictionary = await probe.run_cycles(feed_dark, no_pause)
	result = probe.finish(dark_run, key, 0)
	_expect(not bool(result["wrote"]) and not FileAccess.file_exists(TEST_CACHE) and not ShaderLights.enabled,
		"an inconclusive run writes nothing and changes nothing")
	probe.free()
	# the booted autoload: headless is gated off, writes no verdict and arms nothing
	var live := host.get_tree().root.get_node_or_null("LightProbe")
	_expect(live != null, "the LightProbe autoload is not registered")
	if live != null:
		_expect(String(live.mode) == "off", "a headless boot must resolve to mode off (got %s)" % live.mode)
	_clean()


# -- (d) the occluder, with real physics ------------------------------------------------------------------------------------------------

func _check_occluder(host: Node) -> void:
	var root := Node3D.new()
	host.get_tree().root.add_child(root)
	# structure: a GridMap wall cell at z -8 (its front face at z -7), like a chunk's collision
	var library := MeshLibrary.new()
	library.create_item(0)
	library.set_item_mesh(0, BoxMesh.new())
	library.set_item_shapes(0, [BoxShape3D.new(), Transform3D.IDENTITY])
	var grid := GridMap.new()
	grid.mesh_library = library
	grid.cell_size = Vector3.ONE
	grid.set_cell_item(Vector3i(0, 0, -8), 0)
	root.add_child(grid)
	# a prop (solid, layer 1, not structure) well in front of the wall
	var prop := StaticBody3D.new()
	prop.name = "TestProp"
	var prop_shape := CollisionShape3D.new()
	var prop_box := BoxShape3D.new()
	prop_box.size = Vector3(1, 1, 0.5)
	prop_shape.shape = prop_box
	prop.add_child(prop_shape)
	prop.position = Vector3(0.5, 0.5, -3.0)
	root.add_child(prop)
	# the game's own closed room door
	var door := RouteInteractable3D.new()
	door.configure_room_door("SL-DOOR", PropModelCatalog.model_path("normalRoomDoor", "aim"), false, false)
	door.position = Vector3(0.5, 0.0, -5.0)
	root.add_child(door)
	var flash := SpotLight3D.new()
	flash.spot_range = 16.0
	flash.position = Vector3(0.5, 0.5, 0.0)
	root.add_child(flash)
	for _i in 3:
		await host.get_tree().process_frame
		await host.get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var dir := Vector3(0, 0, -1)
	_expect(not ShaderLights.is_blocker(prop) and ShaderLights.is_blocker(grid), "a prop is not a blocker, a GridMap is")
	var character := CharacterBody3D.new()
	_expect(not ShaderLights.is_blocker(character), "a character is not a blocker")
	character.free()
	var door_body := door.find_child("ToolBarrier", false, false)
	_expect(door_body != null and ShaderLights.is_blocker(door_body), "the real door's barrier body is a blocker (group room_door)")
	# closed door: it stops the beam, the prop in front of it is skipped
	var found := ShaderLights.cast_beam(space, flash.global_position, dir, 16.0)
	_expect(not found.is_empty() and ShaderLights.is_blocker(found["collider"]) and found["collider"] != prop,
		"the beam must skip the prop and stop at the closed door")
	if not found.is_empty():
		_near((found["position"] as Vector3).z, -4.95, 0.08, "closed door hit depth")
	# open door: collision off, the beam reaches the GridMap
	door.apply_room_door_state(true, false)
	for _i in 3:
		await host.get_tree().physics_frame
	found = ShaderLights.cast_beam(space, flash.global_position, dir, 16.0)
	_expect(not found.is_empty() and found["collider"] is GridMap,
		"with the door open the beam must reach the GridMap, and the ray collider must be the GridMap node (is_blocker relies on it)")
	if not found.is_empty():
		_near((found["position"] as Vector3).z, -7.0, 0.03, "GridMap hit depth")
		_expect((found["normal"] as Vector3).is_equal_approx(Vector3(0, 0, 1)), "GridMap hit normal")
	_expect(ShaderLights.cast_beam(space, flash.global_position, dir, 5.0).is_empty(), "a hit beyond the range is no hit")
	# update_occluder: a square hit sets the plane, a skewed one does not
	ShaderLights.update_occluder(flash, RID())
	_expect(ShaderLights._target_hit.w == 1.0, "a square hit on the GridMap must set the occluder")
	_near(ShaderLights._target_plane.w, -7.0, 0.03, "plane w = n . hit point")
	_near(ShaderLights._target_plane.z, 1.0, 1e-4, "plane normal faces the light")
	flash.rotation_degrees = Vector3(0, 30, 0)   # about 30 degrees off square: cos 0.87, still clipped
	flash.position = Vector3(4.5, 0.5, 0.0)      # (so that the slanted ray still lands on the GridMap cell)
	ShaderLights.update_occluder(flash, RID())
	_expect(ShaderLights._target_hit.w == 1.0, "a 30 degree hit is near-square enough to clip")
	flash.rotation_degrees = Vector3(0, 60, 0)   # cos 0.5: a glancing hit never clips
	flash.position = Vector3(12.6, 0.5, 0.0)
	ShaderLights.update_occluder(flash, RID())
	_expect(ShaderLights._target_hit.w == 0.0, "a glancing hit must not clip the beam")
	ShaderLights.clear_occluder()
	root.queue_free()
	await host.get_tree().process_frame
	_clean()


# -- (f) push, lamps and the shader swap ---------------------------------------------------------------------------------------------------

func _check_push_and_lamps(host: Node) -> void:
	_clean()
	var root := Node3D.new()
	host.get_tree().root.add_child(root)
	var camera := Camera3D.new()
	camera.current = true
	root.add_child(camera)
	# a material on the plain shader, tracked because the mode is armed
	var plain := load(ShaderLights.PLAIN_SHADER_PATH) as Shader
	ShaderLights.armed = true
	var material := ShaderMaterial.new()
	material.shader = ShaderLights.surface_shader(plain)
	_expect(material.shader == plain and not ShaderLights.lit_loaded, "while off, new materials get the plain shader and the lit file is never loaded")
	var tint := Vector3(1.25, 1.22, 1.3)
	material.set_shader_parameter("tint", tint)
	ShaderLights.register_material(material, plain)
	var spot := SpotLight3D.new()
	spot.light_energy = 7.5
	spot.spot_range = 16.0
	spot.spot_angle = 30.0
	spot.spot_angle_attenuation = 1.4
	root.add_child(spot)
	var owner_script := GDScript.new()
	owner_script.source_code = "extends Node\nvar flashlight_enabled := false\n"
	owner_script.reload()
	var owner_node: Node = owner_script.new()
	root.add_child(owner_node)
	ShaderLights.register_flashlight(spot, owner_node)
	var mask0 := spot.light_cull_mask
	ShaderLights.register_flashlight(spot, owner_node)
	_expect(spot.light_energy == 7.5 and spot.light_cull_mask == mask0, "registering writes nothing to the light")
	_expect(ShaderLights.set_enabled(true) and ShaderLights.enabled, "the mode switches on")
	_expect(material.shader != plain and (material.shader as Shader).code.contains("sl_emission"), "the registered material got the lit shader")
	_expect(material.get_shader_parameter("tint") == tint, "the material keeps its parameters across the swap")
	# the game's own surface materials, built while the mode is on, take the lit shader and swap back with it
	RefTextures.rebuild_from_registry()
	var game_floor := RefTextures.array_material("floor")
	_expect(game_floor.shader != RefTextures.ARRAY_SHADER and (game_floor.shader as Shader).code.contains("sl_emission"),
		"RefTextures.array_material built while on must use the lit shader")
	_expect(game_floor.get_shader_parameter("tex") != null and game_floor.get_shader_parameter("tint") != null,
		"and keep its texture array and tint")
	ShaderLights.push(0.016)
	_expect(game_floor.get_shader_parameter("sl_flash_a") != null, "and receive the pushed lights")
	_near(spot.light_energy, 7.5 * ShaderLights.spot_scale, 1e-6, "the engine spot drops to spot_scale x its energy")
	_expect(spot.light_cull_mask == ShaderLights.STRUCTURE_FREE_MASK, "the engine spot stops lighting the structure")
	# the beam: off until the controller says the flashlight is on
	ShaderLights.push(0.016)
	_expect(ShaderLights.flash_c.x == 0.0 and ShaderLights.flash_c.y == 0.0 and ShaderLights.flash_c.z == 0.0, "no beam while the flashlight is off")
	owner_node.set("flashlight_enabled", true)
	spot.visible = true
	spot.light_energy = 0.0   # the warm-up renders at 0: must not switch the beam off
	ShaderLights.push(0.016)
	_near(ShaderLights.flash_c.x, 7.5, 1e-5, "beam colour x ORIGINAL energy while lit (engine energy is irrelevant)")
	_near(ShaderLights.flash_c.w, 1.4, 1e-6, "beam angle attenuation")
	_near(ShaderLights.flash_a.w, 16.0, 1e-6, "beam range")
	_near(ShaderLights.flash_b.w, cos(deg_to_rad(30.0)), 1e-6, "beam cos cutoff")
	_near(ShaderLights.flash_b.z, -1.0, 1e-5, "beam direction is the light's -Z")
	spot.visible = false   # a flicker off-beat
	ShaderLights.push(0.016)
	_expect(ShaderLights.flash_c.x == 0.0, "a hidden (flickering) flashlight is off in the shader")
	spot.visible = true
	owner_node.set("flashlight_enabled", false)   # battery empty
	ShaderLights.push(0.016)
	_expect(ShaderLights.flash_c.x == 0.0, "an empty battery is off in the shader")
	owner_node.set("flashlight_enabled", true)
	ShaderLights.push(0.016)
	_expect(material.get_shader_parameter("sl_flash_c") == ShaderLights.flash_c, "push writes the beam to the live materials")
	# the lamps, through a real LampField: slots hold the UNSCALED energy, the engine light is lowered after
	var field := LampField.new()
	root.add_child(field)
	field.set_process(false)
	var lamps: Array = [
		[Vector3(1.0, 2.5, 0.0), Color(1, 1, 1), 1.0, 0, LampField.LIGHT_RANGE],
		[Vector3(-1.0, 2.5, 0.5), Color(1, 1, 1), 2.6, 0, LampField.LIGHT_RANGE]]   # a chandelier-class lamp
	field.register(Vector3i.ZERO, lamps)
	ShaderLights.lamp_cap = 0.4
	field._process(0.25)
	field._process(0.25)
	var slot_energies: Array[float] = []
	for i in 2:
		slot_energies.append(ShaderLights.lamp_col[i].x)
	slot_energies.sort()
	_near(slot_energies[0], LampField.BASE_ENERGY * 1.0, 1e-4, "the shader slot holds the UNSCALED energy of a level-1 lamp (2.1)")
	_near(slot_energies[1], LampField.BASE_ENERGY * 2.6, 1e-4, "and of a 2.6x lamp (5.46), not the capped engine value")
	for i in 2:
		var light: OmniLight3D = field._lights[i]
		_expect(light.light_energy <= 0.4 + 1e-6, "the engine lamp light is capped at 0.4 (slot %d has %.3f)" % [i, light.light_energy])
		_expect(light.light_cull_mask == ShaderLights.STRUCTURE_FREE_MASK, "the engine lamp light skips the structure layers")
		_near(ShaderLights.lamp_pos[i].w, LampField.LIGHT_RANGE, 1e-5, "slot range")
	for i in range(2, ShaderLights.SLOTS):
		_expect(ShaderLights.lamp_col[i].x == 0.0 and ShaderLights.lamp_col[i].y == 0.0 and ShaderLights.lamp_col[i].z == 0.0,
			"unused slot %d must be dark" % i)
	field._process(0.25)   # a further frame must not feed the lowered engine energy back
	var again: Array[float] = [ShaderLights.lamp_col[0].x, ShaderLights.lamp_col[1].x]
	again.sort()
	_near(again[0], slot_energies[0], 1e-5, "no feedback of the lowered engine energy (small lamp)")
	_near(again[1], slot_energies[1], 1e-5, "no feedback of the lowered engine energy (big lamp)")
	# lamps fade out: the slot goes dark
	field.set_enabled(false)
	for _i in 6:
		field._process(0.25)
	_expect(ShaderLights.lamp_col[0].x == 0.0 and ShaderLights.lamp_col[1].x == 0.0, "a faded-out lamp leaves its slot dark")
	field.set_enabled(true)
	# off again: everything comes back
	ShaderLights.set_enabled(false)
	field._process(0.25)
	_expect(material.shader == plain, "the plain shader is back")
	_expect(game_floor.shader == RefTextures.ARRAY_SHADER, "the game's own surface material is back on the plain ARRAY_SHADER resource")
	RefTextures.rebuild_from_registry()
	_expect(material.get_shader_parameter("tint") == tint, "parameters survive the swap back")
	_expect(material.get_shader_parameter("sl_flash_c") == null, "the sl_ parameters are cleared")
	_expect(spot.light_energy == 7.5 and spot.light_cull_mask == mask0, "the flashlight energy and mask are restored")
	for i in 2:
		var light: OmniLight3D = field._lights[i]
		_expect(light.light_cull_mask == StoreyLayers.light_mask(StoreyLayers.level_at(light.global_position.y)) or not light.visible,
			"lamp masks are StoreyLayers' own again")
	root.queue_free()
	await host.get_tree().process_frame
	_clean()


# -- (g) the OK path: a working GPU is left alone -------------------------------------------------------------------------------------------

func _check_off_path(host: Node) -> void:
	_clean()
	var plain := load(ShaderLights.PLAIN_SHADER_PATH) as Shader
	_expect(not ShaderLights.enabled and not ShaderLights.armed, "boot state is off and unarmed")
	_expect(ShaderLights.surface_shader(plain) == plain and not ShaderLights.lit_loaded, "off: the plain shader, and the lit file is never loaded")
	for group in ["floor", "wall"]:
		var material := RefTextures.array_material(group)
		_expect(material.shader == RefTextures.ARRAY_SHADER, "off: the %s material uses the very same ARRAY_SHADER resource" % group)
		_expect(material.get_shader_parameter("sl_flash_c") == null and material.get_shader_parameter("sl_gain") == null,
			"off: no sl_ parameter is set on the %s material" % group)
	_expect(ShaderLights._materials.is_empty() and not ShaderLights.lit_loaded, "unarmed: no material is tracked and the lit shader is never loaded")
	# lights are left alone while off
	var spot := SpotLight3D.new()
	spot.light_energy = 7.5
	var default_mask := spot.light_cull_mask
	ShaderLights.register_flashlight(spot)
	ShaderLights.apply_flashlight()
	_expect(spot.light_energy == 7.5 and spot.light_cull_mask == default_mask, "off: apply_flashlight leaves the light alone")
	for level in [-2, 0, 1, 3]:
		_expect(ShaderLights.light_mask(level) == StoreyLayers.light_mask(level), "off: light_mask(%d) is StoreyLayers' own" % level)
	var before := [ShaderLights.flash_a, ShaderLights.flash_c, ShaderLights.plane, ShaderLights.hit]
	ShaderLights.push(0.016)
	_expect(before == [ShaderLights.flash_a, ShaderLights.flash_c, ShaderLights.plane, ShaderLights.hit], "off: push does nothing")
	# the on/off round trip, with the registration landing in the warm-up window (energy 0)
	spot.light_energy = 0.0
	ShaderLights.register_flashlight(spot)
	_expect(ShaderLights.flash_orig_energy() == ShaderLights.DEFAULT_FLASH_ENERGY, "a light registered at energy 0 (warm-up) is taken as the scene's 7.5")
	ShaderLights.set_enabled(true)
	ShaderLights.set_enabled(false)
	_expect(spot.light_energy == 7.5, "on then off restores 7.5 even when registered during the warm-up")
	spot.light_energy = 7.5
	spot.light_cull_mask = 0x3FF
	ShaderLights.register_flashlight(spot)
	ShaderLights.spot_scale = 0.047
	ShaderLights.set_enabled(true)
	_near(spot.light_energy, 7.5 * 0.047, 1e-6, "spot_scale applies")
	ShaderLights.set_enabled(false)
	_expect(spot.light_energy == 7.5 and spot.light_cull_mask == 0x3FF, "off restores the original energy and the original (non-default) mask")
	# a lit shader that cannot load keeps the mode off
	ShaderLights.reset()
	ShaderLights._lit_failed = true
	_expect(not ShaderLights.set_enabled(true) and not ShaderLights.enabled, "a lit shader that fails to load leaves the mode off")
	_expect(ShaderLights.surface_shader(plain) == plain, "and hands out the plain shader")
	spot.free()
	_clean()
