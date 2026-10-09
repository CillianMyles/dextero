import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_core/dextero_core.dart';
import 'package:dextero_server/dextero_client.dart' show HostModelSelection;
import 'package:dextero_server/dextero_server.dart';
import 'package:test/test.dart';

/// Covers CLI → generated client → Serverpod → core → HTTP Messages API,
/// with a local fake API standing in for api.anthropic.com.
void main() {
  late _FakeMessagesApi api;
  late Directory workspace;
  late InMemoryChatHistoryStore store;
  late String conversationId;
  late int port;
  late Future<void> Function() shutdown;
  const token = 'anthropic-acceptance-token-0123456789012345';

  setUp(() async {
    api = await _FakeMessagesApi.start();
    workspace = await Directory.systemTemp.createTemp('dextero-anthropic-');
    await File('${workspace.path}/README.md').writeAsString('# Demo\n');
    final configuration = AgentRuntimeConfiguration.fromEnvironment({
      'ANTHROPIC_API_KEY': 'sk-ant-acceptance-secret',
      'ANTHROPIC_BASE_URL': 'http://127.0.0.1:${api.port}',
      'GEMINI_API_KEY': 'unused-gemini-key',
    });
    store = InMemoryChatHistoryStore();
    final service = ChatService(
      store: store,
      agent: configuration.createAgent(workspace: workspace.path),
    );
    conversationId = (await service.createConversation()).id;
    final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    port = probe.port;
    await probe.close();
    final pod = await startControlServer(
      token: token,
      chatService: service,
      defaultConversationId: conversationId,
      apiPort: port,
      runInGuardedZone: false,
      modelProvider: configuration.providerName,
      modelName: configuration.modelName,
      availableModels: configuration.availableModels,
      modelOptions: configuration.availableOptions,
      modelSelector: (id) {
        final option = configuration.availableOptions.singleWhere(
          (option) => option.id == id,
        );
        return service.selectAgent(
          conversationId: conversationId,
          agent: configuration.createAgent(
            workspace: workspace.path,
            provider: option.provider,
            modelName: option.modelName,
          ),
        );
      },
    );
    shutdown = () async {
      await pod.shutdown(exitProcess: false);
      await store.close();
      await api.close();
      await workspace.delete(recursive: true);
    };
  });

  tearDown(() => shutdown());

  ServerpodTerminalChatClient client() => ServerpodTerminalChatClient(
    serverUrl: 'http://localhost:$port/',
    token: token,
  );

  test(
    'a Claude Haiku task streams, uses a tool, and records its cost',
    () async {
      api.responses.addAll([
        (request) => api.stream(request, [
          _messageStart(input: 1200),
          ..._text(0, 'Listing the workspace.'),
          {
            'type': 'content_block_start',
            'index': 1,
            'content_block': {
              'type': 'tool_use',
              'id': 'toolu_list',
              'name': 'list_files',
              'input': <String, Object?>{},
            },
          },
          {
            'type': 'content_block_delta',
            'index': 1,
            'delta': {'type': 'input_json_delta', 'partial_json': '{}'},
          },
          {'type': 'content_block_stop', 'index': 1},
          _messageDelta('tool_use', output: 30),
          {'type': 'message_stop'},
        ]),
        (request) => api.stream(request, [
          _messageStart(input: 80, cacheRead: 1200),
          ..._text(0, 'The workspace contains README.md.'),
          _messageDelta('end_turn', output: 12),
          {'type': 'message_stop'},
        ]),
      ]);
      final observer = client();
      addTearDown(observer.close);
      final status = await observer.status();
      expect(status.selectedModelId, 'anthropic:claude-haiku-4-5');
      expect(
        status.selectedModelSummary,
        'Anthropic · claude-haiku-4-5 · Anthropic API key',
      );
      final io = _Io();

      final result = await TerminalChat(
        client: client(),
        io: io,
      ).run(initialMessage: 'What is in this workspace?');

      expect(result, 0, reason: io.errors.join('\n'));
      final output = io.output.join();
      expect(
        output,
        contains('Anthropic · claude-haiku-4-5 · Anthropic API key'),
      );
      expect(output, contains('[model output] Listing the workspace.'));
      expect(output, contains('[list_files] list_files started'));
      expect(output, contains('[list_files] list_files completed'));
      expect(
        output,
        contains(
          '[usage] Anthropic · claude-haiku-4-5 · Anthropic API key · '
          '2,480 input (1,200 cache read, 0 cache write) · 42 output · '
          '\$0.0016',
        ),
      );
      expect(output, contains('[dextero] The workspace contains README.md.'));

      expect(api.headers.map((headers) => headers['x-api-key']).toSet(), {
        'sk-ant-acceptance-secret',
      });
      final followUp = api.bodies.last;
      expect(followUp['model'], 'claude-haiku-4-5');
      expect(followUp['stream'], isTrue);
      final messages = followUp['messages']! as List;
      final toolResult =
          ((messages.last as Map)['content']! as List).single as Map;
      expect(toolResult['tool_use_id'], 'toolu_list');
      expect(toolResult['content'], contains('README.md'));
      final history = await store.history(conversationId);
      expect(
        history.singleWhere((entry) => entry.kind == ChatEntryKind.usage).usage,
        isA<ChatRunUsage>()
            .having((usage) => usage.modelRequests, 'requests', 2)
            .having((usage) => usage.costMicrosUsd, 'cost', 1610),
      );
      for (final entry in history) {
        expect(entry.content, isNot(contains('sk-ant-acceptance-secret')));
      }
    },
  );

  test('out-of-credit is shown as its own state, not retried', () async {
    api.responses.add(
      (request) => api.error(request, 400, {
        'type': 'error',
        'error': {
          'type': 'invalid_request_error',
          'message':
              'Your credit balance is too low to access the Anthropic API. '
              'Please go to Plans & Billing to upgrade or purchase credits.',
        },
      }),
    );
    final io = _Io();

    final result = await TerminalChat(
      client: client(),
      io: io,
    ).run(initialMessage: 'Hello');

    expect(result, 1);
    expect(
      io.output.join(),
      contains('[out of credit] Out of Anthropic API credit: Your credit'),
    );
    expect(io.output.join(), contains('Anthropic Console'));
    expect(api.bodies, hasLength(1));
  });

  test('cancelling from another client closes the API stream', () async {
    final opened = Completer<void>();
    final closed = Completer<void>();
    api.responses.add((request) async {
      // A detached socket reports the client hanging up; HttpResponse
      // writes keep succeeding after the peer has gone.
      final socket = await request.response.detachSocket(writeHeaders: false);
      void send(String event) {
        socket.write('${utf8.encode(event).length.toRadixString(16)}\r\n');
        socket.write('$event\r\n');
      }

      socket.write(
        'HTTP/1.1 200 OK\r\ncontent-type: text/event-stream\r\n'
        'transfer-encoding: chunked\r\n\r\n',
      );
      send('data: ${jsonEncode(_messageStart())}\n\n');
      final pings = Timer.periodic(
        const Duration(milliseconds: 50),
        (_) => send('data: {"type":"ping"}\n\n'),
      );
      void hungUp() {
        pings.cancel();
        if (!closed.isCompleted) closed.complete();
      }

      socket.listen((_) {}, onDone: hungUp, onError: (Object _) => hungUp());
      opened.complete();
    });
    final io = _Io();
    final running = TerminalChat(
      client: client(),
      io: io,
    ).run(initialMessage: 'Long task');
    await opened.future;
    final runId = (await store.history(
      conversationId,
    )).firstWhere((entry) => entry.kind == ChatEntryKind.userMessage).runId!;

    final canceller = client();
    expect(await canceller.cancelRun(conversationId, runId), isTrue);
    await canceller.close();

    expect(await running, 1);
    expect(io.output.join(), contains('[cancelled] Response cancelled'));
    await closed.future.timeout(const Duration(seconds: 5));
  });
}

