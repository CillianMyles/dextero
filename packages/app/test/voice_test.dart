import 'dart:async';
import 'dart:typed_data';

import 'package:dextero_app/main.dart';
import 'package:dextero_app/src/dextero_controller.dart';
import 'package:dextero_app/src/voice_audio.dart';
import 'package:dextero_app/src/voice_controller.dart';
import 'package:dextero_server/dextero_client.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _engine = 'whisper.cpp (ggml-base.bin) on this host';

void main() {
  group('voice audio', () {
    test('wraps PCM in a 16 kHz mono WAV header', () {
      final wav = encodeWav(Uint8List.fromList([1, 0, 2, 0]));
      final header = ByteData.sublistView(wav);

      expect(String.fromCharCodes(wav, 0, 4), 'RIFF');
      expect(String.fromCharCodes(wav, 8, 12), 'WAVE');
      expect(header.getUint16(22, Endian.little), 1);
      expect(header.getUint32(24, Endian.little), 16000);
      expect(header.getUint16(34, Endian.little), 16);
      expect(header.getUint32(40, Endian.little), 4);
      expect(wav.sublist(44), [1, 0, 2, 0]);
    });

    test('downmixes and resamples captured audio to 16 kHz mono', () {
      final stereo48k = ByteData(48000 * 2 * 2);
      for (var frame = 0; frame < 48000; frame++) {
        stereo48k
          ..setInt16(frame * 4, 1000, Endian.little)
          ..setInt16(frame * 4 + 2, 3000, Endian.little);
      }

      final pcm = toVoicePcm(
        stereo48k.buffer.asUint8List(),
        sampleRate: 48000,
        channels: 2,
      );

      expect(pcm.length, 16000 * 2);
      expect(ByteData.sublistView(pcm).getInt16(200, Endian.little), 2000);
    });

    test('measures input level', () {
      final loud = ByteData(400);
      for (var index = 0; index < 200; index++) {
        loud.setInt16(index * 2, index.isEven ? 16000 : -16000, Endian.little);
      }

      expect(pcm16Level(Uint8List(400)), 0);
      expect(pcm16Level(loud.buffer.asUint8List()), greaterThan(0.9));
    });
  });

  testWidgets('hides push-to-talk when the host has no speech engine', (
    tester,
  ) async {
    final harness = _Harness(status: _status(voiceInput: false));

    await harness.pump(tester);

    expect(find.byKey(const Key('push-to-talk')), findsNothing);
    expect(_presenceLabel(tester), 'Ready');
    expect(find.byKey(const Key('agent-presence-detail')), findsNothing);
  });

  testWidgets(
    'completes a push-to-talk turn in the shared conversation and speaks it',
    (tester) async {
      final harness = _Harness();
      final accepted = Completer<ChatSubmission>();
      harness.api.voiceSubmitter = (_) => accepted.future;
      await harness.pump(tester);
      expect(find.text('Tap the microphone to talk.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('push-to-talk')));
      await tester.pump();

      expect(harness.recorder.started, isTrue);
      expect(_presenceLabel(tester), 'Listening');
      expect(find.byKey(const Key('recording-indicator')), findsOneWidget);
      expect(find.text('Recording 0:00'), findsOneWidget);
      expect(find.byKey(const Key('chat-message')), findsNothing);

      harness.recorder.onLevel!(0.8);
      await tester.pump(const Duration(seconds: 1));
      expect(harness.voice.level, 0.8);
      expect(find.text('Recording 0:01'), findsOneWidget);
      expect(find.text('Microphone on · 0:01'), findsOneWidget);

      await tester.tap(find.byKey(const Key('finish-voice')));
      await tester.pump();

      expect(_presenceLabel(tester), 'Transcribing');
      expect(find.text('Transcribing your message…'), findsOneWidget);
      final request = harness.api.voiceSubmissions.single;
      expect(_bytes(request.audio), harness.recorder.clip.bytes);
      expect(request.mimeType, 'audio/wav');
      expect(request.conversationId, 'conversation-1');
      expect(request.modelProvider, 'gemini');
      expect(request.modelName, 'gemini-2.5-flash');

      accepted.complete(
        ChatSubmission(
          conversationId: 'conversation-1',
          runId: 'run-1',
          correlationId: 'app-voice-1',
          userEntry: _entry(
            0,
            ChatEntryKind.userMessage,
            ChatEntryStatus.submitted,
            'What changed today?',
            modality: ChatModality.voice,
            transcriptionEngine: _engine,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('You · Voice'), findsOneWidget);
      expect(find.text('What changed today?'), findsOneWidget);
      expect(find.text('Transcribed by $_engine'), findsOneWidget);
      expect(_presenceLabel(tester), 'Thinking');
      expect(find.byKey(const Key('chat-message')), findsOneWidget);

      harness.api.emit(
        _entry(
          1,
          ChatEntryKind.toolCall,
          ChatEntryStatus.running,
          'read_file started',
          toolCallId: 'call-1',
          toolName: 'read_file',
        ),
      );
      await tester.pump();
      expect(_presenceLabel(tester), 'Working');
      expect(find.text('Using read file'), findsOneWidget);

      harness.api.emit(
        _entry(
          2,
          ChatEntryKind.approval,
          ChatEntryStatus.pending,
          'edit_file requires approval for README.md',
          toolCallId: 'call-2',
          toolName: 'edit_file',
          approvalId: 'approval-1',
        ),
      );
      await tester.pump();
      expect(_presenceLabel(tester), 'Waiting for your approval');
      expect(find.byKey(const Key('approval-prompt')), findsOneWidget);

      for (final entry in [
        _entry(
          3,
          ChatEntryKind.approval,
          ChatEntryStatus.approved,
          'edit_file approved',
          toolCallId: 'call-2',
          toolName: 'edit_file',
          approvalId: 'approval-1',
        ),
        _entry(
          4,
          ChatEntryKind.toolResult,
          ChatEntryStatus.completed,
          'read_file completed',
          toolCallId: 'call-1',
          toolName: 'read_file',
        ),
      ]) {
        harness.api.emit(entry);
      }
      await tester.pump();
      expect(_presenceLabel(tester), 'Thinking');

      harness.api
        ..emit(
          _entry(
            5,
            ChatEntryKind.assistantMessage,
            ChatEntryStatus.completed,
            'Two files changed.',
          ),
        )
        ..emit(
          _entry(
            6,
            ChatEntryKind.lifecycle,
            ChatEntryStatus.completed,
            'Response completed',
          ),
        );
      await tester.pump();
      await tester.pump();

      expect(harness.api.spokenEntryIds, ['entry-5']);
      expect(_presenceLabel(tester), 'Speaking');
      expect(harness.player.played.single, [7, 7, 7]);
      expect(harness.player.mimeTypes.single, 'audio/wav');
      expect(find.byKey(const Key('stop-speaking')), findsOneWidget);

      harness.player.finish();
      await tester.pump();
      expect(_presenceLabel(tester), 'Ready');
      expect(harness.controller.busy, isFalse);
    },
  );

  testWidgets('lets the user stop or talk over a spoken reply', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);
    await harness.completeVoiceTurn(tester);
    expect(_presenceLabel(tester), 'Speaking');

    await tester.tap(find.byKey(const Key('stop-speaking')));
    await tester.pump();
    expect(harness.player.stopped, 1);
    expect(_presenceLabel(tester), 'Ready');

    await harness.completeVoiceTurn(tester, runId: 'run-2', sequence: 10);
    expect(_presenceLabel(tester), 'Speaking');
    await tester.tap(find.byKey(const Key('push-to-talk')));
    await tester.pump();

    expect(harness.player.stopped, 2);
    expect(_presenceLabel(tester), 'Listening');
    await tester.tap(find.byKey(const Key('cancel-voice')));
    await tester.pump();
  });

  testWidgets('discards a cancelled recording without sending it', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('push-to-talk')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cancel-voice')));
    await tester.pump();

    expect(harness.recorder.cancelled, isTrue);
    expect(harness.api.voiceSubmissions, isEmpty);
    expect(_presenceLabel(tester), 'Ready');
    expect(find.byKey(const Key('chat-message')), findsOneWidget);
  });

  testWidgets('sends automatically at the recording limit', (tester) async {
    final harness = _Harness(maxRecording: const Duration(seconds: 1));
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('push-to-talk')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1200));

    expect(harness.api.voiceSubmissions, hasLength(1));
  });

  testWidgets('explains denied microphone access and failed transcription', (
    tester,
  ) async {
    final harness = _Harness();
    harness.recorder.permission = false;
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('push-to-talk')));
    await tester.pump();
    expect(find.text('Voice problem'), findsOneWidget);
    expect(find.textContaining('Microphone access was denied'), findsOneWidget);
    expect(_presenceLabel(tester), 'Ready');

    harness.recorder.permission = true;
    harness.api.voiceSubmitter = (_) async => throw VoiceTurnException(
      message: 'No speech was detected in the recording.',
    );
    await tester.tap(find.byKey(const Key('push-to-talk')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finish-voice')));
    await tester.pump();
    await tester.pump();

    expect(find.text('No speech was detected in the recording.'), findsOne);
    expect(_presenceLabel(tester), 'Ready');
    expect(harness.controller.entries, isEmpty);
  });

  testWidgets('does not speak replies to typed messages', (tester) async {
    final harness = _Harness();
    await harness.pump(tester);

    await tester.enterText(find.byKey(const Key('chat-message')), 'Hello');
    await tester.pump();
    await tester.tap(find.byKey(const Key('send-message')));
    await tester.pump();
    harness.api
      ..emit(
        _entry(
          1,
          ChatEntryKind.assistantMessage,
          ChatEntryStatus.completed,
          'Hi',
        ),
      )
      ..emit(
        _entry(
          2,
          ChatEntryKind.lifecycle,
          ChatEntryStatus.completed,
          'Response completed',
        ),
      );
    await tester.pump();

    expect(harness.api.spokenEntryIds, isEmpty);
    expect(_presenceLabel(tester), 'Ready');
  });

  testWidgets('keeps the recording controls usable at phone width', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final harness = _Harness();
    await harness.pump(tester);

    await tester.tap(find.byKey(const Key('push-to-talk')));
    await tester.pump(const Duration(seconds: 51));

    expect(find.text('Recording 0:51 · 9s left'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const Key('finish-voice'))).dx,
      lessThan(390),
    );
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const Key('cancel-voice')));
    await tester.pump();
  });
}

