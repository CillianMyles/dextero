import 'dart:async';

import 'package:dextero_core/dextero_core.dart' as core;
import 'package:serverpod/serverpod.dart';

import '../generated/protocol.dart';
import 'chat_runtime.dart';

/// The first typed control-plane slice exposed to trusted controllers.
final class ControlEndpoint extends Endpoint {
  static final DateTime _startedAt = DateTime.now().toUtc();

  @override
  bool get requireLogin => true;

  /// Describes the local host and its intentionally volatile MVP storage.
  Future<HostStatus> status(Session session) async => _status();

  /// Selects the model before this process-local conversation has started.
  Future<HostStatus> selectModel(Session session, String modelName) async {
    await ChatRuntime.selectModel(modelName);
    return _status();
  }

  HostStatus _status() => HostStatus(
    name: 'Dextero',
    version: '0.0.1',
    startedAt: _startedAt,
    persistence: 'memory',
    conversationId: ChatRuntime.conversationId,
    retentionNotice: 'History is retained only until the server restarts.',
    databaseRequired: false,
    streamingAvailable: true,
    modelProvider: ChatRuntime.modelProvider,
    modelName: ChatRuntime.modelName,
    availableModels: ChatRuntime.availableModels,
  );

  /// Canonically accepts a user message before starting assistant work.
  Future<ChatSubmission> submitMessage(
    Session session,
    ChatSubmitRequest request,
  ) async {
    final submission = await ChatRuntime.submit(
      conversationId: request.conversationId,
      message: request.message,
      modelName: request.modelName,
      correlationId: request.correlationId,
    );
    return ChatSubmission(
      conversationId: submission.conversationId,
      runId: submission.runId,
      correlationId: submission.correlationId,
      userEntry: _toProtocolEntry(submission.userEntry),
    );
  }

  /// Requests cancellation of the matching active run.
  Future<bool> cancelRun(
    Session session,
    String conversationId,
    String runId,
  ) => ChatRuntime.service.cancel(conversationId: conversationId, runId: runId);

  /// Approves one pending tool action for the matching active run.
  Future<bool> approveWork(
    Session session,
    String conversationId,
    String runId,
    String approvalId,
  ) => ChatRuntime.service.approve(
    conversationId: conversationId,
    runId: runId,
    approvalId: approvalId,
  );

  /// Returns the complete process-local history for one conversation.
  Future<List<ChatEntry>> history(
    Session session,
    String conversationId,
  ) async => (await ChatRuntime.service.store.history(
    conversationId,
  )).map(_toProtocolEntry).toList(growable: false);

  /// Replays entries after the cursor, then streams future appends.
  Stream<ChatEntry> streamHistory(
    Session session,
    String conversationId,
    int afterSequence,
  ) => ChatRuntime.service.store
      .watch(conversationId, afterSequence: afterSequence)
      .map(_toProtocolEntry);

  ChatEntry _toProtocolEntry(core.ChatHistoryEntry entry) => ChatEntry(
    eventVersion: entry.eventVersion,
    family: ChatEventFamily.values.byName(entry.family.name),
    conversationId: entry.conversationId,
    entryId: entry.entryId,
    sequence: entry.sequence,
    kind: ChatEntryKind.values.byName(entry.kind.name),
    status: ChatEntryStatus.values.byName(entry.status.name),
    content: entry.content,
    createdAt: entry.createdAt,
    correlationId: entry.correlationId,
    source: ChatEntrySource.values.byName(entry.source.name),
    truncated: entry.truncated,
    runId: entry.runId,
    toolCallId: entry.toolCallId,
    toolName: entry.toolName,
    approvalId: entry.approvalId,
  );
}
