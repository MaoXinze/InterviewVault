import 'dart:async';

import 'package:drift/drift.dart' show Value;

import '../../data/database/app_database.dart';
import '../interviews/annotation_tags.dart';
import '../../network/llm_client.dart';

/// 卡片来源缺失（标注未关联到存在的分段）。
class FlashcardSourceException implements Exception {
  const FlashcardSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// AI 参考生成事件（卡片详情页流式渲染）。
sealed class CardAiEvent {
  const CardAiEvent();
}

class CardAiDelta extends CardAiEvent {
  const CardAiDelta(this.text);

  final String text;
}

class CardAiDone extends CardAiEvent {
  const CardAiDone(this.full);

  final String full;
}

class CardAiError extends CardAiEvent {
  const CardAiError(this.message);

  final String message;
}

/// 问题卡片服务（PRD 2.7）：
/// - 从标注生成卡片：正面 = 问题段文本，背面 = 后续我的回答（转写片段）
/// - 标签与标注体系打通（存展示名，回顾页筛选用 Tag.name）
/// - AI 参考答案思路：流式生成，中断保留部分内容
class FlashcardService {
  FlashcardService({
    required this.db,
    required this._chatClientFactory,
  });
  final AppDatabase db;

  /// Key 不经此服务：LlmClient 由 AiConfigService.activeChatClient 组装，
  /// 测试注入桩工厂。
  final Future<LlmClient?> Function() _chatClientFactory;

  /// 从标注生成（或更新）问题卡片。
  ///
  /// 幂等：同面试 + 同来源段起点 + 同问题的卡片已存在时更新而非新增，
  /// ai_reference 保留（重生成回答不会丢用户已生成的参考）。
  Future<Flashcard> createOrUpdateFromAnnotation(Annotation annotation) async {
    final interviewId = annotation.interviewId;
    final segments = await db.segmentsDao.getByInterview(interviewId);
    final source = annotation.segmentId == null
        ? null
        : await db.segmentsDao.getById(annotation.segmentId!);
    if (source == null) {
      throw const FlashcardSourceException('标注未关联到有效分段，无法生成卡片');
    }

    final annotations = await db.annotationsDao.getByInterview(interviewId);
    final questionSegmentIds = {
      for (final a in annotations)
        if (a.tag == 'question') a.segmentId,
    };

    // 我的回答：问题段之后的连续分段，遇到面试官标记段或下一个问题段即停
    final answerParts = <String>[];
    var end = source.endTime;
    var past = false;
    for (final segment in segments) {
      if (!past) {
        if (segment.id == source.id) past = true;
        continue;
      }
      if (segment.speaker == 'interviewer' ||
          questionSegmentIds.contains(segment.id)) {
        break;
      }
      answerParts.add(segment.content);
      end = segment.endTime;
    }
    final myAnswer = answerParts.isEmpty ? null : answerParts.join('\n');

    // 卡片标签 = 来源段上的全部标注（展示名，与回顾页筛选打通）
    final tags = {
      for (final a in annotations)
        if (a.segmentId == annotation.segmentId) annotationLabel(a),
    }.toList();

    final existing = await _findSameSource(interviewId, source);
    if (existing != null) {
      await db.flashcardsDao.updateOne(
        existing.id,
        FlashcardsCompanion(
          myAnswer: Value(myAnswer),
          tags: Value(encodeCardTags(tags)),
          sourceEndTime: Value(end),
        ),
      );
      return (await db.flashcardsDao.getById(existing.id))!;
    }

    final id = 'fc-${DateTime.now().microsecondsSinceEpoch}';
    await db.flashcardsDao.insertOne(
      FlashcardsCompanion.insert(
        id: id,
        interviewId: interviewId,
        question: source.content,
        myAnswer: Value(myAnswer),
        tags: Value(encodeCardTags(tags)),
        sourceStartTime: Value(source.startTime),
        sourceEndTime: Value(end),
      ),
    );
    return (await db.flashcardsDao.getById(id))!;
  }

  Future<Flashcard?> _findSameSource(
    String interviewId,
    TranscriptSegment source,
  ) async {
    final cards = await db.flashcardsDao.getByInterview(interviewId);
    for (final card in cards) {
      if (card.sourceStartTime == source.startTime &&
          card.question == source.content) {
        return card;
      }
    }
    return null;
  }

  /// AI 参考答案思路（流式）。持久化策略：
  /// - 正常完成：全文写入 ai_reference
  /// - 中途失败：已收到的部分写入（用户的时间不白费），产出 error 事件
  /// - 模型零输出：不覆盖已有内容
  Stream<CardAiEvent> generateAiReference(Flashcard card) async* {
    final client = await _chatClientFactory();
    if (client == null) {
      yield const CardAiError('未配置 AI 服务商，请到「我的 → AI 配置」填写 API Key');
      return;
    }

    final buffer = StringBuffer();
    try {
      await for (final delta in client.chatCompletionStream(
        messages: _buildMessages(card),
      )) {
        buffer.write(delta);
        yield CardAiDelta(delta);
      }
    } on Exception catch (e) {
      if (buffer.isNotEmpty) {
        await db.flashcardsDao.updateOne(
          card.id,
          FlashcardsCompanion(aiReference: Value(buffer.toString())),
        );
      }
      yield CardAiError('生成中断，已保留部分内容：$e');
      return;
    }

    if (buffer.isEmpty) {
      yield const CardAiError('模型没有返回内容，请稍后重试');
      return;
    }
    await db.flashcardsDao.updateOne(
      card.id,
      FlashcardsCompanion(aiReference: Value(buffer.toString())),
    );
    yield CardAiDone(buffer.toString());
  }

  List<Map<String, String>> _buildMessages(Flashcard card) => [
        const {
          'role': 'system',
          'content': '你是面试复盘教练，像带过很多届校招的学长，正在给学弟当面讲这道题。'
              '用中文输出，分四节：【考察点】【答题框架】【关键要点】【加分示范】。'
              '要求：'
              '1. 只讲重点：先给结论，再讲为什么，别绕弯；'
              '2. 说人话：短句、口语、有画面感，像当面讲解；'
              '禁止"综上所述""首先其次最后""值得注意的是"这类 AI 腔和空洞套话；'
              '3. 结合对方的回答讲：答到位就点名肯定一句，答偏了指出偏在哪、怎么拉回来；'
              '4. 【加分示范】给一句能直接背的示范话术。'
              '合计 300-500 字，不要寒暄，不要重复问题。',
        },
        {
          'role': 'user',
          'content': '面试问题：${card.question}\n'
              '我的回答：${card.myAnswer ?? '（未作答）'}',
        },
      ];
}

/// 卡片背面的标注：来源时间范围内所有分段上的标注
/// （卡片表无 segment_id，按时间范围关联——PRD 3.3 schema v1 约束）
///
/// 半开区间判定：转写分段首尾零间隙衔接，起于 sourceEnd 的下一段
/// 不属于本卡（epsilon 容忍浮点误差）。
List<Annotation> annotationsForCard(
  Flashcard card,
  List<TranscriptSegment> segments,
  List<Annotation> annotations,
) {
  final start = card.sourceStartTime;
  final end = card.sourceEndTime;
  if (start == null || end == null) return const [];
  const epsilon = 0.001;
  final segmentIds = {
    for (final s in segments)
      if (s.endTime > start + epsilon && s.startTime < end - epsilon) s.id,
  };
  return [
    for (final a in annotations)
      if (a.segmentId != null && segmentIds.contains(a.segmentId)) a,
  ];
}
