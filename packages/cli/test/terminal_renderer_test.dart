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

  test('labels voice turns with their transcription provenance', () {
    final entry = ChatEntry(
      conversationId: 'conversation-1',
      entryId: 'entry-0',
      sequence: 0,
      kind: ChatEntryKind.userMessage,
      status: ChatEntryStatus.submitted,
      content: 'What changed?',
      createdAt: DateTime.utc(2026),
      correlationId: 'cli-test-1',
      source: ChatEntrySource.user,
      truncated: false,
      modality: ChatModality.voice,
      transcriptionEngine: 'whisper.cpp\x1B[31m on this host',
    );

    expect(
      const TerminalRenderer().plainEntryLine(entry),
      '[you · voice] What changed?\n(transcribed by whisper.cpp on this host)',
    );
  });

  test('describes agent activity in one status line', () {
    const renderer = TerminalRenderer();

    expect(renderer.activityNotice(AgentActivityState.idle), 'Ready');
    expect(
      renderer.activityNotice(const AgentActivityState(AgentActivity.thinking)),
      'Dextero is thinking…',
    );
    expect(
      renderer.activityNotice(
        const AgentActivityState(AgentActivity.acting, toolName: 'read_file'),
      ),
      'Dextero is using read_file…',
    );
    expect(
      renderer.activityNotice(
        const AgentActivityState(
          AgentActivity.awaitingApproval,
          toolName: 'edit_file',
        ),
      ),
      'Waiting for approval of edit_file; use the approve command shown above',
    );
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
