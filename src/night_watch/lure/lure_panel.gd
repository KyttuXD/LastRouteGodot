class_name LurePanel
extends Control

## Dead Air's side of the monitor: the camera map (eight rooms from LureData, vents dashed), the LURE button, and one row per system with its
## state and a REBOOT button. Built into NightWatchHud's monitor (its own Classic camera map is removed); the HUD file itself is untouched.
## Coordinates are in the 480 x 270 canvas the HUD uses.

signal room_selected(room: String)
signal lure_pressed
signal reboot_pressed(system: String)

const MAP_AT := {
	"lobby": Vector2(50, 9), "arcade": Vector2(16, 27), "party": Vector2(84, 27), "ballpit": Vector2(50, 45),
	"prize": Vector2(84, 45), "storage": Vector2(50, 63), "ventl": Vector2(12, 63), "ventr": Vector2(88, 63),
}
const AMBER := Color(0.96, 0.72, 0.28)

var room_buttons := {}
var lure_button: Button
var rows := {}          # system -> {"row": Control, "state": Label, "button": Button}
var temp_label: Label
var out_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	name = "LurePanel"
	var map := Control.new()
	map.name = "LureMap"
	map.custom_minimum_size = Vector2(120, 80)
	map.position = Vector2(332, 160)
	add_child(map)
	var frame := ColorRect.new()
	frame.color = Color(0.04, 0.08, 0.06, 0.8)
	frame.size = Vector2(120, 80)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(frame)
	for room in LureData.ROOMS:
		var b := Button.new()
		b.name = "Cam_%s" % room
		b.text = "%d %s" % [LureData.ROOMS.find(room) + 1, String(LureData.INFO[room]["label"]).split(" ")[0]]
		b.focus_mode = Control.FOCUS_NONE
		b.size = Vector2(34, 12)
		b.add_theme_font_size_override("font_size", 5)
		var p: Vector2 = MAP_AT[room]
		b.position = Vector2(p.x / 100.0 * 120.0 - 17.0, p.y / 100.0 * 76.0 - 2.0)
		b.pressed.connect(func(): room_selected.emit(room))
		map.add_child(b)
		room_buttons[room] = b
	var you := Label.new()
	you.text = "VENTS LEAD TO YOU"
	you.add_theme_font_size_override("font_size", 5)
	you.add_theme_color_override("font_color", AMBER)
	you.position = Vector2(28, 68)
	you.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map.add_child(you)
	var col := VBoxContainer.new()
	col.name = "Systems"
	col.position = Vector2(332, 34)
	col.custom_minimum_size = Vector2(120, 0)
	col.add_theme_constant_override("separation", 2)
	add_child(col)
	lure_button = Button.new()
	lure_button.name = "LureButton"
	lure_button.text = "LURE HERE  L"
	lure_button.focus_mode = Control.FOCUS_NONE
	lure_button.add_theme_font_size_override("font_size", 7)
	lure_button.pressed.connect(func(): lure_pressed.emit())
	col.add_child(lure_button)
	for system in LureData.SYSTEMS:
		var info: Dictionary = LureData.SYSTEMS[system]
		var row := HBoxContainer.new()
		row.name = "Row_%s" % system
		row.add_theme_constant_override("separation", 3)
		var label := Label.new()
		label.text = String(info["label"])
		label.custom_minimum_size = Vector2(36, 0)
		label.add_theme_font_size_override("font_size", 6)
		row.add_child(label)
		var state := Label.new()
		state.custom_minimum_size = Vector2(42, 0)
		state.add_theme_font_size_override("font_size", 6)
		row.add_child(state)
		var b2 := Button.new()
		b2.text = "REBOOT %s" % info["key"]
		b2.focus_mode = Control.FOCUS_NONE
		b2.add_theme_font_size_override("font_size", 5)
		b2.pressed.connect(func(): reboot_pressed.emit(system))
		row.add_child(b2)
		col.add_child(row)
		rows[system] = {"row": row, "state": state, "button": b2}
	temp_label = Label.new()
	temp_label.name = "TempLabel"
	temp_label.add_theme_font_size_override("font_size", 6)
	col.add_child(temp_label)
	out_label = Label.new()
	out_label.name = "SystemError"
	out_label.text = "SYSTEM ERROR"
	out_label.add_theme_font_size_override("font_size", 14)
	out_label.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
	out_label.set_anchors_preset(Control.PRESET_CENTER)
	out_label.position = Vector2(-60, -10)
	out_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	out_label.visible = false
	add_child(out_label)


func refresh(sim: LureLogic, room: String) -> void:
	for r in room_buttons:
		(room_buttons[r] as Button).modulate = Color(1.0, 0.85, 0.4) if r == room else Color(1, 1, 1)
	var can_lure := sim.online("audio") and sim.lure_cool <= 0.0 and not room.begins_with("vent")
	lure_button.disabled = not can_lure
	lure_button.text = "LURE READY IN %ds" % int(ceil(sim.lure_cool / 1000.0)) if sim.lure_cool > 0.0 else "LURE HERE  L"
	for system in rows:
		var entry: Dictionary = rows[system]
		var shown := true
		if bool(LureData.SYSTEMS[system]["climate"]):
			shown = sim.has_fan if system == "fan" else sim.has_climate
		(entry["row"] as Control).visible = shown
		var st: Dictionary = sim.systems[system]
		var state_text := "ONLINE"
		var color := Color(0.6, 1.0, 0.7)
		if st["state"] == "broken":
			state_text = "BROKEN"
			color = Color(1.0, 0.4, 0.35)
		elif st["state"] == "reboot":
			state_text = "REBOOT %ds" % maxi(0, int(ceil((float(LureLogic.T["rebootMs"]) - float(st["t"])) / 1000.0)))
			color = Color(1.0, 0.85, 0.4)
		(entry["state"] as Label).text = state_text
		(entry["state"] as Label).add_theme_color_override("font_color", color)
		(entry["button"] as Button).disabled = st["state"] != "broken"
	temp_label.visible = sim.has_climate
	temp_label.text = "TEMP %d F   COLD %d%%  HEAT %d%%" % [int(round(sim.temp)), int(sim.cold), int(sim.heat)]
	out_label.visible = not sim.online("cams")
