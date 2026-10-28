extends RefCounted

## The update gate: with an update available the player stays on the update screen (only INSTALL & RESTART, or RETRY after a
## failure; no CONTINUE / CONTINUE OFFLINE) and the hub never opens; when the server is unreachable the boot screen falls
## through to the menu in offline mode; iOS and the web build never block.
##
##   godot --headless --path . res://scenes/validate.tscn -- update_gate

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var saved_available := UpdateManager.available.duplicate(true)
	var saved_offline := UpdateManager.offline_mode
	var opened := [0]
	UpdateManager.gate_override = func() -> void: opened[0] += 1
	for key in ["macos", "windows", "phone", "quest"]:
		_expect(UpdateManager.gated_platform(key), "%s is not held on the update screen" % key)
	for key in ["ios", "web"]:
		_expect(not UpdateManager.gated_platform(key), "%s must never be blocked by the update gate" % key)
	# a newer build is available, for a stamped build (the hard gate)
	UpdateManager.build_number_override = 700
	UpdateManager.offline_mode = false
	UpdateManager.available = {"revision": "b".repeat(40), "build": 999, "sha256": "e".repeat(64), "url": "https://x/y.zip"}
	if UpdateManager.uses_in_progress_screen() and not UpdateManager.is_dev_build():
		_expect(UpdateManager.should_open_progress_screen(), "an available update does not hold the player")
		# the boot screen goes to the update screen, never the menu
		var boot := (load("res://scenes/boot_loading.tscn") as PackedScene).instantiate()
		boot.set("auto_start", false)
		host.add_child(boot)
		await host.get_tree().process_frame
		boot.call("_on_update_check_finished", true, true)
		_expect(opened[0] >= 1 and not bool(boot.get("_may_open_menu")), "boot let the menu open with an update available")
		boot.queue_free()
		# the hub refuses to open
		opened[0] = 0
		var hub := (load("res://scenes/game_hub.tscn") as PackedScene).instantiate()
		host.add_child(hub)
		await host.get_tree().process_frame
		_expect(opened[0] == 1 and hub.find_child("HubCarousel", true, false) == null, "the hub opened with an update available")
		hub.queue_free()
		# the update screen: install only, no way to skip
		var screen := (load("res://scenes/update_progress.tscn") as PackedScene).instantiate()
		screen.set("auto_start", false)
		host.add_child(screen)
		await host.get_tree().process_frame
		screen.call("_show_install_button")
		var cont := screen.find_child("ContinueOfflineButton", true, false) as Button
		var install := screen.find_child("InstallUpdateButton", true, false) as Button
		_expect(install != null and install.visible, "the update screen has no INSTALL & RESTART")
		_expect(cont == null or not cont.visible, "the update screen offers CONTINUE")
		screen.call("_show_retry", "UPDATE DOWNLOAD FAILED // RETRY")
		var retry := screen.find_child("RetryUpdateButton", true, false) as Button
		_expect(retry != null and retry.visible and (cont == null or not cont.visible), "a failed download does not stay on the screen with RETRY only")
		screen.queue_free()
	else:
		print("  (this platform is not gated: %s)" % UpdateManager.platform_key())
	# a stamped build newer than the manifest is never offered a downgrade
	_expect(not UpdateManager.mobile_update_needed("b".repeat(40), "c".repeat(40), 783, 790), "a newer stamped build was offered build 783")
	_expect(UpdateManager.mobile_update_needed("b".repeat(40), "c".repeat(40), 790, 783), "an older stamped build was not offered the update")
	# unstamped (dev) builds: told, never blocked
	_expect(UpdateManager.dev_build(0) and not UpdateManager.dev_build(783), "dev build detection")
	UpdateManager.build_number_override = 0
	if UpdateManager.is_dev_build():
		UpdateManager.available = {"revision": "b".repeat(40), "build": 783}
		_expect(not UpdateManager.should_open_progress_screen(), "an unstamped dev build is held by the update gate")
		var boot3 := (load("res://scenes/boot_loading.tscn") as PackedScene).instantiate()
		boot3.set("auto_start", false)
		host.add_child(boot3)
		await host.get_tree().process_frame
		opened[0] = 0
		boot3.call("_on_update_check_finished", true, true)
		var cont3 := boot3.find_child("ContinueOfflineButton", true, false) as Button
		var phase := String((boot3.get("_phase") as Label).text)
		_expect(opened[0] == 0 and cont3 != null and cont3.visible and phase.contains("783"),
			"a dev build is not shown an optional 'UPDATE AVAILABLE (BUILD 783)' notice with CONTINUE (phase '%s')" % phase)
		var was_offline := Backend.offline_mode if "offline_mode" in Backend else false
		boot3.call("_continue_offline")
		_expect(bool(boot3.get("_may_open_menu")), "CONTINUE on the dev notice does not open the menu")
		_expect(("offline_mode" not in Backend) or Backend.offline_mode == was_offline, "CONTINUE on the dev notice went offline")
		boot3.queue_free()
		UpdateManager.available = {}
	# unreachable: fall through to the menu offline
	UpdateManager.available = {}
	var boot2 := (load("res://scenes/boot_loading.tscn") as PackedScene).instantiate()
	boot2.set("auto_start", false)
	host.add_child(boot2)
	await host.get_tree().process_frame
	opened[0] = 0
	boot2.call("_on_update_check_finished", false, false)
	_expect(bool(boot2.get("_may_open_menu")) and opened[0] == 0 and UpdateManager.offline_mode,
		"an unreachable server did not fall through to the menu offline")
	boot2.queue_free()
	_expect(UpdateManager.MANIFEST_TIMEOUT_SECONDS <= 8.0, "the update check waits longer than 8 s")
	UpdateManager.gate_override = Callable()
	UpdateManager.build_number_override = -1
	UpdateManager.available = saved_available
	UpdateManager.offline_mode = saved_offline
	await host.get_tree().process_frame
	if _failures == 0:
		print("  updategate an available update holds every self-updating platform on the update screen (install or retry only); unreachable -> menu offline; iOS/web never blocked")
	return _failures
