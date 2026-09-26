import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'flashcards_dao.g.dart';

@DriftAccessor(tables: [Flashcards])
class FlashcardsDao extends DatabaseAccessor<AppDatabase>
    with _$FlashcardsDaoMixin {
  FlashcardsDao(super.db);

  Future<void> insertOne(FlashcardsCompanion entry) =>
      into(flashcards).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> updateOne(String id, FlashcardsCompanion entry) =>
      (update(flashcards)..where((t) => t.id.equals(id))).write(
        entry.copyWith(updatedAt: Value(nowIso())),
      );

  Future<void> deleteOne(String id) =>
      (delete(flashcards)..where((t) => t.id.equals(id))).go().then((_) {});

  Future<Flashcard?> getById(String id) =>
      (select(flashcards)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<Flashcard>> getAll() => select(flashcards).get();

  Future<List<Flashcard>> getByInterview(String interviewId) {
    return (select(flashcards)
          ..where((t) => t.interviewId.equals(interviewId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Stream<List<Flashcard>> watchAll() {
    return (select(flashcards)
          ..orderBy([
            (t) => OrderingTerm.desc(t.createdAt),
            (t) => OrderingTerm.desc(t.id),
          ]))
        .watch();
  }

  Future<int> countAll() async {
    final row = await customSelect('SELECT COUNT(*) AS c FROM flashcards')
        .getSingle();
    return row.data['c'] as int;
  }

  /// 翻卡复习：复习次数 +1 并记录时间（P1 间隔重复的基础）
  Future<void> markReviewed(String id) {
    return customUpdate(
      'UPDATE flashcards SET review_count = review_count + 1, '
      'last_reviewed_at = ?, updated_at = ? WHERE id = ?',
      variables: [Variable(nowIso()), Variable(nowIso()), Variable(id)],
    );
  }
}
