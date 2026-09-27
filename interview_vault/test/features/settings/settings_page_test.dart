import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/export/data_management_service.dart';
import 'package:interview_vault/features/export/markdown_export_service.dart';
import 'package:interview_vault/features/settings/presentation/privacy_page.dart';
import 'package:interview_vault/features/settings/presentation/settings_page.dart';

import '../../helpers/pump_app.dart';

/// 页面级桩：导出/删除全部内存化（落盘行为由 data_management_service_test
/// 覆盖，widget 测试只验证页面流程）。
class _StubDataManagementService extends DataManagementService {
  _StubDataManagementService(AppDatabase db)
      : super(
          db: db,
          keyStorage: FakeKeyStorage(),
          documentsPathResolver: () async => '/stub',
          audioFileCleaner: (_) async {},
        );

  int jsonExports = 0;
  int mdExports = 0;
  int deleteCalls = 0;
  int deletedInterviews = 3;

  @override
  Future<ExportedFile> exportAllJson() async {
    jsonExports++;
    return const ExportedFile(
      path: '/stub/exports/interviewvault-export.json',
      fileName: 'interviewvault-export.json',
    );
  }

  @override
  Future<ExportedFile> exportAllMarkdown() async {
    mdExports++;
    return const ExportedFile(
      path: '/stub/exports/interviewvault-复盘全量.md',
      fileName: 'interviewvault-复盘全量.md',
    );
  }

  @override
  Future<DeleteAllResult> deleteAllData() async {
    deleteCalls++;
    return DeleteAllResult(deletedInterviews: deletedInterviews);
  }
}

void main() {
  late AppDatabase db;
  late AppDatabase stubDb;
  late _StubDataManagementService service;
  final shared = <String>[];

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    stubDb = AppDatabase.forTesting(NativeDatabase.memory());
    service = _StubDataManagementService(stubDb);
    shared.clear();
  });
  tearDown(() async {
    await db.close();
    await stubDb.close();
  });

  Future<void> pumpSettings(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appDatabaseProvider.overrideWithValue(db),
          dataManagementServiceProvider.overrideWithValue(service),
          markdownSharerProvider.overrideWithValue(
            (path) async => shared.add(path),
          ),
        ],
        child: const MaterialApp(home: SettingsPage()),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => drainAppTimers(tester));
  }

  /// SnackBar 的 4s 自动消失 Timer 需推进假时钟走完
  Future<void> drainSnackBar(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await drainAppTimers(tester);
  }

  group('数据导出', () {
    testWidgets('导出入口弹出方式选择（JSON / Markdown）', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('btn_export_data')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('btn_export_json')), findsOneWidget);
      expect(find.byKey(const Key('btn_export_md')), findsOneWidget);
      expect(service.jsonExports, 0);
      await drainAppTimers(tester);
    });

    testWidgets('全量 JSON：调服务 → 分享 → snackbar 确认', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('btn_export_data')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_export_json')));
      await tester.pumpAndSettle();

      expect(service.jsonExports, 1);
      expect(service.mdExports, 0);
      expect(shared, ['/stub/exports/interviewvault-export.json']);
      expect(find.text('已导出 interviewvault-export.json'), findsOneWidget);
      await drainSnackBar(tester);
    });

    testWidgets('全量 Markdown：调服务 → 分享 → snackbar 确认', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('btn_export_data')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_export_md')));
      await tester.pumpAndSettle();

      expect(service.mdExports, 1);
      expect(shared, ['/stub/exports/interviewvault-复盘全量.md']);
      expect(find.text('已导出 interviewvault-复盘全量.md'), findsOneWidget);
      await drainSnackBar(tester);
    });
  });

  group('数据删除', () {
    testWidgets('删除全部：二次确认弹窗，取消不执行', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('btn_delete_all')));
      await tester.pumpAndSettle();

      expect(find.text('删除全部数据？'), findsOneWidget);
      expect(find.textContaining('删除即真删，不可恢复'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(service.deleteCalls, 0);
      await drainAppTimers(tester);
    });

    testWidgets('确认后真删并提示场次', (tester) async {
      await pumpSettings(tester);

      await tester.tap(find.byKey(const Key('btn_delete_all')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('btn_delete_confirm')));
      await tester.pumpAndSettle();

      expect(service.deleteCalls, 1);
      expect(find.text('已删除 3 场面试记录'), findsOneWidget);
      await drainSnackBar(tester);
    });
  });

  group('隐私政策全文', () {
    testWidgets('含用户协议与权限说明，无 W4 占位文案', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: PrivacyPage()));
      await tester.pumpAndSettle();

      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.text('用户协议'), findsOneWidget);
      expect(find.text('权限使用'), findsOneWidget);
      expect(find.textContaining('W4'), findsNothing);
      await drainAppTimers(tester);
    });
  });
}
