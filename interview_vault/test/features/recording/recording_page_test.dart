import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:interview_vault/features/recording/recorder_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import '../../helpers/pump_app.dart';

class MockAudioRecorder extends Mock implements AudioRecorder {}

void main() {
  setUpAll(() {
    registerFallbackValue(RecordConfig(encoder: AudioEncoder.wav));
  });

  testWidgets('录音页：待开始 → 录音中计时 → 停止入库并跳转面试列表', (tester) async {
    final recorder = MockAudioRecorder();
    when(() => recorder.hasPermission()).thenAnswer((_) async => true);
    when(() => recorder.isEncoderSupported(AudioEncoder.wav))
        .thenAnswer((_) async => true);
    when(() => recorder.start(any(), path: any(named: 'path')))
        .thenAnswer((_) async {});
    when(() => recorder.getAmplitude())
        .thenAnswer((_) async => Amplitude(current: -30, max: -20));
    when(() => recorder.stop()).thenAnswer((_) async => '/recordings/x.wav');
    when(() => recorder.dispose()).thenAnswer((_) async {});
    when(() => recorder.onStateChanged())
        .thenAnswer((_) => const Stream<RecordState>.empty());

    final service = RecorderService(
      recorder: recorder,
      pathResolver: (_) async => '/recordings/x.wav',
    );
    final db = await pumpInterviewVaultApp(tester, recorder: service);
    addTearDown(service.dispose);
    addTearDown(db.close);

    await tester.tap(find.byKey(const Key('tab_record')));
    await tester.pumpAndSettle();

    // 待开始态
    expect(find.text('00:00'), findsOneWidget);
    expect(find.byKey(const Key('btn_rec_start')), findsOneWidget);

    // 开始录音：状态切换 + 计时走 2 秒
    await tester.tap(find.byKey(const Key('btn_rec_start')));
    await tester.pump();
    expect(find.text('录音中'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('00:02'), findsOneWidget);

    // 停止：落库 + 跳转面试列表
    await tester.tap(find.byKey(const Key('btn_rec_stop')));
    await tester.pumpAndSettle();

    final rows = await db.interviewsDao.getAll();
    expect(rows, hasLength(1));
    expect(rows.single.durationSeconds, 2);
    expect(rows.single.status, 'draft');
    expect(rows.single.audioFilePath, '/recordings/x.wav');
    expect(find.byKey(const Key('page_interviews')), findsOneWidget);

    await drainAppTimers(tester);
  });
}
