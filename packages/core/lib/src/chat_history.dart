import 'dart:async';
import 'dart:convert';
import 'dart:math';

enum ChatEntryKind {
  userMessage,
  assistantMessage,
  assistantDelta,
  toolCall,
  toolOutput,
  toolResult,
  lifecycle,
  error,
}

enum ChatEventFamily {
  message,
  task,
  model,
  tool,
  approval,
  artifact,
  usage,
  warning,
  error,
}

enum ChatEntryStatus {
  submitted,
  queued,
  running,
  warning,
  completed,
  failed,
  cancelled,
}

enum ChatEntrySource { user, dextero, model }

final class ChatConversation {
  const ChatConversation({required this.id, required this.createdAt});

  final String id;
  final DateTime createdAt;
}

/// One immutable, display-safe record in a conversation.
final class ChatHistoryEntry {
  const ChatHistoryEntry({
    this.eventVersion = 1,
    ChatEventFamily? family,
    required this.conversationId,
    required this.entryId,
    required this.sequence,
    required this.kind,
    required this.status,
    required this.content,
    required this.createdAt,
    required this.correlationId,
    required this.source,
    required this.truncated,
    this.runId,
    this.toolCallId,
    this.toolName,
  }) : _family = family;

  final int eventVersion;
  final ChatEventFamily? _family;
  ChatEventFamily get family => _family ?? eventFamilyFor(kind, status);

  final String conversationId;
  final String entryId;
  final int sequence;
  final ChatEntryKind kind;
  final ChatEntryStatus status;
  final String content;
  final DateTime createdAt;
  final String correlationId;
  final ChatEntrySource source;
  final bool truncated;
  final String? runId;
  final String? toolCallId;
  final String? toolName;
}

final class PendingChatEntry {
  const PendingChatEntry({
    required this.kind,
    required this.status,
    required this.content,
    required this.correlationId,
    required this.source,
    this.truncated = false,
    this.runId,
    this.toolCallId,
    this.toolName,
    this.family,
  });

  final ChatEntryKind kind;
  final ChatEntryStatus status;
  final String content;
  final String correlationId;
  final ChatEntrySource source;
  final bool truncated;
  final String? runId;
  final String? toolCallId;
  final String? toolName;
  final ChatEventFamily? family;
}

ChatEventFamily eventFamilyFor(ChatEntryKind kind, ChatEntryStatus status) {
  if (status == ChatEntryStatus.warning) return ChatEventFamily.warning;
  if (status == ChatEntryStatus.failed) return ChatEventFamily.error;
  return switch (kind) {
    ChatEntryKind.userMessage => ChatEventFamily.message,
    ChatEntryKind.assistantMessage ||
    ChatEntryKind.assistantDelta => ChatEventFamily.model,
    ChatEntryKind.toolCall ||
    ChatEntryKind.toolOutput ||
    ChatEntryKind.toolResult => ChatEventFamily.tool,
    ChatEntryKind.lifecycle => ChatEventFamily.task,
    ChatEntryKind.error => ChatEventFamily.error,
  };
}

abstract interface class IdentifierGenerator {
  String next(String prefix);
}

final class SecureIdentifierGenerator implements IdentifierGenerator {
  SecureIdentifierGenerator() : _random = Random.secure();

  final Random _random;
  int _counter = 0;

  @override
  String next(String prefix) {
    final bytes = List<int>.generate(12, (_) => _random.nextInt(256));
    final random = base64Url.encode(bytes).replaceAll('=', '');
    return '${prefix}_${DateTime.now().toUtc().microsecondsSinceEpoch}_'
        '${_counter++}_$random';
  }
}

/// Persistence seam for canonical append-only conversation history.
abstract interface class ChatHistoryStore {
  Future<ChatConversation> createConversation();

  Future<ChatConversation?> conversation(String conversationId);

  Future<ChatHistoryEntry> append(
    String conversationId,
    PendingChatEntry entry,
  );

