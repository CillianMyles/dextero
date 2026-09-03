import 'dart:async';

import 'approval.dart';
import 'cancellation.dart';
import 'chat_history.dart';
import 'safe_metadata.dart';

enum ConversationAgentEventKind {
  lifecycle,
  assistantMessage,
  assistantDelta,
  toolCallStarted,
  toolOutput,
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
    required CancellationToken cancellationToken,
  });
}

/// Optional conversation-agent contract for pausing before gated tool calls.
abstract interface class ApprovalAwareConversationAgent {
  Future<ConversationAgentResult> runWithApproval(
    String prompt, {
    required ConversationAgentEventSink onEvent,
    required CancellationToken cancellationToken,
    ToolApprovalRequester? onApprovalRequest,
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
       _defaultAgent = agent,
       _identifiers = identifiers ?? SecureIdentifierGenerator();

  final ChatHistoryStore _store;
  final ConversationAgent _defaultAgent;
  final IdentifierGenerator _identifiers;
  final Map<String, ConversationAgent> _agents = {};
  final Map<String, _ActiveRun> _activeRuns = {};
  final Map<String, _PendingApproval> _pendingApprovals = {};
  Future<void> _submissionLock = Future.value();

  ChatHistoryStore get store => _store;

  Future<ChatConversation> createConversation() async {
    final conversation = await _store.createConversation();
    _agents[conversation.id] = _defaultAgent;
    return conversation;
  }

  /// Replaces the conversation agent before the first message is accepted.
  Future<void> selectAgent({
    required String conversationId,
    required ConversationAgent agent,
  }) => _withSubmissionLock(() async {
    if (await _store.conversation(conversationId) == null) {
      throw StateError('Unknown conversation: $conversationId');
    }
    if (_activeRuns.containsKey(conversationId) ||
        (await _store.history(conversationId)).isNotEmpty) {
      throw StateError(
        'The model can only be changed before the first message.',
      );
    }
    _agents[conversationId] = agent;
  });

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
      if (_activeRuns.containsKey(conversationId)) {
        throw StateError(
          'A response is already running for this conversation.',
        );
      }
      final agent = _agents[conversationId] ?? _defaultAgent;

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
      final cancellation = CancellationController();
      _activeRuns[conversationId] = _ActiveRun(
        runId: runId,
        cancellation: cancellation,
      );
      final completion = _process(
        conversationId: conversationId,
        runId: runId,
        correlationId: effectiveCorrelationId,
        prompt: normalized,
        agent: agent,
        cancellationToken: cancellation.token,
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

  Future<bool> cancel({
    required String conversationId,
    required String runId,
  }) => _withSubmissionLock(() async {
    if (await _store.conversation(conversationId) == null) {
      throw StateError('Unknown conversation: $conversationId');
    }
    final active = _activeRuns[conversationId];
    if (active == null || active.runId != runId) return false;
    return active.cancellation.cancel();
  });

  /// Approves the matching pending tool action exactly once.
  Future<bool> approve({
    required String conversationId,
    required String runId,
    required String approvalId,
  }) => _withSubmissionLock(() async {
    if (await _store.conversation(conversationId) == null) {
      throw StateError('Unknown conversation: $conversationId');
    }
    final pending = _pendingApprovals[approvalId];
    if (pending == null ||
        pending.conversationId != conversationId ||
        pending.runId != runId) {
      return false;
    }
    final active = _activeRuns[conversationId];
    if (active == null ||
        active.runId != runId ||
        active.cancellation.token.isCancellationRequested) {
      return false;
    }
    await _append(
      conversationId,
      runId,
      pending.correlationId,
      kind: ChatEntryKind.approval,
      status: ChatEntryStatus.approved,
      content: '${pending.request.toolName} approved',
      source: ChatEntrySource.user,
      toolCallId: pending.request.toolCallId,
      toolName: pending.request.toolName,
      approvalId: approvalId,
    );
    _pendingApprovals.remove(approvalId);
    pending.decision.complete(true);
    return true;
  });

  Future<void> _process({
    required String conversationId,
    required String runId,
    required String correlationId,
    required String prompt,
    required ConversationAgent agent,
    required CancellationToken cancellationToken,
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
      cancellationToken.throwIfCancellationRequested();
      FutureOr<void> recordEvent(ConversationAgentEvent event) async {
        cancellationToken.throwIfCancellationRequested();
        if (event.kind == ConversationAgentEventKind.assistantMessage) {
          assistantRecorded = true;
        }
        if (event.kind == ConversationAgentEventKind.error && !event.retrying) {
          terminalAgentErrorRecorded = true;
        }
        await _recordAgentEvent(conversationId, runId, correlationId, event);
      }

      final result = agent is ApprovalAwareConversationAgent
          ? await (agent as ApprovalAwareConversationAgent).runWithApproval(
              prompt,
              cancellationToken: cancellationToken,
              onEvent: recordEvent,
              onApprovalRequest: (request) => _requestApproval(
                conversationId: conversationId,
                runId: runId,
                correlationId: correlationId,
                request: request,
                cancellationToken: cancellationToken,
              ),
            )
          : await agent.run(
              prompt,
              cancellationToken: cancellationToken,
              onEvent: recordEvent,
            );
      cancellationToken.throwIfCancellationRequested();
      if (!assistantRecorded) {
        final output = SafeMetadata.message(result.output);
        await _append(
          conversationId,
          runId,
          correlationId,
          kind: ChatEntryKind.assistantMessage,
          status: ChatEntryStatus.completed,
          content: output.text,
          source: ChatEntrySource.model,
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
    } on RunCancelledException {
      await _append(
        conversationId,
        runId,
        correlationId,
        kind: ChatEntryKind.lifecycle,
        status: ChatEntryStatus.cancelled,
        content: 'Response cancelled',
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
        final active = _activeRuns[conversationId];
        if (active?.runId == runId) _activeRuns.remove(conversationId);
      });
    }
  }

  Future<bool> _requestApproval({
    required String conversationId,
    required String runId,
    required String correlationId,
    required ToolApprovalRequest request,
    required CancellationToken cancellationToken,
  }) async {
    cancellationToken.throwIfCancellationRequested();
    final approvalId = _identifiers.next('approval');
    final normalizedRequest = ToolApprovalRequest(
      toolCallId: SafeMetadata.identifier(request.toolCallId),
      toolName: SafeMetadata.toolName(request.toolName),
      summary: request.summary,
    );
    final pending = _PendingApproval(
      conversationId: conversationId,
      runId: runId,
      correlationId: correlationId,
      request: normalizedRequest,
    );
    await _withSubmissionLock(() async {
      cancellationToken.throwIfCancellationRequested();
      _pendingApprovals[approvalId] = pending;
      await _append(
        conversationId,
        runId,
        correlationId,
        kind: ChatEntryKind.approval,
        status: ChatEntryStatus.pending,
        content: normalizedRequest.summary.text,
        source: ChatEntrySource.dextero,
        truncated: normalizedRequest.summary.truncated,
        toolCallId: normalizedRequest.toolCallId,
        toolName: normalizedRequest.toolName,
        approvalId: approvalId,
      );
    });
    try {
      return await Future.any<bool>([
        pending.decision.future,
        cancellationToken.whenCancelled.then<bool>(
          (_) => throw const RunCancelledException(),
        ),
      ]);
    } on RunCancelledException {
      await _withSubmissionLock(() async {
        if (_pendingApprovals.remove(approvalId) == pending) {
          await _append(
            conversationId,
            runId,
            correlationId,
            kind: ChatEntryKind.approval,
            status: ChatEntryStatus.cancelled,
            content: '${normalizedRequest.toolName} approval cancelled',
            source: ChatEntrySource.dextero,
            toolCallId: normalizedRequest.toolCallId,
            toolName: normalizedRequest.toolName,
            approvalId: approvalId,
          );
        }
      });
      rethrow;
    } finally {
      _pendingApprovals.remove(approvalId);
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
      ConversationAgentEventKind.assistantDelta => (
        ChatEntryKind.assistantDelta,
        ChatEntryStatus.running,
      ),
      ConversationAgentEventKind.toolCallStarted => (
        ChatEntryKind.toolCall,
        ChatEntryStatus.running,
      ),
      ConversationAgentEventKind.toolOutput => (
        ChatEntryKind.toolOutput,
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
      source: ChatEntrySource.model,
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
    String? approvalId,
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
      approvalId: approvalId,
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

final class _ActiveRun {
  const _ActiveRun({required this.runId, required this.cancellation});

  final String runId;
  final CancellationController cancellation;
}

final class _PendingApproval {
  _PendingApproval({
    required this.conversationId,
    required this.runId,
    required this.correlationId,
    required this.request,
  });

  final String conversationId;
  final String runId;
  final String correlationId;
  final ToolApprovalRequest request;
  final Completer<bool> decision = Completer<bool>();
}
