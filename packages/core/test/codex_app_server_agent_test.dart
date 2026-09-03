import 'dart:async';
import 'dart:convert';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test('bridges app-server subscription auth to a dynamic tool', () async {
    final transport = _ScriptedTransport(toolName: 'echo');
    final agent = CodexAppServerAgent(
      model: 'test-model',
      workingDirectory: '/workspace',
      transportFactory: () async => transport,
    );

    final run = await agent.run('say hello', tools: [_EchoTool()]);

    expect(run.output, 'The tool said hello.');
    expect(run.threadId, 'thread-1');
    expect(run.turnId, 'turn-1');
    expect(run.toolCalls, 1);
    expect(transport.closed, isTrue);
    final initialize = transport.sent[0];
    expect((initialize['params']! as JsonMap)['capabilities'], {
      'experimentalApi': true,
    });
    final threadStart = transport.sent.singleWhere(
      (message) => message['method'] == 'thread/start',
    );
    final params = threadStart['params']! as JsonMap;
    expect(params['model'], 'test-model');
    expect(params['cwd'], '/workspace');
    expect(params['ephemeral'], isTrue);
    expect(params['sandbox'], 'read-only');
    expect(params['approvalPolicy'], 'never');
    expect(
      params['developerInstructions'],
      contains(
        'Use run_command for normal CLI execution. Use run_shell only when '
        'shell syntax is required.',
      ),
    );
    expect(params['dynamicTools'], [
      {
        'type': 'function',
        'name': 'echo',
        'description': 'Echo a value.',
        'inputSchema': {'type': 'object'},
      },
    ]);
    final toolResponse = transport.sent.singleWhere(
      (message) => message['id'] == 'tool-request-1',
    );
    expect(toolResponse['result'], {
      'contentItems': [
        {
          'type': 'inputText',
          'text': jsonEncode({'echo': 'hello'}),
        },
      ],
      'success': true,
    });
  });

  test('adapts real item and dynamic-tool activity without raw data', () async {
    final transport = _ScriptedTransport(toolName: 'echo');
    final activities = <CodexAgentActivity>[];

    await CodexAppServerAgent(
      transportFactory: () async => transport,
    ).run('go', tools: [_EchoTool()], onActivity: activities.add);

    expect(
      activities.map((activity) => activity.kind),
      containsAllInOrder([
        CodexAgentActivityKind.lifecycle,
        CodexAgentActivityKind.toolCallStarted,
        CodexAgentActivityKind.toolCallCompleted,
        CodexAgentActivityKind.toolOutput,
        CodexAgentActivityKind.assistantDelta,
        CodexAgentActivityKind.assistantMessage,
      ]),
    );
    expect(
      activities
          .where((activity) => activity.toolCallId == 'call-1')
          .map((activity) => activity.kind),
      [
        CodexAgentActivityKind.toolCallStarted,
        CodexAgentActivityKind.toolCallCompleted,
        CodexAgentActivityKind.toolOutput,
      ],
    );
    final rendered = activities.map((activity) => activity.summary.text).join();
    expect(rendered, isNot(contains('raw-secret-value')));
    expect(rendered, isNot(contains('raw result')));
    expect(rendered, isNot(contains(jsonEncode({'echo': 'hello'}))));
  });

  test('preserves multiline app-server assistant messages', () async {
    final transport = _ScriptedTransport(
      toolName: 'echo',
      output: 'Summary\n\n```dart\nprint(1);\n```',
    );
    final activities = <CodexAgentActivity>[];

    final run = await CodexAppServerAgent(
      transportFactory: () async => transport,
    ).run('go', tools: [_EchoTool()], onActivity: activities.add);

    expect(run.output, 'Summary\n\n```dart\nprint(1);\n```');
    expect(
      activities
          .singleWhere(
            (activity) =>
                activity.kind == CodexAgentActivityKind.assistantMessage,
          )
          .summary
          .text,
      'Summary\n\n```dart\nprint(1);\n```',
    );
  });

  test('returns tool failures to app-server as unsuccessful results', () async {
    final transport = _ScriptedTransport(toolName: 'fail');
    final activities = <CodexAgentActivity>[];
    final run = await CodexAppServerAgent(
      transportFactory: () async => transport,
    ).run('try it', tools: [_FailingTool()], onActivity: activities.add);

    expect(run.output, 'The tool failed safely.');
    final toolResponse = transport.sent.singleWhere(
      (message) => message['id'] == 'tool-request-1',
    );
    final result = toolResponse['result']! as JsonMap;
    expect(result['success'], isFalse);
    expect(
      ((result['contentItems']! as List).single as JsonMap)['text'],
      contains('tool exploded'),
    );
    expect(
      activities
          .singleWhere(
            (activity) =>
                activity.kind == CodexAgentActivityKind.toolCallCompleted,
          )
          .summary
          .text,
      'fail failed: Bad state: tool exploded',
    );
  });

  test('waits for approval before calling a gated dynamic tool', () async {
    final transport = _ScriptedTransport(
      toolName: 'edit_file',
      arguments: const {
        'path': 'README.md',
        'oldText': 'old heading',
        'newText': 'new heading',
      },
    );
    final tool = _CountingEditTool();
    final requested = Completer<ToolApprovalRequest>();
    final approval = Completer<bool>();

    final future = CodexAppServerAgent(transportFactory: () async => transport)
        .run(
          'edit it',
          tools: [tool],
          approvalRequiredTools: const {'edit_file'},
          onApprovalRequest: (request) {
            requested.complete(request);
            return approval.future;
          },
        );
    final request = await requested.future;

    expect(request.toolCallId, 'call-1');
    expect(request.summary.text, contains('edit_file requires approval'));
    expect(request.summary.text, contains('-old heading'));
    expect(request.summary.text, contains('+new heading'));
    expect(tool.calls, 0);

    approval.complete(true);
    final run = await future;

    expect(run.output, 'The tool said hello.');
    expect(tool.calls, 1);
  });

  test('records a complete command and its bounded output', () async {
    final transport = _ScriptedTransport(
      toolName: 'run_command',
      arguments: const {
        'command': '/usr/bin/printf',
        'arguments': ['%s', 'token=super-secret'],
      },
    );
    final activities = <CodexAgentActivity>[];

    await CodexAppServerAgent(
      transportFactory: () async => transport,
    ).run('run it', tools: [_CommandTool()], onActivity: activities.add);

    final commandActivities = activities.where(
      (activity) => activity.toolCallId == 'call-1',
    );
    expect(
      commandActivities
          .singleWhere(
            (activity) =>
                activity.kind == CodexAgentActivityKind.toolCallStarted,
          )
          .summary
          .text,
      'run_command started: /usr/bin/printf %s token=super-secret',
    );
    final result = commandActivities
        .singleWhere(
          (activity) =>
              activity.kind == CodexAgentActivityKind.toolCallCompleted,
        )
        .summary;
    expect(result.text, contains('stdout:\ncommand output'));
    expect(result.text, contains('stderr:\nwarning'));
    expect(result.truncated, isFalse);
  });

  test('adapts built-in command execution details from app-server', () async {
    final activities = <CodexAgentActivity>[];

    await CodexAppServerAgent(
      transportFactory: () async => _CommandExecutionTransport(),
    ).run('run it', tools: const [], onActivity: activities.add);

    final commandActivities = activities.where(
      (activity) => activity.toolCallId == 'command-1',
    );
    expect(
      commandActivities
          .singleWhere(
            (activity) =>
                activity.kind == CodexAgentActivityKind.toolCallStarted,
          )
          .summary
          .text,
      'command_execution started: printf token=super-secret',
    );
    expect(
      commandActivities
          .singleWhere(
            (activity) =>
                activity.kind == CodexAgentActivityKind.toolCallCompleted,
          )
          .summary
          .text,
      contains('output:\nsafe output'),
    );
  });

  test('rejects an empty prompt before starting a process', () async {
    var started = false;
    final agent = CodexAppServerAgent(
      transportFactory: () async {
        started = true;
        return _ScriptedTransport(toolName: 'echo');
      },
    );

    await expectLater(agent.run('  ', tools: []), throwsArgumentError);
    expect(started, isFalse);
  });

  test('rejects duplicate tool names before starting a process', () async {
    var started = false;
    final agent = CodexAppServerAgent(
      transportFactory: () async {
        started = true;
        return _ScriptedTransport(toolName: 'echo');
      },
    );

    await expectLater(
      agent.run('go', tools: [_EchoTool(), _EchoTool()]),
      throwsArgumentError,
    );
    expect(started, isFalse);
  });

  test('surfaces an app-server JSON-RPC error and closes transport', () async {
    final transport = _InitializationErrorTransport();

    await expectLater(
      CodexAppServerAgent(
        transportFactory: () async => transport,
      ).run('go', tools: []),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('not authenticated'),
        ),
      ),
    );
    expect(transport.closed, isTrue);
  });

  test('fails a completed turn that has no final agent message', () async {
    final transport = _NoOutputTransport();

    await expectLater(
      CodexAppServerAgent(
        transportFactory: () async => transport,
      ).run('go', tools: []),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('without a final agent message'),
        ),
      ),
    );
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

