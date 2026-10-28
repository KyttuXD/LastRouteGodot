extends RefCounted

## Headless check that the UI survives the screen it is put on.
##
## Everything 2D is authored against a 480 x 270 design size, and the project
## stretches that with aspect "expand" -- so a window that is not 16:9 does not
## get black bars, it gets MORE viewport. That is only an improvement if the
## layout is anchored: a HUD pinned by absolute offsets in a 480 x 270 grid
## drifts into the middle of a wider screen and leaves the corners empty, which
## is exactly what these scenes used to do.
##
## Anchors are invisible in a screenshot at the design size, because that is
## the one size where right and wrong agree. This drives the window through
## five real aspect ratios instead and compares.
##
## Run with:
##   godot4 --headless res://scenes/validate.tscn -- layout

## The suite runs inside scenes/validate.tscn, so the tree comes from the host
## node rather than from `self` -- see scripts/validate_runner.gd for why these
## are not `--script` SceneTree scripts any more.
var _host: Node


func _tree() -> SceneTree:
	return _host.get_tree()


func _root() -> Window:
	return _host.get_tree().root


func _frame() -> Signal:
	return _host.get_tree().process_frame


const SIZES := [
	Vector2i(480, 270),     # exact 1x design-scale window
	Vector2i(960, 540),     # exact 2x design-scale window
	Vector2i(1920, 1080),   # 16:9, the design aspect
	Vector2i(1920, 1200),   # 16:10
	Vector2i(2560, 1080),   # 21:9 ultrawide
	Vector2i(3440, 1440),   # 21:9 ultrawide at a different render scale
	Vector2i(1024, 768),    # 4:3
	Vector2i(800, 600),     # compact 4:3
	Vector2i(1366, 768),    # a small laptop, below two design sizes
]

## scene -> node -> which edges it must stay glued to.
const ANCHORED := {
	"res://scenes/hud.tscn": {
		"ObjectivePanel": ["right", "top"],
		"MinimapPanel": ["right", "top"],
		"MetersPanel": ["left", "right", "bottom"],
		"FpsLabel": ["left", "top"],
		"HotbarPanel": ["hcentre", "bottom"],
		"InteractionLabel": ["hcentre", "vcentre"],   # just under the crosshair
		"MessageLabel": ["hcentre", "top"],
		"MapOverlay": ["hcentre", "vcentre"],
		"EscapeOverlay": ["hcentre", "vcentre"],
	},
	"res://scenes/main_menu.tscn": {
		"KickerLabel": ["hcentre", "vcentre"],
		"BrandLabel": ["hcentre", "vcentre"],
		"TitleLabel": ["hcentre", "vcentre"],
		"LedeLabel": ["hcentre", "vcentre"],
		"ButtonPanel": ["hcentre", "vcentre"],
		"VersionLabel": ["hcentre", "bottom"],
		"SettingsOverlay": ["hcentre", "vcentre"],
	},
	"res://scenes/boot_loading.tscn": {
		"BootLoadingPanel": ["hcentre", "vcentre"],
	},
	"res://scenes/update_progress.tscn": {
		"UpdateProgressPanel": ["hcentre", "vcentre"],
	},
	# Staging is built in code and grows with the room, so it is exactly the
	# screen most likely to push its own start button off the bottom.
	"res://scenes/room_lobby.tscn": {
		"StagingPanel": ["hcentre", "vcentre"],
	},
	"res://scenes/route_loading.tscn": {
		"LoadingPanel": ["hcentre", "vcentre"],
	},
	"res://scenes/run_report.tscn": {
		"ReportPanel": ["hcentre", "vcentre"],
	},
}

## How much the distance from an anchored edge may vary between viewport
## shapes, in design pixels. Not an absolute margin: elements are deliberately
## inset (the interaction prompt sits 79 px above the bottom), and an inset
## that stays the same on every screen is exactly what correct anchoring looks
## like. What is being caught is a gap that GROWS with the viewport, which is
## an element pinned to the design size instead of to an edge.
const DRIFT_TOLERANCE := 1.5


func run(host: Node) -> int:
	_host = host
	var failures := 0
	for path in ANCHORED:
		failures += await _check_scene(path)
	if failures == 0:
		print("layout OK")
	return failures


