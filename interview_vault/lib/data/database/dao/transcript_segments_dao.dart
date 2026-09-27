import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'transcript_segments_dao.g.dart';

/// 逐字稿片段 DAO（db.segmentsDao）
@DriftAccessor(tables: [TranscriptSegments])
class SegmentsDao extends DatabaseAccessor<AppDatabase>
    with _$SegmentsDaoMixin {
  SegmentsDao(super.db);

  Future<void> insertOne(TranscriptSegmentsCompanion entry) =>
      into(transcriptSegments).insert(entry, mode: InsertMode.insertOrReplace);

  /// 单段编辑校正 / 说话人标记（W2-M3 逐字稿页）
  Future<void> updateOne(String id, TranscriptSegmentsCompanion entry) =>
      (update(transcriptSegments)..where((t) => t.id.equals(id))).write(
        entry.copyWith(updatedAt: Value(nowIso())),
      );

  Future<void> insertAll(List<TranscriptSegmentsCompanion> entries) =>
      batch((b) => b.insertAll(
            transcriptSegments,
            entries,
            mode: InsertMode.insertOrReplace,
          ));

  /// 逐字稿整段替换（编辑校正场景）：删除旧片段后写入新片段
  Future<void> replaceAllForInterview(
    String interviewId,
    List<TranscriptSegmentsCompanion> entries,
  ) {
    return transaction(() async {
      await (delete(transcriptSegments)
            ..where((t) => t.interviewId.equals(interviewId)))
          .go();
      await insertAll(entries);
    });
  }

  Future<List<TranscriptSegment>> getAll() => select(transcriptSegments).get();

  /// 按 start_time 升序
  Future<List<TranscriptSegment>> getByInterview(String interviewId) {
    return (select(transcriptSegments)
          ..where((t) => t.interviewId.equals(interviewId))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .get();
  }

  Stream<List<TranscriptSegment>> watchByInterview(String interviewId) {
    return (select(transcriptSegments)
          ..where((t) => t.interviewId.equals(interviewId))
          ..orderBy([(t) => OrderingTerm.asc(t.startTime)]))
        .watch();
  }
}
