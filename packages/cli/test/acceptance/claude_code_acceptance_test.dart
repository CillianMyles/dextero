import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_core/dextero_core.dart';
import 'package:dextero_server/dextero_client.dart' as protocol;
import 'package:dextero_server/dextero_server.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late InMemoryChatHistoryStore store;
  late ChatService service;
  late String conversationId;
  late List<_ClaudeCli> clis;
  late ServerpodTerminalChatClient observer;
  late int port;
  const token = 'claude-acceptance-token-0123456789012345678901';

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('dextero-claude-');
    await File('${workspace.path}/hello.txt').writeAsString('hi');
    clis = [];
    final configuration = AgentRuntimeConfiguration.fromEnvironment(
      const {},
      claudeCode: const ClaudeCodeAvailability.available(),
    );
    ConversationAgent agentFor(String id) {
      final option = configuration.availableOptions.singleWhere(
        (option) => option.id == id,
      );
      return configuration.createAgent(
        workspace: workspace.path,
        provider: option.provider,
        modelName: option.modelName,
        codexTransportFactory: () => throw StateError('Codex was not chosen'),
        claudeTransportFactory: (arguments) async {
          final cli = _ClaudeCli(arguments);
          clis.add(cli);
          return cli;
        },
      );
    }

    store = InMemoryChatHistoryStore();
    service = ChatService(
      store: store,
      agent: agentFor(configuration.selectedModelId),
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
      modelSelector: (id) => service.selectAgent(
        conversationId: conversationId,
        agent: agentFor(id),
      ),
    );
    observer = ServerpodTerminalChatClient(
      serverUrl: 'http://localhost:$port/',
      token: token,
    );
    addTearDown(() async {
      await observer.close();
      await pod.shutdown(exitProcess: false);
      await store.close();
      await workspace.delete(recursive: true);
    });
  });

  test('CLI runs a bounded Claude Code task with streamed receipts', () async {
    final initial = await observer.status();
    final claude = initial.modelOptions.singleWhere(
      (option) => option.id == 'claude:opus',
    );
    expect(claude.authSource, 'local Claude Code subscription');
    final io = _Io();

    final result = await TerminalChat(
      client: ServerpodTerminalChatClient(
        serverUrl: 'http://localhost:$port/',
        token: token,
      ),
      io: io,
    ).run(initialMessage: 'List the workspace files', modelName: 'claude:opus');

    expect(result, 0, reason: io.errors.join('\n'));
    final cli = clis.single;
    expect(cli.arguments, containsAllInOrder(['--model', 'opus']));
    expect(cli.arguments, containsAllInOrder(['--tools', '']));
    expect(cli.listedTools, hasLength(5));
    expect(cli.bashPermission, {
      'behavior': 'deny',
      'message': 'Dextero only permits its own harness tools.',
    });
    expect(cli.listFilesOutput, contains('hello.txt'));
    expect(cli.closed, isTrue);

    final history = await store.history(conversationId);
    String contentOf(ChatEntryKind kind) =>
        history.firstWhere((entry) => entry.kind == kind).content;
    expect(
      history.map((entry) => entry.content),
      contains(
        'Claude Code is working · claude-opus-5-5 · '
        'local Claude Code subscription',
      ),
    );
    expect(
      history
          .where((entry) => entry.kind == ChatEntryKind.toolResult)
          .map((entry) => (entry.toolName, entry.status)),
      containsAll([
        ('list_files', ChatEntryStatus.completed),
        ('Bash', ChatEntryStatus.failed),
      ]),
    );
    expect(
      history.where((entry) => entry.kind == ChatEntryKind.assistantDelta),
      isNotEmpty,
    );
    expect(
      contentOf(ChatEntryKind.assistantMessage),
      'The workspace contains hello.txt.',
    );
    expect(history.last.content, 'Response completed');
  });

  test('cancelling over HTTP interrupts a pending Claude approval', () async {
    await observer.selectModel('claude:opus');
    final submission = await observer.submit(
      protocol.ChatSubmitRequest(
        conversationId: conversationId,
        message: 'Edit hello.txt',
        modelName: 'opus',
        modelProvider: 'claude',
      ),
    );
    await _waitFor(
      () async => (await store.history(conversationId)).any(
        (entry) =>
            entry.kind == ChatEntryKind.approval &&
            entry.status == ChatEntryStatus.pending,
      ),
    );

    expect(await observer.cancelRun(conversationId, submission.runId), isTrue);
    await _waitFor(
      () async => (await store.history(
        conversationId,
      )).any((entry) => entry.content == 'Response cancelled'),
    );

    final cli = clis.single;
    await _waitFor(() async => cli.closed);
    expect(cli.interrupted, isTrue);
    expect(await File('${workspace.path}/hello.txt').readAsString(), 'hi');
  });
}

