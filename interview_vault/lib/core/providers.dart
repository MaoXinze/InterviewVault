import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database/app_database.dart';
import '../data/secure/key_storage.dart';
import '../features/api_key/ai_config_service.dart';
import 'widgets/theme_reveal.dart';

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

/// 待回顾卡片数（首页"N 道题待回顾"）。
final flashcardCountProvider = StreamProvider<int>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.flashcardsDao.watchAll().map((cards) => cards.length);
});

/// 最近面试流（首页/面试页共用）。
final interviewsStreamProvider = StreamProvider<List<Interview>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.interviewsDao.watchAll();
});

/// 全部问题卡片流（回顾页）。
final flashcardsStreamProvider = StreamProvider<List<Flashcard>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.flashcardsDao.watchAll();
});

/// 标签流（回顾页筛选 chips，含系统与自定义）。
final tagsStreamProvider = StreamProvider<List<Tag>>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return db.tagsDao.watchAll();
});

/// 圆形主题切换控制器（模式① Radial Theme Transition）。
final themeRevealControllerProvider = Provider<ThemeRevealController>((ref) {
  final controller = ThemeRevealController();
  ref.onDispose(controller.dispose);
  return controller;
});