JsonMap _messageStart({int input = 10, int cacheRead = 0}) => {
  'type': 'message_start',
  'message': {
    'id': 'msg_acceptance',
    'model': 'claude-haiku-4-5',
    'usage': {
      'input_tokens': input,
      'cache_creation_input_tokens': 0,
      'cache_read_input_tokens': cacheRead,
      'output_tokens': 1,
    },
  },
};

List<JsonMap> _text(int index, String text) => [
  {
    'type': 'content_block_start',
    'index': index,
    'content_block': {'type': 'text', 'text': ''},
  },
  {
    'type': 'content_block_delta',
    'index': index,
    'delta': {'type': 'text_delta', 'text': text},
  },
  {'type': 'content_block_stop', 'index': index},
];

JsonMap _messageDelta(String stopReason, {required int output}) => {
  'type': 'message_delta',
  'delta': {'stop_reason': stopReason},
  'usage': {'output_tokens': output},
};

typedef _Responder = Future<void> Function(HttpRequest request);

final class _FakeMessagesApi {
  _FakeMessagesApi._(this._server) {
    _server.listen((request) async {
      headers.add({
        for (final name in ['x-api-key', 'anthropic-version'])
          name: request.headers.value(name),
      });
      bodies.add(jsonDecode(await utf8.decodeStream(request)) as JsonMap);
      if (request.uri.path != '/v1/messages' || responses.isEmpty) {
        request.response.statusCode = 500;
        await request.response.close();
        return;
      }
      await responses.removeAt(0)(request);
    });
  }

  static Future<_FakeMessagesApi> start() async => _FakeMessagesApi._(
    await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
  );

  final HttpServer _server;
  final responses = <_Responder>[];
  final headers = <Map<String, String?>>[];
  final bodies = <JsonMap>[];

  int get port => _server.port;

  Future<void> stream(HttpRequest request, List<JsonMap> events) async {
    request.response
      ..bufferOutput = false
      ..headers.contentType = ContentType('text', 'event-stream');
    for (final event in events) {
      request.response.write(
        'event: ${event['type']}\ndata: ${jsonEncode(event)}\n\n',
      );
    }
    await request.response.close();
  }

  Future<void> error(HttpRequest request, int status, JsonMap body) async {
    request.response
      ..statusCode = status
      ..headers.contentType = ContentType.json
      ..headers.set('request-id', 'req_acceptance')
      ..write(jsonEncode(body));
    await request.response.close();
  }

  Future<void> close() => _server.close(force: true);
}

final class _Io implements TerminalIo {
  final output = <String>[];
  final errors = <String>[];
  @override
  bool get hasInputTerminal => false;
  @override
  bool get hasOutputTerminal => false;
  @override
  String? readLine() => null;
  @override
  void write(String value) => output.add(value);
  @override
  void writeln(String value) => output.add('$value\n');
  @override
  void error(String value) => errors.add(value);
}
