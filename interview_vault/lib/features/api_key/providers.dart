import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart';
import '../../data/secure/key_storage.dart';
import 'ai_config_service.dart';

/// 数据库单例：W1 起全程复用（drift 内部管理连接）。
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// KeyStorage：API Key 唯一读写入口（flutter_secure_storage 封装）。
final keyStorageProvider = Provider<KeyStorage>((ref) => KeyStorage());

/// AI 配置面（DB 配置 + Key 本体的组合操作）。
final aiConfigServiceProvider = Provider<AiConfigService>(
  (ref) => AiConfigService(
    db: ref.watch(appDatabaseProvider),
    keyStorage: ref.watch(keyStorageProvider),
  ),
);
