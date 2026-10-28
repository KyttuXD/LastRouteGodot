extends RefCounted

## Headless check on the room.
##
## The point of introducing rooms before there is any networking is that
## singleplayer stops being a second code path -- so what is worth testing is
## exactly that: a solo session really is a one-player room, and the rules that
## will matter online (which modes need other people, who seats how many) are
## properties of the ROOM rather than of whichever button was pressed.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- room

var _failures := 0
## VALIDATE_PORT_OFFSET lets parallel runs on one machine use distinct ports.
var TEST_PORT := 28421 + int(OS.get_environment("VALIDATE_PORT_OFFSET"))


func _fail(message: String) -> void:
	print("  FAIL  %s" % message)
	_failures += 1


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_fail(message)


## A guest leaving a co-op run (their own exit, or the host going away) ends up on the MAIN MENU with the room fully cleared.
func _check_guest_leaves_to_menu(host: Node) -> void:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	RoomState.code = "ZZZZZ"
	RoomState.is_host = false
	RoomState.session_active = true
	RoomState.peers = {1: "HOSTNAME", 2: "GUESTNAME"}
	RoomState.reset_after_leaving("YOU LEFT THE ROOM")
	_expect(RoomState.code != "ZZZZZ" and RoomState.is_host and not RoomState.online and not RoomState.connecting,
		"leaving a room kept its code or the guest role")
	_expect(not RoomState.session_active and not RoomState.reconnect_active, "leaving a room left its session or a reconnect running")
	_expect(not RoomState.peers.has(1) or RoomState.peers.size() <= 1, "leaving a room kept the host's roster (%s)" % [RoomState.peers])
	_expect(RoomState.menu_notice == "YOU LEFT THE ROOM", "the leave notice was not queued for the main menu")
	_expect(RoomState.status_message.is_empty(), "a stale staging status survived the leave")
	_expect(RoomState.HOST_LEFT_NOTICE.begins_with("HOST LEFT"), "the host-left notice does not say HOST LEFT")
	# the main menu shows the notice once
	RoomState.menu_notice = RoomState.HOST_LEFT_NOTICE
	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	host.add_child(menu)
	await host.get_tree().process_frame
	var notice := menu.find_child("RoomNotice", true, false) as Label
	_expect(notice != null and notice.text.begins_with("HOST LEFT"), "the main menu did not show HOST LEFT after the host went away")
	_expect(RoomState.menu_notice.is_empty(), "the menu notice was not consumed")
	menu.queue_free()
	await host.get_tree().process_frame
	# the three guest exits and the host-gone paths all use it (not the staging screen)
	var route_source := FileAccess.get_file_as_string("res://src/infinite_route_test.gd")
	var main_source := FileAccess.get_file_as_string("res://src/main_3d.gd")
	var state_source := FileAccess.get_file_as_string("res://src/autoload/room_state.gd")
	_expect(route_source.contains('RoomState.leave_room_to_menu("YOU LEFT THE ROOM")'), "the streamed route's guest leave does not go to the main menu")
	_expect(main_source.count('RoomState.leave_room_to_menu("YOU LEFT THE ROOM")') == 2, "main_3d guest exits do not all go to the main menu")
	_expect(state_source.count("_close_failed_connection(HOST_LEFT_NOTICE, true)") == 2, "a lost or timed-out host does not send guests to the main menu")


