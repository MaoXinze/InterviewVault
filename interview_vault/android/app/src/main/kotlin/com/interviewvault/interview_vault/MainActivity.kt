package com.interviewvault.interview_vault

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.provider.MediaStore
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 音频导入的本机媒体查询通道（"device_audio"）：
 * - permissionStatus / requestPermission：音频媒体读权限
 *   （Android 13+ 为 READ_MEDIA_AUDIO，旧版 READ_EXTERNAL_STORAGE）
 * - listAudios：MediaStore 全量音频，按加入时间倒序（导入页点选导入，
 *   免去系统文件管理器翻目录）。仅本机读取，不上传。
 */
class MainActivity : FlutterActivity() {
    private val channelName = "device_audio"
    private val requestCode = 7001

    private var pendingPermissionResult: MethodChannel.Result? = null

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
                    else -> result.notImplemented()
                }
            }
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
        val projection = arrayOf(
            MediaStore.Audio.Media._ID,
            MediaStore.Audio.Media.DATA,
            MediaStore.Audio.Media.DISPLAY_NAME,
            MediaStore.Audio.Media.ALBUM,
            MediaStore.Audio.Media.DURATION,
            MediaStore.Audio.Media.SIZE,
            MediaStore.Audio.Media.DATE_ADDED,
        )
        val out = mutableListOf<Map<String, Any?>>()
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
            while (cursor.moveToNext()) {
                val path = cursor.getString(dataCol) ?: continue
                out.add(
                    mapOf(
                        "path" to path,
                        "title" to (cursor.getString(nameCol) ?: path),
                        "album" to cursor.getString(albumCol),
                        "durationMs" to cursor.getLong(durationCol),
                        "sizeBytes" to cursor.getLong(sizeCol),
                        // DATE_ADDED 单位为秒
                        "addedAtSec" to cursor.getLong(addedCol),
                    ),
                )
            }
        }
        return out
    }
}
