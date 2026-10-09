import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicModel', () {
    test(
      'streams a tool loop, replays thinking, and records usage and cost',
      () async {
        final transport = _ScriptedTransport([
          _events([
            _start(input: 900, cacheWrite: 4200),
            {
              'type': 'content_block_start',
              'index': 0,
              'content_block': {
                'type': 'thinking',
                'thinking': '',
                'signature': '',
              },
            },
            {
              'type': 'content_block_delta',
              'index': 0,
              'delta': {'type': 'signature_delta', 'signature': 'sig-1'},
            },
            {'type': 'content_block_stop', 'index': 0},
            ..._textBlock(1, ['Checking ', 'the workspace.']),
            {
              'type': 'content_block_start',
              'index': 2,
              'content_block': {
                'type': 'tool_use',
                'id': 'toolu_1',
                'name': 'echo',
                'input': <String, Object?>{},
              },
            },
            {
              'type': 'content_block_delta',
              'index': 2,
              'delta': {
                'type': 'input_json_delta',
                'partial_json': '{"value":',
              },
            },
            {
              'type': 'content_block_delta',
              'index': 2,
              'delta': {'type': 'input_json_delta', 'partial_json': '"hi"}'},
            },
            {'type': 'content_block_stop', 'index': 2},
            _stopWith('tool_use', output: 40),
          ]),
          _events([
            _start(input: 30, cacheRead: 5100),
            ..._textBlock(0, ['Workspace ready.']),
            _stopWith('end_turn', output: 10),
          ]),
        ]);
        final events = <ConversationAgentEvent>[];

        final result =
            await ModelConversationAgent(
              model: AnthropicModel(transport: transport),
              tools: [_EchoTool()],
              providerName: 'Anthropic',
              modelName: defaultAnthropicModel,
              authSource: anthropicAuthSource,
              estimateCost: (usage) =>
                  estimateAnthropicCostMicrosUsd(defaultAnthropicModel, usage),
            ).run(
              'Inspect it',
              onEvent: events.add,
              cancellationToken: CancellationController().token,
            );

        expect(result.output, 'Workspace ready.');
        expect(events.map((event) => event.kind), [
          ConversationAgentEventKind.lifecycle,
          ConversationAgentEventKind.assistantDelta,
          ConversationAgentEventKind.toolCallStarted,
          ConversationAgentEventKind.toolCallCompleted,
          ConversationAgentEventKind.assistantDelta,
          ConversationAgentEventKind.usage,
        ]);
        expect(events[1].summary.text, 'Checking the workspace.');
        expect(events[2].toolCallId, 'toolu_1');
        final usage = events.last.usage!;
        expect(usage.provider, 'Anthropic');
        expect(usage.model, defaultAnthropicModel);
        expect(usage.authSource, 'Anthropic API key');
        expect(usage.modelRequests, 2);
        expect(usage.inputTokens, 930);
        expect(usage.outputTokens, 50);
        expect(usage.cacheCreationInputTokens, 4200);
        expect(usage.cacheReadInputTokens, 5100);
        // 930*1 + 50*5 + 4200*1.25 + 5100*0.1 micro-dollars.
        expect(usage.costMicrosUsd, 6940);
        expect(
          events.last.summary.text,
          'Anthropic · claude-haiku-4-5 · Anthropic API key · '
          '10,230 input (5,100 cache read, 4,200 cache write) · 50 output · '
          '\$0.0069',
        );

        final first = transport.requests.first;
        expect(first['model'], defaultAnthropicModel);
        expect(first['max_tokens'], 32000);
        expect(first['cache_control'], {'type': 'ephemeral'});
        final system = (first['system']! as List).single as Map;
        expect(system['cache_control'], {'type': 'ephemeral'});
        final tool = (first['tools']! as List).single as Map;
        expect(tool['name'], 'echo');
        expect(tool['input_schema'], _EchoTool.schema);

        final messages = transport.requests.last['messages']! as List;
        expect(messages, hasLength(3));
        final assistant = messages[1] as Map;
        expect(assistant['role'], 'assistant');
        final blocks = assistant['content']! as List;
        expect(blocks.first, {
          'type': 'thinking',
          'thinking': '',
          'signature': 'sig-1',
        });
        expect(blocks.last, {
          'type': 'tool_use',
          'id': 'toolu_1',
          'name': 'echo',
          'input': {'value': 'hi'},
        });
        expect(messages[2], {
          'role': 'user',
          'content': [
            {
              'type': 'tool_result',
              'tool_use_id': 'toolu_1',
              'content': '{"echo":"hi"}',
            },
          ],
        });
      },
    );

    test('returns a permission denial to Claude as a tool error', () async {
      final transport = _ScriptedTransport([
        _events([
          _start(),
          {
            'type': 'content_block_start',
            'index': 0,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_edit',
              'name': 'edit_file',
              'input': <String, Object?>{},
            },
          },
          {
            'type': 'content_block_delta',
            'index': 0,
            'delta': {
              'type': 'input_json_delta',
              'partial_json': '{"path":"a.txt","old":"a","new":"b"}',
            },
          },
          {'type': 'content_block_stop', 'index': 0},
          _stop('tool_use'),
        ]),
        _events([
          _start(),
          ..._textBlock(0, ['Left unchanged.']),
          _stop(),
        ]),
      ]);
      final editTool = _RecordingTool('edit_file');

      final run =
          await AgentLoop(
            model: AnthropicModel(transport: transport),
            tools: [editTool],
          ).run(
            'Edit it',
            onApprovalRequest: (request) async {
              expect(request.toolCallId, 'toolu_edit');
              return false;
            },
          );

      expect(run.output, 'Left unchanged.');
      expect(editTool.calls, 0);
      final result =
          (((transport.requests.last['messages']! as List)[2]
                      as Map)['content']!
                  as List)
              .single;
      expect(result, {
        'type': 'tool_result',
        'tool_use_id': 'toolu_edit',
        'content': 'edit_file was not approved.',
        'is_error': true,
      });
    });

    test(
      'retries 429 and mid-stream overload, honouring retry-after',
      () async {
        final delays = <Duration>[];
        final transport = _ScriptedTransport([
          _failure(
            const AnthropicApiException(
              statusCode: 429,
              errorType: 'rate_limit_error',
              message: 'Slow down.',
              retryAfter: Duration(seconds: 7),
            ),
          ),
          _events([
            _start(),
            {
              'type': 'error',
              'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
            },
          ]),
          _events([
            _start(),
            ..._textBlock(0, ['Done.']),
            _stop(),
          ]),
        ]);
        final retries = <ModelRetryScheduled>[];

        final turn =
            await AnthropicModel(
              transport: transport,
              sleep: (delay) async => delays.add(delay),
            ).nextTurn(
              messages: [AgentMessage.user('Hi')],
              tools: const [],
              onEvent: (event) {
                if (event is ModelRetryScheduled) retries.add(event);
              },
            );

        expect(turn.content, 'Done.');
        expect(delays, [
          const Duration(seconds: 7),
          const Duration(seconds: 2),
        ]);
        expect(retries.map((retry) => retry.attempt), [1, 2]);
        expect(retries.last.reason, contains('HTTP 529'));
      },
    );

    test('stops retrying after the configured limit', () async {
      final transport = _ScriptedTransport([
        for (var index = 0; index < 3; index++)
          _failure(
            const AnthropicApiException(statusCode: 529, message: 'Overloaded'),
          ),
      ]);

      await expectLater(
        AnthropicModel(
          transport: transport,
          maxRetries: 2,
          sleep: (_) async {},
        ).nextTurn(messages: [AgentMessage.user('Hi')], tools: const []),
        throwsA(
          isA<AnthropicApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            529,
          ),
        ),
      );
      expect(transport.requests, hasLength(3));
    });

    test('does not retry after text has streamed', () async {
      final transport = _ScriptedTransport([
        _events([
          _start(),
          ..._textBlock(0, ['Partial']).take(2),
          {
            'type': 'error',
            'error': {'type': 'overloaded_error', 'message': 'Overloaded'},
          },
        ]),
      ]);

      await expectLater(
        AnthropicModel(
          transport: transport,
          sleep: (_) async {},
        ).nextTurn(messages: [AgentMessage.user('Hi')], tools: const []),
        throwsA(isA<AnthropicApiException>()),
      );
      expect(transport.requests, hasLength(1));
    });

    test('records out-of-credit as a categorized failure with usage', () async {
      final store = InMemoryChatHistoryStore();
      final transport = _ScriptedTransport([
        _failure(
          AnthropicApiException.classify(
            statusCode: 400,
            errorType: 'invalid_request_error',
            message:
                'Your credit balance is too low to access the Anthropic API.',
          ),
        ),
      ]);
      final service = ChatService(
        store: store,
        agent: ModelConversationAgent(
          model: AnthropicModel(transport: transport),
          tools: const [],
          providerName: 'Anthropic',
        ),
      );
      final conversation = await service.createConversation();

      await service.submit(conversationId: conversation.id, message: 'Hi');
      final history = await _settled(store, conversation.id);

      final error = history.singleWhere(
        (entry) => entry.kind == ChatEntryKind.error,
      );
      expect(error.errorCode, ChatErrorCode.creditExhausted);
      expect(error.content, startsWith('Out of Anthropic API credit:'));
      expect(error.content, contains('Anthropic Console'));
      expect(transport.requests, hasLength(1));
      expect(history.last.status, ChatEntryStatus.failed);
    });

    test('cancels an in-flight stream and a pending retry', () async {
      final streaming = CancellationController();
      final hanging = _HangingTransport();
      final pending = AnthropicModel(transport: hanging).nextTurn(
        messages: [AgentMessage.user('Hi')],
        tools: const [],
        cancellationToken: streaming.token,
      );
      await hanging.started.future;
      streaming.cancel();
      await expectLater(pending, throwsA(isA<RunCancelledException>()));
      expect(hanging.cancelledByConsumer, isTrue);

      final retrying = CancellationController();
      final sleeping = Completer<void>();
      final retry =
          AnthropicModel(
            transport: _ScriptedTransport([
              _failure(
                const AnthropicApiException(statusCode: 529, message: 'Busy'),
              ),
            ]),
            sleep: (_) {
              scheduleMicrotask(retrying.cancel);
              return sleeping.future;
            },
          ).nextTurn(
            messages: [AgentMessage.user('Hi')],
            tools: const [],
            cancellationToken: retrying.token,
          );
      await expectLater(retry, throwsA(isA<RunCancelledException>()));
    });

    test('maps max_tokens and refusals to clear stop errors', () async {
      Future<ModelTurn> turn(JsonMap stop) => AnthropicModel(
        transport: _ScriptedTransport([
          _events([
            _start(),
            ..._textBlock(0, ['Part']),
            stop,
          ]),
        ]),
      ).nextTurn(messages: [AgentMessage.user('Hi')], tools: const []);

      await expectLater(
        turn(_stop('max_tokens')),
        throwsA(
          isA<AnthropicStopException>().having(
            (error) => error.toString(),
            'message',
            contains('output token limit'),
          ),
        ),
      );
      await expectLater(
        turn({
          'type': 'message_delta',
          'delta': {
            'stop_reason': 'refusal',
            'stop_details': {'type': 'refusal', 'category': 'cyber'},
          },
          'usage': {'output_tokens': 1},
        }),
        throwsA(
          isA<AnthropicStopException>().having(
            (error) => error.toString(),
            'message',
            'Claude declined the request (cyber).',
          ),
        ),
      );
    });

    test('rejects a stream that ends before message_stop', () async {
      await expectLater(
        AnthropicModel(
          transport: _ScriptedTransport([
            _events([_start(), ..._textBlock(0, [])]),
            _events([_start(), ..._textBlock(0, [])]),
          ]),
          maxRetries: 1,
          sleep: (_) async {},
        ).nextTurn(messages: [AgentMessage.user('Hi')], tools: const []),
        throwsA(
          isA<AnthropicApiException>().having(
            (error) => error.errorType,
            'errorType',
            'connection_error',
          ),
        ),
      );
    });
  });

  group('AnthropicApiException.classify', () {
    test('categorizes credit, authentication, and rate-limit failures', () {
      CategorizedAgentFailure categorized(int status, String type, String m) =>
          AnthropicApiException.classify(
                statusCode: status,
                errorType: type,
                message: m,
              )
              as CategorizedAgentFailure;

      expect(
        categorized(402, 'billing_error', 'Payment required.').errorCode,
        ChatErrorCode.creditExhausted,
      );
      expect(
        categorized(
          400,
          'invalid_request_error',
          'You have reached your specified workspace API usage limits.',
        ).errorCode,
        ChatErrorCode.creditExhausted,
      );
      expect(
        categorized(401, 'authentication_error', 'invalid x-api-key').errorCode,
        ChatErrorCode.authenticationFailed,
      );
      expect(
        categorized(429, 'rate_limit_error', 'Slow down.').errorCode,
        ChatErrorCode.rateLimited,
      );
      expect(
        AnthropicApiException.classify(statusCode: 400, message: 'Bad'),
        isNot(isA<CategorizedAgentFailure>()),
      );
    });

    test('prices known models and leaves unknown models unpriced', () {
      const usage = ModelUsage(
        inputTokens: 1000000,
        outputTokens: 1000000,
        cacheCreationInputTokens: 1000000,
        cacheReadInputTokens: 1000000,
      );
      expect(
        estimateAnthropicCostMicrosUsd(anthropicSonnetModel, usage),
        (2 + 10 + 2.5 + 0.2) * 1000000,
      );
      expect(estimateAnthropicCostMicrosUsd('claude-unknown', usage), isNull);
    });
  });

  group('AnthropicHttpTransport', () {
    late HttpServer server;
    late List<HttpRequest> requests;
    late List<String> bodies;
    late Future<void> Function(HttpRequest request) handler;

    setUp(() async {
      requests = [];
      bodies = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add(request);
        bodies.add(await utf8.decodeStream(request));
        request.response.bufferOutput = false;
        await handler(request);
      });
    });

    tearDown(() => server.close(force: true));

    AnthropicHttpTransport transport({Duration? idleTimeout}) =>
        AnthropicHttpTransport(
          apiKey: 'sk-ant-test-secret',
          apiEndpoint: Uri.parse('http://127.0.0.1:${server.port}'),
          idleTimeout: idleTimeout ?? const Duration(seconds: 5),
        );

    test('sends authenticated streaming requests and parses SSE', () async {
      handler = (request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write(
          ': comment\n'
          'event: message_start\n'
          'data: {"type":"message_start","message":{"usage":{}}}\n\n'
          'event: ping\ndata: {"type":"ping"}\n\n'
          'event: message_stop\ndata: {"type":"message_stop"}\n\n',
        );
        await request.response.close();
      };

      final events = await transport()
          .streamMessage(request: {'model': 'claude-haiku-4-5'})
          .toList();

      expect(events.map((event) => event['type']), [
        'message_start',
        'ping',
        'message_stop',
      ]);
      final request = requests.single;
      expect(request.uri.path, '/v1/messages');
      expect(request.headers.value('x-api-key'), 'sk-ant-test-secret');
      expect(request.headers.value('anthropic-version'), '2023-06-01');
      expect(request.uri.query, isEmpty);
      expect(jsonDecode(bodies.single), {
        'model': 'claude-haiku-4-5',
        'stream': true,
      });
    });

    test('parses API errors without exposing the key', () async {
      handler = (request) async {
        request.response
          ..statusCode = 429
          ..headers.set('retry-after', '12')
          ..headers.set('request-id', 'req_123')
          ..write(
            jsonEncode({
              'type': 'error',
              'error': {'type': 'rate_limit_error', 'message': 'Slow down.'},
            }),
          );
        await request.response.close();
      };

      final error = await transport()
          .streamMessage(request: const {})
          .toList()
          .then<Object?>((_) => null, onError: (Object error) => error);

      expect(error, isA<AnthropicCategorizedApiException>());
      final apiError = error! as AnthropicApiException;
      expect(apiError.statusCode, 429);
      expect(apiError.retryAfter, const Duration(seconds: 12));
      expect(apiError.isRetryable, isTrue);
      expect(apiError.toString(), contains('req_123'));
      expect(apiError.toString(), isNot(contains('sk-ant-test-secret')));
    });

    test('cancels an open stream and times out an idle one', () async {
      // A raw socket reports the client hanging up; HttpServer writes keep
      // succeeding after the peer has gone.
      final raw = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(raw.close);
      final disconnected = Completer<void>();
      raw.listen((socket) {
        Timer? pings;
        void hungUp() {
          pings?.cancel();
          if (!disconnected.isCompleted) disconnected.complete();
        }

        socket.listen(
          (_) {
            if (pings != null) return;
            socket.write(
              'HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n'
              'transfer-encoding: chunked\r\n\r\n',
            );
            pings = Timer.periodic(const Duration(milliseconds: 20), (_) {
              const event = 'data: {"type":"ping"}\n\n';
              socket.write('${event.length.toRadixString(16)}\r\n$event\r\n');
            });
          },
          onDone: hungUp,
          onError: (Object _) => hungUp(),
        );
      });

      final controller = CancellationController();
      final events = <JsonMap>[];
      final cancelled =
          AnthropicHttpTransport(
                apiKey: 'sk-ant-test-secret',
                apiEndpoint: Uri.parse('http://127.0.0.1:${raw.port}'),
              )
              .streamMessage(
                request: const {},
                cancellationToken: controller.token,
              )
              .forEach((event) {
                events.add(event);
                controller.cancel();
              });
      await expectLater(cancelled, throwsA(isA<RunCancelledException>()));
      expect(events, hasLength(1));
      await disconnected.future.timeout(const Duration(seconds: 5));

      handler = (request) async {
        request.response.headers.contentType = ContentType(
          'text',
          'event-stream',
        );
        request.response.write('data: {"type":"ping"}\n\n');
        await request.response.flush();
      };

      await expectLater(
        transport(
          idleTimeout: const Duration(milliseconds: 100),
        ).streamMessage(request: const {}).toList(),
        throwsA(
          isA<AnthropicApiException>().having(
            (error) => error.statusCode,
            'statusCode',
            408,
          ),
        ),
      );
    });
  });
}

