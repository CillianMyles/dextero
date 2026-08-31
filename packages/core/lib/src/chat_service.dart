import 'dart:async';

import 'chat_history.dart';
import 'safe_metadata.dart';

enum ConversationAgentEventKind {
  lifecycle,
  assistantMessage,
  toolCallStarted,
  toolCallCompleted,
  error,
}

final class ConversationAgentEvent {
  const ConversationAgentEvent({
    required this.kind,
    required this.summary,
    this.toolCallId,
    this.toolName,
    this.success,
    this.retrying = false,
  });

  final ConversationAgentEventKind kind;
  final SafeSummary summary;
  final String? toolCallId;
  final String? toolName;
  final bool? success;
  final bool retrying;
}

final class ConversationAgentResult {
  const ConversationAgentResult({required this.output});

  final String output;
}

typedef ConversationAgentEventSink =
    FutureOr<void> Function(ConversationAgentEvent event);

abstract interface class ConversationAgent {
  Future<ConversationAgentResult> run(
    String prompt, {
    required ConversationAgentEventSink onEvent,
  });
}

final class ChatSubmission {
  const ChatSubmission({
    required this.conversationId,
    required this.runId,
    required this.correlationId,
    required this.userEntry,
  });

  final String conversationId;
  final String runId;
  final String correlationId;
  final ChatHistoryEntry userEntry;
}

/// Accepts messages synchronously into history, then orchestrates the run.
final class ChatService {
  ChatService({
    required ChatHistoryStore store,
    required ConversationAgent agent,
    IdentifierGenerator? identifiers,
  }) : _store = store,
       _agent = agent,
       _identifiers = identifiers ?? SecureIdentifierGenerator();

  final ChatHistoryStore _store;
  final ConversationAgent _agent;
  final IdentifierGenerator _identifiers;
  final Set<String> _activeConversations = {};
  Future<void> _submissionLock = Future.value();

  ChatHistoryStore get store => _store;

  Future<ChatConversation> createConversation() => _store.createConversation();

  Future<ChatSubmission> submit({
    required String conversationId,
    required String message,
    String? correlationId,
  }) async {
    final normalized = message.trim();
    if (normalized.isEmpty || normalized.length > 32000) {
      throw ArgumentError.value(
        message,
        'message',
        'must contain between 1 and 32000 characters',
      );
    }

    return _withSubmissionLock(() async {
      if (await _store.conversation(conversationId) == null) {
        throw StateError('Unknown conversation: $conversationId');
      }
      if (_activeConversations.contains(conversationId)) {
        throw StateError(
          'A response is already running for this conversation.',
        );
      }

      final runId = _identifiers.next('run');
      final effectiveCorrelationId = _normalizeCorrelationId(correlationId);
      final userEntry = await _store.append(
        conversationId,
        PendingChatEntry(
          kind: ChatEntryKind.userMessage,
          status: ChatEntryStatus.submitted,
          content: normalized,
          correlationId: effectiveCorrelationId,
          source: ChatEntrySource.user,
          runId: runId,
        ),
      );
      _activeConversations.add(conversationId);
      final completion = _process(
        conversationId: conversationId,
        runId: runId,
        correlationId: effectiveCorrelationId,
        prompt: normalized,
      );
      unawaited(completion);
      return ChatSubmission(
        conversationId: conversationId,
        runId: runId,
        correlationId: effectiveCorrelationId,
        userEntry: userEntry,
      );
    });
  }

