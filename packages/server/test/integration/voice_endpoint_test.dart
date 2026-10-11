import 'dart:async';
import 'dart:typed_data';

import 'package:dextero_core/dextero_core.dart' as core;
import 'package:dextero_server/src/control/chat_runtime.dart';
import 'package:dextero_server/src/generated/protocol.dart';
import 'package:test/test.dart';

import 'test_tools/serverpod_test_tools.dart';
import 'test_tools/test_server_config.dart';

void main() {
  late core.InMemoryChatHistoryStore store;
  late core.ChatService service;
  late _RecordingAgent agent;
  late _FakeTranscriber transcriber;
  late _FakeSynthesizer synthesizer;
  late String conversationId;

  setUp(() async {
    store = core.InMemoryChatHistoryStore();
    agent = _RecordingAgent();
    service = core.ChatService(store: store, agent: agent);
    conversationId = (await service.createConversation()).id;
    transcriber = _FakeTranscriber();
    synthesizer = _FakeSynthesizer();
    ChatRuntime.configure(
      chatService: service,
      defaultConversationId: conversationId,
      voiceService: core.VoiceService(
        store: store,
        transcriber: transcriber,
        synthesizer: synthesizer,
      ),
    );
  });

  tearDown(() => store.close());

  withServerpod('Voice control endpoint', (sessionBuilder, endpoints) {
    final session = sessionBuilder.copyWith(
      authentication: AuthenticationOverride.authenticationInfo(
        'test-controller',
        const {},
      ),
    );

    VoiceSubmitRequest request({
      ByteData? audio,
      String mimeType = 'audio/wav',
      String modelName = 'default',
    }) => VoiceSubmitRequest(
      conversationId: conversationId,
      audio: audio ?? ByteData.sublistView(_wav()),
      mimeType: mimeType,
      modelName: modelName,
      modelProvider: 'codex',
      correlationId: 'voice-1',
    );

    Future<void> waitForRun(String runId) => store
        .watch(conversationId)
        .firstWhere(
          (entry) =>
              entry.runId == runId &&
              entry.kind == core.ChatEntryKind.lifecycle &&
              entry.status == core.ChatEntryStatus.completed,
        );

    test('advertises voice capabilities and their privacy notice', () async {
      final status = await endpoints.control.status(session);

      expect(status.voiceInputAvailable, isTrue);
      expect(status.voiceOutputAvailable, isTrue);
      expect(status.voiceNotice, contains('fake whisper on this host'));
      expect(status.voiceNotice, contains('deleted after transcription'));
      expect(status.voiceNotice, contains('fake voice on this host'));
    });

    test(
      'reports voice as unavailable when no engines are configured',
      () async {
        ChatRuntime.configure(
          chatService: service,
          defaultConversationId: conversationId,
        );

        final status = await endpoints.control.status(session);

        expect(status.voiceInputAvailable, isFalse);
        expect(status.voiceOutputAvailable, isFalse);
        expect(status.voiceNotice, isNull);
        await expectLater(
          endpoints.control.submitVoiceMessage(session, request()),
          throwsA(
            isA<VoiceTurnException>().having(
              (error) => error.message,
              'message',
              contains('not configured'),
            ),
          ),
        );
      },
    );

    test(
      'transcribes a voice turn into the shared conversation and speaks it',
      () async {
        final audio = _wav();

        final submission = await endpoints.control.submitVoiceMessage(
          session,
          request(audio: ByteData.sublistView(audio)),
        );
        await waitForRun(submission.runId);
        final text = await endpoints.control.submitMessage(
          session,
          ChatSubmitRequest(
            conversationId: conversationId,
            message: 'And in text?',
            modelName: 'default',
            modelProvider: 'codex',
          ),
        );
        await waitForRun(text.runId);
        final history = await endpoints.control.history(
          session,
          conversationId,
        );
        final reply = history.firstWhere(
          (entry) =>
              entry.runId == submission.runId &&
              entry.kind == ChatEntryKind.assistantMessage,
        );
        final spoken = await endpoints.control.speakReply(
          session,
          conversationId,
          reply.entryId,
        );

        expect(transcriber.received.single, audio);
        expect(submission.correlationId, 'voice-1');
        expect(submission.userEntry.content, 'What changed today?');
        expect(submission.userEntry.modality, ChatModality.voice);
        expect(
          submission.userEntry.transcriptionEngine,
          'fake whisper on this host',
        );
        expect(agent.prompts, ['What changed today?', 'And in text?']);
        final users = history
            .where((entry) => entry.kind == ChatEntryKind.userMessage)
            .toList();
        expect(users.map((entry) => entry.modality), [
          ChatModality.voice,
          ChatModality.text,
        ]);
        expect(users.map((entry) => entry.conversationId).toSet(), {
          conversationId,
        });
        expect(spoken.entryId, reply.entryId);
        expect(spoken.mimeType, 'audio/wav');
        expect(spoken.engine, 'fake voice on this host');
        expect(spoken.truncated, isFalse);
        expect(
          spoken.audio.buffer.asUint8List(
            spoken.audio.offsetInBytes,
            spoken.audio.lengthInBytes,
          ),
          [1, 2, 3, 4],
        );
        expect(synthesizer.spoken, ['Reply to What changed today?']);
      },
    );

    test(
      'rejects invalid audio and stale models before history changes',
      () async {
        await expectLater(
          endpoints.control.submitVoiceMessage(
            session,
            request(audio: ByteData.sublistView(_wav(amplitude: 0))),
          ),
          throwsA(
            isA<VoiceTurnException>().having(
              (error) => error.message,
              'message',
              contains('No speech'),
            ),
          ),
        );
        await expectLater(
          endpoints.control.submitVoiceMessage(
            session,
            request(mimeType: 'audio/webm'),
          ),
          throwsA(isA<VoiceTurnException>()),
        );
        await expectLater(
          endpoints.control.submitVoiceMessage(
            session,
            request(modelName: 'stale'),
          ),
          throwsStateError,
        );
        transcriber.text = '[BLANK_AUDIO]';
        await expectLater(
          endpoints.control.submitVoiceMessage(session, request()),
          throwsA(isA<VoiceTurnException>()),
        );

        expect(transcriber.received, hasLength(1));
        expect(await store.history(conversationId), isEmpty);
      },
    );

    test('refuses a voice turn while a response is running', () async {
      agent.release = Completer<void>();
      final first = await endpoints.control.submitVoiceMessage(
        session,
        request(),
      );

      await expectLater(
        endpoints.control.submitVoiceMessage(session, request()),
        throwsStateError,
      );
      expect(transcriber.received, hasLength(1));
      agent.release!.complete();
      await waitForRun(first.runId);
    });

    test('speaks only assistant replies', () async {
      final submission = await endpoints.control.submitVoiceMessage(
        session,
        request(),
      );
      await waitForRun(submission.runId);

      await expectLater(
        endpoints.control.speakReply(
          session,
          conversationId,
          submission.userEntry.entryId,
        ),
        throwsA(isA<VoiceTurnException>()),
      );
    });

    test('rejects unauthenticated voice calls', () async {
      await expectLater(
        endpoints.control.submitVoiceMessage(sessionBuilder, request()),
        throwsA(isA<ServerpodUnauthenticatedException>()),
      );
      await expectLater(
        endpoints.control.speakReply(sessionBuilder, conversationId, 'entry'),
        throwsA(isA<ServerpodUnauthenticatedException>()),
      );
    });
  }, configOverride: useEphemeralApiPort);
}

