import 'dart:async';

import 'package:dextero_core/dextero_core.dart' as core;
import 'package:dextero_server/src/auth/dextero_token_authenticator.dart';
import 'package:dextero_server/src/control/chat_runtime.dart';
import 'package:dextero_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';
import 'test_tools/test_server_config.dart';

void main() {
  late core.InMemoryChatHistoryStore store;
  late core.ChatService service;
  late String conversationId;
  late String selectedModel;

  setUp(() async {
    store = core.InMemoryChatHistoryStore();
    service = core.ChatService(store: store, agent: _FakeConversationAgent());
    conversationId = (await service.createConversation()).id;
    selectedModel = 'default';
    ChatRuntime.configure(
      chatService: service,
      defaultConversationId: conversationId,
      availableModels: const ['default', core.codexSparkModel],
      modelSelector: (modelName) async {
        await service.selectAgent(
          conversationId: conversationId,
          agent: _FakeConversationAgent(modelName: modelName),
        );
        selectedModel = modelName;
      },
    );
  });

  tearDown(() => store.close());

  withServerpod('Control endpoint', (sessionBuilder, endpoints) {
    final authenticatedSession = sessionBuilder.copyWith(
      authentication: AuthenticationOverride.authenticationInfo(
        'test-controller',
        const {},
      ),
    );

    test('rejects unauthenticated status calls', () async {
      await expectLater(
        endpoints.control.status(sessionBuilder),
        throwsA(isA<ServerpodUnauthenticatedException>()),
      );
    });

    test('authenticates only the configured bootstrap token', () async {
      final authenticator = DexteroTokenAuthenticator('a' * 32);
      final session = sessionBuilder.build();

      final accepted = await authenticator.authenticate(session, 'a' * 32);
      final rejected = await authenticator.authenticate(session, 'b' * 32);

      expect(accepted?.userIdentifier, 'dextero-controller');
      expect(rejected, isNull);
      await session.close();
    });

    test('reports the default volatile conversation', () async {
      final status = await endpoints.control.status(authenticatedSession);

      expect(status.name, 'Dextero');
      expect(status.persistence, 'memory');
      expect(status.conversationId, conversationId);
      expect(status.retentionNotice, contains('server restarts'));
      expect(status.databaseRequired, isFalse);
      expect(status.streamingAvailable, isTrue);
      expect(status.modelProvider, 'codex');
      expect(status.modelName, 'default');
      expect(status.availableModels, ['default', core.codexSparkModel]);
      expect(status.startedAt.isUtc, isTrue);
    });

    test('selects an advertised model before the first message', () async {
      final status = await endpoints.control.selectModel(
        authenticatedSession,
        core.codexSparkModel,
      );

      expect(status.modelName, core.codexSparkModel);
      expect(selectedModel, core.codexSparkModel);
    });

    test('rejects a stale client model before accepting its message', () async {
      await endpoints.control.selectModel(
        authenticatedSession,
        core.codexSparkModel,
      );

      await expectLater(
        endpoints.control.submitMessage(
          authenticatedSession,
          ChatSubmitRequest(
            conversationId: conversationId,
            message: 'Use the stale choice',
            modelName: 'default',
          ),
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(core.codexSparkModel),
          ),
        ),
      );
      expect(await store.history(conversationId), isEmpty);
    });

    test('rejects model changes after the first message', () async {
      final submission = await endpoints.control.submitMessage(
        authenticatedSession,
        ChatSubmitRequest(
          conversationId: conversationId,
          message: 'Start',
          modelName: 'default',
        ),
      );
      await store
          .watch(conversationId)
          .firstWhere(
            (entry) =>
                entry.runId == submission.runId &&
                entry.kind == core.ChatEntryKind.lifecycle &&
                entry.status == core.ChatEntryStatus.completed,
          );

      await expectLater(
        endpoints.control.selectModel(
          authenticatedSession,
          core.codexSparkModel,
        ),
        throwsStateError,
      );
    });

    test(
      'submits, stores, and streams canonical ordered chat history',
      () async {
        final submission = await endpoints.control.submitMessage(
          authenticatedSession,
          ChatSubmitRequest(
            conversationId: conversationId,
            message: 'Inspect the workspace',
            modelName: 'default',
            correlationId: 'client-1',
          ),
        );
        await store
            .watch(conversationId)
            .firstWhere(
              (entry) =>
                  entry.runId == submission.runId &&
                  entry.kind == core.ChatEntryKind.lifecycle &&
                  {
                    core.ChatEntryStatus.completed,
                    core.ChatEntryStatus.failed,
                  }.contains(entry.status),
            );

        final history = await endpoints.control.history(
          authenticatedSession,
          conversationId,
        );
        final streamed = await endpoints.control
            .streamHistory(authenticatedSession, conversationId, -1)
            .take(history.length)
            .toList();

        expect(submission.userEntry.sequence, 0);
        expect(submission.userEntry.entryId, isNotEmpty);
        expect(history.map((entry) => entry.sequence), [
          0,
          1,
          2,
          3,
          4,
          5,
          6,
          7,
        ]);
        expect(
          streamed.map((entry) => entry.entryId),
          history.map((entry) => entry.entryId),
        );
        expect(history.map((entry) => entry.runId).toSet(), {submission.runId});
        expect(history.map((entry) => entry.correlationId).toSet(), {
          'client-1',
        });
        expect(history.first.kind, ChatEntryKind.userMessage);
        expect(history.last.status, ChatEntryStatus.completed);
        expect(
          history
              .singleWhere((entry) => entry.kind == ChatEntryKind.toolCall)
              .content,
          'run_command started: printf "hello world"',
        );
        expect(
          history
              .singleWhere((entry) => entry.kind == ChatEntryKind.toolOutput)
              .content,
          'stdout:\nhello world',
        );
        expect(
          history
              .singleWhere((entry) => entry.kind == ChatEntryKind.toolResult)
              .content,
          contains('run_command completed (exit 0)'),
        );
      },
    );

    test('rejects empty messages before appending history', () async {
      await expectLater(
        endpoints.control.submitMessage(
          authenticatedSession,
          ChatSubmitRequest(
            conversationId: conversationId,
            message: '   ',
            modelName: 'default',
          ),
        ),
        throwsArgumentError,
      );
      expect(
        await endpoints.control.history(authenticatedSession, conversationId),
        isEmpty,
      );
    });

    test('rejects unknown conversation identifiers', () async {
      await expectLater(
        endpoints.control.history(authenticatedSession, 'missing'),
        throwsStateError,
      );
    });

    test('cancels an active run through the typed endpoint', () async {
      final transport = _CancellableGeminiTransport();
      service = core.ChatService(
        store: store,
        agent: core.ModelConversationAgent(
          model: core.GeminiModel(transport: transport),
          tools: const [],
          providerName: 'Gemini',
        ),
      );
      conversationId = (await service.createConversation()).id;
      ChatRuntime.configure(
        chatService: service,
        defaultConversationId: conversationId,
      );
      final submission = await endpoints.control.submitMessage(
        authenticatedSession,
        ChatSubmitRequest(
          conversationId: conversationId,
          message: 'Long task',
          modelName: 'default',
        ),
      );
      await transport.started.future;

      expect(
        await endpoints.control.cancelRun(
          authenticatedSession,
          conversationId,
          submission.runId,
        ),
        isTrue,
      );
      final terminal = await store
          .watch(conversationId)
          .firstWhere(
            (entry) =>
                entry.runId == submission.runId &&
                entry.kind == core.ChatEntryKind.lifecycle &&
                entry.status == core.ChatEntryStatus.cancelled,
          );
      expect(terminal.content, 'Response cancelled');
    });

    test('approves a pending action through the typed endpoint', () async {
      final agent = _ApprovalConversationAgent();
      service = core.ChatService(store: store, agent: agent);
      conversationId = (await service.createConversation()).id;
      ChatRuntime.configure(
        chatService: service,
        defaultConversationId: conversationId,
      );
      final submission = await endpoints.control.submitMessage(
        authenticatedSession,
        ChatSubmitRequest(
          conversationId: conversationId,
          message: 'Edit README.md',
          modelName: 'default',
        ),
      );
      final pending = await store
          .watch(conversationId)
          .firstWhere(
            (entry) =>
                entry.kind == core.ChatEntryKind.approval &&
                entry.status == core.ChatEntryStatus.pending,
          );

      expect(agent.executed, isFalse);
      expect(
        await endpoints.control.approveWork(
          authenticatedSession,
          conversationId,
          submission.runId,
          pending.approvalId!,
        ),
        isTrue,
      );
      await store
          .watch(conversationId)
          .firstWhere(
            (entry) =>
                entry.runId == submission.runId &&
                entry.kind == core.ChatEntryKind.lifecycle &&
                entry.status == core.ChatEntryStatus.completed,
          );

      expect(agent.executed, isTrue);
      final history = await endpoints.control.history(
        authenticatedSession,
        conversationId,
      );
      expect(
        history
            .where((entry) => entry.approvalId == pending.approvalId)
            .map((entry) => entry.status),
        [ChatEntryStatus.pending, ChatEntryStatus.approved],
      );
      expect(
        await endpoints.control.approveWork(
          authenticatedSession,
          conversationId,
          submission.runId,
          pending.approvalId!,
        ),
        isFalse,
      );
    });
  }, configOverride: useEphemeralApiPort);
}

