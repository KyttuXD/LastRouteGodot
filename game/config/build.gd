class_name Build
extends RefCounted

## Manually controlled release identifier. Keep this unchanged during unrelated
## work; only change it when the user explicitly asks to change or bump it.
const VERSION := "0.0.1.0"
const REVISION_PATH := "res://build_revision.json"
const SOURCE_REVISION := "source"

static var _revision_cache := ""
static var _build_number_cache := -1

## What this build is allowed to show the player.
##
## The web version carries developer instrumentation -- an FPS readout, the
## memory-map overlay, the radar -- that is genuinely useful while building the
## game and has no business in a normal one: it hands out hunter positions and
## tells the player things the mode is built around not knowing.
##
## The rule is that developer UI is opt-IN and defaults to off, rather than
## something to remember to strip before shipping. An exported release build
## reports false here whatever anyone forgot, and the editor reports true, so
## the tools are there while working and gone when not.
##
## Anything that reveals state the player is supposed to be uncertain about
## goes behind `tools_enabled()`. Ordinary features that happen to be handy
## (the maze's own memory map, which is an item the player earns) do not --
## those are gameplay.


## Player-facing builds never receive tools merely because they are debug
## exports. The primary server must authenticate an owner (KYTTU/AYTTU) or a
## scoped roster member during this process; a display name or edited
## ConfigFile is never enough. Headless validation keeps a non-interactive
## exception so CI can exercise the otherwise gated controls.
static func tools_enabled() -> bool:
	return Backend.admin_authorized() or _headless_validation()


static func admin_permission(permission: String) -> bool:
	return _headless_validation() or Backend.admin_has_permission(permission)


static func admin_owner_tools_enabled() -> bool:
	return _headless_validation() or Backend.admin_owner_authorized()


## A release host cannot trust a boolean or display name supplied by another
## ENet peer as proof of admin access. Player-facing debug and release rooms
## both require a short-lived, room-bound proof from the primary backend.
## Only non-interactive headless validation bypasses that network dependency.
static func remote_guest_tools_allowed() -> bool:
	return _headless_validation()


## Set by dev/look/admin_capture.gd only: the screenshot rig has a window (so it is not "headless") but must draw the
## admin panel without a live login. Debug builds only, never reachable from the UI or the command line.
static var capture_rig := false


## Validators set this to see what a player WITHOUT admin sees (the headless exception would otherwise grant everything).
static var deny_admin_for_test := false


static func _headless_validation() -> bool:
	if deny_admin_for_test:
		return false
	return OS.is_debug_build() and (DisplayServer.get_name() == "headless" or capture_rig)


## Whether to draw the frame counter and other always-on readouts.
static func show_diagnostics() -> bool:
	return tools_enabled()


## Whether debug views that would spoil a run -- hunter positions, the full
## facility layout, threat timers -- may be opened at all.
static func allow_spoiler_views() -> bool:
	return tools_enabled()


static func update_channel() -> String:
	# An authenticated release admin is still running a release build.
	return "debug" if OS.is_debug_build() else "release"


## Git commit embedded by tools/build/export_test_builds.sh. Editor/source runs do
## not have the generated file and deliberately identify as "source".
static func revision() -> String:
	if not _revision_cache.is_empty():
		return _revision_cache
	_revision_cache = SOURCE_REVISION
	if not FileAccess.file_exists(REVISION_PATH):
		return _revision_cache
	var file := FileAccess.open(REVISION_PATH, FileAccess.READ)
	if file == null:
		return _revision_cache
	var parsed = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		var candidate := String(parsed.get("revision", "")).strip_edges().to_lower()
		if _valid_revision(candidate):
			_revision_cache = candidate
	return _revision_cache


## The publish build number (git rev-list --count of the commit, also the Android versionCode; written beside the
## revision by tools/android/build_apk.sh PUBLISH=1). 0 for source runs and unstamped exports.
static func build_number() -> int:
	if _build_number_cache >= 0:
		return _build_number_cache
	_build_number_cache = 0
	if FileAccess.file_exists(REVISION_PATH):
		var file := FileAccess.open(REVISION_PATH, FileAccess.READ)
		if file != null:
			var parsed = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_build_number_cache = maxi(0, int(parsed.get("build", 0)))
	return _build_number_cache


static func short_revision() -> String:
	var value := revision()
	return value.left(8) if value != SOURCE_REVISION else value


## Only exported debug builds fail closed on an unavailable update service.
## Editor runs stay usable while the developer is changing the backend.
## BETA builds (export presets "* Beta", custom feature `beta`): play-test builds that talk to the PRODUCTION server
## (public route/rooms) and never wait for an update. They change no version information.
static func is_beta() -> bool:
	return OS.has_feature("beta")


static func requires_update_gate() -> bool:
	# TEST SERVER builds (run_multi / export_test_multiplayer) are play-test builds: they never wait for an update.
	if OS.has_feature("test_server") or OS.has_feature("web") or is_beta():
		return false
	return OS.is_debug_build() and revision() != SOURCE_REVISION


static func _valid_revision(value: String) -> bool:
	if value.length() < 7 or value.length() > 40:
		return false
	for character in value:
		if not "0123456789abcdef".contains(character):
			return false
	return true
