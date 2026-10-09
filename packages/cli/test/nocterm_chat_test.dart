import 'dart:async';
import 'dart:io';

import 'package:dextero_cli/dextero_cli.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:nocterm/nocterm.dart' as nocterm;
import 'package:test/test.dart';

void main() {
  test('lists combinations then switches provider before submitting', () async {
    final tester = await nocterm.NoctermTester.create(
      size: const nocterm.Size(120, 30),
    );
    addTearDown(tester.dispose);
    final client = _FakeClient();
    await tester.pumpComponent(DexteroTui(client: client, onExit: (_) {}));
    await tester.pump();
    await tester.pump();
    await tester.enterText('/models');
    await tester.sendEnter();
    await tester.pump();
    expect(
      tester.terminalState.containsText('codex:gpt-5.3-codex-spark'),
      isTrue,
    );
    expect(tester.terminalState.containsText('Dextero harness tools'), isTrue);
    await tester.enterText('/model codex:gpt-5.3-codex-spark');
    await tester.sendEnter();
    await tester.pump();
    await tester.pump();
    expect(client.modelSelections, ['codex:gpt-5.3-codex-spark']);
    await tester.enterText('Start');
    await tester.sendEnter();
    await tester.pump();
    await tester.pump();
    expect(client.requests.single.modelProvider, 'codex');
    expect(client.requests.single.modelName, 'gpt-5.3-codex-spark');
    await tester.enterText('/model gemini:gemini-2.5-flash');
    await tester.sendEnter();
    await tester.pump();
    expect(
      tester.terminalState.containsText('locked after the first message'),
      isTrue,
    );
    expect(client.modelSelections, hasLength(1));
  });

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

  test('shows how to resume a truncated pending approval', () async {
    final tester = await nocterm.NoctermTester.create(
      size: const nocterm.Size(110, 24),
    );
    addTearDown(tester.dispose);
    final client = _FakeClient(
      historyEntries: [
        _entry(
          sequence: 0,
          id: 'approval-pending',
          kind: ChatEntryKind.approval,
          status: ChatEntryStatus.pending,
          content: 'edit_file requires approval for README.md',
          approvalId: 'approval-7',
          truncated: true,
        ),
      ],
    );

    await tester.pumpComponent(DexteroTui(client: client, onExit: (_) {}));
    await tester.pump();
    await tester.pump();

    expect(tester.terminalState.containsText('Run ID: run-1'), isTrue);
    expect(
      tester.terminalState.containsText('Approval ID: approval-7'),
      isTrue,
    );
    expect(
      tester.terminalState.containsText(
        'make approve RUN_ID=run-1 APPROVAL_ID=approval-7',
      ),
      isTrue,
    );
    expect(
      tester.terminalState.containsText(
        'WARNING: Approval preview truncated; part of the proposed edit is not shown.',
      ),
      isTrue,
    );
  });

  test('distinguishes approved and cancelled approval history', () async {
    final tester = await nocterm.NoctermTester.create(
      size: const nocterm.Size(100, 24),
    );
    addTearDown(tester.dispose);
    final client = _FakeClient(
      historyEntries: [
        _entry(
          sequence: 0,
          id: 'approval-approved',
          kind: ChatEntryKind.approval,
          status: ChatEntryStatus.approved,
          content: 'edit_file approved',
          approvalId: 'approval-1',
        ),
        _entry(
          sequence: 1,
          id: 'approval-cancelled',
          kind: ChatEntryKind.approval,
          status: ChatEntryStatus.cancelled,
          content: 'edit_file approval cancelled',
          approvalId: 'approval-2',
        ),
      ],
    );

    await tester.pumpComponent(DexteroTui(client: client, onExit: (_) {}));
    await tester.pump();
    await tester.pump();

    expect(tester.terminalState.containsText('✓ approved'), isTrue);
    expect(tester.terminalState.containsText('× cancelled'), isTrue);
  });

  test('selects a model before the first message', () async {
    final tester = await nocterm.NoctermTester.create();
    addTearDown(tester.dispose);
    final client = _FakeClient();

    await tester.pumpComponent(DexteroTui(client: client, onExit: (_) {}));
    await tester.pump();
    await tester.pump();
    await tester.enterText('/model gemini-pro');
    await tester.sendEnter();
    await tester.pump();
    await tester.pump();

    expect(client.modelSelections, ['gemini:gemini-pro']);
    expect(tester.terminalState.containsText('gemini · gemini-pro'), isTrue);
    expect(tester.terminalState.containsText('Using gemini'), isTrue);
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
    expect(tester.terminalState.containsText('Dextero is thinking…'), isTrue);

    await tester.sendKeyEvent(
      const nocterm.KeyboardEvent(
        logicalKey: nocterm.LogicalKey.keyC,
        modifiers: nocterm.ModifierKeys(ctrl: true),
      ),
    );

    expect(exitCode, 0);
  });

  test('sends /voice recordings and narrates agent activity', () async {
    final tester = await nocterm.NoctermTester.create(
      size: const nocterm.Size(110, 30),
    );
    addTearDown(tester.dispose);
    final directory = Directory.systemTemp.createTempSync('dextero-tui-');
    addTearDown(() => directory.deleteSync(recursive: true));
    final recording = File('${directory.path}/question.wav')
      ..writeAsBytesSync([82, 73, 70, 70]);
    final responses = StreamController<ChatEntry>();
    final client = _FakeClient(responseStream: responses.stream);
    await tester.pumpComponent(DexteroTui(client: client, onExit: (_) {}));
    await tester.pump();
    await tester.pump();

    await tester.enterText('/voice ${recording.path}');
    await tester.sendEnter();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(client.voiceRequests.single.mimeType, 'audio/wav');
    expect(client.requests, isEmpty);
    expect(tester.terminalState.containsText('YOU voice'), isTrue);
    expect(tester.terminalState.containsText('Check the build'), isTrue);
    expect(
      tester.terminalState.containsText('transcribed by whisper.cpp'),
      isTrue,
    );
    expect(tester.terminalState.containsText('Dextero is thinking'), isTrue);

    responses.add(
      _entry(
        sequence: 1,
        id: 'tool-1',
        kind: ChatEntryKind.toolCall,
        status: ChatEntryStatus.running,
        content: 'run_command started',
        toolCallId: 'call-1',
        toolName: 'run_command',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(
      tester.terminalState.containsText('Dextero is using run_command'),
      isTrue,
    );

    responses
      ..add(
        _entry(
          sequence: 2,
          id: 'assistant-1',
          kind: ChatEntryKind.assistantMessage,
          status: ChatEntryStatus.completed,
          content: 'Build passes',
        ),
      )
      ..add(
        _entry(
          sequence: 3,
          id: 'lifecycle-1',
          kind: ChatEntryKind.lifecycle,
          status: ChatEntryStatus.completed,
          content: 'Response completed',
        ),
      );
    await tester.pump();
    await tester.pump();
    expect(tester.terminalState.containsText('Ready'), isTrue);
    await responses.close();
  });

  test('explains how to send a voice recording', () async {
    final tester = await nocterm.NoctermTester.create(
      size: const nocterm.Size(110, 24),
    );
    addTearDown(tester.dispose);
    final client = _FakeClient();
    await tester.pumpComponent(DexteroTui(client: client, onExit: (_) {}));
    await tester.pump();
    await tester.pump();

    await tester.enterText('/voice');
    await tester.sendEnter();
    await tester.pump();

    expect(
      tester.terminalState.containsText('Send a recording with /voice'),
      isTrue,
    );
    expect(client.voiceRequests, isEmpty);
  });
}

final class _FakeClient implements TerminalChatClient {
  _FakeClient({this.historyEntries = const [], this.responseStream});

  final List<ChatEntry> historyEntries;
  final Stream<ChatEntry>? responseStream;
  final requests = <ChatSubmitRequest>[];
  final voiceRequests = <VoiceSubmitRequest>[];
  final cursors = <int>[];
  final modelSelections = <String>[];

  @override
  Future<void> close() async {}

  @override
  Future<bool> cancelRun(String conversationId, String runId) async => true;

  @override
  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  ) async => true;

  @override
  Future<List<ChatEntry>> history(String conversationId) async => [
    ...historyEntries,
  ];

  @override
  Future<HostStatus> status() async => _status();

  @override
  Future<HostStatus> selectModel(String modelName) async {
    modelSelections.add(modelName);
    return _status(modelName: modelName.split(':').last);
  }

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

  @override
  Future<ChatSubmission> submitVoice(VoiceSubmitRequest request) async {
    voiceRequests.add(request);
    return ChatSubmission(
      conversationId: request.conversationId,
      runId: 'run-1',
      correlationId: request.correlationId!,
      userEntry: _entry(
        sequence: historyEntries.length,
        id: 'user-voice-1',
        kind: ChatEntryKind.userMessage,
        status: ChatEntryStatus.submitted,
        content: 'Check the build',
        modality: ChatModality.voice,
        transcriptionEngine: 'whisper.cpp (ggml-base.bin) on this host',
      ),
    );
  }

  @override
  Future<SpokenReply> speakReply(String conversationId, String entryId) =>
      throw UnimplementedError('The TUI does not play audio.');
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
  modelProvider: modelName == 'gpt-5.3-codex-spark' || modelName == 'default'
      ? 'codex'
      : 'gemini',
  modelName: modelName,
  availableModels: const ['gemini-2.5-flash', 'gemini-pro'],
  modelOptions: [
    for (final model in const ['gpt-5.3-codex-spark', 'default'])
      ModelOption(
        id: 'codex:$model',
        provider: 'codex',
        modelName: model,
        label: 'Codex · $model',
        toolDescription: 'Codex tools + Dextero harness tools',
      ),
    for (final model in const ['gemini-2.5-flash', 'gemini-pro'])
      ModelOption(
        id: 'gemini:$model',
        provider: 'gemini',
        modelName: model,
        label: 'Gemini · $model',
        toolDescription: 'Dextero harness tools',
      ),
  ],
);

ChatEntry _entry({
  required int sequence,
  required String id,
  required ChatEntryKind kind,
  required ChatEntryStatus status,
  required String content,
  String? approvalId,
  bool truncated = false,
  String? toolCallId,
  String? toolName,
  ChatModality modality = ChatModality.text,
  String? transcriptionEngine,
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
  truncated: truncated,
  runId: 'run-1',
  approvalId: approvalId,
  toolCallId: toolCallId,
  toolName: toolName,
  modality: modality,
  transcriptionEngine: transcriptionEngine,
);