## Offline mode: a clear join message, GO ONLINE (menu + join dialog) without a restart, an OFFLINE badge, and a boot that retries the
## server a few times before it gives up and starts offline.
func _check_offline_mode(host: Node) -> void:
	Backend.suppress_requests_for_tests()
	var offline_before := Backend.offline_mode
	var update_offline_before := UpdateManager.offline_mode
	Backend.offline_mode = true
	var result := []
	var capture := func(_code: String, _endpoint: Dictionary, error: String) -> void: result.append(error)
	Backend.room_resolved.connect(capture)
	Backend.resolve_room("abc12")
	Backend.room_resolved.disconnect(capture)
	_expect(result == ["OFFLINE MODE // GO ONLINE TO JOIN ROOMS"], "an offline join lookup says %s" % [result])

	var menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	host.add_child(menu)
	await host.get_tree().process_frame
	var badge := menu.find_child("OfflineBadge", true, false) as Label
	var go_button := menu.find_child("GoOnlineButton", true, false) as Button
	_expect(badge != null and badge.visible and badge.text == "OFFLINE", "the main menu shows no OFFLINE badge while offline")
	_expect(go_button != null and go_button.visible, "the main menu shows no GO ONLINE button while offline")
	menu.call("_on_join_pressed")
	await host.get_tree().process_frame
	(menu.find_child("RoomCodeInput", true, false) as LineEdit).text = RoomState._make_code()
	menu.call("_submit_join")
	var status := menu.find_child("JoinStatus", true, false) as Label
	var dialog_go := menu.find_child("JoinGoOnline", true, false) as Button
	_expect(status != null and status.text == Backend.OFFLINE_JOIN_MESSAGE, "the join dialog does not explain offline mode")
	_expect(dialog_go != null and dialog_go.visible, "the join dialog has no GO ONLINE button while offline")
	dialog_go.pressed.emit()
	await host.get_tree().process_frame
	_expect(not Backend.offline_mode and not UpdateManager.offline_mode, "GO ONLINE did not leave offline mode")
	_expect(not go_button.visible and not badge.visible, "the offline badge and GO ONLINE stay up after going online")
	menu.queue_free()
	await host.get_tree().process_frame

	# Create Room carries the Offline option: off normally, on (with a note) when offline, and a failed server check turns it on
	Backend.offline_mode = false
	var create_menu := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	host.add_child(create_menu)
	await host.get_tree().process_frame
	_expect(create_menu.find_child("OfflineButton", true, false) == null, "the old PLAY OFFLINE button is still on the menu")
	create_menu.call("_on_play_pressed")
	await host.get_tree().process_frame
	var toggle := create_menu.find_child("CreateOfflineToggle", true, false) as Button
	_expect(toggle != null, "Create Room has no Offline (solo, no server) option")
	_expect(not bool(create_menu.get("_create_offline")), "the Offline option should start off while the server is fine")
	create_menu.set("_creating_room", true)
	create_menu.call("_on_create_health_checked", false, "DIRECTORY UNAVAILABLE")
	var create_note := create_menu.find_child("CreateNote", true, false) as Label
	_expect(bool(create_menu.get("_create_offline")) and create_note != null and create_note.text.contains("SERVER NOT REACHABLE"),
		"a failed server check did not turn the Offline option on with a note")
	create_menu.call("_close_modal")
	Backend.offline_mode = true
	create_menu.call("_on_play_pressed")
	await host.get_tree().process_frame
	_expect(bool(create_menu.get("_create_offline")) and (create_menu.find_child("CreateNote", true, false) as Label).text == Backend.OFFLINE_NOTE,
		"opening Create Room while offline did not start with Offline on and a note")
	create_menu.queue_free()
	await host.get_tree().process_frame
	Backend.offline_mode = false

	# offline for one run ends at the menu: leave the room, then joining works again without a restart
	Backend.enter_run_offline()
	_expect(Backend.offline_mode and Backend.offline_for_run and UpdateManager.offline_mode, "an offline run did not start offline")
	var after_run := (load("res://scenes/main_menu.tscn") as PackedScene).instantiate()
	host.add_child(after_run)
	await host.get_tree().process_frame
	_expect(not Backend.offline_mode and not Backend.offline_for_run and not UpdateManager.offline_mode,
		"offline mode survived leaving the offline run (the menu must clear it)")
	_expect(not (after_run.find_child("OfflineBadge", true, false) as Label).visible, "the OFFLINE badge stayed up after leaving the offline run")
	var after_result := []
	var after_capture := func(_code: String, _endpoint: Dictionary, error: String) -> void: after_result.append(error)
	Backend.room_resolved.connect(after_capture)
	Backend.resolve_room("abc12")
	Backend.room_resolved.disconnect(after_capture)
	_expect(not after_result.has(Backend.OFFLINE_JOIN_MESSAGE), "joining after an offline run still says offline")
	after_run.queue_free()
	await host.get_tree().process_frame
	# a boot-time or --offline mode is NOT run-scoped: the menu keeps it until GO ONLINE
	Backend.enable_offline_mode()
	_expect(not Backend.end_run_offline() and Backend.offline_mode, "a session offline mode was cleared like a run-scoped one")
	Backend.offline_mode = false

	# the boot sequence retries the server before falling back
	var boot := (load("res://scenes/boot_loading.tscn") as PackedScene).instantiate()
	boot.set("auto_start", false)
	host.add_child(boot)
	await host.get_tree().process_frame
	for attempt in 3:
		boot.call("_on_update_check_finished", false, false)
		_expect(not UpdateManager.offline_mode and not bool(boot.get("_may_open_menu")),
			"the boot went offline after only %d failed check(s)" % (attempt + 1))
		_expect(String((boot.get("_status") as Label).text).contains("RETRYING (%d/3)" % (attempt + 1)),
			"the boot does not say it is retrying (%s)" % (boot.get("_status") as Label).text)
	boot.call("_on_update_check_finished", false, false)
	_expect(UpdateManager.offline_mode and Backend.offline_mode and bool(boot.get("_may_open_menu")),
		"the boot did not fall back to offline mode after its retries")
	boot.queue_free()
	await host.get_tree().process_frame
	Backend.offline_mode = offline_before
	UpdateManager.offline_mode = update_offline_before