Future<List<ChatHistoryEntry>> _settled(
  ChatHistoryStore store,
  String conversationId,
) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final history = await store.history(conversationId);
    if (history.isNotEmpty &&
        history.last.kind == ChatEntryKind.lifecycle &&
        {
          ChatEntryStatus.completed,
          ChatEntryStatus.failed,
          ChatEntryStatus.cancelled,
        }.contains(history.last.status)) {
      return history;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Run did not settle.');
}

JsonMap _start({int input = 10, int cacheWrite = 0, int cacheRead = 0}) => {
  'type': 'message_start',
  'message': {
    'id': 'msg_test',
    'model': defaultAnthropicModel,
    'usage': {
      'input_tokens': input,
      'cache_creation_input_tokens': cacheWrite,
      'cache_read_input_tokens': cacheRead,
      'output_tokens': 1,
    },
  },
};

List<JsonMap> _textBlock(int index, List<String> chunks) => [
  {
    'type': 'content_block_start',
    'index': index,
    'content_block': {'type': 'text', 'text': ''},
  },
  for (final chunk in chunks)
    {
      'type': 'content_block_delta',
      'index': index,
      'delta': {'type': 'text_delta', 'text': chunk},
    },
  {'type': 'content_block_stop', 'index': index},
];

JsonMap _stop([String reason = 'end_turn', int output = 5]) =>
    _stopWith(reason, output: output);

