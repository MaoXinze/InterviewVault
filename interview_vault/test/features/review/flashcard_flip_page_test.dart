import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/core/providers.dart';
import 'package:interview_vault/core/router.dart';
import 'package:interview_vault/core/widgets/illustration.dart';
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

  /// 模拟真实拖拽：分步移动。首个移动事件被拖拽启动（slop）消耗，
  /// 不会作为 update 分发——单次 moveBy 拿不到任何 update 事件。
  Future<TestGesture> dragSteps(
    WidgetTester tester,
    Finder finder,
    Offset total, {
    Duration stepInterval = Duration.zero,
    int steps = 5,
  }) async {
    final center = tester.getCenter(finder);
    final gesture = await tester.startGesture(center);
    await tester.pump();
    final per = Offset(total.dx / steps, total.dy / steps);
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(per);
      await tester.pump(stepInterval);
    }
    return gesture;
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

  testWidgets('翻面后背面文字不呈镜像（合成旋转须归位）', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    // 正面静止：合成 x 分量为 1
    final frontMatrix = tester
        .renderObject<RenderBox>(find.text('请介绍你最有挑战的项目'))
        .getTransformTo(null);
    expect(frontMatrix.entry(0, 0), moreOrLessEquals(1.0));

    await tester.tap(find.byKey(const Key('flip_card_fc-1')));
    await tester.pumpAndSettle();

    // 背面静止：外层 rotationY(π) × 内容预转 rotationY(π) = 2π 归位；
    // 修复前合成只剩 rotationY(π)，x 分量 -1 → 文字水平镜像
    final backMatrix = tester
        .renderObject<RenderBox>(find.text('我的回答'))
        .getTransformTo(null);
    expect(
      backMatrix.entry(0, 0),
      moreOrLessEquals(1.0),
      reason: '背面文字被 3D 翻转镜像（合成 x 分量为负）',
    );
    await drainAppTimers(tester);
  });

  testWidgets('右滑提交：markReviewed 落库并推进（与按钮等价）', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    final gesture = await dragSteps(
      tester,
      find.byKey(const Key('flip_card_fc-1')),
      const Offset(600, 0),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final reviewed = await db.flashcardsDao.getById('fc-1');
    expect(reviewed!.reviewCount, 1);
    expect(find.byKey(const Key('flip_card_fc-2')), findsOneWidget);
    await drainAppTimers(tester);
  });

  testWidgets('左滑跳过：不计复习直接推进', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    final gesture = await dragSteps(
      tester,
      find.byKey(const Key('flip_card_fc-1')),
      const Offset(-600, 0),
    );
    await gesture.up();
    await tester.pumpAndSettle();

    final card = await db.flashcardsDao.getById('fc-1');
    expect(card!.reviewCount, 0);
    expect(find.byKey(const Key('flip_card_fc-2')), findsOneWidget);
    await drainAppTimers(tester);
  });

  testWidgets('拖动中倾斜与速度形变，未过阈值松手回弹', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    // 慢速小步拖动：位移/速度都不过阈值
    final gesture = await dragSteps(
      tester,
      find.byKey(const Key('flip_card_fc-1')),
      const Offset(120, 0),
      stepInterval: const Duration(milliseconds: 100),
    );

    final matrix = tester
        .renderObject<RenderBox>(find.text('请介绍你最有挑战的项目'))
        .getTransformTo(null);
    expect(matrix.entry(0, 1).abs(), greaterThan(0.005),
        reason: '拖动中应有 rotateZ 倾斜（跟随指尖）');
    expect(matrix.entry(1, 1), lessThan(0.999),
        reason: '拖动中应有垂直轴压缩（速度形变）');

    await gesture.up();
    await tester.pumpAndSettle();

    // 回弹归位：静止恒等矩阵，未推进
    final settled = tester
        .renderObject<RenderBox>(find.text('请介绍你最有挑战的项目'))
        .getTransformTo(null);
    expect(settled.entry(0, 1), moreOrLessEquals(0.0));
    expect(settled.entry(1, 1), moreOrLessEquals(1.0));
    expect(find.byKey(const Key('flip_card_fc-1')), findsOneWidget);
    expect((await db.flashcardsDao.getById('fc-1'))!.reviewCount, 0);
    await drainAppTimers(tester);
  });

  testWidgets('背后下一张预览：视差下沉 6px 露出底边', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    // 直读背后 Transform 的矩阵（getTransformTo(null) 会混入布局绝对坐标）
    final behindTransform = tester.widget<Transform>(
      find.ancestor(
        of: find.text('说说你对状态管理的理解'),
        matching: find.byType(Transform),
      ).first,
    ).transform;
    expect(behindTransform.entry(1, 3), moreOrLessEquals(6.0),
        reason: '静止时背后卡下沉 6px（卡片堆隐喻）');
    await drainAppTimers(tester);
  });

  testWidgets('减弱动态效果：拖动无形变，提交直达终态', (tester) async {
    final cards = await seedCards();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(disableAnimations: true),
            child: FlashcardFlipPage(cards: cards),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => drainAppTimers(tester));

    final gesture = await dragSteps(
      tester,
      find.byKey(const Key('flip_card_fc-1')),
      const Offset(600, 0),
    );

    // 拖动中无视觉形变（功能性输入保留，装饰运动移除）
    final matrix = tester
        .renderObject<RenderBox>(find.text('请介绍你最有挑战的项目'))
        .getTransformTo(null);
    expect(matrix.entry(0, 1), moreOrLessEquals(0.0));

    // 松手即提交：无飞出动画
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('flip_card_fc-2')), findsOneWidget);
    expect((await db.flashcardsDao.getById('fc-1'))!.reviewCount, 1);
    await drainAppTimers(tester);
  });

  testWidgets('Quizlet 式卡面：判定章随拖动浮现，翻面金底面板灯泡，完成页奖牌', (tester) async {
    final cards = await seedCards();
    await pumpFlip(tester, cards);

    // 右滑中段：「已掌握」判定章浮现（120px 未过阈值）
    final rightGesture = await dragSteps(
      tester,
      find.byKey(const Key('flip_card_fc-1')),
      const Offset(120, 0),
      stepInterval: const Duration(milliseconds: 100),
    );
    expect(find.text('已掌握'), findsOneWidget);
    await rightGesture.up();
    await tester.pumpAndSettle();
    // 未过阈值回弹 → 章消失
    expect(find.text('已掌握'), findsNothing);

    // 左滑中段：「再看看」
    final leftGesture = await dragSteps(
      tester,
      find.byKey(const Key('flip_card_fc-1')),
      const Offset(-120, 0),
      stepInterval: const Duration(milliseconds: 100),
    );
    expect(find.text('再看看'), findsOneWidget);
    await leftGesture.up();
    await tester.pumpAndSettle();

    // 翻面：AI 参考思路金底面板，灯泡插画
    await tester.tap(find.byKey(const Key('flip_card_fc-1')));
    await tester.pumpAndSettle();
    expect(find.text('AI 参考思路'), findsOneWidget);
    expect(find.byType(CardIllustration), findsOneWidget);

    await tester.tap(find.byKey(const Key('btn_reviewed_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('btn_reviewed_next')));
    await tester.pumpAndSettle();
    // 完成页：奖牌插画
    expect(find.byKey(const Key('flip_finish')), findsOneWidget);
    expect(find.byType(CardIllustration), findsOneWidget);
    await drainAppTimers(tester);
  });
}