func _fail(message: String) -> int:
	print("  FAIL  %s" % message)
	return 1


func _check_scene(path: String) -> int:
	var failures := 0
	var packed: PackedScene = load(path)
	if packed == null:
		return _fail("could not load %s" % path)
	var scene: Node = packed.instantiate()
	# The real loading scene immediately requests the gameplay PackedScene. Keep
	# it on this screen while its layout and state contract are inspected.
	if path in ["res://scenes/route_loading.tscn", "res://scenes/boot_loading.tscn",
			"res://scenes/update_progress.tscn"]:
		scene.set("auto_start", false)
	_root().add_child(scene)
	if path == "res://scenes/run_report.tscn":
		scene.call("open", {
			"online": false, "reason": "CAPTURED BY AKI", "depth": 8,
			"score": 4200, "relays": 3, "relay_target": 6, "coins": 12,
			"difficulty": "HARD", "seed": "ROOM-REPORT-1234567890",
		})
	await _frame()

	var widest := 0.0
	var gaps := {}          # "node/edge" -> the distances seen across sizes
	for size in SIZES:
		_root().size = size
		# Two frames: one for the window resize, one for the containers inside
		# it to settle against their new anchors.
		await _frame()
		await _frame()
		var view := _root().get_visible_rect()
		widest = maxf(widest, view.size.x)
		for name in ANCHORED[path]:
			var node := scene.find_child(name, true, false)
			if node == null or not node is Control:
				failures += _fail("%s: no Control named %s" % [path, name])
				continue
			failures += _measure(path, size, view, node as Control,
				ANCHORED[path][name], gaps)

	# Siblings must not land on each other. Containment and drift both passed
	# while the menu title sat ON the button panel: title anchored to the top,
	# panel to the centre, so a taller viewport walked them together. Nothing
	# was off-screen and nothing drifted -- they just collided.
	failures += _check_overlaps(scene, path)

	for key in gaps:
		var seen: Array = gaps[key]
		var drift: float = seen.max() - seen.min()
		if drift > DRIFT_TOLERANCE:
			failures += _fail("%s %s drifts %.0f px between viewport shapes -- it is "
				% [path.get_file(), key, drift]
				+ "pinned to the design size, not to that edge")

	if path == "res://scenes/main_menu.tscn":
		failures += await _check_main_menu_contract(scene)
	elif path == "res://scenes/hud.tscn":
		failures += _check_hud_contract(scene)
	elif path == "res://scenes/room_lobby.tscn":
		failures += await _check_room_lobby_contract(scene)
	elif path == "res://scenes/route_loading.tscn":
		failures += await _check_route_loading_contract(scene)
	elif path == "res://scenes/boot_loading.tscn":
		failures += await _check_boot_loading_contract(scene)
	elif path == "res://scenes/update_progress.tscn":
		failures += await _check_update_progress_contract(scene)
	elif path == "res://scenes/run_report.tscn":
		failures += await _check_run_report_contract(scene)

	_root().size = Vector2i(960, 540)
	scene.queue_free()
	await _frame()
	print("  %-28s %d nodes held across %d aspect ratios, up to %.0f design px wide"
		% [path.get_file(), ANCHORED[path].size(), SIZES.size(), widest])
	return failures


