import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

void main() {
  test('renders assistant activity as a stable plain event', () {
    final entry = _entry(
      sequence: 2,
      kind: ChatEntryKind.assistantMessage,
      status: ChatEntryStatus.completed,
      content: 'Finished the work',
    );
    expect(
      const TerminalRenderer().plainEntryLine(entry),
      '[dextero] Finished the work',
    );
  });

  test('renders pending approval identifiers and the resume command', () {
    final entry = _entry(
      sequence: 3,
      kind: ChatEntryKind.approval,
      status: ChatEntryStatus.pending,
      content: 'edit_file requires approval for README.md',
      approvalId: 'approval-7',
    );

    final rendered = const TerminalRenderer().plainEntryLine(entry);

    expect(rendered, contains('Run ID: run-1'));
    expect(rendered, contains('Approval ID: approval-7'));
    expect(
      rendered,
      contains('make approve RUN_ID=run-1 APPROVAL_ID=approval-7'),
    );
  });

  test('warns when a pending approval preview is truncated', () {
    final entry = _entry(
      sequence: 4,
      kind: ChatEntryKind.approval,
      status: ChatEntryStatus.pending,
      content: 'edit_file requires approval for "very-long-path"',
      approvalId: 'approval-8',
      truncated: true,
    );

    final rendered = const TerminalRenderer().plainEntryLine(entry);

    expect(
      rendered,
      contains(
        'WARNING: Approval preview truncated; part of the proposed edit is not shown.',
      ),
    );
  });

  test('labels usage receipts and categorized failures', () {
    const renderer = TerminalRenderer();
    expect(
      renderer.plainEntryLine(
        _entry(
          sequence: 5,
          kind: ChatEntryKind.usage,
          status: ChatEntryStatus.completed,
          content: 'Anthropic · claude-haiku-4-5 · Anthropic API key',
        ),
      ),
      '[usage] Anthropic · claude-haiku-4-5 · Anthropic API key',
    );
    expect(
      renderer.plainEntryLine(
        _entry(
          sequence: 6,
          kind: ChatEntryKind.error,
          status: ChatEntryStatus.failed,
          content: 'Out of Anthropic API credit.',
        ).copyWith(errorCode: ChatErrorCode.creditExhausted),
      ),
      '[out of credit] Out of Anthropic API credit.',
    );
  });

  test('removes terminal control sequences from history content', () {
    final entry = _entry(
      sequence: 0,
      kind: ChatEntryKind.assistantMessage,
      status: ChatEntryStatus.completed,
      content: 'Keep this\x1b[2J visible',
    );

    final rendered = const TerminalRenderer().plainEntryLine(entry);

    expect(rendered, '[dextero] Keep this visible');
    expect(rendered, isNot(contains('\x1b')));
  });
}

ChatEntry _entry({
  required int sequence,
  required ChatEntryKind kind,
  required ChatEntryStatus status,
  required String content,
  String? toolName,
  String? approvalId,
  bool truncated = false,
}) => ChatEntry(
  conversationId: 'conversation-1',
  entryId: 'entry-$sequence',
  sequence: sequence,
  kind: kind,
  status: status,
  content: content,
  createdAt: DateTime.utc(2026),
  correlationId: 'correlation-1',
  source: kind == ChatEntryKind.userMessage
      ? ChatEntrySource.user
      : ChatEntrySource.model,
  truncated: truncated,
  runId: 'run-1',
  toolName: toolName,
  approvalId: approvalId,
);
