class_name ShaderLights
extends RefCounted

## Shader-computed lights for the chunk surfaces (docs/SHADER_LIGHTS.md).
##
## Apple's legacy OpenGL driver (Intel Macs) breaks the engine's light path: a light lights nothing beyond about a metre and
## the reach shrinks as its energy grows. On such a GPU the flashlight cone and the lamp pool are computed in the surface
## shader instead (ref_surface_lit.gdshader + shader_lights.gdshaderinc) and added as EMISSION. This class holds the
## switch (`enabled`), the values the shader reads, the hand-over of the engine lights, the beam's occluder, and the
## pure functions the startup self-test (LightProbe) and the tests use.
##
## OFF is the default everywhere. While `enabled` is false nothing here writes a light, a mask or a material, and
## RefTextures hands out the untouched ref_surface.gdshader: working GPUs run the exact program they always did.

const PLAIN_SHADER_PATH := "res://game/look/ref_surface.gdshader"
const LIT_SHADER_PATH := "res://game/look/ref_surface_lit.gdshader"
const INCLUDE_PATH := "res://game/look/shader_lights.gdshaderinc"

## Pool lamps the shader can light with (PlatformProfile.lamp_pool is 8 on desktop, fewer on phones and headsets).
const SLOTS := 8
const LAMP_POS_NAMES: Array[StringName] = [&"sl_lamp_pos0", &"sl_lamp_pos1", &"sl_lamp_pos2", &"sl_lamp_pos3",
	&"sl_lamp_pos4", &"sl_lamp_pos5", &"sl_lamp_pos6", &"sl_lamp_pos7"]
const LAMP_COL_NAMES: Array[StringName] = [&"sl_lamp_col0", &"sl_lamp_col1", &"sl_lamp_col2", &"sl_lamp_col3",
	&"sl_lamp_col4", &"sl_lamp_col5", &"sl_lamp_col6", &"sl_lamp_col7"]
## Every uniform of the include that push() writes (the test checks each one is declared there).
const BEAM_UNIFORMS: Array[StringName] = [&"sl_gain", &"sl_flash_a", &"sl_flash_b", &"sl_flash_c", &"sl_flash_plane",
	&"sl_flash_hit"]
## What the material keeps across a shader swap.
const BASE_PARAMETERS: Array[StringName] = [&"tex", &"tint", &"specular_base", &"specular_metal"]

# -- twins of the constants in shader_lights.gdshaderinc (the test compares them) --------------------------------------------

## Engine light units -> this shader's units. Derived from the flash_lab numbers (docs/SHADER_LIGHTS.md, Calibration): with
## Godot's own falloff the PC's real SpotLight3D (7.5, range 16) is 2.1x the plain Lambert term at both the floor and the
## 12 m end wall. Windowed tuning knob: LR_SL_FLASH_GAIN / LR_SL_LAMP_GAIN (no shader edit).
const FLASH_GAIN := 2.1
const LAMP_GAIN := 2.1
const FLASH_DECAY := 1.0
const LAMP_DECAY := 1.6
const STOREY := 4.0
const BAND_OFFSET := 0.05
const CLIP_R := 6.0
const CLIP_FADE := 2.0
const CLIP_LO := -0.5
const CLIP_HI := -0.2

# -- the beam's occluder ------------------------------------------------------------------------------------------------------

## A hit only clips the beam when the surface faces the light this squarely (cos of the angle to the beam axis).
const OCC_MIN_DOT := 0.75
## Colliders skipped (props, hunters, players) before the ray is given up.
const OCC_SKIPS := 4
## A new plane further than this from the current one (m), tilted more than this (cos), or with a hit point further than
## this (m) replaces it at once; smaller changes ease in. A half-way plane between two walls is never drawn.
const PLANE_SNAP_D := 0.35
const PLANE_SNAP_DOT := 0.95
const PLANE_SNAP_HIT := 1.0
const PLANE_EASE := 25.0
const BLOCKER_PARENTS := 3
const DOOR_GROUP := &"room_door"

# -- hand-over of the engine lights --------------------------------------------------------------------------------------------

