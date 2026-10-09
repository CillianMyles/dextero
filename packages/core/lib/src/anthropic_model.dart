import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'agent_failure.dart';
import 'cancellation.dart';
import 'chat_history.dart';
import 'model.dart';
import 'tool.dart';

const defaultAnthropicModel = 'claude-haiku-4-5';
const anthropicSonnetModel = 'claude-sonnet-5-5';
const anthropicAuthSource = 'Anthropic API key';
const anthropicApiVersion = '2023-06-01';

/// First-party Messages API prices in US dollars per million tokens.
final class AnthropicModelPricing {
  const AnthropicModelPricing({
    required this.input,
    required this.output,
    required this.cacheWrite,
    required this.cacheRead,
  });

  final double input;
  final double output;

  /// Five-minute cache writes, the only TTL Dextero requests.
  final double cacheWrite;
  final double cacheRead;
}

const anthropicModelPricing = <String, AnthropicModelPricing>{
  'claude-haiku-4-5': AnthropicModelPricing(
    input: 1,
    output: 5,
    cacheWrite: 1.25,
    cacheRead: 0.10,
  ),
  'claude-sonnet-5-5': AnthropicModelPricing(
    input: 2,
    output: 10,
    cacheWrite: 2.50,
    cacheRead: 0.20,
  ),
  'claude-opus-5-5': AnthropicModelPricing(
    input: 4,
    output: 20,
    cacheWrite: 5,
    cacheRead: 0.20,
  ),
};

/// Estimates cost in millionths of a dollar, or null for an unpriced model.
int? estimateAnthropicCostMicrosUsd(String model, ModelUsage usage) {
  final pricing = anthropicModelPricing[model];
  if (pricing == null) return null;
  // One token at $N per million tokens costs N micro-dollars.
  return (usage.inputTokens * pricing.input +
          usage.outputTokens * pricing.output +
          usage.cacheCreationInputTokens * pricing.cacheWrite +
          usage.cacheReadInputTokens * pricing.cacheRead)
      .round();
}

/// Streams Messages API server-sent events as decoded JSON objects.
abstract interface class AnthropicTransport {
  Stream<JsonMap> streamMessage({
    required JsonMap request,
    CancellationToken? cancellationToken,
  });
}

/// Calls the Messages API over HTTPS with the key in the `x-api-key` header.
final class AnthropicHttpTransport implements AnthropicTransport {
  AnthropicHttpTransport({
    required String apiKey,
    Uri? apiEndpoint,
    this.responseTimeout = const Duration(seconds: 60),
    this.idleTimeout = const Duration(seconds: 90),
    this.maxDuration = const Duration(minutes: 10),
    this.maxEventBytes = 8 * 1024 * 1024,
  }) : _apiKey = _validatedApiKey(apiKey),
       _messagesUri = _normalizeEndpoint(
         apiEndpoint ?? Uri.parse('https://api.anthropic.com/'),
       ).resolve('v1/messages') {
    if (maxEventBytes < 1) {
      throw ArgumentError.value(
        maxEventBytes,
        'maxEventBytes',
        'must be positive',
      );
    }
  }

  final String _apiKey;
  final Uri _messagesUri;

  /// Time allowed for the response headers to arrive.
  final Duration responseTimeout;

  /// Longest gap between stream chunks; the API sends periodic pings.
  final Duration idleTimeout;

  /// Upper bound for one complete streamed response.
  final Duration maxDuration;
  final int maxEventBytes;

