extends Node

## Which device class the game runs on, and the budgets that follow from it (docs/XR_ANDROID.md). Read once at boot.
## Desktop is the reference: every value here equals what the game did before this file existed, so a desktop build
## behaves identically. Phones (Android flat) and XR headsets get smaller budgets; gameplay, networking and saves never
## branch on the platform, only presentation, input and budgets do.
##
##   --touch     force the phone profile and touch controls on any build (testing on desktop)
##   --xr        handled by PlayerController3D (OpenXR); the profile only reads it
##   --lowmem    force the low-memory budget

## Emitted by flush_saves (quitting, or the app going to the background): anything holding unsaved state saves now.
signal saves_flushed

## A flat Android phone or tablet (touch controls, phone UI scale).
var is_phone := false
## An XR export or `--xr` (OpenXR headset; the player rig decides whether it actually started).
var is_xr := false
## The Meta Quest standalone export.
var is_quest := false
## Little RAM (phones at or under LOW_MEMORY_BYTES): ladder trips rebuild the other storey instead of keeping it parked.
var low_memory := false

## Desktop values (the reference): lamps the LampField moves onto the nearest sources, first-person camera far plane
## (0 = leave the scene's value), whether linked storeys are pre-built and parked.
var lamp_pool := 8
var camera_far := 0.0
var prebuild_linked_levels := true
## Phones start with the pixel post effect off (a full-screen pass costs too much on mobile GPUs).
var default_pixel_effect_percent := -1.0
## Streaming per-frame time budget (StreamedFacilityView3D.STREAM_BUDGET_MS / _MAX_MS on desktop) and the on-device
## frame log (PerfLog, user://perf). Mobile GPUs share the frame with a slower CPU: smaller build slices.
var stream_budget_ms := 4.0
var stream_budget_max_ms := 9.0
## Right after a level change or teleport, while the runner's own storey is still streaming in (StreamedFacilityView3D).
## Slow machines get the most: a few slower frames at a hop beat seconds of missing walls (an Air built ~5 ms a frame).
var stream_budget_burst_ms := 14.0
var perf_log := false
## Device quality tier (QualityTier): detected from the hardware at boot, or forced by Settings GRAPHICS. In AUTO the
## QualityGovernor gives up notches live when the frame target is missed and takes one back after a long clean stretch.
var specs := {}
var detected_tier := QualityTier.Tier.HIGH
var tier := QualityTier.Tier.HIGH
var graphics_auto := true
var notch := 0
var shadows := true
var prop_range_scale := 1.0
var prerender_ambience := true
## Minimap redraws per second (0 = every frame, the HIGH reference).
var map_update_hz := 0.0
## 3D render resolution scale (a phone governor's last notch; flat screens only: an XR swapchain is sized at session start).
var render_scale := 1.0
## HiDPI (Retina) desktops: the canvas stretch renders 3D at the window's physical pixels, 4x the pixels of the same
## window on a 1x screen. 3D renders at logical resolution instead (the art is low-res pixels); 1.0 on 1x screens.
var hidpi_scale := 1.0
## Share of pure-dressing props (no collider, no interaction) and of wall extras (pipes, cables, frames) that spawn.
var prop_density := 1.0
var decor_density := 1.0
## Maze culling (StreamedFacilityView3D): hide prop visuals and 15 x 15 surface tiles no open line of sight can reach.
## Opt-in while it is measured (`--cull` or MAZE_CULLING=1).
var maze_culling := (OS.get_environment("MAZE_CULLING") == "1" or OS.get_cmdline_user_args().has("--cull")) \
	and not OS.get_cmdline_user_args().has("--no-cull")
var frame_target_hz := 60.0
var worker_threads := 1
var governor: QualityGovernor
var _refresh_seen := 0.0
signal budgets_changed

