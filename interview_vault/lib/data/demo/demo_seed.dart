import 'dart:convert' show jsonEncode;

import 'package:drift/drift.dart' show Value;

import '../database/app_database.dart';

/// 演示数据（--dart-define=DEMO_SEED=true 构建时启用）。
/// 真实感内容用于走查：逐字稿/标注/卡片/总结页/按日汇总/导出。
/// 仅当面试表为空时填充；正式构建不含此调用路径。
Future<bool> seedDemoDataIfEmpty(AppDatabase db) async {
  if ((await db.interviewsDao.getAll()).isNotEmpty) return false;

  // ── 场次 1：字节跳动二面（已标注，无音频） ──────────────────────────
  await db.interviewsDao.insertOne(
    InterviewsCompanion.insert(
      id: 'iv-demo-bytedance',
      company: const Value('字节跳动'),
      position: const Value('后端工程师'),
      round: const Value('二面'),
      interviewDate: const Value('2026-09-25T14:00:00.000'),
      durationSeconds: const Value(1925),
      status: const Value('annotated'),
    ),
  );
  await _segments(db, 'iv-demo-bytedance', [
    _Seg('s1', 0, 12, '先简单自我介绍一下吧，重点讲讲你最近一年做的项目。',
        'interviewer'),
    _Seg(
        's2',
        12,
        95,
        '好的。我最近一年主要负责电商订单系统的重构，把单体拆成微服务，'
            'QPS 从 800 提到 3000，故障恢复时间从分钟级降到秒级。'
            '我在里面负责订单核心链路的设计和落地。',
        'candidate'),
    _Seg('s3', 95, 108, '订单系统拆分的时候，怎么保证分布式事务的一致性？',
        'interviewer'),
    _Seg(
        's4',
        108,
        210,
        '我们用的是本地消息表加事务消息的方案。订单库先落本地消息表，'
            '同一个事务里提交，然后由投递任务发到 MQ，消费端做幂等。'
            '超时未确认的消息走补偿扫描。当时踩过的坑是补偿任务和正常投递'
            '并发导致重复下单，后来加了状态机约束才解决。',
        'candidate'),
    _Seg('s5', 210, 222, '如果要你现场设计一个短链接服务，你会怎么做？',
        'interviewer'),
    _Seg(
        's6',
        222,
        330,
        '（略作思考）发号器用号段模式预分配，301 重定向，缓存前移扛读流量，'
            '布隆过滤器防穿透……不过高并发下的发号器单点问题我当时答得'
            '不够完整。',
        'candidate'),
    _Seg('s7', 330, 342, '好，那今天先聊到这里，你有什么想问我的吗？',
        'interviewer'),
    _Seg('s8', 342, 360, '想请教团队目前订单系统的日均量级和明年技术演进的方向。',
        'candidate'),
  ]);
  await _annotations(db, 'iv-demo-bytedance', [
    _Ann('a1', 's1', 'question'),
    _Ann('a2', 's2', 'answer'),
    _Ann('a3', 's2', 'custom', customTagName: '心态平稳'),
    _Ann('a4', 's3', 'question'),
    _Ann(
        'a5', 's4', 'highlight', note: '结合踩坑经历讲分布式事务，比背概念有说服力'),
    _Ann('a6', 's6', 'mistake',
        note: '短链接发号器单点问题没答完整，需要补一致性哈希与集群方案'),
    _Ann('a7', 's6', 'improvement', note: '回答前先要清边界：读多写少还是写多？再定方案'),
  ]);
  await _cards(db, 'iv-demo-bytedance', [
    _Card(
      'c1',
      question: '订单系统拆分的时候，怎么保证分布式事务的一致性？',
      myAnswer:
          '我们用的是本地消息表加事务消息的方案。订单库先落本地消息表，'
              '同一个事务里提交，然后由投递任务发到 MQ，消费端做幂等。'
              '超时未确认的消息走补偿扫描。当时踩过的坑是补偿任务和正常投递'
              '并发导致重复下单，后来加了状态机约束才解决。',
      aiReference: '参考思路：\n'
          '1. 本地消息表 + 事务消息：同库事务落消息，投递任务异步发 MQ；\n'
          '2. 消费端幂等（唯一键 / 状态机）兜底重复；\n'
          '3. 补偿扫描处理超时消息，配合对账任务兜底。\n'
          '加分项：说清楚选型对比（TCC / SAGA 的成本）与踩坑。',
      tags: ['问题', '亮点', '回答'],
      start: 95,
      end: 210,
    ),
    _Card(
      'c2',
      question: '如果要你现场设计一个短链接服务，你会怎么做？',
      myAnswer:
          '发号器用号段模式预分配，301 重定向，缓存前移扛读流量，'
              '布隆过滤器防穿透……不过高并发下的发号器单点问题我当时答得'
              '不够完整。',
      aiReference: '参考思路：\n'
          '1. 发号：号段 / 雪花，分布式发号要考虑集群与容灾；\n'
          '2. 存储：KV + 缓存前移，热点链接预热；\n'
          '3. 跳转：301 / 302 的取舍（浏览器缓存 vs 统计）；\n'
          '4. 防护：布隆过滤器 + 限流。',
      tags: ['问题', '失误', '待改进'],
      start: 210,
      end: 330,
    ),
  ]);

  // ── 场次 2：美团一面（已转写，未标注） ────────────────────────────
  await db.interviewsDao.insertOne(
    InterviewsCompanion.insert(
      id: 'iv-demo-meituan',
      company: const Value('美团'),
      position: const Value('客户端工程师'),
      round: const Value('一面'),
      interviewDate: const Value('2026-09-26T10:00:00.000'),
      durationSeconds: const Value(2712),
      status: const Value('transcribed'),
    ),
  );
  await _segments(db, 'iv-demo-meituan', [
    _Seg('s1', 0, 15, '介绍一下你做过的最有挑战的项目。', 'interviewer'),
    _Seg('s2', 15, 120, '直播秒杀的链路改造：前端预热 + 网关限流 + 库存预扣。',
        'candidate'),
    _Seg('s3', 120, 135, '客户端这边，秒杀按钮的防重复点击你是怎么处理的？',
        'interviewer'),
    _Seg('s4', 135, 240,
        '按钮置灰加请求去重 token，失败后允许重试，本地先渲染乐观状态。',
        'candidate'),
  ]);
  await _annotations(db, 'iv-demo-meituan', [
    _Ann('a1', 's1', 'question'),
    _Ann('a2', 's2', 'answer'),
    _Ann('a3', 's3', 'question'),
  ]);

  // ── 场次 3：模拟面试（无音频，AI 逐题反馈） ───────────────────────
  await db.interviewsDao.insertOne(
    InterviewsCompanion.insert(
      id: 'iv-demo-mock',
      company: const Value('模拟面试'),
      position: const Value('Go 后端工程师'),
      interviewDate: const Value('2026-09-27T09:30:00.000'),
      durationSeconds: const Value(190),
      status: const Value('transcribed'),
    ),
  );
  await _segments(db, 'iv-demo-mock', [
    _Seg('s1', 0, 8, '请介绍一下你对 Go 协程调度模型 GMP 的理解。', 'interviewer'),
    _Seg('s2', 8, 60,
        'GMP：G 是协程，M 是内核线程，P 是调度上下文，本地队列 + 全局队列 + work stealing。',
        'candidate'),
    _Seg('s3', 60, 70, 'channel 关闭后读和写分别会发生什么？', 'interviewer'),
    _Seg('s4', 70, 120, '关闭后读返回零值和 false（第二个返回值），写会 panic。',
        'candidate'),
    _Seg('s5', 120, 130, '最后一题：如何用 channel 实现一个带超时的控制并发？',
        'interviewer'),
    _Seg('s6', 130, 190, 'select 加 time.After，配合带缓冲 channel 做信号量。',
        'candidate'),
  ]);
  await _annotations(db, 'iv-demo-mock', [
    _Ann('a1', 's1', 'question'),
    _Ann('a2', 's3', 'question'),
    _Ann('a3', 's5', 'question'),
  ]);
  await _cards(db, 'iv-demo-mock', [
    _Card(
      'c1',
      question: '请介绍一下你对 Go 协程调度模型 GMP 的理解。',
      myAnswer:
          'GMP：G 是协程，M 是内核线程，P 是调度上下文，本地队列 + 全局队列 + work stealing。',
      aiReference: '【优点】\n'
          '- 结构清晰，G / M / P 职责说得准，提到了 work stealing。\n'
          '【不足】\n'
          '- 没提 P 的数量默认等于 CPU 核数，以及 GOMAXPROCS 的作用。\n'
          '【改进建议】\n'
          '- 补充 netpoller 场景下阻塞 G 的处理，举一个系统调用阻塞的例子。',
      tags: ['问题'],
      start: 0,
      end: 60,
    ),
    _Card(
      'c2',
      question: 'channel 关闭后读和写分别会发生什么？',
      myAnswer: '关闭后读返回零值和 false（第二个返回值），写会 panic。',
      aiReference: '【优点】\n'
          '- 结论正确：读零值 + false，写 panic。\n'
          '【不足】\n'
          '- 没提 range 读取与 v, ok 的等价写法。\n'
          '【改进建议】\n'
          '- 顺手给出"向 nil channel 读写都会阻塞"的对比，展示体系化理解。',
      tags: ['问题'],
      start: 60,
      end: 120,
    ),
    _Card(
      'c3',
      question: '如何用 channel 实现一个带超时的控制并发？',
      myAnswer: 'select 加 time.After，配合带缓冲 channel 做信号量。',
      aiReference: '【优点】\n'
          '- select + time.After 是标准答案方向，缓冲 channel 信号量也对。\n'
          '【不足】\n'
          '- time.After 在循环里会泄漏 timer（Go 1.23 前）。\n'
          '【改进建议】\n'
          '- 用 time.NewTimer + Reset，或 context.WithTimeout 收口。',
      tags: ['问题'],
      start: 120,
      end: 190,
    ),
  ]);

  return true;
}

