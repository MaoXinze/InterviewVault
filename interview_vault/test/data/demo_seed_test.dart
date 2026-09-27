import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/data/demo/demo_seed.dart';

/// 演示数据填充：--dart-define=DEMO_SEED=true 构建专用，
/// 正式构建不含调用路径，但填充逻辑本身要有数据层测试兜底。
void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  test('空库填充：3 场面试 + 逐字稿/标注/卡片齐备，系统标签不受影响', () async {
    final seeded = await seedDemoDataIfEmpty(db);

    expect(seeded, isTrue);
    final interviews = await db.interviewsDao.getAll();
    expect(interviews.length, 3);
    expect((await db.segmentsDao.getAll()).length, 18);
    expect((await db.annotationsDao.getAll()).length, 13);
    expect((await db.flashcardsDao.getAll()).length, 5);
    // 系统标签是建库预置，演示数据不动它
    expect((await db.tagsDao.getAll()).length, 5);
    // 演示数据覆盖三种形态：已标注真实面试 / 已转写未标注 / 模拟面试
    final statuses = interviews.map((i) => i.status).toSet();
    expect(statuses, containsAll(['annotated', 'transcribed']));
    final mock = interviews.firstWhere((i) => i.id == 'iv-demo-mock');
    expect(mock.audioFilePath, isNull);
  });

  test('已有数据时跳过填充（不污染真实库）', () async {
    await seedDemoDataIfEmpty(db);
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(id: 'iv-real', company: const Value('真实公司')),
    );

    final seededAgain = await seedDemoDataIfEmpty(db);

    expect(seededAgain, isFalse);
    expect((await db.interviewsDao.getAll()).length, 4);
    expect((await db.flashcardsDao.getAll()).length, 5);
  });

  test('演示卡片标签为合法 JSON 数组（与回顾页筛选打通）', () async {
    await seedDemoDataIfEmpty(db);

    final card = await db.flashcardsDao.getById('iv-demo-bytedance-c1');
    expect(card, isNotNull);
    expect(decodeCardTags(card!.tags), ['问题', '亮点', '回答']);
  });
}
