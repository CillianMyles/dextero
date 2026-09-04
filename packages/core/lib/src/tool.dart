import 'dart:async';

import 'cancellation.dart';

typedef JsonMap = Map<String, Object?>;
typedef ToolOutputSink = FutureOr<void> Function(ToolOutputUpdate update);

/// Copies JSON-like input into recursively immutable maps and lists.
JsonMap snapshotJsonMap(JsonMap value) => Map.unmodifiable({
  for (final entry in value.entries) entry.key: _snapshotJsonValue(entry.value),
});

Object? _snapshotJsonValue(Object? value) {
  if (value is Map) {
    return Map.unmodifiable({
      for (final entry in value.entries)
        entry.key: _snapshotJsonValue(entry.value),
    });
  }
  if (value is List) {
    return List.unmodifiable(value.map(_snapshotJsonValue));
  }
  return value;
}

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
    this.providerMetadata = const {},
  });

  final String id;
  final String name;
  final JsonMap arguments;
  final JsonMap providerMetadata;

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'arguments': arguments,
    if (providerMetadata.isNotEmpty) 'providerMetadata': providerMetadata,
  };
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
