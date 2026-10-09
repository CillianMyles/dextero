import 'dart:io';

import '../cancellation.dart';
import '../speech.dart';
import 'speech_command.dart';

/// Transcribes audio on this host with the whisper.cpp command-line tool.
final class WhisperCppTranscriber implements SpeechTranscriber {
  WhisperCppTranscriber({
    required this.modelPath,
    this.executable = 'whisper-cli',
    this.language = 'auto',
    SpeechCommandRunner? runner,
  }) : _runner = runner ?? runSpeechCommand {
    if (modelPath.trim().isEmpty) {
      throw ArgumentError.value(modelPath, 'modelPath', 'must not be empty');
    }
    if (!RegExp(r'^(auto|[a-z]{2,3})$').hasMatch(language)) {
      throw ArgumentError.value(
        language,
        'language',
        'must be auto or a two- or three-letter language code',
      );
    }
  }

  final String modelPath;
  final String executable;
  final String language;
  final SpeechCommandRunner _runner;

  @override
  String get engine =>
      'whisper.cpp (${modelPath.split(RegExp(r'[/\\]')).last}) on this host';

  @override
  Set<String> get supportedMimeTypes => const {
    'audio/wav',
    'audio/mpeg',
    'audio/flac',
  };

  @override
  Future<SpeechTranscript> transcribe(
    SpeechAudio audio, {
    CancellationToken? cancellationToken,
  }) => withSpeechWorkspace((directory) async {
    final extension = switch (audio.mimeType) {
      'audio/mpeg' => 'mp3',
      'audio/flac' => 'flac',
      _ => 'wav',
    };
    final input = File(
      '${directory.path}${Platform.pathSeparator}input.$extension',
    );
    await input.writeAsBytes(audio.bytes, flush: true);
    final result = await _runner(
      executable,
      [
        '--model',
        modelPath,
        '--file',
        input.path,
        '--language',
        language,
        '--no-timestamps',
        '--no-prints',
      ],
      workingDirectory: directory.path,
      cancellationToken: cancellationToken,
    );
    if (result.timedOut) {
      throw const SpeechException('Transcription timed out.');
    }
    if (result.exitCode != 0) {
      throw SpeechException(
        'Transcription failed: whisper.cpp exited with ${result.exitCode}.',
      );
    }
    return SpeechTranscript(text: result.stdout, engine: engine);
  });
}
