@tool
extends EditorExportPlugin

## Android Gradle exports link the installer AAR that tools/android/build_installer_plugin.sh builds into bin/ (never
## committed). Without it the export still works; the game then says to install updates manually instead.

const AAR := "kyttu_installer/bin/kyttu_installer.aar"


func _get_name() -> String:
	return "KyttuInstaller"


func _supports_platform(platform: EditorExportPlatform) -> bool:
	return platform is EditorExportPlatformAndroid


func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if FileAccess.file_exists("res://addons/%s" % AAR):
		return PackedStringArray([AAR])
	return PackedStringArray()


func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
	if FileAccess.file_exists("res://addons/%s" % AAR):
		return PackedStringArray(["androidx.core:core:1.8.0"])
	return PackedStringArray()