## Intel's driver whites out any small nearby surface lit by a strong light at ANY energy (flash_lab), and the held
## flashlight model and the props are not shader-lit, so the safe default is that the engine lights contribute nothing in
## this mode. Raise them with LR_SL_SPOT_SCALE / LR_SL_LAMP_CAP once a windowed check shows no white-out.
const DEFAULT_SPOT_SCALE := 0.0
const DEFAULT_LAMP_SCALE := 0.15
const DEFAULT_LAMP_CAP := 0.0
const DEFAULT_FLASH_ENERGY := 7.5
## Cull mask of the engine lights while the shader lights the structure: everything but the structure layers.
const STRUCTURE_FREE_MASK := StoreyLayers.ALL & ~(StoreyLayers.EVEN | StoreyLayers.ODD)

# -- the self-test's decision ---------------------------------------------------------------------------------------------------

enum Verdict { OK, BROKEN, INCONCLUSIVE }
## Ambient-only luma of the probe wall outside this range means the readback is not what we think: inconclusive.
const AMB_MIN := 0.010
const AMB_MAX := 0.20
## The omni (wall 1.5 m away) or the spot (wall 12 m away) must lift the wall by this much above ambient to count as working.
## Measured: PC +0.41 / +0.15, Intel Mac +0.00 / +0.00.
const PASS_OMNI := 0.05
const PASS_SPOT := 0.02
const CACHE_VERSION := 1
## A confirmed fail expires so a driver update is noticed; a pass is keyed by adapter, vendor, api and engine version.
const FAIL_EXPIRY_SECONDS := 3 * 86400

# -- state ----------------------------------------------------------------------------------------------------------------------

## True while the shader draws the lights. Everything else checks this one flag; nothing connects to a signal.
static var enabled := false
## True when this session could ever turn the mode on (macOS auto, or a dev override). Off: materials are not even tracked.
static var armed := false
static var lit_loaded := false
static var spot_scale := DEFAULT_SPOT_SCALE
static var lamp_scale := DEFAULT_LAMP_SCALE
static var lamp_cap := DEFAULT_LAMP_CAP
static var flash_gain := FLASH_GAIN
static var lamp_gain := LAMP_GAIN

static var flash_a := Vector4(0.0, 0.0, 0.0, 16.0)
static var flash_b := Vector4(0.0, 0.0, -1.0, 0.8660254)
static var flash_c := Vector4(0.0, 0.0, 0.0, 1.4)
static var plane := Vector4(0.0, 0.0, 1.0, 0.0)
static var hit := Vector4.ZERO
static var lamp_pos: Array[Vector4] = _zero_slots(1.0)
static var lamp_col: Array[Vector4] = _zero_slots(0.0)

static var _lit: Shader
static var _lit_failed := false
static var _plain: Shader
static var _materials: Array = []          # WeakRef -> ShaderMaterial
static var _flash: WeakRef
static var _flash_owner: WeakRef
static var _flash_orig_energy := DEFAULT_FLASH_ENERGY
static var _flash_orig_mask := StoreyLayers.ALL
static var _flash_touched := false
static var _target_plane := Vector4(0.0, 0.0, 1.0, 0.0)
static var _target_hit := Vector4.ZERO


static func _zero_slots(w: float) -> Array[Vector4]:
	var out: Array[Vector4] = []
	for _i in SLOTS:
		out.append(Vector4(0.0, 0.0, 0.0, w))
	return out


## Back to the boot state (tests; also how a dev switch is undone). Restores the engine lights and the plain shader.
static func reset() -> void:
	if enabled:
		set_enabled(false)
	apply_flashlight()
	enabled = false
	armed = false
	lit_loaded = false
	_lit = null
	_lit_failed = false
	_plain = null
	_materials.clear()
	_flash = null
	_flash_owner = null
	_flash_orig_energy = DEFAULT_FLASH_ENERGY
	_flash_orig_mask = StoreyLayers.ALL
	_flash_touched = false
	spot_scale = DEFAULT_SPOT_SCALE
	lamp_scale = DEFAULT_LAMP_SCALE
	lamp_cap = DEFAULT_LAMP_CAP
	flash_gain = FLASH_GAIN
	lamp_gain = LAMP_GAIN
	flash_a = Vector4(0.0, 0.0, 0.0, 16.0)
	flash_b = Vector4(0.0, 0.0, -1.0, 0.8660254)
	flash_c = Vector4(0.0, 0.0, 0.0, 1.4)
	plane = Vector4(0.0, 0.0, 1.0, 0.0)
	hit = Vector4.ZERO
	_target_plane = plane
	_target_hit = hit
	lamp_pos = _zero_slots(1.0)
	lamp_col = _zero_slots(0.0)


