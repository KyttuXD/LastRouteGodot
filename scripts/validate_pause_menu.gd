extends RefCounted

## The pause menu's tabs and statistics page: only the open page's tab is lit (PAUSE / SAVES / STATISTICS), and the
## statistics page scrolls so its last row can be brought into view at 480x270, 1024x768, phone landscape and a small XR-panel
## size, with a visible house-style scrollbar.
##
##   godot --headless --path . res://scenes/validate.tscn -- pause_menu

const SIZES := {"480x270": Vector2i(480, 270), "1024x768": Vector2i(1024, 768), "phone844x390": Vector2i(844, 390), "xr640x360": Vector2i(640, 360)}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


static func _lit(button: Button) -> bool:
	var box := button.get_theme_stylebox("normal") as StyleBoxFlat
	return box != null and box.bg_color == Palette.ACCENT


func run(host: Node) -> int:
	for key in SIZES:
		var pixels: Vector2i = SIZES[key]
		var holder := SubViewport.new()
		holder.size = pixels
		var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
		holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
		holder.size_2d_override_stretch = true
		host.add_child(holder)
		var menu := PauseMenu.new()
		menu.pauses_tree = false
		menu.statistics_source = func() -> Dictionary:
			var rows := {}
			for i in 14:
				rows["STAT ROW %02d" % i] = str(i * 7)
			rows["CURRENT FLOOR"] = "-3"
			return rows
		menu.save_status_source = func() -> String: return "RUN SAVED AT LEVEL -3, 14:05"
		holder.add_child(menu)
		await host.get_tree().process_frame
		menu.open()
		await host.get_tree().process_frame
		for page in ["statistics", "pause"]:
			menu._set_section(page)
			await host.get_tree().process_frame
			for id in menu._tabs:
				_expect(_lit(menu._tabs[id]) == (id == page), "%s: tab %s lit=%s while %s is open" % [key, id, _lit(menu._tabs[id]), page])
		menu._set_section("statistics")
		for _i in 3:
			await host.get_tree().process_frame
		var scroll := menu._statistics_scroll
		_expect(scroll != null and scroll.get_v_scroll_bar().visible, "%s: the statistics page has no visible scrollbar" % key)
		menu.scroll_statistics_to_end()
		for _i in 2:
			await host.get_tree().process_frame
		var last := menu._statistics_grid.get_child(menu._statistics_grid.get_child_count() - 1) as Control
		var view := scroll.get_global_rect().grow(1.0)
		_expect(last != null and view.encloses(last.get_global_rect()), "%s: the last statistic cannot be scrolled into view (%s in %s)" % [key, last.get_global_rect() if last != null else Rect2(), view])
		_expect(Rect2(Vector2.ZERO, units).grow(1.0).encloses(scroll.get_global_rect()), "%s: the statistics scroller leaves the window" % key)
		# SAVES: no slot page any more, one status line under RETURN
		menu._set_section("pause")
		await host.get_tree().process_frame
		var status := menu.find_child("PauseSaveStatus", true, false) as Label
		_expect(not menu._tabs.has("saves") and status != null and status.is_visible_in_tree() \
			and status.text == "RUN SAVED AT LEVEL -3, 14:05", "%s: the pause page lacks the run-saved line (or still has a SAVES tab)" % key)
		_expect(status != null and Rect2(Vector2.ZERO, units).grow(1.0).encloses(status.get_global_rect()), "%s: the run-saved line leaves the window" % key)
		menu.close()
		holder.queue_free()
		await host.get_tree().process_frame
	if _failures == 0:
		print("  pausemenu only the open tab is lit; statistics scrolls to its last row, the run-saved line shows at 480x270, 1024x768, phone, XR panel")
	return _failures
