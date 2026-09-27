import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/core/router.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/review/presentation/flashcard_flip_page.dart';
import '../../helpers/pump_app.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() => db.close());

  Future<List<Flashcard>> seedCards() async {
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: const Value('字节跳动'),
      ),
    );
    for (final (id, question, answer, ai, tags) in const [
      ('fc-1', '请介绍你最有挑战的项目', '我负责直播秒杀的链路改造', '先讲背景，再讲权衡', '["问题","亮点"]'),
      ('fc-2', '说说你对状态管理的理解', null, null, '["问题"]'),
    ]) {
      await db.flashcardsDao.insertOne(
        FlashcardsCompanion.insert(
          id: id,
          interviewId: 'iv-1',
          question: question,
          myAnswer: answer == null ? const Value(null) : Value(answer),
          aiReference: ai == null ? const Value(null) : Value(ai),
          tags: Value(tags),
        ),
      );
    }
    return db.flashcardsDao.getByInterview('iv-1');
  }

  Future<void> pumpFlip(
    WidgetTester tester,
    List<Flashcard> cards,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: FlashcardFlipPage(cards: cards)),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => drainAppTimers(tester));
  }

  testWidgets('正面显示问题与进度，背面内容不出现', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    expect(find.byKey(const Key('page_flip')), findsOneWidget);
    expect(find.byKey(const Key('flip_card_fc-1')), findsOneWidget);
    expect(find.text('请介绍你最有挑战的项目'), findsOneWidget);
    expect(find.textContaining('1 / 2'), findsOneWidget);
    // 背面未渲染
    expect(find.text('我负责直播秒杀的链路改造'), findsNothing);
    await drainAppTimers(tester);
  });

  testWidgets('点击翻面：背面显示我的回答与 AI 参考', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    await tester.tap(find.byKey(const Key('flip_card_fc-1')));
    await tester.pumpAndSettle();

    expect(find.text('我负责直播秒杀的链路改造'), findsOneWidget);
    expect(find.text('AI 参考思路'), findsOneWidget);
    expect(find.text('先讲背景，再讲权衡'), findsOneWidget);
    await drainAppTimers(tester);
  });

  testWidgets('已复习下一张：markReviewed 落库并推进', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    await tester.tap(find.byKey(const Key('btn_reviewed_next')));
    await tester.pumpAndSettle();

    final reviewed = await db.flashcardsDao.getById('fc-1');
    expect(reviewed!.reviewCount, 1);
    expect(reviewed.lastReviewedAt, isNotNull);
    // 推进到第二张
    expect(find.byKey(const Key('flip_card_fc-2')), findsOneWidget);
    expect(find.text('说说你对状态管理的理解'), findsOneWidget);
    expect(find.textContaining('2 / 2'), findsOneWidget);
    await drainAppTimers(tester);
  });

  testWidgets('跳过不标记：复习次数不变', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    await tester.tap(find.byKey(const Key('btn_skip_card')));
    await tester.pumpAndSettle();

    final card = await db.flashcardsDao.getById('fc-1');
    expect(card!.reviewCount, 0);
    expect(card.lastReviewedAt, isNull);
    expect(find.byKey(const Key('flip_card_fc-2')), findsOneWidget);
    await drainAppTimers(tester);
  });

  testWidgets('全部标记后进入完成页', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    await tester.tap(find.byKey(const Key('btn_reviewed_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn_reviewed_next')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('flip_finish')), findsOneWidget);
    expect(find.text('本轮复习完成'), findsOneWidget);
    expect(find.text('本次标记复习 2 张 · 已复习 2 张卡'), findsOneWidget);
    // 数据库两次 markReviewed
    expect((await db.flashcardsDao.getById('fc-2'))!.reviewCount, 1);
    await drainAppTimers(tester);
  });

  testWidgets('回顾页筛选后进入翻卡：只复习筛选命中的卡片', (tester) async {
    final db = await pumpInterviewVaultApp(tester);
    addTearDown(db.close);
    await db.interviewsDao.insertOne(
      InterviewsCompanion.insert(
        id: 'iv-1',
        company: const Value('字节跳动'),
      ),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-1',
        interviewId: 'iv-1',
        question: '请介绍你最有挑战的项目',
        tags: const Value('["问题"]'),
      ),
    );
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: 'fc-2',
        interviewId: 'iv-1',
        question: '说说你对状态管理的理解',
        tags: const Value('["亮点"]'),
      ),
    );

    appRouter.go('/home');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tab_review')));
    await tester.pumpAndSettle();
    // 选中"亮点"标签筛选（卡片副标题也含"亮点"文本，须按 chip key 点击）
    await tester.tap(find.byKey(const Key('tag_chip_亮点')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review_card_fc-1')), findsNothing);
    expect(find.byKey(const Key('review_card_fc-2')), findsOneWidget);

    await tester.tap(find.text('开始回顾'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page_flip')), findsOneWidget);
    expect(find.text('说说你对状态管理的理解'), findsOneWidget);
    expect(find.textContaining('1 / 1'), findsOneWidget);
    expect(find.text('请介绍你最有挑战的项目'), findsNothing);

    appRouter.go('/home');
    await tester.pumpAndSettle();
    await drainAppTimers(tester);
  });
}
