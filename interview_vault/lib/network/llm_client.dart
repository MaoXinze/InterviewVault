import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 用户自持 AI 直连客户端（AGENTS 铁律 2：App 只是遥控器，请求从客户端直连）。
///
/// 安全设计：
/// - [EndpointAuthInterceptor] 只在请求 host == 用户配置 baseUrl 的 host 时
///   注入鉴权头，绝不把 Key 带去任何第三方；
/// - [RedactingLogInterceptor] 输出日志时脱敏全部 header（AGENTS 安全红线）；
/// - 异常信息不携带 Key。
class LlmClient {
  LlmClient({required this.endpoint, required this.apiKey, Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              baseUrl: endpoint.baseUrl,
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 60),
              // 安全红线：302 重定向可能把 x-api-key 带到非用户配置的 host
              //（dart:io 会剥离 Authorization，但不剥离 x-api-key）。
              // LLM API 无合法重定向场景，直接禁用跟随。
              followRedirects: false,
              maxRedirects: 0,
            )) {
    _dio.interceptors.addAll([
      EndpointAuthInterceptor(
        allowedHost: Uri.parse(endpoint.baseUrl).host,
        providerId: endpoint.providerId,
        apiKey: apiKey,
      ),
      RedactingLogInterceptor(),
    ]);
  }

  final AiEndpoint endpoint;
  final String apiKey;
  final Dio _dio;

  /// 供高级场景复用同一份拦截器配置（测试也借此验证跨 host 不带 Key）。
  Dio get dio => _dio;

  /// 连接测试：OpenAI 兼容走 GET /models；Anthropic 走 GET /v1/models。
  Future<LlmTestResult> testConnection() async {
    final path = endpoint.providerId == 'anthropic'
        ? '/v1/models'
        : '/models';
    try {
      final resp = await _dio.get<dynamic>(path);
      if (resp.statusCode == 200) {
        return const LlmTestResult.success('连接成功');
      }
      return LlmTestResult.failure('服务端返回 ${resp.statusCode}');
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      return LlmTestResult.failure(
        '连接失败${code != null ? '（HTTP $code）' : ''}：${e.type.name}',
      );
    } on Exception catch (e) {
      return LlmTestResult.failure('连接失败：$e');
    }
  }

  /// 流式对话（SSE，OpenAI 兼容格式；Anthropic 的 content_block_delta 同样解析）。
  ///
  /// W1 保证"流式就绪"；W3 模拟面试逐题反馈直接复用。
  Stream<String> chatCompletionStream({
    required List<Map<String, String>> messages,
    String? modelName,
  }) async* {
    final resp = await _dio.post<ResponseBody>(
      endpoint.providerId == 'anthropic'
          ? '/v1/messages'
          : '/chat/completions',
      options: Options(responseType: ResponseType.stream),
      data: endpoint.providerId == 'anthropic'
          ? {
              'model': modelName ?? endpoint.modelName,
              'messages': messages,
              'max_tokens': 1024,
              'stream': true,
            }
          : {
              'model': modelName ?? endpoint.modelName,
              'messages': messages,
              'stream': true,
            },
    );
    final body = resp.data;
    if (body == null) return;
    await for (final event in _parseSse(body.stream)) {
      yield event;
    }
  }

  Stream<String> _parseSse(Stream<Uint8List> bytes) async* {
    var buffer = '';
    await for (final chunk in bytes.cast<List<int>>().transform(utf8.decoder)) {
      buffer += chunk;
      while (buffer.contains('\n')) {
        final idx = buffer.indexOf('\n');
        final line = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 1);
        final text = _deltaFromLine(line);
        if (text != null) yield text;
      }
    }
    // 流结束：部分服务端最后一行不带换行符，flush 残留的 buffer
    final text = _deltaFromLine(buffer);
    if (text != null) yield text;
  }

  /// 解析一行 SSE，返回增量文本；非 data 行 / 空 payload / [DONE] 返回 null。
  /// [DONE] 后无需提前终止流：服务端随即断开，残余行为空行或注释。
  String? _deltaFromLine(String rawLine) {
    final line = rawLine.trim();
    if (!line.startsWith('data:')) return null;
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;
    return _extractDeltaText(payload);
  }

  String? _extractDeltaText(String jsonPayload) {
    try {
      final obj = jsonDecode(jsonPayload);
      if (obj is! Map<String, dynamic>) return null;
      if (obj['type'] == 'content_block_delta') {
        final delta = obj['delta'];
        if (delta is Map<String, dynamic>) return delta['text'] as String?;
      }
      final choices = obj['choices'];
      if (choices is List && choices.isNotEmpty) {
        final first = choices.first;
        if (first is Map<String, dynamic>) {
          final delta = first['delta'];
          if (delta is Map<String, dynamic>) return delta['content'] as String?;
        }
      }
      return null;
    } on FormatException {
      return null;
    }
  }
}

/// 一个用户可配置的 AI 端点（不含 Key 本体；Key 单独传入内存）。
class AiEndpoint {
  const AiEndpoint({
    required this.providerId,
    required this.baseUrl,
    required this.modelName,
  });

  final String providerId;
  final String baseUrl;
  final String modelName;
}

class LlmTestResult {
  const LlmTestResult.success(this.message) : success = true;
  const LlmTestResult.failure(this.message) : success = false;

  final bool success;
  final String message;
}

/// 按鉴权方式构造请求头；仅 [EndpointAuthInterceptor] 在 host 校验后调用。
Map<String, String> authHeaders(String providerId, String apiKey) =>
    switch (providerId) {
      'anthropic' => {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
      _ => {'Authorization': 'Bearer $apiKey'},
    };

class EndpointAuthInterceptor extends Interceptor {
  EndpointAuthInterceptor({
    required this.allowedHost,
    required this.providerId,
    required this.apiKey,
  });

  /// 用户配置的 baseUrl 的 host——Key 唯一允许发往的目的地
  final String allowedHost;
  final String providerId;
  final String apiKey;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (options.uri.host == allowedHost) {
      options.headers.addAll(authHeaders(providerId, apiKey));
    }
    handler.next(options);
  }
}

/// 日志脱敏：全部 header 值替换为 ***（AGENTS：日志拦截器必须脱敏全部 header）。
Map<String, String> redactHeaders(Map<String, dynamic> headers) =>
    headers.map((k, _) => MapEntry(k, '***'));

class RedactingLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    assert(() {
      // ignore: avoid_print
      print('[llm] → ${options.method} ${options.uri}');
      // ignore: avoid_print
      print('[llm]   headers: ${redactHeaders(options.headers)}');
      return true;
    }());
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    assert(() {
      // ignore: avoid_print
      print('[llm] ✗ ${err.response?.statusCode} ${err.requestOptions.uri}');
      return true;
    }());
    handler.next(err);
  }
}