  Future<void> _process({
    required String conversationId,
    required String runId,
    required String correlationId,
    required String prompt,
  }) async {
    var assistantRecorded = false;
    var terminalAgentErrorRecorded = false;
    try {
      await _append(
        conversationId,
        runId,
        correlationId,
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.queued,
        content: 'Message queued',
        source: ChatEntrySource.dextero,
      );
      final result = await _agent.run(
        prompt,
        onEvent: (event) async {
          if (event.kind == ConversationAgentEventKind.assistantMessage) {
            assistantRecorded = true;
          }
          if (event.kind == ConversationAgentEventKind.error &&
              !event.retrying) {
            terminalAgentErrorRecorded = true;
          }
          await _recordAgentEvent(conversationId, runId, correlationId, event);
        },
      );
      if (!assistantRecorded) {
        final output = SafeMetadata.message(result.output);
        await _append(
          conversationId,
          runId,
          correlationId,
          kind: ChatEntryKind.assistantMessage,
          status: ChatEntryStatus.completed,
          content: output.text,
          source: ChatEntrySource.codex,
          truncated: output.truncated,
        );
      }
      await _append(
        conversationId,
        runId,
        correlationId,
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.completed,
        content: 'Response completed',
        source: ChatEntrySource.dextero,
      );
    } on Object catch (error) {
      if (!terminalAgentErrorRecorded) {
        final summary = SafeMetadata.text(error);
        await _append(
          conversationId,
          runId,
          correlationId,
          kind: ChatEntryKind.error,
          status: ChatEntryStatus.failed,
          content: summary.text,
          source: ChatEntrySource.dextero,
          truncated: summary.truncated,
        );
      }
      await _append(
        conversationId,
        runId,
        correlationId,
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.failed,
        content: 'Response failed',
        source: ChatEntrySource.dextero,
      );
    } finally {
      await _withSubmissionLock(() async {
        _activeConversations.remove(conversationId);
      });
    }
  }

  Future<void> _recordAgentEvent(
    String conversationId,
    String runId,
    String correlationId,
    ConversationAgentEvent event,
  ) async {
    final (kind, status) = switch (event.kind) {
      ConversationAgentEventKind.lifecycle => (
        ChatEntryKind.lifecycle,
        ChatEntryStatus.running,
      ),
      ConversationAgentEventKind.assistantMessage => (
        ChatEntryKind.assistantMessage,
        ChatEntryStatus.completed,
      ),
      ConversationAgentEventKind.toolCallStarted => (
        ChatEntryKind.toolCall,
        ChatEntryStatus.running,
      ),
      ConversationAgentEventKind.toolCallCompleted => (
        ChatEntryKind.toolResult,
        event.success == false
            ? ChatEntryStatus.failed
            : ChatEntryStatus.completed,
      ),
      ConversationAgentEventKind.error => (
        ChatEntryKind.error,
        event.retrying ? ChatEntryStatus.warning : ChatEntryStatus.failed,
      ),
    };
    await _append(
      conversationId,
      runId,
      correlationId,
      kind: kind,
      status: status,
      content: event.summary.text,
      source: ChatEntrySource.codex,
      truncated: event.summary.truncated,
      toolCallId: event.toolCallId == null
          ? null
          : SafeMetadata.identifier(event.toolCallId!),
      toolName: event.toolName == null
          ? null
          : SafeMetadata.toolName(event.toolName!),
    );
  }

  Future<ChatHistoryEntry> _append(
    String conversationId,
    String runId,
    String correlationId, {
    required ChatEntryKind kind,
    required ChatEntryStatus status,
    required String content,
    required ChatEntrySource source,
    bool truncated = false,
    String? toolCallId,
    String? toolName,
  }) => _store.append(
    conversationId,
    PendingChatEntry(
      kind: kind,
      status: status,
      content: content,
      correlationId: correlationId,
      source: source,
      truncated: truncated,
      runId: runId,
      toolCallId: toolCallId,
      toolName: toolName,
    ),
  );

  String _normalizeCorrelationId(String? value) {
    if (value == null || value.trim().isEmpty) {
      return _identifiers.next('correlation');
    }
    final normalized = value.trim();
    if (normalized.length > 160 ||
        !RegExp(r'^[a-zA-Z0-9_.:-]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'correlationId',
        'must be 1 to 160 identifier characters',
      );
    }
    return normalized;
  }

  Future<T> _withSubmissionLock<T>(Future<T> Function() action) async {
    final previous = _submissionLock;
    final completer = Completer<void>();
    _submissionLock = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }
}
