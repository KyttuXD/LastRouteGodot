extends RefCounted

## The mod UI: Settings -> MODS (auto-download off by default and persisted, installed list, remove downloaded), the join dialog's
## confirm list / progress / error / PACKS DIFFER stages, auto-download skipping the confirm, no partial join, and that both fit
## and scroll at 480x270, 1024x768, phone landscape and the XR panel size. The loader is a fake provider behind ModPackApi.
##
##   godot --headless --path . res://tests/scenes/validate.tscn -- mods

const SIZES := {"480x270": Vector2i(480, 270), "1024x768": Vector2i(1024, 768), "phone844x390": Vector2i(844, 390), "xr640x360": Vector2i(640, 360)}

var _failures := 0
var _joined := 0
var _cancelled := 0


class FakeLoader:
	extends RefCounted
	var packs: Array = []
	var removed := 0
	var mode := "ok"   # ok | fail | hang
	var calls: Array = []
	var finish: Callable

	func installed_packs() -> Array:
		return packs

	func remove_downloaded() -> int:
		var kept := []
		var count := 0
		for pack in packs:
			if pack["source"] == "downloaded":
				count += 1
			else:
				kept.append(pack)
		packs = kept
		return count

	func download_packs(wanted: Array, on_progress: Callable, on_done: Callable) -> void:
		calls.append(wanted)
		if mode == "hang":
			finish = on_done
			on_progress.call(512, 2048, "Pack")
			return
		if mode == "fail":
			on_done.call(false, "HASH MISMATCH FOR %s" % String(wanted[0]["name"]).to_upper())
			return
		on_progress.call(2048, 2048, "Pack")
		for pack in wanted:
			var copy: Dictionary = pack.duplicate()
			copy["source"] = "downloaded"
			packs.append(copy)
		on_done.call(true, "")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _pack(id: String, source: String = "downloaded", version: String = "1.0", sha: String = "") -> Dictionary:
	return {"pack_id": id, "name": id.capitalize(), "author": "Someone", "version": version, "size": 1500000,
		"sha256": sha if not sha.is_empty() else (id + "0000000000").sha256_text(), "source": source}


func run(host: Node) -> int:
	var saved_auto := Settings.auto_download_mods
	var saved_provider := ModPackApi.provider
	_check_pure()
	await _check_panel(host)
	await _check_dialog(host)
	await _check_sizes(host)
	ModPackApi.provider = saved_provider
	Settings.auto_download_mods = saved_auto
	Settings.set_auto_download_mods(saved_auto)
	if _failures == 0:
		print("mods OK")
	return _failures


func _check_pure() -> void:
	_expect(ModPackApi.format_size(900) == "900 B" and ModPackApi.format_size(2048) == "2.0 KB" \
		and ModPackApi.format_size(3 * 1048576) == "3.0 MB", "pack sizes are formatted wrongly")
	_expect(ModPackApi.short_hash("0123456789abcdef") == "01234567", "the short hash is not 8 characters")
	var host := [_pack("a"), _pack("b"), _pack("c", "downloaded", "2.0")]
	var mine := [_pack("a"), _pack("c", "downloaded", "1.0", "x"), _pack("z", "local"), _pack("core", "builtin")]
	var diff := ModPackApi.diff(host, mine)
	_expect(diff["missing"].size() == 1 and diff["missing"][0]["pack_id"] == "b", "diff: missing wrong")
	_expect(diff["different"].size() == 1 and diff["different"][0]["pack_id"] == "c", "diff: different wrong")
	_expect(diff["extra"].size() == 1 and diff["extra"][0]["pack_id"] == "z", "diff: extra wrong (builtin must not count)")
	ModPackApi.provider = null
	_expect(ModPackApi.installed().is_empty() and ModPackApi.remove_downloaded() == 0, "no loader should mean an empty list")
	var result := [true, "x"]
	ModPackApi.download([_pack("a")], func(_d, _t, _n) -> void: pass, func(ok: bool, reason: String) -> void:
		result[0] = ok
		result[1] = reason)
	_expect(result[0] == false and not String(result[1]).is_empty(), "downloading with no loader must fail with a reason")


