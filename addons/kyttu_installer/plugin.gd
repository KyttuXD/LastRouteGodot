@tool
extends EditorPlugin

## Registers the Android export hook for the APK installer plugin (docs/XR_ANDROID.md, "Self-update").

var _export: EditorExportPlugin


func _enter_tree() -> void:
	_export = preload("res://addons/kyttu_installer/export_plugin.gd").new()
	add_export_plugin(_export)


func _exit_tree() -> void:
	remove_export_plugin(_export)
	_export = null
