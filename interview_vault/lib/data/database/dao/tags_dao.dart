import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'tags_dao.g.dart';

/// PRD 2.5 预置系统标签（question/answer/highlight/mistake/improvement），
/// 与 PLAN §3 一致：每个标签带定义文案。
const systemTagSeeds = <String, String>{
  '问题': '面试官提出的问题，用于标记问题本身',
  '回答': '我的回答内容',
  '亮点': '答得好的地方',
  '失误': '答得不好的地方',
  '待改进': '需要优化的地方',
};

@DriftAccessor(tables: [Tags])
class TagsDao extends DatabaseAccessor<AppDatabase> with _$TagsDaoMixin {
  TagsDao(super.db);

  /// 建库时种子：按系统标签固定顺序写入，created_at 依次错开以保持排序稳定
  Future<void> seedSystemTags() async {
    final base = DateTime.now();
    var i = 0;
    for (final entry in systemTagSeeds.entries) {
      final ts = base.add(Duration(milliseconds: i++)).toIso8601String();
      await into(tags).insert(
        TagsCompanion.insert(
          id: 'tag-${systemTagId(entry.key)}',
          name: entry.key,
          isSystem: const Value(true),
          color: const Value(null),
          description: Value(entry.value),
          createdAt: Value(ts),
          updatedAt: Value(ts),
        ),
      );
    }
  }

  /// 普通插入：name 唯一约束冲突时抛异常（而不是静默覆盖）
  Future<void> insertOne(TagsCompanion entry) => into(tags).insert(entry);

  /// 系统标签不可删除（数据自主原则下的防误删兜底）
  Future<void> deleteOne(String id) async {
    final row = await getById(id);
    if (row == null) return;
    if (row.isSystem) {
      throw SystemTagDeletionError(row.name);
    }
    await (delete(tags)..where((t) => t.id.equals(id))).go();
  }

  Future<Tag?> getById(String id) =>
      (select(tags)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Tag>> getAll() => select(tags).get();

  /// 系统标签在前，其余按创建顺序
  Stream<List<Tag>> watchAll() {
    return (select(tags)
          ..orderBy([
            (t) => OrderingTerm.desc(t.isSystem),
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .watch();
  }
}

class SystemTagDeletionError implements Exception {
  SystemTagDeletionError(this.tagName);

  final String tagName;

  @override
  String toString() => '系统标签「$tagName」不可删除';
}

String systemTagId(String name) => switch (name) {
      '问题' => 'question',
      '回答' => 'answer',
      '亮点' => 'highlight',
      '失误' => 'mistake',
      '待改进' => 'improvement',
      _ => name.hashCode.toRadixString(36),
    };