func _check_panel(host: Node) -> void:
	var fake := FakeLoader.new()
	fake.packs = [_pack("alpha"), _pack("beta", "local"), _pack("core", "builtin")]
	ModPackApi.provider = fake
	Settings.auto_download_mods = false
	var panel := ModsPanel.new()
	host.add_child(panel)
	await host.get_tree().process_frame
	_expect(Settings.auto_download_mods == false, "auto-download must default to off")
	_expect(panel.auto_button != null and panel.auto_button.find_child("StateToggleContent", true, false) != null, "no auto-download switch")
	var warning := panel.find_child("AutoDownloadWarning", true, false) as Label
	_expect(warning != null and warning.text.contains("trust"), "the auto-download warning line is missing")
	_expect(panel.find_child("Mod_alpha", true, false) != null and panel.find_child("Mod_core", true, false) != null, "installed packs are not listed")
	var detail := panel.find_child("ModDetail", true, false) as Label
	_expect(detail != null and detail.text.contains("SOMEONE") and detail.text.contains("MB"), "a pack row lacks author or size")
	_expect(panel.remove_button.text.contains("(1)"), "remove button should count 1 downloaded pack (%s)" % panel.remove_button.text)
	var saved_enabled: Array = Settings.mods_enabled.duplicate()
	Settings.mods_enabled = []
	var use := panel.find_child("Mod_beta", true, false).find_child("UseButton", true, false) as Button
	_expect(use != null, "a LOCAL pack has no USE IN MY ROOMS toggle")
	_expect(panel.find_child("Mod_alpha", true, false).find_child("UseButton", true, false) == null, "a downloaded pack must not be hostable")
	_expect(panel.find_child("Mod_core", true, false).find_child("UseButton", true, false) == null, "a built-in pack has a host toggle")
	if use != null:
		use.pressed.emit()
		_expect(Settings.mods_enabled == ["beta"], "the toggle did not enable the pack (%s)" % [Settings.mods_enabled])
		(panel.find_child("Mod_beta", true, false).find_child("UseButton", true, false) as Button).pressed.emit()
		_expect(Settings.mods_enabled.is_empty(), "the toggle did not disable the pack")
	Settings.mods_enabled = saved_enabled
	Settings.set_mod_enabled("", false)
	panel.auto_button.pressed.emit()
	_expect(Settings.auto_download_mods, "the switch did not turn auto-download on")
	panel.auto_button.pressed.emit()
	_expect(not Settings.auto_download_mods, "the switch did not turn auto-download off")
	panel.remove_button.pressed.emit()
	_expect(fake.packs.size() == 3, "one press removed mods without a confirm")
	panel.remove_button.pressed.emit()
	_expect(fake.packs.size() == 2 and panel.status.text.contains("REMOVED 1"), "the confirmed removal did not delete downloaded packs only")
	_expect(panel.remove_button.disabled, "remove should disable with nothing downloaded")
	panel.queue_free()
	await host.get_tree().process_frame
	var settings := load("res://game/menus/settings_overlay.tscn") as PackedScene
	var overlay := settings.instantiate()
	host.add_child(overlay)
	await host.get_tree().process_frame
	var tabs := overlay.find_child("SettingsCategoryTabs", true, false) as TabBar
	_expect(tabs != null and tabs.tab_count == 6 and tabs.get_tab_title(5) == "MODS", "Settings has no MODS tab")
	if tabs != null:
		_expect(tabs.get_tab_rect(5).end.x <= tabs.size.x + 1.0, "the MODS tab is cut off the end of the tab bar (%s of %s)" % [tabs.get_tab_rect(5), tabs.size])
	var section := overlay.find_child("ModsSection", true, false) as ModsPanel
	if section != null and tabs != null:
		_expect(not section.visible, "MODS shows before its tab is picked")
		tabs.current_tab = 5
		await host.get_tree().process_frame
		_expect(section.visible, "MODS is hidden on its tab")
		tabs.current_tab = 0
		await host.get_tree().process_frame
		_expect(not section.visible, "MODS shows on other tabs")
	else:
		_expect(false, "the MODS section is missing")
	overlay.queue_free()
	await host.get_tree().process_frame


func _dialog(host: Node) -> ModJoinDialog:
	var dialog := ModJoinDialog.new()
	_joined = 0
	_cancelled = 0
	dialog.join_allowed.connect(func() -> void: _joined += 1)
	dialog.cancelled.connect(func() -> void: _cancelled += 1)
	host.add_child(dialog)
	return dialog