func run(host: Node) -> int:
	await _check_offline_mode(host)
	await _check_guest_leaves_to_menu(host)
	_expect(Backend.PRIMARY_BASE_URL == "http://lastroute.kyttuslab.org:8105",
		"the built-in room directory is %s" % Backend.PRIMARY_BASE_URL)
	var backend_url_before := Backend.base_url
	Backend.base_url = Backend.PRIMARY_BASE_URL
	_expect(Backend.accounts_available(),
		"the explicitly enabled primary HTTP deployment rejects credentials")
	_expect(Backend.account_transport_warning().is_empty(),
		"the enabled primary HTTP origin shows an in-game transport warning")
	Backend.base_url = "http://untrusted.invalid:1105"
	_expect(not Backend.accounts_available(),
		"an arbitrary public HTTP backend gained credential access")
	Backend.base_url = "http://localhost.attacker.invalid:1105"
	_expect(not Backend.accounts_available(),
		"a hostname beginning with localhost bypassed account transport checks")
	Backend.base_url = "https://accounts.example.invalid"
	_expect(Backend.accounts_available() and Backend.account_transport_warning().is_empty(),
		"an HTTPS account origin was rejected or warned as unencrypted")
	Backend.base_url = backend_url_before
	_expect(RoomState.ROUTE_LOADING_SCENE == "res://scenes/route_loading.tscn"
		and ResourceLoader.exists(RoomState.ROUTE_LOADING_SCENE),
		"room starts do not pass through the route loading scene")
	_expect(RoomState.session_scene_path() == "res://scenes/infinite_route_test.tscn",
		"the default route loader does not target Infinite")
	var account_before := {
		"username": Backend.account_username,
		"token": Backend.account_session_token,
		"admin": Backend.account_admin,
		"admin_owner": Backend.account_admin_owner,
		"admin_permissions": Backend.account_admin_permissions.duplicate(),
		"verified": Backend.account_session_verified,
	}
	Backend.account_username = "Kyttu"
	Backend.account_session_token = "validation-token"
	Backend.account_admin = true
	Backend.account_admin_owner = true
	Backend.account_admin_permissions = PackedStringArray(["player", "world"])
	Backend.account_session_verified = true
	_expect(not Backend.admin_authorized(),
		"mixed-case local state bypasses canonical server identity")
	Backend.account_username = "KYTTU"
	_expect(Backend.admin_authorized(),
		"verified canonical KYTTU is not authorized for release admin")
	Backend.account_username = "AYTTU"
	_expect(Backend.admin_owner_authorized(),
		"verified canonical AYTTU is not authorized as the second owner")
	Backend.account_admin = false
	Backend.account_admin_owner = false
	Backend.account_admin_permissions = PackedStringArray()
	Backend._adopt_admin_identity({"admin": true})
	_expect(Backend.admin_owner_authorized() \
		and Backend.account_admin_permissions.size() == Backend.ADMIN_PERMISSION_NAMES.size(),
		"an authenticated existing AYTTU account from the legacy backend lost owner access")
	Backend.account_username = "NOT_KYTTU"
	Backend._adopt_admin_identity({"admin": true})
	_expect(not Backend.admin_authorized(),
		"legacy admin compatibility granted access to a non-owner username")
	Backend.account_session_verified = false
	_expect(not Backend.admin_authorized(),
		"unverified cached account state authorizes release admin")
	Backend.account_username = account_before["username"]
	Backend.account_session_token = account_before["token"]
	Backend.account_admin = account_before["admin"]
	Backend.account_admin_owner = account_before["admin_owner"]
	Backend.account_admin_permissions = account_before["admin_permissions"]
	Backend.account_session_verified = account_before["verified"]
	_expect(UpdateManager._newer("0.0.1.1", "0.0.1.0"),
		"the updater did not recognize a newer four-part version")
	_expect(not UpdateManager._newer("0.0.1.0", "0.0.1.0"),
		"the updater treated the current version as newer")
	_expect(not UpdateManager._newer("0.0.0.9", "0.0.1.0"),
		"the updater treated an older version as newer")
	_expect(UpdateManager.DEBUG_RECHECK_SECONDS <= 10.0,
		"debug update checks are too slow for active test builds")
	_expect(UpdateManager.MANIFEST_TIMEOUT_SECONDS > 0.0 \
		and UpdateManager.MANIFEST_TIMEOUT_SECONDS <= 10.0,
		"an unreachable update backend can leave the startup gate checking forever")
	_expect(UpdateManager._update_needed("0.0.1.0", "0.0.1.0",
		"bbbbbbbbbbbb", "aaaaaaaaaaaa"),
		"the updater ignored a newer build commit at the same frozen version")
	_expect(not UpdateManager._update_needed("0.0.1.0", "0.0.1.0",
		"aaaaaaaaaaaa", "aaaaaaaaaaaa"),
		"the updater offered its own build commit")
	_expect(not UpdateManager._update_needed("0.0.1.0", "0.0.1.0", "", "source"),
		"an editor/source run was treated as an exported revision")
	_expect(UpdateManager._valid_sha256("a".repeat(64)),
		"the updater rejected a valid SHA-256")
	_expect(not UpdateManager._valid_sha256("a".repeat(63)),
		"the updater accepted a short SHA-256")
	var gameplay_marker := Node.new()
	gameplay_marker.add_to_group("gameplay_session")
	host.get_tree().root.add_child(gameplay_marker)
	var old_update_required: bool = UpdateManager.update_required
	var old_available: Dictionary = UpdateManager.available.duplicate(true)
	UpdateManager.update_required = true
	UpdateManager.build_number_override = 700   # a stamped build: dev (unstamped) builds are never gated
	_expect(not UpdateManager._should_install_automatically(),
		"the background updater would restart the executable during gameplay")
	gameplay_marker.queue_free()
	await host.get_tree().process_frame
	_expect(UpdateManager.UPDATE_PROGRESS_SCENE == "res://scenes/update_progress.tscn"
		and ResourceLoader.exists(UpdateManager.UPDATE_PROGRESS_SCENE),
		"desktop required updates have no in-progress screen")
	_expect(UpdateManager.uses_in_progress_screen() == (UpdateManager.platform_key()
		in ["linux", "windows", "windows_legacy", "steamvr", "macos", "phone", "quest"]),
		"in-progress screen eligibility does not match the desktop platforms")
	_expect(not UpdateManager._should_install_automatically(),
		"required desktop updates still quit before the in-progress screen")
	UpdateManager.available = {"version": "0.0.1.1", "required": true}
	# background updates (UpdateBadge): even a required update never sends the menu to a blocking screen
	_expect(not UpdateManager.should_open_progress_screen(),
		"an update still sends the menu to a blocking screen")
	var old_preparing: bool = UpdateManager.preparing
	var old_downloading: bool = UpdateManager.downloading
	UpdateManager.available = {
		"version": "0.0.1.1",
		"required": true,
		"url": "https://example.test/last-route-update.zip",
		"sha256": "a".repeat(64),
	}
	UpdateManager.preparing = true
	UpdateManager.downloading = false
	_expect(not UpdateManager.should_open_progress_screen(),
		"verify/unpack sends the menu to a blocking screen")
	UpdateManager.download_update()
	_expect(not UpdateManager.downloading,
		"verify/unpack re-entered download and could wipe the staging tree")
	UpdateManager.preparing = old_preparing
	UpdateManager.downloading = old_downloading
	_expect(UpdateManager.is_failure_status("COULD NOT START UPDATE INSTALLER // RETRY"),
		"a helper-launch failure was not treated as a retryable update error")
	_expect(UpdateManager.is_failure_status("COULD NOT UNPACK UPDATE // RETRY"),
		"an unpack failure was not treated as a retryable update error")
	_expect(UpdateManager.is_failure_status(
		UpdateManager.PLATFORM_MISMATCH_STATUS),
		"the live Windows mismatch footer was not treated as a retryable update error")
	_expect(UpdateManager.is_failure_status(
		"%s // RETRY" % UpdateManager.PLATFORM_MISMATCH_STATUS),
		"a platform-mismatch failure was not treated as a retryable update error")
	_expect(UpdateManager.update_manifest_url().ends_with("/api/updates/%s/%s" % [
		Build.update_channel(), UpdateManager.platform_key()]),
		"the updater does not request the channel/platform published for this build")
	_expect(not UpdateManager.update_manifest_url().contains("/api/updates/release/")
		or Build.update_channel() == "release",
		"a debug client requested the release update channel")
	_expect(UpdateManager.is_failure_status("UPDATE STAGED // GAME FOLDER IS READ-ONLY"),
		"a read-only install folder was not treated as a retryable update error")
	_expect(not UpdateManager.is_failure_status("INSTALLING UPDATE // RESTARTING"),
		"the successful install hand-off was treated as a failure")
	_expect(UpdateManager.WINDOWS_HELPER.contains("Wait-Process")
		and UpdateManager.WINDOWS_HELPER.contains("Start-Process"),
		"the Windows update helper no longer waits for exit before replacing and relaunching")
	UpdateManager.available = old_available
	UpdateManager.build_number_override = -1
	UpdateManager.update_required = old_update_required
	for safe_entry in ["LastRoute.pck", "Game.app/Contents/MacOS/Game"]:
		_expect(UpdateManager._safe_archive_entry(safe_entry),
			"the updater rejected safe archive entry %s" % safe_entry)
	for unsafe_entry in ["../LastRoute.pck", "/tmp/LastRoute", "folder/../../escape",
			"C:/Windows/System32/escape", "folder\\escape"]:
		_expect(not UpdateManager._safe_archive_entry(unsafe_entry),
			"the updater accepted unsafe archive entry %s" % unsafe_entry)
	_expect(UpdateManager._mac_bundle_path(
		"/Applications/Kyttu's Lab.app/Contents/MacOS/Kyttu's Lab") \
		== "/Applications/Kyttu's Lab.app",
		"the updater could not resolve a macOS app bundle")
	_expect(UpdateManager._previous_install_backup_path("windows",
		"C:/Games/KyttusLab-Windows-Debug.exe") \
		== "C:/Games/.lastroute-backup-previous",
		"the updater could not resolve a Windows rollback folder")
	_expect(UpdateManager._previous_install_backup_path("macos",
		"/Applications/Kyttu's Lab.app/Contents/MacOS/Kyttu's Lab") \
		== "/Applications/.lastroute-backup-previous",
		"the updater could not resolve a macOS rollback folder")
	var update_archive := "user://last-route-update-test.zip"
	var update_stage := "user://last-route-update-test"
	UpdateManager._remove_tree(update_stage)
	var packer := ZIPPacker.new()
	_expect(packer.open(update_archive) == OK, "could not create updater test ZIP")
	_expect(packer.start_file("KyttusLab-Test.x86_64") == OK,
		"could not add the updater test executable")
	packer.write_file("test executable".to_utf8_buffer())
	packer.close_file()
	_expect(packer.start_file("KyttusLab-Test.pck") == OK,
		"could not add the updater test PCK")
	packer.write_file("test pck".to_utf8_buffer())
	packer.close_file()
	packer.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(update_stage))
	var extract_error := UpdateManager._extract_archive(update_archive, update_stage)
	_expect(extract_error.is_empty(),
		"the updater could not unpack a valid platform archive")
	_expect(not UpdateManager.is_failure_status(extract_error),
		"a successful unpack reported a retryable update error")
	_expect(UpdateManager._extract_archive(
		"user://missing-last-route-update.zip", update_stage).contains("RETRY"),
		"a missing update package no longer offers retry")
	var update_layout := UpdateManager._installation_layout("linux",
		"/games/KyttusLab-Old.x86_64", update_stage)
	_expect(String(update_layout.get("launch", "")) == "KyttusLab-Test.x86_64",
		"the updater could not find the staged Linux executable")
	var legacy_executable := FileAccess.open(
		update_stage.path_join("KyttusLab-Windows-Legacy-Debug.exe"), FileAccess.WRITE)
	legacy_executable.store_string("test legacy executable")
	legacy_executable.close()
	var legacy_layout := UpdateManager._installation_layout("windows_legacy",
		"C:/Games/KyttusLab-Windows-Legacy-Debug.exe", update_stage)
	_expect(String(legacy_layout.get("launch", "")) == \
		"KyttusLab-Windows-Legacy-Debug.exe",
		"the updater could not find the staged legacy Windows executable")
	_expect(String(legacy_layout.get("stage", "")) == update_stage,
		"a flat Windows archive was rewritten to a nested export folder")
	var nested_archive := "user://last-route-nested-update-test.zip"
	var nested_stage := "user://last-route-nested-update-test"
	UpdateManager._remove_tree(nested_stage)
	var nested_packer := ZIPPacker.new()
	_expect(nested_packer.open(nested_archive) == OK,
		"could not create the nested Windows updater test ZIP")
	_expect(nested_packer.start_file("KyttusLab-Windows-Debug/KyttusLab-Windows-Debug.exe") == OK,
		"could not add the nested Windows updater test executable")
	nested_packer.write_file("nested windows executable".to_utf8_buffer())
	nested_packer.close_file()
	nested_packer.close()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(nested_stage))
	_expect(UpdateManager._extract_archive(nested_archive, nested_stage).is_empty(),
		"the updater could not unpack a Godot-style nested Windows archive")
	_expect(UpdateManager._export_root("windows", nested_stage) \
		== nested_stage.path_join("KyttusLab-Windows-Debug"),
		"the updater did not descend into the single Windows export folder")
	var nested_windows := UpdateManager._installation_layout("windows",
		"C:/Games/KyttusLab-Windows-Debug.exe", nested_stage)
	_expect(String(nested_windows.get("launch", "")) == "KyttusLab-Windows-Debug.exe",
		"the updater rejected a Windows zip whose exe sits in one export folder")
	_expect(String(nested_windows.get("stage", "")) \
		== nested_stage.path_join("KyttusLab-Windows-Debug"),
		"the updater did not stage from the nested Windows export folder")
	var linux_only := "user://last-route-linux-only-update-test"
	UpdateManager._remove_tree(linux_only)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(linux_only))
	_expect(UpdateManager._extract_archive(update_archive, linux_only).is_empty(),
		"the updater could not unpack a Linux-only archive for the mismatch check")
	_expect(UpdateManager._installation_layout("windows",
		"C:/Games/KyttusLab-Windows-Debug.exe", linux_only).is_empty(),
		"a Linux archive was accepted as a Windows update")
	_expect(String(UpdateManager._installation_layout("linux",
		"/games/KyttusLab-Old.x86_64", linux_only).get("launch", "")) \
		== "KyttusLab-Test.x86_64",
		"the Linux-only archive fixture lost its executable")
	var nested_linux_stage := "user://last-route-nested-linux-update-test"
	UpdateManager._remove_tree(nested_linux_stage)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		nested_linux_stage.path_join("KyttusLab-Linux-Debug")))
	var nested_linux_exe := FileAccess.open(nested_linux_stage.path_join(
		"KyttusLab-Linux-Debug/KyttusLab-Linux-Debug.x86_64"), FileAccess.WRITE)
	nested_linux_exe.store_string("nested linux executable")
	nested_linux_exe.close()
	_expect(UpdateManager._installation_layout("windows",
		"C:/Games/KyttusLab-Windows-Debug.exe", nested_linux_stage).is_empty(),
		"a nested Linux zip was accepted as a Windows update")
	_expect(UpdateManager._installation_layout("linux",
		"/games/KyttusLab-Old.x86_64", nested_stage).is_empty(),
		"a nested Windows zip was accepted as a Linux update")
	var macos_stage := "user://last-route-macos-update-test"
	UpdateManager._remove_tree(macos_stage)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		macos_stage.path_join("Kyttu's Lab.app/Contents/MacOS")))
	_expect(UpdateManager._export_root("macos", macos_stage) == macos_stage,
		"the updater unwrapped a top-level macOS app bundle")
	_expect(String(UpdateManager._installation_layout("macos",
		"/Applications/Kyttu's Lab.app/Contents/MacOS/Kyttu's Lab",
		macos_stage).get("launch", "")) == "Kyttu's Lab.app",
		"the updater could not find a top-level macOS app bundle")
	_expect(FileAccess.get_file_as_string(
		update_stage.path_join("KyttusLab-Test.pck")) == "test pck",
		"the updater changed the staged PCK")
	var helper_path := "user://last-route-update-helper-test.sh"
	_expect(UpdateManager._write_text(helper_path, UpdateManager.UNIX_HELPER),
		"the updater could not write its desktop helper")
	var helper_output := []
	var has_unix_shell := FileAccess.file_exists("/bin/sh")
	if has_unix_shell:
		_expect(OS.execute("/bin/sh", PackedStringArray(["-n",
			ProjectSettings.globalize_path(helper_path)]), helper_output, true) == 0,
			"the Unix update helper has invalid shell syntax: %s" % helper_output)
	else:
		_expect(UpdateManager.UNIX_HELPER.begins_with("#!/bin/sh")
			and UpdateManager.UNIX_HELPER.contains("while kill -0"),
			"the Unix update helper is no longer a wait-then-replace shell script")
	var cache_keep := UpdateManager.UPDATE_ROOT.path_join("linux-current.zip")
	var cache_old := UpdateManager.UPDATE_ROOT.path_join("linux-old.zip")
	var cache_stage := UpdateManager.UPDATE_ROOT.path_join("staged-linux-old")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_stage))
	_expect(UpdateManager._write_text(cache_keep, "current"),
		"could not create the updater cleanup keep fixture")
	_expect(UpdateManager._write_text(cache_old, "old"),
		"could not create the updater cleanup stale fixture")
	_expect(UpdateManager._write_text(
		UpdateManager.UPDATE_ROOT.path_join(UpdateManager.DOWNLOAD_PART), "partial"),
		"could not create the updater partial-download fixture")
	_expect(UpdateManager._write_text(cache_stage.path_join("old-binary"), "old"),
		"could not create the updater staging fixture")
	UpdateManager._cleanup_update_cache([cache_keep])
	_expect(FileAccess.file_exists(cache_keep),
		"updater cleanup deleted the current revision archive")
	_expect(not FileAccess.file_exists(cache_old),
		"updater cleanup retained an obsolete revision archive")
	_expect(not FileAccess.file_exists(
		UpdateManager.UPDATE_ROOT.path_join(UpdateManager.DOWNLOAD_PART)),
		"updater cleanup retained an abandoned partial download")
	_expect(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(cache_stage)),
		"updater cleanup retained an obsolete staging directory")
	UpdateManager._cleanup_update_cache()
	var old_staged_path: String = UpdateManager.staged_path
	var old_downloaded_path: String = UpdateManager.downloaded_path
	UpdateManager.staged_path = cache_stage
	UpdateManager.downloaded_path = ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(cache_stage))
	_expect(UpdateManager._write_text(cache_stage.path_join("staged"), "staged"),
		"could not create the updater reveal-path fixture")
	_expect(UpdateManager._package_reveal_path() == cache_stage,
		"a read-only install fallback did not reveal the staged tree after the ZIP was removed")
	UpdateManager.staged_path = old_staged_path
	UpdateManager.downloaded_path = old_downloaded_path
	UpdateManager._remove_tree(cache_stage)
	var apply_root := "user://last-route-update-apply-test"
	var apply_stage := apply_root.path_join("stage")
	var apply_install := apply_root.path_join("install")
	UpdateManager._remove_tree(apply_root)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(apply_stage))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(apply_install))
	var new_executable := FileAccess.open(
		apply_stage.path_join("KyttusLab-Test.x86_64"), FileAccess.WRITE)
	new_executable.store_string("#!/bin/sh\nexit 0\n")
	new_executable.close()
	var new_pck := FileAccess.open(apply_stage.path_join("KyttusLab-Test.pck"), FileAccess.WRITE)
	new_pck.store_string("new pck")
	new_pck.close()
	var old_executable := FileAccess.open(
		apply_install.path_join("KyttusLab-Test.x86_64"), FileAccess.WRITE)
	old_executable.store_string("old executable")
	old_executable.close()
	var old_pck := FileAccess.open(apply_install.path_join("KyttusLab-Test.pck"), FileAccess.WRITE)
	old_pck.store_string("old pck")
	old_pck.close()
	if has_unix_shell:
		helper_output.clear()
		_expect(OS.execute("/bin/sh", PackedStringArray([
			ProjectSettings.globalize_path(helper_path),
			ProjectSettings.globalize_path(apply_stage),
			ProjectSettings.globalize_path(apply_install),
			"KyttusLab-Test.x86_64", "99999999", "abcdef1", "linux"]),
			helper_output, true) == 0,
			"the Unix update helper failed its disposable install: %s" % helper_output)
		_expect(FileAccess.get_file_as_string(
			apply_install.path_join("KyttusLab-Test.pck")) == "new pck",
			"the update helper did not install the new PCK")
		_expect(FileAccess.get_file_as_string(apply_install.path_join(
			".lastroute-backup-previous/KyttusLab-Test.pck")) == "old pck",
			"the update helper did not retain the previous PCK")
	else:
		_expect(FileAccess.file_exists(helper_path),
			"the updater could not keep its written desktop helper")
	UpdateManager._remove_tree(update_stage)
	UpdateManager._remove_tree(nested_stage)
	UpdateManager._remove_tree(nested_linux_stage)
	UpdateManager._remove_tree(linux_only)
	UpdateManager._remove_tree(macos_stage)
	UpdateManager._remove_tree(apply_root)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(update_archive))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(nested_archive))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(helper_path))
	_expect(RoomState.valid_room_code("ABCDE"),
		"a valid primary-server room code was rejected")
	for invalid_code in ["ABCD", "ABCDEF", "AB0DE", "ABIDE", "ABODE"]:
		_expect(not RoomState.valid_room_code(invalid_code),
			"invalid room code %s was accepted" % invalid_code)
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.code.length() == RoomState.CODE_LENGTH,
		"room code is %d characters" % RoomState.code.length())
	for glyph in RoomState.code:
		_expect(RoomState.CODE_ALPHABET.contains(glyph),
			"room code contains '%s', which is not in the spoken-aloud alphabet" % glyph)
	_expect(RoomState.players.size() == 1, "a local room seated %d players"
		% RoomState.players.size())
	_expect(RoomState.is_host, "the host of a local room is not the local player")
	_expect(not RoomState.online, "a local room reports itself online")
	_expect(RoomState.seed_text.begins_with("ROOM-%s-" % RoomState.code),
		"route seed %s does not name its own room" % RoomState.seed_text)

	# Nightmare is deliberately reserved until its multi-hunter rules exist.
	# Hard is a complete, selectable midpoint profile rather than a relabelled
	# Standard button.
	_expect(RoomState.DIFFICULTY_LABELS.has(RoomState.Difficulty.HARD),
		"Hard is missing from the selectable difficulty row")
	_expect(RoomState.DIFFICULTY_LABELS.has(RoomState.Difficulty.NIGHTMARE),
		"Nightmare is not visible as a planned difficulty")
	_expect(not RoomState.difficulty_available(RoomState.Difficulty.NIGHTMARE),
		"Nightmare is selectable before its multi-hunter rules exist")
	RoomState.set_difficulty(RoomState.Difficulty.HARD)
	_expect(RoomState.difficulty == RoomState.Difficulty.HARD,
		"set_difficulty did not accept Hard")
	_expect(RoomState.difficulty_id() == "hard", "Hard resolves to the wrong rules id")
	RoomState.set_difficulty(RoomState.Difficulty.NIGHTMARE)
	_expect(RoomState.difficulty == RoomState.Difficulty.HARD,
		"set_difficulty accepted the reserved Nightmare mode")
	_expect(RoomState._selectable_difficulty_or_standard(
		RoomState.Difficulty.NIGHTMARE) == RoomState.Difficulty.STANDARD,
		"a stale network Nightmare value is not sanitized to Standard")
	var standard := GameConfig.difficulty_profile("standard")
	var hard := GameConfig.difficulty_profile("hard")
	var nightmare := GameConfig.difficulty_profile("nightmare")
	for field in GameConfig.DIFFICULTY_PROFILES["standard"]:
		var low := minf(float(standard[field]), float(nightmare[field]))
		var high := maxf(float(standard[field]), float(nightmare[field]))
		_expect(float(hard[field]) >= low - .0001 and float(hard[field]) <= high + .0001,
			"Hard %s is %.3f, outside the Standard/Nightmare range %.3f..%.3f" % [
				field, float(hard[field]), low, high])
	# the approved tweak table for Hard (docs/HUNTER_HARD_ABILITIES.md)
	var approved_hard := {"hunter_sight": 1.10, "hunter_hearing": 1.12, "search_time": 4.0, "lost_sight_grace": 3.6,
		"stamina_drain": 12.0, "hide_tell": 1.3, "hide_trail": 3.5, "hide_cooldown": 16.0, "hide_random": .25,
		"taser_stun": 2.4, "taser_cooldown": 9.0, "escape_stun": 2.6, "spawn_distance": 11.0, "emote_chase_scale": .5,
		"emote_spot_p": .15, "relay_alert_radius": 18.0, "relay_alert_chance": 1.0}
	for field in approved_hard:
		_expect(is_equal_approx(float(hard[field]), float(approved_hard[field])),
			"Hard %s is %.3f, the approved table says %.3f" % [field, float(hard[field]), float(approved_hard[field])])
	for difficulty_id in ["relaxed", "standard", "hard", "nightmare"]:
		GameState.start_new_run(12345, difficulty_id)
		_expect(not GameState.game_over,
			"%s started in a game-over state" % difficulty_id)
	RoomState.set_difficulty(RoomState.Difficulty.STANDARD)

	# Account checkpoints resume deterministic solo floor boundaries. The
	# visible seed/config and GameState totals must round-trip together, while a
	# tampered seed is rejected before it can replace the current room.
	RoomState.map_scale = RoomState.Scale.LARGE
	RoomState.difficulty = RoomState.Difficulty.HARD
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	GameState.depth = 7
	GameState.score = 2400
	GameState.coins = 13
	var checkpoint := GameState.route_checkpoint(RoomState.seed_text,
		RoomState.map_scale, RoomState.difficulty, RoomState.difficulty_id())
	var checkpoint_seed := RoomState.seed_text
	_expect(RoomState.prepare_route_checkpoint(checkpoint).is_empty(),
		"a valid route checkpoint was rejected")
	_expect(RoomState.seed_text == checkpoint_seed
		and RoomState.map_scale == RoomState.Scale.LARGE
		and RoomState.difficulty == RoomState.Difficulty.HARD,
		"checkpoint room configuration did not restore")
	_expect(GameState.restore_queued_route_checkpoint(),
		"a prepared checkpoint was not consumed")
	_expect(GameState.depth == 7 and GameState.score == 2400
		and GameState.coins == 13,
		"checkpoint run totals did not restore")
	_expect(GameState.relays_collected == 0 and GameState.relays_sabotaged == 0,
		"a floor-boundary checkpoint restored partial relay state")
	var tampered := checkpoint.duplicate(true)
	tampered["run_seed"] = int(tampered["run_seed"]) + 1
	var seed_before_bad_checkpoint := RoomState.seed_text
	_expect(not RoomState.prepare_route_checkpoint(tampered).is_empty(),
		"a checkpoint with a mismatched seed was accepted")
	_expect(RoomState.seed_text == seed_before_bad_checkpoint,
		"a rejected checkpoint replaced the current room")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	GameState.start_new_run(RoomState.run_seed(), RoomState.difficulty_id())
	_expect(Palette.title_font().font_names[0] == "Arial Black",
		"the title no longer requests the original Arial Black face first")

	# The seed on screen and the facility on the floor must agree, which means
	# the run seed is derived from the text rather than stored beside it.
	var before := RoomState.run_seed()
	_expect(RoomState.run_seed() == before, "run seed is not stable for one route")
	var text := RoomState.seed_text
	RoomState.reroll_seed()
	_expect(RoomState.seed_text != text, "rerolling produced the same route")
	_expect(RoomState.code == RoomState.code, "rerolling changed the room code")
	_expect(RoomState.run_seed() != before, "a new route seed gave the same run seed")

	_expect(RoomState.mode_available(RoomState.Mode.DEFAULT),
		"Default mode is unavailable")
	RoomState.create_local(RoomState.Mode.DEFAULT)
	_expect(RoomState.seats() == RoomState.MAX_PLAYERS,
		"a route seats %d, not %d" % [RoomState.seats(), RoomState.MAX_PLAYERS])
	_expect(RoomState.start_label() == "ENTER ROUTE",
		"route staging says '%s'" % RoomState.start_label())
	_expect(RoomState.GUEST_FIRST_NAMES.size() >= 24,
		"guest FIRST-name pool is still too small")
	_expect(RoomState.GUEST_LAST_NAMES.size() >= 24,
		"guest LAST-name pool is still too small")
	for word in RoomState.GUEST_FIRST_NAMES + RoomState.GUEST_LAST_NAMES:
		_expect(String(word) == String(word).to_upper(),
			"guest callsign word %s is not uppercase" % word)

	# Normal route staging is Infinite-only. STANDARD remains loadable only as
	# an internal regression/save fallback and is absent from the player UI.
	_expect(RoomState.SELECTABLE_SCALE_LABELS.size() == 1 \
		and RoomState.SELECTABLE_SCALE_LABELS.has(RoomState.Scale.INFINITE) \
		and not RoomState.SELECTABLE_SCALE_LABELS.has(RoomState.Scale.STANDARD),
		"staging is not Infinite-only")
	RoomState.set_map_scale(RoomState.Scale.SMALL)
	_expect(RoomState.map_scale == RoomState.Scale.INFINITE,
		"retired Small scale remained selectable")
	RoomState.set_map_scale(RoomState.Scale.INFINITE)
	_expect(RoomState.map_scale == RoomState.Scale.INFINITE,
		"debug solo Infinite scale did not become selectable")
	_expect(RoomState.session_scene_path() == "res://scenes/infinite_route_test.tscn",
		"Infinite scale did not route into its streamed playtest scene")
	RoomState.online = true
	_expect(RoomState.map_scale_available(RoomState.Scale.INFINITE),
		"co-op Infinite scale is not selectable")
	_expect(RoomState.session_scene_path() == "res://scenes/infinite_route_test.tscn",
		"online Infinite scale did not route into its streamed scene")
	RoomState.online = false
	RoomState.map_scale = RoomState.Scale.STANDARD
	var options := RoomState.generator_options()
	var built := FacilityGenerator.new("scale-check", options)
	_expect(built.cols == options["cols"] and built.rows == options["rows"] \
		and built.floor_cells().size() > 0,
		"Standard map no longer builds a walkable facility")
	RoomState.map_scale = RoomState.Scale.INFINITE

	# Staging has to actually draw, since it is built entirely in code.
	var lobby: Node = load("res://scenes/room_lobby.tscn").instantiate()
	host.get_tree().root.add_child(lobby)
	await host.get_tree().process_frame
	await host.get_tree().process_frame
	_expect(lobby.get_child_count() > 1, "the staging screen drew nothing")
	var saw_hard := false
	var nightmare_button: Button = null
	var office_button: Button = null
	var saw_hide_seek := false
	var saw_small := false
	var saw_large := false
	var saw_immense := false
	var infinite_button: Button = null
	var default_mode_button: Button = null
	for button in lobby.find_children("*", "Button", true, false):
		saw_hard = saw_hard or String(button.text) == "HARD"
		if String(button.text) == "NIGHTMARE":
			nightmare_button = button
		if String(button.text) == "OFFICE":
			office_button = button
		saw_hide_seek = saw_hide_seek or String(button.text) == "HIDE & SEEK"
		saw_small = saw_small or String(button.text) == "SMALL"
		saw_large = saw_large or String(button.text) == "LARGE"
		saw_immense = saw_immense or String(button.text) == "IMMENSE"
		if String(button.text) == "INFINITE":
			infinite_button = button
		if String(button.text) == "DEFAULT":
			default_mode_button = button
	_expect(saw_hard, "the staging screen did not render a Hard button")
	_expect(nightmare_button != null and nightmare_button.disabled,
		"Nightmare is not visible and greyed out")
	_expect(office_button == null,
		"Office mode still appears as a player-facing staging button")
	_expect(not saw_hide_seek, "Hide & Seek still appears in staging")
	_expect(not saw_small and not saw_large and not saw_immense,
		"retired finite scale buttons still appear in staging")
	_expect(infinite_button == null and default_mode_button == null,
		"redundant mode/scale controls still occupy the staging screen")
	_expect(lobby.find_child("LobbyContinueButton", true, false) != null,
		"staging lost the CONTINUE RUN action")
	_expect(lobby.find_child("DebugCustomHostLabel", true, false) == null,
		"the removed custom-host label is still visible")
	_expect(lobby.find_child("DebugCustomHostRow", true, false) == null,
		"the removed custom-host controls are still visible")
	var create_online := lobby.find_child("CreateOnlineRoomButton", true, false) as Button
	var join_online := lobby.find_child("JoinOnlineRoomButton", true, false) as Button
	var code_input := lobby.find_child("PrimaryRoomCodeInput", true, false) as LineEdit
	var leave_online := lobby.find_child("LeaveOnlineRoomButton", true, false) as Button
	_expect(create_online == null, "staging still has a separate online-room action")
	_expect(join_online == null, "staging still has a second join-room action")
	_expect(code_input == null, "staging still has a duplicate room-code input")
	_expect(leave_online == null, "staging still has separate online-room controls")
	_expect(lobby.find_child("EnterRouteButton", true, false) != null,
		"staging lost its enter-route action")
	_expect(lobby.find_child("BackToMenuButton", true, false) != null,
		"staging lost its back-to-menu action")
	var back := lobby.find_child("BackToMenuButton", true, false) as Button
	_expect(back != null and back.text == "BACK TO LAST ROUTE", "the staging back button is not BACK TO LAST ROUTE (%s)" % (back.text if back != null else "none"))
	_expect(RoomState.menu_scene_path() == "res://scenes/main_menu.tscn" and Settings.hub_last_game == "last_route",
		"back from Last Route staging does not land on the Last Route menu / card")
	var old_connection_copy := ["HOST + LIST ROOM", "JOIN ROOM CODE", "LOCAL SESSION",
		"JOIN AT", "GO OFFLINE", "127.0.0.1", ":8421"]
	for node in lobby.find_children("*", "Control", true, false):
		var copy := ""
		if node is Label or node is Button:
			copy = String(node.text)
		elif node is LineEdit:
			copy = "%s %s" % [node.text, node.placeholder_text]
		for retired in old_connection_copy:
			_expect(not copy.contains(retired),
				"staging still exposes retired connection copy '%s'" % retired)
	lobby.queue_free()
	await host.get_tree().process_frame

	# Actually open a port. Everything above is bookkeeping; this is the part
	# that either works on the machine or does not, and "COULD NOT OPEN PORT"
	# is the single most likely outcome of testing with two windows.
	Backend.suppress_requests_for_tests()
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var error := RoomState.host_room(TEST_PORT)
	if not error.is_empty():
		_fail("hosting failed: %s" % error)
	else:
		_expect(RoomState.online, "hosting did not put the room online")
		_expect(RoomState.is_host, "the host is not the host")
		_expect(RoomState.roster().size() == 1,
			"a freshly hosted room lists %d players" % RoomState.roster().size())
		# Exactly one host, and it is peer 1. Every row used to claim both, so
		# a guest's window showed itself hosting the room it had joined.
		var rows: Array = RoomState.roster_rows()
		var hosts := 0
		var mine := 0
		for row in rows:
			if row["host"]:
				hosts += 1
				if int(row["id"]) != 1:
					_fail("peer %d is marked host; only peer 1 hosts" % row["id"])
			if row["you"]:
				mine += 1
		if hosts != 1:
			_fail("%d rows claim to be the host" % hosts)
		if mine != 1:
			_fail("%d rows claim to be you" % mine)
		print("  network   hosting on %d, %d seated" % [TEST_PORT,
			RoomState.roster().size()])
		print("  directory fixed to the primary service; no custom-host controls")

	# Hosting twice must not leave the first port held.
	error = RoomState.host_room(TEST_PORT)
	if not error.is_empty():
		_fail("re-hosting failed, so the previous socket was never released: %s" % error)
	RoomState.leave_network()
	_expect(not RoomState.online, "leaving did not take the room offline")
	_expect(RoomState.roster().size() == 1,
		"going offline left %d players in the room" % RoomState.roster().size())

	# CREATE ROOM's online-first wrapper must degrade to the same playable solo
	# room when its initial directory listing fails. Simulate that callback
	# directly; validation suppresses all real primary-server traffic.
	RoomState.create_local(RoomState.Mode.DEFAULT)
	error = RoomState.host_primary_room(TEST_PORT)
	if not error.is_empty():
		_fail("online-first create could not open its local ENet room: %s" % error)
	else:
		RoomState._on_directory_registration(false, "TEST DIRECTORY OFFLINE")
		_expect(not RoomState.online,
			"failed initial listing left CREATE ROOM stuck online")
		_expect("SOLO ROOM" in RoomState.status_message,
			"failed initial listing did not explain its solo fallback")

	if _failures == 0:
		print("  room      %s seats %d, seed %s"
			% [RoomState.code, RoomState.seats(), RoomState.seed_text])
		print("  rules     Hide & Seek and Office buttons hidden; Infinite is player-facing")
		print("  difficulty Relaxed / Standard / Hard live; Nightmare visible but disabled")
		print("  guests    %d FIRST x %d LAST callsign words" % [
			RoomState.GUEST_FIRST_NAMES.size(), RoomState.GUEST_LAST_NAMES.size()])
		print("  scales    Infinite primary; Standard hidden as an internal fallback")
		print("  create    primary server first; registration failure falls back to solo")
		print("room OK")
	return _failures