## Dev tuning knobs for the windowed merge-gate check (none changes anything unless the mode is on).
static func apply_env() -> void:
	spot_scale = _env_float("LR_SL_SPOT_SCALE", spot_scale)
	lamp_cap = _env_float("LR_SL_LAMP_CAP", lamp_cap)
	flash_gain = _env_float("LR_SL_FLASH_GAIN", flash_gain)
	lamp_gain = _env_float("LR_SL_LAMP_GAIN", lamp_gain)


static func _env_float(key: String, fallback: float) -> float:
	var text := OS.get_environment(key)
	return text.to_float() if not text.strip_edges().is_empty() and text.is_valid_float() else fallback


# -- shader and materials -------------------------------------------------------------------------------------------------------

## The shader a new chunk-surface material gets. `plain` (ref_surface.gdshader) unless the mode is on AND the lit variant
## loads and looks right; the lit file is never loaded while the mode is off.
static func surface_shader(plain: Shader) -> Shader:
	if not enabled:
		return plain
	var lit := _load_lit()
	return lit if lit != null else plain


static func _load_lit() -> Shader:
	if _lit != null:
		return _lit
	if _lit_failed:
		return null
	lit_loaded = true
	var shader := load(LIT_SHADER_PATH) as Shader
	var include := load(INCLUDE_PATH) as ShaderInclude
	if shader == null or shader.code.is_empty() or not shader.code.contains("sl_emission") \
			or include == null or not include.code.contains("sl_emission"):
		_lit_failed = true
		push_warning("ShaderLights: %s did not load; shader lights stay off" % LIT_SHADER_PATH)
		return null
	_lit = shader
	return _lit


## Called by RefTextures for each chunk-surface material it builds. A no-op unless this session can turn the mode on.
static func register_material(material: ShaderMaterial, plain: Shader) -> void:
	if not armed or material == null:
		return
	_plain = plain
	_prune()
	_materials.append(weakref(material))
	if enabled:
		push_materials()


static func _prune() -> void:
	var keep: Array = []
	for ref in _materials:
		if (ref as WeakRef).get_ref() != null:
			keep.append(ref)
	_materials = keep


static func _live_materials() -> Array[ShaderMaterial]:
	var out: Array[ShaderMaterial] = []
	for ref in _materials:
		var m := (ref as WeakRef).get_ref() as ShaderMaterial
		if m != null:
			out.append(m)
	return out


## Switches the mode. Turning it on needs the lit shader to load; if it does not, the mode stays off. Returns the state.
static func set_enabled(on: bool) -> bool:
	if on == enabled:
		return enabled
	if on:
		var lit := _load_lit()
		if lit == null:
			return false
		enabled = true
		armed = true
		_swap_shader(lit)
		apply_flashlight()
		push_materials()
	else:
		enabled = false
		_swap_shader(_plain)
		_clear_materials()
		apply_flashlight()
		beam_off()
	return enabled


static func _swap_shader(shader: Shader) -> void:
	if shader == null:
		return
	for m in _live_materials():
		if m.shader == shader:
			continue
		var saved := {}
		for key in BASE_PARAMETERS:
			saved[key] = m.get_shader_parameter(key)
		m.shader = shader
		for key in BASE_PARAMETERS:
			if saved[key] != null:
				m.set_shader_parameter(key, saved[key])


static func _clear_materials() -> void:
	for m in _live_materials():
		for key in BEAM_UNIFORMS:
			m.set_shader_parameter(key, null)
		for i in SLOTS:
			m.set_shader_parameter(LAMP_POS_NAMES[i], null)
			m.set_shader_parameter(LAMP_COL_NAMES[i], null)