  @override
  Stream<JsonMap> streamMessage({
    required JsonMap request,
    CancellationToken? cancellationToken,
  }) async* {
    cancellationToken?.throwIfCancellationRequested();
    final client = HttpClient()..connectionTimeout = responseTimeout;
    final elapsed = Stopwatch()..start();
    try {
      final response = await _await(
        _open(client, request).timeout(responseTimeout),
        client,
        cancellationToken,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw await _errorFrom(response);
      }
      final lines = StreamIterator(
        response
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter()),
      );
      final data = StringBuffer();
      while (true) {
        final remaining = maxDuration - elapsed.elapsed;
        if (remaining <= Duration.zero) {
          throw const AnthropicApiException(
            statusCode: 408,
            errorType: 'timeout_error',
            message: 'The response exceeded the maximum duration.',
          );
        }
        final hasNext = await _await(
          lines.moveNext().timeout(
            remaining < idleTimeout ? remaining : idleTimeout,
          ),
          client,
          cancellationToken,
        );
        if (!hasNext) break;
        final line = lines.current;
        if (line.isEmpty) {
          if (data.isNotEmpty) yield _decodeEvent(data.toString());
          data.clear();
        } else if (line.startsWith('data:')) {
          if (data.isNotEmpty) data.write('\n');
          data.write(line.substring(line.startsWith('data: ') ? 6 : 5));
          if (data.length > maxEventBytes) {
            throw const FormatException(
              'Anthropic stream event exceeded size limit.',
            );
          }
        }
      }
      if (data.isNotEmpty) yield _decodeEvent(data.toString());
    } finally {
      client.close(force: true);
    }
  }

  Future<HttpClientResponse> _open(HttpClient client, JsonMap request) async {
    final encoded = utf8.encode(jsonEncode({...request, 'stream': true}));
    final httpRequest = await client.postUrl(_messagesUri);
    httpRequest.headers
      ..contentType = ContentType.json
      ..set('x-api-key', _apiKey)
      ..set('anthropic-version', anthropicApiVersion)
      ..set(HttpHeaders.acceptHeader, 'text/event-stream')
      ..contentLength = encoded.length;
    httpRequest.add(encoded);
    return httpRequest.close();
  }

  /// Races [operation] against cancellation and maps transient I/O failures.
  Future<T> _await<T>(
    Future<T> operation,
    HttpClient client,
    CancellationToken? cancellationToken,
  ) async {
    try {
      if (cancellationToken == null) return await operation;
      return await Future.any([
        operation,
        cancellationToken.whenCancelled.then<T>((_) {
          client.close(force: true);
          throw const RunCancelledException();
        }),
      ]);
    } on TimeoutException {
      cancellationToken?.throwIfCancellationRequested();
      throw const AnthropicApiException(
        statusCode: 408,
        errorType: 'timeout_error',
        message: 'The Anthropic API did not respond in time.',
      );
    } on SocketException catch (error) {
      cancellationToken?.throwIfCancellationRequested();
      throw AnthropicApiException(
        statusCode: 0,
        errorType: 'connection_error',
        message: error.message,
      );
    } on HttpException catch (error) {
      cancellationToken?.throwIfCancellationRequested();
      throw AnthropicApiException(
        statusCode: 0,
        errorType: 'connection_error',
        message: error.message,
      );
    } on Object {
      cancellationToken?.throwIfCancellationRequested();
      rethrow;
    }
  }

  JsonMap _decodeEvent(String data) {
    final decoded = jsonDecode(data);
    if (decoded is! Map) {
      throw const FormatException('Anthropic stream event was not an object.');
    }
    return decoded.cast<String, Object?>();
  }

  Future<AnthropicApiException> _errorFrom(HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response.timeout(responseTimeout)) {
      if (bytes.length + chunk.length > 64 * 1024) break;
      bytes.addAll(chunk);
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      decoded = null;
    }
    final error = decoded is Map && decoded['error'] is Map
        ? decoded['error']! as Map
        : const {};
    final retryAfter = int.tryParse(
      response.headers.value('retry-after')?.trim() ?? '',
    );
    return AnthropicApiException.classify(
      statusCode: response.statusCode,
      errorType: error['type'] is String ? error['type']! as String : null,
      message: error['message'] is String
          ? error['message']! as String
          : 'The Anthropic API rejected the request.',
      requestId: response.headers.value('request-id'),
      retryAfter: retryAfter == null || retryAfter < 0
          ? null
          : Duration(seconds: retryAfter),
    );
  }

  static String _validatedApiKey(String value) {
    final key = value.trim();
    if (key.isEmpty) {
      throw ArgumentError.value('<empty>', 'apiKey', 'must not be empty');
    }
    return key;
  }

  static Uri _normalizeEndpoint(Uri endpoint) {
    if (!{'http', 'https'}.contains(endpoint.scheme) || endpoint.host.isEmpty) {
      throw ArgumentError.value(
        endpoint,
        'apiEndpoint',
        'must be an absolute HTTP(S) URI',
      );
    }
    final path = endpoint.path.endsWith('/')
        ? endpoint.path
        : '${endpoint.path}/';
    return endpoint.replace(path: path, query: null, fragment: null);
  }
}