func _check_hud_contract(scene: Node) -> int:
	var failures := 0
	if scene.find_child("CompactStatusLabel", true, false) != null:
		failures += _fail("HUD still carries the obsolete lamp/stamina text row")
	var stamina := scene.find_child("CompactStaminaBar", true, false) as ProgressBar
	if stamina == null:
		failures += _fail("HUD has no compact colored stamina bar")
	elif stamina.size.x > 180.0 or stamina.size.y > 12.0:
		failures += _fail("compact stamina bar is too large for the hotbar HUD")
	var objective := scene.find_child("ObjectivePanel", true, false) as Control
	var minimap := scene.find_child("MinimapPanel", true, false) as Control
	if objective == null or minimap == null:
		failures += _fail("HUD is missing the objective panel or minimap")
	elif Rect2(objective.global_position, objective.size).intersects(
			Rect2(minimap.global_position, minimap.size)):
		failures += _fail("the compact minimap still covers the objective panel")
	elif minimap.size.x > 100.0 or minimap.size.y > 82.0:
		failures += _fail("minimap did not shrink to the compact HUD size")
	scene.call("update_infinite_status", 4, 11, 73)
	scene.call("set_hold_message", "STATIONARY // THREAT 8s")
	var hold := scene.find_child("MessageLabel", true, false) as Label
	if hold == null or not hold.visible or hold.text != "STATIONARY // THREAT 8s":
		failures += _fail("AFK warning does not use the existing HUD message line")
	scene.call("set_hold_message", "")
	var danger_row := scene.find_child("DangerRow", true, false) as HBoxContainer
	var danger_label := scene.find_child("DangerLabel", true, false) as Label
	var danger_bar := scene.find_child("DangerBar", true, false) as ProgressBar
	if danger_row == null or not danger_row.visible or danger_label == null \
			or danger_label.text != "DANGER 73%" or danger_bar == null \
			or not is_equal_approx(danger_bar.value, 73.0):
		failures += _fail("Infinite danger does not drive the compact route-panel meter")
	if scene.find_child("DangerPulse", true, false) != null:
		failures += _fail("the removed pain-style danger vignette still occupies the HUD")
	if (scene.find_child("RelayLabel", true, false) as Label).text.contains("DANGER"):
		failures += _fail("HUD displays a duplicate legacy danger percentage")
	if scene.find_child("InventoryDragGhost", true, false) == null:
		failures += _fail("inventory has no cursor-following drag visual")
	var legend := scene.find_child("Legend", true, false) as Label
	if legend == null or "TEAL-BLUE relay" not in legend.text \
			or "YELLOW battery" not in legend.text:
		failures += _fail("map legend does not distinguish teal relays from yellow batteries")
	# F1 must hide the ordinary play HUD without blanking modal/critical UI.
	# Calling the same input path catches regressions where a helper exists but
	# the requested key was never actually wired to it.
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.physical_keycode = KEY_F1
	f1.pressed = true
	scene.call("_input", f1)
	if not bool(scene.call("hud_is_hidden")):
		failures += _fail("F1 does not hide the gameplay HUD")
	for node_name in ["ObjectivePanel", "HotbarPanel", "CompactStaminaBar",
			"FpsLabel", "InteractionLabel", "MessageLabel",
			"Crosshair", "MinimapPanel"]:
		var surface := scene.find_child(node_name, true, false) as CanvasItem
		if surface == null or surface.modulate.a > .001:
			failures += _fail("F1 leaves %s visible" % node_name)
	for node_name in ["MapOverlay", "EscapeOverlay", "InventoryOverlay"]:
		var modal := scene.find_child(node_name, true, false) as CanvasItem
		if modal == null or modal.modulate.a < .999:
			failures += _fail("F1 also hides the %s modal" % node_name)
	scene.call("_input", f1)
	if bool(scene.call("hud_is_hidden")) \
			or (objective != null and objective.modulate.a < .999):
		failures += _fail("a second F1 press does not restore the gameplay HUD")
	return failures


func _check_route_loading_contract(scene: Node) -> int:
	var failures := 0
	for node_name in ["OuterFrame", "InnerFrame", "RouteSeedLabel", "RouteConfigurationLabel",
			"RouteLoadProgress", "RouteLoadPhase"]:
		if scene.find_child(node_name, true, false) == null:
			failures += _fail("route loading screen is missing %s" % node_name)
	if scene.find_child("TipPanel", true, false) != null \
			or scene.find_child("RouteTipLabel", true, false) != null:
		failures += _fail("route loading screen still contains field notes")
	for frame_name in ["OuterFrame", "InnerFrame"]:
		var frame := scene.find_child(frame_name, true, false) as Control
		if frame != null and (frame.anchor_left != 0.0 or frame.anchor_top != 0.0
				or frame.anchor_right != 1.0 or frame.anchor_bottom != 1.0):
			failures += _fail("route loading %s is not anchored as an edge frame" % frame_name)
	var panel := scene.find_child("LoadingPanel", true, false) as Control
	if panel == null or not _root().get_visible_rect().encloses(
			Rect2(panel.global_position, panel.size)):
		failures += _fail("route loading panel spills outside the viewport")

	scene.call("show_waiting_for_snapshot")
	await _frame()
	var phase := scene.find_child("RouteLoadPhase", true, false) as Label
	var progress := scene.find_child("RouteLoadProgress", true, false) as ProgressBar
	if phase == null or "WAITING FOR HOST" not in phase.text:
		failures += _fail("guest loading state does not say it is waiting for the host")
	if progress == null or not progress.indeterminate:
		failures += _fail("guest host-snapshot wait is not visibly indeterminate")
	scene.call("show_snapshot_retry", "TEST SNAPSHOT FAILURE")
	await _frame()
	var status := scene.find_child("RouteLoadStatus", true, false) as Label
	if status == null or status.text != "TEST SNAPSHOT FAILURE":
		failures += _fail("snapshot retry failure is hidden behind the loading screen")
	scene.call("dismiss")
	if scene.visible:
		failures += _fail("accepted route loading screen did not dismiss")
	return failures


