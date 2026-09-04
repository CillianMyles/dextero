import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

import 'dart:convert';

void main() {
  test(
    'runs a repeatable interactive conversation through injected seams',
    () async {
      final client = _FakeClient();
      final io = _FakeIo(lines: ['Inspect the repo', '/exit']);
      final chat = TerminalChat(
        client: client,
        io: io,
        correlationIdFactory: () => 'cli-test-1',
      );

      final result = await chat.run();

      expect(result, 0);
      expect(client.requests.single.message, 'Inspect the repo');
      expect(client.requests.single.correlationId, 'cli-test-1');
      expect(client.cursors, [0]);
      expect(io.output.join(), contains('[dextero] Repository inspected'));
      expect(io.output.join(), contains('you> '));
      expect(client.closed, isTrue);
    },
  );

  test(
    'supports one-shot messages and returns failure lifecycle status',
    () async {
      final client = _FakeClient(fail: true);
      final io = _FakeIo(lines: const []);

      final result = await TerminalChat(
        client: client,
        io: io,
      ).run(initialMessage: 'Do the work');

      expect(result, 1);
      expect(io.output.join(), contains('[error] Safe failure'));
      expect(client.closed, isTrue);
    },
  );

  test('selects the requested model before loading history', () async {
    final client = _FakeClient();
    final io = _FakeIo(lines: const []);

    final result = await TerminalChat(
      client: client,
      io: io,
    ).run(initialMessage: 'Do the work', modelName: 'gemini-pro');

    expect(result, 0);
    expect(client.modelSelections, ['gemini-pro']);
    expect(io.output.join(), contains('gemini · gemini-pro'));
  });

  test(
    'reports client errors through the deterministic error stream',
    () async {
      final client = _FakeClient(statusError: StateError('offline'));
      final io = _FakeIo(lines: const []);

      final result = await TerminalChat(client: client, io: io).run();

      expect(result, 1);
      expect(io.errors.single, contains('offline'));
      expect(client.closed, isTrue);
    },
  );

  test('fails if the history stream closes without a terminal entry', () async {
    final client = _FakeClient(endBeforeTerminal: true);
    final io = _FakeIo(lines: const []);

    final result = await TerminalChat(
      client: client,
      io: io,
    ).run(initialMessage: 'Do the work');

    expect(result, 1);
    expect(io.errors.single, contains('before the response completed'));
  });

  test('cancels a run by id without submitting a message', () async {
    final client = _FakeClient();
    final io = _FakeIo(lines: const []);

    final result = await TerminalChat(
      client: client,
      io: io,
    ).run(cancelRunId: 'run-42');

    expect(result, 0);
    expect(client.cancellations, [('conversation-1', 'run-42')]);
    expect(client.requests, isEmpty);
    expect(io.output.join(), contains('Cancellation requested'));
  });

  test('approves a pending action by run and approval id', () async {
    final client = _FakeClient();
    final io = _FakeIo(lines: const []);

    final result = await TerminalChat(
      client: client,
      io: io,
    ).run(approveRunId: 'run-42', approvalId: 'approval-7');

    expect(result, 0);
    expect(client.approvals, [('conversation-1', 'run-42', 'approval-7')]);
    expect(client.requests, isEmpty);
    expect(io.output.join(), contains('Approved approval-7'));
  });

  test('emits accepted and rejected approvals as JSONL', () async {
    for (final accepted in [true, false]) {
      final client = _FakeClient(approvalAccepted: accepted);
      final io = _FakeIo(lines: const []);

      final result = await TerminalChat(
        client: client,
        io: io,
        outputMode: TerminalOutputMode.jsonl,
      ).run(approveRunId: 'run-42', approvalId: 'approval-7');

      expect(result, accepted ? 0 : 1);
      expect(jsonDecode(io.output.single), {
        'schema_version': 1,
        'type': 'approval_result',
        'conversation_id': 'conversation-1',
        'run_id': 'run-42',
        'approval_id': 'approval-7',
        'accepted': accepted,
        'status': accepted ? 'approved' : 'not_pending',
      });
    }
  });

  test('emits only stable JSONL events in automation mode', () async {
    final client = _FakeClient();
    final io = _FakeIo(lines: const []);

    final result = await TerminalChat(
      client: client,
      io: io,
      outputMode: TerminalOutputMode.jsonl,
    ).run(initialMessage: 'Inspect the repo');

    expect(result, 0);
    final records = io.output
        .map((line) => jsonDecode(line) as Map<String, Object?>)
        .toList();
    expect(records, isNotEmpty);
    expect(records.every((record) => record['schema_version'] == 1), isTrue);
    expect(records.every((record) => record['type'] == 'chat_event'), isTrue);
    expect(io.output.join(), isNot(contains('Dextero is working')));
  });
}