final class _FailingTool implements Tool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'fail',
    description: 'Fail.',
    inputSchema: {'type': 'object'},
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) => throw StateError('tool exploded');
}

final class _CommandTool implements Tool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'run_command',
    description: 'Run a command.',
    inputSchema: {'type': 'object'},
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) => const {
    'exit_code': 0,
    'stdout': 'command output\n',
    'stderr': 'warning\n',
    'truncated': false,
  };
}

final class _CountingEditTool implements Tool {
  var calls = 0;

  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'edit_file',
    description: 'Edit a file.',
    inputSchema: {'type': 'object'},
  );

  @override
  Object? call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) {
    calls++;
    return {'path': arguments['path']};
  }
}

base class _FakeTransport implements CodexAppServerTransport {
  final _controller = StreamController<JsonMap>();
  final sent = <JsonMap>[];
  bool closed = false;

  @override
  Stream<JsonMap> get messages => _controller.stream;

  @override
  Future<void> send(JsonMap message) async {
    sent.add(message);
    respond(message);
  }

  void respond(JsonMap message) {}

  void emit(JsonMap message) => _controller.add(message);

  @override
  Future<void> close() async {
    closed = true;
    await _controller.close();
  }
}

final class _ScriptedTransport extends _FakeTransport {
  _ScriptedTransport({
    required this.toolName,
    this.output,
    this.arguments = const {'value': 'hello'},
  });

