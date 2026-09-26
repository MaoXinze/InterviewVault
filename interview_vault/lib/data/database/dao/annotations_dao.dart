import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'annotations_dao.g.dart';

@DriftAccessor(tables: [Annotations])
class AnnotationsDao extends DatabaseAccessor<AppDatabase>
    with _$AnnotationsDaoMixin {
  AnnotationsDao(super.db);

  Future<void> insertOne(AnnotationsCompanion entry) =>
      into(annotations).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateOne(String id, AnnotationsCompanion entry) =>
      (update(annotations)..where((t) => t.id.equals(id))).write(
        entry.copyWith(updatedAt: Value(nowIso())),
      );

  Future<void> deleteOne(String id) =>
      (delete(annotations)..where((t) => t.id.equals(id))).go().then((_) {});

  Future<List<Annotation>> getAll() => select(annotations).get();

  Future<List<Annotation>> getByInterview(String interviewId) {
    return (select(annotations)
          ..where((t) => t.interviewId.equals(interviewId))
          ..orderBy([
            (t) => OrderingTerm.asc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }

  /// 按标签筛选（全局，跨面试）——快速定位所有"失误"/"待改进"
  Future<List<Annotation>> filterByTag(String tag, {String? customTagName}) {
    return (select(annotations)
          ..where(
            (t) =>
                t.tag.equals(tag) &
                (customTagName == null
                    ? const Constant(true)
                    : t.customTagName.equals(customTagName)),
          )
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.asc(t.id),
          ]))
        .get();
  }
}
