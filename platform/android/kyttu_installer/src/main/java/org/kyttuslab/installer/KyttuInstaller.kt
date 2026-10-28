package org.kyttuslab.installer

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.UsedByGodot
import java.io.File

/**
 * Hands a downloaded, checksum-verified update APK to Android's package installer (UpdateManager, docs/XR_ANDROID.md).
 * Nothing installs silently: the system installer always asks the user to confirm. The APK is shared through Godot's own
 * FileProvider (authority <package>.fileprovider, covering the app's internal files), because Android 7+ refuses
 * file:// URIs between apps.
 */
class KyttuInstaller(godot: Godot) : GodotPlugin(godot) {

    override fun getPluginName() = "KyttuInstaller"

    /** Whether this app may open the package installer (Android 8+ asks the user once, per app). */
    @UsedByGodot
    fun canRequestInstalls(): Boolean {
        val context = activity ?: return false
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.O || context.packageManager.canRequestPackageInstalls()
    }

    /** Opens the system page where the user allows installs from this app. Returns false if it could not open. */
    @UsedByGodot
    fun openInstallPermission(): Boolean {
        val context = activity ?: return false
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        return try {
            context.startActivity(
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + context.packageName))
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (error: Exception) {
            false
        }
    }

    /**
     * Opens the installer for the APK at [path] (an absolute path inside the app's files/updates folder).
     * Returns "ok", "missing" (no such file), "permission" (installs from this app are not allowed yet) or "error".
     */
    @UsedByGodot
    fun installApk(path: String): String {
        val context = activity ?: return "error"
        val file = File(path)
        if (!file.isFile) return "missing"
        if (!canRequestInstalls()) return "permission"
        return try {
            val uri = FileProvider.getUriForFile(context, context.packageName + ".fileprovider", file)
            context.startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            "ok"
        } catch (error: Exception) {
            "error"
        }
    }
}
