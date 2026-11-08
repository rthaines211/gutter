package com.ryanhaines.gutter

import android.os.Build
import android.os.StatFs
import android.os.storage.StorageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// iOS's other channels are skipped here: `panels` (Core ML model, not ported
// yet: Dart hides panel zoom on Android), `push` and `open_url` (personal
// build only; Dart treats a missing channel as "off").
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.comic_reader/files")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "freeSpace" -> result.success(freeBytes())
                    // iOS sets isExcludedFromBackup per directory; Android
                    // excludes downloads statically (res/xml/backup_rules.xml,
                    // data_extraction_rules.xml). Nothing to do at runtime.
                    "excludeFromBackup" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    // Free bytes on the volume holding the app's files (downloads live under
    // app_flutter/, beside filesDir). Like iOS's "important usage" capacity,
    // Android 8+ counts cache the system would clear to make room.
    private fun freeBytes(): Long? = try {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val sm = getSystemService(StorageManager::class.java)
            sm.getAllocatableBytes(sm.getUuidForPath(filesDir))
        } else {
            StatFs(filesDir.path).availableBytes
        }
    } catch (e: Exception) {
        null
    }
}