static func push_materials() -> void:
	for m in _live_materials():
		m.set_shader_parameter(&"sl_gain", Vector2(flash_gain, lamp_gain))
		m.set_shader_parameter(&"sl_flash_a", flash_a)
		m.set_shader_parameter(&"sl_flash_b", flash_b)
		m.set_shader_parameter(&"sl_flash_c", flash_c)
		m.set_shader_parameter(&"sl_flash_plane", plane)
		m.set_shader_parameter(&"sl_flash_hit", hit)
		for i in SLOTS:
			m.set_shader_parameter(LAMP_POS_NAMES[i], lamp_pos[i])
			m.set_shader_parameter(LAMP_COL_NAMES[i], lamp_col[i])


# -- the flashlight -----------------------------------------------------------------------------------------------------------

## The player's SpotLight3D (and the controller, read for flashlight_enabled). Reads and stores only: while the mode is
## off nothing is written to the light. The original energy is taken from the node unless it is 0 (the warm-up renders the
## light at 0 for three frames), in which case the scene's 7.5 is used.
static func register_flashlight(light: Light3D, owner: Object = null) -> void:
	if light == null:
		return
	var again := _flash_node() == light and _flash_touched
	_flash = weakref(light)
	_flash_owner = weakref(owner) if owner != null else null
	if not again:
		_flash_orig_energy = light.light_energy if light.light_energy > 0.0 else DEFAULT_FLASH_ENERGY
		_flash_orig_mask = light.light_cull_mask
		_flash_touched = false
	if enabled:
		apply_flashlight()


static func _flash_node() -> Light3D:
	return _flash.get_ref() as Light3D if _flash != null else null


## Enabled: the engine spot drops to spot_scale x its energy and stops lighting the structure (the shader does). Disabled:
## the original energy and mask come back, and only if the mode was ever on (so a normal device is never written to).
static func apply_flashlight() -> void:
	var light := _flash_node()
	if light == null:
		return
	if enabled:
		light.light_energy = _flash_orig_energy * spot_scale
		light.light_cull_mask = STRUCTURE_FREE_MASK
		_flash_touched = true
	elif _flash_touched:
		light.light_energy = _flash_orig_energy
		light.light_cull_mask = _flash_orig_mask
		_flash_touched = false


static func flash_orig_energy() -> float:
	return _flash_orig_energy


## Per frame, after the controller and the lamp field have run: the beam's uniforms, then the materials.
static func push(delta: float) -> void:
	if not enabled:
		return
	_update_beam(delta)
	push_materials()


static func _update_beam(delta: float) -> void:
	var light := _flash_node()
	if light == null or not light.is_inside_tree():
		beam_off()
		return
	var owner: Object = _flash_owner.get_ref() if _flash_owner != null else null
	var on := light.is_visible_in_tree() and (owner == null or bool(owner.get("flashlight_enabled")))
	if not on:
		beam_off()
		return
	var colour := light.light_color.srgb_to_linear()
	var spot := light as SpotLight3D
	var angle_cos := cos(deg_to_rad(spot.spot_angle)) if spot != null else 0.8660254
	var attenuation := spot.spot_angle_attenuation if spot != null else 1.4
	var reach := spot.spot_range if spot != null else 16.0
	var dir := -light.global_basis.z.normalized()
	flash_a = Vector4(light.global_position.x, light.global_position.y, light.global_position.z, reach)
	flash_b = Vector4(dir.x, dir.y, dir.z, angle_cos)
	var e := _flash_orig_energy
	flash_c = Vector4(colour.r * e, colour.g * e, colour.b * e, attenuation)
	_ease_plane(delta)


## The beam is off: the shader skips it (colour 0) and no clip applies.
static func beam_off() -> void:
	flash_c = Vector4(0.0, 0.0, 0.0, flash_c.w)
	hit.w = 0.0
	_target_hit.w = 0.0


