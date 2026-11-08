extends RefCounted

## Background updates (no blocking gate): with an update available the boot screen still opens the menu, the landing scene (hub, or the Last Route menu while the hub is skipped) opens, and
## the update downloads in the background; the UpdateBadge shows "UPDATE AVAILABLE // DOWNLOADING n%" then
## "UPDATE READY // RESTART TO APPLY" (phones: TAP TO INSTALL), in a run inside the HUD status bar; staging waits while a run is
## going; a ready update is applied on quit (helper swap without relaunch) or with RESTART NOW from the badge popup; dev builds
## only see the badge text; a stamped build is never offered a lower build.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- update_gate

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func run(host: Node) -> int:
	var saved_available := UpdateManager.available.duplicate(true)
	var saved_offline := UpdateManager.offline_mode
	var saved_ready := UpdateManager.ready_to_install
	var opened := [0]
	UpdateManager.gate_override = func() -> void: opened[0] += 1
	UpdateManager.build_number_override = 700
	UpdateManager.offline_mode = false
	UpdateManager.available = {"revision": "b".repeat(40), "build": 783, "sha256": "e".repeat(64), "url": "https://x/y.zip"}
	_expect(not UpdateManager.should_open_progress_screen(), "an update still blocks the player")
	# boot falls through to the menu
	var boot := (load("res://game/boot/boot_loading.tscn") as PackedScene).instantiate()
	boot.set("auto_start", false)
	host.add_child(boot)
	await host.get_tree().process_frame
	boot.call("_on_update_check_finished", true, true)
	_expect(bool(boot.get("_may_open_menu")) and opened[0] == 0, "boot did not open the menu with an update available")
	boot.queue_free()
	# the landing scene opens (the hub with GameRegistry.SKIP_HUB off, the Last Route menu with it on) and does not call the gate
	for skip in [0, 1]:
		GameRegistry.skip_hub_override = skip
		var landing := (load(GameRegistry.landing_scene()) as PackedScene).instantiate()
		host.add_child(landing)
		await host.get_tree().process_frame
		var marker_name := "PlayButton" if skip == 1 else "HubCarousel"
		_expect(landing.find_child(marker_name, true, false) != null and opened[0] == 0,
			"the %s did not open with an update available" % ("Last Route menu" if skip == 1 else "hub"))
		landing.queue_free()
	GameRegistry.skip_hub_override = -1
	# badge states
	var badge := host.get_tree().root.find_child("UpdateBadge", true, false) as UpdateBadge
	if badge == null:
		badge = UpdateBadge.new()
		host.add_child(badge)
	UpdateManager.downloading = true
	UpdateManager._last_progress_percent = 42
	_expect(UpdateManager.badge_text() == "UPDATE AVAILABLE // DOWNLOADING 42%", "downloading badge: %s" % UpdateManager.badge_text())
	await host.get_tree().process_frame
	_expect(badge.badge_visible_text() == UpdateManager.badge_text(), "the badge does not show the download")
	UpdateManager.downloading = false
	UpdateManager.ready_to_install = true
	var ready_text := "UPDATE READY // %s" % ("TAP TO INSTALL" if UpdateManager.is_mobile_package() else "RESTART TO APPLY")
	_expect(UpdateManager.badge_text() == ready_text, "ready badge: %s" % UpdateManager.badge_text())
	badge.open_popup()
	await host.get_tree().process_frame
	var restart := badge.find_child("RestartNowButton", true, false) as Button
	_expect(badge.popup_open() and restart != null and restart.visible, "the popup has no RESTART NOW for a ready update")
	badge.close_popup()
	# in a run: the text moves into the HUD status bar
	var hud := (load("res://game/hud/hud.tscn") as PackedScene).instantiate()
	host.add_child(hud)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_expect((hud.get("status_bar") as HudStatusBar).segment_text("update") == ready_text and badge.badge_visible_text().is_empty(),
		"in a run the update status is not in the HUD bar")
	hud.queue_free()
	# staging waits during a run
	UpdateManager.ready_to_install = false
	var marker := Node.new()
	marker.add_to_group("gameplay_session")
	host.add_child(marker)
	UpdateManager.downloaded_path = "user://updates/none.zip"
	UpdateManager._prepare_verified_download()
	_expect(UpdateManager.staging_deferred and not UpdateManager.preparing, "staging ran during a run")
	marker.queue_free()
	UpdateManager.staging_deferred = false
	UpdateManager.set_process(false)
	# dev builds: badge text only
	UpdateManager.build_number_override = 0
	_expect(UpdateManager.badge_text().contains("DEV BUILD") and UpdateManager.badge_text().contains("783"), "dev badge: %s" % UpdateManager.badge_text())
	UpdateManager.build_number_override = 700
	# no downgrade
	_expect(not UpdateManager.mobile_update_needed("b".repeat(40), "c".repeat(40), 783, 790), "a newer stamped build was offered 783")
	# unreachable: menu, offline
	UpdateManager.available = {}
	var boot2 := (load("res://game/boot/boot_loading.tscn") as PackedScene).instantiate()
	boot2.set("auto_start", false)
	host.add_child(boot2)
	await host.get_tree().process_frame
	for _attempt in 3:   # the boot retries the server (with a growing pause) before giving up
		boot2.call("_on_update_check_finished", false, false)
		_expect(not UpdateManager.offline_mode, "the boot went offline before retrying the server")
	boot2.call("_on_update_check_finished", false, false)
	_expect(bool(boot2.get("_may_open_menu")) and UpdateManager.offline_mode, "an unreachable server did not fall through offline")
	boot2.queue_free()
	UpdateManager.gate_override = Callable()
	UpdateManager.build_number_override = -1
	UpdateManager.available = saved_available
	UpdateManager.offline_mode = saved_offline
	UpdateManager.ready_to_install = saved_ready
	UpdateManager.downloaded_path = ""
	await host.get_tree().process_frame
	if _failures == 0:
		print("  updategate no blocking gate: boot + hub open, badge DOWNLOADING n% -> READY (HUD bar in runs), RESTART NOW popup, staging waits for the run, dev badge, no downgrade, offline fall-through")
	return _failures
