import 'model.dart';
import 'tool.dart';

final class AgentRun {
  const AgentRun({
    required this.output,
    required this.messages,
    required this.turns,
  });

  final String output;
  final List<AgentMessage> messages;
  final int turns;
}

final class AgentLoop {
  AgentLoop({
    required AgentModel model,
    required List<Tool> tools,
    this.maxTurns = 12,
  }) : _model = model,
       _tools = {for (final tool in tools) tool.definition.name: tool} {
    if (_tools.length != tools.length) {
      throw ArgumentError('Tool names must be unique.');
    }
    if (maxTurns < 1) {
      throw ArgumentError.value(maxTurns, 'maxTurns', 'must be positive');
    }
  }

  final AgentModel _model;
  final Map<String, Tool> _tools;
  final int maxTurns;

  Future<AgentRun> run(String prompt) async {
    final messages = <AgentMessage>[AgentMessage.user(prompt)];
    final definitions = _tools.values.map((tool) => tool.definition).toList();

    for (var turn = 1; turn <= maxTurns; turn++) {
      final response = await _model.nextTurn(
        messages: List.unmodifiable(messages),
        tools: List.unmodifiable(definitions),
      );
      messages.add(
        AgentMessage.assistant(
          content: response.content,
          toolCalls: response.toolCalls,
        ),
      );

      if (response.toolCalls.isEmpty) {
        final output = response.content?.trim();
        if (output == null || output.isEmpty) {
          throw StateError('Model returned neither tool calls nor final text.');
        }
        return AgentRun(
          output: output,
          messages: List.unmodifiable(messages),
          turns: turn,
        );
      }

      for (final call in response.toolCalls) {
        messages.add(AgentMessage.tool(await _execute(call)));
      }
    }

    throw StateError('Agent exceeded the $maxTurns turn limit.');
  }

  Future<ToolResult> _execute(ToolCall call) async {
    final tool = _tools[call.name];
    if (tool == null) {
      return ToolResult(
        callId: call.id,
        content: 'Unknown tool: ${call.name}',
        isError: true,
      );
    }

    try {
      return ToolResult(
        callId: call.id,
        content: await tool.call(call.arguments),
      );
    } on Object catch (error) {
      return ToolResult(
        callId: call.id,
        content: error.toString(),
        isError: true,
      );
    }
  }
}