static func _ease_plane(delta: float) -> void:
	if _target_hit.w <= 0.0:
		hit.w = 0.0
		return
	var n_old := Vector3(plane.x, plane.y, plane.z)
	var n_new := Vector3(_target_plane.x, _target_plane.y, _target_plane.z)
	var snap := hit.w <= 0.0 or absf(_target_plane.w - plane.w) > PLANE_SNAP_D or n_old.dot(n_new) < PLANE_SNAP_DOT \
			or Vector3(hit.x, hit.y, hit.z).distance_to(Vector3(_target_hit.x, _target_hit.y, _target_hit.z)) > PLANE_SNAP_HIT
	if snap:
		plane = _target_plane
		hit = _target_hit
		return
	var k := 1.0 - exp(-PLANE_EASE * delta)
	var n := n_old.lerp(n_new, k).normalized()
	var d := lerpf(plane.w, _target_plane.w, k)
	plane = Vector4(n.x, n.y, n.z, d)
	hit = Vector4(lerpf(hit.x, _target_hit.x, k), lerpf(hit.y, _target_hit.y, k), lerpf(hit.z, _target_hit.z, k), 1.0)


# -- the occluder -----------------------------------------------------------------------------------------------------------------

## Walls and closed doors stop the beam; props, hunters and players do not. The structure's colliders are GridMaps; a door
## is a RouteInteractable3D (group room_door) whose barrier body is its child, and its collision is disabled once open.
static func is_blocker(collider: Object) -> bool:
	if collider is GridMap:
		return true
	var node := collider as Node
	for _i in BLOCKER_PARENTS + 1:
		if node == null:
			return false
		if node.is_in_group(DOOR_GROUP):
			return true
		node = node.get_parent()
	return false


## First blocker along the beam, skipping non-blockers; an empty Dictionary when there is none within `length`.
static func cast_beam(space: PhysicsDirectSpaceState3D, origin: Vector3, dir: Vector3, length: float,
		exclude: Array[RID] = []) -> Dictionary:
	var skipped: Array[RID] = []
	skipped.append_array(exclude)
	for _try in OCC_SKIPS + 1:
		var query := PhysicsRayQueryParameters3D.create(origin, origin + dir * length)
		query.exclude = skipped
		query.collision_mask = 1
		var result := space.intersect_ray(query)
		if result.is_empty():
			return {}
		if is_blocker(result["collider"]):
			return result
		skipped.append(result["rid"])
	return {}


## Plane through `pos` with `normal` turned to face the light (a Vector4: xyz = n, w = n . pos).
static func plane_from_hit(dir: Vector3, pos: Vector3, normal: Vector3) -> Vector4:
	var n := normal.normalized()
	if n.dot(-dir) < 0.0:
		n = -n
	return Vector4(n.x, n.y, n.z, n.dot(pos))


## Physics tick: find the wall or closed door the beam lands on. Near-square hits set the target plane; anything else (no
## hit, a skewed one) leaves the beam unclipped.
static func update_occluder(light: Light3D, exclude_rid: RID) -> void:
	_target_hit.w = 0.0
	if light == null or not light.is_inside_tree():
		return
	var spot := light as SpotLight3D
	var length := spot.spot_range if spot != null else 16.0
	var dir := -light.global_basis.z.normalized()
	var origin := light.global_position
	var skip: Array[RID] = [exclude_rid]
	var found := cast_beam(light.get_world_3d().direct_space_state, origin, dir, length, skip)
	if found.is_empty():
		return
	var normal: Vector3 = found["normal"]
	if absf(normal.dot(dir)) < OCC_MIN_DOT:
		return
	var at: Vector3 = found["position"]
	_target_plane = plane_from_hit(dir, at, normal)
	_target_hit = Vector4(at.x, at.y, at.z, 1.0)


static func clear_occluder() -> void:
	_target_hit.w = 0.0


# -- lamps --------------------------------------------------------------------------------------------------------------------------

## LampField, every frame for each pool light: its position, range and linear colour x UNSCALED energy (zero = off). The
## engine light's own energy is lowered afterwards (engine_lamp_energy), so the shader never reads a scaled value back.
static func set_lamp(slot: int, pos: Vector3, lamp_range: float, rgb_energy: Vector3) -> void:
	if slot < 0 or slot >= SLOTS:
		return
	lamp_pos[slot] = Vector4(pos.x, pos.y, pos.z, maxf(lamp_range, 0.001))
	lamp_col[slot] = Vector4(rgb_energy.x, rgb_energy.y, rgb_energy.z, 1.0)


