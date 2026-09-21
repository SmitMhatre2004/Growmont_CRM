package com.growmont.growmont_crm

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hosts the Android side of the in-app updater.
 *
 * Unlike Windows — where UpdateService can silently run the Inno Setup
 * installer and exit — Android has no way for a sideloaded app to install
 * an APK without user consent. The best achievable flow is:
 *
 *   1. Confirm this app is allowed to request installs at all
 *      (`canInstallPackages`). On Android 8+ this is a per-app setting the
 *      user must turn on once, and it is off by default.
 *   2. If not, send them to exactly that settings page
 *      (`openInstallSettings`) rather than leaving the update silently
 *      doing nothing.
 *   3. Hand the downloaded APK to the system package installer
 *      (`installApk`), which shows its own confirmation screen.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "com.growmont.growmont_crm/installer"
        const val APK_MIME = "application/vnd.android.package-archive"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "updateDownloadDir" -> result.success(updateDownloadDir().absolutePath)
                "canInstallPackages" -> result.success(canInstallPackages())
                "openInstallSettings" -> result.success(openInstallSettings())
                "installApk" -> installApk(call.argument<String>("path"), result)
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Where the Dart side saves a downloaded APK: `files/updates/`, the one
     * directory `res/xml/file_paths.xml` exposes to the package installer.
     *
     * Resolved here rather than in Dart so the two cannot drift apart —
     * a mismatch only surfaces as FileProvider refusing the file at install
     * time. Deliberately not the cache dir, which Android clears whenever
     * it wants the space back; see UpdateService._downloadDirectory.
     */
    private fun updateDownloadDir(): File =
        File(filesDir, "updates").apply { mkdirs() }

    /**
     * Whether the user has granted this app permission to install APKs.
     *
     * Below API 26 the REQUEST_INSTALL_PACKAGES manifest permission is
     * sufficient on its own, so there is nothing to check.
     */
    private fun canInstallPackages(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }

    /**
     * Opens the per-app "install unknown apps" screen. Returns false if the
     * screen could not be opened, so the Dart side can fall back to telling
     * the user where to find it manually rather than appearing to hang.
     */
    private fun openInstallSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return try {
            startActivity(
                Intent(
                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                    Uri.parse("package:$packageName"),
                ),
            )
            true
        } catch (e: Exception) {
            false
        }
    }

    private fun installApk(path: String?, result: MethodChannel.Result) {
        if (path.isNullOrBlank()) {
            result.error("INVALID_PATH", "No APK path supplied.", null)
            return
        }

        val apk = File(path)
        if (!apk.exists() || apk.length() == 0L) {
            result.error(
                "MISSING_APK",
                "Downloaded APK is missing or empty ($path).",
                null,
            )
            return
        }

        try {
            // A file:// URI would throw FileUriExposedException on API 24+,
            // so the APK is exposed through the app's FileProvider and the
            // read grant is attached to the intent itself — the installer
            // is a different process and has no access to our cache dir
            // otherwise.
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                apk,
            )

            startActivity(
                Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(uri, APK_MIME)
                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                },
            )
            result.success(true)
        } catch (e: Exception) {
            result.error("INSTALL_FAILED", e.message, null)
        }
    }
}
