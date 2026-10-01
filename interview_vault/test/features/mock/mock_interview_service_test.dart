import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/data/database/app_database.dart';
import 'package:interview_vault/features/mock/mock_interview_service.dart';
import 'package:interview_vault/network/llm_client.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// 与 flashcard_service_test 相同的打桩方式：拦截 dio 请求，返回可编程响应体。
class _CapturingAdapter implements HttpClientAdapter {
  _CapturingAdapter(this.responder);

  final ResponseBody Function(RequestOptions options) responder;
  final List<RequestOptions> requests = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return responder(options);
  }
}

/// SSE 流式响应：逐 chunk 下发 data 行（jsonEncode 转义，容忍含引号的内容）
ResponseBody _sseChunks(List<List<String>> chunks) {
  final stream = Stream<List<String>>.fromIterable(chunks)
      .map((deltas) => utf8.encode(deltas.map((d) {
            final payload = jsonEncode({
              'choices': [
                {'delta': {'content': d}}
              ],
            });
            return 'data: $payload\n\n';
          }).join())).cast<Uint8List>();
  return ResponseBody(stream, 200);
}

LlmClient _client(ResponseBody Function(RequestOptions) responder) {
  final adapter = _CapturingAdapter(responder);
  return LlmClient(
    endpoint: const AiEndpoint(
      providerId: 'openai',
      baseUrl: 'https://api.test.com',
      modelName: 'test-model',
    ),
    apiKey: 'sk-test',
    dio: Dio()..httpClientAdapter = adapter,
  );
}