static func lamp_rgb(color: Color, energy: float) -> Vector3:
	var c := color.srgb_to_linear()
	return Vector3(c.r, c.g, c.b) * energy


static func clear_lamps_from(first: int) -> void:
	for i in range(maxi(first, 0), SLOTS):
		lamp_col[i] = Vector4(0.0, 0.0, 0.0, 1.0)


## What the engine light keeps while the shader lights the structure.
static func engine_lamp_energy(energy: float) -> float:
	return minf(energy * lamp_scale, lamp_cap)


## The cull mask for a lamp homed on `level`: StoreyLayers' own while off, structure-free while the shader lights it.
static func light_mask(level: int) -> int:
	return STRUCTURE_FREE_MASK if enabled else StoreyLayers.light_mask(level)


# -- the maths, in GDScript (the shader's twin; the tests hold them together) -------------------------------------------------

static func omni_att(distance: float, light_range: float, decay: float) -> float:
	var nd := distance / light_range
	nd *= nd
	nd *= nd
	nd = maxf(1.0 - nd, 0.0)
	nd *= nd
	return nd * pow(maxf(distance, 0.0001), -decay)


## Cone x range falloff x Lambert N.L of a spot at `pos` pointing along `dir` (energy, colour, gain and clip not applied).
static func spot_factor(wpos: Vector3, wnor: Vector3, pos: Vector3, dir: Vector3, light_range: float,
		cos_cut: float, angle_att: float) -> float:
	var rel := pos - wpos
	var d := rel.length()
	if d >= light_range:
		return 0.0
	var l := rel / maxf(d, 0.0001)
	var scos := maxf((-l).dot(dir), cos_cut)
	var rim := maxf(0.0001, (1.0 - scos) / (1.0 - cos_cut))
	var cone := 1.0 - pow(rim, angle_att)
	return cone * omni_att(d, light_range, FLASH_DECAY) * maxf(wnor.dot(l), 0.0)


static func lamp_factor(wpos: Vector3, wnor: Vector3, pos: Vector3, light_range: float) -> float:
	var rel := pos - wpos
	var d := rel.length()
	if d >= light_range:
		return 0.0
	return omni_att(d, light_range, LAMP_DECAY) * maxf(wnor.dot(rel / maxf(d, 0.0001)), 0.0)


