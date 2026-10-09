import 'dart:async';

import 'package:dextero_app/main.dart';
import 'package:dextero_app/src/dextero_controller.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shad/shad.dart';

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
    expect(find.text('Gemini · gemini-2.5-flash'), findsOneWidget);
    expect(find.byType(ShadEmpty), findsOneWidget);
    expect(find.text('Gemini API key'), findsOneWidget);
    expect(find.byType(ShadBadge), findsNWidgets(3));
    expect(find.byType(ShadInput), findsOneWidget);
  });

  testWidgets('selects a model before the first message', (tester) async {
    final api = _FakeChatApi(status: Future.value(_status()));
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gemini · gemini-pro').last);
    await tester.pumpAndSettle();

    expect(api.modelSelections, ['gemini:gemini-pro']);
    expect(controller.hostStatus!.modelName, 'gemini-pro');
    expect(find.text('Gemini · gemini-pro'), findsOneWidget);
  });

  testWidgets('switches provider and submits the selected combination', (
    tester,
  ) async {
    final api = _FakeChatApi(status: Future.value(_status()));
    final controller = DexteroController(api: api);
    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('model-selector')));
    await tester.pumpAndSettle();
    expect(find.text('Dextero harness tools · Gemini API key'), findsWidgets);
    expect(
      find.text('Codex tools + Dextero harness tools · Codex CLI login'),
      findsWidgets,
    );
    await tester.tap(find.text('Codex · gpt-5.3-codex-spark').last);
    await tester.pumpAndSettle();
    expect(controller.hostStatus!.modelProvider, 'codex');
    expect(find.text('Codex CLI login'), findsOneWidget);
    expect(api.modelSelections, ['codex:gpt-5.3-codex-spark']);
    await tester.enterText(find.byKey(const Key('chat-message')), 'Start');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pumpAndSettle();
    expect(api.submissions.single.modelProvider, 'codex');
    expect(api.submissions.single.modelName, 'gpt-5.3-codex-spark');
    expect(controller.canSelectModel, isFalse);
    expect(await controller.selectModel('gemini:gemini-2.5-flash'), isFalse);
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

  testWidgets(
    'renders rich safe activity metadata and expandable identifiers',
    (tester) async {
      final api = _FakeChatApi(
        status: Future.value(_status()),
        initialHistory: [
          _entry(
            sequence: 7,
            entryId: 'entry-rich-tool',
            kind: ChatEntryKind.toolCall,
            status: ChatEntryStatus.warning,
            content: 'read_file started for lib/main.dart',
            toolCallId: 'call-7',
            toolName: 'read_file',
            correlationId: 'correlation-7',
            runId: 'run-7',
            truncated: true,
            family: ChatEventFamily.warning,
            createdAt: DateTime.utc(2026, 9, 1, 19, 57, 21),
          ),
        ],
      );

      await tester.pumpWidget(
        DexteroApp(controller: DexteroController(api: api)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Read file started'), findsOneWidget);
      expect(find.text('read_file started for lib/main.dart'), findsOneWidget);
      expect(find.text('Warning'), findsOneWidget);
      expect(find.text('Truncated'), findsOneWidget);
      expect(find.text('2026-09-01 19:57:21 UTC'), findsOneWidget);
      expect(find.text('• Model'), findsOneWidget);
      expect(find.text('run-7'), findsNothing);
      expect(find.text('call-7'), findsNothing);

      await tester.tap(
        find.byKey(const Key('activity-details-entry-rich-tool')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Sequence'), findsOneWidget);
      expect(find.text('Event'), findsOneWidget);
      expect(find.text('v1 · Warning'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('Run ID'), findsOneWidget);
      expect(find.text('run-7'), findsOneWidget);
      expect(find.text('Correlation ID'), findsOneWidget);
      expect(find.text('correlation-7'), findsOneWidget);
      expect(find.text('Tool call'), findsOneWidget);
      expect(find.text('call-7'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(find.text('run-7'), findsNothing);
    },
  );

  testWidgets('renders command, output, and tool error diagnostics', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 1,
          entryId: 'entry-command',
          kind: ChatEntryKind.toolCall,
          status: ChatEntryStatus.running,
          content: 'run_command started: sed -n 1,20p README.md',
          toolCallId: 'command-1',
          toolName: 'run_command',
        ),
        _entry(
          sequence: 2,
          entryId: 'entry-command-output',
          kind: ChatEntryKind.toolOutput,
          status: ChatEntryStatus.running,
          content: 'stdout:\n# Dextero\n\nLocal agent.',
          toolCallId: 'command-1',
          toolName: 'run_command',
        ),
        _entry(
          sequence: 3,
          entryId: 'entry-read-error',
          kind: ChatEntryKind.toolResult,
          status: ChatEntryStatus.failed,
          content: 'read_file failed: File not found: missing.txt',
          toolCallId: 'read-1',
          toolName: 'read_file',
        ),
      ],
    );

    await tester.pumpWidget(
      DexteroApp(controller: DexteroController(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run command started'), findsOneWidget);
    expect(
      find.text('run_command started: sed -n 1,20p README.md'),
      findsOneWidget,
    );
    expect(find.text('Run command output'), findsOneWidget);
    expect(find.text('stdout:\n# Dextero\n\nLocal agent.'), findsOneWidget);
    expect(find.text('Read file result'), findsOneWidget);
    expect(
      find.text('read_file failed: File not found: missing.txt'),
      findsOneWidget,
    );
  });

  testWidgets('renders run usage receipts and the out-of-credit state', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 1,
          entryId: 'entry-usage',
          kind: ChatEntryKind.usage,
          status: ChatEntryStatus.completed,
          content:
              'Anthropic · claude-haiku-4-5 · Anthropic API key · '
              '10,230 input · 50 output · \$0.0069',
          family: ChatEventFamily.usage,
          usage: ChatRunUsage(
            provider: 'Anthropic',
            model: 'claude-haiku-4-5',
            authSource: 'Anthropic API key',
            inputTokens: 930,
            outputTokens: 50,
            cacheCreationInputTokens: 4200,
            cacheReadInputTokens: 5100,
            modelRequests: 2,
            costMicrosUsd: 6940,
          ),
        ),
      ],
    );
    await tester.pumpWidget(
      DexteroApp(controller: DexteroController(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Run usage'), findsOneWidget);
    await tester.tap(find.byKey(const Key('activity-details-entry-usage')));
    await tester.pumpAndSettle();
    expect(find.text('claude-haiku-4-5'), findsOneWidget);
    expect(find.text('Anthropic API key'), findsOneWidget);
    expect(
      find.text('930 input · 5100 cache read · 4200 cache write · 50 output'),
      findsOneWidget,
    );
    expect(find.text('0.006940'), findsOneWidget);

    api.emit(
      _entry(
        sequence: 2,
        entryId: 'entry-credit',
        kind: ChatEntryKind.error,
        status: ChatEntryStatus.failed,
        content:
            'Out of Anthropic API credit: Your credit balance is too low. '
            'Add credit or raise the workspace spend limit in the Anthropic '
            'Console, or choose another model.',
        errorCode: ChatErrorCode.creditExhausted,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Out of credit'), findsOneWidget);
    expect(find.text('Agent error'), findsNothing);
    expect(
      find.textContaining('Out of Anthropic API credit'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('keeps expanded failed activity responsive at compact width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 1,
          entryId: 'entry-compact-error',
          kind: ChatEntryKind.error,
          status: ChatEntryStatus.failed,
          content: 'Codex could not complete the requested operation safely.',
          correlationId: 'compact-correlation-with-a-long-identifier',
          runId: 'compact-run-with-a-long-identifier',
        ),
      ],
    );

    await tester.pumpWidget(
      DexteroApp(controller: DexteroController(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Agent error'), findsOneWidget);
    expect(find.text('Failed'), findsOneWidget);
    await tester.tap(
      find.byKey(const Key('activity-details-entry-compact-error')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('compact-correlation-with-a-long-identifier'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
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
    expect(find.byType(ShadSpinner), findsOneWidget);

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
      tester.widget<ShadInput>(find.byKey(const Key('chat-message'))).enabled,
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
      tester.widget<ShadInput>(find.byKey(const Key('chat-message'))).enabled,
      isTrue,
    );
  });

  testWidgets('cancels the active run from the composer', (tester) async {
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 0,
          entryId: 'entry-cancel-user',
          kind: ChatEntryKind.userMessage,
          status: ChatEntryStatus.submitted,
          content: 'Keep working',
        ),
        _entry(
          sequence: 1,
          entryId: 'entry-cancel-running',
          kind: ChatEntryKind.lifecycle,
          status: ChatEntryStatus.running,
          content: 'Codex is working',
        ),
      ],
    );
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('cancel-run')), findsOneWidget);

    await tester.tap(find.byKey(const Key('cancel-run')));
    await tester.pumpAndSettle();

    expect(api.cancellations, [('conversation-1', 'run-1')]);
    expect(controller.canCancel, isFalse);
    expect(await controller.cancelActiveRun(), isFalse);
    expect(api.cancellations, hasLength(1));
    api.emit(
      _entry(
        sequence: 2,
        entryId: 'entry-delayed-approval',
        kind: ChatEntryKind.approval,
        status: ChatEntryStatus.pending,
        content: 'edit_file requires approval for README.md',
        toolCallId: 'edit-call-delayed',
        toolName: 'edit_file',
        approvalId: 'approval-delayed',
        family: ChatEventFamily.approval,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.pendingApproval, isNull);
    expect(controller.canApprove, isFalse);
    expect(find.byKey(const Key('approval-prompt')), findsNothing);
    expect(await controller.approvePendingWork(), isFalse);
    expect(api.approvals, isEmpty);
    api.emit(
      _entry(
        sequence: 3,
        entryId: 'entry-cancelled',
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.cancelled,
        content: 'Response cancelled',
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.busy, isFalse);
    expect(find.byKey(const Key('send-message')), findsOneWidget);
  });

  testWidgets('keeps an accepted approval resolved while history catches up', (
    tester,
  ) async {
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 0,
          entryId: 'entry-approval-pending',
          kind: ChatEntryKind.approval,
          status: ChatEntryStatus.pending,
          content:
              'edit_file requires approval for README.md\n'
              '--- old text\n-old\n+++ new text\n+new',
          toolCallId: 'edit-call-1',
          toolName: 'edit_file',
          approvalId: 'approval-1',
          family: ChatEventFamily.approval,
        ),
      ],
    );
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approval-prompt')), findsOneWidget);
    expect(find.text('Approval required'), findsNWidgets(2));
    expect(
      find.text(
        'edit_file requires approval for README.md\n'
        '--- old text\n-old\n+++ new text\n+new',
      ),
      findsNWidgets(2),
    );

    await tester.tap(find.byKey(const Key('approve-work')));
    await tester.pumpAndSettle();

    expect(api.approvals, [('conversation-1', 'run-1', 'approval-1')]);
    expect(controller.pendingApproval, isNull);
    expect(controller.canApprove, isFalse);
    expect(find.byKey(const Key('approval-prompt')), findsNothing);
    expect(await controller.approvePendingWork(), isFalse);
    expect(api.approvals, hasLength(1));
    api.emit(
      _entry(
        sequence: 1,
        entryId: 'entry-approval-approved',
        kind: ChatEntryKind.approval,
        status: ChatEntryStatus.approved,
        content: 'edit_file approved',
        toolCallId: 'edit-call-1',
        toolName: 'edit_file',
        approvalId: 'approval-1',
        family: ChatEventFamily.approval,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('approval-prompt')), findsNothing);
    expect(find.text('Action approved'), findsOneWidget);
  });

  testWidgets('distinguishes approved and cancelled approval history', (
    tester,
  ) async {
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 0,
          entryId: 'entry-approval-approved',
          kind: ChatEntryKind.approval,
          status: ChatEntryStatus.approved,
          content: 'edit_file approved',
          approvalId: 'approval-1',
          family: ChatEventFamily.approval,
        ),
        _entry(
          sequence: 1,
          entryId: 'entry-approval-cancelled',
          kind: ChatEntryKind.approval,
          status: ChatEntryStatus.cancelled,
          content: 'edit_file approval cancelled',
          approvalId: 'approval-2',
          family: ChatEventFamily.approval,
        ),
      ],
    );

    await tester.pumpWidget(
      DexteroApp(controller: DexteroController(api: api)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Action approved'), findsOneWidget);
    expect(find.byIcon(LucideIcons.shieldCheck), findsOneWidget);
    expect(find.text('Approval cancelled'), findsOneWidget);
    expect(find.byIcon(LucideIcons.circleStop), findsOneWidget);
  });

  testWidgets('keeps approval disabled through accepted cancellation', (
    tester,
  ) async {
    final cancelled = Completer<bool>();
    final api = _FakeChatApi(
      status: Future.value(_status()),
      canceller: (_, _) => cancelled.future,
      initialHistory: [_pendingApprovalEntry()],
    );
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('cancel-run')));
    await tester.pump();

    expect(controller.cancelling, isTrue);
    expect(controller.canApprove, isFalse);
    expect(
      tester.widget<ShadButton>(find.byKey(const Key('approve-work'))).enabled,
      isFalse,
    );
    expect(await controller.approvePendingWork(), isFalse);
    expect(api.approvals, isEmpty);

    cancelled.complete(true);
    await tester.pumpAndSettle();

    expect(controller.pendingApproval, isNull);
    expect(controller.canApprove, isFalse);
    expect(find.byKey(const Key('approval-prompt')), findsNothing);
    expect(await controller.approvePendingWork(), isFalse);
    expect(api.approvals, isEmpty);

    api.emit(
      _entry(
        sequence: 1,
        entryId: 'entry-approval-cancelled',
        kind: ChatEntryKind.approval,
        status: ChatEntryStatus.cancelled,
        content: 'edit_file approval cancelled',
        toolCallId: 'edit-call-1',
        toolName: 'edit_file',
        approvalId: 'approval-1',
        family: ChatEventFamily.approval,
      ),
    );
    await tester.pumpAndSettle();
    expect(controller.pendingApproval, isNull);
  });

  testWidgets('disables cancellation while approval is in flight', (
    tester,
  ) async {
    final approved = Completer<bool>();
    final api = _FakeChatApi(
      status: Future.value(_status()),
      approver: (_, _, _) => approved.future,
      initialHistory: [_pendingApprovalEntry()],
    );
    final controller = DexteroController(api: api);

    await tester.pumpWidget(DexteroApp(controller: controller));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('approve-work')));
    await tester.pump();

    expect(controller.approving, isTrue);
    expect(controller.canCancel, isFalse);
    expect(
      tester
          .widget<ShadIconButton>(find.byKey(const Key('cancel-run')))
          .enabled,
      isFalse,
    );
    expect(await controller.cancelActiveRun(), isFalse);
    expect(api.cancellations, isEmpty);

    approved.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('keeps a large approval preview bounded and scrollable', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final api = _FakeChatApi(
      status: Future.value(_status()),
      initialHistory: [
        _entry(
          sequence: 0,
          entryId: 'entry-large-approval',
          kind: ChatEntryKind.approval,
          status: ChatEntryStatus.pending,
          content: List.generate(300, (index) => '-line $index').join('\n'),
          toolCallId: 'edit-call-large',
          toolName: 'edit_file',
          approvalId: 'approval-large',
          family: ChatEventFamily.approval,
        ),
      ],
    );

    await tester.pumpWidget(
      DexteroApp(controller: DexteroController(api: api)),
    );
    await tester.pumpAndSettle();

    final preview = find.byKey(const Key('approval-preview'));
    expect(preview, findsOneWidget);
    expect(
      find.descendant(
        of: preview,
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(preview).height, lessThanOrEqualTo(144));
    expect(find.byKey(const Key('approve-work')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('explains configuration and server failures', (tester) async {
    final unconfigured = DexteroController.fromEnvironment(const {});
    await tester.pumpWidget(DexteroApp(controller: unconfigured));
    await tester.pump();

    expect(find.text('Disconnected'), findsOneWidget);
    expect(find.textContaining('make app-<platform>'), findsOneWidget);

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
    this.canceller,
    this.approver,
    this.initialHistory = const [],
  }) : statusFuture = status;

  final Future<HostStatus> statusFuture;
  final Future<ChatSubmission> Function(ChatSubmitRequest request)? submitter;
  final Future<bool> Function(String conversationId, String runId)? canceller;
  final Future<bool> Function(
    String conversationId,
    String runId,
    String approvalId,
  )?
  approver;
  final List<ChatEntry> initialHistory;
  final submissions = <ChatSubmitRequest>[];
  final modelSelections = <String>[];
  final cancellations = <(String, String)>[];
  final approvals = <(String, String, String)>[];
  final _stream = StreamController<ChatEntry>.broadcast();

  void emit(ChatEntry entry) => _stream.add(entry);

  @override
  Future<void> close() async {}

  @override
  Future<bool> cancelRun(String conversationId, String runId) {
    cancellations.add((conversationId, runId));
    return canceller?.call(conversationId, runId) ?? Future.value(true);
  }

  @override
  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  ) {
    approvals.add((conversationId, runId, approvalId));
    return approver?.call(conversationId, runId, approvalId) ??
        Future.value(true);
  }

  @override
  Future<List<ChatEntry>> history(String conversationId) async =>
      initialHistory;

  @override
  Future<HostStatus> status() => statusFuture;

  @override
  Future<HostStatus> selectModel(String modelName) async {
    modelSelections.add(modelName);
    return _status(modelName: modelName.split(':').last);
  }

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
        authSource: 'Codex CLI login',
      ),
    for (final model in const ['gemini-2.5-flash', 'gemini-pro'])
      ModelOption(
        id: 'gemini:$model',
        provider: 'gemini',
        modelName: model,
        label: 'Gemini · $model',
        toolDescription: 'Dextero harness tools',
        authSource: 'Gemini API key',
      ),
  ],
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

ChatEntry _pendingApprovalEntry() => _entry(
  sequence: 0,
  entryId: 'entry-approval-pending',
  kind: ChatEntryKind.approval,
  status: ChatEntryStatus.pending,
  content: 'edit_file requires approval for README.md',
  toolCallId: 'edit-call-1',
  toolName: 'edit_file',
  approvalId: 'approval-1',
  family: ChatEventFamily.approval,
);

ChatEntry _entry({
  required int sequence,
  required String entryId,
  required ChatEntryKind kind,
  required ChatEntryStatus status,
  required String content,
  String? toolCallId,
  String? toolName,
  String? approvalId,
  String correlationId = 'app-test-1',
  String? runId = 'run-1',
  bool truncated = false,
  DateTime? createdAt,
  ChatEventFamily family = ChatEventFamily.task,
  ChatRunUsage? usage,
  ChatErrorCode? errorCode,
}) => ChatEntry(
  family: family,
  usage: usage,
  errorCode: errorCode,
  conversationId: 'conversation-1',
  entryId: entryId,
  sequence: sequence,
  kind: kind,
  status: status,
  content: content,
  createdAt: createdAt ?? DateTime.utc(2026),
  correlationId: correlationId,
  source: kind == ChatEntryKind.userMessage
      ? ChatEntrySource.user
      : ChatEntrySource.model,
  truncated: truncated,
  runId: runId,
  toolCallId: toolCallId,
  toolName: toolName,
  approvalId: approvalId,
);