func _check_update_progress_contract(scene: Node) -> int:
	var failures := 0
	for node_name in ["OuterFrame", "InnerFrame", "UpdateTitle", "UpdateProgress",
			"UpdatePhase", "UpdateStatus", "RetryUpdateButton", "ContinueOfflineButton"]:
		if scene.find_child(node_name, true, false) == null:
			failures += _fail("update progress screen is missing %s" % node_name)
	var panel := scene.find_child("UpdateProgressPanel", true, false) as Control
	if panel == null or not _root().get_visible_rect().encloses(
			Rect2(panel.global_position, panel.size)):
		failures += _fail("update progress panel spills outside the viewport")
	for frame_name in ["OuterFrame", "InnerFrame"]:
		var frame := scene.find_child(frame_name, true, false) as Control
		if frame != null and (frame.anchor_left != 0.0 or frame.anchor_top != 0.0
				or frame.anchor_right != 1.0 or frame.anchor_bottom != 1.0):
			failures += _fail("update progress %s is not anchored as an edge frame" % frame_name)
	var retry := scene.find_child("RetryUpdateButton", true, false) as Button
	var continue_button := scene.find_child("ContinueOfflineButton", true, false) as Button
	scene.call("_show_retry", "UPDATE DOWNLOAD FAILED // RETRY")
	await _frame()
	if retry == null or not retry.visible:
		failures += _fail("update progress failure has no retry action")
	# the update gate (KT): no CONTINUE OFFLINE past an available update, RETRY only
	if continue_button != null and continue_button.visible:
		failures += _fail("update progress failure offers a way past the update")
	if retry != null:
		retry.visible = false
	if continue_button != null:
		continue_button.visible = false
	scene.call("_on_update_status", "COULD NOT START UPDATE INSTALLER // RETRY")
	await _frame()
	if retry == null or not retry.visible:
		failures += _fail("update progress treats a helper-launch failure as a successful apply")
	if continue_button != null and continue_button.visible:
		failures += _fail("update progress helper-launch failure offers a way past the update")
	if retry != null:
		retry.visible = false
	if continue_button != null:
		continue_button.visible = false
	scene.call("_on_update_status", "COULD NOT UNPACK UPDATE // RETRY")
	await _frame()
	if retry == null or not retry.visible:
		failures += _fail("update progress hides unpack failures instead of offering retry")
	if retry != null:
		retry.visible = false
	if continue_button != null:
		continue_button.visible = false
	scene.call("_on_update_status", UpdateManager.PLATFORM_MISMATCH_STATUS)
	await _frame()
	var phase := scene.find_child("UpdatePhase", true, false) as Label
	if retry == null or not retry.visible:
		failures += _fail("update progress hides a platform-mismatch footer instead of offering retry")
	if phase != null and phase.text == "APPLYING UPDATE":
		failures += _fail("update progress headlines APPLYING UPDATE for a platform-mismatch failure")
	if phase != null and phase.text != "UPDATE INTERRUPTED":
		failures += _fail("update progress does not mark a platform-mismatch as interrupted")
	if not scene.has_method("_start_install"):
		failures += _fail("update progress screen cannot hand off a staged desktop install")
	var was_installing: bool = UpdateManager.installing
	scene.call("_start_install")
	if UpdateManager.installing and not was_installing:
		failures += _fail("update progress screen started the helper before a build was staged")
		UpdateManager.installing = false
	return failures


