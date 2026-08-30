import 'package:dextero/harness.dart';
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
  Object? call(JsonMap arguments) => throw StateError('exploded');
}

final class _QueueModel implements AgentModel {
  _QueueModel(this._turns);

  final List<ModelTurn> _turns;
  var _index = 0;

  @override
  Future<ModelTurn> nextTurn({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
  }) async => _turns[_index++];
}
