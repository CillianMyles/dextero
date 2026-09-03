import 'dart:async';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:nocterm/nocterm.dart' as nocterm;
import 'package:test/test.dart';

void main() {
  test(
    'renders history and submits a message through the Nocterm TUI',
    () async {
      final tester = await nocterm.NoctermTester.create(
        size: const nocterm.Size(100, 30),
      );
      addTearDown(tester.dispose);
      final client = _FakeClient(
        historyEntries: [
          _entry(
            sequence: 0,
            id: 'history-0',
            kind: ChatEntryKind.assistantMessage,
            status: ChatEntryStatus.completed,
            content: 'Welcome **back**',
          ),
        ],
      );

      await tester.pumpComponent(
        DexteroTui(
          client: client,
          correlationIdFactory: () => 'tui-test-1',
          onExit: (_) {},
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        tester.terminalState.containsText('DEXTERO  Dextero 0.0.1'),
        isTrue,
      );
      expect(tester.terminalState.containsText('Welcome back'), isTrue);
      expect(tester.terminalState.containsText('Ready'), isTrue);

      await tester.enterText('Inspect the repo');
      await tester.sendEnter();
      await tester.pump();
      await tester.pump();

      expect(client.requests.single.message, 'Inspect the repo');
      expect(client.requests.single.correlationId, 'tui-test-1');
      expect(client.cursors, [1]);
      expect(tester.terminalState.containsText('Repository inspected'), isTrue);
      expect(tester.terminalState.containsText('Inspect the repo'), isTrue);
    },
  );

  test('leaves the Nocterm TUI through the documented slash command', () async {
    final tester = await nocterm.NoctermTester.create();
    addTearDown(tester.dispose);
    final client = _FakeClient();
    int? exitCode;

    await tester.pumpComponent(
      DexteroTui(client: client, onExit: (code) => exitCode = code),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText('/exit');
    await tester.sendEnter();

    expect(exitCode, 0);
    expect(client.requests, isEmpty);
  });

  test('keeps Ctrl+C active while a response stream is pending', () async {
    final tester = await nocterm.NoctermTester.create();
    addTearDown(tester.dispose);
    final response = StreamController<ChatEntry>();
    addTearDown(response.close);
    final client = _FakeClient(responseStream: response.stream);
    int? exitCode;

    await tester.pumpComponent(
      DexteroTui(client: client, onExit: (code) => exitCode = code),
    );
    await tester.pump();
    await tester.pump();
    await tester.enterText('Wait for the result');
    await tester.sendEnter();
    await tester.pump();

    expect(client.requests.single.message, 'Wait for the result');
    expect(tester.terminalState.containsText('Dextero is working…'), isTrue);

    await tester.sendKeyEvent(
      const nocterm.KeyboardEvent(
        logicalKey: nocterm.LogicalKey.keyC,
        modifiers: nocterm.ModifierKeys(ctrl: true),
      ),
    );

    expect(exitCode, 0);
  });
}

final class _FakeClient implements TerminalChatClient {
  _FakeClient({this.historyEntries = const [], this.responseStream});

  final List<ChatEntry> historyEntries;
  final Stream<ChatEntry>? responseStream;
  final requests = <ChatSubmitRequest>[];
  final cursors = <int>[];

  @override
  Future<void> close() async {}

  @override
  Future<bool> cancelRun(String conversationId, String runId) async => true;

  @override
  Future<List<ChatEntry>> history(String conversationId) async => [
    ...historyEntries,
  ];

  @override
  Future<HostStatus> status() async => _status();

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) {
    cursors.add(afterSequence);
    if (responseStream case final stream?) return stream;
    return Stream.fromIterable([
      _entry(
        sequence: afterSequence + 1,
        id: 'assistant-1',
        kind: ChatEntryKind.assistantMessage,
        status: ChatEntryStatus.completed,
        content: 'Repository inspected',
      ),
      _entry(
        sequence: afterSequence + 2,
        id: 'lifecycle-1',
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.completed,
        content: 'Response completed',
      ),
    ]);
  }

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) async {
    requests.add(request);
    return ChatSubmission(
      conversationId: request.conversationId,
      runId: 'run-1',
      correlationId: request.correlationId!,
      userEntry: _entry(
        sequence: historyEntries.length,
        id: 'user-1',
        kind: ChatEntryKind.userMessage,
        status: ChatEntryStatus.submitted,
        content: request.message,
      ),
    );
  }
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
  modelName: 'gemini-2.5-flash',
);

ChatEntry _entry({
  required int sequence,
  required String id,
  required ChatEntryKind kind,
  required ChatEntryStatus status,
  required String content,
}) => ChatEntry(
  conversationId: 'conversation-1',
  entryId: id,
  sequence: sequence,
  kind: kind,
  status: status,
  content: content,
  createdAt: DateTime.utc(2026),
  correlationId: 'tui-test-1',
  source: kind == ChatEntryKind.userMessage
      ? ChatEntrySource.user
      : ChatEntrySource.model,
  truncated: false,
  runId: 'run-1',
);
