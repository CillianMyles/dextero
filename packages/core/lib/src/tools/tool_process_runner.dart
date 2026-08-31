import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../tool.dart';

/// Runs a process with bounded, separate stdout and stderr capture.
final class ToolProcessRunner {
  ToolProcessRunner({
    required String workingDirectory,
    this.timeout = const Duration(seconds: 30),
    this.maxOutputBytes = 1024 * 1024,
  }) : workingDirectory = Directory(workingDirectory).absolute.path {
    if (timeout <= Duration.zero || timeout > const Duration(minutes: 5)) {
      throw ArgumentError.value(
        timeout,
        'timeout',
        'must be greater than zero and at most five minutes',
      );
    }
    if (maxOutputBytes < 1 || maxOutputBytes > 10 * 1024 * 1024) {
      throw ArgumentError.value(
        maxOutputBytes,
        'maxOutputBytes',
        'must be from 1 byte to 10 MiB',
      );
    }
  }

  final String workingDirectory;
  final Duration timeout;
  final int maxOutputBytes;

  Future<JsonMap> run(String command, List<String> arguments) async {
    final process = await Process.start(
      command,
      arguments,
      workingDirectory: workingDirectory,
      runInShell: false,
    );
    final stdoutFuture = _capture(process.stdout);
    final stderrFuture = _capture(process.stderr);
    final timer = Timer(timeout, process.kill);

    final exitCode = await process.exitCode;
    timer.cancel();
    final stdout = await stdoutFuture;
    final stderr = await stderrFuture;
    return {
      'exit_code': exitCode,
      'stdout': stdout.text,
      'stderr': stderr.text,
      'truncated': stdout.truncated || stderr.truncated,
    };
  }

  Future<_CapturedOutput> _capture(Stream<List<int>> stream) async {
    final bytes = BytesBuilder(copy: false);
    var remaining = maxOutputBytes;
    var truncated = false;
    await for (final chunk in stream) {
      if (chunk.length <= remaining) {
        bytes.add(chunk);
        remaining -= chunk.length;
      } else {
        if (remaining > 0) bytes.add(chunk.sublist(0, remaining));
        remaining = 0;
        truncated = true;
      }
    }
    return _CapturedOutput(
      utf8.decode(bytes.takeBytes(), allowMalformed: true),
      truncated,
    );
  }
}

final class _CapturedOutput {
  const _CapturedOutput(this.text, this.truncated);

  final String text;
  final bool truncated;
}
