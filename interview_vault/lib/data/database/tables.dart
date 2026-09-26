import 'package:drift/drift.dart';

/// PRD 3.3 schema v1 + PLAN §3 约定：
/// - 所有表带 created_at/updated_at（TEXT ISO8601，Dart 侧默认值）
/// - 子表外键走 customConstraint 以带上 ON DELETE CASCADE
/// - API Key 不入库（执行修订 #5），ai_configs 仅存 provider/model/baseUrl

String nowIso() => DateTime.now().toIso8601String();

/// 面试记录
class Interviews extends Table {
  TextColumn get id => text()();
  TextColumn get company => text().nullable()();
  TextColumn get position => text().nullable()();
  TextColumn get round => text().nullable()();
  TextColumn get interviewDate => text().nullable()();
  IntColumn get durationSeconds => integer().nullable()();
  TextColumn get audioFilePath => text().nullable()();
  TextColumn get transcriptText => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get createdAt => text().clientDefault(nowIso)();
  TextColumn get updatedAt => text().clientDefault(nowIso)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 转写片段（带时间戳的逐字稿）
class TranscriptSegments extends Table {
  TextColumn get id => text()();
  TextColumn get interviewId =>
      text().customConstraint('REFERENCES interviews (id) ON DELETE CASCADE')();
  RealColumn get startTime => real()();
  RealColumn get endTime => real()();
  /// 列名按 PRD 为 text；getter 用 content 避免与 drift 的 text() 构建器重名
  TextColumn get content => text().named('text')();
  TextColumn get speaker => text().nullable()(); // interviewer/candidate
  TextColumn get createdAt => text().clientDefault(nowIso)();
  TextColumn get updatedAt => text().clientDefault(nowIso)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 标注
class Annotations extends Table {
  TextColumn get id => text()();
  TextColumn get interviewId =>
      text().customConstraint('REFERENCES interviews (id) ON DELETE CASCADE')();
  TextColumn get segmentId => text().nullable()();
  IntColumn get startOffset => integer().nullable()();
  IntColumn get endOffset => integer().nullable()();
  TextColumn get tag => text()(); // question/answer/highlight/mistake/improvement/custom
  TextColumn get customTagName => text().nullable()();
  TextColumn get note => text().nullable()();
  TextColumn get createdAt => text().clientDefault(nowIso)();
  TextColumn get updatedAt => text().clientDefault(nowIso)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 问题卡片
class Flashcards extends Table {
  TextColumn get id => text()();
  TextColumn get interviewId =>
      text().customConstraint('REFERENCES interviews (id) ON DELETE CASCADE')();
  TextColumn get question => text()();
  TextColumn get myAnswer => text().nullable()();
  TextColumn get aiReference => text().nullable()();
  /// JSON 数组字符串，与标注标签体系打通；用 encodeCardTags/decodeCardTags 读写
  TextColumn get tags => text().withDefault(const Constant('[]'))();
  RealColumn get sourceStartTime => real().nullable()();
  RealColumn get sourceEndTime => real().nullable()();
  IntColumn get reviewCount => integer().withDefault(const Constant(0))();
  TextColumn get lastReviewedAt => text().nullable()();
  TextColumn get createdAt => text().clientDefault(nowIso)();
  TextColumn get updatedAt => text().clientDefault(nowIso)();

  @override
  Set<Column> get primaryKey => {id};
}

/// AI 配置（不存 Key 本体，Key 在 flutter_secure_storage）
class AiConfigs extends Table {
  TextColumn get id => text()();
  TextColumn get provider => text()(); // openai/deepseek/kimi/qwen/anthropic/custom
  TextColumn get modelName => text().nullable()();
  TextColumn get baseUrl => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
  TextColumn get createdAt => text().clientDefault(nowIso)();
  TextColumn get updatedAt => text().clientDefault(nowIso)();

  @override
  Set<Column> get primaryKey => {id};
}

/// 标签（预置 5 个系统标签 + 用户自定义）
class Tags extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get color => text().nullable()();
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();
  /// 系统标签定义文案（PLAN §3）
  TextColumn get description => text().nullable()();
  TextColumn get createdAt => text().clientDefault(nowIso)();
  TextColumn get updatedAt => text().clientDefault(nowIso)();

  @override
  Set<Column> get primaryKey => {id};
}
