import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../data/database/app_database.dart';
import '../../data/database/tables.dart' show nowIso;
import '../../network/llm_client.dart';

/// AI 返回内容不可用（未配置 / 格式解析失败 / 空结果）。
class MockAiException implements Exception {
  const MockAiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 模拟面试会话里的一题（P0 文字作答；语音 P1）。
class MockQa {
  const MockQa({required this.question, this.answer, this.feedback});

  final String question;

  /// 用户文字作答；跳过为 null
  final String? answer;

  /// AI 逐题反馈全文（含【优点】【不足】【改进建议】）
  final String? feedback;
}

/// 出题完成后的会话计划（配置页 → 会话页的 go_router extra）。
class MockSessionPlan {
  const MockSessionPlan({
    required this.position,
    required this.resume,
    required this.jd,
    required this.questions,
  });

  final String position;
  final String resume;
  final String jd;
  final List<String> questions;
}

/// 逐题反馈事件（卡片 AI 参考同款三分法：增量 / 完成 / 出错）。
sealed class MockFeedbackEvent {
  const MockFeedbackEvent();
}

class MockFeedbackDelta extends MockFeedbackEvent {
  const MockFeedbackDelta(this.text);

  final String text;
}

class MockFeedbackDone extends MockFeedbackEvent {
  const MockFeedbackDone(this.full);

  final String full;
}

class MockFeedbackError extends MockFeedbackEvent {
  const MockFeedbackError(this.message);

  final String message;
}

/// 模拟面试全流程（PRD 2.9 P0 基础版 / PLAN W3-M3）：
/// - 岗位 + 简历 + JD → AI 出题 5 道
/// - 文字作答 → AI 逐题流式反馈（优点/不足/改进建议）
/// - 会话落库：interview + Q/A 分段 + 问题卡片（与真实面试统一管理），
///   卡片背面 = 我的回答 + AI 反馈（ai_reference），来源锚回 Q/A 分段
class MockInterviewService {
  MockInterviewService({
    required this.db,
    required this._chatClientFactory,
  });

  final AppDatabase db;

  /// Key 不经此服务：LlmClient 由 AiConfigService.activeChatClient 组装，
  /// 测试注入桩工厂。
  final Future<LlmClient?> Function() _chatClientFactory;

  /// AI 出题：基于岗位/简历/JD 生成至多 5 道。
  ///
  /// 只要求 JSON 数组输出；容忍模型把数组包进代码围栏或说明文字里。
  Future<List<String>> generateQuestions({
    required String position,
    String resume = '',
    String jd = '',
  }) async {
    final client = await _chatClientFactory();
    if (client == null) {
      throw const MockAiException('未配置 AI 服务商，请先到「我的 → AI 配置」填写 API Key');
    }
    final buffer = StringBuffer();
    try {
      await for (final delta in client.chatCompletionStream(
        messages: [
          const {
            'role': 'system',
            'content': '你是资深的面试官，正在面试一位候选人。'
                '只输出一个 JSON 字符串数组：每项是一道中文面试题，共 5 道，'
                '贴合候选人的岗位方向、简历与 JD，由浅入深。'
                '题目要问得具体：围绕简历项目的细节和 JD 的关键要求追问，'
                '像真人面试官一样自然口语地提问，别出模板化的题面。'
                '不要输出数组以外的任何内容。',
          },
          {
            'role': 'user',
            'content': _contextLines(position: position, resume: resume, jd: jd),
          },
        ],
      )) {
        buffer.write(delta);
      }
    } on Exception catch (e) {
      throw MockAiException('出题失败：$e');
    }
    return _parseQuestions(buffer.toString());
  }

  List<String> _parseQuestions(String raw) {
    final start = raw.indexOf('[');
    final end = raw.lastIndexOf(']');
    if (start < 0 || end <= start) {
      throw const MockAiException('AI 返回格式无法解析，请重试');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw.substring(start, end + 1));
    } on FormatException {
      throw const MockAiException('AI 返回格式无法解析，请重试');
    }
    if (decoded is! List) {
      throw const MockAiException('AI 返回格式无法解析，请重试');
    }
    final questions = [
      for (final q in decoded)
        if (q.toString().trim().isNotEmpty) q.toString().trim(),
    ];
    if (questions.isEmpty) {
      throw const MockAiException('AI 没有给出题目，请重试');
    }
    return questions.take(5).toList();
  }