/// Half a second of a 16 kHz mono PCM WAV square wave.
Uint8List _wav({double amplitude = 0.4}) {
  const samples = 8000;
  final data = ByteData(44 + samples * 2);
  void ascii(int offset, String value) {
    for (var index = 0; index < value.length; index++) {
      data.setUint8(offset + index, value.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples * 2, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 16000, Endian.little)
    ..setUint32(28, 32000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  final level = (amplitude * 32767).round();
  for (var index = 0; index < samples; index++) {
    data.setInt16(
      44 + index * 2,
      index % 40 < 20 ? level : -level,
      Endian.little,
    );
  }
  return data.buffer.asUint8List();
}

final class _RecordingAgent implements core.ConversationAgent {
  final prompts = <String>[];
  Completer<void>? release;

  @override
  Future<core.ConversationAgentResult> run(
    String prompt, {
    required core.ConversationAgentEventSink onEvent,
    required core.CancellationToken cancellationToken,
  }) async {
    prompts.add(prompt);
    await release?.future;
    return core.ConversationAgentResult(output: 'Reply to $prompt');
  }
}

final class _FakeTranscriber implements core.SpeechTranscriber {
  String text = ' What changed today? ';
  final received = <Uint8List>[];

  @override
  String get engine => 'fake whisper on this host';

  @override
  Set<String> get supportedMimeTypes => const {'audio/wav'};

  @override
  Future<core.SpeechTranscript> transcribe(
    core.SpeechAudio audio, {
    core.CancellationToken? cancellationToken,
  }) async {
    received.add(audio.bytes);
    return core.SpeechTranscript(text: text, engine: engine);
  }
}

final class _FakeSynthesizer implements core.SpeechSynthesizer {
  final spoken = <String>[];

  @override
  String get engine => 'fake voice on this host';

  @override
  Future<core.SynthesizedSpeech> synthesize(
    String text, {
    core.CancellationToken? cancellationToken,
  }) async {
    spoken.add(text);
    return core.SynthesizedSpeech(
      bytes: Uint8List.fromList([1, 2, 3, 4]),
      mimeType: 'audio/wav',
      engine: engine,
    );
  }
}
