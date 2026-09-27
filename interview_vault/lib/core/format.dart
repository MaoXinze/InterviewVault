/// 时长显示：超 1 小时 h:mm:ss，否则 mm:ss（录音计时与导入信息共用）。
String formatClock(Duration d) {
  String two(int v) => v.toString().padLeft(2, '0');
  if (d.inHours > 0) {
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

/// 文件大小人性化：B / KB / MB / GB，一位小数。
String formatFileSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} MB';
  return '${(mb / 1024).toStringAsFixed(1)} GB';
}
