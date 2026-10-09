import 'dart:async';
import 'dart:convert';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('runs a Dextero tool through the CLI control protocol', () async {
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      final tools = await cli.mcp({'method': 'tools/list', 'id': 1});
      expect((tools['result']! as JsonMap)['tools'], [
        {
          'name': 'echo',
          'description': 'Echo a value.',
          'inputSchema': {'type': 'object'},
        },
      ]);
      cli.toolUse('toolu_1', 'mcp__dextero__echo', {'value': 'hello'});
      final permission = await cli.canUseTool('toolu_1', 'mcp__dextero__echo', {
        'value': 'hello',
      });
      expect(permission, {
        'behavior': 'allow',
        'updatedInput': {'value': 'hello'},
      });
      final call = await cli.callTool('toolu_1', 'echo', {'value': 'hello'});
      expect(call['result'], {
        'content': [
          {
            'type': 'text',
            'text': jsonEncode({'echo': 'hello'}),
          },
        ],
        'isError': false,
      });
      cli.textDelta('The tool ');
      cli.textDelta('said hello.');
      cli.result('The tool said hello.');
    });
    final events = <ConversationAgentEvent>[];

    final result = await _agent(cli).run(
      'say hello',
      onEvent: events.add,
      cancellationToken: CancellationController().token,
    );

    expect(result.output, 'The tool said hello.');
    expect(cli.closed, isTrue);
    expect(cli.arguments, containsAllInOrder(['--model', 'opus']));
    expect(cli.arguments, containsAllInOrder(['--tools', '']));
    expect(
      cli.arguments,
      containsAllInOrder(['--permission-prompt-tool', 'stdio']),
    );
    expect(
      cli.arguments,
      containsAll(['--safe-mode', '--strict-mcp-config', '--session-id']),
    );
    expect(cli.arguments, isNot(contains('--resume')));
    final initialize = cli.sent.first;
    expect(initialize['request'], {
      'subtype': 'initialize',
      'sdkMcpServers': ['dextero'],
    });
    expect(
      events.map((event) => event.kind),
      containsAllInOrder([
        ConversationAgentEventKind.lifecycle,
        ConversationAgentEventKind.toolCallStarted,
        ConversationAgentEventKind.toolCallCompleted,
        ConversationAgentEventKind.assistantDelta,
        ConversationAgentEventKind.assistantDelta,
      ]),
    );
    expect(
      events.first.summary.text,
      'Claude Code is working · claude-opus-5-5 · '
      'local Claude Code subscription',
    );
    final started = events.where(
      (event) => event.kind == ConversationAgentEventKind.toolCallStarted,
    );
    expect(started.single.toolName, 'echo');
    expect(started.single.toolCallId, 'toolu_1');
  });

  test('denies Claude Code tools outside the Dextero harness', () async {
    late JsonMap permission;
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      cli.toolUse('toolu_bash', 'Bash', {'command': 'rm -rf /'});
      permission = await cli.canUseTool('toolu_bash', 'Bash', {
        'command': 'rm -rf /',
      });
      cli.result('I was not allowed to run that.');
    });
    final events = <ConversationAgentEvent>[];

    await _agent(cli).run(
      'clean up',
      onEvent: events.add,
      cancellationToken: CancellationController().token,
    );

    expect(permission, {
      'behavior': 'deny',
      'message': 'Dextero only permits its own harness tools.',
    });
    final completed = events.singleWhere(
      (event) => event.kind == ConversationAgentEventKind.toolCallCompleted,
    );
    expect(completed.toolName, 'Bash');
    expect(completed.success, isFalse);
  });

  test('a denied Dextero approval stops the gated tool', () async {
    late JsonMap permission;
    final edit = _RecordingTool('edit_file');
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      permission = await cli.canUseTool(
        'toolu_edit',
        'mcp__dextero__edit_file',
        {'path': 'a.txt'},
      );
      cli.result('The edit was declined.');
    });
    final approvals = <ToolApprovalRequest>[];

    await _agent(cli, tools: [edit]).runWithApproval(
      'edit',
      onEvent: (_) {},
      cancellationToken: CancellationController().token,
      onApprovalRequest: (request) async {
        approvals.add(request);
        return false;
      },
    );

    expect(approvals.single.toolName, 'edit_file');
    expect(approvals.single.toolCallId, 'toolu_edit');
    expect(permission, {
      'behavior': 'deny',
      'message': 'edit_file was not approved.',
    });
    expect(edit.calls, isEmpty);
  });

  test('an approved gated tool runs once without a second approval', () async {
    final edit = _RecordingTool('edit_file');
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      await cli.canUseTool('toolu_edit', 'mcp__dextero__edit_file', {
        'path': 'a.txt',
      });
      final call = await cli.callTool('toolu_edit', 'edit_file', {
        'path': 'a.txt',
      });
      expect((call['result']! as JsonMap)['isError'], isFalse);
      cli.result('Edited.');
    });
    var approvals = 0;

    await _agent(cli, tools: [edit]).runWithApproval(
      'edit',
      onEvent: (_) {},
      cancellationToken: CancellationController().token,
      onApprovalRequest: (_) async {
        approvals++;
        return true;
      },
    );

    expect(approvals, 1);
    expect(edit.calls, [
      {'path': 'a.txt'},
    ]);
  });

  test('a gated tool call that skipped the permission prompt still needs '
      'Dextero approval', () async {
    final edit = _RecordingTool('edit_file');
    late JsonMap call;
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      call = await cli.callTool('toolu_edit', 'edit_file', {'path': 'a.txt'});
      cli.result('Done.');
    });

    await _agent(cli, tools: [edit]).runWithApproval(
      'edit',
      onEvent: (_) {},
      cancellationToken: CancellationController().token,
      onApprovalRequest: (_) async => false,
    );

    expect(edit.calls, isEmpty);
    expect(call['result'], {
      'content': [
        {'type': 'text', 'text': 'edit_file was not approved.'},
      ],
      'isError': true,
    });
  });

  test('cancellation during approval interrupts and closes the CLI', () async {
    final controller = CancellationController();
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      unawaited(
        cli.canUseTool('toolu_edit', 'mcp__dextero__edit_file', {
          'path': 'a.txt',
        }),
      );
    });

    final run = _agent(cli, tools: [_RecordingTool('edit_file')])
        .runWithApproval(
          'edit',
          onEvent: (_) {},
          cancellationToken: controller.token,
          onApprovalRequest: (_) {
            controller.cancel();
            return Completer<bool>().future;
          },
        );

    await expectLater(run, throwsA(isA<RunCancelledException>()));
    expect(cli.closed, isTrue);
    expect(
      cli.sent.map((message) => message['request']),
      contains(equals({'subtype': 'interrupt'})),
    );
  });

  test('cancellation while streaming interrupts the turn', () async {
    final controller = CancellationController();
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      cli.textDelta('1\n2\n');
    });

    final run = _agent(cli).run(
      'count',
      onEvent: (event) {
        if (event.kind == ConversationAgentEventKind.assistantDelta) {
          controller.cancel();
        }
      },
      cancellationToken: controller.token,
    );

    await expectLater(run, throwsA(isA<RunCancelledException>()));
    expect(cli.closed, isTrue);
    expect(
      cli.sent.map((message) => message['request']),
      contains(equals({'subtype': 'interrupt'})),
    );
  });

  test('later runs resume the same Claude Code session', () async {
    final clis = <_FakeClaudeCli>[];
    final agent = _newAgent(
      transportFactory: (arguments) async {
        final cli = _FakeClaudeCli((cli) async {
          await cli.startSession();
          cli.result('ok');
        });
        clis.add(cli);
        return cli.start(arguments);
      },
    );

    for (final prompt in ['remember heron', 'what was it?']) {
      await agent.run(
        prompt,
        onEvent: (_) {},
        cancellationToken: CancellationController().token,
      );
    }

    expect(
      clis[0].arguments,
      containsAllInOrder(['--session-id', agent.sessionId]),
    );
    expect(
      clis[1].arguments,
      containsAllInOrder(['--resume', agent.sessionId]),
    );
    expect(clis[1].arguments, isNot(contains('--session-id')));
  });

  test('maps an authentication failure to a structured error', () async {
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      cli.emit({
        'type': 'result',
        'subtype': 'success',
        'is_error': true,
        'api_error_status': 401,
        'result': 'Invalid bearer token raw-secret-value',
      });
    });

    final run = _agent(cli).run(
      'hi',
      onEvent: (_) {},
      cancellationToken: CancellationController().token,
    );

    await expectLater(
      run,
      throwsA(
        isA<ClaudeCodeException>()
            .having((e) => e.kind, 'kind', ClaudeCodeErrorKind.authentication)
            .having((e) => e.message, 'message', contains('claude auth login'))
            .having(
              (e) => e.message,
              'message',
              isNot(contains('raw-secret-value')),
            ),
      ),
    );
    expect(cli.closed, isTrue);
  });

  test('reports a CLI exit before the result with stderr context', () async {
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      cli.diagnosticsText = 'Error: model not found';
      await cli.exit();
    });

    final run = _agent(cli).run(
      'hi',
      onEvent: (_) {},
      cancellationToken: CancellationController().token,
    );

    await expectLater(
      run,
      throwsA(
        isA<ClaudeCodeException>()
            .having((e) => e.kind, 'kind', ClaudeCodeErrorKind.processExited)
            .having((e) => e.message, 'message', contains('model not found')),
      ),
    );
  });

  test('rejects unsupported control requests without stalling', () async {
    late JsonMap response;
    final cli = _FakeClaudeCli((cli) async {
      await cli.startSession();
      response = await cli.control({'subtype': 'hook_callback'});
      cli.result('ok');
    });

    await _agent(cli).run(
      'hi',
      onEvent: (_) {},
      cancellationToken: CancellationController().token,
    );

    expect(response['subtype'], 'error');
  });

  group('availability', () {
    test('reports a subscription login as the auth source', () {
      final availability = ClaudeCodeAvailability.fromAuthStatus(
        0,
        jsonEncode({'loggedIn': true, 'authMethod': 'claude.ai'}),
      );

      expect(availability.available, isTrue);
      expect(availability.authSource, 'local Claude Code subscription');
    });

    test('is unavailable when the CLI is not logged in', () {
      final availability = ClaudeCodeAvailability.fromAuthStatus(
        1,
        jsonEncode({'loggedIn': false}),
      );

      expect(availability.available, isFalse);
      expect(availability.reason, contains('claude auth login'));
    });

    test('keeps API keys out of the CLI environment', () {
      final environment = claudeCodeProcessEnvironment({
        'PATH': '/bin',
        'HOME': '/home/me',
        'ANTHROPIC_API_KEY': 'secret',
        'CLAUDE_CONFIG_DIR': '/home/me/.claude-alt',
      });

      expect(environment, {
        'PATH': '/bin',
        'HOME': '/home/me',
        'CLAUDE_CONFIG_DIR': '/home/me/.claude-alt',
      });
    });
  });
}

