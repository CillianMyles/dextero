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

  test('includes usage receipts and categorized error codes', () {
    final usage =
        jsonDecode(
              const JsonlRenderer().entry(
                ChatEntry(
                  conversationId: 'conversation-1',
                  entryId: 'entry-9',
                  sequence: 9,
                  kind: ChatEntryKind.usage,
                  family: ChatEventFamily.usage,
                  status: ChatEntryStatus.completed,
                  content: 'Anthropic · claude-haiku-4-5',
                  createdAt: DateTime.utc(2026, 10, 9),
                  correlationId: 'cli-1',
                  source: ChatEntrySource.dextero,
                  truncated: false,
                  usage: ChatRunUsage(
                    provider: 'Anthropic',
                    model: 'claude-haiku-4-5',
                    authSource: 'Anthropic API key',
                    inputTokens: 930,
                    outputTokens: 50,
                    cacheCreationInputTokens: 4200,
                    cacheReadInputTokens: 5100,
                    modelRequests: 2,
                    costMicrosUsd: 6940,
                  ),
                ),
              ),
            )
            as Map<String, Object?>;
    expect(usage['family'], 'usage');
    expect(usage['usage'], {
      'provider': 'Anthropic',
      'model': 'claude-haiku-4-5',
      'auth_source': 'Anthropic API key',
      'input_tokens': 930,
      'output_tokens': 50,
      'cache_creation_input_tokens': 4200,
      'cache_read_input_tokens': 5100,
      'model_requests': 2,
      'cost_micros_usd': 6940,
    });

    final error =
        jsonDecode(
              const JsonlRenderer().entry(
                ChatEntry(
                  conversationId: 'conversation-1',
                  entryId: 'entry-10',
                  sequence: 10,
                  kind: ChatEntryKind.error,
                  status: ChatEntryStatus.failed,
                  content: 'Out of Anthropic API credit.',
                  createdAt: DateTime.utc(2026, 10, 9),
                  correlationId: 'cli-1',
                  source: ChatEntrySource.dextero,
                  truncated: false,
                  errorCode: ChatErrorCode.creditExhausted,
                ),
              ),
            )
            as Map<String, Object?>;
    expect(error['error_code'], 'creditExhausted');
    expect(error, isNot(contains('usage')));
  });
}
