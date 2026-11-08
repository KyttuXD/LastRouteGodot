class_name UiHudBar
extends ProgressBar

## A HUD meter (battery, stamina, exposure, noise): flat inset track and a fill
## that moves crimson -> amber -> stable-green with the ratio, or the reverse
## for "bad when high" meters such as noise and exposure.

@export var high_is_bad := false


func _init() -> void:
	min_value = 0.0
	max_value = 1.0
	step = 0.0
	show_percentage = false
	custom_minimum_size = Vector2(60, 5)


func set_ratio(ratio: float) -> void:
	value = clampf(ratio, 0.0, 1.0)
	var badness := value if high_is_bad else 1.0 - value
	theme_type_variation = &"HudBarLow" if badness > .66 \
		else (&"HudBarWarn" if badness > .33 else &"HudBarSafe")
