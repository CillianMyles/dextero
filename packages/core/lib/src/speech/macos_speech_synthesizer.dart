import 'dart:io';

import '../cancellation.dart';
import '../speech.dart';
import 'speech_command.dart';

/// Speaks replies on this host with the macOS `say` command.
final class MacOsSpeechSynthesizer implements SpeechSynthesizer {
  MacOsSpeechSynthesizer({
    this.executable = '/usr/bin/say',
    this.voice,
    SpeechCommandRunner? runner,
  }) : _runner = runner ?? runSpeechCommand {
    if (voice case final voice?
        when !RegExp(r'^[a-zA-Z0-9 ()._-]{1,64}$').hasMatch(voice)) {
      throw ArgumentError.value(voice, 'voice', 'must be a macOS voice name');
    }
  }

  final String executable;
  final String? voice;
  final SpeechCommandRunner _runner;

  @override
  String get engine => voice == null
      ? 'macOS say on this host'
      : 'macOS say ($voice) on this host';

  @override
  Future<SynthesizedSpeech> synthesize(
    String text, {
    CancellationToken? cancellationToken,
  }) => withSpeechWorkspace((directory) async {
    final separator = Platform.pathSeparator;
    final input = File('${directory.path}${separator}reply.txt');
    final output = File('${directory.path}${separator}reply.wav');
    await input.writeAsString(text, flush: true);
    final result = await _runner(
      executable,
      [
        if (voice case final voice?) ...['--voice', voice],
        '--input-file',
        input.path,
        '--output-file',
        output.path,
        '--file-format=WAVE',
        '--data-format=LEI16@22050',
      ],
      workingDirectory: directory.path,
      cancellationToken: cancellationToken,
    );
    if (result.timedOut) {
      throw const SpeechException('Speech synthesis timed out.');
    }
    if (result.exitCode != 0 || !await output.exists()) {
      throw SpeechException(
        'Speech synthesis failed: say exited with ${result.exitCode}.',
      );
    }
    return SynthesizedSpeech(
      bytes: await output.readAsBytes(),
      mimeType: 'audio/wav',
      engine: engine,
    );
  });
}
