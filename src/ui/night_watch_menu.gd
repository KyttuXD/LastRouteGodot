class_name NightWatchMenu
extends Control

## Night Watch's menu: pick a night (a cleared night opens the next), start it, or go BACK TO GAMES. Opened from the hub card.

const SHIFT_SCENE := "res://scenes/night_watch.tscn"

var night_buttons := {}
var back_button: Button
var status_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme_path := String(GameRegistry.get_game("night_watch").get("theme", ""))
	if not theme_path.is_empty() and ResourceLoader.exists(theme_path) and load(theme_path) is Theme:
		theme = load(theme_path)
	var back := ColorRect.new()
	back.color = Color(0.03, 0.03, 0.05)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size = Vector2(220, 0)
	center.add_child(box)
	var kicker := Label.new()
	kicker.text = "CAMERA FEED // OVERNIGHT SHIFT"
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kicker.add_theme_color_override("font_color", Color(0.96, 0.72, 0.28))
	box.add_child(kicker)
	var title := Label.new()
	title.name = "Title"
	title.text = "NIGHT WATCH"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	status_label = Label.new()
	status_label.name = "StatusLabel"
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(0.7, 0.68, 0.62))
	box.add_child(status_label)
	var unlocked := NightWatchSave.unlocked_night()
	var cleared := NightWatchSave.cleared()
	for n in range(1, NightWatchData.NIGHTS + 1):
		var b := Button.new()
		b.name = "Night%d" % n
		var tag := "  (cleared)" if cleared.has(n) else ""
		var hunters: Array = NightWatchData.active_hunters(n)
		b.text = "NIGHT %d%s" % [n, tag]
		b.tooltip_text = ", ".join(PackedStringArray(hunters.map(func(h): return String(NightWatchData.NAMES.get(h, h)))))
		b.disabled = n > unlocked
		b.pressed.connect(start_night.bind(n))
		box.add_child(b)
		night_buttons[n] = b
	back_button = Button.new()
	back_button.name = "BackButton"
	back_button.text = "BACK TO GAMES"
	back_button.pressed.connect(func(): get_tree().change_scene_to_file(GameRegistry.HUB_SCENE))
	box.add_child(back_button)
	status_label.text = "Nights cleared: %d of %d   //   A / D doors   Q / E lights   SPACE monitor" % [cleared.size(), NightWatchData.NIGHTS]
	var first := night_buttons.get(mini(unlocked, NightWatchData.NIGHTS)) as Button
	if first != null:
		first.grab_focus()


func start_night(night: int) -> void:
	if night > NightWatchSave.unlocked_night():
		return
	NightWatchSession.start(night)
	get_tree().change_scene_to_file(SHIFT_SCENE)
