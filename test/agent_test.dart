import 'package:dart_harness_cli_spike/harness.dart';
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
