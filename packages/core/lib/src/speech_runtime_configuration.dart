import 'dart:io';

import 'chat_history.dart';
import 'speech.dart';
import 'speech/macos_speech_synthesizer.dart';
import 'speech/whisper_cpp_transcriber.dart';

/// Resolves host-side speech engines from explicit environment data.
///
/// Voice input is off unless `DEXTERO_WHISPER_MODEL` names a whisper.cpp
/// model. Spoken replies default to `say` on macOS and are off elsewhere.
final class SpeechRuntimeConfiguration {
  const SpeechRuntimeConfiguration._({this.transcriber, this.synthesizer});

  factory SpeechRuntimeConfiguration.fromEnvironment(
    Map<String, String> environment, {
    bool? isMacOS,
    bool Function(String path)? fileExists,
  }) {
    final modelPath = _nonEmpty(environment['DEXTERO_WHISPER_MODEL']);
    SpeechTranscriber? transcriber;
    if (modelPath != null) {
      if (!(fileExists ?? (path) => File(path).existsSync())(modelPath)) {
        throw StateError(
          'DEXTERO_WHISPER_MODEL does not name an existing whisper.cpp '
          'model file.',
        );
      }
      transcriber = WhisperCppTranscriber(
        modelPath: modelPath,
        executable:
            _nonEmpty(environment['DEXTERO_WHISPER_CLI']) ?? 'whisper-cli',
        language:
            _nonEmpty(environment['DEXTERO_WHISPER_LANGUAGE'])?.toLowerCase() ??
            'auto',
      );
    }
    final macOS = isMacOS ?? Platform.isMacOS;
    final output = _nonEmpty(
      environment['DEXTERO_SPEECH_OUTPUT'],
    )?.toLowerCase();
    final voice = _nonEmpty(environment['DEXTERO_SPEECH_VOICE']);
    final synthesizer = switch (output) {
      null when macOS => MacOsSpeechSynthesizer(voice: voice),
      null || 'off' => null,
      'say' when macOS => MacOsSpeechSynthesizer(voice: voice),
      'say' => throw StateError('DEXTERO_SPEECH_OUTPUT=say requires macOS.'),
      _ => throw ArgumentError.value(
        output,
        'DEXTERO_SPEECH_OUTPUT',
        'must be say or off',
      ),
    };
    return SpeechRuntimeConfiguration._(
      transcriber: transcriber,
      synthesizer: synthesizer,
    );
  }

  final SpeechTranscriber? transcriber;
  final SpeechSynthesizer? synthesizer;

  VoiceService createService(ChatHistoryStore store) => VoiceService(
    store: store,
    transcriber: transcriber,
    synthesizer: synthesizer,
  );

  static String? _nonEmpty(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }
}