const LOW_MEMORY_BYTES := 4_800_000_000
const PHONE_LAMP_POOL := 4
const PHONE_CAMERA_FAR := 140.0
const QUEST_LAMP_POOL := 4
const QUEST_CAMERA_FAR := 60.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	is_xr = OS.has_feature("xr") or args.has("--xr")
	is_quest = OS.has_feature("quest")
	is_phone = (OS.has_feature("mobile") and not is_xr) or args.has("--touch")
	var physical := int(OS.get_memory_info().get("physical", 0))
	low_memory = args.has("--lowmem") or (is_phone and physical > 0 and physical <= LOW_MEMORY_BYTES)
	specs = QualityTier.detect()
	detected_tier = QualityTier.score(specs)
	tier = detected_tier
	if not is_phone and not is_xr and DisplayServer.get_name() != "headless" and not OS.has_feature("web") and DisplayServer.screen_get_scale() > 1.01 \
			and not args.has("--no-hidpi-scale"):
		hidpi_scale = 1.0 / DisplayServer.screen_get_scale()
	governor = QualityGovernor.new()
	governor.name = "QualityGovernor"
	apply_budgets()
	for arg in args:
		if String(arg).begins_with("--graphics="):   # benchmarks: force a tier (LOW / MEDIUM / HIGH; ULTRA means HIGH, AUTO = detect). Never saved.
			set_graphics_quality.call_deferred(String(arg).trim_prefix("--graphics="))
	governor.notch_changed.connect(_on_notch_changed)
	if hidpi_scale < 1.0:
		_apply_live.call_deferred()
	add_child(governor)
	get_tree().node_added.connect(_on_node_added)
	if not is_phone and not is_xr and DisplayServer.get_name() != "headless":
		# the refresh rate caps the governor target; the monitor can change (a window dragged to another screen), so poll slowly
		var refresh_timer := Timer.new()
		refresh_timer.name = "RefreshPoll"
		refresh_timer.wait_time = 2.0
		refresh_timer.autostart = true
		refresh_timer.timeout.connect(func() -> void: set_display_refresh(DisplayServer.screen_get_refresh_rate()))
		add_child(refresh_timer)
	if prerender_ambience and DisplayServer.get_name() != "headless":
		# every district and level bed renders on the worker pool at boot, so entering one never waits for it
		for key in AmbienceTable.regions() + AmbienceTable.levels():
			Sound.prerender_ambience.call_deferred(String(key))
	PerfLog.install(get_tree().root, perf_log or args.has("--perflog"))
	# overlay installs quietly; it only paints when admin pref is on.
	var _perf_root := get_tree().root
	if _perf_root.get_node_or_null("PerfOverlay") == null:
		var _perf_overlay: Node = (load("res://game/hud/perf_overlay.gd") as GDScript).new()
		_perf_overlay.name = "PerfOverlay"
		_perf_root.add_child.call_deferred(_perf_overlay)
	if is_phone or is_quest:
		# A run must not dim and lock the screen while the runner is standing still in a locker.
		DisplayServer.screen_set_keep_on(true)
	if is_xr:
		# The menus are 2D: with OpenXR running, show them on a floating panel (XRMenuPanel) until a route takes over.
		XRMenuPanel.attach.call_deferred(self)


## The budgets for the current tier and notch (also called by the platform validator on a fresh instance with faked
## flags, which has no detected specs: desktop is then the HIGH reference, phones MEDIUM, low-memory phones LOW).
func apply_budgets() -> void:
	var tier_specs := specs.duplicate()
	if tier_specs.is_empty():
		tier_specs = {"phone": is_phone, "quest": is_quest, "xr": is_xr, "cores": 8,
			"ram_bytes": 4 * QualityTier.GB if low_memory else 8 * QualityTier.GB}
		tier = QualityTier.score(tier_specs) if (is_phone or is_quest) else QualityTier.Tier.HIGH
	tier_specs["fps_limit"] = Settings.fps_limit   # a player cap below the tier target is not a miss
	var base_budgets := QualityTier.budgets(tier, tier_specs)
	var budgets := QualityGovernor.degrade(base_budgets, notch)
	stream_budget_ms = budgets["stream_budget_ms"]
	stream_budget_max_ms = budgets["stream_budget_max_ms"]
	stream_budget_burst_ms = float(budgets.get("stream_budget_burst_ms", stream_budget_max_ms))
	prebuild_linked_levels = bool(budgets["prebuild_linked_levels"]) and not low_memory
	lamp_pool = budgets["lamp_pool"]
	# Desktop HIGH only (its governor can drop them as the last notch). MEDIUM, LOW, and AUTO at MEDIUM or below leave them off.
	shadows = budgets["shadows"]
	camera_far = budgets["camera_far"]
	prop_range_scale = budgets["prop_range_scale"]
	prerender_ambience = budgets["prerender_ambience"]
	map_update_hz = budgets["map_update_hz"]
	render_scale = budgets["render_scale"]
	prop_density = budgets["prop_density"]
	decor_density = budgets["decor_density"]
	frame_target_hz = budgets["frame_target_hz"]
	worker_threads = budgets["worker_threads"]
	if governor != null:
		governor.target_ms = 1000.0 / frame_target_hz
		governor.max_notch = QualityGovernor.notches_for(base_budgets)
	if is_phone:
		default_pixel_effect_percent = 0.0
	if is_quest or is_phone:
		perf_log = true