  Future<List<ChatHistoryEntry>> history(String conversationId);

  Stream<ChatHistoryEntry> watch(
    String conversationId, {
    int afterSequence = -1,
  });

  Future<void> close();
}

/// Process-local history. All content is lost when the host restarts.
final class InMemoryChatHistoryStore implements ChatHistoryStore {
  InMemoryChatHistoryStore({
    IdentifierGenerator? identifiers,
    DateTime Function()? clock,
  }) : _identifiers = identifiers ?? SecureIdentifierGenerator(),
       _clock = clock ?? (() => DateTime.now().toUtc());

  final IdentifierGenerator _identifiers;
  final DateTime Function() _clock;
  final Map<String, _ConversationState> _conversations = {};
  var _closed = false;

  @override
  Future<ChatConversation> createConversation() async {
    _ensureOpen();
    final conversation = ChatConversation(
      id: _identifiers.next('conversation'),
      createdAt: _clock().toUtc(),
    );
    _conversations[conversation.id] = _ConversationState(conversation);
    return conversation;
  }

  @override
  Future<ChatConversation?> conversation(String conversationId) async {
    _ensureOpen();
    return _conversations[conversationId]?.conversation;
  }

  @override
  Future<ChatHistoryEntry> append(
    String conversationId,
    PendingChatEntry entry,
  ) async {
    _ensureOpen();
    final state = _state(conversationId);
    final canonical = ChatHistoryEntry(
      eventVersion: 1,
      family: entry.family,
      conversationId: conversationId,
      entryId: _identifiers.next('entry'),
      sequence: state.entries.length,
      kind: entry.kind,
      status: entry.status,
      content: entry.content,
      createdAt: _clock().toUtc(),
      correlationId: entry.correlationId,
      source: entry.source,
      truncated: entry.truncated,
      runId: entry.runId,
      toolCallId: entry.toolCallId,
      toolName: entry.toolName,
    );
    state.entries.add(canonical);
    state.changes.add(canonical);
    return canonical;
  }

  @override
  Future<List<ChatHistoryEntry>> history(String conversationId) async {
    _ensureOpen();
    return List.unmodifiable(_state(conversationId).entries);
  }

  @override
  Stream<ChatHistoryEntry> watch(
    String conversationId, {
    int afterSequence = -1,
  }) {
    _ensureOpen();
    if (afterSequence < -1) {
      throw ArgumentError.value(
        afterSequence,
        'afterSequence',
        'must be at least -1',
      );
    }
    final state = _state(conversationId);
    return Stream<ChatHistoryEntry>.multi((controller) {
      var lastSequence = afterSequence;
      final subscription = state.changes.stream.listen(
        (entry) {
          if (entry.sequence <= lastSequence) return;
          lastSequence = entry.sequence;
          controller.add(entry);
        },
        onError: controller.addError,
        onDone: controller.close,
      );
      final snapshot = List<ChatHistoryEntry>.of(state.entries);
      for (final entry in snapshot) {
        if (entry.sequence <= lastSequence) continue;
        lastSequence = entry.sequence;
        controller.add(entry);
      }
      controller.onCancel = subscription.cancel;
    });
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final state in _conversations.values) {
      await state.changes.close();
    }
  }

  _ConversationState _state(String conversationId) {
    if (conversationId.trim().isEmpty) {
      throw ArgumentError.value(
        conversationId,
        'conversationId',
        'must not be empty',
      );
    }
    final state = _conversations[conversationId];
    if (state == null) {
      throw StateError('Unknown conversation: $conversationId');
    }
    return state;
  }

  void _ensureOpen() {
    if (_closed) throw StateError('The chat history store is closed.');
  }
}

final class _ConversationState {
  _ConversationState(this.conversation);

  final ChatConversation conversation;
  final List<ChatHistoryEntry> entries = [];
  final StreamController<ChatHistoryEntry> changes =
      StreamController<ChatHistoryEntry>.broadcast(sync: true);
}
