import 'dart:async';

import 'cancellation.dart';
import 'model.dart';
import 'safe_metadata.dart';
import 'tool.dart';

enum AgentLoopActivityKind { toolCallStarted, toolOutput, toolCallCompleted }

final class AgentLoopActivity {
  const AgentLoopActivity({
    required this.kind,
    required this.summary,
    required this.toolCallId,
    required this.toolName,
    this.success,
  });

  final AgentLoopActivityKind kind;
  final SafeSummary summary;
  final String toolCallId;
  final String toolName;
  final bool? success;
}

typedef AgentLoopActivitySink =
    FutureOr<void> Function(AgentLoopActivity activity);

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

  Future<AgentRun> run(
    String prompt, {
    CancellationToken? cancellationToken,
    AgentLoopActivitySink? onActivity,
  }) async {
    if (prompt.trim().isEmpty) {
      throw ArgumentError.value(prompt, 'prompt', 'must not be empty');
    }
    final messages = <AgentMessage>[AgentMessage.user(prompt)];
    final definitions = _tools.values.map((tool) => tool.definition).toList();

    for (var turn = 1; turn <= maxTurns; turn++) {
      cancellationToken?.throwIfCancellationRequested();
      final response = await _model.nextTurn(
        messages: List.unmodifiable(messages),
        tools: List.unmodifiable(definitions),
        cancellationToken: cancellationToken,
      );
      cancellationToken?.throwIfCancellationRequested();
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
        await onActivity?.call(
          AgentLoopActivity(
            kind: AgentLoopActivityKind.toolCallStarted,
            summary: SafeMetadata.toolCall(call.name, call.arguments),
            toolCallId: call.id,
            toolName: call.name,
          ),
        );
        final result = await _execute(
          call,
          cancellationToken: cancellationToken,
          onOutput: (update) => onActivity?.call(
            AgentLoopActivity(
              kind: AgentLoopActivityKind.toolOutput,
              summary: SafeMetadata.text(
                '${call.name} ${update.stream}: ${update.byteCount} bytes',
              ),
              toolCallId: call.id,
              toolName: call.name,
            ),
          ),
        );
        messages.add(AgentMessage.tool(result));
        await onActivity?.call(
          AgentLoopActivity(
            kind: AgentLoopActivityKind.toolCallCompleted,
            summary: SafeMetadata.toolResult(
              call.name,
              result.content,
              success: !result.isError,
            ),
            toolCallId: call.id,
            toolName: call.name,
            success: !result.isError,
          ),
        );
      }
    }

    throw StateError('Agent exceeded the $maxTurns turn limit.');
  }

  Future<ToolResult> _execute(
    ToolCall call, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  }) async {
    cancellationToken?.throwIfCancellationRequested();
    final tool = _tools[call.name];
    if (tool == null) {
      return ToolResult(
        callId: call.id,
        content: 'Unknown tool: ${call.name}',
        isError: true,
      );
    }

    try {
      final content = await tool.call(
        call.arguments,
        cancellationToken: cancellationToken,
        onOutput: onOutput,
      );
      cancellationToken?.throwIfCancellationRequested();
      return ToolResult(callId: call.id, content: content);
    } on Object catch (error) {
      cancellationToken?.throwIfCancellationRequested();
      return ToolResult(
        callId: call.id,
        content: error.toString(),
        isError: true,
      );
    }
  }
}
