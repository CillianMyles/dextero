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
  truncated: false,
  runId: 'run-1',
  toolName: toolName,
);
