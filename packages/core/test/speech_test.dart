import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dextero_core/dextero_core.dart';
import 'package:test/test.dart';

void main() {
  group('VoiceService.transcribe', () {
    late InMemoryChatHistoryStore store;
    late _FakeTranscriber transcriber;
    late VoiceService voice;

    setUp(() {
      store = InMemoryChatHistoryStore();
      transcriber = _FakeTranscriber(' [BLANK_AUDIO] What changed? (music) ');
      voice = VoiceService(
        store: store,
        transcriber: transcriber,
        maxAudioBytes: 64 * 1024,
      );
    });

    tearDown(() => store.close());

    test('returns a normalized transcript with engine provenance', () async {
      final audio = _tone();

      final transcript = await voice.transcribe(
        SpeechAudio(bytes: audio, mimeType: 'audio/x-wav; codecs=1'),
      );

      expect(transcript.text, 'What changed?');
      expect(transcript.engine, 'fake engine on this host');
      expect(transcriber.received.single.bytes, audio);
      expect(transcriber.received.single.mimeType, 'audio/wav');
    });

    test('rejects invalid recordings before transcription', () async {
      Future<void> rejects(SpeechAudio audio, String message) => expectLater(
        voice.transcribe(audio),
        throwsA(
          isA<SpeechException>().having(
            (error) => error.message,
            'message',
            contains(message),
          ),
        ),
      );

      await rejects(
        SpeechAudio(bytes: Uint8List(0), mimeType: 'audio/wav'),
        'empty',
      );
      await rejects(
        SpeechAudio(bytes: _tone(seconds: 3), mimeType: 'audio/wav'),
        'too long',
      );
      await rejects(
        SpeechAudio(bytes: _tone(), mimeType: 'audio/webm'),
        'Unsupported audio type audio/webm',
      );
      await rejects(
        SpeechAudio(
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'audio/wav',
        ),
        'not valid audio/wav',
      );
      await rejects(
        SpeechAudio(bytes: _tone(amplitude: 0), mimeType: 'audio/wav'),
        'No speech was detected',
      );
      expect(transcriber.received, isEmpty);
    });

    test('rejects transcripts that contain only annotations', () async {
      transcriber.text = '[BLANK_AUDIO]\n (silence) ';

      await expectLater(
        voice.transcribe(SpeechAudio(bytes: _tone(), mimeType: 'audio/wav')),
        throwsA(
          isA<SpeechException>().having(
            (error) => error.message,
            'message',
            'No speech was recognized.',
          ),
        ),
      );
    });

    test('reports when voice input is not configured', () async {
      final unconfigured = VoiceService(store: store);

      expect(unconfigured.inputAvailable, isFalse);
      expect(unconfigured.outputAvailable, isFalse);
      expect(unconfigured.privacyNotice, isNull);
      await expectLater(
        unconfigured.transcribe(
          SpeechAudio(bytes: _tone(), mimeType: 'audio/wav'),
        ),
        throwsA(isA<SpeechException>()),
      );
    });
  });

  group('VoiceService.speak', () {
    test('speaks only assistant replies as bounded prose', () async {
      final store = InMemoryChatHistoryStore();
      addTearDown(store.close);
      final synthesizer = _FakeSynthesizer();
      final voice = VoiceService(
        store: store,
        synthesizer: synthesizer,
        maxSpokenCharacters: 120,
      );
      final conversation = await store.createConversation();
      final user = await store.append(
        conversation.id,
        const PendingChatEntry(
          kind: ChatEntryKind.userMessage,
          status: ChatEntryStatus.submitted,
          content: 'Hello',
          correlationId: 'c-1',
          source: ChatEntrySource.user,
        ),
      );
      final reply = await store.append(
        conversation.id,
        PendingChatEntry(
          kind: ChatEntryKind.assistantMessage,
          status: ChatEntryStatus.completed,
          content:
              '## Summary\n\n**Done.** See [the guide](https://example.com).\n'
              '```dart\nvoid main() {}\n```\n- Run `make check`.\n'
              '${'More detail follows here. ' * 6}',
          correlationId: 'c-1',
          source: ChatEntrySource.model,
        ),
      );

      final speech = await voice.speak(
        conversationId: conversation.id,
        entryId: reply.entryId,
      );

      expect(
        synthesizer.spoken.single,
        startsWith(
          'Summary Done. See the guide. Code is shown in the conversation. '
          'Run make check.',
        ),
      );
      expect(
        synthesizer.spoken.single,
        endsWith('The full reply is in the conversation.'),
      );
      expect(speech.truncated, isTrue);
      expect(speech.mimeType, 'audio/wav');
      expect(speech.engine, 'fake voice on this host');
      expect(speech.bytes, [1, 2, 3]);
      await expectLater(
        voice.speak(conversationId: conversation.id, entryId: user.entryId),
        throwsA(isA<SpeechException>()),
      );
      await expectLater(
        voice.speak(conversationId: conversation.id, entryId: 'missing'),
        throwsA(isA<SpeechException>()),
      );
      expect(voice.privacyNotice, contains('fake voice on this host'));
      expect(voice.privacyNotice, isNot(contains('transcribed')));
    });
  });

  group('speech helpers', () {
    test('measures PCM WAV level and ignores other formats', () {
      expect(wavRmsLevel(_tone(amplitude: 0)), 0);
      expect(wavRmsLevel(_tone(amplitude: 0.5)), closeTo(0.354, 0.01));
      expect(wavRmsLevel(Uint8List.fromList('fLaC'.codeUnits)), isNull);
    });

    test('keeps short replies and snake_case identifiers intact', () {
      final spoken = spokenText(
        'Use read_file on `lib/main.dart`.',
        maxCharacters: 200,
      );

      expect(spoken.text, 'Use read_file on lib/main.dart.');
      expect(spoken.truncated, isFalse);
    });

    test('normalizes MIME aliases', () {
      expect(normalizeAudioMimeType('Audio/Wave'), 'audio/wav');
      expect(normalizeAudioMimeType('audio/mp3'), 'audio/mpeg');
      expect(normalizeAudioMimeType('audio/x-flac'), 'audio/flac');
    });
  });

  group('WhisperCppTranscriber', () {
    test('runs whisper-cli on a private copy that is then deleted', () async {
      late String inputPath;
      late List<String> arguments;
      final transcriber = WhisperCppTranscriber(
        modelPath: '/models/ggml-base.bin',
        language: 'en',
        runner:
            (
              executable,
              args, {
              required workingDirectory,
              cancellationToken,
            }) async {
              expect(executable, 'whisper-cli');
              arguments = args;
              inputPath = args[args.indexOf('--file') + 1];
              expect(File(inputPath).readAsBytesSync(), [1, 2, 3]);
              expect(File(inputPath).parent.path, workingDirectory);
              return const SpeechCommandResult(
                exitCode: 0,
                stdout: ' Hello there.\n',
              );
            },
      );

      final transcript = await transcriber.transcribe(
        SpeechAudio(
          bytes: Uint8List.fromList([1, 2, 3]),
          mimeType: 'audio/flac',
        ),
      );

      expect(transcript.text, ' Hello there.\n');
      expect(transcript.engine, 'whisper.cpp (ggml-base.bin) on this host');
      expect(arguments, [
        '--model',
        '/models/ggml-base.bin',
        '--file',
        inputPath,
        '--language',
        'en',
        '--no-timestamps',
        '--no-prints',
      ]);
      expect(inputPath, endsWith('input.flac'));
      expect(File(inputPath).parent.existsSync(), isFalse);
    });

    test('reports failures and timeouts without raw output', () async {
      for (final result in const [
        SpeechCommandResult(exitCode: 3, stdout: 'secret'),
        SpeechCommandResult(exitCode: -9, stdout: '', timedOut: true),
      ]) {
        final transcriber = WhisperCppTranscriber(
          modelPath: 'model.bin',
          runner:
              (_, _, {required workingDirectory, cancellationToken}) async =>
                  result,
        );
        await expectLater(
          transcriber.transcribe(
            SpeechAudio(bytes: _tone(), mimeType: 'audio/wav'),
          ),
          throwsA(
            isA<SpeechException>().having(
              (error) => error.message,
              'message',
              isNot(contains('secret')),
            ),
          ),
        );
      }
    });

    test('rejects unsafe language codes', () {
      expect(
        () => WhisperCppTranscriber(modelPath: 'model.bin', language: '-x'),
        throwsArgumentError,
      );
    });
  });

  group('MacOsSpeechSynthesizer', () {
    test('writes text to a file and returns the generated WAV', () async {
      late List<String> arguments;
      final synthesizer = MacOsSpeechSynthesizer(
        voice: 'Samantha',
        runner:
            (
              executable,
              args, {
              required workingDirectory,
              cancellationToken,
            }) async {
              expect(executable, '/usr/bin/say');
              arguments = args;
              final input = args[args.indexOf('--input-file') + 1];
              expect(File(input).readAsStringSync(), '-Starts with a dash');
              File(
                args[args.indexOf('--output-file') + 1],
              ).writeAsBytesSync([9, 8, 7]);
              return const SpeechCommandResult(exitCode: 0, stdout: '');
            },
      );

      final speech = await synthesizer.synthesize('-Starts with a dash');

      expect(speech.bytes, [9, 8, 7]);
      expect(speech.mimeType, 'audio/wav');
      expect(speech.engine, 'macOS say (Samantha) on this host');
      expect(arguments.take(2), ['--voice', 'Samantha']);
      expect(arguments, contains('--data-format=LEI16@22050'));
    });

    test('fails when say produces no file', () async {
      final synthesizer = MacOsSpeechSynthesizer(
        runner: (_, _, {required workingDirectory, cancellationToken}) async =>
            const SpeechCommandResult(exitCode: 0, stdout: ''),
      );

      await expectLater(
        synthesizer.synthesize('Hello'),
        throwsA(isA<SpeechException>()),
      );
    });

    test('rejects option-like voice names', () {
      expect(
        () => MacOsSpeechSynthesizer(voice: '--output-file=/tmp/x'),
        throwsArgumentError,
      );
    });
  });

  test('reports a missing speech executable clearly', () async {
    await expectLater(
      runSpeechCommand(
        'dextero-missing-speech-engine',
        const [],
        workingDirectory: Directory.systemTemp.path,
      ),
      throwsA(
        isA<SpeechException>().having(
          (error) => error.message,
          'message',
          'dextero-missing-speech-engine is not installed on this host.',
        ),
      ),
    );
  });

  group('SpeechRuntimeConfiguration', () {
    test('keeps voice input off without a whisper model', () {
      final configuration = SpeechRuntimeConfiguration.fromEnvironment(
        const {},
        isMacOS: false,
      );

      expect(configuration.transcriber, isNull);
      expect(configuration.synthesizer, isNull);
    });

    test('configures whisper.cpp and macOS speech output', () {
      final configuration = SpeechRuntimeConfiguration.fromEnvironment(
        const {
          'DEXTERO_WHISPER_MODEL': '/models/ggml-base.bin',
          'DEXTERO_WHISPER_CLI': '/opt/bin/whisper-cli',
          'DEXTERO_WHISPER_LANGUAGE': 'EN',
          'DEXTERO_SPEECH_VOICE': 'Samantha',
        },
        isMacOS: true,
        fileExists: (path) => path == '/models/ggml-base.bin',
      );

      final transcriber = configuration.transcriber! as WhisperCppTranscriber;
      expect(transcriber.executable, '/opt/bin/whisper-cli');
      expect(transcriber.language, 'en');
      expect(
        configuration.synthesizer!.engine,
        'macOS say (Samantha) on this host',
      );
    });

    test('rejects missing models and unsupported speech output', () {
      expect(
        () => SpeechRuntimeConfiguration.fromEnvironment(const {
          'DEXTERO_WHISPER_MODEL': '/missing.bin',
        }, fileExists: (_) => false),
        throwsStateError,
      );
      expect(
        () => SpeechRuntimeConfiguration.fromEnvironment(const {
          'DEXTERO_SPEECH_OUTPUT': 'say',
        }, isMacOS: false),
        throwsStateError,
      );
      expect(
        () => SpeechRuntimeConfiguration.fromEnvironment(const {
          'DEXTERO_SPEECH_OUTPUT': 'cloud',
        }, isMacOS: true),
        throwsArgumentError,
      );
      expect(
        SpeechRuntimeConfiguration.fromEnvironment(const {
          'DEXTERO_SPEECH_OUTPUT': 'off',
        }, isMacOS: true).synthesizer,
        isNull,
      );
    });
  });

  final liveModel = Platform.environment['DEXTERO_WHISPER_MODEL'] ?? '';
  test(
    'transcribes macOS speech with the configured local whisper model',
    () async {
      final speech = await MacOsSpeechSynthesizer().synthesize(
        'What files are in this workspace?',
      );
      final store = InMemoryChatHistoryStore();
      addTearDown(store.close);
      final voice = VoiceService(
        store: store,
        transcriber: WhisperCppTranscriber(modelPath: liveModel),
      );

      final transcript = await voice.transcribe(
        SpeechAudio(bytes: speech.bytes, mimeType: speech.mimeType),
      );

      expect(transcript.text.toLowerCase(), contains('workspace'));
    },
    skip: liveModel.isEmpty || !Platform.isMacOS
        ? 'Set DEXTERO_WHISPER_MODEL on macOS to run the live speech check.'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

/// One-second-per-unit 16 kHz mono PCM WAV containing a 440 Hz tone.
Uint8List _tone({double seconds = 1, double amplitude = 0.5}) {
  const sampleRate = 16000;
  final samples = (sampleRate * seconds).round();
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
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  data.setUint32(40, samples * 2, Endian.little);
  for (var index = 0; index < samples; index++) {
    final value = sin(2 * pi * 440 * index / sampleRate) * amplitude * 32767;
    data.setInt16(44 + index * 2, value.round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

final class _FakeTranscriber implements SpeechTranscriber {
  _FakeTranscriber(this.text);

  String text;
  final received = <SpeechAudio>[];

  @override
  String get engine => 'fake engine on this host';

  @override
  Set<String> get supportedMimeTypes => const {'audio/wav'};

  @override
  Future<SpeechTranscript> transcribe(
    SpeechAudio audio, {
    CancellationToken? cancellationToken,
  }) async {
    received.add(audio);
    return SpeechTranscript(text: text, engine: engine);
  }
}

final class _FakeSynthesizer implements SpeechSynthesizer {
  final spoken = <String>[];

  @override
  String get engine => 'fake voice on this host';

  @override
  Future<SynthesizedSpeech> synthesize(
    String text, {
    CancellationToken? cancellationToken,
  }) async {
    spoken.add(text);
    return SynthesizedSpeech(
      bytes: Uint8List.fromList([1, 2, 3]),
      mimeType: 'audio/wav',
      engine: engine,
    );
  }
}
