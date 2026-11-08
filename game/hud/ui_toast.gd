class_name UiToast
extends Label

## One amber, letter-spaced status line that fades out ("toast" in the web
## builds). Call pop(); it ignores the mouse and never takes focus.

var _tween: Tween


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_color_override("font_color", Palette.AMBER)
	add_theme_color_override("font_outline_color", Color(0, 0, 0, .8))
	add_theme_constant_override("outline_size", 2)
	modulate.a = 0.0


func pop(message: String, seconds: float = 2.6, tint: Color = Palette.AMBER) -> void:
	text = message
	add_theme_color_override("font_color", tint)
	if _tween != null and _tween.is_valid():
		_tween.kill()
	modulate.a = 1.0
	_tween = create_tween()
	_tween.tween_interval(maxf(.1, seconds - .5))
	_tween.tween_property(self, "modulate:a", 0.0, .5)