ClaudeCodeConversationAgent _agent(_FakeClaudeCli cli, {List<Tool>? tools}) =>
    _newAgent(
      tools: tools,
      transportFactory: (arguments) async => cli.start(arguments),
    );

ClaudeCodeConversationAgent _newAgent({
  List<Tool>? tools,
  required ClaudeCodeTransportFactory transportFactory,
}) => ClaudeCodeConversationAgent(
  model: 'opus',
  workingDirectory: '/workspace',
  tools: tools ?? [_EchoTool()],
  transportFactory: transportFactory,
  messageTimeout: const Duration(seconds: 5),
);

/// A reactive stand-in for `claude --print` speaking stream-json.
final class _FakeClaudeCli implements ClaudeCodeTransport {
  _FakeClaudeCli(this._script);

  final Future<void> Function(_FakeClaudeCli cli) _script;
  final _output = StreamController<JsonMap>();
  final sent = <JsonMap>[];
  final _unread = <JsonMap>[];
  final _waiters = <(bool Function(JsonMap), Completer<JsonMap>)>[];
  var arguments = const <String>[];
  var closed = false;
  var diagnosticsText = '';
  var _requests = 0;

  _FakeClaudeCli start(List<String> arguments) {
    this.arguments = arguments;
    unawaited(_script(this));
    return this;
  }