/// A Messages API error. The message never includes request credentials.
class AnthropicApiException implements Exception {
  const AnthropicApiException({
    required this.statusCode,
    required this.message,
    this.errorType,
    this.requestId,
    this.retryAfter,
  });

  /// Builds the most specific exception for an API error response or event.
  factory AnthropicApiException.classify({
    required int statusCode,
    required String message,
    String? errorType,
    String? requestId,
    Duration? retryAfter,
  }) {
    final normalized = message.toLowerCase();
    final code = switch (statusCode) {
      _
          when statusCode == 402 ||
              errorType == 'billing_error' ||
              normalized.contains('credit balance') ||
              normalized.contains('usage limit') =>
        ChatErrorCode.creditExhausted,
      401 => ChatErrorCode.authenticationFailed,
      _ when errorType == 'authentication_error' =>
        ChatErrorCode.authenticationFailed,
      429 => ChatErrorCode.rateLimited,
      _ => null,
    };
    if (code == null) {
      return AnthropicApiException(
        statusCode: statusCode,
        message: message,
        errorType: errorType,
        requestId: requestId,
        retryAfter: retryAfter,
      );
    }
    return AnthropicCategorizedApiException(
      errorCode: code,
      statusCode: statusCode,
      message: message,
      errorType: errorType,
      requestId: requestId,
      retryAfter: retryAfter,
    );
  }

  /// Builds an exception from an `error` event received mid-stream.
  factory AnthropicApiException.fromStreamEvent(JsonMap event) {
    final error = event['error'] is Map ? event['error']! as Map : const {};
    final type = error['type'] is String ? error['type']! as String : null;
    return AnthropicApiException.classify(
      statusCode: switch (type) {
        'overloaded_error' => 529,
        'rate_limit_error' => 429,
        'api_error' => 500,
        'billing_error' => 402,
        'authentication_error' => 401,
        _ => 400,
      },
      errorType: type,
      message: error['message'] is String
          ? error['message']! as String
          : 'The Anthropic stream reported an error.',
    );
  }

  /// HTTP status, or 0 when the connection failed before a response.
  final int statusCode;
  final String message;
  final String? errorType;
  final String? requestId;
  final Duration? retryAfter;

  /// Rate limits, overload, server errors, timeouts, and connection failures.
  bool get isRetryable =>
      statusCode == 0 ||
      statusCode == 408 ||
      statusCode == 429 ||
      statusCode >= 500;

  @override
  String toString() {
    final status = statusCode == 0 ? errorType : 'HTTP $statusCode';
    final request = requestId == null ? '' : ' [request $requestId]';
    return 'Anthropic API request failed ($status): $message$request';
  }
}

/// An API error that clients present as a specific user-facing state.
final class AnthropicCategorizedApiException extends AnthropicApiException
    implements CategorizedAgentFailure {
  const AnthropicCategorizedApiException({
    required this.errorCode,
    required super.statusCode,
    required super.message,
    super.errorType,
    super.requestId,
    super.retryAfter,
  });

  @override
  final ChatErrorCode errorCode;

  @override
  String get userMessage => switch (errorCode) {
    ChatErrorCode.creditExhausted =>
      'Out of Anthropic API credit: $message Add credit or raise the '
          'workspace spend limit in the Anthropic Console, or choose another '
          'model.',
    ChatErrorCode.authenticationFailed =>
      'The Anthropic API key was rejected: $message Check ANTHROPIC_API_KEY '
          'on the Dextero host.',
    ChatErrorCode.rateLimited =>
      'Anthropic rate limit persisted after retries: $message Try again '
          'shortly.',
  };
}