  /// AI 逐题反馈（流式）。持久化由会话页收尾统一处理：
  /// 中断时页面已渲染的部分内容随会话一起落库（用户的时间不白费）。
  Stream<MockFeedbackEvent> generateFeedback({
    required String question,
    required String answer,
    String position = '',
    String resume = '',
  }) async* {
    final client = await _chatClientFactory();
    if (client == null) {
      yield const MockFeedbackError('未配置 AI 服务商，请先到「我的 → AI 配置」填写 API Key');
      return;
    }
    final buffer = StringBuffer();
    try {
      await for (final delta in client.chatCompletionStream(
        messages: [
          const {
            'role': 'system',
            'content': '你是面试复盘教练，像带过很多场面试的学长在给学弟逐题复盘。'
                '用中文输出，分三节：【优点】【不足】【改进建议】。'
                '要求：'
                '1. 每节都扣住回答原话：优点说清好在哪；不足要点名哪句话站不住、'
                '面试官大概率会怎么追问；'
                '2. 【改进建议】要能直接照做：先给方向，再给一句改写后的示范话术；'
                '3. 说人话：短句、口语、直给，'
                '禁止"综上所述""首先其次""值得注意的是"这类 AI 腔和空洞套话；'
                '4. 合计 300-500 字，不要寒暄，不要复述问题。',
          },
          {
            'role': 'user',
            'content': '${_contextLines(position: position, resume: resume)}'
                '面试题：$question\n'
                '我的回答：${answer.trim().isEmpty ? '（未作答）' : answer.trim()}',
          },
        ],
      )) {
        buffer.write(delta);
        yield MockFeedbackDelta(delta);
      }
    } on Exception catch (e) {
      yield MockFeedbackError('生成中断，已保留部分内容：$e');
      return;
    }
    if (buffer.isEmpty) {
      yield const MockFeedbackError('模型没有返回内容，请稍后重试');
      return;
    }
    yield MockFeedbackDone(buffer.toString());
  }

  String _contextLines({
    required String position,
    String resume = '',
    String jd = '',
  }) {
    return [
      '岗位方向：${position.trim()}',
      if (resume.trim().isNotEmpty) '候选人简历：\n${resume.trim()}',
      if (jd.trim().isNotEmpty) '职位 JD：\n${jd.trim()}',
    ].join('\n');
  }

  /// 会话落库：一场模拟面试 = 一条 interview（status=transcribed，无音频）
  /// + 每题一对分段（面试官问 / 我答）+ 每题一张卡片。
  /// 卡片来源时间锚回 Q/A 分段，之后的手动标注照常挂上卡片。
  Future<String> persistSession({
    required String position,
    required List<MockQa> qas,
  }) async {
    final base = DateTime.now().microsecondsSinceEpoch;
    final interviewId = 'iv-mock-$base';
    await db.transaction(() async {
      await db.interviewsDao.insertOne(
        InterviewsCompanion.insert(
          id: interviewId,
          position: Value(position.trim()),
          interviewDate: Value(nowIso()),
          status: const Value('transcribed'),
        ),
      );
      for (final (i, qa) in qas.indexed) {
        final qStart = i * 2.0;
        final qEnd = i * 2.0 + 1.0;
        final answer = qa.answer?.trim();
        final hasAnswer = answer != null && answer.isNotEmpty;
        final aEnd = i * 2.0 + 2.0;
        await db.segmentsDao.insertOne(
          TranscriptSegmentsCompanion.insert(
            id: 'seg-$base-q$i',
            interviewId: interviewId,
            startTime: qStart,
            endTime: qEnd,
            content: qa.question.trim(),
            speaker: const Value('interviewer'),
          ),
        );
        if (hasAnswer) {
          await db.segmentsDao.insertOne(
            TranscriptSegmentsCompanion.insert(
              id: 'seg-$base-a$i',
              interviewId: interviewId,
              startTime: qEnd,
              endTime: aEnd,
              content: answer,
              speaker: const Value('candidate'),
            ),
          );
        }
        final feedback = qa.feedback?.trim();
        await db.flashcardsDao.insertOne(
          FlashcardsCompanion.insert(
            id: 'fc-$base-$i',
            interviewId: interviewId,
            question: qa.question.trim(),
            myAnswer: Value(hasAnswer ? answer : null),
            aiReference: Value(
                feedback == null || feedback.isEmpty ? null : feedback),
            tags: const Value('["问题"]'),
            sourceStartTime: Value(qStart),
            sourceEndTime: Value(hasAnswer ? aEnd : qEnd),
          ),
        );
      }
    });
    return interviewId;
  }
}

/// 简历 PDF 文字提取（执行修订 #6：纯 Dart 方案，无 GMS 依赖）。
///
/// 加密/损坏/图片扫描件都提取不出可用文字，统一抛 FormatException，
/// 文案直接引导用户改用粘贴文字（P0 不做 OCR）。
String extractResumeText(String path) {
  final PdfDocument doc;
  try {
    doc = PdfDocument(inputBytes: File(path).readAsBytesSync());
  } catch (_) {
    throw const FormatException('无法读取该 PDF（可能已加密），请改用粘贴文字');
  }
  try {
    final text = PdfTextExtractor(doc).extractText();
    if (text.trim().isEmpty) {
      throw const FormatException('该 PDF 提取不到文字（可能是图片扫描件），请改用粘贴文字');
    }
    return text;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException('PDF 文字提取失败，请改用粘贴文字');
  } finally {
    doc.dispose();
  }
}