func _check_dialog(host: Node) -> void:
	var fake := FakeLoader.new()
	fake.packs = [_pack("have", "local")]
	ModPackApi.provider = fake
	Settings.auto_download_mods = false
	var host_list := [_pack("have", "local"), _pack("need1"), _pack("need2")]

	# identical lists join straight away with no dialog
	var dialog := _dialog(host)
	await host.get_tree().process_frame
	dialog.begin([_pack("have", "local")])
	_expect(_joined == 1 and not dialog.visible, "matching packs should join without a dialog")

	# missing packs: confirm list with name, author, size, hash and the own-risk warning
	dialog.begin(host_list)
	_expect(dialog.visible and dialog.stage == ModJoinDialog.Stage.CONFIRM, "missing packs did not open the confirm list")
	_expect(dialog.list_box.get_child_count() == 2, "the confirm list should hold the 2 missing packs, not %d" % dialog.list_box.get_child_count())
	var first := dialog.list_box.get_child(0) as Label
	_expect(first != null and first.text.contains("SOMEONE") and first.text.contains("MB") and first.text.contains("#"),
		"a confirm row lacks author, size or hash (%s)" % (first.text if first != null else "none"))
	_expect(dialog.body.text.contains("own risk"), "the confirm lacks the own-risk warning")
	_expect(fake.calls.is_empty() and _joined == 1, "nothing may download before the player confirms")

	# cancel: no download, no join
	dialog.cancel_button.pressed.emit()
	_expect(_cancelled == 1 and not dialog.visible and fake.calls.is_empty() and _joined == 1, "cancel must leave without downloading or joining")

	# confirm + don't ask again: downloads, joins, and turns the setting on
	dialog.begin(host_list)
	dialog.ask_again.button_pressed = true
	dialog.confirm_button.pressed.emit()
	_expect(fake.calls.size() == 1 and fake.calls[0].size() == 2, "confirm did not download exactly the 2 missing packs")
	_expect(_joined == 2 and not dialog.visible, "a finished download should join")
	_expect(Settings.auto_download_mods, "'don't ask again' did not turn auto-download on")
	_expect(ModPackApi.installed().size() == 3, "the downloaded packs are not installed afterwards")

	# progress while downloading, and no join while it is unfinished
	Settings.auto_download_mods = false
	fake.packs = [_pack("have", "local")]
	fake.mode = "hang"
	dialog.begin(host_list)
	dialog.confirm_button.pressed.emit()
	_expect(dialog.stage == ModJoinDialog.Stage.DOWNLOADING and dialog.progress.visible, "no progress bar while downloading")
	_expect(is_equal_approx(dialog.progress.value / dialog.progress.max_value, 0.25), "progress is not 512/2048")
	_expect(dialog.progress_label.text.contains("PACK"), "the progress line does not name the pack")
	_expect(_joined == 2, "joined before the download finished")
	dialog.cancel_button.pressed.emit()
	_expect(_cancelled == 2 and _joined == 2, "cancelling mid-download should not join")

	# failure: clear error, no join, partial set never kept
	fake.packs = [_pack("have", "local")]
	fake.mode = "fail"
	dialog.begin(host_list)
	dialog.confirm_button.pressed.emit()
	_expect(dialog.stage == ModJoinDialog.Stage.ERROR and dialog.body.text.contains("HASH MISMATCH"), "a failed download did not show its reason")
	_expect(dialog.body.text.contains("NOT CONNECTED") and _joined == 2, "an error must say nothing joined")

	# auto-download on: no confirm, downloads at once
	fake.packs = [_pack("have", "local")]
	fake.mode = "ok"
	fake.calls.clear()
	Settings.auto_download_mods = true
	dialog.begin(host_list)
	_expect(fake.calls.size() == 1 and _joined == 3 and dialog.stage == ModJoinDialog.Stage.HIDDEN, "auto-download still asked for confirmation")

	# installed packs the host does not use never refuse a join
	Settings.auto_download_mods = false
	fake.packs = [_pack("have", "local"), _pack("mine", "local")]
	fake.calls.clear()
	var joined_before := _joined
	dialog.begin([_pack("have", "local")])
	_expect(_joined == joined_before + 1 and not dialog.visible and fake.calls.is_empty(), "an extra installed pack must not refuse or delay the join")
	# a public room refuses a modded host and shows what differs
	fake.packs = [_pack("have", "local")]
	dialog.begin([_pack("have", "local"), _pack("need1")], false)
	_expect(dialog.stage == ModJoinDialog.Stage.DIFFER and dialog.title.text == "PACKS DIFFER", "a public room did not show PACKS DIFFER")
	_expect(dialog.list_box.get_child_count() == 1 and (dialog.list_box.get_child(0) as Label).text.begins_with("MISSING"), "the differ list does not name the missing pack")
	fake.packs = [_pack("have", "local")]
	_expect(fake.calls.is_empty(), "a refused join must not download")
	dialog.queue_free()
	await host.get_tree().process_frame


func _check_sizes(host: Node) -> void:
	var fake := FakeLoader.new()
	for i in 12:
		fake.packs.append(_pack("pack%d" % i))
	ModPackApi.provider = fake
	var root := host.get_tree().root
	var before := root.size
	for label in SIZES:
		root.size = SIZES[label]
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var panel := ModsPanel.new()
		panel.size = Vector2(400, 176)
		host.add_child(panel)
		await host.get_tree().process_frame
		var bar := panel.get_v_scroll_bar()
		_expect(bar.max_value > bar.page, "%s: 12 packs should make the list scroll" % label)
		panel.scroll_vertical = int(bar.max_value)
		await host.get_tree().process_frame
		_expect(panel.remove_button.get_global_rect().end.y <= panel.get_global_rect().end.y + 1.0 \
			or panel.scroll_vertical > 0, "%s: the remove button cannot be scrolled into view" % label)
		panel.queue_free()
		var dialog := _dialog(host)
		await host.get_tree().process_frame
		var many := []
		for i in 10:
			many.append(_pack("host%d" % i))
		fake.packs = []
		dialog.begin(many)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var rect := (dialog.find_child("ModJoinPanel", true, false) as Control).get_global_rect()
		_expect(root.get_visible_rect().grow(1.0).encloses(rect), "%s: the join dialog spills out of the window (%s)" % [label, rect])
		_expect(dialog.confirm_button.get_global_rect().end.y <= root.get_visible_rect().end.y + 1.0, "%s: DOWNLOAD & JOIN is off screen" % label)
		dialog.queue_free()
		fake.packs = []
		for i in 12:
			fake.packs.append(_pack("pack%d" % i))
		await host.get_tree().process_frame
	root.size = before
