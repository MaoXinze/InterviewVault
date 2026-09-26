import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interview_vault/network/llm_client.dart';

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

AiEndpoint _endpoint([String baseUrl = 'https://api.example.com/v1']) =>
    AiEndpoint(providerId: 'openai', baseUrl: baseUrl, modelName: 'test-model');

void main() {
  test('请求 host == 用户配置 baseUrl host 时注入 Authorization', () async {
    final adapter = _CapturingAdapter(
      (options) => ResponseBody.fromString('{}', 200),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
      ..httpClientAdapter = adapter;
    final client = LlmClient(
      endpoint: _endpoint(),
      apiKey: 'sk-THIS-SHOULD-NOT-LEAK',
      dio: dio,
    );

    await client.testConnection();

    final headers = adapter.requests.single.headers;
    expect(headers['Authorization'], 'Bearer sk-THIS-SHOULD-NOT-LEAK');
  });

  test('禁用重定向跟随：跨 host 3xx 不把 Key 带往别的端点', () async {
    final adapter = _CapturingAdapter(
      (options) => ResponseBody.fromString(
        'moved',
        302,
        headers: {
          'location': ['https://evil.example.org/harvest'],
        },
      ),
    );
    // 不注入 dio：走生产路径的 BaseOptions（安全开关内建）
    final client =
        LlmClient(endpoint: _endpoint(), apiKey: 'sk-THIS-SHOULD-NOT-LEAK')
          ..dio.httpClientAdapter = adapter;

    await client.testConnection();

    // 只对配置 host 发起一次请求；请求层面禁用重定向跟随，
    // 防止 302 把 x-api-key 带到非用户配置的 host
    expect(adapter.requests, hasLength(1));
    expect(adapter.requests.single.followRedirects, isFalse);
    expect(adapter.requests.single.maxRedirects, isZero);
  });

  test('请求 host 与配置 host 不同时绝不注入 Key', () async {
    final adapter = _CapturingAdapter(
      (options) => ResponseBody.fromString('{}', 200),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
      ..httpClientAdapter = adapter;
    final client = LlmClient(
      endpoint: _endpoint(),
      apiKey: 'sk-THIS-SHOULD-NOT-LEAK',
      dio: dio,
    );

    // 模拟任何指向第三方的请求：不能带上用户的 Key
    await client.dio.get('https://totally-different.example.org/anything');

    final headers = adapter.requests.single.headers;
    expect(headers.containsKey('Authorization'), isFalse);
    expect(jsonEncode(headers), isNot(contains('sk-THIS-SHOULD-NOT-LEAK')));
  });

  test('anthropic 走 x-api-key + anthropic-version 头', () async {
    final adapter = _CapturingAdapter(
      (options) => ResponseBody.fromString(
        jsonEncode({'data': []}),
        200,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType],
        },
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.anthropic.com'))
      ..httpClientAdapter = adapter;
    final client = LlmClient(
      endpoint: const AiEndpoint(
        providerId: 'anthropic',
        baseUrl: 'https://api.anthropic.com',
        modelName: 'claude-3-5-haiku-latest',
      ),
      apiKey: 'sk-ant-test',
      dio: dio,
    );

    await client.testConnection();

    final headers = adapter.requests.single.headers;
    expect(headers['x-api-key'], 'sk-ant-test');
    expect(headers['anthropic-version'], isNotEmpty);
    expect(headers.containsKey('Authorization'), isFalse);
  });

  test('连接测试 401 → success=false，错误信息不含 Key', () async {
    final adapter = _CapturingAdapter(
      (options) => ResponseBody.fromString('unauthorized', 401),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
      ..httpClientAdapter = adapter;
    final client = LlmClient(
      endpoint: _endpoint(),
      apiKey: 'sk-TOPSECRET',
      dio: dio,
    );

    final result = await client.testConnection();

    expect(result.success, isFalse);
    expect(result.message, isNot(contains('sk-TOPSECRET')));
  });

  test('日志拦截器脱敏全部 header 值', () {
    final redacted = redactHeaders({
      'Authorization': 'Bearer sk-TOPSECRET',
      'Content-Type': 'application/json',
      'x-api-key': 'sk-ant-SECRET',
    });
    expect(redacted.keys, containsAll(['Authorization', 'Content-Type']));
    expect(
      redacted.values.where((v) => v.toString().contains('sk-')),
      isEmpty,
    );
  });

  test('SSE 流式：逐 delta 吐出文本，遇到 [DONE] 结束', () async {
    const sse =
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"好"}}]}\n\n'
        'data: [DONE]\n\n';
    final adapter = _CapturingAdapter(
      (options) => ResponseBody.fromBytes(
        utf8.encode(sse),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
      ..httpClientAdapter = adapter;
    final client = LlmClient(endpoint: _endpoint(), apiKey: 'sk-x', dio: dio);

    final chunks = await client
        .chatCompletionStream(
          messages: const [
            {'role': 'user', 'content': '你好'},
          ],
        )
        .toList();

    expect(chunks, ['你', '好']);
  });

  test('SSE 尾包：最后一行不带换行符也吐出（部分服务端行为）', () async {
    const sse =
        'data: {"choices":[{"delta":{"content":"你"}}]}\n\n'
        'data: {"choices":[{"delta":{"content":"好"}}]}';
    final adapter = _CapturingAdapter(
      (options) => ResponseBody.fromBytes(
        utf8.encode(sse),
        200,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      ),
    );
    final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/v1'))
      ..httpClientAdapter = adapter;
    final client = LlmClient(endpoint: _endpoint(), apiKey: 'sk-x', dio: dio);

    final chunks = await client
        .chatCompletionStream(
          messages: const [
            {'role': 'user', 'content': '你好'},
          ],
        )
        .toList();

    expect(chunks, ['你', '好']);
  });
}