/// A response that ended for a reason other than completing its turn.
final class AnthropicStopException implements Exception {
  const AnthropicStopException({required this.stopReason, this.detail});

  final String stopReason;
  final String? detail;

  @override
  String toString() => switch (stopReason) {
    'max_tokens' => 'Claude reached its output token limit before finishing.',
    'refusal' =>
      'Claude declined the request${detail == null ? '' : ' ($detail)'}.',
    _ => 'Claude stopped unexpectedly (stop reason: $stopReason).',
  };
}

/// Claude Messages API adapter for Dextero's provider-neutral model seam.
final class AnthropicModel implements AgentModel {
  AnthropicModel({
    required AnthropicTransport transport,
    this.model = defaultAnthropicModel,
    this.maxTokens = 32000,
    this.maxRetries = 3,
    this.initialRetryDelay = const Duration(seconds: 1),
    this.maxRetryDelay = const Duration(seconds: 60),
    Future<void> Function(Duration delay)? sleep,
    this.systemInstruction =
        'You are driving the Dextero workspace harness. Use the provided '
        'tools for file and command operations. Use run_command for normal '
        'CLI execution and run_shell only when shell syntax is required.',
  }) : _transport = transport,
       _sleep = sleep ?? Future<void>.delayed {
    if (model.trim().isEmpty) {
      throw ArgumentError.value(model, 'model', 'must not be empty');
    }
    if (maxTokens < 1) {
      throw ArgumentError.value(maxTokens, 'maxTokens', 'must be positive');
    }
    if (maxRetries < 0) {
      throw ArgumentError.value(maxRetries, 'maxRetries', 'must not be < 0');
    }
  }

  final AnthropicTransport _transport;
  final Future<void> Function(Duration delay) _sleep;
  final String model;
  final int maxTokens;
  final int maxRetries;
  final Duration initialRetryDelay;
  final Duration maxRetryDelay;
  final String systemInstruction;

  @override
  Future<ModelTurn> nextTurn({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
    CancellationToken? cancellationToken,
    ModelEventSink? onEvent,
  }) async {
    if (messages.isEmpty) {
      throw ArgumentError.value(messages, 'messages', 'must not be empty');
    }
    final request = <String, Object?>{
      'model': model,
      'max_tokens': maxTokens,
      // Caches the growing conversation; the system marker below keeps a
      // read point for the stable tools + system prefix.
      'cache_control': {'type': 'ephemeral'},
      if (systemInstruction.trim().isNotEmpty)
        'system': [
          {
            'type': 'text',
            'text': systemInstruction,
            'cache_control': {'type': 'ephemeral'},
          },
        ],
      if (tools.isNotEmpty)
        'tools': [
          for (final tool in tools)
            {
              'name': tool.name,
              'description': tool.description,
              'input_schema': tool.inputSchema,
            },
        ],
      'messages': _encodeMessages(messages),
    };
    for (var attempt = 0; ; attempt++) {
      cancellationToken?.throwIfCancellationRequested();
      final turn = _TurnAccumulator();
      try {
        await for (final event in _transport.streamMessage(
          request: request,
          cancellationToken: cancellationToken,
        )) {
          final text = turn.apply(event);
          if (text != null && text.isNotEmpty) {
            await onEvent?.call(ModelTextDelta(text));
          }
        }
        return turn.finish(messages.length);
      } on AnthropicApiException catch (error) {
        // Retrying after visible output would duplicate streamed text.
        if (!error.isRetryable ||
            attempt >= maxRetries ||
            turn.emittedText ||
            error is AnthropicCategorizedApiException &&
                error.errorCode != ChatErrorCode.rateLimited) {
          rethrow;
        }
        final delay = _retryDelay(error, attempt);
        await onEvent?.call(
          ModelRetryScheduled(
            reason: error.toString(),
            delay: delay,
            attempt: attempt + 1,
          ),
        );
        final wait = _sleep(delay);
        await (cancellationToken?.waitFor(wait) ?? wait);
      }
    }
  }

