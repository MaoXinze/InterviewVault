package com.interviewvault.interview_vault

import android.content.ContentUris
import android.net.Uri
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream

/**
 * 手机录音机直导（W2-M2 补充）：
 * - list: 查询 MediaStore 里录音机目录（Recordings/、MIUI sound_recorder/）下的音频，
 *   返回 uri/文件名/时长/大小/时间，供 App 内直接选择（避免用户在系统文件
 *   管理器里翻目录——MIUI 录音目录带 .nomedia，文件选择器里很难找到）
 * - copy: 把选中录音复制进 App 库目录（优先文件路径，失败退回 content uri）
 */
class MainActivity : FlutterActivity() {
    private val channelName = "interviewvault/phone_recordings"

    /// 录音机常用目录：MIUI 旧目录带 .nomedia 不被 MediaStore 索引，
    /// 新设备保存到 /Recordings/（可被索引）。均按直接扫描兜底。
    private val recorderDirs = listOf(
        "/storage/emulated/0/MIUI/sound_recorder/app_rec",
        "/storage/emulated/0/MIUI/sound_recorder/call_rec",
        "/storage/emulated/0/MIUI/sound_recorder",
        "/storage/emulated/0/Recordings/call",
        "/storage/emulated/0/Recordings",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "list" -> result.success(listRecorderAudio())
                    "copy" -> {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        val path = call.argument<String>("sourcePath")
                        val target = call.argument<String>("target")
                        if (target == null) {
                            result.error("invalid_args", "target 不能为空", null)
                        } else {
                            runCatching { copyRecording(uri, path, File(target)) }
                                .onSuccess { result.success(null) }
                                .onFailure { result.error("copy_failed", it.message, null) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun listRecorderAudio(): List<Map<String, Any>> {
        val rows = mutableListOf<Map<String, Any>>()
        val seenPaths = mutableSetOf<String>()
        queryMediaStore(rows, seenPaths)
        scanRecorderDirs(rows, seenPaths)
        return rows
    }

    /// MediaStore 索引过的音频（需 READ_MEDIA_AUDIO / READ_EXTERNAL_STORAGE）
    private fun queryMediaStore(rows: MutableList<Map<String, Any>>, seen: MutableSet<String>) {
        runCatching {
            val resolver = contentResolver
            val media = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            val data = MediaStore.Audio.Media.DATA
            val selection = "$data LIKE ? OR $data LIKE ?"
            val args = arrayOf("%/Recordings/%", "%/MIUI/sound_recorder/%")
            resolver.query(
                media,
                arrayOf(
                    MediaStore.Audio.Media._ID,
                    MediaStore.Audio.Media.DISPLAY_NAME,
                    MediaStore.Audio.Media.DURATION,
                    MediaStore.Audio.Media.SIZE,
                    MediaStore.Audio.Media.DATE_ADDED,
                    data,
                ),
                selection,
                args,
                "${MediaStore.Audio.Media.DATE_ADDED} DESC",
            )?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DISPLAY_NAME)
                val durCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DURATION)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.SIZE)
                val dateCol = cursor.getColumnIndexOrThrow(MediaStore.Audio.Media.DATE_ADDED)
                val pathCol = cursor.getColumnIndexOrThrow(data)
                while (cursor.moveToNext()) {
                    val path = cursor.getString(pathCol) ?: continue
                    if (!seen.add(path)) continue
                    val uri = ContentUris.withAppendedId(media, cursor.getLong(idCol)).toString()
                    rows.add(
                        mapOf(
                            "sourceUri" to uri,
                            "sourcePath" to path,
                            "fileName" to (cursor.getString(nameCol) ?: "recording"),
                            "durationMs" to cursor.getLong(durCol),
                            "sizeBytes" to cursor.getLong(sizeCol),
                            "recordedAt" to cursor.getLong(dateCol) * 1000L,
                        ),
                    )
                }
            }
        }
    }

    /// 直接扫描录音机目录（.nomedia 目录里的文件不在 MediaStore；
    /// 无权限时 listFiles 返回 null，静默跳过）
    private fun scanRecorderDirs(rows: MutableList<Map<String, Any>>, seen: MutableSet<String>) {
        val audioExts = setOf("m4a", "mp3", "wav", "aac", "ogg", "3gp")
        for (dirPath in recorderDirs) {
            val dir = File(dirPath)
            val files = runCatching { dir.listFiles() }.getOrNull() ?: continue
            for (f in files) {
                if (!f.isFile) continue
                val path = f.absolutePath
                if (!seen.add(path)) continue
                val ext = f.extension.lowercase()
                if (ext !in audioExts) continue
                rows.add(
                    mapOf(
                        "sourceUri" to Uri.fromFile(f).toString(),
                        "sourcePath" to path,
                        "fileName" to f.name,
                        "durationMs" to 0L,
                        "sizeBytes" to f.length(),
                        "recordedAt" to f.lastModified(),
                    ),
                )
            }
        }
    }

    /// 复制进库：先试原始路径（.nomedia 目录里的文件拿不到 content uri），
    /// 失败退回 contentResolver 流
    private fun copyRecording(uri: Uri, sourcePath: String?, target: File) {
        if (sourcePath != null) {
            val src = File(sourcePath)
            if (src.exists() && src.canRead()) {
                FileInputStream(src).use { input ->
                    target.outputStream().use { output -> input.copyTo(output) }
                }
                return
            }
        }
        contentResolver.openInputStream(uri)?.use { input ->
            target.outputStream().use { output -> input.copyTo(output) }
        } ?: throw IllegalStateException("无法打开录音文件 $uri")
    }
}