String _presenceLabel(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(const Key('agent-presence-label'))).data!;

Uint8List _bytes(ByteData data) =>
    data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

final class _Harness {
  _Harness({
    HostStatus? status,
    Duration maxRecording = const Duration(seconds: 60),
  }) : api = _VoiceApi(status ?? _status()) {
    controller = DexteroController(
      api: api,
      correlationIdFactory: () => 'app-voice-1',
    );
    voice = VoiceController(
      chat: controller,
      recorder: recorder,
      player: player,
      maxRecording: maxRecording,
    );
  }

  final _VoiceApi api;
  final recorder = _FakeRecorder();
  final player = _FakePlayer();
  late final DexteroController controller;
  late final VoiceController voice;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(DexteroApp(controller: controller, voice: voice));
    await tester.pumpAndSettle();
  }

  /// Records, sends, and completes one voice turn up to its spoken reply.
  Future<void> completeVoiceTurn(
    WidgetTester tester, {
    String runId = 'run-1',
    int sequence = 0,
  }) async {
    api.voiceSubmitter = (_) async => ChatSubmission(
      conversationId: 'conversation-1',
      runId: runId,
      correlationId: 'app-voice-1',
      userEntry: _entry(
        sequence,
        ChatEntryKind.userMessage,
        ChatEntryStatus.submitted,
        'Question $sequence',
        runId: runId,
        modality: ChatModality.voice,
        transcriptionEngine: _engine,
      ),
    );
    await tester.tap(find.byKey(const Key('push-to-talk')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('finish-voice')));
    await tester.pump();
    api
      ..emit(
        _entry(
          sequence + 1,
          ChatEntryKind.assistantMessage,
          ChatEntryStatus.completed,
          'Answer $sequence',
          runId: runId,
        ),
      )
      ..emit(
        _entry(
          sequence + 2,
          ChatEntryKind.lifecycle,
          ChatEntryStatus.completed,
          'Response completed',
          runId: runId,
        ),
      );
    await tester.pump();
    await tester.pump();
  }
}