JsonMap _stopWith(String reason, {int output = 5}) => {
  'type': 'message_delta',
  'delta': {'stop_reason': reason},
  'usage': {'output_tokens': output},
};

Stream<JsonMap> Function() _events(List<JsonMap> events) =>
    () => Stream.fromIterable(
      events.followedBy([
        if (events.last['type'] == 'message_delta') {'type': 'message_stop'},
      ]),
    );

Stream<JsonMap> Function() _failure(Object error) =>
    () => Stream.error(error);

final class _ScriptedTransport implements AnthropicTransport {
  _ScriptedTransport(this._responses);

  final List<Stream<JsonMap> Function()> _responses;
  final requests = <JsonMap>[];

  @override
  Stream<JsonMap> streamMessage({
    required JsonMap request,
    CancellationToken? cancellationToken,
  }) {
    requests.add(jsonDecode(jsonEncode(request)) as JsonMap);
    return _responses[requests.length - 1]();
  }
}

final class _HangingTransport implements AnthropicTransport {
  final started = Completer<void>();
  var cancelledByConsumer = false;

  @override
  Stream<JsonMap> streamMessage({
    required JsonMap request,
    CancellationToken? cancellationToken,
  }) {
    late StreamController<JsonMap> controller;
    controller = StreamController<JsonMap>(
      onListen: () {
        controller.add(_start());
        started.complete();
        cancellationToken!.whenCancelled.then((_) {
          cancelledByConsumer = true;
          controller.addError(const RunCancelledException());
          controller.close();
        });
      },
    );
    return controller.stream;
  }
}

final class _EchoTool implements Tool {
  static const schema = {
    'type': 'object',
    'properties': {
      'value': {'type': 'string'},
    },
    'required': ['value'],
  };

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'echo',
    description: 'Echo a value.',
    inputSchema: schema,
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) => {'echo': arguments['value']};
}

final class _RecordingTool implements Tool {
  _RecordingTool(this.name);

  final String name;
  var calls = 0;

  @override
  ToolDefinition get definition => ToolDefinition(
    name: name,
    description: 'Records calls.',
    inputSchema: const {'type': 'object'},
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) {
    calls++;
    return 'ok';
  }
}
