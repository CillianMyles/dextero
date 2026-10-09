import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

void main() {
  test('is idle without an unfinished run', () {
    expect(agentActivityOf(const []).activity, AgentActivity.idle);
    expect(
      agentActivityOf([
        _entry(0, ChatEntryKind.userMessage, ChatEntryStatus.submitted),
        _entry(1, ChatEntryKind.lifecycle, ChatEntryStatus.completed),
      ]).activity,
      AgentActivity.idle,
    );
  });

  test('follows thinking, tool use, approval, and completion', () {
    final entries = [
      _entry(0, ChatEntryKind.userMessage, ChatEntryStatus.submitted),
      _entry(1, ChatEntryKind.lifecycle, ChatEntryStatus.queued),
    ];
    expect(agentActivityOf(entries).activity, AgentActivity.thinking);
    expect(agentActivityOf(entries).runId, 'run-1');

    entries.add(
      _entry(
        2,
        ChatEntryKind.toolCall,
        ChatEntryStatus.running,
        toolCallId: 'call-1',
        toolName: 'read_file',
      ),
    );
    final acting = agentActivityOf(entries);
    expect(acting.activity, AgentActivity.acting);
    expect(acting.toolName, 'read_file');

    entries.add(
      _entry(
        3,
        ChatEntryKind.toolResult,
        ChatEntryStatus.completed,
        toolCallId: 'call-1',
        toolName: 'read_file',
      ),
    );
    expect(agentActivityOf(entries).activity, AgentActivity.thinking);

    entries.add(
      _entry(
        4,
        ChatEntryKind.approval,
        ChatEntryStatus.pending,
        toolCallId: 'call-2',
        toolName: 'edit_file',
        approvalId: 'approval-1',
      ),
    );
    final waiting = agentActivityOf(entries.reversed);
    expect(waiting.activity, AgentActivity.awaitingApproval);
    expect(waiting.toolName, 'edit_file');

    entries.add(
      _entry(
        5,
        ChatEntryKind.approval,
        ChatEntryStatus.approved,
        toolCallId: 'call-2',
        toolName: 'edit_file',
        approvalId: 'approval-1',
      ),
    );
    expect(agentActivityOf(entries).activity, AgentActivity.thinking);

    entries.add(_entry(6, ChatEntryKind.lifecycle, ChatEntryStatus.failed));
    expect(agentActivityOf(entries).activity, AgentActivity.idle);
    expect(isTerminalRunEntry(entries.last), isTrue);
  });

  test('reports the newest unfinished run', () {
    final state = agentActivityOf([
      _entry(0, ChatEntryKind.lifecycle, ChatEntryStatus.cancelled),
      _entry(1, ChatEntryKind.userMessage, ChatEntryStatus.submitted, run: 2),
    ]);

    expect(state.activity, AgentActivity.thinking);
    expect(state.runId, 'run-2');
  });
}

ChatEntry _entry(
  int sequence,
  ChatEntryKind kind,
  ChatEntryStatus status, {
  int run = 1,
  String? toolCallId,
  String? toolName,
  String? approvalId,
}) => ChatEntry(
  conversationId: 'conversation-1',
  entryId: 'entry-$sequence',
  sequence: sequence,
  kind: kind,
  status: status,
  content: kind.name,
  createdAt: DateTime.utc(2026),
  correlationId: 'correlation-1',
  source: ChatEntrySource.dextero,
  truncated: false,
  runId: 'run-$run',
  toolCallId: toolCallId,
  toolName: toolName,
  approvalId: approvalId,
);
