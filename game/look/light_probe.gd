extends Node

## Startup self-test for the engine light path, and the owner of ShaderLights' per-frame push (docs/SHADER_LIGHTS.md).
##
## Apple's legacy OpenGL driver (Intel Macs) lights nothing beyond about a metre. On a macOS desktop build whose GPU is not a
## known Apple GPU, a tiny off-screen corridor is rendered with one omni light and one spot at the flashlight's energy and
## range; if neither lifts a plain wall above its ambient luma, twice in a row, the surfaces switch to ShaderLights. The
## verdict is cached in user://light_probe.json (keyed by adapter, vendor, api and engine version) so later launches skip
## the test; a fail is written as a strike and only trusted (confirmed) from the second launch that sees it.
##
## Everything else is OFF and does nothing: headless, web, XR and phone builds, and every non-macOS desktop unless forced.
##
##   LR_SHADER_LIGHTS=1 | --shader-lights      force the shader lights ON on any desktop (compare against the engine picture)
##   LR_SHADER_LIGHTS=0 | --no-shader-lights   force them OFF (also skips the self-test)
##   LR_SHADER_LIGHTS=probe | --light-probe    run the self-test now on any desktop, ignoring the cache
##   --no-light-probe                          never run the self-test (auto mode stays off)
##   delete user://light_probe.json            forget the cached verdict

const CACHE_PATH := "user://light_probe.json"
## Frames each phase renders before it is read, and the pause before a confirming measurement.
const WAIT_FRAMES := 12
const BOOT_DELAY := 2.0
const CONFIRM_DELAY := 1.5
const VIEW_SIZE := Vector2i(64, 36)
const PROBE_ENERGY := 7.5
const PROBE_RANGE := 16.0
const OMNI_WALL := 1.5
const SPOT_WALL := 12.0
const AMBIENT := 0.035
const SPOT_OFFSET := Vector3(0.08, -0.05, -0.12)

var cache_path := CACHE_PATH
var mode := "off"
var last_result := {}

var _view: SubViewport
var _wall: MeshInstance3D
var _omni: OmniLight3D
var _spot: SpotLight3D


func _ready() -> void:
	process_priority = 1000   # after the player and the LampField have written this frame's lights
	set_process(false)
	ShaderLights.apply_env()
	var ctx := context()
	mode = ShaderLights.resolve_mode(OS.get_environment("LR_SHADER_LIGHTS"), OS.get_cmdline_user_args(), ctx)
	match mode:
		"on":
			ShaderLights.armed = true
			ShaderLights.set_enabled(true)
			_sync_process()
			print("LightProbe: forced ON (adapter=%s)" % ctx["adapter"])
		"probe":
			ShaderLights.armed = true
			_start_probe.call_deferred(false)
		"auto":
			_auto(ctx)


static func context() -> Dictionary:
	return {
		"headless": DisplayServer.get_name() == "headless",
		"web": OS.has_feature("web"),
		"xr": PlatformProfile.is_xr,
		"phone": PlatformProfile.is_phone,
		"macos": OS.get_name() == "macOS",
		"adapter": RenderingServer.get_video_adapter_name(),
		"vendor": RenderingServer.get_video_adapter_vendor(),
		"api": RenderingServer.get_video_adapter_api_version(),
	}


func current_key() -> Dictionary:
	var ctx := context()
	return ShaderLights.cache_key(String(ctx["adapter"]), String(ctx["vendor"]), String(ctx["api"]),
		String(Engine.get_version_info().get("string", "")))


func _auto(ctx: Dictionary) -> void:
	if not ShaderLights.auto_probe_allowed(String(ctx["adapter"]), String(ctx["vendor"])):
		return   # a known Apple GPU (or nothing to measure): passes, stays OFF, writes nothing
	ShaderLights.armed = true
	var key := current_key()
	var entry := ShaderLights.read_cache(cache_path)
	var now := int(Time.get_unix_time_from_system())
	if ShaderLights.cache_valid(entry, key, now):
		var ok := bool(entry.get("ok", true))
		ShaderLights.set_enabled(not ok)
		_sync_process()
		print("LightProbe: cached adapter=%s api=%s result=%s" % [key["adapter"], key["api"], "ok" if ok else "BROKEN (shader lights on)"])
		return
	_start_probe.call_deferred(true)


func _sync_process() -> void:
	set_process(ShaderLights.enabled)


func _process(delta: float) -> void:
	ShaderLights.push(delta)


# -- the measurement ----------------------------------------------------------------------------------------------------------------

func _start_probe(delayed: bool) -> void:
	if delayed:
		await get_tree().create_timer(BOOT_DELAY).timeout   # not in the middle of boot or the first streamed frames
	var key := current_key()
	var prior := ShaderLights.cache_strikes(ShaderLights.read_cache(cache_path), key, int(Time.get_unix_time_from_system()))
	var run := await run_cycles(Callable(self, "_measure_real"), Callable(self, "_pause"))
	_free_view()
	finish(run, key, prior)


func _pause() -> void:
	await get_tree().create_timer(CONFIRM_DELAY).timeout


