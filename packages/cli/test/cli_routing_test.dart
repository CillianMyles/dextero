import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:test/test.dart';

import '../bin/dextero.dart' as cli;

void main() {
  test(
    'uses line input when stdin is redirected but stdout is a TTY',
    () async {
      final io = _FakeIo(lines: ['Inspect via pipe', '/exit']);
      final client = _FakeClient();
      var tuiRuns = 0;

      final result = await cli.run(
        const [],
        io: io,
        environment: const {
          'DEXTERO_CONTROL_TOKEN': 'test-token-0123456789-0123456789',
        },
        clientFactory: ({required serverUrl, required token}) => client,
        tuiRunner: ({required client, modelName}) async {
          tuiRuns++;
          return 0;
        },
      );

      expect(result, 0);
      expect(tuiRuns, 0);
      expect(client.requests.single.message, 'Inspect via pipe');
      expect(io.output.join(), contains('[dextero] Pipe inspected'));
      expect(client.closed, isTrue);
    },
  );

  test('passes a startup model selection into the Nocterm TUI', () async {
    final io = _FakeIo(
      lines: const [],
      hasInputTerminal: true,
      hasOutputTerminal: true,
    );
    final client = _FakeClient();
    String? selectedModel;

    final result = await cli.run(
      const ['--model', 'gemini-pro'],
      io: io,
      environment: const {
        'DEXTERO_CONTROL_TOKEN': 'test-token-0123456789-0123456789',
      },
      clientFactory: ({required serverUrl, required token}) => client,
      tuiRunner: ({required client, modelName}) async {
        selectedModel = modelName;
        return 0;
      },
    );

    expect(result, 0);
    expect(selectedModel, 'gemini-pro');
  });
}

final class _FakeIo implements TerminalIo {
  _FakeIo({
    required List<String> lines,
    this.hasInputTerminal = false,
    this.hasOutputTerminal = true,
  }) : _lines = List.of(lines);

  final List<String> _lines;
  final output = <String>[];

  @override
  final bool hasInputTerminal;

  @override
  final bool hasOutputTerminal;

  @override
  void error(String value) {}

  @override
  String? readLine() => _lines.isEmpty ? null : _lines.removeAt(0);

  @override
  void write(String value) => output.add(value);

  @override
  void writeln(String value) => output.add('$value\n');
}

final class _FakeClient implements TerminalChatClient {
  final requests = <ChatSubmitRequest>[];
  bool closed = false;

  @override
  Future<bool> cancelRun(String conversationId, String runId) async => true;

  @override
  Future<void> close() async => closed = true;

  @override
  Future<List<ChatEntry>> history(String conversationId) async => const [];

  @override
  Future<HostStatus> status() async => HostStatus(
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
    availableModels: const ['gemini-2.5-flash'],
  );

  @override
  Future<HostStatus> selectModel(String modelName) async => status();

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) =>
      Stream.fromIterable([
        _entry(
          sequence: 1,
          id: 'assistant-1',
          kind: ChatEntryKind.assistantMessage,
          status: ChatEntryStatus.completed,
          content: 'Pipe inspected',
        ),
        _entry(
          sequence: 2,
          id: 'lifecycle-1',
          kind: ChatEntryKind.lifecycle,
          status: ChatEntryStatus.completed,
          content: 'Response completed',
        ),
      ]);

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) async {
    requests.add(request);
    return ChatSubmission(
      conversationId: request.conversationId,
      runId: 'run-1',
      correlationId: request.correlationId!,
      userEntry: _entry(
        sequence: 0,
        id: 'user-1',
        kind: ChatEntryKind.userMessage,
        status: ChatEntryStatus.submitted,
        content: request.message,
      ),
    );
  }
}

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
  correlationId: 'cli-routing-test',
  source: kind == ChatEntryKind.userMessage
      ? ChatEntrySource.user
      : ChatEntrySource.model,
  truncated: false,
  runId: 'run-1',
);
