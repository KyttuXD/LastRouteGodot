class_name TestServerBadge
extends Label

## "TEST SERVER" tag shown in the menu and HUD while a debug run is pointed at the test
## instance (Backend.test_server_active), so nobody mistakes it for production.

static func attach(parent: Node) -> void:
	# only a debug build pointed at the test server is marked, and never with the server's address (ServerPrivacy)
	if not (Backend.test_server_active and OS.is_debug_build()) or parent.has_node("TestServerBadge"):
		return
	var text := "TEST SERVER"
	if parent is HUD:
		(parent as HUD).status_bar.set_segment("env", text, "env")
		return
	var badge := TestServerBadge.new()
	badge.name = "TestServerBadge"
	badge.text = text
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_font_size_override("font_size", 6)
	badge.add_theme_color_override("font_color", Palette.ON_AMBER)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.ACCENT
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	badge.add_theme_stylebox_override("normal", box)
	badge.set_anchors_preset(Control.PRESET_CENTER_TOP)
	badge.grow_horizontal = Control.GROW_DIRECTION_BOTH
	badge.offset_top = 4
	parent.add_child(badge)
