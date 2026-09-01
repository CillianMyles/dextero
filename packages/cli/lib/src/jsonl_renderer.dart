import 'dart:convert';

import 'package:dextero_server/dextero_client.dart';

/// Stable, line-oriented automation representation of the typed chat stream.
final class JsonlRenderer {
  const JsonlRenderer();

  static const schemaVersion = 1;

  String entry(ChatEntry entry) => jsonEncode({
    'schema_version': schemaVersion,
    'type': 'chat_event',
    'event_version': entry.eventVersion,
    'family': entry.family.name,
    'conversation_id': entry.conversationId,
    'entry_id': entry.entryId,
    'sequence': entry.sequence,
    'kind': entry.kind.name,
    'status': entry.status.name,
    'content': entry.content,
    'created_at': entry.createdAt.toUtc().toIso8601String(),
    'correlation_id': entry.correlationId,
    'source': entry.source.name,
    'truncated': entry.truncated,
    if (entry.runId != null) 'run_id': entry.runId,
    if (entry.toolCallId != null) 'tool_call_id': entry.toolCallId,
    if (entry.toolName != null) 'tool_name': entry.toolName,
  });

  String error(Object error) => jsonEncode({
    'schema_version': schemaVersion,
    'type': 'client_error',
    'message': error.toString(),
  });
}
