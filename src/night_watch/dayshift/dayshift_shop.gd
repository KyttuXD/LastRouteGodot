class_name DayshiftShop
extends CanvasLayer

## Salvage Run's day: the shop. A panel with the week's budget, tonight's quota and the five upgrades as toggle buttons (the 2D shop's wording and rules:
## DayshiftLogic.shop_toggle decides both the greyed-out buttons and the click, so the two can't disagree), and START SHIFT. Emits `started(owned)`.

signal started(owned: Array)

var week := 1
var carry := 0
var custom := false
var owned: Array = []
var budget_label: Label
var quota_label: Label
var buttons := {}
var start_button: Button


func setup(week_number: int, carry_amount: int, is_custom: bool) -> void:
	week = week_number
	carry = carry_amount
	custom = is_custom


func _ready() -> void:
	layer = 18
	var root := Control.new()
	root.name = "ShopRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var theme_path := "res://src/ui/theme_nightwatch.tres"
	if ResourceLoader.exists(theme_path) and load(theme_path) is Theme:
		root.theme = load(theme_path)
	add_child(root)
	var back := ColorRect.new()
	back.color = Color(0.02, 0.02, 0.04, 0.9)
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(back)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	var kicker := Label.new()
	kicker.name = "ShopKicker"
	kicker.text = "DAY · %s" % ("CUSTOM" if custom else "WEEK %d" % week)
	kicker.add_theme_font_size_override("font_size", 9)
	kicker.add_theme_color_override("font_color", NightWatchHud.AMBER)
	box.add_child(kicker)
	var title := Label.new()
	title.text = "THE SHOP"
	title.add_theme_font_size_override("font_size", 20)
	box.add_child(title)
	budget_label = Label.new()
	budget_label.name = "BudgetLabel"
	budget_label.add_theme_font_size_override("font_size", 10)
	box.add_child(budget_label)
	quota_label = Label.new()
	quota_label.name = "QuotaLabel"
	quota_label.add_theme_font_size_override("font_size", 10)
	box.add_child(quota_label)
	for u in DayshiftData.UPGRADES:
		var b := Button.new()
		b.name = "Upgrade_%s" % u["id"]
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(330, 20)
		b.add_theme_font_size_override("font_size", 8)
		var id := String(u["id"])
		b.pressed.connect(func(): toggle(id))
		box.add_child(b)
		buttons[id] = b
	start_button = Button.new()
	start_button.name = "StartShift"
	start_button.text = "▶ START SHIFT"
	start_button.focus_mode = Control.FOCUS_NONE
	start_button.custom_minimum_size = Vector2(330, 24)
	start_button.pressed.connect(func(): started.emit(owned.duplicate()))
	box.add_child(start_button)
	refresh()


func quota() -> int:
	return DayshiftLogic.quota_for(4 if custom else week)


func budget() -> int:
	return DayshiftLogic.budget_for(4 if custom else week, carry)


func toggle(id: String) -> bool:
	var next = DayshiftLogic.shop_toggle(owned, id, 4 if custom else week, carry)
	if next == null:
		return false
	owned = next
	refresh()
	return true


func refresh() -> void:
	var left := budget() - DayshiftLogic.total_cost(owned)
	var carried := budget() - DayshiftLogic.budget_for(4 if custom else week, 0)
	budget_label.text = "Budget $%d of $%d%s" % [left, budget(), " (incl. $%d carried over)" % carried if carried > 0 else ""]
	quota_label.text = "Tonight's quota $%d" % quota()
	for u in DayshiftData.UPGRADES:
		var id := String(u["id"])
		var b := buttons[id] as Button
		var has := owned.has(id)
		var off := not has and DayshiftLogic.shop_toggle(owned, id, 4 if custom else week, carry) == null
		b.text = "%s %s  $%d  %s" % ["✔" if has else " ", String(u["name"]).to_upper(), int(u["cost"]), String(u["blurb"])]
		b.disabled = off
