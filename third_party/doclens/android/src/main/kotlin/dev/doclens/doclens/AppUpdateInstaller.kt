package dev.doclens.doclens

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/** Own subclass so this provider never clashes with other plugins' ones. */
class DoclensUpdateFileProvider : FileProvider()

/**
 * In-app update helpers: report the installed version and hand a
 * downloaded APK to Android's package installer. Android itself shows the
 * final "Update this app?" confirmation and refuses an APK signed with a
 * different key, so nothing is installed silently.
 */
internal object AppUpdateInstaller {
    fun version(context: Context): Map<String, Any> {
        val info = if (Build.VERSION.SDK_INT >= 33) {
            context.packageManager.getPackageInfo(context.packageName,
                android.content.pm.PackageManager.PackageInfoFlags.of(0))
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, 0)
        }
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode
            else @Suppress("DEPRECATION") info.versionCode.toLong()
        return mapOf("versionName" to (info.versionName ?: ""),
            "buildNumber" to code.toString())
    }

    /** True when this app may open the package installer. */
    fun canInstall(context: Context): Boolean =
        Build.VERSION.SDK_INT < 26 || context.packageManager.canRequestPackageInstalls()

    /** Opens "Install unknown apps" for this app. */
    fun openInstallPermission(activity: Activity?, context: Context) {
        val intent = if (Build.VERSION.SDK_INT >= 26) {
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${context.packageName}"))
        } else {
            Intent(Settings.ACTION_SECURITY_SETTINGS)
        }
        start(activity, context, intent)
    }

    /** Returns false if the file is missing or outside the update folder. */
    fun install(activity: Activity?, context: Context, path: String): Boolean {
        val file = File(path).canonicalFile
        val folder = File(context.cacheDir, "updates").canonicalFile
        if (!file.isFile || file.parentFile != folder) return false
        val uri = FileProvider.getUriForFile(context,
            "${context.packageName}.doclens.updates", file)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        start(activity, context, intent)
        return true
    }

    private fun start(activity: Activity?, context: Context, intent: Intent) {
        if (activity != null) {
            activity.startActivity(intent)
        } else {
            context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }
}
