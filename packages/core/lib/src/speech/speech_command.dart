import 'dart:io';

import '../cancellation.dart';
import '../speech.dart';
import '../tools/tool_process_runner.dart';

final class SpeechCommandResult {
  const SpeechCommandResult({
    required this.exitCode,
    required this.stdout,
    this.timedOut = false,
  });

  final int exitCode;
  final String stdout;
  final bool timedOut;
}

/// Runs one local speech-engine process inside [workingDirectory].
typedef SpeechCommandRunner =
    Future<SpeechCommandResult> Function(
      String executable,
      List<String> arguments, {
      required String workingDirectory,
      CancellationToken? cancellationToken,
    });

/// Runs without a shell, with a filtered environment, timeout, and output cap.
Future<SpeechCommandResult> runSpeechCommand(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  CancellationToken? cancellationToken,
}) async {
  try {
    final result = await ToolProcessRunner(
      workingDirectory: workingDirectory,
      timeout: const Duration(minutes: 2),
      maxOutputBytes: 256 * 1024,
    ).run(executable, arguments, cancellationToken: cancellationToken);
    return SpeechCommandResult(
      exitCode: result['exit_code']! as int,
      stdout: result['stdout']! as String,
      timedOut: result['timed_out'] == true,
    );
  } on ProcessException {
    throw SpeechException('$executable is not installed on this host.');
  }
}

/// Runs [action] in a private temporary directory that is always deleted.
Future<T> withSpeechWorkspace<T>(
  Future<T> Function(Directory directory) action,
) async {
  final directory = await Directory.systemTemp.createTemp('dextero-voice-');
  try {
    return await action(directory);
  } finally {
    await directory.delete(recursive: true);
  }
}
