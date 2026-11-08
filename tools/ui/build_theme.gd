extends SceneTree

## Regenerates res://game/ui_common/ref_theme.tres from UiTheme.build().
##   godot --headless --path . --script tools/ui/build_theme.gd

func _initialize() -> void:
	var theme := UiTheme.build()
	var err := ResourceSaver.save(theme, UiTheme.THEME_PATH)
	print("ref_theme.tres saved: ", err)
	quit()