void main() {
  late AppDatabase db;
  late MockInterviewService service;
  Future<LlmClient?>? nextChatClient;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    nextChatClient = null;
    service = MockInterviewService(
      db: db,
      chatClientFactory: () async => nextChatClient,
    );
  });
  tearDown(() => db.close());

  group('AI 出题', () {
    test('解析 JSON 数组（容忍围栏与前后文本），截取前 5 道', () async {
      nextChatClient = Future.value(_client((options) => _sseChunks([
            ['```json\n["第一题：介绍项目经历", "第二题：',
              '谈谈状态管理", "第三题", "第四题", "第五题", "第六题"]\n```'],
          ])));

      final questions = await service.generateQuestions(
        position: '客户端工程师',
        resume: '三年 Flutter 经验',
        jd: '负责 App 架构演进',
      );

      expect(questions, hasLength(5));
      expect(questions.first, '第一题：介绍项目经历');
      expect(questions[1], '第二题：谈谈状态管理');
      expect(questions.any((q) => q.contains('第六题')), isFalse);
      final body = (await _capturedBody(nextChatClient!))!;
      expect(body, contains('岗位方向：客户端工程师'));
      expect(body, contains('三年 Flutter 经验'));
      expect(body, contains('负责 App 架构演进'));
    });

    test('简历与 JD 为空时提示词只含岗位方向', () async {
      nextChatClient = Future.value(_client((options) => _sseChunks([
            ['["题目一"]'],
          ])));

      final questions =
          await service.generateQuestions(position: '产品经理');

      expect(questions, ['题目一']);
      final body = (await _capturedBody(nextChatClient!))!;
      expect(body, contains('岗位方向：产品经理'));
      expect(body.contains('简历'), isFalse);
      expect(body.contains('JD'), isFalse);
    });

    test('未配置 AI 时抛 MockAiException 并带引导文案', () async {
      nextChatClient = Future.value(null);

      await expectLater(
        service.generateQuestions(position: '客户端工程师'),
        throwsA(isA<MockAiException>().having(
          (e) => e.message,
          'message',
          contains('未配置 AI 服务商'),
        )),
      );
    });

    test('输出不可解析为 JSON 数组时抛 MockAiException', () async {
      nextChatClient = Future.value(_client((options) => _sseChunks([
            ['抱歉，我无法出题'],
          ])));

      await expectLater(
        service.generateQuestions(position: '客户端工程师'),
        throwsA(isA<MockAiException>()),
      );
    });

    test('空数组视为失败', () async {
      nextChatClient = Future.value(_client((options) => _sseChunks([
            ['[]'],
          ])));

      await expectLater(
        service.generateQuestions(position: '客户端工程师'),
        throwsA(isA<MockAiException>()),
      );
    });
  });

  group('逐题反馈（流式）', () {
    test('增量事件按序产出，Done 带全文', () async {
      nextChatClient = Future.value(_client((options) => _sseChunks([
            ['【优点】', '表达清晰'],
            ['【不足】缺少量化'],
          ])));

      final events = await service
          .generateFeedback(question: '介绍项目', answer: '我做了一款 App')
          .toList();

      final deltas = events.whereType<MockFeedbackDelta>().toList();
      expect(deltas.map((e) => e.text).join(), '【优点】表达清晰【不足】缺少量化');
      final done = events.whereType<MockFeedbackDone>().single;
      expect(done.full, '【优点】表达清晰【不足】缺少量化');
      final body = (await _capturedBody(nextChatClient!))!;
      expect(body, contains('介绍项目'));
      expect(body, contains('我做了一款 App'));
    });

    test('未配置 AI 时产出 Error 事件（不抛异常）', () async {
      nextChatClient = Future.value(null);

      final events = await service
          .generateFeedback(question: '介绍项目', answer: '回答')
          .toList();

      expect(events.whereType<MockFeedbackError>().single.message,
          contains('未配置 AI 服务商'));
    });

    test('中途异常产出 Error 事件且文案提示已保留部分内容', () async {
      // 先发一个正常 chunk，再以网络错误中断（与 flashcard_service_test 同款）
      nextChatClient = Future.value(_client((options) {
        final controller = StreamController<Uint8List>()
          ..add(utf8.encode(
              'data: {"choices":[{"delta":{"content":"【优点】还行"}}]}\n\n'))
          ..addError(const SocketException('连接中断'))
          ..close();
        return ResponseBody(controller.stream, 200);
      }));

      final events = await service
          .generateFeedback(question: '介绍项目', answer: '回答')
          .toList();

      expect(
        events.whereType<MockFeedbackDelta>().map((e) => e.text).join(),
        '【优点】还行',
      );
      expect(events.last, isA<MockFeedbackError>());
      expect((events.last as MockFeedbackError).message, contains('已保留部分内容'));
    });

    test('模型零输出产出 Error 事件', () async {
      nextChatClient = Future.value(_client((options) => _sseChunks([
            [''],
          ])));

      final events = await service
          .generateFeedback(question: '介绍项目', answer: '回答')
          .toList();

      expect(
        events.whereType<MockFeedbackError>().single.message,
        contains('没有返回内容'),
      );
    });
  });

  group('会话落库（与真实面试统一管理）', () {
    Future<List<TranscriptSegment>> segmentsOf(String interviewId) =>
        db.segmentsDao.getByInterview(interviewId);

    test('5 题含作答与反馈：interview + Q/A 分段 + 5 张卡片', () async {
      final qas = List.generate(
        5,
        (i) => MockQa(
          question: '题目${i + 1}',
          answer: '我的回答${i + 1}',
          feedback: '【优点】反馈${i + 1}',
        ),
      );

      final interviewId = await service.persistSession(
        position: '客户端工程师',
        qas: qas,
      );

      final interview = (await db.interviewsDao.getById(interviewId))!;
      expect(interview.status, 'transcribed');
      expect(interview.position, '客户端工程师');
      expect(interview.audioFilePath, isNull);

      final segments = await segmentsOf(interviewId);
      expect(segments, hasLength(10));
      expect(segments.first.speaker, 'interviewer');
      expect(segments.first.content, '题目1');
      expect(segments[1].speaker, 'candidate');
      expect(segments[1].content, '我的回答1');
      // 时间轴顺序递增且 Q 在 A 前；相邻题首尾相接（模拟面试无真实音频）
      expect(segments.first.startTime, lessThan(segments[1].startTime));
      expect(segments[1].endTime, lessThanOrEqualTo(segments[2].startTime));

      final cards = await db.flashcardsDao.getByInterview(interviewId);
      expect(cards, hasLength(5));
      final first = cards.firstWhere((c) => c.question == '题目1');
      expect(first.myAnswer, '我的回答1');
      expect(first.aiReference, '【优点】反馈1');
      expect(first.tags, '["问题"]');
      // 来源范围覆盖问答两段（供后续手动标注挂到卡片）
      expect(first.sourceStartTime, segments.first.startTime);
      expect(first.sourceEndTime, segments[1].endTime);
    });

    test('跳过作答的题：无 candidate 段，卡片来源止于问题段', () async {
      final interviewId = await service.persistSession(
        position: '客户端工程师',
        qas: const [
          MockQa(question: '题目1'),
          MockQa(question: '题目2', answer: '回答2'),
        ],
      );

      final segments = await segmentsOf(interviewId);
      expect(segments, hasLength(3));
      expect(segments.map((s) => s.speaker).toList(),
          ['interviewer', 'interviewer', 'candidate']);

      final cards = await db.flashcardsDao.getByInterview(interviewId);
      final skipped = cards.firstWhere((c) => c.question == '题目1');
      expect(skipped.myAnswer, isNull);
      expect(skipped.aiReference, isNull);
      final questionSeg =
          segments.firstWhere((s) => s.content == '题目1');
      expect(skipped.sourceEndTime, questionSeg.endTime);
      final answered = cards.firstWhere((c) => c.question == '题目2');
      expect(answered.myAnswer, '回答2');
    });

    test('反馈为空白时不写入 aiReference', () async {
      final interviewId = await service.persistSession(
        position: '客户端工程师',
        qas: const [
          MockQa(question: '题目1', answer: '回答1', feedback: '   '),
        ],
      );

      final cards = await db.flashcardsDao.getByInterview(interviewId);
      expect(cards.single.aiReference, isNull);
      expect(cards.single.myAnswer, '回答1');
    });
  });

  group('简历 PDF 提取（执行修订 #6：纯 Dart 方案）', () {
    test('程序生成的文本 PDF 可提取原文', () async {
      final doc = PdfDocument();
      doc.pages.add().graphics.drawString(
            'Flutter client engineer, 3 years experience',
            PdfStandardFont(PdfFontFamily.helvetica, 12),
            brush: PdfBrushes.black,
          );
      final bytes = await doc.save();
      doc.dispose();

      final file =
          File('${Directory.systemTemp.path}/resume_test_${DateTime.now().microsecondsSinceEpoch}.pdf');
      file.writeAsBytesSync(bytes);
      addTearDown(file.delete);

      final text = extractResumeText(file.path);
      expect(text, contains('Flutter client engineer'));
    });

    test('损坏文件抛 FormatException 并引导粘贴文字', () {
      final file = File(
          '${Directory.systemTemp.path}/bad_${DateTime.now().microsecondsSinceEpoch}.pdf');
      file.writeAsBytesSync(const [1, 2, 3, 4]);
      addTearDown(file.delete);

      expect(
        () => extractResumeText(file.path),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('粘贴文字'),
        )),
      );
    });

    test('提取不到文字（图片扫描件）时引导粘贴文字', () async {
      final doc = PdfDocument();
      doc.pages.add();
      final bytes = await doc.save();
      doc.dispose();

      final file = File(
          '${Directory.systemTemp.path}/empty_${DateTime.now().microsecondsSinceEpoch}.pdf');
      file.writeAsBytesSync(bytes);
      addTearDown(file.delete);

      expect(
        () => extractResumeText(file.path),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('扫描件'),
        )),
      );
    });
  });

  group('提示词 v2（更详细、人话）', () {
    test('出题：要求贴合简历/JD 细节追问，口语自然', () async {
      nextChatClient = Future.value(_client((_) => _sseChunks([
            ['["一题"]'],
          ])));
      await service.generateQuestions(position: '客户端工程师');

      final adapter =
          (await nextChatClient)!.dio.httpClientAdapter as _CapturingAdapter;
      final messages =
          (adapter.requests.single.data as Map)['messages'] as List;
      final system = messages
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'])
          .join();
      expect(system, contains('JSON 字符串数组'));
      expect(system, contains('追问'));
    });

    test('逐题反馈：三节结构 + 扣原话点评 + 可照做的示范话术', () async {
      LlmClient? client;
      nextChatClient = Future.value(client = _client(
        (_) => _sseChunks([['【优点】不错']]),
      ));
      await service
          .generateFeedback(question: '介绍项目', answer: '我做了一款 App')
          .toList();

      final adapter = client.dio.httpClientAdapter as _CapturingAdapter;
      final messages =
          (adapter.requests.single.data as Map)['messages'] as List;
      final system = messages
          .where((m) => m['role'] == 'system')
          .map((m) => m['content'])
          .join();
      expect(system, contains('【优点】'));
      expect(system, contains('【不足】'));
      expect(system, contains('【改进建议】'));
      // 改进要能直接照做：给改写后的示范话术
      expect(system, contains('示范话术'));
      // 人话铁律：像学长复盘，不要端着的书面腔
      expect(system, contains('学长'));
    });
  });
}

/// 从打桩的 LlmClient 中取出最近一次请求的 user 消息，断言提示词内容用。
Future<String?> _capturedBody(Future<LlmClient?> clientFuture) async {
  final client = (await clientFuture)!;
  // LlmClient 构造时把 adapter 包进 dio；取回测试桩
  final adapter = client.dio.httpClientAdapter as _CapturingAdapter;
  final options = adapter.requests.single;
  final data = options.data;
  if (data is Map) {
    final messages = data['messages'] as List;
    return messages
        .where((m) => m['role'] == 'user')
        .map((m) => m['content'])
        .join('\n');
  }
  return null;
}
