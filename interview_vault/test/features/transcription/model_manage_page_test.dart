import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/features/transcription/presentation/model_manage_page.dart';
import 'package:interview_vault/features/transcription/whisper_model_manager.dart';

class FakeModelGateway implements WhisperModelGateway {
  FakeModelGateway({Map<TranscribeModel, bool>? downloadedFlags})
      : downloadedFlags = downloadedFlags ?? {};

  final _events = StreamController<ModelDownloadEvent>.broadcast();

  @override
  Stream<ModelDownloadEvent> get events => _events.stream;

  late Map<TranscribeModel, bool> downloadedFlags;
  final Set<TranscribeModel> downloadingModels = {};
  final Map<TranscribeModel, int> percentValues = {};
  int downloadCalls = 0;
  int deleteCalls = 0;
  TranscribeModel? lastDownloaded;
  TranscribeModel? lastDeleted;

  @override
  Future<bool> isDownloaded(TranscribeModel model) async =>
      downloadedFlags[model] ?? false;

  @override
  Future<void> download(
    TranscribeModel model, {
    void Function(int received, int totalBytes)? onProgress,
  }) async {
    downloadCalls++;
    lastDownloaded = model;
    downloadedFlags[model] = true;
  }

  @override
  Future<void> delete(TranscribeModel model) async {
    deleteCalls++;
    lastDeleted = model;
    downloadedFlags[model] = false;
  }

  @override
  bool isDownloading(TranscribeModel model) =>
      downloadingModels.contains(model);

  @override
  int? percentOf(TranscribeModel model) => percentValues[model];

}

void main() {
  late FakeModelGateway gateway;

  setUp(() {
    gateway = FakeModelGateway();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [whisperModelGatewayProvider.overrideWithValue(gateway)],
        child: const MaterialApp(home: ModelManagePage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('展示 base/small 两张模型卡与说明', (tester) async {
    await pumpPage(tester);

    expect(find.byKey(const Key('model_card_base')), findsOneWidget);
    expect(find.byKey(const Key('model_card_small')), findsOneWidget);
    expect(find.text('Base · 中文可用 · 速度与精度均衡'), findsOneWidget);
    expect(find.text('Small · 更准更慢 · 建议 WiFi 下载'), findsOneWidget);
  });

  testWidgets('未下载模型展示下载按钮，点击触发下载', (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byKey(const Key('btn_download_base')));
    await tester.pumpAndSettle();

    expect(gateway.downloadCalls, 1);
    expect(gateway.lastDownloaded, TranscribeModel.base);
    // 下载完成后缓存刷新 → 出现"已下载"徽章与删除入口
    expect(find.text('已下载'), findsOneWidget);
    expect(find.byKey(const Key('btn_delete_base')), findsOneWidget);
  });

  testWidgets('已下载模型展示删除入口，确认后删除', (tester) async {
    gateway.downloadedFlags = {
      TranscribeModel.base: true,
      TranscribeModel.small: false,
    };
    await pumpPage(tester);

    expect(find.byKey(const Key('btn_delete_base')), findsOneWidget);
    await tester.tap(find.byKey(const Key('btn_delete_base')));
    await tester.pumpAndSettle();

    // 确认对话框
    expect(find.text('删除模型'), findsOneWidget);
    await tester.tap(find.byKey(const Key('btn_confirm_delete_model')));
    await tester.pumpAndSettle();

    expect(gateway.deleteCalls, 1);
    expect(gateway.lastDeleted, TranscribeModel.base);
  });

  testWidgets('下载中展示进度条与百分比', (tester) async {
    gateway.downloadingModels.add(TranscribeModel.small);
    gateway.percentValues[TranscribeModel.small] = 42;
    await pumpPage(tester);

    expect(find.byKey(const Key('model_progress_small')), findsOneWidget);
    expect(find.text('下载中 42%'), findsOneWidget);
    // 下载中不出现下载/删除按钮
    expect(find.byKey(const Key('btn_download_small')), findsNothing);
  });
}
