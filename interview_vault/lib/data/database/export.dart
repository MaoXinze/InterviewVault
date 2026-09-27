import 'dart:convert';

import 'app_database.dart';

/// 全量导出 schema。
///
/// 稳定性承诺（AGENTS 工程纪律 4 / PRD 注意事项 5）：
/// - schema_version 递增才允许结构变化；
/// - data 下六个数组的键名为 drift 生成的 camelCase 字段名（与 SQL 列名的
///   snake_case 一一对应），发布后不得改名；
/// - 用户可能依赖该 JSON 做二次处理，任何调整都是破坏性变更。
const exportSchemaVersion = 1;

Future<Map<String, dynamic>> buildExportPayload(
  AppDatabase db, {
  DateTime Function()? now,
}) async {
  return {
    'schema_version': exportSchemaVersion,
    'exported_at': (now ?? DateTime.now)().toIso8601String(),
    'data': {
      'interviews': (await db.interviewsDao.getAll())
          .map((r) => r.toJson())
          .toList(),
      'transcript_segments': (await db.segmentsDao.getAll())
          .map((r) => r.toJson())
          .toList(),
      'annotations': (await db.annotationsDao.getAll())
          .map((r) => r.toJson())
          .toList(),
      'flashcards': (await db.flashcardsDao.getAll())
          .map((r) => r.toJson())
          .toList(),
      'ai_configs': (await db.aiConfigsDao.getAll())
          .map((r) => r.toJson())
          .toList(),
      'tags': (await db.tagsDao.getAll()).map((r) => r.toJson()).toList(),
    },
  };
}

/// flashcards.tags 为 JSON 数组字符串（PRD 3.3）。
List<String> decodeCardTags(String raw) {
  if (raw.isEmpty) return const [];
  final decoded = jsonDecode(raw);
  if (decoded is! List) return const [];
  return decoded.map((e) => e.toString()).toList();
}

String encodeCardTags(List<String> tags) => jsonEncode(tags);