Future<void> _waitFor(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) fail('Timed out waiting.');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// A stand-in for `claude --print` driving the stream-json control protocol.
///
/// "List" prompts call list_files and attempt Bash; "Edit" prompts request
/// edit_file permission and then wait.
final class _ClaudeCli implements ClaudeCodeTransport {
  _ClaudeCli(this.arguments);

  final List<String> arguments;
  final _output = StreamController<JsonMap>();
  final _responses = <String, Completer<JsonMap>>{};
  var _requests = 0;
  var closed = false;
  var interrupted = false;
  List<Object?> listedTools = const [];
  JsonMap? bashPermission;
  String? listFilesOutput;

  @override
  Stream<JsonMap> get messages => _output.stream;

  @override
  String get diagnostics => '';

  @override
  Future<void> send(JsonMap message) async {
    final copy = jsonDecode(jsonEncode(message)) as JsonMap;
    switch (copy['type']) {
      case 'control_request':
        final request = copy['request']! as JsonMap;
        if (request['subtype'] == 'interrupt') interrupted = true;
        _emit({
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': copy['request_id'],
            'response': <String, Object?>{},
          },
        });
      case 'control_response':
        final response = copy['response']! as JsonMap;
        _responses.remove(response['request_id'])?.complete(response);
      case 'user':
        final content = (copy['message']! as JsonMap)['content']! as String;
        unawaited(_turn(content));
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_output.isClosed) await _output.close();
  }

  void _emit(JsonMap message) {
    if (!_output.isClosed) _output.add(message);
  }

  Future<JsonMap> _control(JsonMap request) {
    final id = 'cli-${++_requests}';
    final completer = _responses[id] = Completer<JsonMap>();
    _emit({'type': 'control_request', 'request_id': id, 'request': request});
    return completer.future.then(
      (response) => response['response']! as JsonMap,
    );
  }

  Future<JsonMap> _mcp(JsonMap message) async =>
      (await _control({
            'subtype': 'mcp_message',
            'server_name': 'dextero',
            'message': {'jsonrpc': '2.0', ...message},
          }))['mcp_response']!
          as JsonMap;

  Future<void> _turn(String prompt) async {
    await _mcp({
      'method': 'initialize',
      'id': 0,
      'params': {'protocolVersion': '2025-11-25'},
    });
    final list = await _mcp({'method': 'tools/list', 'id': 1});
    listedTools = (list['result']! as JsonMap)['tools']! as List;
    _emit({
      'type': 'system',
      'subtype': 'init',
      'model': 'claude-opus-5-5',
      'session_id': 'session-test',
    });
    if (prompt.startsWith('Edit')) {
      await _control({
        'subtype': 'can_use_tool',
        'tool_name': 'mcp__dextero__edit_file',
        'tool_use_id': 'toolu_edit',
        'input': {'path': 'hello.txt', 'old_text': 'hi', 'new_text': 'bye'},
      });
      return;
    }
    await _control({
      'subtype': 'can_use_tool',
      'tool_name': 'mcp__dextero__list_files',
      'tool_use_id': 'toolu_list',
      'input': {'path': '.'},
    });
    final call = await _mcp({
      'method': 'tools/call',
      'id': 2,
      'params': {
        'name': 'list_files',
        'arguments': {'path': '.'},
        '_meta': {'claudecode/toolUseId': 'toolu_list'},
      },
    });
    final content = (call['result']! as JsonMap)['content']! as List;
    listFilesOutput = (content.single as JsonMap)['text'] as String;
    bashPermission = await _control({
      'subtype': 'can_use_tool',
      'tool_name': 'Bash',
      'tool_use_id': 'toolu_bash',
      'input': {'command': 'ls'},
    });
    for (final text in ['The workspace ', 'contains hello.txt.']) {
      _emit({
        'type': 'stream_event',
        'parent_tool_use_id': null,
        'event': {
          'type': 'content_block_delta',
          'delta': {'type': 'text_delta', 'text': text},
        },
      });
    }
    _emit({
      'type': 'result',
      'subtype': 'success',
      'is_error': false,
      'result': 'The workspace contains hello.txt.',
    });
  }
}

final class _Io implements TerminalIo {
  final errors = <String>[];
  @override
  bool get hasInputTerminal => false;
  @override
  bool get hasOutputTerminal => false;
  @override
  String? readLine() => null;
  @override
  void write(String value) {}
  @override
  void writeln(String value) {}
  @override
  void error(String value) => errors.add(value);
}