func _check_boot_loading_contract(scene: Node) -> int:
	var failures := 0
	for node_name in ["OuterFrame", "InnerFrame", "BootTitle", "BootProgress",
			"BootPhase", "BootStatus", "RetryUpdateButton", "ContinueOfflineButton"]:
		if scene.find_child(node_name, true, false) == null:
			failures += _fail("boot loading screen is missing %s" % node_name)
	var panel := scene.find_child("BootLoadingPanel", true, false) as Control
	if panel == null or not _root().get_visible_rect().encloses(
			Rect2(panel.global_position, panel.size)):
		failures += _fail("boot loading panel spills outside the viewport")
	var retry := scene.find_child("RetryUpdateButton", true, false) as Button
	var continue_button := scene.find_child("ContinueOfflineButton", true, false) as Button
	scene.call("_show_retry", "UPDATE CHECK REQUIRED", false)
	await _frame()
	if retry == null or not retry.visible:
		failures += _fail("mandatory startup update failure has no retry action")
	if continue_button == null or not continue_button.visible:
		failures += _fail("mandatory startup failure has no explicit offline test path")
	scene.call("_show_retry", "OPTIONAL UPDATE FAILED", true)
	await _frame()
	if continue_button == null or not continue_button.visible:
		failures += _fail("ordinary startup update failure cannot continue offline")
	if not scene.has_method("_handoff_desktop_update"):
		failures += _fail("boot loading cannot hand a desktop update to the main menu")
	var was_installing: bool = UpdateManager.installing
	scene.call("_on_update_ready", "user://updates/staged-layout-test")
	if UpdateManager.installing and not was_installing:
		failures += _fail("boot loading still quits immediately when a desktop update is ready")
		UpdateManager.installing = false
	return failures


func _check_run_report_contract(scene: Node) -> int:
	var failures := 0
	for node_name in ["OuterFrame", "InnerFrame", "ReportTitle", "EndReason",
			"RunStats", "ReportPrimaryButton", "ReportSecondaryButton"]:
		if scene.find_child(node_name, true, false) == null:
			failures += _fail("run report is missing %s" % node_name)
	var panel := scene.find_child("ReportPanel", true, false) as Control
	if panel == null or not _root().get_visible_rect().encloses(
			Rect2(panel.global_position, panel.size)):
		failures += _fail("run report spills outside the viewport")
	var primary := scene.find_child("ReportPrimaryButton", true, false) as Button
	var secondary := scene.find_child("ReportSecondaryButton", true, false) as Button
	if primary == null or primary.text != "RESTART ROUTE":
		failures += _fail("solo run report has no explicit restart action")
	if secondary == null or secondary.text != "MAIN MENU":
		failures += _fail("solo run report has no main-menu action")
	var depth := scene.find_child("DepthReachedValue", true, false) as Label
	if depth == null or depth.text != "8":
		failures += _fail("run report did not display the completed route statistics")
	for value_name in ["DepthReachedValue", "ScoreValue", "FloorRelaysValue",
			"CoinsValue", "DifficultyValue", "RouteSeedValue"]:
		var value := scene.find_child(value_name, true, false) as Label
		if value == null or value.size.x < 100.0:
			failures += _fail("run report %s value column collapsed" % value_name)

	scene.call("open", {
		"online": true, "host": false, "reason": "CAPTURED BY AKI", "depth": 8,
		"score": 4200, "relays": 3, "relay_target": 6, "coins": 12,
		"difficulty": "HARD", "seed": "ROOM-REPORT-1234567890",
	})
	await _frame()
	if primary == null or primary.text != "LEAVE ROOM":
		failures += _fail("captured guest is offered a hidden respawn/rejoin")
	if secondary == null or secondary.visible:
		failures += _fail("co-op elimination report exposes a second life path")
	scene.call("open", {
		"online": true, "host": true, "reason": "CAPTURED BY AKI", "depth": 8,
		"score": 4200, "relays": 3, "relay_target": 6, "coins": 12,
		"difficulty": "HARD", "seed": "ROOM-REPORT-1234567890",
	})
	await _frame()
	if primary == null or primary.text != "END ROUTE":
		failures += _fail("captured host is not offered the explicit end-route action")
	scene.call("close")
	if scene.call("is_open"):
		failures += _fail("run report did not close after its action")
	return failures


