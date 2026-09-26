import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'interviews_dao.g.dart';

@DriftAccessor(tables: [Interviews])
class InterviewsDao extends DatabaseAccessor<AppDatabase>
    with _$InterviewsDaoMixin {
  InterviewsDao(super.db);

  Future<void> insertOne(InterviewsCompanion entry) =>
      into(interviews).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateOne(String id, InterviewsCompanion entry) =>
      (update(interviews)..where((t) => t.id.equals(id))).write(
        entry.copyWith(updatedAt: Value(nowIso())),
      );

  Future<void> deleteOne(String id) =>
      (delete(interviews)..where((t) => t.id.equals(id))).go().then((_) {});

  Future<Interview?> getById(String id) =>
      (select(interviews)..where((t) => t.id.equals(id))).getSingleOrNull();

  /// 按面试日期倒序（最新在前）
  Stream<List<Interview>> watchAll() {
    return (select(interviews)
          ..orderBy([
            (t) => OrderingTerm.desc(t.interviewDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<List<Interview>> getAll() => select(interviews).get();

  /// 搜索：公司 / 岗位 关键词（W1 数据层能力，UI 在 Step5 接入）
  Future<List<Interview>> search(String keyword) {
    final pattern = '%$keyword%';
    return (select(interviews)
          ..where(
            (t) =>
                t.company.like(pattern) | t.position.like(pattern),
          )
          ..orderBy([
            (t) => OrderingTerm.desc(t.interviewDate),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .get();
  }
}
