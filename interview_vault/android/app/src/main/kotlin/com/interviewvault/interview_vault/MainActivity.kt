package com.interviewvault.interview_vault

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.IntentCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 音频导入的本机媒体查询通道（"device_audio"）：
 * - permissionStatus / requestPermission：音频媒体读权限
 *   （Android 13+ 为 READ_MEDIA_AUDIO，旧版 READ_EXTERNAL_STORAGE）
 * - listAudios：MediaStore 全量音频，按加入时间倒序（导入页点选导入，
 *   免去系统文件管理器翻目录）。仅本机读取，不上传。
 * - takeSharedAudio：取走系统分享送来的音频（录音机私有目录导入入口）。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "device_audio"
    private val requestCode = 7001

    private var pendingPermissionResult: MethodChannel.Result? = null

    private var pendingSharedAudio: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "permissionStatus" -> result.success(hasAudioPermission())
                    "requestPermission" -> requestAudioPermission(result)
                    "listAudios" -> {
                        if (!hasAudioPermission()) {
                            result.error("PERMISSION_DENIED", "未授予音频媒体读权限", null)
                        } else {
                            result.success(listAudios())
                        }
                    }
                    "takeSharedAudio" -> result.success(
                        pendingSharedAudio.also { pendingSharedAudio = null },
                    )
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        captureSharedAudio(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureSharedAudio(intent)
    }

    /** 铃声包目录段（MIUI 会把铃声包登记成普通音乐，按路径排除） */
    private val soundPackSegments =
        setOf("ringtone", "ringtones", "notifications", "alarms")

    private fun isSoundPackPath(path: String): Boolean =
        path.lowercase().split('/', '\\').any { it in soundPackSegments }

    /** 与 listAudios / 导入白名单一致的可导入格式 */
    private val supportedExtensions =
        setOf("mp3", "wav", "m4a", "aac", "ogg")

    /**
     * 录音机等应用"分享"来的音频（Manifest 注册 ACTION_SEND 接收任意音频 MIME）。
     * MIUI/HyperOS 录音机把录音存在应用私有目录（Android/data/…/files/），
     * Android 11+ 第三方完全读不到且 MediaStore 不收录——系统分享是拿到
     * 这类文件的唯一入口。拷贝进缓存目录，Dart 侧 takeSharedAudio 领走
     * 后走导入确认管线；拷贝失败静默忽略（导入页仍有文件管理器兜底）。
     */
    private fun captureSharedAudio(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val uri = IntentCompat.getParcelableExtra(
            intent, Intent.EXTRA_STREAM, Uri::class.java,
        ) ?: return
        val mime = intent.type ?: ""
        var displayName = "shared_audio"
        contentResolver.query(
            uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                cursor.getString(0)?.takeIf { it.isNotBlank() }?.let {
                    displayName = it
                }
            }
        }
        displayName = java.io.File(displayName).name
        val ext = displayName.substringAfterLast('.', "").lowercase()
        if (!mime.startsWith("audio/") && ext !in supportedExtensions) return
        val dir = java.io.File(cacheDir, "shared_audio").apply { mkdirs() }
        val target = java.io.File(dir, displayName)
        try {
            contentResolver.openInputStream(uri)?.use { input ->
                target.outputStream().use { output -> input.copyTo(output) }
            } ?: return
        } catch (e: Exception) {
            target.delete()
            return
        }
        pendingSharedAudio = mapOf(
            "path" to target.absolutePath,
            "title" to displayName,
            "sizeBytes" to target.length(),
        )
    }

    private fun hasAudioPermission(): Boolean {
        val permission = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        return ContextCompat.checkSelfPermission(this, permission) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestAudioPermission(result: MethodChannel.Result) {
        if (hasAudioPermission()) {
            result.success(true)
            return
        }
        // 系统弹窗异步回调：挂起 result，等 onRequestPermissionsResult 回填
        pendingPermissionResult = result
        val permission = if (Build.VERSION.SDK_INT >= 33) {
            Manifest.permission.READ_MEDIA_AUDIO
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        ActivityCompat.requestPermissions(this, arrayOf(permission), requestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != requestCode) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    private fun listAudios(): List<Map<String, Any?>> {
        val supported = setOf("mp3", "wav", "m4a", "aac", "ogg")
        val out = LinkedHashMap<String, Map<String, Any?>>()

        // 1) MediaStore：排除铃声/通知/闹钟（MIUI 会登记几十个 ringtone，
        //    把真实录音淹没），只留可导入格式
        val projection = arrayOf(
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
            MediaStore.Audio.Media.IS_RINGTONE,
            MediaStore.Audio.Media.IS_NOTIFICATION,
            MediaStore.Audio.Media.IS_ALARM,
        )
        contentResolver.query(
            MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
            projection,
            null,
            null,
            "${MediaStore.Audio.Media.DATE_ADDED} DESC",
        )?.use { cursor ->
            val dataCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATA)
            val nameCol =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
            val albumCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.ALBUM)
            val durationCol =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
            val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
            val addedCol =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
            val ringCol =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.IS_RINGTONE)
            val notifCol =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.IS_NOTIFICATION)
            val alarmCol =
                cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.IS_ALARM)
            while (cursor.moveToNext()) {
                val path = cursor.getString(dataCol) ?: continue
                val ext = path.substringAfterLast('.', "").lowercase()
                if (ext !in supported) continue
                val isSystemSound = cursor.getInt(ringCol) == 1 ||
                    cursor.getInt(notifCol) == 1 ||
                    cursor.getInt(alarmCol) == 1
                if (isSystemSound || isSoundPackPath(path)) continue
                out[path] = mapOf(
                    "path" to path,
                    "title" to (cursor.getString(nameCol) ?: path),
                    "album" to cursor.getString(albumCol),
                    "durationMs" to cursor.getLong(durationCol),
                    "sizeBytes" to cursor.getLong(sizeCol),
                    // DATE_ADDED 单位为秒
                    "addedAtSec" to cursor.getLong(addedCol),
                )
            }
        }

        // 2) 常见录音/下载目录兜底扫描：新拷贝的文件可能还没被媒体库索引
        val scanDirs = listOf(
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_RECORDINGS,
            ),
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_MUSIC,
            ),
            Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS,
            ),
            // MIUI 录音机目录带 .nomedia（媒体库永不索引），必须显式扫描；
            // 不同版本落在 app_rec（普通录音）/call_rec（通话）/fm_rec
            java.io.File("/sdcard/MIUI/sound_recorder/app_rec"),
            java.io.File("/sdcard/MIUI/sound_recorder/call_rec"),
            java.io.File("/sdcard/MIUI/sound_recorder/fm_rec"),
        )
        for (dir in scanDirs) {
            val files = dir.listFiles() ?: continue
            for (file in files) {
                if (!file.isFile) continue
                if (file.extension.lowercase() !in supported) continue
                if (isSoundPackPath(file.absolutePath)) continue
                if (out.containsKey(file.absolutePath)) continue
                out[file.absolutePath] = mapOf(
                    "path" to file.absolutePath,
                    "title" to file.name,
                    "album" to null,
                    "durationMs" to null,
                    "sizeBytes" to file.length(),
                    "addedAtSec" to file.lastModified() / 1000,
                )
            }
        }

        return out.values.sortedByDescending {
            (it["addedAtSec"] as? Number)?.toLong() ?: 0
        }
    }
}
