class_name TrollAdOverlay
extends CanvasLayer

## The troll-mode pop-up "ad" (TrollAds, docs/ANTI_CHEAT.md): a blocky panel over the view with an unskippable
## countdown, then a SKIP AD button that hops away the first couple of times it is hovered or pressed. It hides at once
## (dismiss) when the player is caught or a death screen opens.

signal closed

const SKIP_DODGES := 2

var ad := {}
var remaining := 0.0
var _panel: PanelContainer
var _title: Label
var _body: Label
var _footer: Label
var _count: Label
var _skip: Button
var _hop: Control
var _dodges := 0


func _ready() -> void:
	layer = 40
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_panel = PanelContainer.new()
	_panel.name = "AdPanel"
	_panel.add_theme_stylebox_override("panel", Palette.panel_box(Color(0.06, 0.04, 0.09, 0.96), Color(1.0, 0.55, 0.8)))
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(440, 250)
	_panel.position = Vector2(-220, -125)
	root.add_child(_panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	_panel.add_child(column)
	var tag := Label.new()
	Palette.style_label(tag, Color(1.0, 0.85, 0.3), 12)
	tag.text = Palette.track("ADVERTISEMENT")
	column.add_child(tag)
	_title = Label.new()
	Palette.style_label(_title, Color(1.0, 0.55, 0.8), 26)
	column.add_child(_title)
	_body = Label.new()
	Palette.style_label(_body, Color(0.92, 0.95, 0.95), 16)
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_body)
	_footer = Label.new()
	Palette.style_label(_footer, Color(0.55, 0.95, 0.95), 11)
	column.add_child(_footer)
	var row := HBoxContainer.new()
	column.add_child(row)
	_count = Label.new()
	Palette.style_label(_count, Color(1.0, 0.85, 0.3), 14)
	row.add_child(_count)
	_hop = Control.new()   # the gap SKIP AD hops across
	_hop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_hop)
	_skip = Button.new()
	_skip.name = "SkipAd"
	_skip.text = "SKIP AD >"
	Palette.style_button(_skip, true, true)
	_skip.pressed.connect(_on_skip)
	_skip.mouse_entered.connect(_dodge)
	row.add_child(_skip)
	visible = false


func show_ad(value: Dictionary) -> void:
	ad = value
	remaining = TrollAds.COUNTDOWN_SECONDS
	_dodges = 0
	_title.text = String(ad.get("title", ""))
	_body.text = String(ad.get("body", ""))
	_footer.text = String(ad.get("footer", ""))
	_hop.custom_minimum_size.x = 0.0
	_hop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	visible = true
	_refresh()


func showing() -> bool:
	return visible


## Hides without the skip game (caught / death screen).
func dismiss() -> void:
	if visible:
		visible = false
		closed.emit()


func _process(delta: float) -> void:
	if not visible:
		return
	remaining = maxf(0.0, remaining - delta)
	_refresh()


func _refresh() -> void:
	_count.text = "AD ENDS IN %d" % ceili(remaining) if remaining > 0.0 else "YOU MAY NOW SKIP"
	_skip.disabled = remaining > 0.0


## The fake SKIP AD runs away a couple of times before it lets you click it.
func _dodge() -> void:
	if remaining > 0.0 or _dodges >= SKIP_DODGES:
		return
	_dodges += 1
	# Jump to the other end of the row: swap the gap from before the button to after it.
	var row := _skip.get_parent()
	row.move_child(_skip, 1 if _skip.get_index() > 1 else row.get_child_count() - 1)


func _on_skip() -> void:
	if remaining > 0.0:
		return
	if _dodges < SKIP_DODGES:
		_dodge()
		return
	dismiss()