final class _FakeRecorder implements VoiceRecorder {
  bool permission = true;
  bool started = false;
  bool cancelled = false;
  void Function(double level)? onLevel;
  final clip = RecordedClip(
    bytes: encodeWav(Uint8List.fromList([1, 2, 3, 4])),
    mimeType: 'audio/wav',
    duration: const Duration(seconds: 1),
  );

  @override
  Future<bool> start({required void Function(double level) onLevel}) async {
    this.onLevel = onLevel;
    started = permission;
    return permission;
  }

  @override
  Future<RecordedClip?> stop() async => clip;

  @override
  Future<void> cancel() async => cancelled = true;

  @override
  Future<void> dispose() async {}
}

final class _FakePlayer implements SpeechPlayer {
  final played = <Uint8List>[];
  final mimeTypes = <String>[];
  var stopped = 0;
  Completer<void>? _playback;

  void finish() => _playback?.complete();

  @override
  Future<void> play(Uint8List bytes, {required String mimeType}) {
    played.add(bytes);
    mimeTypes.add(mimeType);
    return (_playback = Completer<void>()).future;
  }

  @override
  Future<void> stop() async {
    stopped++;
    final playback = _playback;
    if (playback != null && !playback.isCompleted) playback.complete();
  }

  @override
  Future<void> dispose() async {}
}