func _check_room_lobby_contract(scene: Node) -> int:
	var failures := 0
	var dossier_button := scene.find_child("DossierButton", true, false) as Button
	if dossier_button == null or dossier_button.text != "HUNTER DOSSIER":
		return _fail("room staging is missing the hunter dossier action")

	# Discovery belongs to a verified account. Seed one known hunter and ensure
	# the categorized roster keeps every other identity hidden.
	var account_before := {
		"username": Backend.account_username,
		"token": Backend.account_session_token,
		"verified": Backend.account_session_verified,
		"progress": Backend.account_progress.duplicate(true),
	}
	Backend.account_username = "DOSSIER_TEST"
	Backend.account_session_token = "validation-token"
	Backend.account_session_verified = true
	Backend.account_progress = {
		"schema": 1,
		"kind": "profile",
		"hunter_discoveries": ["aki"],
	}
	# The dossier is dynamic, scrolls the complete roster, and must remain usable
	# at the smallest design window as well as ultrawide/full-resolution screens.
	scene.call("_on_dossier_pressed")
	await _frame()
	var dossier := scene.find_child("DossierRoster", true, false) as ItemList
	if dossier == null or dossier.item_count != HunterRoster.PROFILES.size() + 2:
		failures += _fail("hunter dossier does not list every categorized hunter")
	elif dossier.get_item_text(0) != "-- A-Z HUNTERS --" \
			or dossier.get_item_text(27) != "-- VOID HUNTERS --":
		failures += _fail("hunter dossier category headers are missing or out of order")
	elif dossier.get_item_text(1) != "AKI" \
			or dossier.get_item_text(2) != "???":
		failures += _fail("hunter dossier does not reveal only account discoveries")
	for node_name in ["DossierName", "DossierBehavior", "DossierStats"]:   # the counter label is retired: always hidden and empty
		var label := scene.find_child(node_name, true, false) as Label
		if label == null or label.text.is_empty():
			failures += _fail("hunter dossier is missing populated %s" % node_name)
	if dossier != null and dossier.item_count > 3:
		var final_hunter := dossier.item_count - 1
		dossier.select(final_hunter)
		dossier.item_selected.emit(final_hunter)
		await _frame()
		var selected_name := scene.find_child("DossierName", true, false) as Label
		if selected_name == null or selected_name.text.is_empty():
			failures += _fail("hunter dossier selection did not update its detail card")
	var close := scene.find_child("DossierCloseButton", true, false) as Button
	if close == null or close.find_child("EscCloseContent", true, false) == null:
		failures += _fail("room dossier does not use the ESC keycap close control")
	for size in [Vector2i(480, 270), Vector2i(1024, 768), Vector2i(3440, 1440)]:
		_root().size = size
		await _frame()
		await _frame()
		var dossier_panel := scene.find_child("DossierPanel", true, false) as Control
		if dossier_panel == null or not _root().get_visible_rect().encloses(
				Rect2(dossier_panel.global_position, dossier_panel.size)):
			failures += _fail("hunter dossier spills outside %s" % size)
	scene.call("_close_modal")
	Backend.account_username = account_before["username"]
	Backend.account_session_token = account_before["token"]
	Backend.account_session_verified = account_before["verified"]
	Backend.account_progress = account_before["progress"]
	await _frame()
	return failures


