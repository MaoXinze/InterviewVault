import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'ai_configs_dao.g.dart';

@DriftAccessor(tables: [AiConfigs])
class AiConfigsDao extends DatabaseAccessor<AppDatabase>
    with _$AiConfigsDaoMixin {
  AiConfigsDao(super.db);

  /// 按 id 覆盖式保存；已存在时保留 createdAt（insertOrReplace 会整行
  /// 替换、把 createdAt 重置为 now，导致"配置创建时间"随每次保存漂移）
  Future<void> upsert(AiConfigsCompanion entry) async {
    if (!entry.id.present) {
      throw ArgumentError('upsert 需要显式 id', 'entry');
    }
    final id = entry.id.value;
    final existing = await (select(aiConfigs)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (existing == null) {
      await into(aiConfigs).insert(entry);
    } else {
      await (update(aiConfigs)..where((t) => t.id.equals(id))).write(
        entry.copyWith(updatedAt: Value(nowIso())),
      );
    }
  }

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
