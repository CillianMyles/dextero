import 'dart:async';
import 'dart:typed_data';

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
    modelOptions: [
      for (final option in ChatRuntime.modelOptions)
        ModelOption(
          id: option.id,
          provider: option.provider.name,
          modelName: option.modelName,
          label: option.label,
          toolDescription: option.toolDescription,
        ),
    ],
    voiceInputAvailable: ChatRuntime.voice.inputAvailable,
    voiceOutputAvailable: ChatRuntime.voice.outputAvailable,
    voiceNotice: ChatRuntime.voice.privacyNotice,
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
      modelProvider: request.modelProvider,
      correlationId: request.correlationId,
    );
    return ChatSubmission(
      conversationId: submission.conversationId,
      runId: submission.runId,
      correlationId: submission.correlationId,
      userEntry: _toProtocolEntry(submission.userEntry),
    );
  }

  /// Transcribes push-to-talk audio on the host and accepts the transcript
  /// into the same conversation as typed messages. Audio is not retained.
  Future<ChatSubmission> submitVoiceMessage(
    Session session,
    VoiceSubmitRequest request,
  ) async {
    final submission = await _voiceOperation(
      () => ChatRuntime.submitVoice(
        conversationId: request.conversationId,
        audio: request.audio.buffer.asUint8List(
          request.audio.offsetInBytes,
          request.audio.lengthInBytes,
        ),
        mimeType: request.mimeType,
        modelName: request.modelName,
        modelProvider: request.modelProvider,
        correlationId: request.correlationId,
      ),
    );
    return ChatSubmission(
      conversationId: submission.conversationId,
      runId: submission.runId,
      correlationId: submission.correlationId,
      userEntry: _toProtocolEntry(submission.userEntry),
    );
  }

  /// Synthesizes speech for one assistant reply; the audio is not stored.
  Future<SpokenReply> speakReply(
    Session session,
    String conversationId,
    String entryId,
  ) async {
    final speech = await _voiceOperation(
      () => ChatRuntime.voice.speak(
        conversationId: conversationId,
        entryId: entryId,
      ),
    );
    return SpokenReply(
      entryId: entryId,
      audio: ByteData.sublistView(speech.bytes),
      mimeType: speech.mimeType,
      engine: speech.engine,
      truncated: speech.truncated,
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
    modality: ChatModality.values.byName(entry.modality.name),
    transcriptionEngine: entry.transcriptionEngine,
  );

  Future<T> _voiceOperation<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on core.SpeechException catch (error) {
      throw VoiceTurnException(message: error.message);
    }
  }
}