func _check_main_menu_contract(scene: Node) -> int:
	var failures := 0
	if scene.find_child("RouteNotice", true, false) != null:
		failures += _fail("main menu still carries the removed room-description line")
	var generic_input := LineEdit.new()
	Palette.style_line_edit(generic_input)
	if generic_input.text_direction != Control.TEXT_DIRECTION_LTR \
			or generic_input.alignment != HORIZONTAL_ALIGNMENT_LEFT:
		failures += _fail("shared text inputs are not forced left-to-right")
	generic_input.free()
	if not scene.has_method("_on_create_health_checked"):
		failures += _fail("CREATE ROOM has no primary-server health/fallback flow")
	var settings := scene.find_child("SettingsButton", true, false) as Button
	if settings == null or settings.text != "SETTINGS":
		failures += _fail("main menu does not label the categorized panel SETTINGS")
	if scene.find_child("DossierButton", true, false) != null:
		failures += _fail("hunter dossier is still exposed on the main menu")
	for heading in ["AudioHeading", "DisplayHeading", "ControlsHeading"]:
		if scene.find_child(heading, true, false) == null:
			failures += _fail("Settings is missing its %s category" % heading)
	var settings_tabs := scene.find_child("SettingsCategoryTabs", true, false) as TabBar
	if settings_tabs == null or settings_tabs.tab_count != 5 \
			or settings_tabs.get_tab_title(0) != "AUDIO" \
			or settings_tabs.get_tab_title(1) != "DISPLAY" \
			or settings_tabs.get_tab_title(2) != "CONTROLS" \
			or settings_tabs.get_tab_title(3) != "SKIN" \
			or settings_tabs.get_tab_title(4) != "VOICE":
		failures += _fail("Settings categories do not use the shared tab treatment")
	if scene.find_child("PixelEffectSlider", true, false) == null \
			or scene.find_child("PixelEffectValueLabel", true, false) == null:
		failures += _fail("Settings is missing the 3D signal-filter intensity control")
	if scene.find_child("PlayerHueSlider", true, false) == null \
			or scene.find_child("PlayerHueValueLabel", true, false) == null:
		failures += _fail("Settings is missing the player skin hue control")
	for control_name in ["SfxVolumeSlider", "UiVolumeSlider", "VsyncButton",
			"FpsLimitSlider", "FovSlider"]:
		if scene.find_child(control_name, true, false) == null:
			failures += _fail("Settings is missing %s" % control_name)
	var fov := scene.find_child("FovSlider", true, false) as HSlider
	if fov != null and (fov.min_value != Settings.MIN_FIELD_OF_VIEW \
			or fov.max_value != Settings.MAX_FIELD_OF_VIEW):
		failures += _fail("FOV slider does not use Settings' supported range")
	var play_button := scene.find_child("PlayButton", true, false) as Button
	var join_button := scene.find_child("JoinButton", true, false) as Button
	var offline_button := scene.find_child("OfflineButton", true, false) as Button
	scene.call("_set_route_update_locked", "UPDATING")
	if play_button == null or join_button == null or not play_button.disabled \
			or not join_button.disabled or play_button.text != "UPDATING" \
			or join_button.text != "UPDATING":
		failures += _fail("mandatory updates do not lock and relabel both route buttons")
	if offline_button == null or offline_button.disabled \
			or offline_button.text != "PLAY OFFLINE":
		failures += _fail("main menu has no independent offline solo test path")
	scene.call("_clear_route_update_lock")
	if play_button == null or join_button == null or play_button.disabled \
			or join_button.disabled or play_button.text != "CREATE ROOM" \
			or join_button.text != "JOIN ROOM":
		failures += _fail("route buttons do not recover after the update gate clears")
	if not scene.has_method("_open_update_progress_if_needed"):
		failures += _fail("main menu cannot switch to the desktop update-in-progress screen")
	elif bool(scene.call("_open_update_progress_if_needed")):
		failures += _fail("main menu opened the update screen without a required desktop update")
	scene.call("_on_join_pressed")
	await _frame()
	var room_code_input := scene.find_child("RoomCodeInput", true, false) as LineEdit
	if scene.find_child("MenuModal", true, false) == null or room_code_input == null:
		failures += _fail("Join Room did not open before the periodic-update test")
	else:
		room_code_input.text = "a"
		room_code_input.caret_column = 1
		scene.call("_on_join_code_changed", "a")
		room_code_input.insert_text_at_caret("b")
		scene.call("_on_join_code_changed", room_code_input.text)
		if room_code_input.text != "AB" or room_code_input.caret_column != 2:
			failures += _fail("room-code normalization reverses typed characters")
	scene.call("_set_route_update_locked", "UPDATING")
	await _frame()
	if scene.find_child("MenuModal", true, false) != null:
		failures += _fail("a newly discovered update leaves an existing Join dialog open")
	scene.call("_clear_route_update_lock")
	var settings_close := scene.find_child("CloseButton", true, false) as Button
	if settings_close == null or settings_close.find_child("EscCloseContent", true, false) == null:
		failures += _fail("Settings close action does not use the ESC keycap control")
	var fullscreen := scene.find_child("FullscreenButton", true, false) as Button
	if fullscreen == null or fullscreen.find_child("StateChip", true, false) == null:
		failures += _fail("Fullscreen does not expose a boxed ON/OFF state chip")

	# Dynamic dialogs use the same control. Opening one here catches regressions
	# that a static scene-file scan cannot see.
	scene.call("_on_tutorial_pressed")
	await _frame()
	var modal := scene.find_child("MenuModal", true, false)
	if modal == null or modal.find_child("EscCloseContent", true, false) == null:
		failures += _fail("menu dialogs do not use the ESC keycap close control")
	scene.call("_close_modal")
	await _frame()

	# Failed account requests must remain readable. This used to rebuild the
	# dialog on every account signal, erasing the server error one frame later.
	# Isolate this from a developer's persisted local login/custom-host state;
	# validation must always exercise the signed-out primary-host form.
	var account_before := {
		"username": Backend.account_username,
		"token": Backend.account_session_token,
		"admin": Backend.account_admin,
		"admin_owner": Backend.account_admin_owner,
		"admin_permissions": Backend.account_admin_permissions.duplicate(),
		"verified": Backend.account_session_verified,
		"progress": Backend.account_progress.duplicate(true),
		"saved_at": Backend.account_progress_saved_at,
		"base_url": Backend.base_url,
	}
	Backend.account_username = ""
	Backend.account_session_token = ""
	Backend.account_admin = false
	Backend.account_admin_owner = false
	Backend.account_admin_permissions = PackedStringArray()
	Backend.account_session_verified = false
	Backend.base_url = Backend.PRIMARY_BASE_URL
	scene.call("_close_modal")
	Backend.account_username = account_before["username"]
	Backend.account_session_token = account_before["token"]
	Backend.account_session_verified = account_before["verified"]
	Backend.account_progress = account_before["progress"]
	await _frame()
	return failures


