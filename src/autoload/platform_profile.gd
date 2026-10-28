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
	apply_budgets()
	if is_phone or is_quest:
		# A run must not dim and lock the screen while the runner is standing still in a locker.
		DisplayServer.screen_set_keep_on(true)
	if is_xr:
		# The menus are 2D: with OpenXR running, show them on a floating panel (XRMenuPanel) until a route takes over.
		XRMenuPanel.attach.call_deferred(self)


## The budgets for the detected class (also called by the platform validator on a fresh instance with faked flags).
func apply_budgets() -> void:
	if is_quest:
		lamp_pool = QUEST_LAMP_POOL
		camera_far = QUEST_CAMERA_FAR
		prebuild_linked_levels = false
	elif is_phone:
		lamp_pool = PHONE_LAMP_POOL
		camera_far = PHONE_CAMERA_FAR
		default_pixel_effect_percent = 0.0
		prebuild_linked_levels = not low_memory


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
	return "%s%s%s lamps %d far %s prebuild %s" % [
		"PHONE " if is_phone else "", "QUEST " if is_quest else ("XR " if is_xr else ""),
		"LOWMEM " if low_memory else "", lamp_pool, str(camera_far) if camera_far > 0.0 else "scene",
		"on" if prebuild_linked_levels else "off"]