  Duration _retryDelay(AnthropicApiException error, int attempt) {
    final requested = error.retryAfter;
    final exponential = initialRetryDelay * pow(2, attempt).toInt();
    final delay = requested ?? exponential;
    return delay > maxRetryDelay ? maxRetryDelay : delay;
  }

  List<JsonMap> _encodeMessages(List<AgentMessage> messages) {
    final encoded = <JsonMap>[];
    var index = 0;
    while (index < messages.length) {
      final message = messages[index];
      switch (message.role) {
        case MessageRole.user:
          encoded.add({'role': 'user', 'content': message.content ?? ''});
          index++;
        case MessageRole.assistant:
          encoded.add({
            'role': 'assistant',
            'content': _assistantContent(message),
          });
          index++;
        case MessageRole.tool:
          // Parallel tool results belong in one user message.
          final results = <JsonMap>[];
          while (index < messages.length &&
              messages[index].role == MessageRole.tool) {
            final result = messages[index].toolResult;
            if (result == null) {
              throw const FormatException('Tool message omitted its result.');
            }
            results.add({
              'type': 'tool_result',
              'tool_use_id': result.callId,
              'content': switch (result.content) {
                final String text => text,
                null => '',
                final value => jsonEncode(value),
              },
              if (result.isError) 'is_error': true,
            });
            index++;
          }
          encoded.add({'role': 'user', 'content': results});
      }
    }
    return encoded;
  }

  /// Replays the exact response blocks, including thinking signatures.
  List<Object?> _assistantContent(AgentMessage message) {
    if (message.providerState['anthropicContent'] case final List blocks
        when blocks.isNotEmpty) {
      return blocks;
    }
    return [
      if (message.content case final content? when content.isNotEmpty)
        {'type': 'text', 'text': content},
      for (final call in message.toolCalls)
        {
          'type': 'tool_use',
          'id': call.id,
          'name': call.name,
          'input': call.arguments,
        },
    ];
  }
}

/// Assembles one streamed Messages API response.
final class _TurnAccumulator {
  final Map<int, JsonMap> _blocks = {};
  final Map<int, StringBuffer> _toolInputs = {};
  var _inputTokens = 0;
  var _outputTokens = 0;
  var _cacheCreationInputTokens = 0;
  var _cacheReadInputTokens = 0;
  String? _stopReason;
  String? _stopDetail;
  var _stopped = false;
  var emittedText = false;