final class _ApprovalConversationAgent
    implements core.ConversationAgent, core.ApprovalAwareConversationAgent {
  var executed = false;

  @override
  Future<core.ConversationAgentResult> run(
    String prompt, {
    required core.ConversationAgentEventSink onEvent,
    required core.CancellationToken cancellationToken,
  }) => runWithApproval(
    prompt,
    onEvent: onEvent,
    cancellationToken: cancellationToken,
  );

  @override
  Future<core.ConversationAgentResult> runWithApproval(
    String prompt, {
    required core.ConversationAgentEventSink onEvent,
    required core.CancellationToken cancellationToken,
    core.ToolApprovalRequester? onApprovalRequest,
  }) async {
    executed = await onApprovalRequest!(
      core.ToolApprovalRequest(
        toolCallId: 'endpoint-edit-1',
        toolName: 'edit_file',
        summary: core.SafeMetadata.approvalRequest('edit_file', const {
          'path': 'README.md',
          'oldText': 'old',
          'newText': 'new',
        }),
      ),
    );
    return const core.ConversationAgentResult(output: 'Edited README.md');
  }
}

final class _CancellableGeminiTransport implements core.GeminiTransport {
  final started = Completer<void>();

  @override
  Future<core.JsonMap> generateContent({
    required String model,
    required core.JsonMap request,
    core.CancellationToken? cancellationToken,
  }) async {
    started.complete();
    await cancellationToken!.whenCancelled;
    cancellationToken.throwIfCancellationRequested();
    throw StateError('unreachable');
  }
}

