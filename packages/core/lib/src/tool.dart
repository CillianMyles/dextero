import 'dart:async';

import 'cancellation.dart';

typedef JsonMap = Map<String, Object?>;
typedef ToolOutputSink = FutureOr<void> Function(ToolOutputUpdate update);

final class ToolOutputUpdate {
  const ToolOutputUpdate({required this.stream, required this.byteCount});

  final String stream;
  final int byteCount;
}

final class ToolDefinition {
  const ToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
  });

  final String name;
  final String description;
  final JsonMap inputSchema;

  JsonMap toJson() => {
    'name': name,
    'description': description,
    'inputSchema': inputSchema,
  };
}

final class ToolCall {
  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final JsonMap arguments;

  JsonMap toJson() => {'id': id, 'name': name, 'arguments': arguments};
}

final class ToolResult {
  const ToolResult({
    required this.callId,
    required this.content,
    this.isError = false,
  });

  final String callId;
  final Object? content;
  final bool isError;

  JsonMap toJson() => {
    'callId': callId,
    'content': content,
    'isError': isError,
  };
}

abstract interface class Tool {
  ToolDefinition get definition;

  FutureOr<Object?> call(
    JsonMap arguments, {
    CancellationToken? cancellationToken,
    ToolOutputSink? onOutput,
  });
}