  @override
  Stream<JsonMap> get messages => _output.stream;

  @override
  String get diagnostics => diagnosticsText;

  @override
  Future<void> send(JsonMap message) async {
    if (closed) throw StateError('closed');
    final copy = jsonDecode(jsonEncode(message)) as JsonMap;
    sent.add(copy);
    for (final waiter in _waiters) {
      if (waiter.$1(copy)) {
        _waiters.remove(waiter);
        waiter.$2.complete(copy);
        return;
      }
    }
    _unread.add(copy);
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_output.isClosed) await _output.close();
  }

  Future<void> exit() => _output.close();

  void emit(JsonMap message) {
    if (!_output.isClosed) _output.add(message);
  }

  Future<JsonMap> fromHost(bool Function(JsonMap) test) {
    for (final message in _unread) {
      if (test(message)) {
        _unread.remove(message);
        return Future.value(message);
      }
    }
    final completer = Completer<JsonMap>();
    _waiters.add((test, completer));
    return completer.future;
  }

  /// Acknowledges initialization, accepts the prompt, and connects MCP.
  Future<void> startSession() async {
    final initialize = await fromHost(
      (message) => message['type'] == 'control_request',
    );
    emit({
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': initialize['request_id'],
        'response': {'commands': <Object?>[]},
      },
    });
    await fromHost((message) => message['type'] == 'user');
    final mcpInitialize = await mcp({
      'method': 'initialize',
      'id': 0,
      'params': {'protocolVersion': '2025-11-25'},
    });
    expect(
      (mcpInitialize['result']! as JsonMap)['protocolVersion'],
      '2025-11-25',
    );
    await mcp({'method': 'notifications/initialized'});
    emit({
      'type': 'system',
      'subtype': 'init',
      'model': 'claude-opus-5-5',
      'session_id': 'cli-session',
      'apiKeySource': 'none',
    });
  }

  Future<JsonMap> control(JsonMap request) async {
    final id = 'cli-${++_requests}';
    final response = fromHost(
      (message) =>
          message['type'] == 'control_response' &&
          (message['response']! as JsonMap)['request_id'] == id,
    );
    emit({'type': 'control_request', 'request_id': id, 'request': request});
    return (await response)['response']! as JsonMap;
  }

  Future<JsonMap> mcp(JsonMap message) async {
    final response = await control({
      'subtype': 'mcp_message',
      'server_name': 'dextero',
      'message': {'jsonrpc': '2.0', ...message},
    });
    return (response['response']! as JsonMap)['mcp_response']! as JsonMap;
  }

  Future<JsonMap> canUseTool(String id, String name, JsonMap input) async =>
      (await control({
            'subtype': 'can_use_tool',
            'tool_name': name,
            'input': input,
            'tool_use_id': id,
          }))['response']!
          as JsonMap;

  Future<JsonMap> callTool(String id, String name, JsonMap arguments) => mcp({
    'method': 'tools/call',
    'id': 2,
    'params': {
      'name': name,
      'arguments': arguments,
      '_meta': {'claudecode/toolUseId': id},
    },
  });

  void toolUse(String id, String name, JsonMap input) => emit({
    'type': 'assistant',
    'parent_tool_use_id': null,
    'message': {
      'role': 'assistant',
      'content': [
        {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
      ],
    },
  });

  void textDelta(String text) => emit({
    'type': 'stream_event',
    'parent_tool_use_id': null,
    'event': {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': text},
    },
  });

  void result(String text) => emit({
    'type': 'result',
    'subtype': 'success',
    'is_error': false,
    'result': text,
    'session_id': 'cli-session',
  });
}

final class _EchoTool implements Tool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'echo',
    description: 'Echo a value.',
    inputSchema: {'type': 'object'},
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
  final calls = <JsonMap>[];

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
    calls.add(arguments);
    return 'ok';
  }
}
