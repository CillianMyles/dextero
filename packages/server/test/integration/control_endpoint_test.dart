import 'dart:async';

import 'package:dextero_core/dextero_core.dart' as core;
import 'package:dextero_server/src/auth/dextero_token_authenticator.dart';
import 'package:dextero_server/src/control/chat_runtime.dart';
import 'package:dextero_server/src/generated/protocol.dart';
import 'package:serverpod/serverpod.dart' show ServerConfig, ServerpodConfig;
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';

void main() {
  late core.InMemoryChatHistoryStore store;
  late core.ChatService service;
  late String conversationId;

  setUp(() async {
    store = core.InMemoryChatHistoryStore();
    service = core.ChatService(store: store, agent: _FakeConversationAgent());
    conversationId = (await service.createConversation()).id;
    ChatRuntime.configure(
      chatService: service,
      defaultConversationId: conversationId,
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
      expect(status.startedAt.isUtc, isTrue);
    });

    test(
      'submits, stores, and streams canonical ordered chat history',
      () async {
        final submission = await endpoints.control.submitMessage(
          authenticatedSession,
          ChatSubmitRequest(
            conversationId: conversationId,
            message: 'Inspect the workspace',
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
        expect(history.map((entry) => entry.sequence), [0, 1, 2, 3, 4, 5, 6]);
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
      },
    );

    test('rejects empty messages before appending history', () async {
      await expectLater(
        endpoints.control.submitMessage(
          authenticatedSession,
          ChatSubmitRequest(conversationId: conversationId, message: '   '),
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
      final cancellable = _CancellableConversationAgent();
      service = core.ChatService(store: store, agent: cancellable);
      conversationId = (await service.createConversation()).id;
      ChatRuntime.configure(
        chatService: service,
        defaultConversationId: conversationId,
      );
      final submission = await endpoints.control.submitMessage(
        authenticatedSession,
        ChatSubmitRequest(conversationId: conversationId, message: 'Long task'),
      );
      await cancellable.started.future;

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
  }, configOverride: _useEphemeralApiPort);
}

ServerpodConfig _useEphemeralApiPort(ServerpodConfig config) => config.copyWith(
  apiServer: ServerConfig(
    port: 0,
    publicHost: 'localhost',
    publicPort: 0,
    publicScheme: 'http',
  ),
);

final class _CancellableConversationAgent implements core.ConversationAgent {
  final started = Completer<void>();

  @override
  Future<core.ConversationAgentResult> run(
    String prompt, {
    required core.ConversationAgentEventSink onEvent,
    required core.CancellationToken cancellationToken,
  }) async {
    started.complete();
    await cancellationToken.whenCancelled;
    cancellationToken.throwIfCancellationRequested();
    throw StateError('unreachable');
  }
}

final class _FakeConversationAgent implements core.ConversationAgent {
  @override
  Future<core.ConversationAgentResult> run(
    String prompt, {
    required core.ConversationAgentEventSink onEvent,
    required core.CancellationToken cancellationToken,
  }) async {
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.lifecycle,
        summary: core.SafeMetadata.text('Codex is working'),
      ),
    );
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.toolCallStarted,
        summary: core.SafeMetadata.text('list_files started'),
        toolCallId: 'tool-call-1',
        toolName: 'list_files',
      ),
    );
    await onEvent(
      core.ConversationAgentEvent(
        kind: core.ConversationAgentEventKind.toolCallCompleted,
        summary: core.SafeMetadata.text('list_files completed (4 entries)'),
        toolCallId: 'tool-call-1',
        toolName: 'list_files',
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