static func smoothstep_f(lo: float, hi: float, x: float) -> float:
	var t := clampf((x - lo) / (hi - lo), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


## 1 = lit, 0 = behind the hit wall; only fragments near the hit point are ever clipped.
static func plane_clip(wpos: Vector3, plane_value: Vector4, hit_value: Vector4) -> float:
	var s := Vector3(plane_value.x, plane_value.y, plane_value.z).dot(wpos) - plane_value.w
	var clip := smoothstep_f(CLIP_LO, CLIP_HI, s)
	var near := 1.0 - smoothstep_f(CLIP_R, CLIP_R + CLIP_FADE, wpos.distance_to(Vector3(hit_value.x, hit_value.y, hit_value.z)))
	return lerpf(1.0, clip, hit_value.w * near)


## The storeys a light reaches: its own parity (StoreyLayers masks the structure of the neighbouring storeys).
static func in_band(y: float, src_y: float) -> bool:
	var ds := floorf((y + BAND_OFFSET) / STOREY) - floorf(src_y / STOREY)
	return posmod(int(ds), 2) == 0


# -- startup self-test: decisions, mode and cache (LightProbe drives them) ---------------------------------------------------------

## OK when either light lifts the wall clearly above its ambient-only luma; BROKEN only when neither does.
static func decide(amb: float, a: float, b: float) -> int:
	if amb < AMB_MIN or amb > AMB_MAX:
		return Verdict.INCONCLUSIVE
	if a - amb >= PASS_OMNI or b - amb >= PASS_SPOT:
		return Verdict.OK
	return Verdict.BROKEN


## From the verdicts so far (oldest first): "done_ok", "done_inconclusive" (nothing is cached), "need_another" (one BROKEN,
## measure again) or "done_broken" (two BROKEN in a row).
static func next_step(history: Array) -> String:
	if history.is_empty():
		return "need_another"
	var last := int(history.back())
	if last == Verdict.OK:
		return "done_ok"
	if last == Verdict.INCONCLUSIVE:
		return "done_inconclusive"
	var run := 0
	for i in range(history.size() - 1, -1, -1):
		if int(history[i]) != Verdict.BROKEN:
			break
		run += 1
	return "done_broken" if run >= 2 else "need_another"


## "off" (the platform or a dev switch says no), "on" (forced), "probe" (run the self-test now, ignoring the cache) or
## "auto" (macOS: use the cache, else run the self-test). Headless, web, XR and phone builds are OFF whatever is forced.
static func resolve_mode(env: String, args: PackedStringArray, ctx: Dictionary) -> String:
	if bool(ctx.get("headless", false)) or bool(ctx.get("web", false)) or bool(ctx.get("xr", false)) \
			or bool(ctx.get("phone", false)):
		return "off"
	if args.has("--no-shader-lights"):
		return "off"
	if args.has("--shader-lights"):
		return "on"
	match env.strip_edges().to_lower():
		"1", "on", "true":
			return "on"
		"0", "off", "false":
			return "off"
		"probe":
			return "probe"
	if args.has("--light-probe"):
		return "probe"
	if args.has("--no-light-probe"):
		return "off"
	return "auto" if bool(ctx.get("macos", false)) else "off"


## Auto mode only probes a GPU that can be the legacy driver: a known Apple GPU (M-series, A-series) passes, and an empty
## adapter name (headless, dummy renderer) has nothing to measure.
static func auto_probe_allowed(adapter: String, vendor: String) -> bool:
	if adapter.strip_edges().is_empty():
		return false
	return not (adapter.to_lower().contains("apple") or vendor.to_lower().contains("apple"))


static func cache_key(adapter: String, vendor: String, api: String, engine: String) -> Dictionary:
	return {"adapter": adapter, "vendor": vendor, "api": api, "engine": engine}


static func cache_entry(key: Dictionary, ok: bool, strikes: int, now: int) -> Dictionary:
	var entry := key.duplicate()
	entry["v"] = CACHE_VERSION
	entry["ok"] = ok
	entry["strikes"] = 0 if ok else strikes
	entry["confirmed"] = (not ok) and strikes >= 2
	entry["checked_unix"] = now
	return entry


static func _same_key(entry: Dictionary, key: Dictionary) -> bool:
	if int(entry.get("v", 0)) != CACHE_VERSION:
		return false
	for field in ["adapter", "vendor", "api", "engine"]:
		if String(entry.get(field, "")) != String(key.get(field, "")):
			return false
	return true


## A pass for this exact adapter/vendor/api/engine, or a CONFIRMED fail younger than FAIL_EXPIRY_SECONDS. Anything else
## (a mismatch, an unconfirmed strike, an old fail, a corrupt file) is a miss and the self-test runs again.
static func cache_valid(entry: Dictionary, key: Dictionary, now: int) -> bool:
	if entry.is_empty() or not _same_key(entry, key):
		return false
	if bool(entry.get("ok", false)):
		return true
	if not bool(entry.get("confirmed", false)):
		return false
	return now - int(entry.get("checked_unix", 0)) < FAIL_EXPIRY_SECONDS and now >= int(entry.get("checked_unix", 0))


## Earlier BROKEN launches for this key that have not expired (the next BROKEN is strike strikes + 1).
static func cache_strikes(entry: Dictionary, key: Dictionary, now: int) -> int:
	if entry.is_empty() or not _same_key(entry, key) or bool(entry.get("ok", true)):
		return 0
	if now - int(entry.get("checked_unix", 0)) >= FAIL_EXPIRY_SECONDS:
		return 0
	return maxi(int(entry.get("strikes", 0)), 0)


static func read_cache(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return {}   # corrupt: a miss
	return json.data as Dictionary if json.data is Dictionary else {}


## Temp file, then rename: a crash mid-write never leaves a half file that reads as a verdict.
static func write_cache(path: String, entry: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(entry))
	file.close()
	return DirAccess.rename_absolute(tmp, path) == OK
