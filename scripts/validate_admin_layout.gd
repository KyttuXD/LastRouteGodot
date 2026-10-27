extends RefCounted

## The admin panel is on screen, big enough and readable at every resolution KT uses: 1280x720, 1366x768 (small laptop),
## 1920x1080, 2560x1440, ultrawide 3440x1440, and phone/tablet shapes (portrait and landscape). Each size is a SubViewport
## with the same expand-stretch rule as the real window (480x270 minimum, extra room on the long side).
##
##   godot --headless --path . res://scenes/validate.tscn -- admin_layout

const SIZES := [Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(2560, 1440),
	Vector2i(3440, 1440), Vector2i(390, 844), Vector2i(844, 390), Vector2i(1024, 768)]

var _failures := 0


func _expect(condition: bool, message: String) -> void:
	if not condition:
		print("  FAIL  %s" % message)
		_failures += 1


## Canvas units the project's stretch ("canvas_items", aspect "expand", base 480x270) gives a window of this size.
static func units_for(pixels: Vector2i) -> Vector2:
	var aspect := float(pixels.x) / float(pixels.y)
	return Vector2(270.0 * aspect, 270.0) if aspect >= 480.0 / 270.0 else Vector2(480.0, 480.0 / aspect)


func run(host: Node) -> int:
	RoomState.create_local(RoomState.Mode.DEFAULT)
	var route: Node = (load("res://scenes/infinite_route_test.tscn") as PackedScene).instantiate()
	host.get_tree().root.add_child(route)
	for _i in 6:
		await host.get_tree().process_frame
	var actions: Array = route._infinite_admin_actions()
	var fields: Array = route._admin_roster_fields()
	var status := func() -> String: return "STATUS // TEST"
	for pixels in SIZES:
		var holder := SubViewport.new()
		holder.size = pixels
		var units := units_for(pixels)
		holder.size_2d_override = Vector2i(roundi(units.x), roundi(units.y))
		holder.size_2d_override_stretch = true
		host.add_child(holder)
		var menu := AdminMenu.attach(holder, status, actions, fields)
		if menu == null:
			_expect(false, "no admin menu in this build")
			holder.queue_free()
			continue
		await host.get_tree().process_frame
		menu._set_open(true)
		await host.get_tree().process_frame
		await host.get_tree().process_frame
		var view := holder.get_visible_rect()
		var zoom := menu._panel.scale.x
		var rect := Rect2(menu._panel.position, menu._panel.size * zoom)
		_expect(view.grow(1.0).encloses(rect), "%s: admin panel %s leaves the viewport %s" % [pixels, rect, view])
		var on_screen_w := rect.size.x * (float(pixels.x) / view.size.x)
		var on_screen_h := rect.size.y * (float(pixels.y) / view.size.y)
		_expect(on_screen_w >= minf(float(pixels.x) * 0.55, 560.0) and on_screen_h >= minf(float(pixels.y) * 0.5, 300.0),
			"%s: admin panel is only %dx%d px" % [pixels, on_screen_w, on_screen_h])
		var font_px := 8.0 * zoom * (float(pixels.x) / view.size.x)
		_expect(font_px >= 12.0, "%s: admin text is %.1f px (needs >= 12)" % [pixels, font_px])
		_expect(menu._panel.get_theme_stylebox("panel").bg_color.a >= 0.99, "the admin panel background must be opaque")
		menu._set_open(false)
		holder.queue_free()
		await host.get_tree().process_frame
	route.queue_free()
	await host.get_tree().process_frame
	if _failures == 0:
		print("  adminui   panel fits, is opaque and readable (>= 12 px text) at %d window sizes" % SIZES.size())
	return _failures