## Settings GRAPHICS: "AUTO" (detected tier, live governor) or a fixed LOW / MEDIUM / HIGH. Reads the choice through
## QualityTier.canonical, so the retired "ULTRA" means HIGH and anything unknown means AUTO. A preset change resets the
## governor (its history describes different settings). Never saves.
func set_graphics_quality(choice: String) -> void:
	var fixed := QualityTier.from_name(choice)
	graphics_auto = fixed < 0
	tier = detected_tier if graphics_auto else fixed
	notch = 0
	if governor != null:
		governor.enabled = graphics_auto
		governor.reset()
	apply_budgets()
	_apply_live()
	budgets_changed.emit()


## The monitor's refresh rate caps the governor target. Polled every couple of seconds; a new value counts only after two
## consecutive equal polls (a window dragged between screens reports odd values for a moment). hz <= 0 means unknown.
func set_display_refresh(hz: float) -> void:
	if hz <= 0.0:
		_refresh_seen = 0.0
		return
	if specs.is_empty():
		return
	var stable := is_equal_approx(hz, _refresh_seen)
	_refresh_seen = hz
	if stable and not is_equal_approx(hz, float(specs.get("refresh", 0.0))):
		specs["refresh"] = hz
		apply_budgets()


func _on_notch_changed(value: int) -> void:
	notch = value
	apply_budgets()
	_apply_live()
	budgets_changed.emit()


## Budgets that can change mid-run: the camera far plane and shadow-casting lights. Streaming budgets are read every
## frame; lamp pool, prop ranges and pre-building apply to what streams in next.
func _apply_live() -> void:
	if Settings.fps_limit <= 0:
		Engine.max_fps = default_fps_cap()
	var viewport := get_viewport()
	if viewport != null and not is_xr:
		viewport.scaling_3d_scale = render_scale * hidpi_scale
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera != null:
		if not camera.has_meta("tier_base_far"):
			camera.set_meta("tier_base_far", camera.far)
		camera.far = camera_far if camera_far > 0.0 else float(camera.get_meta("tier_base_far"))
	for node in get_tree().root.find_children("*", "Light3D", true, false):
		var light := node as Light3D
		if not light.has_meta("tier_shadow"):
			light.set_meta("tier_shadow", light.shadow_enabled)
		light.shadow_enabled = bool(light.get_meta("tier_shadow")) and shadows


## Lights created after a tier without shadows was applied (hunter beams, remote players' lamps) start without them.
func _on_node_added(node: Node) -> void:
	if not shadows and node is Light3D:
		var light := node as Light3D
		if not light.has_meta("tier_shadow"):
			light.set_meta("tier_shadow", light.shadow_enabled)
		light.set_deferred("shadow_enabled", false)


## The frame rate a device can hold when the player sets no limit: phones 60, the Quest its fixed 72 (desktop: none).
func default_fps_cap() -> int:
	if is_quest:
		return 72
	if is_phone:
		return 60
	return 0


func tier_readout() -> String:
	return "%s%s (detected %s%s)" % [QualityTier.name_of(tier), " -%d" % notch if notch > 0 else "",
		QualityTier.name_of(detected_tier), ", auto" if graphics_auto else ""]


## Whether the app can offer a QUIT button. iOS apps may not terminate themselves (the user swipes them away) and a
## web build has no desktop to return to, so both hide it.
func can_quit() -> bool:
	return quit_allowed(OS.has_feature("ios"), OS.has_feature("web"))


static func quit_allowed(ios: bool, web: bool) -> bool:
	return not ios and not web


## Leaves the app: saves first (flush_saves), ends the OpenXR session on a headset so it returns cleanly to the home
## environment, then quits. On Android get_tree().quit() finishes the activity. Desktop behaves as before. `quit` replaces
## the final step (the platform validator checks the order without leaving).
func quit_app(quit := Callable()) -> void:
	flush_saves()
	await RoomState.close_room_for_quit()   # a hosting player closes their room (guests -> main menu) before the app ends
	await UpdateManager.apply_on_exit()   # a downloaded update is swapped in as the game exits
	if is_xr:
		var openxr := XRServer.find_interface("OpenXR")
		if openxr != null and openxr.is_initialized():
			get_tree().root.use_xr = false
			openxr.uninitialize()
	if quit.is_valid():
		quit.call()
	else:
		get_tree().quit()


## Writes everything that is kept between launches. Called before quitting and when a phone or headset sends the app
## to the background (iOS may then end it without notice).
func flush_saves() -> void:
	Settings.call("_save")
	saves_flushed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		flush_saves()


## One line for logs and the debug overlay.
func summary() -> String:
	return "%s%s%s%s lamps %d far %s prebuild %s shadows %s" % [
		"PHONE " if is_phone else "", "QUEST " if is_quest else ("XR " if is_xr else ""),
		"LOWMEM " if low_memory else "", tier_readout() + " ", lamp_pool, str(camera_far) if camera_far > 0.0 else "scene",
		"on" if prebuild_linked_levels else "off", "on" if shadows else "off"]
