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
		menu.save_slots_source = func() -> Array:
			var slots := []
			for i in 9:
				slots.append({"slot_id": "slot_%d" % i, "name": "ROUTE %d" % i, "level": -i, "difficulty": "STANDARD",
					"elapsed_seconds": 60.0 * i, "saved_at": 1700000000 + i})
			return slots
		holder.add_child(menu)
		await host.get_tree().process_frame
		menu.open()
		await host.get_tree().process_frame
		for page in ["statistics", "saves", "pause"]:
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
		# SAVES: same header/frame style as STATISTICS and every slot reachable
		menu._set_section("saves")
		for _i in 3:
			await host.get_tree().process_frame
		var saves_scroll := menu._saves_scroll
		_expect(saves_scroll != null and saves_scroll.get_v_scroll_bar().visible, "%s: the saves page has no visible scrollbar" % key)
		var heading := menu.find_child("SavesHeading", true, false) as Label
		_expect(heading != null and heading.get_theme_color("font_color") == Palette.AMBER and heading.get_theme_font_size("font_size") == 8,
			"%s: the saves header does not match the statistics header" % key)
		var frame := menu.find_child("SaveControls", true, false) as PanelContainer
		var share := menu.find_child("PauseShare", true, false) as PanelContainer
		_expect(frame != null and share != null and (frame.get_theme_stylebox("panel") as StyleBoxFlat).bg_color == (share.get_theme_stylebox("panel") as StyleBoxFlat).bg_color,
			"%s: the saves frame does not match the statistics frame" % key)
		menu.scroll_saves_to_end()
		for _i in 2:
			await host.get_tree().process_frame
		var slots := menu._save_list.get_children().filter(func(n: Node) -> bool: return n is Control and (n as Control).visible)
		var last_slot := slots[-1] as Control if not slots.is_empty() else null
		var saves_view := saves_scroll.get_global_rect().grow(1.0)
		_expect(slots.size() >= 9 and last_slot != null and saves_view.encloses(last_slot.get_global_rect()),
			"%s: the last save slot cannot be scrolled into view (%d slots)" % [key, slots.size()])
		_expect(Rect2(Vector2.ZERO, units).grow(1.0).encloses(saves_scroll.get_global_rect()), "%s: the saves scroller leaves the window" % key)
		menu.close()
		holder.queue_free()
		await host.get_tree().process_frame
	if _failures == 0:
		print("  pausemenu only the open tab is lit; statistics and saves (matching style) scroll to their last row at 480x270, 1024x768, phone, XR panel")
	return _failures