## Every anchored node in a scene, checked pairwise. Text can legitimately sit
## over a backdrop, so full-rect nodes are skipped -- they ARE the backdrop.
func _check_overlaps(scene: Node, path: String) -> int:
	var failures := 0
	var rects := {}
	var view := _root().get_visible_rect()
	for name in ANCHORED[path]:
		var node := scene.find_child(name, true, false) as Control
		if node == null or not node.visible:
			continue
		var rect := Rect2(node.global_position, node.size)
		if rect.size.x >= view.size.x * 0.95 and rect.size.y >= view.size.y * 0.95:
			continue
		rects[name] = rect
	var names: Array = rects.keys()
	names.sort()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			var hit := a.intersection(b)
			if hit.size.x > 1.0 and hit.size.y > 1.0:
				failures += _fail("%s %s overlaps %s by %.0f x %.0f px"
					% [path.get_file(), names[i], names[j], hit.size.x, hit.size.y])
	return failures


func _measure(path: String, size: Vector2i, view: Rect2,
		node: Control, edges: Array, gaps: Dictionary) -> int:
	var failures := 0
	var rect := Rect2(node.global_position, node.size)
	var tag := "%s %s @%dx%d" % [path.get_file(), node.name, size.x, size.y]

	# Nothing may run off the screen, whatever it is anchored to. This is what
	# caught the meters row and the office control bar, both of which were
	# wider than the design size and had been overflowing all along.
	if rect.position.x < -1.0 or rect.position.y < -1.0 \
			or rect.end.x > view.size.x + 1.0 or rect.end.y > view.size.y + 1.0:
		failures += _fail("%s spills outside the %s viewport at %s"
			% [tag, view.size, rect])

	for edge in edges:
		var gap := 0.0
		match edge:
			"left": gap = rect.position.x
			"top": gap = rect.position.y
			"right": gap = view.size.x - rect.end.x
			"bottom": gap = view.size.y - rect.end.y
			"hcentre": gap = absf(rect.get_center().x - view.size.x * 0.5)
			"vcentre": gap = absf(rect.get_center().y - view.size.y * 0.5)
		var key := "%s/%s" % [node.name, edge]
		if not gaps.has(key):
			gaps[key] = []
		(gaps[key] as Array).append(gap)
	return failures
