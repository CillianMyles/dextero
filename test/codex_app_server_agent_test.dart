import 'dart:async';
import 'dart:convert';

import 'package:dextero/harness.dart';
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

  test('returns tool failures to app-server as unsuccessful results', () async {
    final transport = _ScriptedTransport(toolName: 'fail');
    final run = await CodexAppServerAgent(
      transportFactory: () async => transport,
    ).run('try it', tools: [_FailingTool()]);

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
  Object? call(JsonMap arguments) => {'echo': arguments['value']};
}

final class _FailingTool implements Tool {
  @override
  ToolDefinition get definition => const ToolDefinition(
    name: 'fail',
    description: 'Fail.',
    inputSchema: {'type': 'object'},
  );

  @override
  Object? call(JsonMap arguments) => throw StateError('tool exploded');
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
  _ScriptedTransport({required this.toolName});

  final String toolName;

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
          'id': 'tool-request-1',
          'method': 'item/tool/call',
          'params': {
            'threadId': 'thread-1',
            'turnId': 'turn-1',
            'callId': 'call-1',
            'tool': toolName,
            'arguments': {'value': 'hello'},
          },
        });
      case null:
        if (message['id'] != 'tool-request-1') return;
        emit({
          'method': 'item/completed',
          'params': {
            'item': {
              'type': 'agentMessage',
              'text': toolName == 'fail'
                  ? 'The tool failed safely.'
                  : 'The tool said hello.',
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
