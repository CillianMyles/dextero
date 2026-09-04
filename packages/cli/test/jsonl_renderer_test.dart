import 'dart:convert';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

void main() {
  test('renders host and controller identities as versioned status', () {
    final rendered = const JsonlRenderer().hostStatus(
      HostStatus(
        name: 'Dextero',
        version: '0.0.1',
        deviceId: 'device_0123456789abcdef',
        projectId: 'project_0123456789abcdef',
        projectName: 'Dextero',
        workspaceId: 'workspace_0123456789abcdef',
        workspaceName: 'main',
        controller: ControllerIdentity(
          id: 'controller_0123456789abcdef',
          name: 'Test CLI',
        ),
        startedAt: DateTime.utc(2026),
        persistence: 'memory',
        conversationId: 'conversation-1',
        retentionNotice: 'Until restart',
        databaseRequired: false,
        streamingAvailable: true,
        modelProvider: 'gemini',
        modelName: 'gemini-2.5-flash',
        availableModels: const ['gemini-2.5-flash'],
      ),
    );

    expect(jsonDecode(rendered), {
      'schema_version': 1,
      'type': 'host_status',
      'device_id': 'device_0123456789abcdef',
      'project_id': 'project_0123456789abcdef',
      'project_name': 'Dextero',
      'workspace_id': 'workspace_0123456789abcdef',
      'workspace_name': 'main',
      'controller_id': 'controller_0123456789abcdef',
      'controller_name': 'Test CLI',
      'conversation_id': 'conversation-1',
      'model_provider': 'gemini',
      'model_name': 'gemini-2.5-flash',
    });
  });

  test('renders a stable versioned JSONL event without null fields', () {
    final rendered = const JsonlRenderer().entry(
      ChatEntry(
        conversationId: 'conversation-1',
        entryId: 'entry-2',
        sequence: 2,
        kind: ChatEntryKind.toolCall,
        family: ChatEventFamily.tool,
        status: ChatEntryStatus.running,
        content: 'Read README.md',
        createdAt: DateTime.utc(2026, 9, 1, 20, 30),
        correlationId: 'cli-1',
        source: ChatEntrySource.model,
        truncated: false,
        runId: 'run-1',
        toolCallId: 'call-1',
        toolName: 'read_file',
        approvalId: 'approval-1',
      ),
    );
    final event = jsonDecode(rendered) as Map<String, Object?>;

    expect(event['schema_version'], 1);
    expect(event['event_version'], 1);
    expect(event['family'], 'tool');
    expect(event['type'], 'chat_event');
    expect(event['kind'], 'toolCall');
    expect(event['created_at'], '2026-09-01T20:30:00.000Z');
    expect(event['tool_name'], 'read_file');
    expect(event['approval_id'], 'approval-1');
    expect(event, isNot(contains('unused')));
  });

  test('renders machine-readable client errors', () {
    final event =
        jsonDecode(const JsonlRenderer().error(StateError('offline')))
            as Map<String, Object?>;

    expect(event, {
      'schema_version': 1,
      'type': 'client_error',
      'message': 'Bad state: offline',
    });
  });

  test('renders versioned approval and cancellation results', () {
    final renderer = const JsonlRenderer();
    final approval = jsonDecode(
      renderer.approvalResult(
        conversationId: 'conversation-1',
        runId: 'run-1',
        approvalId: 'approval-1',
        accepted: false,
      ),
    );
    final cancellation = jsonDecode(
      renderer.cancellationResult(
        conversationId: 'conversation-1',
        runId: 'run-2',
        accepted: true,
      ),
    );

    expect(approval, {
      'schema_version': 1,
      'type': 'approval_result',
      'conversation_id': 'conversation-1',
      'run_id': 'run-1',
      'approval_id': 'approval-1',
      'accepted': false,
      'status': 'not_pending',
    });
    expect(cancellation, {
      'schema_version': 1,
      'type': 'cancellation_result',
      'conversation_id': 'conversation-1',
      'run_id': 'run-2',
      'accepted': true,
      'status': 'cancellation_requested',
    });
  });
}