class _Seg {
  const _Seg(this.id, this.start, this.end, this.content, this.speaker);
  final String id;
  final double start;
  final double end;
  final String content;
  final String speaker;
}

Future<void> _segments(
  AppDatabase db,
  String interviewId,
  List<_Seg> segments,
) async {
  for (final s in segments) {
    await db.segmentsDao.insertOne(
      TranscriptSegmentsCompanion.insert(
        id: '$interviewId-${s.id}',
        interviewId: interviewId,
        startTime: s.start,
        endTime: s.end,
        content: s.content,
        speaker: Value(s.speaker),
      ),
    );
  }
}

class _Ann {
  const _Ann(
    this.id,
    this.segmentId,
    this.tag, {
    this.customTagName,
    this.note,
  });
  final String id;
  final String segmentId;
  final String tag;
  final String? customTagName;
  final String? note;
}

Future<void> _annotations(
  AppDatabase db,
  String interviewId,
  List<_Ann> annotations,
) async {
  var order = 0;
  for (final a in annotations) {
    order++;
    await db.annotationsDao.insertOne(
      AnnotationsCompanion.insert(
        id: '$interviewId-${a.id}',
        interviewId: interviewId,
        tag: a.tag,
        segmentId: Value('$interviewId-${a.segmentId}'),
        customTagName: Value(a.customTagName),
        note: Value(a.note),
        createdAt: Value('2026-09-27T10:00:${order.toString().padLeft(2, '0')}'),
      ),
    );
  }
}

class _Card {
  const _Card(
    this.id, {
    required this.question,
    required this.myAnswer,
    required this.aiReference,
    required this.tags,
    required this.start,
    required this.end,
  });
  final String id;
  final String question;
  final String myAnswer;
  final String? aiReference;
  final List<String> tags;
  final double start;
  final double end;
}

Future<void> _cards(
  AppDatabase db,
  String interviewId,
  List<_Card> cards,
) async {
  var order = 0;
  for (final c in cards) {
    order++;
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: '$interviewId-${c.id}',
        interviewId: interviewId,
        question: c.question,
        myAnswer: Value(c.myAnswer),
        aiReference: Value(c.aiReference),
        tags: Value(jsonEncode(c.tags)),
        sourceStartTime: Value(c.start),
        sourceEndTime: Value(c.end),
        createdAt: Value('2026-09-27T11:00:${order.toString().padLeft(2, '0')}'),
      ),
    );
  }
}
