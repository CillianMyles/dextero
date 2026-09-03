import 'dart:async';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'executes a tool call and returns the following model response',
    () async {
      final model = _QueueModel([
        const ModelTurn(
          toolCalls: [
            ToolCall(id: 'call-1', name: 'echo', arguments: {'value': 'hello'}),
          ],
        ),
        const ModelTurn(content: 'finished'),
      ]);

      final run = await AgentLoop(model: model, tools: [_EchoTool()]).run('go');

      expect(run.output, 'finished');
      expect(run.turns, 2);
      final result = run.messages.singleWhere(
        (message) => message.role == MessageRole.tool,
      );
      expect(result.toolResult?.content, {'echo': 'hello'});
      expect(result.toolResult?.isError, isFalse);
    },
  );

  test('returns unknown tools to the model as errors', () async {
    final model = _QueueModel([
      const ModelTurn(
        toolCalls: [ToolCall(id: 'call-1', name: 'missing', arguments: {})],
      ),
      const ModelTurn(content: 'recovered'),
    ]);

    final run = await AgentLoop(model: model, tools: []).run('go');
    final result = run.messages.singleWhere(
      (message) => message.role == MessageRole.tool,
    );

    expect(result.toolResult?.isError, isTrue);
    expect(result.toolResult?.content, contains('Unknown tool'));
  });

  test('returns thrown tool errors to the model and continues', () async {
    final model = _QueueModel([
      const ModelTurn(
        toolCalls: [ToolCall(id: 'call-1', name: 'fail', arguments: {})],
      ),
      const ModelTurn(content: 'recovered'),
    ]);

    final run = await AgentLoop(
      model: model,
      tools: [_FailingTool()],
    ).run('go');
    final result = run.messages.singleWhere(
      (message) => message.role == MessageRole.tool,
    );

    expect(run.output, 'recovered');
    expect(result.toolResult?.isError, isTrue);
    expect(result.toolResult?.content, contains('exploded'));
  });

  test('executes multiple tool calls from one model turn in order', () async {
    final model = _QueueModel([
      const ModelTurn(
        toolCalls: [
          ToolCall(id: 'call-1', name: 'echo', arguments: {'value': 'one'}),
          ToolCall(id: 'call-2', name: 'echo', arguments: {'value': 'two'}),
        ],
      ),
      const ModelTurn(content: 'done'),
    ]);

    final run = await AgentLoop(model: model, tools: [_EchoTool()]).run('go');
    final results = run.messages
        .where((message) => message.role == MessageRole.tool)
        .map((message) => message.toolResult?.content)
        .toList();

    expect(results, [
      {'echo': 'one'},
      {'echo': 'two'},
    ]);
  });

  test('waits for approval before executing a gated tool', () async {
    final approval = Completer<bool>();
    final requested = Completer<ToolApprovalRequest>();
    final tool = _CountingTool();
    final model = _QueueModel([
      const ModelTurn(
        toolCalls: [
          ToolCall(
            id: 'call-edit-1',
            name: 'edit_file',
            arguments: {
              'path': 'README.md',
              'oldText': 'old heading',
              'newText': 'new heading',
            },
          ),
        ],
      ),
      const ModelTurn(content: 'edited'),
    ]);

    final future =
        AgentLoop(
          model: model,
          tools: [tool],
          approvalRequiredTools: const {'edit_file'},
        ).run(
          'edit',
          onApprovalRequest: (request) {
            requested.complete(request);
            return approval.future;
          },
        );
    final request = await requested.future;

    expect(request.toolCallId, 'call-edit-1');
    expect(request.summary.text, contains('edit_file requires approval'));
    expect(request.summary.text, contains('-old heading'));
    expect(request.summary.text, contains('+new heading'));
    expect(tool.calls, 0);

    approval.complete(true);
    final run = await future;

    expect(run.output, 'edited');
    expect(tool.calls, 1);
  });

  test('rejects duplicate tool names', () {
    expect(
      () =>
          AgentLoop(model: _QueueModel([]), tools: [_EchoTool(), _EchoTool()]),
      throwsArgumentError,
    );
  });

  test('rejects a non-positive turn limit', () {
    expect(
      () => AgentLoop(model: _QueueModel([]), tools: [], maxTurns: 0),
      throwsArgumentError,
    );
  });

  test('fails when the model returns no text and no tool calls', () async {
    final loop = AgentLoop(model: _QueueModel([const ModelTurn()]), tools: []);

    await expectLater(
      loop.run('go'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('neither tool calls nor final text'),
        ),
      ),
    );
  });

  test('fails after the configured model-turn limit', () async {
    final loop = AgentLoop(
      model: _QueueModel([
        const ModelTurn(
          toolCalls: [ToolCall(id: '1', name: 'echo', arguments: {})],
        ),
      ]),
      tools: [_EchoTool()],
      maxTurns: 1,
    );

    await expectLater(
      loop.run('go'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          contains('turn limit'),
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
  }) => throw StateError('exploded');
}

final class _CountingTool implements Tool {
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

final class _QueueModel implements AgentModel {
  _QueueModel(this._turns);

  final List<ModelTurn> _turns;
  var _index = 0;

  @override
  Future<ModelTurn> nextTurn({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
    CancellationToken? cancellationToken,
  }) async => _turns[_index++];
}
