import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

void main() {
  test('renders user, assistant, and safe tool activity as chat', () {
    final entries = [
      _entry(
        sequence: 0,
        kind: ChatEntryKind.userMessage,
        status: ChatEntryStatus.submitted,
        content: 'Inspect the repo',
      ),
      _entry(
        sequence: 1,
        kind: ChatEntryKind.toolCall,
        status: ChatEntryStatus.running,
        content: 'list_files started',
        toolName: 'list_files',
      ),
      _entry(
        sequence: 2,
        kind: ChatEntryKind.assistantMessage,
        status: ChatEntryStatus.completed,
        content: 'Finished the work',
      ),
    ];

    final frame = const TerminalRenderer().frame(
      status: _status(),
      entries: entries,
    );

    expect(frame, contains('DEXTERO'));
    expect(frame, contains('Inspect the repo'));
    expect(frame, contains('list_files started'));
    expect(frame, contains('Finished the work'));
    expect(frame, contains('server restarts'));
    expect(frame, contains('gemini · gemini-3.7-flash'));
    expect(
      const TerminalRenderer().plainEntryLine(entries.last),
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

HostStatus _status() => HostStatus(
  name: 'Dextero',
  version: '0.0.1',
  startedAt: DateTime.utc(2026),
  persistence: 'memory',
  conversationId: 'conversation-1',
  retentionNotice: 'History is retained only until the server restarts.',
  databaseRequired: false,
  streamingAvailable: true,
  modelProvider: 'gemini',
  modelName: 'gemini-3.7-flash',
);

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
