import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database/app_database.dart';
import '../data/local/audio_files.dart' as audio_files;
import '../data/secure/key_storage.dart';
import '../features/api_key/ai_config_service.dart';
import '../features/export/data_management_service.dart';
import '../features/export/markdown_export_service.dart';
import '../features/flashcards/flashcard_service.dart';
import '../features/import/audio_import_service.dart';
import '../features/interviews/audio_playback.dart';
import '../features/mock/mock_interview_service.dart';
import '../features/recording/recorder_service.dart';
import '../features/transcription/transcription_service.dart';
import '../features/transcription/whisper_engine.dart';
import '../features/transcription/whisper_model_manager.dart';
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

/// 录音服务：录音页的状态与动作源（record 插件封装）。
final recorderServiceProvider = Provider<RecorderService>((ref) {
  final service = RecorderService();
  ref.onDispose(service.dispose);
  return service;
});

/// 音频文件清理（删除面试时同步删文件，AGENTS 铁律 3"删除即真删"）。
/// 函数式注入：测试用记录型桩替换。
final audioFileCleanerProvider = Provider<Future<void> Function(String?)>(
  (ref) => audio_files.deleteAudioFile,
);

/// 音频导入服务（W2-M2：系统选择器 → 格式确认 → 复制进库）。
final audioImportServiceProvider = Provider<AudioImportService>(
  (ref) => AudioImportService(),
);

/// 本地转写模型网关（W2-M3：下载/校验/删除 ggml 模型）。
final whisperModelGatewayProvider = Provider<WhisperModelGateway>(
  (ref) => WhisperModelManager(),
);

/// 本地转写引擎（whisper_ggml 封装；推理在包内后台 isolate）。
final whisperEngineProvider = Provider<WhisperEngine>(
  (ref) => WhisperGgmlEngine(),
);

/// 转写编排服务（分段落库 + 状态翻转 + 进度事件）。
final transcriptionServiceProvider = Provider<TranscriptionRunner>((ref) {
  final service = TranscriptionService(
    db: ref.watch(appDatabaseProvider),
    engine: ref.watch(whisperEngineProvider),
    isModelDownloaded: (model) =>
        ref.watch(whisperModelGatewayProvider).isDownloaded(model),
  );
  ref.onDispose(service.dispose);
  return service;
});

/// 单场面试详情流（详情页：转写状态变化实时刷新）。
final interviewByIdProvider =
    StreamProvider.family<Interview?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.interviewsDao.watchById(id);
});

/// 单场面试逐字稿分段流（详情页）。
final segmentsByInterviewProvider =
    StreamProvider.family<List<TranscriptSegment>, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.segmentsDao.watchByInterview(id);
});

/// 单场面试的最近一次转写事件（详情页进度条；无事件时为 loading）。
final transcriptionProgressProvider =
    StreamProvider.family<TranscriptionEvent, String>((ref, id) {
  return ref
      .watch(transcriptionServiceProvider)
      .events
      .where((e) => e.interviewId == id);
});

/// 模型下载事件流（模型管理页与转写入口共用）。
final whisperModelEventsProvider = StreamProvider<ModelDownloadEvent>((ref) {
  return ref.watch(whisperModelGatewayProvider).events;
});

/// 面试录音回放（W3-M1：迷你播放条 + 点标注跳播放）。
final audioPlaybackProvider = Provider<AudioPlayback>((ref) {
  final playback = JustAudioPlayback();
  ref.onDispose(playback.dispose);
  return playback;
});

/// 回放状态流（迷你播放条渲染；订阅即重放当前值）。
final audioPlaybackStatesProvider = StreamProvider<AudioPlaybackSnapshot>((ref) {
  return ref.watch(audioPlaybackProvider).states;
});

/// 单场面试标注流（详情页标注 chips 与标签筛选实时刷新）。
final annotationsByInterviewProvider =
    StreamProvider.family<List<Annotation>, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.annotationsDao.watchByInterview(id);
});

/// 问题卡片编排（W3-M2：标注生成卡片 + AI 参考流式）。
final flashcardServiceProvider = Provider<FlashcardService>((ref) {
  return FlashcardService(
    db: ref.watch(appDatabaseProvider),
    chatClientFactory: () =>
        ref.read(aiConfigServiceProvider).activeChatClient(),
  );
});

/// 模拟面试编排（W3-M3：出题 + 逐题流式反馈 + 会话落库）。
final mockInterviewServiceProvider = Provider<MockInterviewService>((ref) {
  return MockInterviewService(
    db: ref.watch(appDatabaseProvider),
    chatClientFactory: () =>
        ref.read(aiConfigServiceProvider).activeChatClient(),
  );
});

/// 单张卡片流（卡片详情页）。
final cardByIdProvider =
    StreamProvider.family<Flashcard?, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.flashcardsDao.watchById(id);
});

/// 单场面试卡片流（W4-M1 总结页：时间轴序，与导出一致）。
final flashcardsByInterviewProvider =
    StreamProvider.family<List<Flashcard>, String>((ref, id) {
  final db = ref.watch(appDatabaseProvider);
  return db.flashcardsDao.watchByInterview(id);
});

/// Markdown 复盘导出（W4-M1：拼模板 + 落盘 exports/ + 状态推进）。
final markdownExportServiceProvider = Provider<MarkdownExportService>((ref) {
  return MarkdownExportService(db: ref.watch(appDatabaseProvider));
});

/// 数据管理（W4-M2：全量 JSON/Markdown 导出 + 删除全部）。
/// 录音清理复用"删除即真删"的注入式清理函数。
final dataManagementServiceProvider = Provider<DataManagementService>((ref) {
  return DataManagementService(
    db: ref.watch(appDatabaseProvider),
    keyStorage: ref.watch(keyStorageProvider),
    audioFileCleaner: ref.watch(audioFileCleanerProvider),
  );
});

/// 导出后的系统分享入口（share_plus），函数式注入便于测试替换。
Future<void> defaultShareMarkdown(String path) async {
  await SharePlus.instance.share(
    ShareParams(files: [XFile(path)], subject: '面试复盘'),
  );
}

final markdownSharerProvider = Provider<Future<void> Function(String path)>(
  (ref) => defaultShareMarkdown,
);