final class _VoiceApi implements ChatApi {
  _VoiceApi(this._status);

  final HostStatus _status;
  final _stream = StreamController<ChatEntry>.broadcast();
  final voiceSubmissions = <VoiceSubmitRequest>[];
  final spokenEntryIds = <String>[];
  Future<ChatSubmission> Function(VoiceSubmitRequest request)? voiceSubmitter;

  void emit(ChatEntry entry) => _stream.add(entry);

  @override
  Future<HostStatus> status() async => _status;

  @override
  Future<HostStatus> selectModel(String modelName) async => _status;

  @override
  Future<List<ChatEntry>> history(String conversationId) async => const [];

  @override
  Stream<ChatEntry> streamHistory(String conversationId, int afterSequence) =>
      _stream.stream;

  @override
  Future<ChatSubmission> submit(ChatSubmitRequest request) async =>
      ChatSubmission(
        conversationId: 'conversation-1',
        runId: 'run-1',
        correlationId: 'app-voice-1',
        userEntry: _entry(
          0,
          ChatEntryKind.userMessage,
          ChatEntryStatus.submitted,
          request.message,
        ),
      );

  @override
  Future<ChatSubmission> submitVoice(VoiceSubmitRequest request) {
    voiceSubmissions.add(request);
    return voiceSubmitter?.call(request) ??
        Future.value(
          ChatSubmission(
            conversationId: 'conversation-1',
            runId: 'run-1',
            correlationId: 'app-voice-1',
            userEntry: _entry(
              0,
              ChatEntryKind.userMessage,
              ChatEntryStatus.submitted,
              'Spoken',
              modality: ChatModality.voice,
              transcriptionEngine: _engine,
            ),
          ),
        );
  }

  @override
  Future<SpokenReply> speakReply(String conversationId, String entryId) async {
    spokenEntryIds.add(entryId);
    return SpokenReply(
      entryId: entryId,
      audio: ByteData.sublistView(Uint8List.fromList([7, 7, 7])),
      mimeType: 'audio/wav',
      engine: 'macOS say on this host',
      truncated: false,
    );
  }

  @override
  Future<bool> cancelRun(String conversationId, String runId) async => true;

  @override
  Future<bool> approveWork(
    String conversationId,
    String runId,
    String approvalId,
  ) async => true;

  @override
  Future<void> close() async {}
}

HostStatus _status({bool voiceInput = true}) => HostStatus(
  name: 'Dextero',
  version: '0.0.1',
  startedAt: DateTime.utc(2026),
  persistence: 'memory',
  conversationId: 'conversation-1',
  retentionNotice: 'History is retained only until the server restarts.',
  databaseRequired: false,
  streamingAvailable: true,
  modelProvider: 'gemini',
  modelName: 'gemini-2.5-flash',
  availableModels: const ['gemini-2.5-flash'],
  modelOptions: [
    ModelOption(
      id: 'gemini:gemini-2.5-flash',
      provider: 'gemini',
      modelName: 'gemini-2.5-flash',
      label: 'Gemini · gemini-2.5-flash',
      toolDescription: 'Dextero harness tools',
    ),
  ],
  voiceInputAvailable: voiceInput,
  voiceOutputAvailable: voiceInput,
  voiceNotice: voiceInput
      ? 'Push-to-talk audio is transcribed by $_engine and deleted after '
            'transcription.'
      : null,
);

ChatEntry _entry(
  int sequence,
  ChatEntryKind kind,
  ChatEntryStatus status,
  String content, {
  String runId = 'run-1',
  String? toolCallId,
  String? toolName,
  String? approvalId,
  ChatModality modality = ChatModality.text,
  String? transcriptionEngine,
}) => ChatEntry(
  conversationId: 'conversation-1',
  entryId: 'entry-$sequence',
  sequence: sequence,
  kind: kind,
  status: status,
  content: content,
  createdAt: DateTime.utc(2026),
  correlationId: 'app-voice-1',
  source: kind == ChatEntryKind.userMessage
      ? ChatEntrySource.user
      : ChatEntrySource.model,
  truncated: false,
  runId: runId,
  toolCallId: toolCallId,
  toolName: toolName,
  approvalId: approvalId,
  modality: modality,
  transcriptionEngine: transcriptionEngine,
);