  /// Applies one event and returns any new visible text.
  String? apply(JsonMap event) {
    switch (event['type']) {
      case 'message_start':
        final message = event['message'];
        if (message is Map && message['usage'] is Map) {
          _applyUsage(message['usage']! as Map);
        }
      case 'content_block_start':
        final index = _index(event);
        final block = event['content_block'];
        if (block is! Map) {
          throw const FormatException('Anthropic sent a malformed block.');
        }
        final copy = block.cast<String, Object?>();
        _blocks[index] = switch (copy['type']) {
          'text' => {'type': 'text', 'text': copy['text'] ?? ''},
          'thinking' => {
            'type': 'thinking',
            'thinking': copy['thinking'] ?? '',
            'signature': copy['signature'] ?? '',
          },
          'tool_use' => {
            'type': 'tool_use',
            'id': copy['id'],
            'name': copy['name'],
            'input': const <String, Object?>{},
          },
          _ => Map.of(copy),
        };
        if (copy['type'] == 'tool_use') _toolInputs[index] = StringBuffer();
        if (copy['type'] == 'text') {
          final text = copy['text'] is String ? copy['text']! as String : '';
          if (text.isNotEmpty) emittedText = true;
          return text;
        }
      case 'content_block_delta':
        final index = _index(event);
        final block = _blocks[index];
        final delta = event['delta'];
        if (block == null || delta is! Map) {
          throw const FormatException('Anthropic sent an orphaned delta.');
        }
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'] is String
                ? delta['text']! as String
                : '';
            block['text'] = '${block['text'] ?? ''}$text';
            if (text.isNotEmpty) emittedText = true;
            return text;
          case 'input_json_delta':
            _toolInputs[index]?.write(delta['partial_json'] ?? '');
          case 'thinking_delta':
            block['thinking'] =
                '${block['thinking'] ?? ''}'
                '${delta['thinking'] ?? ''}';
          case 'signature_delta':
            block['signature'] = delta['signature'] ?? '';
        }
      case 'content_block_stop':
        final index = _index(event);
        final input = _toolInputs[index];
        if (input != null) {
          final raw = input.toString().trim();
          final decoded = raw.isEmpty ? const <String, Object?>{} : _json(raw);
          if (decoded is! Map) {
            throw const FormatException(
              'Claude returned malformed tool input.',
            );
          }
          _blocks[index]!['input'] = decoded.cast<String, Object?>();
        }
      case 'message_delta':
        final delta = event['delta'];
        if (delta is Map && delta['stop_reason'] is String) {
          _stopReason = delta['stop_reason']! as String;
          final details = delta['stop_details'];
          if (details is Map && details['category'] is String) {
            _stopDetail = details['category']! as String;
          }
        }
        if (event['usage'] is Map) _applyUsage(event['usage']! as Map);
      case 'message_stop':
        _stopped = true;
      case 'error':
        throw AnthropicApiException.fromStreamEvent(event);
    }
    return null;
  }

  ModelTurn finish(int messageCount) {
    if (!_stopped) {
      throw const AnthropicApiException(
        statusCode: 0,
        errorType: 'connection_error',
        message: 'The stream ended before the message completed.',
      );
    }
    final stopReason = _stopReason;
    if (stopReason == null ||
        !{'end_turn', 'tool_use', 'stop_sequence'}.contains(stopReason)) {
      throw AnthropicStopException(
        stopReason: stopReason ?? 'missing',
        detail: _stopDetail,
      );
    }
    final indexes = _blocks.keys.toList()..sort();
    final blocks = [for (final index in indexes) _blocks[index]!];
    final text = StringBuffer();
    final toolCalls = <ToolCall>[];
    for (final block in blocks) {
      if (block['type'] == 'text' && block['text'] is String) {
        text.write(block['text']! as String);
      } else if (block['type'] == 'tool_use') {
        final id = block['id'];
        final name = block['name'];
        if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
          throw const FormatException('Claude returned a malformed tool call.');
        }
        toolCalls.add(
          ToolCall(
            id: id,
            name: name,
            arguments: (block['input']! as Map).cast<String, Object?>(),
          ),
        );
      }
    }
    final output = text.toString();
    return ModelTurn(
      content: output.isEmpty ? null : output,
      toolCalls: List.unmodifiable(toolCalls),
      usage: ModelUsage(
        inputTokens: _inputTokens,
        outputTokens: _outputTokens,
        cacheCreationInputTokens: _cacheCreationInputTokens,
        cacheReadInputTokens: _cacheReadInputTokens,
      ),
      providerState: {'anthropicContent': blocks},
    );
  }

  /// Usage values are cumulative; later events replace earlier counts.
  void _applyUsage(Map usage) {
    int? count(String key) => usage[key] is int ? usage[key]! as int : null;
    _inputTokens = count('input_tokens') ?? _inputTokens;
    _outputTokens = count('output_tokens') ?? _outputTokens;
    _cacheCreationInputTokens =
        count('cache_creation_input_tokens') ?? _cacheCreationInputTokens;
    _cacheReadInputTokens =
        count('cache_read_input_tokens') ?? _cacheReadInputTokens;
  }

  int _index(JsonMap event) => event['index'] is int
      ? event['index']! as int
      : throw const FormatException('Anthropic event omitted its index.');

  Object? _json(String raw) {
    try {
      return jsonDecode(raw);
    } on FormatException {
      throw const FormatException('Claude returned malformed tool input.');
    }
  }
}
