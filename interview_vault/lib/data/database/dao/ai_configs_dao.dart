import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'ai_configs_dao.g.dart';

@DriftAccessor(tables: [AiConfigs])
class AiConfigsDao extends DatabaseAccessor<AppDatabase>
    with _$AiConfigsDaoMixin {
  AiConfigsDao(super.db);

  Future<void> upsert(AiConfigsCompanion entry) =>
      into(aiConfigs).insert(entry, mode: InsertMode.insertOrReplace);

  Future<void> deleteOne(String id) =>
      (delete(aiConfigs)..where((t) => t.id.equals(id))).go().then((_) {});

  Future<AiConfig?> getById(String id) =>
      (select(aiConfigs)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<AiConfig>> getAll() =>
      (select(aiConfigs)..orderBy([(t) => OrderingTerm.asc(t.createdAt)])).get();

  /// 独占激活：指定配置激活，其余全部置为 inactive
  Future<void> setActive(String id) {
    return transaction(() async {
      await (update(aiConfigs)..where((t) => t.isActive.equals(true))).write(
        AiConfigsCompanion(isActive: const Value(false), updatedAt: Value(nowIso())),
      );
      await (update(aiConfigs)..where((t) => t.id.equals(id))).write(
        AiConfigsCompanion(isActive: const Value(true), updatedAt: Value(nowIso())),
      );
    });
  }

  Future<AiConfig?> getActive() =>
      (select(aiConfigs)..where((t) => t.isActive.equals(true)))
          .getSingleOrNull();

  Stream<AiConfig?> watchActive() =>
      (select(aiConfigs)..where((t) => t.isActive.equals(true)))
          .watchSingleOrNull();

  Future<void> clearActive() {
    return (update(aiConfigs)..where((t) => t.isActive.equals(true))).write(
      AiConfigsCompanion(isActive: const Value(false), updatedAt: Value(nowIso())),
    );
  }
}
