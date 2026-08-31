import 'dart:async';

import 'package:dextero_app/main.dart';
import 'package:dextero_app/src/dextero_controller.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows loading and then a clear empty conversation', (
    tester,
  ) async {
    final status = Completer<HostStatus>();
    final api = _FakeChatApi(status: status.future);
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pump();

    expect(find.byKey(const Key('history-loading')), findsOneWidget);

    status.complete(_status());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('empty-history')), findsOneWidget);
    expect(find.text('Until restart'), findsOneWidget);
    expect(find.text('Dextero 0.0.1'), findsOneWidget);
  });

  testWidgets('keeps the connected chat controls usable at phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = DexteroController(
      api: _FakeChatApi(status: Future.value(_status())),
    );

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat-message')), 'Hello');
    await tester.pump();

    expect(find.byKey(const Key('compact-header')), findsOneWidget);
    expect(find.text('Dextero 0.0.1'), findsOneWidget);
    expect(find.byKey(const Key('send-message')), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('send-message'))).dx,
      lessThan(390),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('renders canonical submission and streamed chat activity', (
    tester,
  ) async {
    final api = _FakeChatApi(status: Future.value(_status()));
    final controller = DexteroController(
      api: api,
      correlationIdFactory: () => 'app-test-1',
    );

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('chat-message')),
      'Inspect the workspace',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pump();

    expect(api.submissions.single.message, 'Inspect the workspace');
    expect(api.submissions.single.correlationId, 'app-test-1');
    expect(find.text('Inspect the workspace'), findsOneWidget);
    expect(find.byKey(const Key('chat-message')), findsOneWidget);

    api.emit(
      _entry(
        sequence: 1,
        entryId: 'entry-1',
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.queued,
        content: 'Message queued',
      ),
    );
    api.emit(
      _entry(
        sequence: 2,
        entryId: 'entry-2',
        kind: ChatEntryKind.toolCall,
        status: ChatEntryStatus.running,
        content: 'list_files started',
        toolCallId: 'call-1',
        toolName: 'list_files',
      ),
    );
    api.emit(
      _entry(
        sequence: 3,
        entryId: 'entry-3',
        kind: ChatEntryKind.assistantMessage,
        status: ChatEntryStatus.completed,
        content: 'The workspace is ready.',
      ),
    );
    api.emit(
      _entry(
        sequence: 4,
        entryId: 'entry-4',
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.completed,
        content: 'Response completed',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('list_files started'), findsOneWidget);
    expect(find.text('The workspace is ready.'), findsOneWidget);
    expect(find.text('Response completed'), findsOneWidget);
    expect(controller.busy, isFalse);
  });

  testWidgets('keeps a visible submitting state until acceptance', (
    tester,
  ) async {
    final accepted = Completer<ChatSubmission>();
    final api = _FakeChatApi(
      status: Future.value(_status()),
      submitter: (_) => accepted.future,
    );
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chat-message')), 'Hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pump();

    expect(controller.submitting, isTrue);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    accepted.complete(_submission('Hello'));
    await tester.pumpAndSettle();

    expect(controller.submitting, isFalse);
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('restores an active run from history before enabling input', (
    tester,
  ) async {
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 0,
          entryId: 'entry-active-user',
          kind: ChatEntryKind.userMessage,
          status: ChatEntryStatus.submitted,
          content: 'Keep working',
        ),
        _entry(
          sequence: 1,
          entryId: 'entry-active-running',
          kind: ChatEntryKind.lifecycle,
          status: ChatEntryStatus.running,
          content: 'Codex is working',
        ),
      ],
    );
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();

    expect(controller.busy, isTrue);
    expect(
      tester.widget<TextField>(find.byKey(const Key('chat-message'))).enabled,
      isFalse,
    );

    api.emit(
      _entry(
        sequence: 2,
        entryId: 'entry-active-complete',
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.completed,
        content: 'Response completed',
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.busy, isFalse);
    expect(
      tester.widget<TextField>(find.byKey(const Key('chat-message'))).enabled,
      isTrue,
    );
  });

  testWidgets('explains configuration and server failures', (tester) async {
    final unconfigured = DexteroController.fromEnvironment(const {});
    await tester.pumpWidget(DexteroApp(controller: unconfigured));
    await tester.pump();

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.textContaining('make app-web'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    final failedStatus = Completer<HostStatus>();
    final failed = DexteroController(
      api: _FakeChatApi(status: failedStatus.future),
    );
    await tester.pumpWidget(DexteroApp(controller: failed));
    await tester.pump();
    failedStatus.completeError(StateError('offline'));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const Key('error-banner')), findsOneWidget);
    expect(find.textContaining('Cannot reach'), findsOneWidget);
  });
}

final class _FakeChatApi implements ChatApi {
  _FakeChatApi({
    required Future<HostStatus> status,
    this.submitter,
    this.initialHistory = const [],
  }) : statusFuture = status;

  final Future<HostStatus> statusFuture;
  final Future<ChatSubmission> Function(ChatSubmitRequest request)? submitter;
  final List<ChatEntry> initialHistory;
  final submissions = <ChatSubmitRequest>[];
  final _stream = StreamController<ChatEntry>.broadcast();

  void emit(ChatEntry entry) => _stream.add(entry);

  @override
  Future<void> close() async {}

  @override
  Future<List<ChatEntry>> history(String conversationId) async =>
      initialHistory;

  @override
  Future<HostStatus> status() => statusFuture;

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) =>
      _stream.stream;

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) {
    submissions.add(request);
    return submitter?.call(request) ??
        Future.value(_submission(request.message));
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
);

ChatSubmission _submission(String message) => ChatSubmission(
  conversationId: 'conversation-1',
  runId: 'run-1',
  correlationId: 'app-test-1',
  userEntry: _entry(
    sequence: 0,
    entryId: 'entry-0',
    kind: ChatEntryKind.userMessage,
    status: ChatEntryStatus.submitted,
    content: message,
  ),
);

ChatEntry _entry({
  required int sequence,
  required String entryId,
  required ChatEntryKind kind,
  required ChatEntryStatus status,
  required String content,
  String? toolCallId,
  String? toolName,
}) => ChatEntry(
  conversationId: 'conversation-1',
  entryId: entryId,
  sequence: sequence,
  kind: kind,
  status: status,
  content: content,
  createdAt: DateTime.utc(2026),
  correlationId: 'app-test-1',
  source: kind == ChatEntryKind.userMessage
      ? ChatEntrySource.user
      : ChatEntrySource.codex,
  truncated: false,
  runId: 'run-1',
  toolCallId: toolCallId,
  toolName: toolName,
);