  final String toolName;
  final String? output;
  final JsonMap arguments;

  @override
  void respond(JsonMap message) {
    switch (message['method']) {
      case 'initialize':
        emit({'id': 0, 'result': <String, Object?>{}});
      case 'thread/start':
        emit({
          'id': 1,
          'result': {
            'thread': {'id': 'thread-1'},
          },
        });
      case 'turn/start':
        emit({
          'id': 2,
          'result': {
            'turn': {'id': 'turn-1'},
          },
        });
        emit({
          'method': 'item/started',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'startedAtMs': 1,
            'item': {
              'id': 'call-1',
              'type': 'dynamicToolCall',
              'tool': toolName,
              'arguments': arguments,
              'status': 'inProgress',
            },
          },
        });
        emit({
          'id': 'tool-request-1',
          'method': 'item/tool/call',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'callId': 'call-1',
            'tool': toolName,
            'arguments': arguments,
          },
        });
      case null:
        if (message['id'] != 'tool-request-1') return;
        emit({
          'method': 'item/commandExecution/outputDelta',
          'params': {'itemId': 'call-1', 'delta': 'raw incremental output'},
        });
        emit({
          'method': 'item/completed',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'completedAtMs': 2,
            'item': {
              'id': 'call-1',
              'type': 'dynamicToolCall',
              'tool': toolName,
              'arguments': {'token': 'raw-secret-value'},
              'status': 'completed',
              'success': true,
              'contentItems': [
                {'type': 'inputText', 'text': 'raw result'},
              ],
            },
          },
        });
        emit({
          'method': 'item/agentMessage/delta',
          'params': {'delta': 'The tool said '},
        });
        emit({
          'method': 'item/completed',
          'params': {
            'item': {
              'type': 'agentMessage',
              'text':
                  output ??
                  (toolName == 'fail'
                      ? 'The tool failed safely.'
                      : 'The tool said hello.'),
            },
          },
        });
        emit({
          'method': 'turn/completed',
          'params': {
            'turn': {'status': 'completed'},
          },
        });
    }
  }
}

final class _InitializationErrorTransport extends _FakeTransport {
  @override
  void respond(JsonMap message) {
    if (message['method'] == 'initialize') {
      emit({
        'id': 0,
        'error': {'code': 401, 'message': 'not authenticated'},
      });
    }
  }
}

final class _NoOutputTransport extends _FakeTransport {
  @override
  void respond(JsonMap message) {
    switch (message['method']) {
      case 'initialize':
        emit({'id': 0, 'result': <String, Object?>{}});
      case 'thread/start':
        emit({
          'id': 1,
          'result': {
            'thread': {'id': 'thread-1'},
          },
        });
      case 'turn/start':
        emit({
          'id': 2,
          'result': {
            'turn': {'id': 'turn-1'},
          },
        });
        emit({
          'method': 'turn/completed',
          'params': {
            'turn': {'status': 'completed'},
          },
        });
    }
  }
}

final class _CommandExecutionTransport extends _FakeTransport {
  @override
  void respond(JsonMap message) {
    switch (message['method']) {
      case 'initialize':
        emit({'id': 0, 'result': <String, Object?>{}});
      case 'thread/start':
        emit({
          'id': 1,
          'result': {
            'thread': {'id': 'thread-1'},
          },
        });
      case 'turn/start':
        emit({
          'id': 2,
          'result': {
            'turn': {'id': 'turn-1'},
          },
        });
        emit({
          'method': 'item/started',
          'params': {
            'item': {
              'id': 'command-1',
              'type': 'commandExecution',
              'command': 'printf token=super-secret',
              'status': 'inProgress',
            },
          },
        });
        emit({
          'method': 'item/completed',
          'params': {
            'item': {
              'id': 'command-1',
              'type': 'commandExecution',
              'command': 'printf token=super-secret',
              'aggregatedOutput': 'safe output\n',
              'exitCode': 0,
              'status': 'completed',
            },
          },
        });
        emit({
          'method': 'item/completed',
          'params': {
            'item': {
              'id': 'message-1',
              'type': 'agentMessage',
              'text': 'Done.',
            },
          },
        });
        emit({
          'method': 'turn/completed',
          'params': {
            'turn': {'status': 'completed'},
          },
        });
    }
  }
}