final class _FakeConversationAgent implements core.ConversationAgent {
  const _FakeConversationAgent({this.modelName = 'default'});

  final String modelName;

  @override
  Future<core.ConversationAgentResult> run(
    String prompt, {
    required core.ConversationAgentEventSink onEvent,
    required core.CancellationToken cancellationToken,
  }) async {
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.lifecycle,
        summary: core.SafeMetadata.text('$modelName is working'),
      ),
    );
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.toolCallStarted,
        summary: core.SafeMetadata.toolCall('run_command', const {
          'command': 'printf',
          'arguments': ['hello world'],
        }),
        toolCallId: 'tool-call-1',
        toolName: 'run_command',
      ),
    );
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.toolOutput,
        summary: core.SafeMetadata.message('stdout:\nhello world'),
        toolCallId: 'tool-call-1',
        toolName: 'run_command',
      ),
    );
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.toolCallCompleted,
        summary: core.SafeMetadata.toolResult('run_command', const {
          'exit_code': 0,
          'stdout': 'hello world\n',
          'stderr': '',
          'truncated': false,
        }, success: true),
        toolCallId: 'tool-call-1',
        toolName: 'run_command',
        success: true,
      ),
    );
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.assistantMessage,
        summary: core.SafeMetadata.text('Workspace inspected'),
      ),
    );
    return const core.ConversationAgentResult(output: 'Workspace inspected');
  }
}
