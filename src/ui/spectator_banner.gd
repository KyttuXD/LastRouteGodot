class_name SpectatorBanner
extends Label

## "SPECTATING" strip shown while a dead/caught runner watches the rest of the party.
## Same flat panel look as the other HUD tags; hidden until show_for() is called.

func _init() -> void:
	name = "SpectatorBanner"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_font_size_override("font_size", 8)
	add_theme_color_override("font_color", Palette.INK)
	var box := StyleBoxFlat.new()
	box.bg_color = Palette.SCRIM
	box.border_color = Palette.ACCENT_EDGE
	box.set_border_width_all(1)
	box.content_margin_left = 10
	box.content_margin_right = 10
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	add_theme_stylebox_override("normal", box)
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_bottom = -18
	visible = false


static func attach(parent: Node) -> SpectatorBanner:
	var existing := parent.get_node_or_null("SpectatorBanner") as SpectatorBanner
	if existing != null:
		return existing
	var banner := SpectatorBanner.new()
	parent.add_child(banner)
	return banner


## watching: display name of the followed runner, or "" for the free camera.
func show_for(watching: String, note: String = "") -> void:
	var line := "SPECTATING  //  %s" % (watching.to_upper() if not watching.is_empty() else "FREE CAMERA")
	line += "\n[E] NEXT   [Q] PREVIOUS   [F] FREE CAMERA"
	if not note.is_empty():
		line += "\n" + note
	text = line
	visible = true


func clear() -> void:
	visible = false