## The probe's control loop with its two outside effects injected, so a test can drive it: `measure(cycle)` returns
## {amb, a, b} (it may be a coroutine) and `pause()` runs between a BROKEN reading and its confirmation.
## Returns {history, step, readings}.
func run_cycles(measure: Callable, pause: Callable) -> Dictionary:
	var history: Array = []
	var readings: Array = []
	var step := "need_another"
	for cycle in 4:
		var r: Dictionary = await measure.call(cycle)
		readings.append(r)
		history.append(ShaderLights.decide(float(r.get("amb", -1.0)), float(r.get("a", -1.0)), float(r.get("b", -1.0))))
		step = ShaderLights.next_step(history)
		if step != "need_another":
			break
		await pause.call()
	if step == "need_another":
		step = "done_inconclusive"   # cannot happen (two readings settle it) but never leave a verdict open
	return {"history": history, "step": step, "readings": readings}


## Applies and caches a finished run. OK: cached as a pass, shader lights off. Two BROKEN in a row: shader lights ON for
## this session, written as one more strike (confirmed from the second). Inconclusive: nothing written, nothing changes.
func finish(run: Dictionary, key: Dictionary, prior_strikes: int) -> Dictionary:
	var step := String(run["step"])
	var now := int(Time.get_unix_time_from_system())
	var wrote := false
	var strikes := 0
	match step:
		"done_ok":
			ShaderLights.set_enabled(false)
			wrote = ShaderLights.write_cache(cache_path, ShaderLights.cache_entry(key, true, 0, now))
		"done_broken":
			strikes = prior_strikes + 1
			wrote = ShaderLights.write_cache(cache_path, ShaderLights.cache_entry(key, false, strikes, now))
			ShaderLights.set_enabled(true)
	_sync_process()
	var last: Dictionary = (run["readings"] as Array).back() if not (run["readings"] as Array).is_empty() else {}
	last_result = {"step": step, "wrote": wrote, "strikes": strikes, "enabled": ShaderLights.enabled}
	print("LightProbe: adapter=%s api=%s amb=%.3f A=%.3f B=%.3f result=%s cached=%s" % [key["adapter"], key["api"],
		float(last.get("amb", -1.0)), float(last.get("a", -1.0)), float(last.get("b", -1.0)), step, str(wrote)])
	return last_result


func _measure_real(cycle: int) -> Dictionary:
	_ensure_view()
	var frames := WAIT_FRAMES * (1 + cycle)
	_phase(false, false, OMNI_WALL)
	await _frames(frames)
	var amb := _centre_luma()
	_phase(true, false, OMNI_WALL)
	await _frames(frames)
	var a := _centre_luma()
	_phase(false, true, SPOT_WALL)
	await _frames(frames)
	var b := _centre_luma()
	return {"amb": amb, "a": a, "b": b}


func _frames(count: int) -> void:
	for _i in count:
		await RenderingServer.frame_post_draw


func _phase(omni: bool, spot: bool, wall_distance: float) -> void:
	_omni.visible = omni
	_spot.visible = spot
	_wall.position = Vector3(0.0, 0.0, -wall_distance)


func _ensure_view() -> void:
	if _view != null:
		return
	_view = SubViewport.new()
	_view.size = VIEW_SIZE
	_view.own_world_3d = true
	_view.transparent_bg = false
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = AMBIENT
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	_view.add_child(world_env)
	var cam := Camera3D.new()
	cam.fov = 75.0
	cam.current = true
	_view.add_child(cam)
	_wall = MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(12.0, 12.0)
	_wall.mesh = plane_mesh
	_wall.rotation_degrees = Vector3(90.0, 0.0, 0.0)   # the plane faces +Y; stand it up so it faces the camera
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.8, 0.15, 0.15)
	material.roughness = 0.8
	_wall.material_override = material
	_view.add_child(_wall)
	_omni = OmniLight3D.new()
	_omni.light_energy = PROBE_ENERGY
	_omni.omni_range = PROBE_RANGE
	_omni.position = SPOT_OFFSET
	_omni.visible = false
	_view.add_child(_omni)
	_spot = SpotLight3D.new()
	_spot.light_energy = PROBE_ENERGY
	_spot.spot_range = PROBE_RANGE
	_spot.spot_angle = 30.0
	_spot.spot_angle_attenuation = 1.4
	_spot.position = SPOT_OFFSET
	_spot.visible = false
	_view.add_child(_spot)
	get_tree().root.add_child(_view)


func _free_view() -> void:
	if _view != null:
		_view.queue_free()
		_view = null


## Mean luma of the centre 12 x 12 pixels; -1 when the image cannot be read (counted as inconclusive).
func _centre_luma() -> float:
	var img := _view.get_texture().get_image() if _view != null else null
	if img == null or img.is_empty() or img.get_size() != VIEW_SIZE:
		return -1.0
	var sum := 0.0
	var n := 0
	var origin := (VIEW_SIZE - Vector2i(12, 12)) / 2
	for y in 12:
		for x in 12:
			sum += img.get_pixel(origin.x + x, origin.y + y).get_luminance()
			n += 1
	return sum / float(n)
