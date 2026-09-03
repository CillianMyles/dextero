import 'dart:convert';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

void main() {
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
}
