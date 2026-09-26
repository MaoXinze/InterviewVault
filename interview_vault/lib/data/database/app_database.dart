import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'dao/ai_configs_dao.dart';
import 'dao/annotations_dao.dart';
import 'dao/flashcards_dao.dart';
import 'dao/interviews_dao.dart';
import 'dao/tags_dao.dart';
import 'dao/transcript_segments_dao.dart';
import 'tables.dart';

export 'dao/tags_dao.dart' show SystemTagDeletionError;
export 'export.dart';

part 'app_database.g.dart';

/// InterviewVault 本地数据库 v1。
///
/// 外键约束在 beforeOpen 中开启（PRAGMA foreign_keys=ON），
/// 子表外键均带 ON DELETE CASCADE：删除面试记录即连带删除片段/标注/卡片。
@DriftDatabase(
  tables: [
    Interviews,
    TranscriptSegments,
    Annotations,
    Flashcards,
    AiConfigs,
    Tags,
  ],
  daos: [
    InterviewsDao,
    SegmentsDao,
    AnnotationsDao,
    FlashcardsDao,
    AiConfigsDao,
    TagsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.db);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // v1 起维护迁移：后续版本在 onUpgrade 里按 fromSchemaVersion 升级，
        // 禁止破坏性重建（AGENTS 工程纪律 3）
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // 兜底补种：onCreate 只在新库执行；web 端浏览器里可能存在
          // 建库早于种子逻辑或被清空过的库，保证系统标签永远在
          final row = await customSelect(
            'SELECT COUNT(*) AS c FROM tags',
          ).getSingle();
          if ((row.data['c'] as int) == 0) {
            await tagsDao.seedSystemTags();
          }
        },
      );
}

QueryExecutor _openConnection() => driftDatabase(name: 'interview_vault');
