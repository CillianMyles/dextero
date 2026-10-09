import 'dart:async';

import 'cancellation.dart';
import 'tool.dart';

enum MessageRole { user, assistant, tool }

final class AgentMessage {
  const AgentMessage._({
    required this.role,
    this.content,
    this.toolCalls = const [],
    this.toolResult,
    this.providerState = const {},
  });

  factory AgentMessage.user(String content) =>
      AgentMessage._(role: MessageRole.user, content: content);

  factory AgentMessage.assistant({
    String? content,
    List<ToolCall> toolCalls = const [],
    JsonMap providerState = const {},
  }) => AgentMessage._(
    role: MessageRole.assistant,
    content: content,
    toolCalls: List.unmodifiable(toolCalls),
    providerState: providerState,
  );

  factory AgentMessage.tool(ToolResult result) =>
      AgentMessage._(role: MessageRole.tool, toolResult: result);

  final MessageRole role;
  final String? content;
  final List<ToolCall> toolCalls;
  final ToolResult? toolResult;

  /// Opaque provider data that must be replayed unchanged on later turns.
  final JsonMap providerState;
}

/// Token counts reported by a provider for one or more model requests.
final class ModelUsage {
  const ModelUsage({
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheCreationInputTokens = 0,
    this.cacheReadInputTokens = 0,
  });

  static const zero = ModelUsage();

  /// Uncached input tokens only; cached tokens are counted separately.
  final int inputTokens;
  final int outputTokens;
  final int cacheCreationInputTokens;
  final int cacheReadInputTokens;

  ModelUsage operator +(ModelUsage other) => ModelUsage(
    inputTokens: inputTokens + other.inputTokens,
    outputTokens: outputTokens + other.outputTokens,
    cacheCreationInputTokens:
        cacheCreationInputTokens + other.cacheCreationInputTokens,
    cacheReadInputTokens: cacheReadInputTokens + other.cacheReadInputTokens,
  );
}

final class ModelTurn {
  const ModelTurn({
    this.content,
    this.toolCalls = const [],
    this.usage,
    this.providerState = const {},
  });

  final String? content;
  final List<ToolCall> toolCalls;
  final ModelUsage? usage;
  final JsonMap providerState;
}

/// Incremental progress reported while a model turn is in flight.
sealed class ModelEvent {
  const ModelEvent();
}

final class ModelTextDelta extends ModelEvent {
  const ModelTextDelta(this.text);

  final String text;
}

final class ModelRetryScheduled extends ModelEvent {
  const ModelRetryScheduled({
    required this.reason,
    required this.delay,
    required this.attempt,
  });

  final String reason;
  final Duration delay;
  final int attempt;
}

typedef ModelEventSink = FutureOr<void> Function(ModelEvent event);

abstract interface class AgentModel {
  Future<ModelTurn> nextTurn({
    required List<AgentMessage> messages,
    required List<ToolDefinition> tools,
    CancellationToken? cancellationToken,
    ModelEventSink? onEvent,
  });
}
