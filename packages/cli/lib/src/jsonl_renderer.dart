import 'dart:convert';

import 'package:dextero_server/dextero_client.dart';

/// Stable, line-oriented automation representation of the typed chat stream.
final class JsonlRenderer {
  const JsonlRenderer();

  static const schemaVersion = 1;

  String hostStatus(HostStatus status) => jsonEncode({
    'schema_version': schemaVersion,
    'type': 'host_status',
    'device_id': status.deviceId,
    'project_id': status.projectId,
    'project_name': status.projectName,
    'workspace_id': status.workspaceId,
    'workspace_name': status.workspaceName,
    'controller_id': status.controller.id,
    'controller_name': status.controller.name,
    'conversation_id': status.conversationId,
    'model_provider': status.modelProvider,
    'model_name': status.modelName,
  });

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
    if (entry.approvalId != null) 'approval_id': entry.approvalId,
  });

  String error(Object error) => jsonEncode({
    'schema_version': schemaVersion,
    'type': 'client_error',
    'message': error.toString(),
  });

  String approvalResult({
    required String conversationId,
    required String runId,
    required String approvalId,
    required bool accepted,
  }) => jsonEncode({
    'schema_version': schemaVersion,
    'type': 'approval_result',
    'conversation_id': conversationId,
    'run_id': runId,
    'approval_id': approvalId,
    'accepted': accepted,
    'status': accepted ? 'approved' : 'not_pending',
  });

  String cancellationResult({
    required String conversationId,
    required String runId,
    required bool accepted,
  }) => jsonEncode({
    'schema_version': schemaVersion,
    'type': 'cancellation_result',
    'conversation_id': conversationId,
    'run_id': runId,
    'accepted': accepted,
    'status': accepted ? 'cancellation_requested' : 'not_active',
  });
}
