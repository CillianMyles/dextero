import 'cancellation.dart';
import 'tool.dart';

enum MessageRole { user, assistant, tool }

final class AgentMessage {
  const AgentMessage._({
    required this.role,
    this.content,
    this.toolCalls = const [],
    this.toolResult,
  });

  factory AgentMessage.user(String content) =>
      AgentMessage._(role: MessageRole.user, content: content);

  factory AgentMessage.assistant({
    String? content,
    List<ToolCall> toolCalls = const [],
  }) => AgentMessage._(
    role: MessageRole.assistant,
    content: content,
    toolCalls: List.unmodifiable(toolCalls),
  );

  factory AgentMessage.tool(ToolResult result) =>
      AgentMessage._(role: MessageRole.tool, toolResult: result);

  final MessageRole role;
  final String? content;
  final List<ToolCall> toolCalls;
  final ToolResult? toolResult;
}

final class ModelTurn {
  const ModelTurn({this.content, this.toolCalls = const []});

  final String? content;
  final List<ToolCall> toolCalls;
}

abstract interface class AgentModel {
  Future<ModelTurn> nextTurn({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
    CancellationToken? cancellationToken,
  });
}
