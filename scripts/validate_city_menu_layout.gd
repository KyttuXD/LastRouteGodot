extends RefCounted

## The City menu fits KT's windows: at 1280x720, 1445x860, 1920x1080, 2560x1440, ultrawide and a tall 4:3 window the whole menu
## (title to footer) is on screen without scrolling, no control leaves the viewport or overlaps another, NEW RUN is the
## primary button, the sections exist and Esc goes back to the games. Phone landscape may scroll but never clips sideways.
##
##   godot --headless --path . res://scenes/validate.tscn -- city_menu_layout

const FITS := {"1280x720": Vector2i(1280, 720), "1445x860": Vector2i(1445, 860), "1920x1080": Vector2i(1920, 1080),
	"2560x1440": Vector2i(2560, 1440), "ultrawide3440x1440": Vector2i(3440, 1440), "1024x768": Vector2i(1024, 768)}
const SCROLLS := {"phone844x390": Vector2i(844, 390)}

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


func _check(host: Node, key: String, pixels: Vector2i, must_fit: bool) -> void:
	var holder := SubViewport.new()
	holder.size = pixels
	var units: Vector2 = load("res://scripts/validate_admin_layout.gd").units_for(pixels)
	holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
	holder.size_2d_override_stretch = true
	host.add_child(holder)
	var menu := (load("res://scenes/city_menu.tscn") as PackedScene).instantiate() as Control
	holder.add_child(menu)
	for _i in 6:
		await host.get_tree().process_frame
	var view := Rect2(Vector2.ZERO, Vector2(holder.size_2d_override))
	var column := menu.find_child("CityColumn", true, false) as Control
	_expect(column != null, "%s: no CityColumn" % key)
	if column != null and must_fit:
		_expect(column.size.y <= view.size.y - 16.0 + 0.5, "%s: the menu is %.0f units tall in a %.0f-unit window (scrolls)" % [key, column.size.y, view.size.y])
	var rects := {}
	for node in menu.find_children("*", "Control", true, false):
		var control := node as Control
		if not control.is_visible_in_tree() or not (control is Button or control is LineEdit or control.name == "CityTitle"):
			continue
		var rect := control.get_global_rect()
		_expect(rect.position.x >= -0.5 and rect.end.x <= view.end.x + 0.5, "%s: %s leaves the window sideways %s" % [key, control.name, rect])
		if must_fit:
			_expect(view.grow(0.5).encloses(rect), "%s: %s is outside the window %s" % [key, control.name, rect])
		rects[control.name] = rect
	var names := rects.keys()
	for i in names.size():
		for j in range(i + 1, names.size()):
			if (rects[names[i]] as Rect2).grow(-0.01).intersects((rects[names[j]] as Rect2).grow(-0.01)):
				_expect(false, "%s: %s overlaps %s" % [key, names[i], names[j]])
	for required in ["NewRunButton", "HostButton", "RoomCodeInput", "JoinButton", "TimeButton", "RainButton", "AccountButton",
			"SettingsButton", "BackToGamesButton", "CityTitle"]:
		_expect(rects.has(required), "%s: %s is not shown" % [key, required])
	var new_run := menu.find_child("NewRunButton", true, false) as Button
	if new_run != null and not new_run.disabled and menu.find_child("ContinueRunButton", true, false) != null \
			and not (menu.find_child("ContinueRunButton", true, false) as Control).visible:
		_expect(new_run.theme_type_variation == &"PrimaryButton", "%s: NEW RUN is not the primary button" % key)
	_expect(menu.find_child("CityMultiplayerRow", true, false) != null and menu.find_child("CityOptionsRow", true, false) != null
		and menu.find_child("CityFooterRow", true, false) != null, "%s: the menu sections are missing" % key)
	holder.queue_free()
	await host.get_tree().process_frame


func run(host: Node) -> int:
	for key in FITS:
		await _check(host, key, FITS[key], true)
	for key in SCROLLS:
		await _check(host, key, SCROLLS[key], false)
	if _failures == 0:
		print("  citymenu  City menu fits %d window sizes without clipping or overlap; sections, primary NEW RUN; phone scrolls" % FITS.size())
	return _failures
