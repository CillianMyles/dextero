import 'dart:async';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'accepts the user message before the agent can produce output',
    () async {
      final agent = _ControlledAgent();
      final store = InMemoryChatHistoryStore(
        identifiers: _SequenceIdentifiers(),
      );
      addTearDown(store.close);
      final service = ChatService(
        store: store,
        agent: agent,
        identifiers: _SequenceIdentifiers(),
      );
      final conversation = await service.createConversation();

      final submission = await service.submit(
        conversationId: conversation.id,
        message: '  Inspect the workspace  ',
        correlationId: 'client-message-1',
      );
      final acceptedHistory = await store.history(conversation.id);

      expect(acceptedHistory.first, same(submission.userEntry));
      expect(submission.userEntry.content, 'Inspect the workspace');
      expect(submission.userEntry.sequence, 0);
      expect(submission.userEntry.runId, submission.runId);
      expect(submission.correlationId, 'client-message-1');
      expect(agent.started.isCompleted, isTrue);

      agent.release.complete();
      await _waitForTerminal(store, conversation.id, submission.runId);
      final history = await store.history(conversation.id);
      expect(history.map((entry) => entry.sequence), [0, 1, 2, 3, 4, 5, 6]);
      expect(history.map((entry) => entry.kind), [
        ChatEntryKind.userMessage,
        ChatEntryKind.lifecycle,
        ChatEntryKind.lifecycle,
        ChatEntryKind.toolCall,
        ChatEntryKind.toolResult,
        ChatEntryKind.assistantMessage,
        ChatEntryKind.lifecycle,
      ]);
      expect(history.map((entry) => entry.runId).toSet(), {submission.runId});
      expect(history.map((entry) => entry.correlationId).toSet(), {
        'client-message-1',
      });
      expect(history[3].toolCallId, 'call-7');
      expect(history[4].toolCallId, 'call-7');
    },
  );

  test('records redacted bounded errors and a failed lifecycle', () async {
    final store = InMemoryChatHistoryStore(identifiers: _SequenceIdentifiers());
    addTearDown(store.close);
    final service = ChatService(
      store: store,
      agent: _FailingAgent(),
      identifiers: _SequenceIdentifiers(),
    );
    final conversation = await service.createConversation();

    final submission = await service.submit(
      conversationId: conversation.id,
      message: 'go',
    );
    await _waitForTerminal(store, conversation.id, submission.runId);
    final history = await store.history(conversation.id);
    final error = history.singleWhere(
      (entry) => entry.kind == ChatEntryKind.error,
    );

    expect(error.content, contains('token=[REDACTED]'));
    expect(error.content, isNot(contains('super-secret')));
    expect(error.content.length, lessThanOrEqualTo(480));
    expect(error.truncated, isTrue);
    expect(history.last.status, ChatEntryStatus.failed);
  });

  test('rejects concurrent runs in one conversation', () async {
    final agent = _ControlledAgent();
    final store = InMemoryChatHistoryStore();
    addTearDown(store.close);
    final service = ChatService(store: store, agent: agent);
    final conversation = await service.createConversation();
    final first = await service.submit(
      conversationId: conversation.id,
      message: 'one',
    );

    await expectLater(
      service.submit(conversationId: conversation.id, message: 'two'),
      throwsStateError,
    );
    agent.release.complete();
    await _waitForTerminal(store, conversation.id, first.runId);
  });

  test(
    'preserves multiline assistant messages and strips terminal controls',
    () async {
      final store = InMemoryChatHistoryStore();
      addTearDown(store.close);
      final service = ChatService(store: store, agent: _MultilineAgent());
      final conversation = await service.createConversation();

      final submission = await service.submit(
        conversationId: conversation.id,
        message: 'show code',
      );
      await _waitForTerminal(store, conversation.id, submission.runId);

      final assistant = (await store.history(
        conversation.id,
      )).singleWhere((entry) => entry.kind == ChatEntryKind.assistantMessage);
      expect(assistant.content, 'First paragraph\n\n```dart\nprint(1);\n```');
      expect(assistant.content, isNot(contains('\x1b')));
      expect(assistant.truncated, isFalse);
    },
  );
}

final class _ControlledAgent implements ConversationAgent {
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
  }) async {
    started.complete();
    await release.future;
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.lifecycle,
        summary: SafeMetadata.text('Codex is working'),
      ),
    );
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.toolCallStarted,
        summary: SafeMetadata.text('read_file started for README.md'),
        toolCallId: 'call-7',
        toolName: 'read_file',
      ),
    );
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.toolCallCompleted,
        summary: SafeMetadata.text('read_file completed for README.md'),
        toolCallId: 'call-7',
        toolName: 'read_file',
        success: true,
      ),
    );
    await onEvent(
      ConversationAgentEvent(
        kind: ConversationAgentEventKind.assistantMessage,
        summary: SafeMetadata.text('The workspace is ready.'),
      ),
    );
    return const ConversationAgentResult(output: 'The workspace is ready.');
  }
}

final class _FailingAgent implements ConversationAgent {
  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
  }) async {
    throw StateError('token=super-secret ${'x' * 600}');
  }
}

final class _MultilineAgent implements ConversationAgent {
  @override
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
  }) async => const ConversationAgentResult(
    output: 'First paragraph\n\n```dart\nprint(1);\n```\x1b[2J',
  );
}

final class _SequenceIdentifiers implements IdentifierGenerator {
  var _next = 0;

  @override
  String next(String prefix) => '${prefix}_${_next++}';
}

Future<ChatHistoryEntry> _waitForTerminal(
  ChatHistoryStore store,
  String conversationId,
  String runId,
) => store
    .watch(conversationId)
    .firstWhere(
      (entry) =>
          entry.runId == runId &&
          entry.kind == ChatEntryKind.lifecycle &&
          {
            ChatEntryStatus.completed,
            ChatEntryStatus.failed,
          }.contains(entry.status),
    );