final class _FakeClient implements TerminalChatClient {
  _FakeClient({
    this.fail = false,
    this.endBeforeTerminal = false,
    this.statusError,
    this.approvalAccepted = true,
  });

  final bool fail;
  final bool endBeforeTerminal;
  final Object? statusError;
  final bool approvalAccepted;
  final requests = <ChatSubmitRequest>[];
  final cursors = <int>[];
  bool closed = false;
  final cancellations = <(String, String)>[];
  final approvals = <(String, String, String)>[];
  final modelSelections = <String>[];

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<bool> cancelRun(String conversationId, String runId) async {
    cancellations.add((conversationId, runId));
    return true;
  }

  @override
  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  ) async {
    approvals.add((conversationId, runId, approvalId));
    return approvalAccepted;
  }

  @override
  Future<List<ChatEntry>> history(String conversationId) async => const [];

  @override
  Future<HostStatus> status() async {
    if (statusError != null) throw statusError!;
    return _status();
  }

  @override
  Future<HostStatus> selectModel(String modelName) async {
    modelSelections.add(modelName);
    return _status(modelName: modelName);
  }

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) {
    cursors.add(afterSequence);
    if (endBeforeTerminal) {
      return Stream.value(
        _entry(
          sequence: 1,
          id: 'entry-1',
          kind: ChatEntryKind.lifecycle,
          status: ChatEntryStatus.queued,
          content: 'Message queued',
        ),
      );
    }
    return Stream.fromIterable(
      fail
          ? [
              _entry(
                sequence: 1,
                id: 'entry-1',
                kind: ChatEntryKind.lifecycle,
                status: ChatEntryStatus.queued,
                content: 'Message queued',
              ),
              _entry(
                sequence: 2,
                id: 'entry-2',
                kind: ChatEntryKind.error,
                status: ChatEntryStatus.failed,
                content: 'Safe failure',
              ),
              _entry(
                sequence: 3,
                id: 'entry-3',
                kind: ChatEntryKind.lifecycle,
                status: ChatEntryStatus.failed,
                content: 'Response failed',
              ),
            ]
          : [
              _entry(
                sequence: 1,
                id: 'entry-1',
                kind: ChatEntryKind.lifecycle,
                status: ChatEntryStatus.queued,
                content: 'Message queued',
              ),
              _entry(
                sequence: 2,
                id: 'entry-2',
                kind: ChatEntryKind.assistantMessage,
                status: ChatEntryStatus.completed,
                content: 'Repository inspected',
              ),
              _entry(
                sequence: 3,
                id: 'entry-3',
                kind: ChatEntryKind.lifecycle,
                status: ChatEntryStatus.completed,
                content: 'Response completed',
              ),
            ],
    );
  }

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) async {
    requests.add(request);
    return ChatSubmission(
      conversationId: request.conversationId,
      runId: 'run-1',
      correlationId: request.correlationId!,
      userEntry: _entry(
        sequence: 0,
        id: 'entry-0',
        kind: ChatEntryKind.userMessage,
        status: ChatEntryStatus.submitted,
        content: request.message,
      ),
    );
  }
}

final class _FakeIo implements TerminalIo {
  _FakeIo({required List<String> lines}) : _lines = List.of(lines);

  final List<String> _lines;
  final output = <String>[];
  final errors = <String>[];

  @override
  bool get hasInputTerminal => false;

  @override
  bool get hasOutputTerminal => false;

  @override
  void error(String value) => errors.add(value);

  @override
  String? readLine() => _lines.isEmpty ? null : _lines.removeAt(0);

  @override
  void write(String value) => output.add(value);

  @override
  void writeln(String value) => output.add('$value\n');
}

HostStatus _status({String modelName = 'gemini-2.5-flash'}) => HostStatus(
  name: 'Dextero',
  version: '0.0.1',
  startedAt: DateTime.utc(2026),
  persistence: 'memory',
  conversationId: 'conversation-1',
  retentionNotice: 'History is retained only until the server restarts.',
  databaseRequired: false,
  streamingAvailable: true,
  modelProvider: 'gemini',
  modelName: modelName,
  availableModels: const ['gemini-2.5-flash', 'gemini-pro'],
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
  correlationId: 'cli-test-1',
  source: kind == ChatEntryKind.userMessage
      ? ChatEntrySource.user
      : ChatEntrySource.model,
  truncated: false,
  runId: 'run-1',
);
